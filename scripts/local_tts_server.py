"""TalkMate local TTS — mid-tier stack.

Engine priority (named):
  1) edge-tts     — Microsoft neural (most natural, needs network)
2) kokoro-onnx  — Kokoro-82M ONNX (fast local, slight synth)
3) pyttsx3      — emergency SAPI
  2) kokoro       — PyTorch Kokoro package (fallback if onnx not present)
  3) edge-tts     — Microsoft neural voices via local proxy (quality, needs network)
  4) pyttsx3      — Windows SAPI offline emergency only

POST /v1/audio/speech  JSON: {input, voice, engine?, speed?}
GET  /health
GET  /v1/voices
GET  /v1/models

Default: http://127.0.0.1:8788/v1
Model dir (kokoro-onnx): scripts/models/  or  $TALKMATE_KOKORO_DIR
"""
from __future__ import annotations

import asyncio
import io
import os
import re
import tempfile
import threading
from pathlib import Path
from typing import Dict, List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel

# TalkMate UI voice ids → Kokoro voice + edge-tts + SAPI approx
VOICE_PRESETS: Dict[str, Dict[str, object]] = {
    "male-elder": {
        "label": "男·老年",
        "kokoro": "am_onyx",
        "edge": "en-GB-RyanNeural",
        "rate": "-18%",
        "pitch": "-8Hz",
        "speed": 0.85,
        "hint": "沉稳偏慢",
        "sapi_gender": "male",
        "sapi_rate": -30,
        "sapi_pitch": -8,
    },
    "male-mid": {
        "label": "男·中年",
        "kokoro": "am_adam",
        "edge": "en-US-GuyNeural",
        "rate": "+0%",
        "pitch": "+0Hz",
        "speed": 0.95,
        "hint": "标准男声",
        "sapi_gender": "male",
        "sapi_rate": 0,
        "sapi_pitch": 0,
    },
    "male-youth": {
        "label": "男·青年",
        "kokoro": "am_michael",
        "edge": "en-US-AndrewNeural",
        "rate": "+4%",
        "pitch": "+2Hz",
        "speed": 1.05,
        "hint": "清朗青年",
        "sapi_gender": "male",
        "sapi_rate": 15,
        "sapi_pitch": 5,
    },
    "male-child": {
        "label": "男·儿童",
        "kokoro": "am_puck",
        "edge": "en-US-BrandonNeural",
        "rate": "+8%",
        "pitch": "+10Hz",
        "speed": 1.08,
        "hint": "童声感（升速升调近似）",
        "sapi_gender": "male",
        "sapi_rate": 20,
        "sapi_pitch": 20,
    },
    "female-elder": {
        "label": "女·老年",
        "kokoro": "af_nova",
        "edge": "en-US-ElizabethNeural",
        "rate": "-16%",
        "pitch": "-6Hz",
        "speed": 0.85,
        "hint": "成熟偏慢",
        "sapi_gender": "female",
        "sapi_rate": -28,
        "sapi_pitch": -6,
    },
    "female-mid": {
        "label": "女·中年",
        "kokoro": "af_nicole",
        "edge": "en-US-AriaNeural",
        "rate": "+0%",
        "pitch": "+0Hz",
        "speed": 0.96,
        "hint": "自然女声",
        "sapi_gender": "female",
        "sapi_rate": 0,
        "sapi_pitch": 0,
    },
    "female-youth": {
        "label": "女·青年",
        "kokoro": "af_bella",
        "edge": "en-US-EmmaNeural",
        "rate": "+4%",
        "pitch": "+2Hz",
        "speed": 1.04,
        "hint": "明快，适合亲子",
        "sapi_gender": "female",
        "sapi_rate": 12,
        "sapi_pitch": 8,
    },
    "female-child": {
        "label": "女·儿童",
        "kokoro": "af_sky",
        "edge": "en-US-AnaNeural",
        "rate": "+0%",
        "pitch": "+0Hz",
        "speed": 1.02,
        "hint": "儿童感女声",
        "sapi_gender": "female",
        "sapi_rate": 5,
        "sapi_pitch": 18,
    },
}

app = FastAPI(title="TalkMate Local TTS (mid-tier)")
# App origins: loopback + RFC1918 LAN. No wildcard.
ALLOWED_ORIGIN_RE = (
    r"https?://(127\.0\.0\.1|localhost|10\.\d+\.\d+\.\d+"
    r"|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|192\.168\.\d+\.\d+)(:\d+)?"
)
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=ALLOWED_ORIGIN_RE,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)


