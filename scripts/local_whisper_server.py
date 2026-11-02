"""TalkMate local Whisper ASR — OpenAI-compatible transcription server.

POST /v1/audio/transcriptions  (multipart: file, optional model/language)
GET  /health
GET  /v1/models

Default: http://127.0.0.1:8787/v1
"""
from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, File, Form, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

MODEL_SIZE = os.environ.get("TALKMATE_WHISPER_MODEL", "small")
DEVICE = os.environ.get("TALKMATE_WHISPER_DEVICE", "auto")
COMPUTE = os.environ.get("TALKMATE_WHISPER_COMPUTE", "int8")
# Default loopback only. Set TALKMATE_HOST=0.0.0.0 explicitly to expose on LAN.
DEFAULT_HOST = os.environ.get("TALKMATE_HOST", "127.0.0.1")

# App origins: loopback + RFC1918 LAN (same ports as the App page). No wildcard.
ALLOWED_ORIGIN_RE = (
    r"https?://(127\.0\.0\.1|localhost|10\.\d+\.\d+\.\d+"
    r"|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|192\.168\.\d+\.\d+)(:\d+)?"
)
# ~25 MB audio cap — larger uploads get 413 before transcribe.

app = FastAPI(title="TalkMate Local Whisper")
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
    import re

    from fastapi.responses import Response

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
        # CORS only hides the response; a cross-site POST still reaches the model.
        return JSONResponse(status_code=403, content={"error": "origin not allowed"})
    response = await call_next(request)
    if allowed:
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Vary"] = "Origin"
    response.headers["Access-Control-Allow-Private-Network"] = "true"
    return response


_model = None
_model_error: Optional[str] = None


def model_dir() -> Path:
    return Path(__file__).resolve().parent / "models"


def resolve_model_ref() -> str:
    """Prefer bundled weights under scripts/models/ so offline package works."""
    env = os.environ.get("TALKMATE_WHISPER_PATH")
    if env and Path(env).exists():
        return env
    bundled = model_dir() / "faster-whisper-small"
    if bundled.exists() and any(bundled.glob("*")):
        return str(bundled)
    return MODEL_SIZE


def get_model():
    global _model, _model_error
    if _model is not None:
        return _model
    try:
        from faster_whisper import WhisperModel

        ref = resolve_model_ref()
        _model = WhisperModel(ref, device=DEVICE, compute_type=COMPUTE)
        _model_error = None
    except Exception as exc:  # noqa: BLE001
        _model_error = str(exc)
        raise
    return _model


class Health(BaseModel):
    ok: bool
    service: str = "whisper"
    model_size: str = MODEL_SIZE
    detail: str = ""


@app.get("/health")
def health() -> Health:
    detail = "ready"
    ok = True
    try:
        get_model()
    except Exception as exc:  # noqa: BLE001
        ok = False
        detail = f"model not loaded: {exc}"
    return Health(ok=ok, detail=detail)


@app.get("/v1/models")
def models():
    return {
        "object": "list",
        "data": [
            {
                "id": "whisper-1",
                "object": "model",
                "owned_by": "talkmate-local",
                "model_size": MODEL_SIZE,
            }
        ],
    }


@app.post("/v1/audio/transcriptions")
def transcriptions(
    file: UploadFile = File(...),
    model: str = Form("whisper-1"),
    language: str = Form("en"),
    response_format: str = Form("json"),
):
    from fastapi.responses import JSONResponse

    try:
        model_obj = get_model()
    except Exception as exc:  # noqa: BLE001
        return JSONResponse(status_code=500, content={"error": f"model load failed: {exc}"})

    suffix = os.path.splitext(file.filename or "audio.wav")[1] or ".wav"
    tmp_path = None
    raw = b""
    try:
        # Sync endpoint runs in FastAPI's threadpool, so blocking file reads and
        # transcription no longer stall the event loop (and /health) mid-request.
        raw = file.file.read()
        if raw and len(raw) > 25 * 1024 * 1024:
            return JSONResponse(status_code=413, content={"error": "audio too large (max 25 MB)"})
        if not raw or len(raw) < 64:
            return JSONResponse(status_code=400, content={"error": "audio too small/empty"})
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(raw)
            tmp_path = tmp.name
        lang = (language or "").strip() or None
        segments, _info = model_obj.transcribe(
            tmp_path,
            language=lang or "en",
            beam_size=5,
            vad_filter=True,
            condition_on_previous_text=False,
            initial_prompt="The following is clear spoken English.",
        )
        text = " ".join(seg.text.strip() for seg in segments if seg.text).strip()
        return {"text": text, "model": model or "whisper-1", "language": lang or "auto"}
    except Exception as exc:  # noqa: BLE001
        return JSONResponse(
            status_code=400,
            content={"error": f"transcribe failed ({suffix}): {exc}", "bytes": len(raw) if raw else 0},
        )
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


if __name__ == "__main__":
    import uvicorn

    host = os.environ.get("TALKMATE_HOST", "127.0.0.1")
    port = int(os.environ.get("TALKMATE_WHISPER_PORT", "8787"))
    print(f"TalkMate Whisper -> http://{host}:{port}/v1  model={MODEL_SIZE}")
    try:
        get_model()
        print("Whisper model preloaded: ready", flush=True)
    except Exception as exc:  # noqa: BLE001
        print(f"Whisper preload deferred (will retry on /health): {exc}", flush=True)
    uvicorn.run(app, host=host, port=port, log_level="info")
