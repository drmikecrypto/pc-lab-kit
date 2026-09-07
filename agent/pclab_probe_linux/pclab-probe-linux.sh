#!/usr/bin/env bash
# PC Lab Kit Linux probe — launches Platform Intelligence Python server (Windows parity routes).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PCLAB_PROBE_PORT="${PCLAB_PROBE_PORT:-18765}"

if command -v python3 >/dev/null 2>&1; then
  PY=python3
elif command -v python >/dev/null 2>&1; then
  PY=python
else
  echo "python3 is required for pclab-probe-linux" >&2
  exit 1
fi

exec "$PY" "$ROOT/pclab-probe-linux.py" "$@"
