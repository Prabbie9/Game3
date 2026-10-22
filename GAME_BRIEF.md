# Project Brief: Open-World Crime Sandbox (GTA-style) in Godot 4

## Start Here: Setup Notes

The Mixamo Animations folder is shared by link. Download it over this link (e.g. with gdown), not the Drive connector: https://drive.google.com/drive/folders/1EEE9K89wnqsCae86tSGU-OfidZIGW-bW?usp=sharing
Record the link in PROGRESS.md so later sessions can use it.

Git and builds:
- **Branch:** Work on a branch called `main`. A leftover test branch, `claude/tmp-push-test`, is currently the repo's default branch. If you can, make `main` the default and delete the test branch. If the proxy blocks that, add a note to OWNER_TEST_CHECKLIST.md asking the owner to switch the default branch to `main` and delete the test branch.
- **Releases:** This environment's proxy may block creating GitHub Releases directly. Instead, add a GitHub Actions workflow (`.github/workflows/release.yml`) that runs whenever you push a version tag like `v0.1.0`. It should check out the repo with Git LFS, install Godot 4.7.2 and its export templates, export the Windows build, zip it, and attach it to a GitHub Release for that tag. Push a tag at the end of each milestone and check (e.g. with `gh run list`) that the workflow succeeded.
- **Fallback:** If you can't push the workflow, or it keeps failing after a couple of fixes, put the zipped builds in a `builds/` folder tracked with Git LFS instead, note it in PROGRESS.md and carry on.

---

You are the sole developer on a long-running project. Build a polished, high-fidelity 3D open-world crime sandbox in the style of the GTA series. There is **no story and no missions**. Everything else a player expects from a modern GTA-style sandbox should be present, working, and polished.

You have as much time as you need. Your sessions will be interrupted by usage limits and resumed later, so **the repository must always be the source of truth for your progress** (see "Working Rules"). Quality beats speed. Do not cut corners to declare something done.

---

## 0. What Matters (read this first, re-read it every session)

The owner will judge this project on exactly four things:

1. **It works.** The exported build launches and plays without crashes, softlocks or broken systems.
2. **It looks high-end.** The lighting, materials, models and effects look good in screenshots and in motion.
3. **It feels smooth.** It holds 60+ FPS, controls are responsive, and animations blend fluidly with no foot sliding, floating or popping.
4. **It's highly interactive.** There is lots to do, lots reacts to the player, and every vehicle can be entered.

Every task you take on must clearly improve one of these four. The owner does not care about code elegance, test coverage, internal tooling, architecture diagrams or documentation beyond what's needed to resume work.

**Anti-rabbit-hole rules**
- **Playable first, always.** Get a playable, good-looking slice early and keep the game playable at every commit. Widen and deepen it from there. Never spend sessions building systems that can't yet be seen or played.
- **Time-box problems.** If something takes more than about two attempts without progress, step back. Pick a simpler approach, use an existing addon or asset, or log it in `PROGRESS.md` and move on to something else.
- **Use what exists.** Before building any system from scratch, check whether an existing Godot addon or asset does it well enough, with a compatible license. Examples: terrain, vehicle physics, IK, ragdoll, crowds, UI theme.
- **Good enough beats perfect for invisible things.** Be a perfectionist about what the player sees and feels. Be pragmatic about everything else.
- **No tooling for its own sake.** Build tools and tests only when they catch problems the player would notice. Keep them small.
- **Before each new task, ask yourself:** "Will the player notice this?" If the answer is no, deprioritise it.

---

## 1. Hard Constraints

- **Engine:** Godot 4.7.2 stable (stay on this version unless a bug forces an upgrade), Forward+ (Vulkan) renderer.
- **Environment setup every session:** Godot is not kept between sessions. In the first session, write `tools/setup_env.sh`. It installs Godot 4.7.2 and its export templates, Mesa's software Vulkan driver (lavapipe), and a virtual display (Xvfb) for screenshots. Run it at the start of every session before anything else; it takes about a minute.
- **Other environment facts:**
  - The machine has 4 CPUs, 15 GB RAM, no GPU and about 30 GB of free disk. Software rendering is slow, so keep screenshot runs small.
  - Quaternius downloads go through itch.io and need a headless browser to get the file link.
  - If Freesound is blocked, use other CC0 audio sources (Kenney audio, OpenGameArt, Sonniss GDC bundles) instead of getting stuck. GDScript by default; C# or GDExtension only where profiling proves it is needed.
