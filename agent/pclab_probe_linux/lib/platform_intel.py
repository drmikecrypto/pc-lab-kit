"""Platform Intelligence — DMI/SMBIOS, UEFI, TPM, ACPI, NVMe (Linux)."""
from __future__ import annotations

import glob
import os
from typing import Any

from common import chassis_is_laptop, elevated, read_int, read_text, sha256_hex, utc_now

DMI = "/sys/class/dmi/id"


def _dmi(name: str) -> str:
    return read_text(os.path.join(DMI, name), "")


def smbios_decoded() -> dict[str, Any]:
    available = os.path.isdir(DMI)
    bios = {
        "vendor": _dmi("bios_vendor") or None,
        "version": _dmi("bios_version") or None,
        "release_date": _dmi("bios_date") or None,
        "source": "sysfs_dmi",
        "confidence": "measured" if _dmi("bios_version") else "unavailable",
    }
    system = {
        "manufacturer": _dmi("sys_vendor") or None,
        "product": _dmi("product_name") or None,
        "version": _dmi("product_version") or None,
        "serial": _dmi("product_serial") or None,
        "uuid": _dmi("product_uuid") or None,
        "sku": _dmi("product_sku") or None,
        "family": _dmi("product_family") or None,
        "source": "sysfs_dmi",
        "confidence": "measured" if _dmi("product_name") else "unavailable",
    }
    baseboard = {
        "manufacturer": _dmi("board_vendor") or None,
        "product": _dmi("board_name") or None,
        "version": _dmi("board_version") or None,
        "serial": _dmi("board_serial") or None,
        "asset_tag": _dmi("board_asset_tag") or None,
        "source": "sysfs_dmi",
        "confidence": "measured" if _dmi("board_name") else "unavailable",
    }
    chassis = {
        "manufacturer": _dmi("chassis_vendor") or None,
        "type_code": _dmi("chassis_type") or None,
        "version": _dmi("chassis_version") or None,
        "serial": _dmi("chassis_serial") or None,
        "source": "sysfs_dmi",
        "confidence": "measured" if _dmi("chassis_type") else "unavailable",
    }
    return {
        "available": available,
        "source": "sysfs_dmi",
        "confidence": "measured" if available else "unavailable",
        "smbios_major": None,
        "smbios_minor": None,
        "types": {
            "bios": bios if bios.get("version") else None,
            "system": system if system.get("product") or system.get("manufacturer") else None,
            "baseboard": baseboard if baseboard.get("product") else None,
            "chassis": chassis if chassis.get("type_code") else None,
            "processor": None,
            "cache": [],
            "slots": [],
            "physical_mem": None,
            "memory_devices": [],
            "memory_array_mapped": [],
        },
        "type_counts": {
            "bios": 1 if bios.get("version") else 0,
            "system": 1 if system.get("product") else 0,
            "baseboard": 1 if baseboard.get("product") else 0,
            "chassis": 1 if chassis.get("type_code") else 0,
            "memory_devices": 0,
        },
        "note": "sysfs DMI identity — not a full DMI type-table walk",
    }


def uefi_info() -> dict[str, Any]:
    is_efi = os.path.isdir("/sys/firmware/efi")
    secure_boot = None
    setup_mode = None
    sb_source = "unavailable"
    # efivarfs SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
    for path in glob.glob("/sys/firmware/efi/efivars/SecureBoot-*"):
        try:
            with open(path, "rb") as fh:
                data = fh.read()
            if len(data) >= 5:
                secure_boot = bool(data[4])
                sb_source = "efivarfs"
            break
        except Exception:
            continue
    for path in glob.glob("/sys/firmware/efi/efivars/SetupMode-*"):
        try:
            with open(path, "rb") as fh:
                data = fh.read()
            if len(data) >= 5:
                setup_mode = bool(data[4])
            break
        except Exception:
            continue

    gaps = []
    if not is_efi:
        gaps.append({"code": "not_uefi", "detail": "No /sys/firmware/efi — legacy BIOS or inaccessible"})
    if is_efi and secure_boot is None:
        gaps.append({"code": "secure_boot_unknown", "detail": "SecureBoot efivar unreadable (needs privileges)"})

    return {
        "firmware_type": "uefi" if is_efi else "bios",
        "secure_boot": secure_boot,
        "secure_boot_source": sb_source,
        "secure_boot_policy": None,
        "setup_mode": setup_mode,
        "device_guard": {"virtualization_based_security": None, "source": "n/a_linux"},
        "bitlocker": {"system_drive_protection": None, "source": "n/a_linux"},
        "boot_current": None,
        "boot_order": [],
        "boot_entries": [],
        "bootmgr_path": None,
        "source": "sysfs_efi",
        "confidence": "measured" if is_efi else "partial",
        "gaps": gaps,
        "note": "Read-only EFI detection — no NVRAM write",
    }


