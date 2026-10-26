#!/usr/bin/env bash
# Renders review screenshots into tests/output (or $1). Optional $2: comma-separated shot names.
cd "$(dirname "$0")/.."
OUT="${1:-tests/output}"
timeout 2400 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-method forward_plus res://tests/runner.tscn -- res://tests/screenshots.gd "$OUT" "${2:-}" 2>&1 | grep -E "^shot|SCRIPT ERROR|^ERROR" | grep -v "status < 0" | awk "NR <= 60"   # (head would kill the game with SIGPIPE once it has its lines)
