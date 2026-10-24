# Decisions log

- 2026-10-22 — Engine Godot 4.7.2 Forward+; physics engine **Jolt** (built-in since 4.4): faster, more stable vehicles/ragdolls.
- 2026-10-22 — Setting: fictional coastal city "Port Solano" (see ART_DIRECTION.md). Realistic PBR look; stylised low-poly kits excluded from visible world so Mixamo characters don't clash.
- 2026-10-22 — Releases via GitHub Actions on version tags (proxy blocks direct release API writes).
- 2026-10-22 — Mixamo clips are retargeted at import to `SkeletonProfileHumanoid` (BoneMap) so every character shares every animation; locomotion clips are made in-place and their native stride speed is recorded to drive playback speed (no foot sliding).
- 2026-10-22 — Repo is **public**, so Mixamo FBX files are NOT committed (brief: "keep them out of any public location" overrides "track used files in LFS"). `assets/mixamo_manifest.json` lists the used files; `tools/fetch_mixamo.py` downloads them from the owner's shared link locally and in CI. `assets/source/mixamo/` is git-ignored.
- 2026-10-22 — Buildings are procedural boxes with a facade shader (tiled Poly Haven PBR wall + procedural windows with interior mapping, lit shops) instead of modular kits: coherent look, few draw calls, night-lit windows for free.
- 2026-10-22 — Cars: Sketchfab "Generic passenger car pack" (CC-BY, 10 unbranded body types, separate wheels) split at runtime by CarLibrary; VehicleBody3D with our -Z forward (negative engine force).
- 2026-10-22 — Fan palms composed from a trunk mesh + the young fan-palm model as the crown (no CC mature Washingtonia found).
- 2026-10-22 — Wine can't run the Windows build in this container; smoke tests run the identical .pck on the Linux release template.
- 2026-10-22 — Only the player character is shipped until pedestrians (M6) to keep the pck small (345 MB); character textures capped at 2K.
- 2026-10-22 — The proxy returns 403 for tag pushes, so releases are cut by committing release.txt on main; the workflow tags and publishes with GITHUB_TOKEN.
- 2026-10-22 — v0.1.0 shipped an untextured player: the CI cache of assets/source/mixamo restored stale *.import files over the committed ones. CI now caches only *.fbx. Character textures are also embedded at import (Basis Universal) rather than extracted to PNGs, which is simpler and reproducible.
- 2026-10-22 — Traversal: vault/climb clips are fitted to the real obstacle by a vertical offset curve per clip
  (bump for vaults, ramp for the jump to hang, constant for the braced climb) plus a start placement from the
  measured hand-plant distance, instead of scaling the motion; root yaw isn't extracted for these clips (hip twist
  stays in the pose). Chest-high ledges use "Climb Wall From Braced Hang To Crouch"; higher ones chain
  "Jump To A Braced Hang" into it (same braced pose, no blend).
- 2026-10-22 — Mixamo's cover set is authored with the character turned around relative to its root, so the root faces
  the wall (FACING = PI) and lateral input maps to -tangent. Verified with front/side/back pose renders.
- 2026-10-22 — Street props get simple collision (cylinders for poles/hydrants/bins, bounds boxes otherwise) on layer 16;
  Poly Haven kits that stack clean + weathered variants keep one per instance (separate RNG so the layout is stable).
- 2026-10-22 — Gamepad: A = sprint, X = jump (GTA layout); keyboard shoulder swap moved to MMB since Q is cover.
- 2026-10-23 — World: a ~2.2 km island baked offline by `tools/world/gen_world.py` (numpy): coastline, district
  layout, road graph (split into ≤160 m pieces), lots, 2 m heightmap with roads carved in, terrain splat, wild-vegetation
  density and the painted map. The game builds everything from that data, so the layout is versioned and deterministic.
- 2026-10-23 — Terrain: one coarse mesh for the whole map (16 m) plus 128 m detail chunks streamed around the camera
  (2 m / 4 m), skirts against cracks; the coarse mesh discards the detail square. Collision = HeightMapShape3D chunks
  around the focus, heights sampled on worker threads.
- 2026-10-23 — City: 256 m cells built on worker threads (CityCell → merged mesh arrays per material, collision boxes,
  MultiMesh prop instances, lights, occluders) and instantiated on the main thread in ≤3 ms steps; freed a few nodes
  per frame. Facade/road shaders take per-building/per-road parameters per vertex so a cell has ~20 meshes in total.
  Every cell also has a one-material far stand-in (boxes with a window grid) shown when it isn't loaded.
  tests/stream_check.gd flies the benchmark route at 45 m/s and fails on hitches.
- 2026-10-23 — Sky: custom sky shader (gradient from time-of-day colours, sun, clouds driven by the weather, stars)
  instead of PhysicalSkyMaterial, which has no clouds. Weather drifts between clear/cloudy/overcast/rain/storm/fog.
- 2026-10-23 — Street lights: thousands of lamps glow through their bulbs; a pool of 12–48 OmniLights (by preset)
  is moved to the lamps nearest the camera.
- 2026-10-23 — Trees: Sketchfab CC-BY jacaranda/oak (≈10k faces) rather than Poly Haven's scanned trees
  (200–900 MB of geometry). Vegetation gets runtime LODs (ImporterMesh.generate_lods) and is grouped per 64 m.