- **The owner does not have Godot installed and never will.** You must install Godot and its export templates yourself in your environment, build everything headlessly, and ship a **ready-to-run Windows x86_64 build** (`.exe` + `.pck`, zipped). The owner will only ever run the exported build.
- **Target hardware:** AMD Ryzen 7 7800X3D-class CPU, AMD Radeon RX 7800 XT GPU, 1440p and 1080p. **Minimum 60 FPS at all times on High preset at 1440p**, including while driving fast through dense areas with traffic, pedestrians and police active. Aim for 90+ average.
- **Legal assets only.** Prefer CC0 (Poly Haven, ambientCG, Kenney, Quaternius, Poly Pizza CC0 items, OpenGameArt CC0, Freesound CC0). CC-BY is fine with attribution. No ripped GTA/Rockstar or other commercial game assets, no real brand logos or trademarked vehicle names/badges, nothing with "non-commercial only" or unclear licenses. Record every external asset in `ASSET_CREDITS.md` with source URL, author and license.
- **It must not look like AI slop.** That means: a coherent art direction, consistent scale, no floating or clipping objects, no placeholder grey boxes in the final build, no default Godot UI theme, no mismatched asset styles thrown together, no programmer-art text.

### Owner-provided resources
- **Mixamo animations and characters** are in the owner's Google Drive, in a folder called **"Mixamo Animations"**. Use them as the primary animation library.
  - **What's there:** About 2,360 animation FBX files (about 1.4 GB), plus a "Characters" subfolder with 23 character FBX files (about 1.2 GB; Ch01–Ch47, Remy, Brute). All files are FBX at 30 fps. Characters are T-pose with skin; animations are without skin.
  - **How to download:** The owner has shared the folder by link. If the link is in `PROGRESS.md` or the kickoff message, download over it directly (e.g. with `gdown`). Otherwise, use the Google Drive connector, which only handles files under 10 MB, so it works for animations but not characters.
  - **Don't commit the whole library.** GitHub limits Git LFS storage. Download everything into an untracked folder (`assets/source/mixamo_raw/`, listed in `.gitignore`) and browse it there. Copy only the characters and animations the game actually uses into `assets/source/mixamo/`, tracked with Git LFS. Aim to keep that under about 500 MB. Each new session re-downloads the raw library from the link only if it needs something new from it.
  - **Missing animations:** With a library this size, almost everything should be there. If something isn't, list it in `OWNER_TEST_CHECKLIST.md` and use the closest substitute meanwhile.
  - Import them with a Godot `BoneMap` to `SkeletonProfileHumanoid`. Retarget all clips onto one shared humanoid skeleton so every character can use every animation.
  - Strip unneeded root-motion tracks or extract root motion deliberately.
  - Fix any T-pose or hip-offset issues before use.
  - Mixamo assets may be used in the shipped game but must not be redistributed as raw files. Keep them out of any public location.
- **Sketchfab access** is already set up. The network proxy adds the owner's credentials to requests to `api.sketchfab.com` automatically, so there is no token to handle.
  - Model files download from `sketchfab-prod-media.s3.amazonaws.com`.
  - Never try to reveal, print or store the credentials.
  - Use the Sketchfab Data API to search for and download models.
  - Only use models licensed **CC0 or CC-BY**. Never use NonCommercial, NoDerivatives, or Store/paid models.
  - Log each model in `ASSET_CREDITS.md` with author, URL and license.
  - Before accepting any model, check its polycount, texture quality and real-world scale, and whether it fits the art direction. Reduce or create LODs as needed.

