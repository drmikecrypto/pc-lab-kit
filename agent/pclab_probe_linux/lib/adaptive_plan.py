"""Adaptive Lab plan — hardware-specific Full Lab steps (Linux parity)."""
from __future__ import annotations

from typing import Any

from common import utc_now


def build_plan(
    fingerprint: dict[str, Any] | None,
    devices: dict[str, Any] | None,
    platform: dict[str, Any] | None,
    telemetry: dict[str, Any] | None = None,
    template: str = "adaptive",
) -> dict[str, Any]:
    fingerprint = fingerprint or {}
    devices = devices or {}
    platform = platform or {}
    telemetry = telemetry or {}

    steps: list[dict[str, Any]] = []
    findings: list[dict[str, Any]] = []
    gated = False
    gate_reason = None

    driverless = int((devices.get("summary") or {}).get("driverless") or 0)
    chipset_missing = False
    network_missing = False
    gpu_missing = False
    for d in devices.get("driverless") or []:
        n = f"{d.get('name') or ''}{d.get('category') or ''}".lower()
        if any(k in n for k in ("chipset", "smbus", "lpc", "host bridge", "mei", "management engine", "psp", "ccp")):
            chipset_missing = True
        if any(k in n for k in ("ethernet", "lan", "wi-fi", "wifi", "wireless", "network", "bluetooth")):
            network_missing = True
        if any(k in n for k in ("nvidia", "geforce", "radeon", "display", "vga", "3d")):
            gpu_missing = True

    if chipset_missing or driverless >= 5:
        gated = True
        gate_reason = (
            "Chipset / platform driver missing - install linux-firmware / modules before Full Lab soak"
            if chipset_missing
            else f"{driverless} unbound PCI devices - prefer inventory + package fix before long stress"
        )
        findings.append(
            {
                "severity": "warn",
                "code": "adaptive_gate_drivers",
                "title": "Lab gated pending drivers",
                "detail": gate_reason,
            }
        )
    elif network_missing:
        findings.append(
            {
                "severity": "warn",
                "code": "adaptive_network_driver",
                "title": "Network driver missing",
                "detail": "Lab continues offline; install firmware packages after chipset",
            }
        )
    if gpu_missing and not gated:
        findings.append(
            {
                "severity": "warn",
                "code": "adaptive_gpu_driver",
                "title": "GPU driver missing",
                "detail": "GPU bench may fall back or fail until vendor/distro packages are installed",
            }
        )

    steps.append(
        {
            "id": "inventory",
            "kind": "inventory",
            "label": "Platform inventory",
            "params": {"include_platform": True},
            "reason": "Capture PCI/USB, DMI/SMBIOS, UEFI/TPM, and coverage before benches",
            "hardware_refs": ["platform", "pci"],
            "order": 10,
        }
    )

    if gated:
        steps.append(
            {
                "id": "drivers_gate",
                "kind": "sensor",
                "label": "Driver gate (review)",
                "params": {"action": "driver_action_plan"},
                "reason": gate_reason,
                "hardware_refs": ["drivers"],
                "order": 15,
                "gate": True,
            }
        )
        return {
            "id": "adaptive",
            "label": "Adaptive Lab (inventory-first)",
            "template": template,
            "gated": True,
            "gate_reason": gate_reason,
            "steps": sorted(steps, key=lambda s: s.get("order", 0)),
            "benches": [],
            "stress_id": None,
            "stress_seconds": 0,
            "findings": findings,
            "fingerprint_id": fingerprint.get("id"),
            "coverage_score": fingerprint.get("coverage_score"),
            "form_factor": fingerprint.get("form_factor") or "desktop",
            "duration_hint_min": 3,
            "platform": "linux",
            "collected_at": utc_now(),
        }

    cores = 0
    arch = (telemetry.get("cpu") or {}).get("architecture") or {}
    try:
        cores = int(arch.get("threads") or 0)
    except Exception:
        cores = 0
    if cores <= 0:
        try:
            with open("/proc/cpuinfo", "r", encoding="utf-8", errors="replace") as fh:
                cores = sum(1 for line in fh if line.startswith("processor"))
        except Exception:
            cores = 4

    has_discrete_gpu = bool(fingerprint.get("has_discrete_gpu"))
    nvme_count = int(fingerprint.get("nvme_count") or 0)
    disk_count = int(fingerprint.get("disk_count") or 0)
    is_laptop = fingerprint.get("form_factor") == "laptop"
    has_hdd = False
    for d in platform.get("storage") or []:
        mt = str(d.get("media_type") or "")
        bus = str(d.get("bus_type") or "")
        if ("HDD" in mt or "Unspecified" in mt) and not d.get("is_nvme"):
            has_hdd = True
        if (("SATA" in bus) or ("ATA" in bus)) and not d.get("is_nvme"):
            has_hdd = True

    benches: list[str] = []
    benches.append("cpu")
    steps.append(
        {
            "id": "bench:cpu",
            "kind": "bench",
            "label": "CPU single-thread",
            "params": {"id": "cpu"},
            "reason": "Baseline single-thread throughput for this CPU",
            "hardware_refs": ["cpu"],
            "order": 20,
        }
    )

    if cores >= 8:
        benches.extend(["cpu_mt", "cpu_cache"])
        steps.append(
            {
                "id": "bench:cpu_mt",
                "kind": "bench",
                "label": "CPU multi-thread",
                "params": {"id": "cpu_mt"},
                "reason": f"{cores} logical processors - multi-thread bench unlocked",
                "hardware_refs": ["cpu"],
                "order": 25,
            }
        )
        steps.append(
            {
                "id": "bench:cpu_cache",
                "kind": "bench",
                "label": "CPU cache",
                "params": {"id": "cpu_cache"},
                "reason": "Cache hierarchy check on high-core silicon",
                "hardware_refs": ["cpu"],
                "order": 28,
            }
        )
    else:
        benches.append("cpu_mt")
        steps.append(
            {
                "id": "bench:cpu_mt",
                "kind": "bench",
                "label": "CPU multi-thread",
                "params": {"id": "cpu_mt"},
                "reason": "Verify MT scaling even on lower core counts",
                "hardware_refs": ["cpu"],
                "order": 25,
            }
        )

    benches.append("memory")
    steps.append(
        {
            "id": "bench:memory",
            "kind": "bench",
            "label": "Memory bandwidth",
            "params": {"id": "memory"},
            "reason": "RAM bandwidth / latency vs DMI inventory",
            "hardware_refs": ["ram", "smbios"],
            "order": 30,
        }
    )

    if disk_count > 0:
        benches.append("storage")
        if nvme_count >= 2:
            storage_reason = f"{nvme_count} NVMe drives - sequential + multi-disk storage bench"
        elif has_hdd:
            storage_reason = "HDD present - longer storage endurance step"
        elif nvme_count == 1:
            storage_reason = "Single NVMe - sequential read/write profile"
        else:
            storage_reason = "Storage present - sequential profile"
        steps.append(
            {
                "id": "bench:storage",
                "kind": "bench",
                "label": "Storage",
                "params": {
                    "id": "storage",
                    "nvme_count": nvme_count,
                    "multi_disk": nvme_count >= 2,
                    "endurance_extra_s": 120 if has_hdd else 0,
                },
                "reason": storage_reason,
                "hardware_refs": ["storage"],
                "order": 40,
            }
        )

    if has_discrete_gpu:
        gpu_vendor = "unknown"
        for p in platform.get("pci_config") or devices.get("pci") or []:
            ven = str(p.get("vendor_id") or "").upper().replace("0X", "")
            if ven == "10DE":
                gpu_vendor = "nvidia"
                break
            if ven == "1002":
                gpu_vendor = "amd"
                break
            if ven == "8086":
                gpu_vendor = "intel"
        benches.append("gpu")
        steps.append(
            {
                "id": "bench:gpu",
                "kind": "bench",
                "label": "GPU compute",
                "params": {"id": "gpu", "vendor": gpu_vendor},
                "reason": f"Discrete GPU ({gpu_vendor}) - compute profile (Vulkan optional)",
                "hardware_refs": ["gpu"],
                "order": 50,
            }
        )
    else:
        findings.append(
            {
                "severity": "info",
                "code": "adaptive_skip_gpu",
                "title": "GPU soak skipped",
                "detail": "No discrete GPU fingerprint - iGPU-only systems skip heavy GPU bench/stress",
            }
        )

    if fingerprint.get("elevated"):
        steps.append(
            {
                "id": "sensor:openbook",
                "kind": "sensor",
                "label": "Open Book sensors",
                "params": {"include_openbook": True},
                "reason": "Root probe - capture hwmon / sysfs open-book channels before stress",
                "hardware_refs": ["gpu", "ec_board"],
                "order": 52,
            }
        )

    if is_laptop and devices.get("battery"):
        on_battery = False
        for b in devices.get("battery") or []:
            st = str(b.get("status") or "").lower()
            if "discharg" in st:
                on_battery = True
        steps.append(
            {
                "id": "sensor:battery",
                "kind": "sensor",
                "label": "Battery / AC path",
                "params": {"sample_battery": True, "prefer_ac": True},
                "reason": (
                    "Laptop on battery - prefer AC for Full Lab thermal truth"
                    if on_battery
                    else "Laptop with battery - sample AC vs battery thermal path"
                ),
                "hardware_refs": ["battery"],
                "order": 55,
            }
        )

    stress_sec_hint = None
    for d in platform.get("storage") or []:
        wear = d.get("wear")
        if wear is not None:
            try:
                if int(wear) >= 90:
                    findings.append(
                        {
                            "severity": "warn",
                            "code": "storage_wear_high",
                            "title": f"Storage wear {wear}%",
                            "detail": f"{d.get('friendly_name') or d.get('model')} reports high wear - endurance stress kept short",
                        }
                    )
                    if not has_hdd:
                        stress_sec_hint = 120
            except Exception:
                pass

    if has_discrete_gpu and cores >= 12:
        stress_id, stress_sec, reason = "oracle", 300, "High-core + discrete GPU - Stability Oracle soak"
    elif has_discrete_gpu:
        stress_id, stress_sec, reason = "combined", 180, "Discrete GPU - combined CPU/GPU stress"
    elif is_laptop:
        stress_id, stress_sec, reason = "quick", 90, "Laptop form factor - shorter thermal soak"
    else:
        stress_id, stress_sec, reason = "combined", 120, "Desktop without discrete GPU - moderate CPU stress"
    if has_hdd:
        stress_sec = max(stress_sec, 240)
    if stress_sec_hint is not None:
        stress_sec = min(stress_sec, int(stress_sec_hint))

    hw_refs = ["cpu"]
    if has_discrete_gpu:
        hw_refs.append("gpu")
    steps.append(
        {
            "id": "stress",
            "kind": "stress",
            "label": f"Stress: {stress_id}",
            "params": {"id": stress_id, "seconds": stress_sec},
            "reason": reason,
            "hardware_refs": hw_refs,
            "order": 80,
        }
    )

    cov = fingerprint.get("coverage_score")
    if cov is not None and int(cov) < 50:
        findings.append(
            {
                "severity": "info",
                "code": "adaptive_low_coverage",
                "title": f"Platform coverage {cov}%",
                "detail": "Run probe as root for fuller EFI/TPM/hwmon planes - benches still run",
            }
        )
    tpm = platform.get("tpm") or {}
    uefi = platform.get("uefi") or {}
    if tpm.get("present") and uefi.get("secure_boot") is False:
        findings.append(
            {
                "severity": "info",
                "code": "secure_boot_off",
                "title": "Secure Boot off",
                "detail": "Finding only - does not fail stress",
            }
        )
    if uefi.get("setup_mode") is True:
        findings.append(
            {
                "severity": "warn",
                "code": "uefi_setup_mode",
                "title": "UEFI Setup Mode",
                "detail": "Secure Boot keys may not be enrolled - shop policy finding only",
            }
        )

    hint = int(round(2 + (len(benches) * 1.5) + (stress_sec / 60.0)))
    return {
        "id": "adaptive",
        "label": "Adaptive Lab",
        "template": template,
        "gated": False,
        "gate_reason": None,
        "steps": sorted(steps, key=lambda s: s.get("order", 0)),
        "benches": benches,
        "stress_id": stress_id,
        "stress_seconds": stress_sec,
        "findings": findings,
        "fingerprint_id": fingerprint.get("id"),
        "coverage_score": fingerprint.get("coverage_score"),
        "form_factor": fingerprint.get("form_factor") or "desktop",
        "has_discrete_gpu": has_discrete_gpu,
        "nvme_count": nvme_count,
        "duration_hint_min": hint,
        "platform": "linux",
        "collected_at": utc_now(),
    }
