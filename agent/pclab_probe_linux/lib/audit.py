"""Platform audit document — shop/OEM bay one-pager (Linux)."""
from __future__ import annotations

from typing import Any

from common import utc_now


def build_audit(inventory: dict[str, Any], drivers_payload: dict[str, Any], plan: dict[str, Any]) -> dict[str, Any]:
    devices = inventory or {}
    fingerprint = devices.get("fingerprint") or {}
    platform = devices.get("platform") or {}
    drivers = (drivers_payload or {}).get("drivers") or drivers_payload or {}
    action_plan = drivers.get("action_plan") or {}

    doc = {
        "schema": "pclab-platform-audit-v1",
        "generated_at": utc_now(),
        "platform_os": "linux",
        "fingerprint": {
            "id": fingerprint.get("id"),
            "hash_sha256": fingerprint.get("hash_sha256"),
            "coverage_score": fingerprint.get("coverage_score"),
            "form_factor": fingerprint.get("form_factor"),
            "elevated": fingerprint.get("elevated") or platform.get("elevated"),
            "capabilities": list(fingerprint.get("capabilities") or []),
        },
        "gaps": [g for g in (fingerprint.get("gaps") or []) if isinstance(g, dict)],
        "platform_planes": {
            "bios": platform.get("bios"),
            "uefi": {
                "firmware_type": (platform.get("uefi") or {}).get("firmware_type"),
                "secure_boot": (platform.get("uefi") or {}).get("secure_boot"),
                "setup_mode": (platform.get("uefi") or {}).get("setup_mode"),
                "bitlocker": None,
                "boot_entry_count": len((platform.get("uefi") or {}).get("boot_entries") or []),
            },
            "tpm": {
                "present": (platform.get("tpm") or {}).get("present"),
                "spec_version": (platform.get("tpm") or {}).get("spec_version"),
                "pcr_banks": (platform.get("tpm") or {}).get("pcr_banks"),
                "pcr_bank_source": (platform.get("tpm") or {}).get("pcr_bank_source"),
                "ready": (platform.get("tpm") or {}).get("ready"),
            },
            "me_psp": platform.get("me_psp"),
            "acpi_count": (platform.get("acpi") or {}).get("signature_count"),
            "storage": [
                {
                    "name": d.get("friendly_name") or d.get("model"),
                    "firmware": d.get("firmware"),
                    "wear": d.get("wear"),
                    "smart_depth": d.get("smart_depth"),
                    "is_nvme": d.get("is_nvme"),
                }
                for d in (platform.get("storage") or [])[:8]
                if isinstance(d, dict)
            ],
            "storage_count": len(platform.get("storage") or []),
            "pci_config_count": len(platform.get("pci_config") or []),
            "ec_board_count": (platform.get("ec_board") or {}).get("count"),
        },
        "adaptive_plan": {
            "id": plan.get("id") or plan.get("profile"),
            "label": plan.get("label"),
            "gated": bool(plan.get("gated")),
            "gate_reason": plan.get("gate_reason"),
            "steps": [s for s in (plan.get("steps") or []) if isinstance(s, dict)],
            "benches": list(plan.get("benches") or []),
            "stress_id": plan.get("stress_id"),
        },
        "driver_actions": {
            "count": int(action_plan.get("count") or len(drivers.get("actions") or [])),
            "installable_count": int(action_plan.get("installable_count") or 0),
            "items": list(action_plan.get("items") or drivers.get("actions") or [])[:40],
        },
        "stress": {"verdict": None, "id": None, "label": None},
        "inventory_summary": devices.get("summary") or {},
        "note": "Read-only Linux platform audit — DMI/sysfs/hwmon; no firmware flash, no Ring0 MMIO",
    }

    html = _to_html(doc)
    return {
        "ok": True,
        "document": doc,
        "html": html,
        "json": doc,
        "collected_at": utc_now(),
        "platform": "linux",
    }


def _to_html(doc: dict[str, Any]) -> str:
    fp = doc.get("fingerprint") or {}
    cov = int(fp.get("coverage_score") or 0)
    planes = doc.get("platform_planes") or {}
    plan = doc.get("adaptive_plan") or {}
    gaps = doc.get("gaps") or []
    gap_li = "".join(
        f"<li><code>{_esc(g.get('plane'))}</code> — {_esc(g.get('detail') or g.get('reason'))}</li>" for g in gaps[:12]
    )
    steps = plan.get("steps") or []
    step_li = "".join(f"<li>{_esc(s.get('label'))}: {_esc(s.get('reason'))}</li>" for s in steps[:16] if isinstance(s, dict))
    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>PC Lab Kit Platform Audit</title>
<style>
body{{font-family:system-ui,sans-serif;max-width:720px;margin:2rem auto;padding:0 1rem;color:#1a1a1a}}
.bar{{background:#e5e5e5;height:10px;border-radius:4px;overflow:hidden}}
.bar span{{display:block;height:100%;background:#2563eb}}
code{{font-size:.9em}}
</style></head><body>
<h1>Platform Audit</h1>
<p class="muted">Linux · {_esc(doc.get('generated_at'))} · fp <code>{_esc(fp.get('id'))}</code></p>
<div class="bar" role="meter"><span style="width:{cov}%"></span></div>
<p><strong>{cov}%</strong> platform coverage · {_esc(fp.get('form_factor'))}</p>
<h2>Planes</h2>
<ul>
<li>BIOS: {_esc((planes.get('bios') or {}).get('version'))}</li>
<li>Secure Boot: {_esc((planes.get('uefi') or {}).get('secure_boot'))}</li>
<li>TPM: {_esc((planes.get('tpm') or {}).get('present'))}</li>
<li>Storage devices: {_esc(planes.get('storage_count'))}</li>
</ul>
<h2>Gaps</h2>
<ul>{gap_li or '<li>None reported</li>'}</ul>
<h2>Adaptive plan</h2>
<p>{_esc(plan.get('label'))}{' (gated)' if plan.get('gated') else ''}</p>
<ol>{step_li or '<li>No steps</li>'}</ol>
<p><em>{_esc(doc.get('note'))}</em></p>
</body></html>"""


def _esc(v: Any) -> str:
    s = "" if v is None else str(v)
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )
