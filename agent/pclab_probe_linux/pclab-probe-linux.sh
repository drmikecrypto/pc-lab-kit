#!/usr/bin/env bash
# PC Lab Kit Linux probe MVP — telemetry + health (R5 parity starter)
set -euo pipefail
PORT="${PCLAB_PROBE_PORT:-18765}"
PREFIX="http://127.0.0.1:${PORT}"

read_cpu_temp() {
  local t=""
  for hw in /sys/class/hwmon/hwmon*/temp1_input; do
    [ -f "$hw" ] || continue
    t=$(cat "$hw" 2>/dev/null || echo "")
    [ -n "$t" ] && echo "scale=1; $t/1000" | bc && return 0
  done
  echo "null"
}

read_gpu_temp() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "null"
  else
    echo "null"
  fi
}

route_health() {
  echo '{"ok":true,"agent":"pclab-probe-linux","version":1,"platform":"linux","elevated":false}'
}

route_telemetry() {
  local cpu gpu
  cpu=$(read_cpu_temp)
  gpu=$(read_gpu_temp)
  echo "{\"cpu_temp\":${cpu:-null},\"gpu_temp\":${gpu:-null},\"platform\":\"linux\"}"
}

handle() {
  local method="$1" path="$2"
  case "$path" in
    /health) route_health ;;
    /telemetry) route_telemetry ;;
    /) echo '{"routes":["GET /health","GET /telemetry"]}' ;;
    *) echo '{"error":"not found"}' ; return 404 ;;
  esac
}

echo "[PcLab Probe Linux MVP] port ${PORT} — health + telemetry only"
while true; do
  { read -r req _; read -r _; read -r _; read -r _; read -r _; } < /dev/tcp/127.0.0.1/"$PORT" 2>/dev/null || {
    # Minimal loop using netcat when available
    if command -v nc >/dev/null 2>&1; then
      nc -l -p "$PORT" -e bash -c 'read -r line; path=$(echo "$line" | awk "{print \$2}"); method=$(echo "$line" | awk "{print \$1}"); body=$(handle "$method" "$path"); printf "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${#body}\r\n\r\n$body"' 2>/dev/null || true
    else
      echo "Install netcat (nc) for Linux probe MVP or use pclab_core R3." >&2
      sleep 5
    fi
  }
done
