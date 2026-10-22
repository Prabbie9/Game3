# PROGRESS — read this first every session

**Mixamo library (owner's shared Drive folder, download over this link with `tools/fetch_mixamo.py` / gdown):**
https://drive.google.com/drive/folders/1EEE9K89wnqsCae86tSGU-OfidZIGW-bW?usp=sharing
(`tools/mixamo_index.json` maps every file name → Drive file id, so no folder listing is needed.)

## Session start
1. `tools/setup_env.sh`
2. Read this file, `docs/PLAN.md`, `git log --oneline -20`.
3. `python3 tools/fetch_mixamo.py` (fetches the Mixamo files the game uses; `--all` mirrors the whole library to `assets/source/mixamo_raw/`, `--grep walk` searches names).

## Current milestone: 1 — Playable vertical slice (in progress)

### Done
- Planning docs: PLAN, ART_DIRECTION, PERF_BUDGET, DECISIONS, OWNER_TEST_CHECKLIST, ASSET_CREDITS.
- `tools/setup_env.sh`, `tools/fetch_mixamo.py`, `.github/workflows/release.yml` (tag `v*` → Windows zip on a GitHub Release).

### In progress / next
- Mixamo import pipeline (BoneMap → SkeletonProfileHumanoid, in-place locomotion with recorded stride speed).
- City block, player controller, car, pistol, HUD, perf overlay, benchmark.

### Known issues
- Default branch is still `claude/tmp-push-test` (proxy blocks changing it) → owner checklist item.

### Builds
| Tag | Milestone | Where |
|---|---|---|
| – | – | – |
