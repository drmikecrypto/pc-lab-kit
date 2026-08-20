"""Shared helpers for Linux probe."""
from __future__ import annotations

import hashlib
import json
import os
import time
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


def chassis_is_laptop(chassis_type: str | int | None) -> bool:
    try:
        code = int(str(chassis_type).strip() or "0")
    except Exception:
        return False
    return code in {8, 9, 10, 11, 12, 14, 30, 31, 32}
