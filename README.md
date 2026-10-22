# Port Solano

An open-world crime sandbox (GTA-style, no story/missions) built in **Godot 4.7.2** (Forward+, Jolt physics).
Players only need the Windows build from the [Releases](../../releases) page: unzip and run `PortSolano.exe`.

## Repository layout
- `scenes/` — Godot scenes (world, player, vehicles, UI)
- `scripts/` — GDScript, grouped by system (`core/`, `player/`, `vehicles/`, `weapons/`, `ui/`, `world/` …)
- `assets/` — models, textures, audio, fonts, grouped by type and source (credits in `ASSET_CREDITS.md`)
- `tools/` — setup, asset fetch, screenshot and export scripts
- `docs/` — plan, art direction, performance budget, decisions
- `tests/` — the few automated checks (grounding check, smoke test)

## Building
```bash
tools/setup_env.sh                 # Godot 4.7.2 + export templates, lavapipe, Xvfb, gdown
python3 tools/fetch_mixamo.py      # Mixamo sources from the owner's shared Drive (never committed)
godot --headless --import --path .
tools/export_windows.sh            # -> build/PortSolano/PortSolano.exe + .pck
```
Pushing a tag `vX.Y.Z` builds the Windows zip in GitHub Actions and attaches it to a Release.

Mixamo characters/animations are used under the Mixamo license and are deliberately **not** stored in this public repository.
