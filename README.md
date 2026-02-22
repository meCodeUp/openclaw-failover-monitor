# openclaw-failover-monitor

> **Beta** — This tool is in early development. Expect rough edges and breaking changes.

A terminal-based monitoring tool for [OpenClaw](https://openclaw.ai) that displays the real-time failover status of your configured AI model providers.

## What it does

OpenClaw supports automatic failover between AI model providers (e.g. Google, OpenAI, Anthropic). When a provider hits rate limits or errors, OpenClaw temporarily disables it and switches to a fallback.

This monitor reads OpenClaw's internal state files and displays:

- **Primary and fallback models** in their configured priority order
- **Error counts** and failure details per provider
- **Cooldown/disabled timers** showing when a provider will be available again
- **Last used timestamps** for each provider

## Prerequisites

- **OpenClaw** installed and configured with at least one agent
- **Python 3.6+** (used for JSON parsing; f-strings require 3.6+)
- **Bash 3.2+** (macOS default is fine; tested on macOS — should work on Linux but is not explicitly tested)

## Installation

```bash
git clone https://github.com/meCodeUp/openclaw-failover-monitor.git
cd openclaw-failover-monitor
chmod +x openclaw-failover-monitor.sh
```

## Usage

```bash
# Start with default 5-second refresh interval
./openclaw-failover-monitor.sh

# Custom refresh interval (e.g. 10 seconds)
./openclaw-failover-monitor.sh 10
```

Press `Ctrl+C` to stop the monitor.

## Example output

```
=== openclaw-failover-monitor === Sun Feb 22 14:30:00 CET 2026

  google:default  [primary]
    model:      google/gemini-flash
    last used:  14:29:55
    errors:     0
    STATUS:     ok

  openai:default  [fallback#1]
    model:      openai/gpt-4o
    last used:  14:20:10
    errors:     3 {'429': 3}
    STATUS:     COOLDOWN (00:04:32 remaining)
```

## How it works

The monitor reads OpenClaw's internal state files under `~/.openclaw/` to extract usage stats, error counts, cooldown timers, and the model failover configuration. It does not read or display API keys or credentials.

It refreshes automatically at the configured interval. No data is modified — the monitor is strictly read-only.

**Note:** If you have multiple agents, the monitor uses the first agent directory found.

## Limitations

- **Single agent only** — The monitor currently reads only the first agent found in `~/.openclaw/agents/`. Multi-agent support (e.g. via `--agent <name>`) is not yet implemented.

## License

MIT License — see [LICENSE](LICENSE).