---

## 2. Art Direction & Graphics (high-end is mandatory)

Pick one coherent setting (e.g. a sunlit coastal US-style city with downtown, suburbs, industrial docks, beach and hills) and hold every asset to it. Write the art direction down in `docs/ART_DIRECTION.md` before sourcing assets: palette, material rules, time-of-day mood, prop density targets.

Required rendering features (all tunable in settings):
- PBR materials everywhere, with proper albedo/normal/roughness/AO at sensible texel density (document your target, e.g. ~512 px/m for near surfaces). Use detail/trim sheets and decals (grime, cracks, road markings, puddles) to kill repetition.
- Dynamic day/night cycle with physically plausible sky, sun/moon, HDRI-quality ambient light, and weather (clear, overcast, rain with wet roads/reflections, fog).
- Global illumination (SDFGI or VoxelGI/baked LightmapGI where appropriate — choose based on profiling), SSAO/SSIL, SSR, volumetric fog, glow/bloom, tonemapping (ACES or AgX), auto-exposure, TAA or FSR, high-quality soft shadows with tuned cascade splits.
- Night city lighting: emissive windows, street lights, car headlights/taillights casting real light (with a budgeted light count), neon signs.
- Foliage with wind, LODs and impostors. Water with reflections/refraction, foam and waves at the shoreline.
- Particles: muzzle flash, sparks, bullet impacts per surface type, blood (toggleable), tire smoke, exhaust, explosions, fire, debris, rain splashes.

---

## 3. Performance Requirements

Treat 60 FPS minimum as a hard requirement, not an aspiration.
- Streaming world: split the map into cells/chunks loaded asynchronously around the player (`ResourceLoader.load_threaded_request`). No hitches when crossing chunk boundaries.
- LODs on every mesh (Godot auto-LOD plus hand-made LODs for hero assets), visibility ranges / HLOD for distant buildings, occlusion culling with baked occluders, `MultiMeshInstance3D` for repeated props, foliage and crowds where possible.
- Pool and reuse NPCs, vehicles, projectiles, decals and particles. Never instantiate in hot loops.
- AI and physics LOD: far NPCs/vehicles tick less often and use simplified logic; very distant ones are despawned.
- Keep a written budget in `docs/PERF_BUDGET.md` (draw calls, visible triangles, active lights, active physics bodies, NPC count, script ms/frame) and enforce it.
- Build an in-game **benchmark mode**: a scripted fly-through/drive-through of the heaviest areas that writes average/1%-low/min FPS, frame-time graph and a stat breakdown to a file next to the exe. The owner will run it and paste you the results. Also include a togglable on-screen perf overlay.
- Graphics presets: Low / Medium / High / Ultra, plus individual toggles. High must hold 60 FPS on the target hardware; Ultra may go further.

---

## 4. Feature Scope

### Player character
- Third-person controller: walk, jog, sprint, crouch, jump, climb/vault low obstacles, fall/ragdoll, swim, take cover (snap to walls), punch/melee.
- Smooth camera with collision, separate on-foot/aim/vehicle modes, aim zoom, shoulder swap.
- Animation via `AnimationTree` with blend spaces and state machines. **No foot sliding**: match locomotion speed to animation root motion or stride. Smooth transitions everywhere (start/stop, turn-in-place, landing).
- **Foot IK** so feet sit exactly on the ground on slopes and stairs, with pelvis adjustment. **Hand IK** so both hands grip weapons correctly; weapons attach to properly oriented hand sockets.
- Health, armor, death/respawn at hospital, wasted/busted screens.

### Weapons & combat
- At least: fists, melee weapon, pistol, SMG, shotgun, assault rifle, sniper rifle, grenades/throwable, rocket launcher.
- Weapon wheel, ammo/reload, recoil, spread, hit-scan or projectile as appropriate, aim assist option, headshots, hit reactions, ragdoll deaths, bullet decals and per-surface impact effects, shooting from vehicles.
- Weapon pickups and a shop (ammu-nation style, unbranded).

