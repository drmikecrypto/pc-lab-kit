"""Sensors / telemetry from hwmon + nvidia-smi / AMD sysfs (+ optional smartctl)."""
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
    rows: list[dict[str, Any]] = []
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
        for volt in sorted(glob.glob(os.path.join(hw, "in*_input"))):
            label_path = volt.replace("_input", "_label")
            label = read_text(label_path, os.path.basename(volt))
            milli = read_int(volt)
            if milli is None:
                continue
            rows.append(
                {
                    "name": f"{chip} {label}",
                    "value": round(milli / 1000.0, 3),
                    "unit": "V",
                    "hardware": chip,
                    "hardware_type": "hwmon",
                    "source": "hwmon",
                    "confidence": "measured",
                }
            )
        for power in sorted(glob.glob(os.path.join(hw, "power*_input"))):
            label_path = power.replace("_input", "_label")
            label = read_text(label_path, os.path.basename(power))
            microw = read_int(power)
            if microw is None:
                continue
            rows.append(
                {
                    "name": f"{chip} {label}",
                    "value": round(microw / 1_000_000.0, 2),
                    "unit": "W",
                    "hardware": chip,
                    "hardware_type": "hwmon",
                    "source": "hwmon",
                    "confidence": "measured",
                }
            )
        for curr in sorted(glob.glob(os.path.join(hw, "curr*_input"))):
            label_path = curr.replace("_input", "_label")
            label = read_text(label_path, os.path.basename(curr))
            milli = read_int(curr)
            if milli is None:
                continue
            rows.append(
                {
                    "name": f"{chip} {label}",
                    "value": round(milli / 1000.0, 3),
                    "unit": "A",
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


def _amd_gpu_temp() -> float | None:
    """AMDGPU hwmon / sysfs junction when present."""
    for path in sorted(glob.glob("/sys/class/drm/card*/device/hwmon/hwmon*/temp*_input")):
        label = read_text(path.replace("_input", "_label"), "")
        milli = read_int(path)
        if milli is None:
            continue
        if not label or any(k in label.lower() for k in ("edge", "junction", "hotspot", "mem")):
            return round(milli / 1000.0, 1)
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


def _dmi_inventory() -> dict[str, Any]:
    board = {
        "manufacturer": read_text("/sys/class/dmi/id/board_vendor", ""),
        "product": read_text("/sys/class/dmi/id/board_name", ""),
        "version": read_text("/sys/class/dmi/id/board_version", ""),
    }
    bios = {
        "vendor": read_text("/sys/class/dmi/id/bios_vendor", ""),
        "version": read_text("/sys/class/dmi/id/bios_version", ""),
        "date": read_text("/sys/class/dmi/id/bios_date", ""),
    }
    product = {
        "manufacturer": read_text("/sys/class/dmi/id/sys_vendor", ""),
        "name": read_text("/sys/class/dmi/id/product_name", ""),
    }
    return {"board": board, "bios": bios, "system": product, "source": "sysfs_dmi"}


def _smart_snapshot() -> dict[str, Any]:
    """Optional smartctl JSON when installed — honesty: not Ring0."""
    try:
        out = subprocess.check_output(
            ["smartctl", "--scan", "-j"],
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=4,
        )
        return {"available": True, "scan_json": out[:4000], "source": "smartctl"}
    except Exception:
        return {
            "available": False,
            "note": "Install smartctl for SMART depth (optional)",
            "source": None,
        }


def telemetry_snapshot() -> dict[str, Any]:
    rows = hwmon_flat()
    cpu_t = _cpu_package_temp(rows)
    gpu_t = _nvidia_gpu_temp()
    amd_t = _amd_gpu_temp()
    if gpu_t is None:
        gpu_t = amd_t
    gpu_source = "nvidia-smi" if _nvidia_gpu_temp() is not None else ("amdgpu_sysfs" if amd_t is not None else None)
    voltages = [r for r in rows if r.get("unit") == "V"]
    powers = [r for r in rows if r.get("unit") == "W"]
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
            "thermal": {
                "core_c": gpu_t,
                "hot_spot_c": None,
                "source": gpu_source,
            },
            "gpus": _gpu_list(gpu_t),
        },
        "thermal": {
            "cpu": {"package_c": cpu_t},
            "gpu": {"core_c": gpu_t, "hot_spot_c": None},
        },
        "power": {
            "samples": powers[:24],
            "source": "hwmon",
        },
        "voltages": voltages[:32],
        "motherboard": _dmi_inventory(),
        "storage": {"smart": _smart_snapshot()},
        "sensors_flat": rows,
        "sensor_density": {
            "temp_channels": sum(1 for r in rows if r.get("unit") == "°C"),
            "fan_channels": sum(1 for r in rows if r.get("unit") == "RPM"),
            "voltage_channels": len(voltages),
            "power_channels": len(powers),
        },
        "open_book": {"count": 0, "sensors": [], "available": False},
        "honesty": {
            "ring0": False,
            "note": "Linux sensors are hwmon/sysfs + optional nvidia-smi/smartctl — no Ring0 MMIO.",
        },
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
    gpus: list[dict[str, Any]] = []
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
    if not gpus:
        for card in sorted(glob.glob("/sys/class/drm/card*/device")):
            vendor = read_text(os.path.join(card, "vendor"), "")
            device = read_text(os.path.join(card, "device"), "")
            if vendor or device:
                gpus.append(
                    {
                        "name": f"DRM {os.path.basename(os.path.dirname(card))}",
                        "vendor": "amd" if vendor.lower() in ("0x1002", "0x1022") else "pci",
                        "driver": None,
                        "vbios": None,
                        "pci_ids": f"{vendor}:{device}",
                        "thermal": {"core_c": temp, "hotspot_source": "amdgpu_sysfs" if temp is not None else None},
                    }
                )
                break
    return gpus


def push_history_sample() -> None:
    snap = telemetry_snapshot()
    sample = {
        "t": utc_now(),
        "cpu_temp": snap.get("cpu_temp"),
        "gpu_temp": snap.get("gpu_temp"),
        "ts": time.time(),
        "sensor_density": snap.get("sensor_density"),
    }
    _HISTORY.append(sample)
    while len(_HISTORY) > _HISTORY_MAX:
        _HISTORY.pop(0)


def history_samples() -> list[dict[str, Any]]:
    return list(_HISTORY)
