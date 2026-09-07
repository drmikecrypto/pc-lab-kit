"""Shared helpers for Linux probe."""
from __future__ import annotations

import hashlib
import json
import os
import time
import uuid
from typing import Any


def elevated() -> bool:
    try:
        return os.geteuid() == 0
    except Exception:
        return False


def read_text(path: str, default: str = "") -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read().strip()
    except Exception:
        return default


def read_int(path: str, default: int | None = None) -> int | None:
    raw = read_text(path, "")
    if not raw:
        return default
    try:
        return int(raw)
    except Exception:
        return default


def utc_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def sha256_hex(material: str) -> str:
    return hashlib.sha256(material.encode("utf-8", errors="replace")).hexdigest()


def json_bytes(obj: Any) -> bytes:
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"), default=str).encode("utf-8")


def probe_token_path() -> str:
    xdg = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(xdg, "PcLabKit", "Probe", "auth.token")


def load_or_create_probe_token() -> str:
    """Env PCLAB_PROBE_TOKEN or ~/.local/share/PcLabKit/Probe/auth.token (create GUID)."""
    env = (os.environ.get("PCLAB_PROBE_TOKEN") or "").strip()
    if env:
        return env
    path = probe_token_path()
    try:
        if os.path.isfile(path):
            with open(path, "r", encoding="ascii", errors="replace") as fh:
                existing = fh.read().strip()
            if existing:
                return existing
    except Exception:
        pass
    token = uuid.uuid4().hex
    try:
        os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
        with open(path, "w", encoding="ascii") as fh:
            fh.write(token)
        try:
            os.chmod(path, 0o600)
        except Exception:
            pass
    except Exception:
        pass
    return token


def chassis_is_laptop(chassis_type: str | int | None) -> bool:
    try:
        code = int(str(chassis_type).strip() or "0")
    except Exception:
        return False
    return code in {8, 9, 10, 11, 12, 14, 30, 31, 32}