def tpm_detail() -> dict[str, Any]:
    tpm_dirs = sorted(glob.glob("/sys/class/tpm/tpm*"))
    if not tpm_dirs:
        return {"present": False, "source": "unavailable", "confidence": "unavailable"}
    tpm0 = tpm_dirs[0]
    caps = read_text(os.path.join(tpm0, "caps"), "")
    version = None
    if os.path.isfile(os.path.join(tpm0, "tpm_version_major")):
        major = read_text(os.path.join(tpm0, "tpm_version_major"), "")
        minor = read_text(os.path.join(tpm0, "tpm_version_minor"), "")
        version = f"{major}.{minor}".strip(".")
    pcr_banks = []
    pcr_source = "unavailable"
    for bank_dir in glob.glob(os.path.join(tpm0, "pcr-*")):
        name = os.path.basename(bank_dir).replace("pcr-", "")
        if name:
            pcr_banks.append(name)
            pcr_source = "sysfs_tpm_pcr"
    if not pcr_banks and version and version.startswith("2"):
        pcr_banks = ["sha256"]
        pcr_source = "heuristic_tpm2"
    return {
        "present": True,
        "enabled": True,
        "activated": True,
        "owned": None,
        "ready": True,
        "locked_out": None,
        "self_test": None,
        "spec_version": version or (caps[:64] if caps else None),
        "manufacturer_id": None,
        "manufacturer_version": None,
        "pcr_banks": pcr_banks,
        "pcr_bank_source": pcr_source,
        "source": "sysfs_tpm",
        "confidence": "measured",
        "note": "sysfs TPM status — no remote attestation",
    }


def me_psp_info() -> dict[str, Any]:
    devices = []
    for path in glob.glob("/sys/bus/pci/devices/*"):
        vendor = read_text(os.path.join(path, "vendor"), "").lower()
        device = read_text(os.path.join(path, "device"), "").lower()
        # Intel ME HECI often 8086:a0e0 etc — detect by class or uevent DRIVER=mei
        driver_link = os.path.join(path, "driver")
        driver = os.path.basename(os.path.realpath(driver_link)) if os.path.islink(driver_link) else ""
        uevent = read_text(os.path.join(path, "uevent"), "")
        name = ""
        if "mei" in driver.lower() or "MEI" in uevent or "mei_me" in uevent:
            name = f"Intel MEI ({os.path.basename(path)})"
            role = "mei"
        elif "ccp" in driver.lower() or "psp" in driver.lower() or "ccp" in uevent.lower():
            name = f"AMD PSP/CCP ({os.path.basename(path)})"
            role = "psp"
        else:
            continue
        devices.append(
            {
                "name": name,
                "instance_id": os.path.basename(path),
                "status": "OK",
                "class": "System",
                "role": role,
                "driver_provider": driver or None,
                "driver_version": None,
                "is_generic": False,
                "vendor_id": vendor.replace("0x", ""),
                "device_id": device.replace("0x", ""),
                "source": "sysfs_pci",
                "confidence": "measured",
            }
        )
    vendor = None
    if any(d["role"] == "mei" for d in devices):
        vendor = "intel"
    elif any(d["role"] == "psp" for d in devices):
        vendor = "amd"
    return {
        "vendor": vendor,
        "present": len(devices) > 0,
        "devices": devices,
        "generic_driver": False,
        "source": "sysfs_pci" if devices else "unavailable",
        "confidence": "measured" if devices else "unavailable",
        "note": "PCI driver binding only — no proprietary MEI/PSP version DLL",
    }


