# lib.sh -- shared helpers for microM8 acceptance tests. Source this.
# Manages the emulator lifecycle and wraps the m8.py driver CLI.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
M8DIR="/Users/green/projects/microm8-cln"
SKILL="/Users/green/Documents/agent-skills/6502-testing"
DISK="$ROOT/build/WORDII.po"
PORT="${M8PORT:-8080}"

# drive <m8.py args...> : run the driver CLI, echo its stdout
drive() { ( cd "$SKILL" && uv run --with mcp python scripts/m8.py "$@" ); }

# m8_boot : (re)launch the emulator on $DISK and wait for the ] prompt
m8_boot() {
  pkill -f "microM8 -mcp" 2>/dev/null || true
  sleep 2
  ( cd "$M8DIR" && nohup ./microM8 -mcp -mcp-mode sse -mcp-port "$PORT" \
      -no-update -ssc-telnet-no-eof -drive1 "$DISK" >/tmp/m8-accept.log 2>&1 & )
  local i
  for i in $(seq 1 40); do
    curl -s --max-time 2 "http://localhost:$PORT/mcp/health" 2>/dev/null | grep -q healthy && break
    sleep 1
  done
  sleep 8   # let ProDOS reach ] before we connect (connecting mid-boot wedges it)
}

# m8_launch : from the ] prompt, start Word II
m8_launch() { drive type '-WORDII.SYSTEM{r}' sleep 2 >/dev/null; }

m8_stop() { pkill -f "microM8 -mcp" 2>/dev/null || true; }

# assert_contains <haystack> <needle> <label>
assert_contains() {
  if printf '%s' "$1" | grep -qF "$2"; then
    echo "  ok   $3"
  else
    echo "  FAIL $3 (missing: $2)"; FAILED=1
  fi
}

FAILED=0
finish() { [ "$FAILED" -eq 0 ] && echo "PASS: $0" || { echo "FAIL: $0"; exit 1; }; }
