#!/usr/bin/env python3
"""PC Lab Kit Linux probe — Platform Intelligence parity with Windows agent."""
from __future__ import annotations

import json
import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib")
if LIB not in sys.path:
    sys.path.insert(0, LIB)

import adaptive_plan  # noqa: E402
import audit  # noqa: E402
import devices  # noqa: E402
import drivers  # noqa: E402
import openbook  # noqa: E402
import platform_intel  # noqa: E402
import sensors  # noqa: E402
import suite  # noqa: E402
from common import elevated, json_bytes, load_or_create_probe_token  # noqa: E402

PORT = int(os.environ.get("PCLAB_PROBE_PORT", "18765"))
VERSION = 2
AGENT = "pclab-probe-linux"
PROBE_AUTH_TOKEN = load_or_create_probe_token()
_LOOPBACK_ORIGIN = re.compile(r"^https?://(127\.0\.0\.1|localhost)(:\d+)?$")
_MUTATING = re.compile(r"^/(suite|stress|oc|rgb|bench|drivers/install|orchestrate|launchers)(/|$)")


class ProbeHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("[pclab-linux] " + (fmt % args) + "\n")

    def _cors(self) -> None:
        origin = self.headers.get("Origin") or ""
        if _LOOPBACK_ORIGIN.match(origin):
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Credentials", "true")
        else:
            self.send_header("Access-Control-Allow-Origin", "http://127.0.0.1")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type, X-PcLab-Token, Authorization",
        )

    def _send(self, code: int, obj) -> None:
        body = json_bytes(obj)
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return {}
        raw = self.rfile.read(min(length, 2_000_000))
        try:
            data = json.loads(raw.decode("utf-8"))
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    def _require_auth(self, method: str, path: str) -> bool:
        if method != "POST" or not PROBE_AUTH_TOKEN:
            return True
        if not _MUTATING.match(path):
            return True
        tok = self.headers.get("X-PcLab-Token") or ""
        if not tok:
            auth = self.headers.get("Authorization") or ""
            if auth.lower().startswith("bearer "):
                tok = auth[7:].strip()
        if tok != PROBE_AUTH_TOKEN:
            self._send(
                401,
                {
                    "ok": False,
                    "error": "unauthorized",
                    "message": "X-PcLab-Token required for mutating routes",
                },
            )
            return False
        return True

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        try:
            self._dispatch("GET")
        except Exception as exc:
            self._send(500, {"ok": False, "error": str(exc)})

    def do_POST(self) -> None:  # noqa: N802
        try:
            self._dispatch("POST")
        except Exception as exc:
            self._send(500, {"ok": False, "error": str(exc)})

    def _dispatch(self, method: str) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        qs = parse_qs(parsed.query)

        if not self._require_auth(method, path):
            return

        if path == "/":
            self._send(
                200,
                {
                    "agent": AGENT,
                    "version": VERSION,
                    "platform": "linux",
                    "routes": [
                        "GET /health",
                        "GET /telemetry",
                        "GET /telemetry/history",
                        "GET /probe",
                        "GET /devices",
                        "GET /drivers",
                        "GET /openbook",
                        "GET /thermal",
                        "GET /suite/plan",
                        "POST /suite/start",
                        "GET /suite/status",
                        "POST /suite/cancel",
                        "GET /audit",
                    ],
                },
            )
            return

        if path == "/health":
            elev = elevated()
            self._send(
                200,
                {
                    "ok": True,
                    "agent": AGENT,
                    "version": VERSION,
                    "platform": "linux",
                    "elevated": elev,
                    "devices": True,
                    "drivers": True,
                    "suite": True,
                    "open_book": True,
                    "audit": True,
                    "hwmon": True,
                    "oc": False,
                    "rgb": False,
                    "launchers": False,
                    "vkbench": False,
                    "auth_required": bool(PROBE_AUTH_TOKEN),
                    "note": "Linux Platform Intelligence — DMI/sysfs/hwmon; no Ring0 MMIO open-book",
                },
            )
            return

        if path == "/telemetry":
            self._send(200, sensors.telemetry_snapshot())
            return

        if path == "/telemetry/history":
            self._send(200, {"ok": True, "samples": sensors.history_samples()})
            return

        if path == "/thermal":
            tel = sensors.telemetry_snapshot()
            self._send(
                200,
                {
                    "elevated": elevated(),
                    "thermal": tel.get("thermal"),
                    "cpu": tel.get("cpu", {}).get("thermal"),
                    "gpu": tel.get("gpu", {}).get("thermal"),
                    "platform": "linux",
                },
            )
            return

        if path == "/devices":
            self._send(200, devices.device_inventory())
            return

        if path == "/probe":
            inv = devices.device_inventory()
            tel = sensors.telemetry_snapshot()
            self._send(
                200,
                {
                    "ok": True,
                    "agent": AGENT,
                    "platform": "linux",
                    "elevated": elevated(),
                    "devices": inv,
                    "cpu": tel.get("cpu"),
                    "gpu": tel.get("gpu"),
                    "thermal": tel.get("thermal"),
                    "sensors": tel.get("sensors_flat"),
                    "collected_at": tel.get("collected_at"),
                },
            )
            return

        if path == "/drivers":
            inv = devices.device_inventory()
            self._send(200, drivers.driver_report(inv))
            return

        if path == "/openbook":
            inv = devices.device_inventory()
            tel = sensors.telemetry_snapshot()
            self._send(200, openbook.openbook_payload(inv, tel))
            return

        if path == "/suite/plan":
            inv = devices.device_inventory()
            plan = adaptive_plan.build_plan(
                inv.get("fingerprint"),
                inv,
                inv.get("platform"),
                sensors.telemetry_snapshot(),
            )
            self._send(200, {"ok": True, "plan": plan, "fingerprint": inv.get("fingerprint")})
            return

        if path == "/suite/status":
            self._send(200, suite.status())
            return

        if path == "/audit":
            inv = devices.device_inventory()
            drv = drivers.driver_report(inv)
            plan = adaptive_plan.build_plan(
                inv.get("fingerprint"),
                inv,
                inv.get("platform"),
                None,
            )
            self._send(200, audit.build_audit(inv, drv, plan))
            return

        if method == "POST" and path == "/suite/start":
            body = self._read_json()
            profile = str(body.get("profile") or "adaptive")
            inv = devices.device_inventory()
            result = suite.start(profile, inv, sensors.telemetry_snapshot())
            self._send(200, result)
            return

        if method == "POST" and path == "/suite/cancel":
            self._send(200, suite.cancel())
            return

        if method == "POST" and path == "/drivers/install":
            self._send(
                200,
                {
                    "ok": False,
                    "error": "linux_driver_install_manual",
                    "note": "Use distro package manager / OEM repo. Action plan lists packages; one-click install is Windows-only for now.",
                },
            )
            return

        self._send(404, {"error": "not found", "path": path, "agent": AGENT, "version": VERSION})


def _history_loop() -> None:
    while True:
        try:
            sensors.push_history_sample()
        except Exception:
            pass
        time.sleep(2.0)


def main() -> None:
    host = "127.0.0.1"
    httpd = ThreadingHTTPServer((host, PORT), ProbeHandler)
    threading.Thread(target=_history_loop, name="pclab-hist", daemon=True).start()
    print(f"[PcLab Probe Linux v{VERSION}] http://{host}:{PORT}/  elevated={elevated()}", flush=True)
    print("  routes: /health /devices /drivers /openbook /suite/* /audit /telemetry", flush=True)
    print(f"  auth_required={bool(PROBE_AUTH_TOKEN)}", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down", flush=True)


if __name__ == "__main__":
    main()