def acpi_detail() -> dict[str, Any]:
    tables_dir = "/sys/firmware/acpi/tables"
    signatures = []
    if os.path.isdir(tables_dir):
        for name in sorted(os.listdir(tables_dir)):
            if name.startswith("."):
                continue
            # dynamic SSDTs appear as SSDT, SSDT1…
            sig = "".join(c for c in name if c.isalpha())[:4] or name[:4]
            signatures.append(sig.upper() if len(sig) <= 4 else name[:4].upper())
    signatures = sorted(set(signatures))
    return {
        "signatures": signatures,
        "signature_count": len(signatures),
        "has_fadt": "FACP" in signatures or "FADT" in signatures,
        "has_dsdt": "DSDT" in signatures,
        "sleep_states": {"s3": None, "s4": None, "s5": True, "source": "partial"},
        "thermal_zone_count": len(glob.glob("/sys/class/thermal/thermal_zone*")),
        "source": "sysfs_acpi",
        "confidence": "measured" if signatures else "partial",
        "note": "ACPI table name list — no AML interpreter",
    }


def nvme_smart() -> list[dict[str, Any]]:
    drives = []
    for nvm in sorted(glob.glob("/sys/class/nvme/nvme*")):
        if not os.path.isdir(nvm):
            continue
        name = os.path.basename(nvm)
        model = read_text(os.path.join(nvm, "model"), name)
        serial = read_text(os.path.join(nvm, "serial"), "")
        fw = read_text(os.path.join(nvm, "firmware_rev"), "")
        # namespace under nvme*n1
        size_gb = None
        temp = None
        wear = None
        for ns in sorted(glob.glob(os.path.join(nvm, "nvme*n*"))):
            size = read_int(os.path.join(ns, "size"))
            if size:
                # size is in 512-byte sectors typically for nvme ns
                size_gb = round(size * 512 / (1024**3), 1)
            hwmon = glob.glob(os.path.join(ns, "device", "hwmon", "hwmon*", "temp1_input"))
            if not hwmon:
                hwmon = glob.glob(os.path.join(nvm, "hwmon", "hwmon*", "temp1_input"))
            if hwmon:
                milli = read_int(hwmon[0])
                if milli is not None:
                    temp = round(milli / 1000.0, 1)
        drives.append(
            {
                "friendly_name": model,
                "model": model,
                "serial": serial,
                "media_type": "SSD",
                "bus_type": "NVMe",
                "is_nvme": True,
                "size_gb": size_gb,
                "health_status": "Healthy",
                "firmware": fw or None,
                "temperature_c": temp,
                "wear": wear,
                "percentage_used": wear,
                "admin_smart": False,
                "smart_depth": "sysfs_nvme_identity",
                "source": "sysfs_nvme",
                "confidence": "measured",
                "note": "sysfs NVMe identity/temp — not full Admin SMART log pages (use nvme-cli for deeper)",
            }
        )
    # Also generic block devices if no nvme class
    if not drives:
        for block in sorted(glob.glob("/sys/block/nvme*")) + sorted(glob.glob("/sys/block/sd*"))[:4]:
            name = os.path.basename(block)
            size = read_int(os.path.join(block, "size"))
            size_gb = round(size * 512 / (1024**3), 1) if size else None
            drives.append(
                {
                    "friendly_name": name,
                    "serial": "",
                    "media_type": "SSD" if name.startswith("nvme") else "Disk",
                    "bus_type": "NVMe" if name.startswith("nvme") else "SCSI",
                    "is_nvme": name.startswith("nvme"),
                    "size_gb": size_gb,
                    "health_status": "Unknown",
                    "firmware": None,
                    "admin_smart": False,
                    "smart_depth": "sysfs_block",
                    "source": "sysfs_block",
                    "confidence": "partial",
                    "note": "Block device identity only",
                }
            )
    return drives


