#!/bin/bash
set -euo pipefail

# openclaw-failover-monitor
# Monitors the failover status of configured AI model providers.
# Reads auth-profiles.json and openclaw.json to display cooldown/disabled states.
#
# Usage: ./openclaw-failover-monitor.sh [interval_seconds]
#   interval_seconds: Refresh interval in seconds (default: 5)

# Help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: $0 [interval_seconds]"
  echo "Monitors OpenClaw model failover status (read-only)."
  echo ""
  echo "  interval_seconds  Refresh interval in seconds (default: 5)"
  echo ""
  echo "The monitor reads the first agent found in ~/.openclaw/agents/."
  echo "Press Ctrl+C to stop."
  exit 0
fi

INTERVAL="${1:-5}"

# Validate interval is a positive integer
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -eq 0 ]]; then
  echo "ERROR: Interval must be a positive integer (got: '$INTERVAL')" >&2
  echo "Usage: $0 [interval_seconds]" >&2
  exit 1
fi

# Check dependencies
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required but not found." >&2
  exit 1
fi

# Locate auth-profiles.json via Bash globbing (no ls)
shopt -s nullglob
auth_files=(~/.openclaw/agents/*/agent/auth-profiles.json)
shopt -u nullglob
if [[ ${#auth_files[@]} -eq 0 ]]; then
  echo "ERROR: No auth-profiles.json found in ~/.openclaw/agents/*/agent/" >&2
  echo "Is OpenClaw installed and has at least one agent been created?" >&2
  exit 1
fi
AUTH_FILE="${auth_files[0]}"
AGENT_DIR="$(dirname "$(dirname "$AUTH_FILE")")"
AGENT_NAME="$(basename "$AGENT_DIR")"

if [[ ${#auth_files[@]} -gt 1 ]]; then
  echo "NOTE: Multiple agents found; monitoring '$AGENT_NAME'." >&2
fi

CONFIG_FILE=~/.openclaw/openclaw.json
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Config file not found: $CONFIG_FILE" >&2
  echo "Is OpenClaw installed?" >&2
  exit 1
fi

# Warn if config files are world-writable (could be tampered with)
for _f in "$AUTH_FILE" "$CONFIG_FILE"; do
  _perms="$(stat -f '%Lp' "$_f" 2>/dev/null || stat -c '%a' "$_f" 2>/dev/null)" || continue
  if [[ "${_perms: -1}" =~ [2367] ]]; then
    echo "WARNING: $_f is world-writable" >&2
  fi
done

# Clean exit on Ctrl+C
trap 'printf "\n%s\n" "Monitor stopped."; exit 0' INT TERM

while true; do
  clear
  echo "=== openclaw-failover-monitor === $(date)  [agent: $AGENT_NAME]"
  echo ""

  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  AUTH_FILE="$AUTH_FILE" CONFIG_FILE="$CONFIG_FILE" python3 "$SCRIPT_DIR/monitor.py" \
    || echo "  (error reading state files — retrying in ${INTERVAL}s)"
  sleep "$INTERVAL"
done