### Vehicles
- **Every vehicle is enterable** with enter/exit animations (driver side, passenger, carjacking with NPC pulled out).
- Classes: compact, sedan, sports, muscle, SUV, truck/van, police car, ambulance, fire truck, motorbike, bicycle, boat, helicopter. Add a plane only if it can be done well.
- Arcade-but-weighty handling tuned per class (raycast/VehicleBody3D suspension, drifting, handbrake), working lights, indicators, horn, radio stations (royalty-free/CC music only), visible damage (deformation or panel detachment, smoke, fire, explosion), tire skid marks.
- Vehicle camera (chase, hood, cinematic), speedometer on HUD.

### Police & wanted system
- 5-star wanted level with escalating response (foot cops → patrol cars → roadblocks → SWAT van → helicopter).
- Line-of-sight based search, wanted zone on minimap, losing the cops, arrests (busted), Pay 'n' Spray style respray (unbranded).
- Crimes that trigger wanted level: assault, shooting, theft, carjacking, hitting pedestrians, attacking police, etc.

### Pedestrians & traffic
- Population that varies by district and time of day; varied character models and outfits (not clones).
- Pedestrians walk sidewalks using navigation, cross at crossings, talk on phones, sit, react: flee, cower, fight back, call police, panic spreads.
- Traffic on a lane graph: obeys traffic lights and junctions, avoids obstacles, honks, reacts to the player and to gunfire, emergency vehicles respond to incidents.

### World & interactivity
- A meaningfully sized open world with distinct districts, roads, highway, alleys, parks, beach, interiors for a few buildings (shop, safehouse, at least one more).
- Make it as interactive as possible: breakable props (lamp posts, fences, hydrants spraying water, bins, glass), pushable physics objects, enterable safehouse with save point, vending machines, ATMs, phone booths, sittable benches, doors that open.
- Collectibles and money pickups, a cash economy.
- Ambient life: birds, distant aircraft, sirens, construction noises.

### Audio
- 3D positional audio with reverb zones (tunnels, interiors), engine sounds that change with RPM, surface-dependent footsteps, weapon sounds with distance falloff, police radio chatter, ambient city soundscape by district/time, UI sounds, multiple radio stations.

### UI / HUD / Menus
- Custom theme (fonts, colors, icons) matching the art direction — never the default Godot look.
- HUD: minimap with roads, blips and wanted zone, health/armor, weapon & ammo, money, wanted stars, notifications, crosshair, vehicle name toast.
- Full-screen map with zoom/pan, legend and waypoint placement with GPS route drawn on the minimap.
- Main menu, polished **pause menu** (resume, map, settings, controls, stats, save/load, quit), settings for graphics, audio, controls/rebinding, gameplay (aim assist, blood, subtitles), and display (resolution, window mode, V-sync, FPS cap, FOV).
- Full keyboard/mouse and gamepad support with correct button prompts.
- Save/load (player position, money, weapons, stats, time/weather).

---

## 5. Working Rules (critical because you will be interrupted)

0. **You are running unattended.** The owner will not reply during development.
   - Never stop to ask questions, offer options or wait for approval. Make the most sensible choice, note it in `docs/DECISIONS.md`, and keep going.
   - Things only the owner can do (testing on their GPU, adding Mixamo animations) go in `OWNER_TEST_CHECKLIST.md`. Never wait for them.
   - When a milestone is finished, push its build and start the next milestone immediately.
   - Only end your work when every milestone is done and you can't find anything left to improve that a player would notice.

