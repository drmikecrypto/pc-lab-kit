"""Device inventory — PCI / USB / DRM monitors (Linux sysfs)."""
from __future__ import annotations

import glob
import os
from typing import Any

import platform_intel
import sensors
from common import elevated, read_text, utc_now


def _pci_devices() -> list[dict[str, Any]]:
    out = []
    for path in sorted(glob.glob("/sys/bus/pci/devices/*")):
        vendor = read_text(os.path.join(path, "vendor"), "").replace("0x", "")
        device = read_text(os.path.join(path, "device"), "").replace("0x", "")
        clazz = read_text(os.path.join(path, "class"), "").replace("0x", "")
        driver = ""
        if os.path.islink(os.path.join(path, "driver")):
            driver = os.path.basename(os.path.realpath(os.path.join(path, "driver")))
        # Prefer uevent PRODUCT / MODALIAS for name
        uevent = read_text(os.path.join(path, "uevent"), "")
        name = os.path.basename(path)
        for line in uevent.splitlines():
            if line.startswith("PCI_SLOT_NAME="):
                name = line.split("=", 1)[1]
        label = f"PCI {vendor}:{device}"
        if driver:
            label = f"{driver} ({vendor}:{device})"
        category = "other"
        if clazz.startswith("03"):
            category = "display"
        elif clazz.startswith("02"):
            category = "network"
        elif clazz.startswith("01"):
            category = "storage"
        elif clazz.startswith("0c"):
            category = "serial_bus"
        elif clazz.startswith("04"):
            category = "multimedia"
        needs_driver = not bool(driver)
        out.append(
            {
                "name": label,
                "class": clazz,
                "category": category,
                "status": "OK" if driver else "Unknown",
                "problem_code": 28 if needs_driver else 0,
                "problem_message": "No kernel driver bound" if needs_driver else "",
                "instance_id": os.path.basename(path),
                "manufacturer": "",
                "bus": "pci",
                "vendor_id": vendor,
                "device_id": device,
                "subsystem_id": "",
                "revision": read_text(os.path.join(path, "revision"), "").replace("0x", ""),
                "service": driver,
                "present": True,
                "hidden": False,
                "needs_driver": needs_driver,
                "has_problem": needs_driver,
                "confidence": "measured",
                "source": "sysfs_pci",
            }
        )
    return out


def _usb_tree() -> dict[str, Any]:
    devices = []
    for path in sorted(glob.glob("/sys/bus/usb/devices/*")):
        if ":" in os.path.basename(path):
            continue
        product = read_text(os.path.join(path, "product"), "")
        manufacturer = read_text(os.path.join(path, "manufacturer"), "")
        vid = read_text(os.path.join(path, "idVendor"), "")
        pid = read_text(os.path.join(path, "idProduct"), "")
        if not (product or vid):
            continue
        devices.append(
            {
                "name": product or f"USB {vid}:{pid}",
                "manufacturer": manufacturer,
                "vendor_id": vid,
                "product_id": pid,
                "instance_id": os.path.basename(path),
                "present": True,
                "bus": "usb",
                "confidence": "measured",
                "source": "sysfs_usb",
            }
        )
    return {"device_count": len(devices), "devices": devices}


def _monitors() -> dict[str, Any]:
    displays = []
    for card in sorted(glob.glob("/sys/class/drm/card*-*")):
        status = read_text(os.path.join(card, "status"), "")
        if status and status != "connected":
            continue
        name = os.path.basename(card)
        edid_path = os.path.join(card, "edid")
        edid_hex = None
        try:
            with open(edid_path, "rb") as fh:
                raw = fh.read()
            if raw:
                edid_hex = raw.hex()
        except Exception:
            pass
        if status == "connected" or edid_hex:
            displays.append(
                {
                    "name": name,
                    "manufacturer": "",
                    "serial": "",
                    "active": status == "connected",
                    "edid": {"raw_hex": edid_hex} if edid_hex else None,
                    "confidence": "measured",
                    "source": "sysfs_drm",
                }
            )
    return {"count": len(displays), "displays": displays, "modes": []}


