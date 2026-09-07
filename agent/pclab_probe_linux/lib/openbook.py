"""Open Book payload — sysfs/hwmon planes (no Ring0 MMIO on Linux)."""
from __future__ import annotations

import glob
import os
from typing import Any

from common import elevated, read_text, utc_now


def _pcie_links(devices: dict[str, Any], telemetry: dict[str, Any]) -> dict[str, Any]:
    links = []
    warnings = []
    for g in (telemetry.get("gpu") or {}).get("gpus") or []:
        row = {
            "device": g.get("name"),
            "role": "gpu",
            "pci_bdf": g.get("pci_bus_id"),
            "gen_current": None,
            "gen_max": None,
            "width_current": None,
            "width_max": None,
            "source": "nvidia-smi" if g.get("vendor") == "nvidia" else "sysfs",
            "confidence": "inventory",
            "note": "PCIe gen/width requires sysfs current_link_* when available",
        }
        bdf = g.get("pci_bus_id")
        if bdf:
            # nvidia-smi bus id like 00000000:01:00.0
            sys_path = f"/sys/bus/pci/devices/{bdf}"
            if not os.path.isdir(sys_path):
                # try lowercase / shortened
                for cand in glob.glob("/sys/bus/pci/devices/*"):
                    if cand.endswith(bdf.split(":")[-1]) or bdf.lower() in cand.lower():
                        sys_path = cand
                        break
            cur = read_text(os.path.join(sys_path, "current_link_speed"), "")
            max_s = read_text(os.path.join(sys_path, "max_link_speed"), "")
            cur_w = read_text(os.path.join(sys_path, "current_link_width"), "")
            max_w = read_text(os.path.join(sys_path, "max_link_width"), "")
            if cur:
                row["gen_current"] = cur
                row["source"] = "sysfs_pcie"
                row["confidence"] = "measured"
            if max_s:
                row["gen_max"] = max_s
            if cur_w:
                try:
                    row["width_current"] = int(cur_w.replace("x", ""))
                except Exception:
                    row["width_current"] = cur_w
            if max_w:
                try:
                    row["width_max"] = int(max_w.replace("x", ""))
                except Exception:
                    row["width_max"] = max_w
            if row.get("width_max") and row.get("width_current") and row["width_current"] < row["width_max"]:
                msg = f"GPU {g.get('name')} running x{row['width_current']} / max x{row['width_max']}"
                row["warning"] = msg
                warnings.append(msg)
        links.append(row)

    for d in devices.get("pci") or []:
        name = (d.get("name") or "").lower()
        if "nvme" in name or d.get("category") == "storage":
            links.append(
                {
                    "device": d.get("name"),
                    "role": "storage",
                    "instance_id": d.get("instance_id"),
                    "source": "sysfs_pci",
                    "confidence": "inventory",
                    "note": "NVMe link speed from sysfs when current_link_* present",
                }
            )
    return {"links": links, "warnings": list(dict.fromkeys(warnings)), "count": len(links)}


def _hwmon_catalog(telemetry: dict[str, Any]) -> dict[str, Any]:
    rows = []
    for s in telemetry.get("sensors_flat") or []:
        rows.append(
            {
                "name": s.get("name"),
                "value": s.get("value"),
                "unit": s.get("unit") or "°C",
                "source": s.get("source") or "hwmon",
                "raw_hex": None,
                "pci_bdf": None,
                "confidence": s.get("confidence") or "measured",
                "hardware": s.get("hardware"),
                "hardware_type": s.get("hardware_type") or "hwmon",
                "open_book": True,
            }
        )
    note = None
    if not rows:
        note = "No hwmon sensors this sample. Load kernel modules or run as root for more chips."
    return {
        "available": len(rows) > 0,
        "count": len(rows),
        "sensors": rows,
        "open_book_therm": len(rows) > 0,
        "open_book_vram": False,
        "elevated": elevated(),
        "note": note
        or "Linux Open Book = hwmon/sysfs (no Ring0 BAR0 MMIO). Windows probe has deeper GPU register planes.",
    }


def openbook_payload(devices: dict[str, Any], telemetry: dict[str, Any]) -> dict[str, Any]:
    catalog = _hwmon_catalog(telemetry)
    pcie = _pcie_links(devices, telemetry)
    platform = devices.get("platform")
    fingerprint = devices.get("fingerprint")

    provenance: dict[str, int] = {}
    for s in catalog.get("sensors") or []:
        tag = str(s.get("source") or "")
        if tag:
            provenance[tag] = provenance.get(tag, 0) + 1
    if platform:
        for plane in ("smbios", "uefi", "tpm", "me_psp", "acpi", "storage", "pci_config", "ec_board"):
            provenance[f"platform_{plane}"] = 1
    provenance["linux_sysfs"] = 1
    provenance["linux_no_ring0"] = 1

    dossier = {
        "schema": "pclab-silicon-dossier-linux-v1",
        "platform": platform,
        "fingerprint": fingerprint,
        "limits": {
            "ring0_mmio": False,
            "pci_config_dump": False,
            "note": "Honest Linux limit: no Ring0 MMIO open-book; DMI/sysfs/hwmon/efivarfs only",
        },
        "collected_at": utc_now(),
    }

    return {
        "open_book": catalog,
        "register_catalog": {
            "version": 0,
            "register_count": 0,
            "provenance_tags": ["hwmon", "sysfs_dmi", "efivarfs", "tpm_sysfs"],
        },
        "pcie": pcie,
        "dossier": dossier,
        "platform": platform,
        "fingerprint": fingerprint,
        "thermal": telemetry.get("thermal"),
        "provenance_counts": provenance,
        "provenance_total": len(provenance),
        "platform_os": "linux",
        "collected_at": utc_now(),
    }
