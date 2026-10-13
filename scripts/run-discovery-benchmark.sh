#!/usr/bin/env bash
# Configure transport outside the frozen acceptance evaluator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -n "${FEEDMINE_BENCH_DEVICE_UDID:-}" ]]; then
  : "${FEEDMINE_BENCH_TRANSPORT_HOST:?Set the Mac LAN host:port for physical-device evaluation}"
  export FEEDMINE_BENCH_TRANSPORT_ORIGIN="http://${FEEDMINE_BENCH_TRANSPORT_HOST}"
else
  export FEEDMINE_BENCH_TRANSPORT_ORIGIN="http://127.0.0.1:8757"
fi
export TEST_RUNNER_FEEDMINE_BENCH_TRANSPORT_ORIGIN="$FEEDMINE_BENCH_TRANSPORT_ORIGIN"
exec python3 scripts/benchmark_launch.py "$@"