- 2026-10-23 — Vehicle sources: the generic car pack plus single CC-BY glTFs with fictional names (Daniel Zhabotinsky's
  low-poly series for muscle/police/van/ambulance/box truck; generic bus, fire engine, bikes, boat, helicopter).
  Models with real brands or real fire-department lettering (e.g. FDNY) were skipped. Textures capped at 2K
  (interiors/metal maps 1K).
- 2026-10-23 — Crash damage is a vertex-shader deformation (8 dents per car as uniforms in the car frame, shared by
  body, glass and lamp materials) rather than CPU mesh edits: free per frame, no mesh copies, works on shared meshes.
- 2026-10-23 — Engine sound: recorded CC0 loops (idle/low/high) crossfaded by rpm with a compressed pitch curve
  (pitch = (rpm/ref)^0.72) because the recordings cover a narrow rpm band; heavy vehicles use a diesel set.
- 2026-10-23 — Bikes are VehicleBody3D with two wheels and a lean controller. Its corrections are torque impulses:
  assigning angular_velocity from script overwrites the tyre impulses VehicleBody3D applies in its state callback
  (turns lost all yaw). Lean target comes from the steering (v·tan(steer)/wheelbase), not the measured yaw rate,
  which would hold a lean forever.
- 2026-10-23 — Carjack uses Mixamo's helicopter pair ("Pull Pilot Out Of Seat And Take The Controls" / "Pulled Out Of
  Pilot Seat"), sped up 1.6x/1.3x; passenger-side entry/exit are runtime mirrors of the driver clips (Left/Right
  tracks swapped, q → (x,-y,-z,w)), which the normalized humanoid rests allow. Three Mixamo characters now ship
  for NPC drivers (pck grows accordingly).
- 2026-10-23 — Audio sources are CC0/CC-BY from OpenGameArt and Kenney (freesound/pixabay are blocked here); the raw
  files stay out of the repo (tools/audio/build_audio.py re-fetches them), processed files are committed.
- 2026-10-23 — ASSET_CREDITS.md now ships in the release zip (CC-BY attribution for players).
- 2026-10-23 — Weapons are placed by a SkeletonModifier (AimPose) from the current frame's hand pose instead of a
  BoneAttachment (one frame late, so the support hand swam on the fore-end); TwoBoneIK only reaches positions, so a
  BoneOrient modifier turns the support wrist to the grip.
- 2026-10-23 — Bullets stop at a character's capsule only if the ray also passes through a limb capsule built from
  the skeleton (ray_test); otherwise the trace continues. Head = x3, limbs = x0.6. No per-bone physics bodies.
- 2026-10-23 — Drive-by has its own actions (vehicle_aim / vehicle_fire: RMB/LMB, LB/X) because the pad's triggers
  are throttle and brake in vehicles.
- 2026-10-23 — The gun shop is a hand-built interior on a lot the city generator leaves empty (WorldData.RESERVED),
  across the street from the start, so the first shop is found without a map.
- 2026-10-23 — Traffic follows a lane graph derived from the road graph at load (50 ms), right-hand traffic, two
  signal phases per town junction; AI drives real VehicleBody3D cars through Vehicle.ai_* inputs (same physics as
  the player's car, so crashes, damage and carjacking just work).
- 2026-10-23 — Pedestrians walk a pavement graph (WalkGraph: both kerbs of every walkable road, corner links,
  zebra crossings at town junctions) instead of a navmesh: the city is procedural and streamed, the graph costs
  25 ms to build for the whole island and gives crossings and signal timing for free.
- 2026-10-23 — 14 Mixamo characters (7 women with their own walk/idle/run clips) serve as pedestrians, drivers,
  clerks and crews; the least-used character is picked for each spawn so streets don't fill with clones.
- 2026-10-23 — Mixamo characters embed 4096² textures (~50 MB video memory each); a post-import script
  (tools/import/character_post_import.gd) downsizes them to 1024 (pedestrians) / 2048 (player).
- 2026-10-23 — Emergency services are ordinary traffic cars on a planned lane route (A* with a binary heap over the
  lane graph; Dijkstra was O(n²) and stalled the frame) with siren/priority; an ambulance's paramedic revives the dead or injured, a fire engine's crew puts out
  burning cars. They only operate near the player (streamed like the rest of the traffic).
- 2026-10-23 — Hand-placed showcase vehicles stand on the kerb (not in a lane) so traffic doesn't queue behind them;
  traffic still changes lane / overtakes round anything left in the road.
- 2026-10-23 — Dying shows WASTED and wakes the player at the hospital for a $100 fee (weapons kept); the
  hospital, police station and respray garage are storefronts on reserved lots so the police (M7) can use them.
- 2026-10-23 — Signals only where an avenue or drive meets other roads (70 junctions); minor street crossings are
  give-way. The bigger road gets the longer green (25 s vs 12 s). With lights on every 64 m grid junction cars
  spent ~60% of their time at red. Cars creep through a red only to clear the way for a siren, when nothing
  crosses.
- 2026-10-23 — tests/stream_check.gd measures streaming alone (no traffic/crowd round the parked player);
  traffic_check covers the traffic itself.
- 2026-10-24 — No uniformed characters in the Mixamo library, so police/SWAT wear a fitted kit (Uniform): a vest shrink-wrapped to the character's torso with weights copied from the nearest body vertices, cap or helmet on the head bone, lettering as Label3D. Fitting runs on a worker thread at load (mesh built on the main thread: RenderingServer calls from the worker deadlocked the exported build at quit).
