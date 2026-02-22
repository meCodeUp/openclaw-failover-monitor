#!/usr/bin/env python3
"""openclaw-failover-monitor – Python backend.

Reads AUTH_FILE and CONFIG_FILE from environment variables, parses the
OpenClaw auth-profiles and config JSON files, and prints a human-readable
failover status summary to stdout.
"""

import os
import sys
import json
import datetime
import re

# Strip ANSI escape sequences and control characters to prevent terminal injection
_ansi_re = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]|\x1b[^[]|[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]')


def sanitize(val):
    if isinstance(val, str):
        return _ansi_re.sub('', val)
    return val


def main():
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
        print(f'  {sanitize(profile)}  [{sanitize(label)}]')
        print(f'    model:      {sanitize(model)}')

        last_used = data.get('lastUsed')
        if last_used:
            lu = datetime.datetime.fromtimestamp(last_used / 1000).strftime('%H:%M:%S')
            print(f'    last used:  {lu}')
        else:
            print(f'    last used:  -')

        errors = data.get('errorCount', 0)
        failure_counts = data.get('failureCounts', {})
        failure_str = f' {sanitize(str(failure_counts))}' if failure_counts else ''
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


if __name__ == '__main__':
    main()
