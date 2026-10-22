#!/usr/bin/env bash
# Installs everything needed to build, export and screenshot the game headlessly.
# Idempotent: safe to run at the start of every session (~1 min on a fresh container).
set -euo pipefail

GODOT_VERSION="4.7.2-stable"
GODOT_TPL_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION/-/.}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/tools/godot}"
BASE="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}"

mkdir -p "$TOOLS_DIR"

if ! command -v godot >/dev/null || [[ "$(godot --version 2>/dev/null)" != 4.7.2.stable* ]]; then
  echo "[setup] Installing Godot ${GODOT_VERSION}"
  curl -sSLf -o "$TOOLS_DIR/godot.zip" "$BASE/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
  unzip -o -q "$TOOLS_DIR/godot.zip" -d "$TOOLS_DIR"
  rm -f "$TOOLS_DIR/godot.zip"
  chmod +x "$TOOLS_DIR/Godot_v${GODOT_VERSION}_linux.x86_64"
  ln -sf "$TOOLS_DIR/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot
fi

if [[ ! -f "$GODOT_TPL_DIR/windows_release_x86_64.exe" ]]; then
  echo "[setup] Installing export templates"
  curl -sSLf -o "$TOOLS_DIR/templates.tpz" "$BASE/Godot_v${GODOT_VERSION}_export_templates.tpz"
  mkdir -p "$GODOT_TPL_DIR"
  unzip -o -q "$TOOLS_DIR/templates.tpz" -d "$TOOLS_DIR/tpl"
  mv "$TOOLS_DIR"/tpl/templates/* "$GODOT_TPL_DIR"/
  rm -rf "$TOOLS_DIR/tpl" "$TOOLS_DIR/templates.tpz"
fi

if [[ ! -f /usr/share/vulkan/icd.d/lvp_icd.json ]] || ! command -v Xvfb >/dev/null; then
  echo "[setup] Installing Mesa lavapipe + Xvfb"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mesa-vulkan-drivers libegl1 xvfb xauth >/dev/null
fi

python3 -c "import gdown" 2>/dev/null || pip install -q gdown 2>/dev/null || pip install -q --break-system-packages gdown
git lfs install --skip-repo >/dev/null 2>&1 || true

echo "[setup] $(godot --version)  templates: $(ls "$GODOT_TPL_DIR" | wc -l) files"