def ec_board_sensors(hwmon_rows: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    rows = []
    for row in hwmon_rows or []:
        name = (row.get("name") or "").lower()
        hw = (row.get("hardware") or "").lower()
        if any(k in name or k in hw for k in ("fan", "vrm", "chipset", "motherboard", "nb_", "sb_", "soc")):
            rows.append({**row, "source": "hwmon_ec_board", "confidence": "measured"})
    return {
        "sensors": rows[:64],
        "count": len(rows),
        "board_match_confidence": "high" if len(rows) > 8 else ("medium" if rows else "unavailable"),
        "source": "hwmon" if rows else "unavailable",
        "note": "hwmon SuperIO/EC-like channels — no custom EC protocol",
    }


def microcode() -> dict[str, Any]:
    rev = None
    try:
        with open("/proc/cpuinfo", "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("microcode"):
                    rev = line.split(":", 1)[1].strip()
                    break
    except Exception:
        pass
    return {
        "revision": rev,
        "source": "proc_cpuinfo" if rev else "unavailable",
        "confidence": "measured" if rev else "unavailable",
    }


def platform_intelligence(hwmon_rows: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    smbios = smbios_decoded()
    uefi = uefi_info()
    tpm = tpm_detail()
    me_psp = me_psp_info()
    acpi = acpi_detail()
    storage = nvme_smart()
    ucode = microcode()
    bios_plane = {
        "vendor": (smbios.get("types") or {}).get("bios", {}) and smbios["types"]["bios"].get("vendor"),
        "version": (smbios.get("types") or {}).get("bios", {}) and smbios["types"]["bios"].get("version"),
        "date": (smbios.get("types") or {}).get("bios", {}) and smbios["types"]["bios"].get("release_date"),
        "smbios_major": None,
        "smbios_minor": None,
        "source": "sysfs_dmi",
        "confidence": "measured" if smbios.get("available") else "unavailable",
    }
    if smbios.get("types") and smbios["types"].get("bios"):
        bios_plane["vendor"] = smbios["types"]["bios"].get("vendor")
        bios_plane["version"] = smbios["types"]["bios"].get("version")
        bios_plane["date"] = smbios["types"]["bios"].get("release_date")

    return {
        "schema_version": 1,
        "collected_at": utc_now(),
        "elevated": elevated(),
        "bios": bios_plane,
        "smbios": smbios,
        "uefi": uefi,
        "tpm": tpm,
        "me_psp": me_psp,
        "acpi": acpi,
        "storage": storage,
        "pci_config": [],
        "ec_board": ec_board_sensors(hwmon_rows),
        "microcode": ucode,
        "planes": [
            "bios",
            "smbios",
            "uefi",
            "tpm",
            "me_psp",
            "acpi",
            "storage",
            "pci_config",
            "ec_board",
            "microcode",
        ],
        "note": "Linux Platform Intelligence — sysfs/DMI/EFI/TPM; no firmware flash",
    }


def machine_fingerprint(platform: dict[str, Any], devices: dict[str, Any] | None = None) -> dict[str, Any]:
    parts: list[str] = []
    types = (platform.get("smbios") or {}).get("types") or {}
    board = types.get("baseboard") or {}
    if board:
        parts.append(f"board:{board.get('manufacturer')}|{board.get('product')}|{board.get('serial')}")
    bios = platform.get("bios") or {}
    parts.append(f"bios:{bios.get('vendor')}|{bios.get('version')}")
    system = types.get("system") or {}
    if system.get("uuid"):
        parts.append(f"uuid:{system.get('uuid')}")
    model = ""
    try:
        with open("/proc/cpuinfo", "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("model name"):
                    model = line.split(":", 1)[1].strip()
                    break
    except Exception:
        pass
    if model:
        parts.append(f"cpu:{model}")
    if (platform.get("microcode") or {}).get("revision"):
        parts.append(f"ucode:{platform['microcode']['revision']}")
    for d in platform.get("storage") or []:
        if d.get("serial"):
            parts.append(f"disk:{d['serial']}")
    for p in (devices or {}).get("pci") or []:
        parts.append(f"pci:{p.get('vendor_id')}:{p.get('device_id')}")

    material = "\n".join(sorted(set(parts)))
    digest = sha256_hex(material)

    planes = [
        ("bios", (bios.get("confidence") in ("measured", "wmi"))),
        ("smbios", bool((platform.get("smbios") or {}).get("available"))),
        ("uefi", (platform.get("uefi") or {}).get("firmware_type") is not None),
        ("tpm", bool((platform.get("tpm") or {}).get("present"))),
        ("me_psp", bool((platform.get("me_psp") or {}).get("present"))),
        ("acpi", ((platform.get("acpi") or {}).get("signature_count") or 0) > 0),
        ("storage", len(platform.get("storage") or []) > 0),
        ("pci_config", len(platform.get("pci_config") or []) > 0),
        ("ec_board", ((platform.get("ec_board") or {}).get("count") or 0) > 0),
        ("microcode", bool((platform.get("microcode") or {}).get("revision"))),
    ]
    measured = sum(1 for _, ok in planes if ok)
    total = len(planes)
    coverage = int(round(100.0 * measured / max(1, total)))

    gaps = []
    for pid, ok in planes:
        if ok:
            continue
        reason = "hardware_absent_or_unreadable"
        detail = f"{pid} plane not measured"
        if pid == "pci_config":
            reason, detail = "linux_limit", "PCI config dump not implemented on Linux probe (sysfs IDs only)"
        elif pid == "ec_board" and not elevated():
            reason, detail = "needs_elevation", "Board/EC hwmon may need root for some chips"
        gaps.append({"plane": pid, "reason": reason, "detail": detail})

    chassis = (types.get("chassis") or {}).get("type_code")
    is_laptop = chassis_is_laptop(chassis)
    has_discrete_gpu = False
    for p in (devices or {}).get("pci") or []:
        name = (p.get("name") or "").lower()
        if any(k in name for k in ("nvidia", "geforce", "radeon", "amd ", "arc ")):
            # skip if likely iGPU only keywords
            if "vga compatible" in name or "3d controller" in name or "display" in name:
                ven = (p.get("vendor_id") or "").lower()
                if ven in ("10de", "1002") or "arc" in name:
                    has_discrete_gpu = True

    capabilities = ["inventory", "adaptive_lab", "driver_action_plan"]
    if (platform.get("smbios") or {}).get("available"):
        capabilities.append("smbios_decode")
    if (platform.get("uefi") or {}).get("secure_boot") is not None:
        capabilities.append("secure_boot_audit")
    if (platform.get("tpm") or {}).get("present"):
        capabilities.append("tpm_status")
    if any(d.get("is_nvme") for d in platform.get("storage") or []):
        capabilities.append("nvme_reliability")
    if elevated():
        capabilities.append("elevated_root")

    return {
        "id": digest[:32],
        "hash_sha256": digest,
        "coverage_score": coverage,
        "planes_measured": measured,
        "planes_total": total,
        "gaps": gaps,
        "capabilities": capabilities,
        "form_factor": "laptop" if is_laptop else "desktop",
        "has_discrete_gpu": has_discrete_gpu,
        "nvme_count": sum(1 for d in platform.get("storage") or [] if d.get("is_nvme")),
        "disk_count": len(platform.get("storage") or []),
        "elevated": elevated(),
        "material_parts": len(parts),
        "source": "platform_intelligence_linux",
        "confidence": "high" if coverage >= 70 else ("medium" if coverage >= 40 else "low"),
        "collected_at": utc_now(),
    }