@app.middleware("http")
async def _browser_private_network(request, call_next):
    """Private-Network preflight, Origin echo, and write-request Origin enforcement."""
    origin = request.headers.get("origin", "")
    allowed = bool(origin) and re.fullmatch(ALLOWED_ORIGIN_RE, origin) is not None
    if request.method == "OPTIONS":
        headers = {
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
            "Access-Control-Allow-Private-Network": "true",
            "Access-Control-Max-Age": "86400",
            "Vary": "Origin",
        }
        if allowed:
            headers["Access-Control-Allow-Origin"] = origin
        return Response(status_code=204, headers=headers)
    if request.method not in ("GET", "HEAD") and not allowed:
        # CORS only hides the response; a cross-site POST still reaches the engine.
        return JSONResponse(status_code=403, content={"error": "origin not allowed"})
    response = await call_next(request)
    if allowed:
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Vary"] = "Origin"
    response.headers["Access-Control-Allow-Private-Network"] = "true"
    return response


_synth_lock = threading.Lock()
_kokoro_onnx = None
_kokoro_torch = None
_kokoro_error = ""


def _run_locked(fn, *args):
    """Serialise blocking synthesis engines; must never wrap an await."""
    with _synth_lock:
        return fn(*args)


def _run_offline_tts(text: str, preset_key: str, speed: Optional[float]) -> bytes:
    # pyttsx3 drives SAPI over COM, which worker threads must initialise themselves.
    comtypes = None
    try:
        import comtypes

        comtypes.CoInitialize()
    except Exception:
        comtypes = None
    try:
        return _run_locked(synth_offline, text, preset_key, speed)
    finally:
        if comtypes is not None:
            try:
                comtypes.CoUninitialize()
            except Exception:
                pass


def model_dir() -> Path:
    env = os.environ.get("TALKMATE_KOKORO_DIR")
    if env:
        return Path(env)
    return Path(__file__).resolve().parent / "models"


def kokoro_onnx_paths():
    d = model_dir()
    onnx = d / os.environ.get("TALKMATE_KOKORO_ONNX", "kokoro-v1.0.onnx")
    voices = d / os.environ.get("TALKMATE_KOKORO_VOICES", "voices-v1.0.bin")
    return onnx, voices


def available_engines() -> List[str]:
    engines = []
    onnx, voices = kokoro_onnx_paths()
    try:
        import kokoro_onnx  # noqa: F401

        if onnx.exists() and voices.exists():
            engines.append("kokoro-onnx")
        else:
            # package present but weights missing
            pass
    except Exception:
        pass
    try:
        import kokoro  # noqa: F401

        engines.append("kokoro")
    except Exception:
        pass
    try:
        import edge_tts  # noqa: F401

        engines.append("edge-tts")
    except Exception:
        pass
    try:
        import pyttsx3  # noqa: F401

        engines.append("pyttsx3")
    except Exception:
        pass
    return engines


def _init_kokoro_onnx():
    global _kokoro_onnx, _kokoro_error
    if _kokoro_onnx is not None:
        return _kokoro_onnx
    onnx, voices = kokoro_onnx_paths()
    if not onnx.exists() or not voices.exists():
        raise RuntimeError(f"kokoro weights missing under {model_dir()}")
    from kokoro_onnx import Kokoro

    _kokoro_onnx = Kokoro(str(onnx), str(voices))
    return _kokoro_onnx


class SpeechReq(BaseModel):
    input: str
    voice: str = "female-child"
    model: str = "talkmate-mid"
    response_format: str = "mp3"
    speed: Optional[float] = None
    engine: Optional[str] = None  # auto | kokoro-onnx | kokoro | edge | offline


class Health(BaseModel):
    ok: bool
    service: str = "tts"
    tier: str = "mid"
    engines: List[str] = []
    primary: str = ""
    model_dir: str = ""
    kokoro_onnx: bool = False
    kokoro_voices: bool = False
    detail: str = ""


def normalize_voice_id(name: str) -> str:
    key = (name or "").strip().replace("_", "-")
    if key in VOICE_PRESETS:
        return key
    # raw kokoro voice e.g. af_bella
    return key