1. **Before writing code**, create `docs/PLAN.md` with milestones (see Section 7) and `PROGRESS.md`. At the start of every session, read `PROGRESS.md`, `docs/PLAN.md` and `git log` before doing anything else.
2. Update `PROGRESS.md` after every meaningful step: what is done, what is in progress, known bugs, next action. Write it so a fresh session with no memory can pick up instantly.
3. Commit early and often with clear messages. Push to the remote regularly. Never leave the repo in a broken state at a commit.
4. Keep a short `docs/DECISIONS.md` log, a line or two per important choice.
5. Do not mark anything complete unless it has been checked (Section 6). If something cannot be verified in your environment, say so explicitly in `PROGRESS.md` and add it to a checklist for the owner to test.
6. Never fake progress: no stub functions passed off as features, no placeholder assets left in milestone builds, no disabled tests.
7. Organise the project cleanly: `scenes/`, `scripts/` (by system), `assets/` (by type and source), `addons/`, `tests/`, `tools/`, `docs/`. Use autoloads sparingly and signals for decoupling.
8. Before adding a third-party addon, check its license and that it supports the current Godot version.

---

## 6. Checking Your Work (lightweight, player-facing only)

You can't watch the game run on the real GPU, so use a few small checks that catch what a player would notice. Keep each of them simple. Don't turn them into projects of their own.

- **Screenshots are your eyes.** Keep one small script that renders a handful of fixed camera shots to PNG: day, night, rain, on foot, in a car, HUD and pause menu. Use a software renderer if there's no GPU. Look at them after every significant change, and fix anything that looks wrong or cheap: floating or clipping objects, bad lighting, repetitive textures, ugly UI.
- **One grounding check.** A quick scripted scene that confirms characters' feet are on the ground, weapons sit in the hands, and car wheels touch the road. Run it after animation, character or vehicle changes.
- **Smoke test every build.** The exported Windows build must boot to the main menu and load the world without errors.
- **Performance.** Keep an eye on draw calls, triangles and light counts. Rely on the owner's benchmark results for real FPS numbers.
- **Unit tests are optional.** Only add them where a bug has already bitten twice, e.g. in save/load.

---

## 7. Milestones (suggested order; each ends with a working Windows build)

1. **Playable vertical slice (get here fast):** one small, good-looking city block with proper lighting and sky. A Mixamo-animated player who walks, runs and jumps with feet on the ground. One car you can enter, drive and exit. One gun you can shoot. A basic HUD. Export a Windows build, add the benchmark mode and perf overlay, and tell the owner in `OWNER_TEST_CHECKLIST.md` to try it. Everything after this expands the slice.
2. **Player polish:** full locomotion set, foot/hand IK, camera, crouch, climb, swimming, ragdoll.
3. **World expansion:** more districts, road network, terrain, water, day/night, weather, streaming, LODs, occlusion. Hit the perf budget here before adding crowds.
4. **Vehicles:** handling, entry/exit, carjacking, damage, lights, all vehicle classes, vehicle audio.
5. **Combat:** weapons, aiming, IK grip, impacts, ragdolls, weapon wheel, pickups/shop.
6. **Population:** pedestrians, traffic with lane graph and lights, reactions, emergency services.
7. **Police:** wanted system, escalation, search behaviour, helicopter, busted/wasted flow.
8. **UI/UX:** HUD, minimap, full map + GPS, menus, pause, settings, rebinding, gamepad prompts, save/load.
9. **Interactivity & life:** breakables, props, interiors, safehouse, economy, collectibles, ambient life, radio.
10. **Polish & optimisation:** fix every bug list item, animation smoothing, audio mix, visual consistency pass, final perf pass on all presets, final export.

After milestone 10, keep iterating: review screenshots, improve the weakest-looking areas, add depth to existing systems, rather than bolting on new half-finished ones.

---

## 8. Deliverables

- Source in the git repo, with a `README.md` explaining structure and how to build.
- Zipped Windows build for each milestone (attached to a GitHub Release, or the location noted in `PROGRESS.md`).
- `ASSET_CREDITS.md`, `PROGRESS.md`, `docs/PLAN.md`, `docs/PERF_BUDGET.md`, `docs/ART_DIRECTION.md`, `docs/DECISIONS.md`.
- `OWNER_TEST_CHECKLIST.md`: short list of things for the owner to try and report back on (benchmark results, anything you could not verify yourself).

Start by reading this brief fully, checking your environment (Godot availability, network access to asset sites), then writing `docs/PLAN.md`.
