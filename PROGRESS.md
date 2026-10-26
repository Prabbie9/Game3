# PROGRESS — read this first every session

**Mixamo library (owner's shared Drive folder — download over this link with `tools/fetch_mixamo.py` / gdown):**
https://drive.google.com/drive/folders/1EEE9K89wnqsCae86tSGU-OfidZIGW-bW?usp=sharing
(`tools/mixamo_index.json` maps every file name → Drive id; `python3 tools/fetch_mixamo.py --grep walk` searches names.)

## Session start
1. `tools/setup_env.sh` (Godot 4.7.2 + templates, lavapipe, Xvfb, gdown).
2. Read this file, `docs/PLAN.md`, `git log --oneline -20`.
3. `python3 tools/fetch_mixamo.py` → fetches the Mixamo files listed in `assets/mixamo_manifest.json`
   (FBX/PNG are git-ignored: public repo). Then `python3 tools/mixamo_import.py && python3 tools/texture_import.py && godot --headless --import --path .`
   (first import of characters takes ~2 min each — only the player character is in the manifest right now).

## Checks (run after relevant changes)
- `godot --headless --path . res://tests/runner.tscn -- res://tools/dev/check_scripts.gd` — every script compiles.
- `... -- res://tests/grounding_check.gd` — feet on ground at all gaits, pistol in hand, wheels on road.
- `... -- res://tests/drive_check.gd` — enter car, accelerate, brake, steer, stay upright, exit.
- `... -- res://tests/abilities_check.gd [SHOT_DIR]` — drives every on-foot ability headless (crouch, vaults/climbs with
  hand-to-top distance, cover, punch, fall→ragdoll→get up, swim + climb out, run stop, turn in place). With a
  SHOT_DIR under `xvfb-run` it also saves a side-view picture of each pose.
- `... -- res://tools/dev/pose_sheet.gd OUT.png TIME clip…` — front/side/back render of library clips (orientation checks);
  `... -- res://tools/dev/action_trace.gd ACTION` — root path + hand/feet positions through a root-motion action.
- `... -- res://tests/stream_check.gd` — streaming hitch check (fails on long frames while flying across the map).
- `tools/screenshots.sh OUT [day,aim,wide,tour|tour_<name>,pool,enter,car,night,rain,pause,menu]` — software-rendered
  review shots (~3 min each with the full world; run subsets)
  (+ draw-call/primitive stats in the log). ~1 min per shot.
- `tools/export_windows.sh` then smoke test: copy `~/.local/share/godot/export_templates/4.7.2.stable/linux_release.x86_64`
  as `PortSolano.x86_64` next to a symlink of `build/PortSolano/PortSolano.pck` and run
  `xvfb-run -a ./PortSolano.x86_64 -- --smoke` (must print `SMOKE TEST PASSED`, exit 0; under llvmpipe it takes
  ~5.5 min — the menu alone ~2.5 min — so give it a 15 min timeout). Wine 9 crashes on start-up
  in this container (page fault inside ntdll), so the Linux template + same .pck is the boot check.
- `... -- res://tests/weapons_check.gd`, `lane_graph_check.gd`, `traffic_check.gd` (traffic not in the world yet).
- `... -- res://tests/asset_check.gd` — characters textured, all clips resolve (also runs in CI before export).
- After a release: download the zip (`gh api repos/Prabbie9/Game3/releases/tags/vX`), smoke-test its pck, and compare
  `tools/pck_list.py` against the local build.
- Never use `pkill -f <pattern>` in the same shell command line that contains the pattern (kills itself); use `pat[t]ern`.

## Status
**Milestone 1 — Playable vertical slice: DONE (v0.1.1; v0.1.0 shipped an untextured player — fixed by embedding character textures)**
- Player: Mixamo Ch08 retargeted to SkeletonProfileHumanoid; AnimationTree (locomotion blendspace at native clip speeds,
  pistol aim strafe 2D, jump/fall/land with timed windows, car enter/drive/exit). Walk 1.0, run 4.2, sprint 6.4 m/s.
- Camera rig (on-foot / aim / vehicle, collision, shoulder swap).
- City: 3x3 road grid (±110 m), procedural road markings/crosswalks/stop lines, curbs with ramp collision, 4 blocks +
  outer ring of facade-shaded buildings (interior-mapped windows, lit shops), palms (composed fan palms + date palms),
  Poly Haven street props, distant skyline, road-end barriers.
- Vehicles: 6 parked cars from the generic car pack (10 body types available), enter/exit with Mixamo clips aligned to
  the door via root-motion displacement, arcade handling (speed-sensitive steering, anti-roll, handbrake), headlights (L).
- Pistol (M1911): hit-scan, recoil, spread, reload, muzzle flash light, tracers, pooled decals/impact particles.
- HUD: vector minimap, health/armor, money, weapon/ammo, crosshair, speedometer, vehicle toast, notifications, prompts.
- Main menu over live city, pause menu, graphics presets (Low/Medium/High/Ultra) persisted, F3 perf overlay,
  benchmark mode (menu or `-- --benchmark`) writing report + CSV next to the exe.
- Perf (software-rendered measurement of draw calls only): street view 532 draws (+1249 shadow), 2.3 M prims.

**Milestone 2 — Player polish: DONE (v0.2.0)**
- Foot IK (raycast feet + pelvis drop, TwoBoneIK legs, foot alignment) and left-hand IK on the pistol grip.
- Crouch (toggle C / L3, crouch walk at clip speed, camera lowers), run stop clip after letting go at a run, turn on
  the spot for sharp reversals from standstill.
- Traversal (Space / X at an obstacle): one-handed vault < 0.95 m, two-handed vault up to 1.35 m (thin obstacles),
  braced climb for 1.0–1.55 m ledges, jump-to-braced-hang + climb for 1.55–2.4 m. Clips are offset to the real
  obstacle height so the hands land on the top surface (checked in abilities_check).
- Cover (Q / RB): snaps the back to a wall, high/low cover, slides along it with the sneak clips, stops at the edge.
- Fists (mouse wheel / D-pad toggles fists ↔ pistol): jab/cross/hook combo, hits bodies, knocks props.
- Swimming in water volumes (plaza pool), treading water / swimming, climb out over an edge (jump or keep pushing).
- Long falls ragdoll in mid-air (Jolt PhysicalBones, damage from predicted impact speed), get up from back/front;
  hard landings; death → respawn.
- Camera: follows the pelvis during vaults/climbs/ragdoll, wider FOV when sprinting, lower in crouch/low cover,
  hides the character when squeezed against it; shoulder swap moved to MMB / R3.
- World: sunken public pool in the plaza (procedural mosaic tiles + caustics, refractive water shader), benches
  assembled from the modular kit, street props now solid (collision layer 16) with one weathering variant each.
- Pause menu lists the controls for the current device; gamepad jump moved to X (A = sprint).

**Milestone 3 — World expansion: DONE (v0.3.0)**
- `tools/world/gen_world.py` bakes the island (assets/world: height.bin, splat.png, nature.png, map.png, world.json):
  coastline, districts, road graph (freeway ring, avenues/streets grid, Ocean Dr, Harbor Blvd, suburbs, Canyon Rd),
  lots, heightmap with carved roads, terrain splat, vegetation density, painted map. Rerun after layout changes.
- Runtime: `WorldData` (loader), `Terrain` (streamed LOD chunks + heightmap collision), `Ocean` (waves, foam,
  swimmable), `City` + `CityCell` + `RoadNet` + `PropCatalog` (threaded cell builds, merged meshes, MultiMesh props,
  collision, occluders, far stand-ins), `LightPool` (street lights), `Weather`, custom sky shader, `FullMap` (M key).
- Districts: downtown towers/mid-rise, plaza pool, parks, fringe malls/parking/gas stations, beachfront hotels,
  boardwalk, pier, lifeguard towers, industrial warehouses, port sheds/containers/cranes, suburbs (gable-roof houses,
  driveways, yard trees), hill villas, lookout, oak/boulder scatter on the hills.
- Checks: `tests/stream_check.gd` (hitches while flying the benchmark route at 45 m/s), screenshot `tour` shots.
- Perf (software-rendered counts): street 277 draws (+699 shadow), 1.9 M prims; downtown aerial 313 (+440), 1.6 M.
  Street furniture uses baked reduced meshes; vegetation is grouped per 64 m with LODs and picture-card impostors.
- Vehicles far from the streamed area are frozen; collision always stays loaded around the player.

**Milestone 4 — Vehicles: DONE (v0.4.0)**
- 19 vehicles. Generic car pack (10 cars) + one glTF each for muscle, police, van, ambulance, box truck, bus, fire
  engine (Sketchfab CC-BY), dirt bike, bicycle, speedboat, police helicopter. `CarLibrary.SINGLE` configures each:
  scale, nose direction, wheels (node names / mesh names + hubs / cylinders cut out of a merged mesh), light meshes
  by role, glass, paintable body, light bar. Every surface gets a dentable shader (car_body.gdshaderinc).
- Handling per class (Vehicle.SPECS): mass, power, top speed, grip, suspension, drive; automatic gearbox with rpm;
  speed-sensitive steering, handbrake drifts, anti-roll; heavy vehicles slower off the line, brakes scale with mass.
- Bike (Bike): lean controller (lean for the turn the steering asks for), side stand, falls after crashes and throws
  the rider; rider pose by IK (arms to grips, legs to pegs / turning pedals). Helicopter: spin-up, hover-holding
  collective, pitch/bank/yaw, autorotating descent. Boat: floats on Ocean.wave_height (CPU mirror of the shader
  swell), stern thrust, rudder, wake.
- Lights: headlights (auto at night), tail/brake/reverse, indicators/hazards on the amber lenses (Z/X/B), emergency
  light bars + siren (tap H). Skid marks + tyre smoke. Cameras: chase / far / hood / cinematic (V), look behind (E).
- Damage (VehicleDamage): shader dents from crash jolts, smashed lamps, cracked/shattered glass, engine health →
  smoke → fire → explosion (shock wave) → burnt wreck; bullets crack glass/lights.
- Audio (Audio autoload, VehicleAudio): rpm-crossfaded engine loops, heavy diesel set, tyre squeal, horn, siren,
  indicator relay, doors, start/stop, impacts, explosions, fire; footsteps by surface, punches, splash, rain.
  `tools/audio/build_audio.py` fetches/processes the CC0/CC-BY sources into assets/audio.
- Parked cars (ParkedCars): deterministic kerb/bay slots from the road graph and car parks, spawned around the focus
  (budget by preset), paint variety, NPC drivers waiting in a few (carjackable). Idle vehicles sleep.
- Carjacking (paired Mixamo pull-out clips, retimed) and passenger-side entry (mirrored driver clips + slide over).
- Checks: vehicle_classes_check, parked_check, damage_check, audio_check, air_sea_check, bike_check, carjack_check;
  `tests/showroom.gd OUT [models]` renders every model; screenshots `parked`, `signals`, `bike`.

**Milestone 5 — Combat: DONE (v0.5.0)**
- Weapons (WeaponDefs, Weapon): fists, knife, bat, pistol, SMG, shotgun (8 pellets), assault rifle, sniper rifle
  (scope, 12° zoom), rocket launcher (Rocket projectile), grenades (Grenade rigid body, 3 s fuse, trajectory arc
  while aiming). Inventory with per-weapon magazine/reserve, reloads (upper-body clips), recoil, spread + bloom
  shown by the crosshair, hit marker, dry fire. Weapon wheel (hold Tab / LB, slow motion), wheel/D-pad cycling.
- Models: Sketchfab CC-BY/CC0 glTFs baked by tools/dev/bake_weapons.gd (xvfb) into assets/models/weapons/*.scn
  (origin at the grip, barrel -Z, Muzzle/Support markers). AimPose (SkeletonModifier) bends the spine with the aim
  pitch and places the gun on the right hand + the support target every frame; left-hand TwoBoneIK + BoneOrient
  hold long guns by the fore-end. Rifle carry/aim blend spaces mixed in by stance; upper-body OneShot layer.
- Damage: bullets traced against limbs (Pedestrian.ray_test: head ×3, limbs ×0.6, shots past the body miss),
  per-surface impacts and sounds, blood (spray, pool), ragdoll deaths pushed by the shot, knock-downs that get up,
  hit reactions, fleeing from gunfire (Game.noise_made). Explosion helper (fireball, scorch, shock wave) shared by
  vehicles, rockets and grenades. Vehicles knock people down (struck_by_vehicle) instead of stopping dead.
- Drive-by (vehicle_aim RMB/LB + vehicle_fire LMB/X): pistol or SMG out of the window, arm IK, works on bikes.
- Gun shop (GunShop, ShopMenu): walk-in store across the street from the start (lot reserved in WorldData),
  clerk, racked weapons, counter turntable preview, buy weapons/ammo/armour. Pickups (Pickup) for every weapon,
  health, armour and cash around the map. Gamepad aim assist (Game.aim_assist). Crimes are reported through
  Game.crime_committed for the wanted system.
- Checks: tests/weapons_check.gd (every weapon, head/miss, reload, knife, rocket, grenade, drive-by, pickup, shop);
  screenshots `weapons` / `wpn_<id>` (each weapon relaxed and aimed).

**Milestone 6 — Population: DONE (v0.6.0)**
- Traffic (TrafficManager + LaneGraph): AI drivers in real VehicleBody3D cars (Vehicle.ai_* inputs) spawn out of
  sight 40–130 m away; pure-pursuit lane following, speed by road class, slow for turns, stop at red/amber (signals where avenues/drives
  meet; the major road gets the longer green), give way at unsignalled junctions and when turning left, junction conflict rule, keep gaps (other traffic, box casts
  for anything else), change lanes round stopped cars, overtake on two-way streets when the oncoming lane is clear, pull over
  for sirens, indicate for turns and lane changes, honk when held up, panic at gunfire, headlights at night,
  wedged cars recycled. TrafficLights: signal heads on poles at every signalled junction near the player.
- Emergency services (EmergencyServices): ambulance for anyone dead in the street (paramedic kneels and revives),
  fire engine for burning cars (firefighter sprays them out); units drive an A* lane route with sirens,
  overtaking and running reds carefully. Crashed/burnt cars stay while a unit attends them.
- Pedestrians (Population + WalkGraph + Pedestrian): 14 Mixamo characters (7 women with female walk/idle/run),
  count by preset × district density × time of day × rain; they walk the pavements with a sideways spread, avoid
  each other and the player, wait at crossings for the cars' red (or a gap), stop for phone calls / texting /
  smoking, stand chatting in pairs, sit on benches; at trouble they cower, run (along the pavements, away),
  spread the panic, call the police (Game.police_call), and some men fight back with fists. Far ones animate at
  10 Hz. Character textures are downsized at import (tools/import/character_post_import.gd).
- Checks: lane_graph_check, traffic_check, walk_graph_check, population_check, emergency_check; screenshots `street`.

- Also in v0.6.0: WASTED screen → wake at the hospital (fee $100); hospital, police station and the respray
  garage stand as storefronts (used fully by the police in M7).

**Milestone 7 — Police: DONE (v0.7.0)**
- Wanted (scripts/police/wanted.gd): 1–5 stars from crimes an officer (on foot, in a car, the helicopter) sees
  or a witness phones in (assault, shooting, murder, theft, carjacking, hitting people, explosions; attacking /
  killing police or stealing a police vehicle always count). Response by stars: foot officers and patrol cars →
  3★ roadblocks across the road ahead of a fast player (lane_ahead along the lane graph, kerb to kerb) →
  4★ SWAT van (rifles, helmets) → 5★ helicopter (keeps 22 m over roofs, cruises high, holds above the player).
- Line-of-sight search: officers report sightings; out of sight the stars blink, the minimap shows the search
  circle round the last sighting, patrol cars cruise points inside it and officers comb the streets round it.
  Out of sight long enough (8 s + 4 s per star) and outside the circle: lost them.
- Cop (scripts/police/cop.gd): runs to the player / last sighting, shoots on sight from 2★ (or at once at an armed
  suspect), arrests an unarmed player who stands still close by (BUSTED → police station, weapons confiscated,
  $100). Officers get out of stalled or arrived cars. Uniform (scripts/police/uniform.gd): vest shrink-wrapped to
  the character's torso and skinned from it, cap / SWAT helmet, POLICE / SWAT lettering; fitted on a worker thread.
- WASTED → hospital ($100); respray garage clears the stars if nobody watched you drive in; police radio chatter
  from nearby units (tools/audio/synth_radio.py).
- Checks: tests/police_check.gd (stars, response, busted, confiscation, losing them, wasted, respray),
  tests/police_chase_check.gd (officers fire, patrol car arrives, roadblock on the road, SWAT, helicopter);
  screenshots `police` (police_hud, police_scene); tests/lineup.gd OUT police (uniforms front/back).

**Milestone 8 — UI/UX: DONE (v0.8.0)**
- Settings (scripts/ui/settings_menu.gd, scripts/core/settings.gd, GraphicsSettings): GRAPHICS (preset or every
  option: GI, AO, SSIL, SSR, fog, bloom, shadow quality/distance, model detail, AA, render scale, upscaler,
  traffic / pedestrian / parked-car counts), DISPLAY (window mode, window size, V-sync, frame cap, field of view),
  AUDIO (master, radio/music, effects, vehicles, ambience), GAMEPLAY (aim assist, blood, subtitles, HUD, invert
  look, mouse / pad sensitivity), CONTROLS (rebind every action for keyboard/mouse and gamepad separately, reset).
  Mouse, keyboard and gamepad navigable; applied at once and saved in user://settings.cfg.
- Pause menu: resume, map, settings, stats, save, load, quit to menu, quit; the controls for the current device.
  Main menu: continue (latest save), new game, load, settings, benchmark, quit. UI sounds (tools/audio/synth_ui.py).
- Save/load (scripts/core/save_game.gd): 3 slots, position, health/armour, money, weapons + ammo, stats, time of
  day and weather; refused while wanted or in a vehicle. Stats (Game.stats): time, distances, theft, shots,
  accuracy, head shots, kills, police killed, highest wanted level, busted/wasted, money earned/spent.
- GPS: road route (A* on the lane graph) to the map waypoint, drawn on the minimap and the full map, cleared on
  arrival. Map places (gun shop, respray, hospital, police) with a legend.
- Subtitles for police radio chatter (lines built from the chase: street, vehicle, sighting, backup) and
  witnesses phoning the police. Prompts follow the player's bindings. UI scales with the window (canvas_items).
- Checks: tests/ui_check.gd (rebinding, prompts, audio volume, save/load round trip, GPS, settings tabs, pause
  panels); screenshots `menu`, `pause` (+ pause_stats, settings_graphics, settings_controls), `map`.

**Milestone 9 — Interactivity & life: DONE (v0.9.0)**
- Street furniture (scripts/world/props/prop_world.gd): lamp posts, hydrants, bins, utility boxes, vending
  machines, payphones and ATMs break when hit by a car, shot, kicked or blasted; the pieces become physics debris
  (layer 32) and are tidied away later; a broken lamp's light goes out. Burst hydrants throw a water jet that
  lifts cars (hydrant_jet.gd). New CC-BY props: vending machine, ATM, payphone (Sketchfab).
- Using things (prop_use.gd): vending machine ($5, +15 health), ATM (balance; a beaten ATM spills cash),
  payphone (pay $400 per star to have one dropped), benches (sit / get up).
- Walk-in interiors (scripts/world/interiors/interior.gd + door.gd): hinged doors that swing open for the player
  and pedestrians and close behind them. The safehouse across 6th Ave (sofa, TV, kitchenette, day bed: "Sleep and
  save" passes the night, heals and opens the save slots) and the Solano Diner (counter, stools, booths, a
  waitress: $12 meal = full health). Furniture is Poly Haven CC0. The gun shop now has a pair of glazed doors.
- Collectibles (scripts/world/collectibles.gd): 30 lucky coins across all six districts (parks, plaza, pier,
  lookout, lifeguard towers, boardwalk, port, hills, suburbs), $100 each, $10,000 for the set; saved with the game
  and counted in the stats. A new game starts a fresh career (money, stats and coins reset).
- Ambient life: pigeons on the plaza, in the parks and on downtown pavements that scatter from the player and
  gunfire, circle and land again; gulls wheeling over the shore and the port (scripts/world/ambient/birds.gd, a
  procedural bird with shader wing beats); an airliner crossing the sky every few minutes with navigation lights
  and engine rumble (aircraft.gd).
- Soundscape (scripts/audio/ambience.gd, tools/audio/build_ambience.py): beds that follow the place and the hour
  (traffic where it is built up, surf near the sea, birdsong by day and crickets at night out of the centre, wind
  on the hills), gull cries, construction sites working by day, ship horns in the port, distant sirens; indoors the
  street is muffled, a room tone hums and effects get a short room reverb.
- Car radio (scripts/audio/radio.gd, tools/audio/build_radio.py): five stations — VIBE 94.1 (funk & soul),
  COSTA 101.3 (latin), THE REEF 88.5 (rock), NIGHT SHIFT 103.7 (electronic), LOW TIDE 99.9 (lounge & lo-fi) — of
  CC-BY / CC0 music, each with a synthesised ident between songs. Stations play on a shared clock (tune back in
  and the song has moved on); every vehicle keeps its station; `.` / `,` (D-pad right) steps through them and OFF.
- Checks: tests/props_check.gd (breakables, hydrant, use, sit, payphone), tests/places_check.gd (door, safehouse
  sleep, diner, coins placed on open ground, pickup, save state), tests/life_check.gd (soundscape by place and hour,
  indoors, pigeons, gulls, aircraft, radio); screenshots `interiors`.

**Milestone 10 — Polish & optimisation: DONE (v1.0.0)**
- Car doors: no model has separate doors, so CarLibrary cuts the front doors out of the body (the outer shell's
  triangles wholly inside the door box between the wheel arch and the seat, from the wheel track) and hangs them on
  a hinge; they swing open when the player gets in or out (passenger side too) and shut behind. Cab-over trucks get
  doors above the wheel arch; the bus is boarded through its front door on the kerb side, then the driver steps
  across. Closed, the cars look exactly as before. Screenshot `doors`.
- Audio mix: the car radio ducks engine and tyre sounds 5 dB while music plays (radio -16 LUFS against engine loops
  at -14..-11 LUFS); ambience beds sit around -30 LUFS under everything.
- Visual pass over every district by day, night and in rain: rain read as a bright sunlit fog (the volumetric fog
  thickens six-fold); haze and ambient light now go grey and dull with the cloud.
- Interiors: safehouse rebuilt as lounge / kitchen / bedroom (a partition, rugs, books, 18 more Poly Haven pieces;
  the old shelving model was 11 m tall), diner back bar dressed; birds rebuilt with bodies and heads, lit both
  sides; the airliner and the gulls skip occlusion culling (street occluders hid them against the sky).
- Performance: interior furniture, coins, wheels and the gun shop's racked weapons cast no shadows (start street
  2,922 draws incl. shadows, budget 3,000); radio tracks load on worker threads; birds/ambience cost timers.
- Fixes: foot IK no longer floods errors from a zero ground normal; parked cars no longer read freed cars; a coin
  that had landed inside a building moved to open ground (coins search up to 18 m for a clear spot).

- Interact uses whichever is nearer, a usable thing or a car door, and the prompt says which. Animation blends
  reviewed (every state change cross-fades 0.08-0.3 s). Full suite green (stream_check's jitter tolerance aside).

**Iteration after v1.0**
- v1.0.1: beach hotels get sea-view balconies (CityCell._balconies: slab, glass, rails, dividers on the ocean face).
  Tyres no longer sink 4 cm into the road (a fixed physics contact margin): the drawn wheel sits on a holder
  lifted 4 cm "up" in the car's frame, physics untouched (enlarging the physics radius raised the cars and made
  AI traffic roll out of lane). grounding_check measures each tyre's drawn bottom against the ground under it.
  Junctions: a car already in the junction now holds back cross traffic even when both go straight (only
  oncoming traffic could ignore it): a late car clearing on amber was being T-boned by the green side.
  Tour screenshots now wait for the city detail to finish streaming (under software rendering the cell builders
  are starved and a fixed wait showed the far stand-ins); new tour shot `tour_hotels`.
- v1.1.0: the rest of brief §4's "breakable props (… fences, … glass), pushable physics objects", which the M9
  build had only partly covered (lamps, hydrants, bins, street furniture):
  - Fences: white picket fences along every suburban front yard (gaps for the driveway and the front path, short
    side returns; CityCell._yard_fence) and Poly Haven chain-link along the industrial yards' street sides. Both are
    MultiMesh props in PropWorld.BREAKABLE: a car ploughs through, a blast tears them out; a picket bay splinters
    into its pickets and rails (PropWorld._splinter) and gives way to gunfire or blows ("tough": damage taken).
  - Glass: GlassPane (scripts/world/props/glass_pane.gd) for the diner, safehouse, gun shop and storefront
    windows: shatters when shot, punched, rammed or blasted (shard particles, breaking/falling glass sounds, a noise
    people react to), the frame is then open; glazed again 3 minutes later once the player is 45 m away.
  - Pushables (scripts/world/props/pushables.gd): crates, oil drums, cardboard boxes and plastic crates in the
    industrial yards and the port, cone lines at the quay cranes and in car parks, footballs in parks, on the beach
    and in front yards. Real rigid bodies on the debris layer, streamed in within 90 m (set out where nothing is in
    the way) and put away beyond 130 m, remembering where they were left. Walking into one shoves it at walking
    pace (a ball is dribbled), kicks and bullets push them by weight, cars and blasts throw them about; knock sounds
    by material. tests/touch_check.gd covers all three.
- v1.1.1: tools/texture_import.py now also covers `.jpeg` (≈30 Sketchfab maps — car bodies, glass, tyres, vending
  machine, ATM, knife — had shipped uncompressed, ~300 MB, without mipmaps). Full map draws district names after
  the place icons and nudges them clear. Night shop glazing dimmed (blown out under auto-exposure). Safehouse:
  reading corner, sideboard, rugs, plants, pictures. Smoke test of the export exits cleanly at ~5.5 min (llvmpipe).
- v1.1.2: gen_world.boardwalk_sand(): the splat (and vegetation, map) get sand from the beach up to the boardwalk;
  the terrain's own beach mask (which also shapes heights) is untouched, so height.bin/world.json are identical.
  The camera hides the player's body while scoped. Full screenshot review of every shot set done after v1.1.1.
- v1.1.3: swimming uses Quaternius' CC0 Universal Animation Library (assets/source/quaternius/ual_standard.glb,
  committed — CC0): Swim_Fwd (head-up surface stroke) and Swim_Idle (treading water), retargeted at import with
  assets/rigs/bonemap_rigify.tres (Rigify DEF- bones → SkeletonProfileHumanoid). AnimLib loads "ual:Clip" sources;
  NATIVE_SPEED gives the in-place stroke its travel speed (the old clip's 0.47 units/s).

**Next: keep iterating (brief §7)** — review screenshots, improve the weakest-looking areas, deepen existing
systems; act on the owner's benchmark reports from OWNER_TEST_CHECKLIST.md.

### Known issues / debt
- tests/emergency_check.gd still fails now and then (an ambulance taking a long way round or wedged before the
  out-of-sight recovery kicks in); traffic_check / police_chase_check pass 3/3 after the latest fixes.
- tests/stream_check.gd: on this 4-core software container the worst single frame varies run to run (30-100 ms,
  once 330 ms) with no script time behind it, with or without any one M9 system; p99 is a steady ~10.5 ms. The
  check tolerates up to 3 isolated spikes over 40 ms (none over 150 ms). Look again in M10 on real hardware.
- Default branch is still `claude/tmp-push-test` (proxy blocks changing it) → owner checklist item.

### Builds
| Tag | Milestone | Where |
|---|---|---|
| v0.1.0 | 1 — vertical slice (player untextured — superseded) | GitHub Release |
| v0.1.1 | 1 — vertical slice hotfix | GitHub Release (workflow runs on release.txt change) |
| v0.2.0 | 2 — player polish | GitHub Release |
| v0.3.0 | 3 — world expansion | GitHub Release |
| v0.4.0 | 4 — vehicles | GitHub Release |
| v0.5.0 | 5 — combat | GitHub Release |
| v0.6.0 | 6 — population | GitHub Release |
| v0.7.0 | 7 — police | GitHub Release |
| v0.8.0 | 8 — UI/UX | GitHub Release |
| v0.9.0 | 9 — interactivity & life | GitHub Release |
| v1.0.0 | 10 — polish & optimisation | GitHub Release |
| v1.0.1 | iteration: beachfront balconies | GitHub Release |
| v1.0.2 | iteration: tyres on the road, junction right of way | GitHub Release |
| v1.1.0 | iteration: breakable fences and windows, pushable objects | GitHub Release |
| v1.1.1 | iteration: texture compression, map labels, night shops, safehouse | GitHub Release |
| v1.1.2 | iteration: beach sand to the boardwalk, scope view | GitHub Release |
| v1.1.3 | iteration: surface swimming and treading water | GitHub Release |
