"""Driver advisor — kernel modules + suggested distro packages."""
from __future__ import annotations

from typing import Any

from common import utc_now

# Suggested apt/dnf package names by category (best-effort; distro varies)
_PACKAGE_HINTS = {
    "chipset": {"label": "Linux firmware / microcode", "packages": ["linux-firmware", "intel-microcode", "amd64-microcode"]},
    "gpu": {
        "nvidia": {"label": "NVIDIA proprietary / Nouveau", "packages": ["nvidia-driver", "nvidia-driver-550"]},
        "amd": {"label": "AMDGPU firmware", "packages": ["linux-firmware", "mesa-vulkan-drivers"]},
        "intel": {"label": "Intel graphics", "packages": ["intel-media-va-driver", "mesa-vulkan-drivers"]},
    },
    "network": {"label": "Network firmware", "packages": ["linux-firmware"]},
    "audio": {"label": "ALSA / PipeWire", "packages": ["alsa-utils", "pipewire"]},
    "storage": {"label": "NVMe / AHCI (in-kernel)", "packages": []},
}


def _loaded_modules() -> set[str]:
    mods = set()
    try:
        with open("/proc/modules", "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                name = line.split()[0]
                mods.add(name)
    except Exception:
        pass
    return mods


def _infer_category(dev: dict[str, Any]) -> str:
    cat = (dev.get("category") or "").lower()
    name = (dev.get("name") or "").lower()
    if cat == "display" or "nvidia" in name or "radeon" in name or "amdgpu" in name:
        return "gpu"
    if cat == "network" or "ethernet" in name or "wifi" in name or "wireless" in name:
        return "network"
    if cat == "storage" or "nvme" in name:
        return "storage"
    if cat == "multimedia" or "audio" in name:
        return "audio"
    if "mei" in name or "ccp" in name or "bridge" in name:
        return "chipset"
    return cat or "other"


def _gpu_vendor(dev: dict[str, Any]) -> str:
    ven = (dev.get("vendor_id") or "").lower()
    if ven == "10de":
        return "nvidia"
    if ven == "1002":
        return "amd"
    if ven == "8086":
        return "intel"
    return "unknown"


def driver_report(inventory: dict[str, Any]) -> dict[str, Any]:
    modules = _loaded_modules()
    actions = []
    items = []
    order = [
        {"id": "chipset", "label": "Firmware / chipset", "why": "linux-firmware + CPU microcode first"},
        {"id": "storage", "label": "Storage", "why": "Usually in-tree; check NVMe firmware"},
        {"id": "gpu", "label": "GPU", "why": "Proprietary NVIDIA or AMDGPU/Mesa"},
        {"id": "network", "label": "Network", "why": "Wi-Fi/Ethernet firmware blobs"},
        {"id": "audio", "label": "Audio", "why": "PipeWire/ALSA stack"},
    ]

    for d in inventory.get("driverless") or []:
        cat = _infer_category(d)
        hint = _PACKAGE_HINTS.get(cat, {"label": cat, "packages": ["linux-firmware"]})
        if cat == "gpu":
            gv = _gpu_vendor(d)
            hint = _PACKAGE_HINTS["gpu"].get(gv, _PACKAGE_HINTS["gpu"]["nvidia"])
        pkgs = hint.get("packages") or []
        action = {
            "severity": "critical",
            "code": "missing_driver",
            "category": cat,
            "device": d.get("name"),
            "instance_id": d.get("instance_id"),
            "vendor_id": d.get("vendor_id"),
            "device_id": d.get("device_id"),
            "title": f"No kernel driver: {d.get('name')}",
            "detail": f"Suggested packages: {', '.join(pkgs) if pkgs else 'check distro firmware'}",
            "install_method": "manual_package",
            "package_url": None,
            "installable": False,
            "match_confidence": "heuristic",
            "primary_link": {
                "label": hint.get("label"),
                "url": "https://wiki.archlinux.org/title/Kernel_module",
            },
            "links": [{"label": p, "url": "#"} for p in pkgs[:4]],
        }
        actions.append(action)
        items.append(
            {
                "id": d.get("instance_id"),
                "device": d.get("name"),
                "instance_id": d.get("instance_id"),
                "category": cat,
                "action": "manual_url",
                "severity": "critical",
                "title": action["title"],
                "detail": action["detail"],
                "match_confidence": "heuristic",
                "match_confidence_pct": 55,
                "installable": False,
                "dependency_order": {"chipset": 0, "storage": 1, "gpu": 2, "network": 3, "audio": 4}.get(cat, 50),
                "packages": pkgs,
            }
        )

    # Bound GPUs still get update advice
    for d in inventory.get("pci") or []:
        if _infer_category(d) != "gpu" or d.get("needs_driver"):
            continue
        gv = _gpu_vendor(d)
        if gv == "nvidia" and "nvidia" not in modules and "nouveau" in modules:
            items.append(
                {
                    "id": d.get("instance_id"),
                    "device": d.get("name"),
                    "category": "gpu",
                    "action": "update",
                    "severity": "warn",
                    "title": "NVIDIA on Nouveau",
                    "detail": "Consider proprietary nvidia-driver for compute/CUDA if needed",
                    "match_confidence": "heuristic",
                    "match_confidence_pct": 70,
                    "installable": False,
                    "dependency_order": 2,
                    "packages": ["nvidia-driver"],
                }
            )

    items.sort(key=lambda x: (x.get("dependency_order", 50), 0 if x.get("severity") == "critical" else 1))
    queue = []
    for step in order:
        related = [a for a in actions if a.get("category") == step["id"]]
        queue.append(
            {
                "id": step["id"],
                "label": step["label"],
                "why": step["why"],
                "status": "action_required" if related else "ok",
                "actions": related,
                "installable": False,
            }
        )

    score = max(0, 100 - 15 * len([a for a in actions if a["severity"] == "critical"]) - 5 * len(items))
    grade = "A" if score >= 90 else ("B" if score >= 75 else ("C" if score >= 60 else "D"))

    return {
        "devices": inventory,
        "drivers": {
            "score": score,
            "grade": grade,
            "is_laptop": (inventory.get("fingerprint") or {}).get("form_factor") == "laptop",
            "summary": {
                "critical_actions": len([a for a in actions if a["severity"] == "critical"]),
                "warn_actions": len([a for a in actions if a["severity"] == "warn"]),
                "driverless": len(inventory.get("driverless") or []),
                "loaded_modules": len(modules),
            },
            "install_order": order,
            "install_queue": queue,
            "actions": actions,
            "action_plan": {
                "schema_version": 1,
                "order": order,
                "items": items,
                "count": len(items),
                "installable_count": 0,
                "note": "Linux: install via apt/dnf/pacman — one-click package install not automated",
            },
            "gpus": [],
            "stale_or_generic": [],
            "driverless": inventory.get("driverless") or [],
            "collected_at": utc_now(),
            "platform": "linux",
        },
    }
