"""Download Kokoro-82M ONNX weights for TalkMate mid-tier TTS.

Pinned to the immutable GitHub release tag `model-files-v1.0` (NOT the
mutable HuggingFace `resolve/main` branch). Every file is verified against
its expected SHA256 before being moved into place.
"""
from __future__ import annotations

import hashlib
import os
import sys
import urllib.request
from pathlib import Path

RELEASE_TAG = "model-files-v1.0"
BASE = f"https://github.com/thewh1teagle/kokoro-onnx/releases/download/{RELEASE_TAG}"

# name -> (url, sha256 of the release asset)
FILES = {
    "kokoro-v1.0.onnx": (
        f"{BASE}/kokoro-v1.0.onnx",
        "7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5",
    ),
    "voices-v1.0.bin": (
        f"{BASE}/voices-v1.0.bin",
        "bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d",
    ),
}

# 10-minute socket timeout; urlretrieve has no timeout parameter of its own.
TIMEOUT = 600


def dest_dir() -> Path:
    env = os.environ.get("TALKMATE_KOKORO_DIR")
    if env:
        return Path(env)
    return Path(__file__).resolve().parent / "models"


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(4 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url: str, out: Path, expected_sha256: str) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(out.suffix + ".part")
    print(f"GET {url}")
    print(f" -> {out}")

    def hook(blocks: int, bs: int, total: int) -> None:
        if total <= 0:
            return
        done = min(blocks * bs, total)
        pct = done * 100 // total
        if blocks % 20 == 0 or done >= total:
            print(f"\r  {pct:3d}%  {done/1e6:.1f}/{total/1e6:.1f} MB", end="", flush=True)

    try:
        # socket-level default timeout applies to urlretrieve's urlopen calls
        import socket

        old = socket.getdefaulttimeout()
        socket.setdefaulttimeout(TIMEOUT)
        try:
            urllib.request.urlretrieve(url, tmp, reporthook=hook)
        finally:
            socket.setdefaulttimeout(old)
        print()
        actual = sha256_of(tmp)
        if actual.lower() != expected_sha256.lower():
            raise ValueError(f"SHA256 mismatch: got {actual}, want {expected_sha256}")
        if out.exists():
            out.unlink()
        tmp.rename(out)
    except BaseException:
        # never leave a stale .part behind
        try:
            if tmp.exists():
                tmp.unlink()
        except OSError:
            pass
        raise


def main() -> int:
    d = dest_dir()
    d.mkdir(parents=True, exist_ok=True)
    print(f"Kokoro model dir: {d}  (release: {RELEASE_TAG})")
    ok = True
    for name, (url, sha256) in FILES.items():
        target = d / name
        if target.exists() and target.stat().st_size > 1_000_000:
            try:
                if sha256_of(target).lower() == sha256.lower():
                    print(f"SKIP {name} ({target.stat().st_size} bytes, sha256 OK)")
                    continue
                print(f"RE-DOWNLOAD {name}: existing file failed sha256 check")
            except OSError as exc:
                print(f"RE-DOWNLOAD {name}: cannot read existing file ({exc})")
        try:
            download(url, target, sha256)
            print(f"OK {name} {target.stat().st_size} bytes (sha256 OK)")
        except Exception as exc:  # noqa: BLE001
            ok = False
            print(f"ERROR could not download {name}: {exc}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
