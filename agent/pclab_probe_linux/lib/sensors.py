"""Sensors / telemetry from hwmon + nvidia-smi."""
from __future__ import annotations

import glob
import os
import subprocess
import time
from typing import Any

from common import elevated, read_int, read_text, utc_now

_HISTORY: list[dict[str, Any]] = []
_HISTORY_MAX = 120


def hwmon_flat() -> list[dict[str, Any]]:
    rows = []
    for hw in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        chip = read_text(os.path.join(hw, "name"), os.path.basename(hw))
        for temp in sorted(glob.glob(os.path.join(hw, "temp*_input"))):
            label_path = temp.replace("_input", "_label")
            label = read_text(label_path, os.path.basename(temp))
            milli = read_int(temp)
            if milli is None:
                continue
            rows.append(
                {
                    "name": f"{chip} {label}",
                    "value": round(milli / 1000.0, 1),
                    "unit": "°C",
                    "hardware": chip,
                    "hardware_type": "hwmon",
                    "source": "hwmon",
                    "confidence": "measured",
                }
            )
        for fan in sorted(glob.glob(os.path.join(hw, "fan*_input"))):
            label_path = fan.replace("_input", "_label")
            label = read_text(label_path, os.path.basename(fan))
            rpm = read_int(fan)
            if rpm is None:
                continue
            rows.append(
                {
                    "name": f"{chip} {label}",
                    "value": rpm,
                    "unit": "RPM",
                    "hardware": chip,
                    "hardware_type": "hwmon",
                    "source": "hwmon",
                    "confidence": "measured",
                }
            )
    return rows


def _nvidia_gpu_temp() -> float | None:
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"],
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=3,
        )
        line = out.strip().splitlines()[0]
        return float(line)
    except Exception:
        return None


def _cpu_package_temp(rows: list[dict[str, Any]]) -> float | None:
    for r in rows:
        n = (r.get("name") or "").lower()
        if r.get("unit") == "°C" and any(k in n for k in ("package", "tctl", "tdie", "cpu", "core")):
            return float(r["value"])
    for r in rows:
        if r.get("unit") == "°C":
            return float(r["value"])
    return None


def telemetry_snapshot() -> dict[str, Any]:
    rows = hwmon_flat()
    cpu_t = _cpu_package_temp(rows)
    gpu_t = _nvidia_gpu_temp()
    return {
        "collected_at": utc_now(),
        "platform": "linux",
        "elevated": elevated(),
        "cpu_temp": cpu_t,
        "gpu_temp": gpu_t,
        "cpu": {
            "thermal": {"package_c": cpu_t, "source": "hwmon"},
            "architecture": _cpu_arch(),
        },
        "gpu": {
            "thermal": {"core_c": gpu_t, "hot_spot_c": None, "source": "nvidia-smi" if gpu_t is not None else None},
            "gpus": _gpu_list(gpu_t),
        },
        "thermal": {
            "cpu": {"package_c": cpu_t},
            "gpu": {"core_c": gpu_t, "hot_spot_c": None},
        },
        "sensors_flat": rows,
        "open_book": {"count": 0, "sensors": [], "available": False},
    }


def _cpu_arch() -> dict[str, Any]:
    model = ""
    cores = 0
    threads = 0
    try:
        with open("/proc/cpuinfo", "r", encoding="utf-8", errors="replace") as fh:
            seen = set()
            for line in fh:
                if line.startswith("model name") and not model:
                    model = line.split(":", 1)[1].strip()
                if line.startswith("processor"):
                    threads += 1
                if line.startswith("core id"):
                    seen.add(line.split(":", 1)[1].strip())
            cores = len(seen) or threads
    except Exception:
        pass
    return {"model": model, "cores": cores, "threads": threads, "vendor_tag": None}


def _gpu_list(temp: float | None) -> list[dict[str, Any]]:
    gpus = []
    try:
        out = subprocess.check_output(
            [
                "nvidia-smi",
                "--query-gpu=name,driver_version,memory.total,pci.bus_id",
                "--format=csv,noheader,nounits",
            ],
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=3,
        )
        for line in out.strip().splitlines():
            parts = [p.strip() for p in line.split(",")]
            if len(parts) >= 1:
                gpus.append(
                    {
                        "name": parts[0],
                        "vendor": "nvidia",
                        "driver": parts[1] if len(parts) > 1 else None,
                        "vbios": None,
                        "pci_bus_id": parts[3] if len(parts) > 3 else None,
                        "thermal": {"core_c": temp, "hotspot_source": None},
                    }
                )
    except Exception:
        pass
    return gpus


def push_history_sample() -> None:
    snap = telemetry_snapshot()
    sample = {
        "t": utc_now(),
        "cpu_temp": snap.get("cpu_temp"),
        "gpu_temp": snap.get("gpu_temp"),
        "ts": time.time(),
    }
    _HISTORY.append(sample)
    while len(_HISTORY) > _HISTORY_MAX:
        _HISTORY.pop(0)


def history_samples() -> list[dict[str, Any]]:
    return list(_HISTORY)