@app.get("/health")
def health() -> Health:
    engines = available_engines()
    onnx, voices = kokoro_onnx_paths()
    primary = engines[0] if engines else ""
    ok = bool(engines)
    detail = "ok: " + ", ".join(engines) if engines else "no TTS engine installed"
    return Health(
        ok=ok,
        engines=engines,
        primary=primary,
        model_dir=str(model_dir()),
        kokoro_onnx=onnx.exists(),
        kokoro_voices=voices.exists(),
        detail=detail,
    )


@app.get("/v1/voices")
def voices():
    return {
        "object": "list",
        "data": [
            {
                "id": pid,
                "object": "voice",
                "label": meta["label"],
                "kokoro": meta["kokoro"],
                "engine_voice": meta["edge"],
                "rate": meta["rate"],
                "pitch": meta["pitch"],
                "speed": meta["speed"],
                "hint": meta["hint"],
            }
            for pid, meta in VOICE_PRESETS.items()
        ],
    }


@app.get("/v1/models")
def models():
    return {
        "object": "list",
        "data": [
            {
                "id": "talkmate-mid-tts",
                "object": "model",
                "tier": "mid",
                "engines": available_engines(),
                "presets": list(VOICE_PRESETS),
                "note": "Natural-first: edge-tts then Kokoro-82M ONNX; offline: pyttsx3",
            }
        ],
    }


def _apply_speed(rate: str, speed: Optional[float]) -> str:
    if not speed:
        return rate
    pct = int(round((float(speed) - 1.0) * 100))
    base = 0
    m = re.search(r"([+-]?\d+)%", str(rate or ""))
    if m:
        base = int(m.group(1))
    total = max(-50, min(50, base + pct))
    sign = "+" if total >= 0 else ""
    return f"{sign}{total}%"


def _wav_bytes_from_float32(audio, sample_rate: int) -> bytes:
    import numpy as np
    import wave

    pcm = np.clip(audio, -1.0, 1.0)
    pcm16 = (pcm * 32767.0).astype("<i2")
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(int(sample_rate))
        w.writeframes(pcm16.tobytes())
    return buf.getvalue()


def synth_kokoro_onnx(text: str, preset_key: str, speed: Optional[float]) -> bytes:
    meta = VOICE_PRESETS.get(preset_key)
    voice = meta["kokoro"] if meta else preset_key
    base_speed = float(meta["speed"]) if meta else 1.0
    if speed:
        base_speed = float(speed)
    k = _init_kokoro_onnx()
    # kokoro-onnx create() returns (samples, sample_rate)
    result = k.create(text, voice=voice, speed=base_speed, lang="en-us")
    if isinstance(result, tuple) and len(result) == 2:
        samples, sr = result
    else:
        samples, sr = result, 24000
    data = _wav_bytes_from_float32(samples, sr)
    if not data:
        raise RuntimeError("empty kokoro-onnx audio")
    return data


def synth_kokoro_torch(text: str, preset_key: str, speed: Optional[float]) -> bytes:
    import soundfile as sf

    meta = VOICE_PRESETS.get(preset_key)
    voice = meta["kokoro"] if meta else preset_key
    base_speed = float(meta["speed"]) if meta else 1.0
    if speed:
        base_speed = float(speed)

    from kokoro import KPipeline

    # American English
    pipeline = KPipeline(lang_code="a")
    generator = pipeline(text, voice=voice, speed=base_speed)
    chunks = []
    sr = 24000
    for _gs, _ps, audio in generator:
        chunks.append(audio)
        try:
            sr = int(getattr(audio, "sr", 24000)) or 24000
        except Exception:
            pass
    if not chunks:
        raise RuntimeError("empty kokoro torch audio")
    import numpy as np

    audio = np.concatenate(chunks)
    return _wav_bytes_from_float32(audio, sr)


async def synth_edge(text: str, preset_key: str, speed: Optional[float]) -> bytes:
    import edge_tts

    meta = VOICE_PRESETS.get(preset_key, VOICE_PRESETS["female-child"])
    engine_voice = meta["edge"]
    rate = _apply_speed(str(meta.get("rate", "+0%")), speed)
    pitch = str(meta.get("pitch", "+0Hz"))
    buf = io.BytesIO()
    communicate = edge_tts.Communicate(text, engine_voice, rate=rate, pitch=pitch)
    async for chunk in communicate.stream():
        if chunk["type"] == "audio":
            buf.write(chunk["data"])
    data = buf.getvalue()
    if not data:
        raise RuntimeError("empty audio from edge-tts")
    return data


