#!/usr/bin/env bash
# Exports the Windows x86_64 build (exe + pck) to build/PortSolano and zips it. Assumes tools/setup_env.sh ran.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/mixamo_import.py
python3 tools/texture_import.py
godot --headless --import --path . >/dev/null 2>&1 || true
rm -rf build/PortSolano && mkdir -p build/PortSolano
godot --headless --path . --export-release "Windows Desktop" build/PortSolano/PortSolano.exe 2>&1 | grep -E "ERROR|WARNING: .*export" || true
test -s build/PortSolano/PortSolano.exe && test -s build/PortSolano/PortSolano.pck
VER=$(grep -oP 'config/version="\K[^"]+' project.godot)
(cd build && rm -f PortSolano-*.zip && zip -r -q "PortSolano-v${VER}-windows-x86_64.zip" PortSolano)
ls -la build/PortSolano build/*.zip
