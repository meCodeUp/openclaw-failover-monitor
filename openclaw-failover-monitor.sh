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

CONFIG_FILE=~/.openclaw/openclaw.json
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Config file not found: $CONFIG_FILE" >&2
  echo "Is OpenClaw installed?" >&2
  exit 1
fi

# Clean exit on Ctrl+C
trap 'printf "\n%s\n" "Monitor stopped."; exit 0' INT TERM

while true; do
  clear
  echo "=== openclaw-failover-monitor === $(date)"
  echo ""

  AUTH_FILE="$AUTH_FILE" CONFIG_FILE="$CONFIG_FILE" python3 -c "
import os, sys, json, datetime

auth_path = os.environ['AUTH_FILE']
config_path = os.environ['CONFIG_FILE']

try:
    with open(auth_path) as f:
        auth = json.load(f)
except FileNotFoundError:
    print(f'  ERROR: Auth file not found: {auth_path}')
    sys.exit(1)
except json.JSONDecodeError as e:
    print(f'  ERROR: Invalid JSON in {auth_path}: {e}')
    sys.exit(1)

try:
    with open(config_path) as f:
        config = json.load(f)
except FileNotFoundError:
    print(f'  ERROR: Config file not found: {config_path}')
    sys.exit(1)
except json.JSONDecodeError as e:
    print(f'  ERROR: Invalid JSON in {config_path}: {e}')
    sys.exit(1)

stats = auth.get('usageStats', {})
# Timestamps in auth-profiles.json are milliseconds since epoch (local time)
now = datetime.datetime.now().timestamp() * 1000

# Load primary + fallback models from config
model_config = config.get('agents', {}).get('defaults', {}).get('model', {})
primary = model_config.get('primary', '')
fallbacks = model_config.get('fallbacks', [])
all_models = [primary] + fallbacks

if not primary:
    print('  WARNING: No primary model configured in openclaw.json')
    print()

# Extract provider profiles (e.g. 'google/gemini-flash' -> 'google:default')
seen = []
ordered_profiles = []
for model in all_models:
    parts = model.split('/')
    if len(parts) < 2:
        continue
    provider = parts[0]
    profile_key = f'{provider}:default'
    if profile_key not in seen:
        seen.append(profile_key)
        try:
            idx = fallbacks.index(model) + 1
            label = f'fallback#{idx}'
        except ValueError:
            label = 'primary' if model == primary else 'unknown'
        ordered_profiles.append((profile_key, model, label))

if not ordered_profiles:
    print('  WARNING: No model profiles found in config.')
    sys.exit(0)

for profile, model, label in ordered_profiles:
    data = stats.get(profile, {})
    print(f'  {profile}  [{label}]')
    print(f'    model:      {model}')

    last_used = data.get('lastUsed')
    if last_used:
        lu = datetime.datetime.fromtimestamp(last_used / 1000).strftime('%H:%M:%S')
        print(f'    last used:  {lu}')
    else:
        print(f'    last used:  -')

    errors = data.get('errorCount', 0)
    failure_counts = data.get('failureCounts', {})
    failure_str = f' {failure_counts}' if failure_counts else ''
    print(f'    errors:     {errors}{failure_str}')

    cooldown = data.get('cooldownUntil')
    disabled = data.get('disabledUntil')

    if cooldown and cooldown > now:
        secs = int((cooldown - now) / 1000)
        mins, s = divmod(secs, 60)
        hrs, mins = divmod(mins, 60)
        print(f'    STATUS:     COOLDOWN ({hrs:02d}:{mins:02d}:{s:02d} remaining)')
    elif disabled and disabled > now:
        secs = int((disabled - now) / 1000)
        mins, s = divmod(secs, 60)
        hrs, mins = divmod(mins, 60)
        print(f'    STATUS:     DISABLED ({hrs:02d}:{mins:02d}:{s:02d} remaining)')
    elif profile not in stats:
        print(f'    STATUS:     no failover data')
    else:
        print(f'    STATUS:     ok')
    print()
" || echo "  (error reading state files — retrying in ${INTERVAL}s)"
  sleep "$INTERVAL"
done