def synth_offline(text: str, preset_key: str, speed: Optional[float]) -> bytes:
    import pyttsx3

    meta = VOICE_PRESETS.get(preset_key, VOICE_PRESETS["female-child"])
    sapi_rate = int(meta.get("sapi_rate", 0))
    sapi_pitch = int(meta.get("sapi_pitch", 0))
    gender = str(meta.get("sapi_gender", "female"))
    engine = pyttsx3.init()
    try:
        voices = engine.getProperty("voices") or []
        chosen = None
        for v in voices:
            blob = f"{getattr(v,'name','')} {getattr(v,'id','')}".lower()
            if gender == "male" and any(k in blob for k in ("male", "david", "mark", "daniel", "guy")):
                chosen = v
                break
            if gender == "female" and any(k in blob for k in ("female", "zira", "hazel", "aria", "jenny")):
                chosen = v
                break
        if chosen is None and voices:
            chosen = voices[0]
        if chosen is not None:
            engine.setProperty("voice", chosen.id)
        base = engine.getProperty("rate") or 200
        multiplier = float(speed) if speed else 1.0
        engine.setProperty("rate", int(base * multiplier + sapi_rate))
        try:
            engine.setProperty("pitch", max(0, min(100, 50 + sapi_pitch)))
        except Exception:
            pass
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            out_path = tmp.name
        try:
            engine.save_to_file(text, out_path)
            engine.runAndWait()
            data = Path(out_path).read_bytes()
        finally:
            try:
                os.unlink(out_path)
            except OSError:
                pass
        if not data:
            raise RuntimeError("empty pyttsx3 audio")
        return data
    finally:
        try:
            engine.stop()
        except Exception:
            pass


@app.post("/v1/audio/speech")
async def speech(req: SpeechReq):
    text = (req.input or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="input is empty")
    if len(text) > 2000:
        raise HTTPException(status_code=413, detail="input too long (max 2000 chars)")

    preset_key = normalize_voice_id(req.voice)
    engines = available_engines()
    prefer = (req.engine or "auto").lower()
    order = []
    if prefer == "auto":
        order = ["edge-tts", "kokoro-onnx", "kokoro", "pyttsx3"]
    elif prefer in ("kokoro-onnx", "kokoro"):
        order = [prefer]
    elif prefer in ("edge", "edge-tts"):
        order = ["edge-tts"]
    elif prefer in ("offline", "pyttsx3"):
        order = ["pyttsx3"]
    else:
        order = [prefer]

    errors = []
    for eng in order:
        if eng not in engines and prefer == "auto":
            continue
        try:
            if eng == "kokoro-onnx":
                data = await asyncio.to_thread(_run_locked, synth_kokoro_onnx, text, preset_key, req.speed)
                return Response(content=data, media_type="audio/wav", headers={"X-TalkMate-TTS-Engine": "kokoro-onnx"})
            if eng == "kokoro":
                data = await asyncio.to_thread(_run_locked, synth_kokoro_torch, text, preset_key, req.speed)
                return Response(content=data, media_type="audio/wav", headers={"X-TalkMate-TTS-Engine": "kokoro"})
            if eng in ("edge-tts", "edge"):
                # Network-bound: never hold the single-engine lock across an await.
                data = await synth_edge(text, preset_key, req.speed)
                return Response(content=data, media_type="audio/mpeg", headers={"X-TalkMate-TTS-Engine": "edge-tts"})
            if eng == "pyttsx3":
                data = await asyncio.to_thread(_run_offline_tts, text, preset_key, req.speed)
                return Response(content=data, media_type="audio/wav", headers={"X-TalkMate-TTS-Engine": "pyttsx3"})
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{eng}: {exc}")

    raise HTTPException(status_code=500, detail=" | ".join(errors) or "no engine")


if __name__ == "__main__":
    import uvicorn

    # Default loopback only. Set TALKMATE_HOST=0.0.0.0 explicitly to expose on LAN.
    host = os.environ.get("TALKMATE_HOST", "127.0.0.1")
    port = int(os.environ.get("TALKMATE_TTS_PORT", "8788"))
    onnx, voices = kokoro_onnx_paths()
    print(f"TalkMate TTS (mid) -> http://{host}:{port}/v1")
    print(f"  engines={available_engines()}")
    print(f"  kokoro dir={model_dir()} onnx={onnx.exists()} voices={voices.exists()}")
    uvicorn.run(app, host=host, port=port, log_level="info")