def device_inventory() -> dict[str, Any]:
    hwmon = sensors.hwmon_flat()
    pci = _pci_devices()
    usb = _usb_tree()
    monitors = _monitors()
    platform = platform_intel.platform_intelligence(hwmon)
    # Temporary devices stub for fingerprint GPU detection
    partial = {"pci": pci}
    fingerprint = platform_intel.machine_fingerprint(platform, partial)

    all_devices = list(pci)
    for u in usb.get("devices") or []:
        all_devices.append(
            {
                **u,
                "category": "usb",
                "class": "USB",
                "status": "OK",
                "problem_code": 0,
                "needs_driver": False,
                "has_problem": False,
                "hidden": False,
                "service": "",
            }
        )

    driverless = [d for d in pci if d.get("needs_driver")]
    problem = [d for d in pci if d.get("has_problem")]

    findings = []
    if driverless:
        findings.append(
            {
                "severity": "warn",
                "code": "devices_missing_drivers",
                "title": f"{len(driverless)} PCI device(s) have no kernel driver",
                "detail": "Install distro firmware/kernel modules. See Drivers tab for suggested packages.",
                "devices": [d.get("name") for d in driverless[:8]],
            }
        )
    if not (platform.get("tpm") or {}).get("present"):
        findings.append(
            {
                "severity": "info",
                "code": "tpm_missing",
                "title": "No TPM detected",
                "detail": "Enable fTPM/PTT in firmware if the silicon supports it.",
            }
        )
    if fingerprint.get("coverage_score", 0) < 50:
        findings.append(
            {
                "severity": "info",
                "code": "platform_coverage_low",
                "title": f"Platform coverage {fingerprint.get('coverage_score')}%",
                "detail": "Run probe as root for fuller EFI/TPM/hwmon planes where permitted.",
            }
        )

    board = ((platform.get("smbios") or {}).get("types") or {}).get("baseboard") or {}
    bios = platform.get("bios") or {}

    return {
        "summary": {
            "total_devices": len(all_devices),
            "present_devices": len(all_devices),
            "hidden_devices": 0,
            "problem_devices": len(problem),
            "driverless": len(driverless),
            "usb_devices": usb.get("device_count", 0),
            "monitors": monitors.get("count", 0),
            "pci_devices": len(pci),
            "audio_devices": 0,
            "bluetooth": 0,
            "system_slots": 0,
            "categories": {},
            "coverage_score": fingerprint.get("coverage_score"),
            "form_factor": fingerprint.get("form_factor"),
        },
        "firmware": {
            "bios": bios,
            "board": board,
            "system": ((platform.get("smbios") or {}).get("types") or {}).get("system") or {},
            "tpm": platform.get("tpm"),
            "secure_boot": (platform.get("uefi") or {}).get("secure_boot"),
            "uefi": platform.get("uefi"),
        },
        "platform": platform,
        "fingerprint": fingerprint,
        "motherboard": board,
        "bios": bios,
        "tpm": platform.get("tpm"),
        "secure_boot": (platform.get("uefi") or {}).get("secure_boot"),
        "monitors": monitors,
        "usb": usb,
        "audio": [],
        "bluetooth": [],
        "pci": pci,
        "system_slots": [],
        "ports": [],
        "battery": _batteries(),
        "problem": problem,
        "driverless": driverless,
        "hidden": [],
        "by_category": {},
        "findings": findings,
        "all_devices": all_devices,
        "schema": {"version": 3, "confidence_rule": "measured|sysfs|heuristic|unavailable", "platform": "linux"},
        "collected_at": utc_now(),
        "elevated": elevated(),
    }


def _batteries() -> list[dict[str, Any]]:
    out = []
    for bat in sorted(glob.glob("/sys/class/power_supply/BAT*")):
        out.append(
            {
                "name": os.path.basename(bat),
                "status": read_text(os.path.join(bat, "status"), ""),
                "capacity": read_text(os.path.join(bat, "capacity"), ""),
                "technology": read_text(os.path.join(bat, "technology"), ""),
                "source": "sysfs_power_supply",
                "confidence": "measured",
            }
        )
    return out
