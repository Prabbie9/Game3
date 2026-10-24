# Owner test checklist

Things only you can do. Each item says what to run and what to send back. Nothing here blocks development —
reply whenever convenient and the next session will act on it.

## Repository housekeeping
- [ ] **Default branch:** on GitHub open *Settings → General → Default branch*, switch it to `main`, then delete the
  branch `claude/tmp-push-test` (*Code → Branches*). The session's proxy does not allow changing the default branch or
  deleting branches.

## Optional: two Mixamo clips that would make swimming look better
The shared Mixamo folder has no surface-swimming or treading-water animation, so swimming currently uses "Swimming
Underwater" and "Floating". If you can, download **"Treading Water"** and **"Swimming"** (the freestyle one) from
mixamo.com (FBX, *Without Skin*, 30 fps) into the Drive folder's animations — the next session will pick them up.

## v0.9.0 — Milestone 9 interactivity & life
- [ ] Drive into lamp posts, hydrants and bins; shoot a vending machine; kick a bin. Do the pieces fly about
      believably? Park on a burst hydrant's jet.
- [ ] Use a vending machine, an ATM, a bench (sit, then move off) and, with a star or two, a payphone.
- [ ] Walk into the safehouse (across the avenue from the start): do the doors open smoothly? Sleep in the bed and
      save. Have a meal at the Solano Diner next door. Do the rooms look and sound like rooms (muffled street,
      slight echo)?
- [ ] Look for lucky coins (gold glints, 30 in all): any you can't reach or that sit inside something?
- [ ] Listen around the island: traffic downtown, surf on the beach, gulls, birdsong by day, crickets at night out
      of town, construction near the cranes, ship horns at the port. Anything too loud, too quiet or repetitive?
- [ ] Pigeons on the plaza and in the parks: walk up to them or fire a shot. Watch the sky for an airliner.
- [ ] Car radio: `.` and `,` (D-pad right) change station. Are the stations balanced in volume against the engine?

## v0.8.0 — Milestone 8 menus, settings, saving
- [ ] Settings → Display: try windowed / borderless / fullscreen and a few window sizes. Does the UI scale well on
      your monitor (and on 1440p/4K if you have one)?
- [ ] Settings → Graphics: switch presets and single options; does anything fail to change or look broken?
- [ ] Settings → Controls: rebind a key and a gamepad button, then check the pause-menu controls list. Reset.
- [ ] Save in slot 1 somewhere away from the start, quit to the menu, CONTINUE: same place, money, weapons, time?
- [ ] Set a waypoint on the map and drive along the GPS line. Does it pick sensible routes?
- [ ] Gamepad only: can you reach everything in the menus with the D-pad, A, B, LB/RB?

## v0.7.0 — Milestone 7 police
- [ ] Fire a gun near a police officer: one or two stars, officers and a patrol car arrive. Holster (mouse wheel to
      fists) and stand still next to an officer: BUSTED, you leave the police station without weapons.
- [ ] Get to three stars and drive fast down an avenue: is there a roadblock ahead? Does it look believable?
- [ ] Keep going to five stars: SWAT van, then the helicopter. Does the helicopter follow you well (it should stay
      above roofs)?
- [ ] Lose the police: get out of sight, outside the circle on the minimap. Does it take about the right time?
- [ ] Respray (east of the start, green RESPRAY sign) with stars while nobody watches.
- [ ] Do the uniforms look right up close (vest following the body, cap/helmet on the head)? Screenshot if not.
- [ ] Frame time in a five-star chase (F3) on Medium/High.

## v0.6.0 — Milestone 6 population
- [ ] **Benchmark** on HIGH and paste the report: traffic and pedestrians now spawn along the route, so this is
      the first build where the CPU is busy. Also note the frame time standing at a busy downtown junction (F3).
- [ ] Watch a signalled junction for a minute: do cars stop for red, turn sensibly, and not crash into each
      other? Report anything odd (cars stuck, driving through each other, wrong side of the road).
- [ ] Walk downtown: enough people? Too many look alike? Do they cross at the zebra crossings with the signals?
- [ ] Fire a gun in a crowd: people run, cower, call the police; a driver panics. Punch a man: does he fight back?
- [ ] Kill someone and wait: an ambulance should come with its siren on. Set a car on fire: a fire engine comes.
- [ ] Settings → Graphics: try LOW and ULTRA — traffic and crowd sizes scale with the preset.

## v0.5.0 — Milestone 5 combat
- [ ] Hold Tab (LB): the weapon wheel opens, time slows, mouse/right stick picks; does it feel quick enough?
- [ ] Walk into the gun shop across the street from the start, press F at the counter, buy a rifle and armour.
- [ ] Aim each gun (RMB/LT): both hands on long guns, body follows the aim up/down, gun not clipping the face.
      Send a screenshot of anything that looks off (wrist angles on the fore-end were tuned blind).
- [ ] Fire every gun: sound, recoil and crosshair spread feel right? Sniper scope zoom and mouse speed OK?
- [ ] Shoot a pedestrian on the plaza in the head / body / past the shoulder; ragdoll, blood pool, others run.
- [ ] Throw a grenade (the arc shows while aiming), fire a rocket at a parked car: blast, scorch, chain fires.
- [ ] In a car/bike: hold RMB (LB) and fire with LMB (X) out of the window. Pad users: is LB/X comfortable?
- [ ] Drive into a pedestrian (they should be thrown and get back up if they survive).
- [ ] GPU frame time while lots is going on (explosions + smoke) on Medium/High.

## v0.4.0 — Milestone 4 vehicles
Download `PortSolano-v0.4.0-windows-x86_64.zip` from the Releases page, unzip, run `PortSolano.exe`.

1. **Benchmark:** Graphics HIGH → Benchmark and paste the report (parked cars now line the route).
2. **Drive a few classes** near the start: sedan, sports car, muscle car (south), police cruiser (west; tap H for the
   siren), ambulance, fire engine, the bus, the dirt bike and bicycle on the pavement. Tell me which ones feel
   wrong (too twitchy, too slow, rolls over too easily, brakes too hard).
3. **Crash something** into a wall a few times: does the damage look right? Keep going until it burns and blows up.
4. **Sound:** is the engine believable when you rev and change gear? Too loud/quiet relative to everything else?
5. **Carjack** a car with someone at the wheel (they wait in some parked cars, engine running): walk to the driver's
   door and press F.
6. **Helicopter** (south car park, east end; open the map, M): Space climbs, Ctrl descends, W/S pitch, A/D turn.
   **Boat**: moored at the end of the pier on the beach. How do they feel?

## v0.3.0 — Milestone 3 world expansion
Download `PortSolano-v0.3.0-windows-x86_64.zip` from the Releases page, unzip, run `PortSolano.exe`.

1. **Benchmark (most important):** Graphics HIGH → Benchmark. The flight now crosses the whole island at speed
   (downtown, freeway, beach, port) for 90 s. Paste the report — especially the "1% low" and any hitches you saw.
2. Explore: **M** (or D-pad down) opens the full map — right-click sets a waypoint, which shows on the minimap.
   Districts: Downtown, Playa Solano beach (pier, boardwalk), Port of Solano (cranes, containers), Eastside
   warehouses, Las Lomas suburbs, Mirador Hills (Canyon Road up to the lookout).
3. Time passes (a full day takes 48 minutes) and the weather changes on its own (clouds, overcast, rain, storms,
   fog). Tell me if night is too dark/bright, if street lights look right, and how rain looks.
4. Drive the freeway fast: any stutter when new areas load in? Anything popping in late or missing?

## v0.2.0 — Milestone 2 player polish
Download `PortSolano-v0.2.0-windows-x86_64.zip` from the Releases page, unzip, run `PortSolano.exe`.
Esc shows all controls for keyboard or gamepad.

1. **Benchmark** again (main menu → Graphics HIGH → Benchmark) and paste the report — this build has more props.
2. Try the new moves and tell me anything that looks or feels off:
   - **Space at a wall/fence/bench:** low fences and barriers are vaulted, chest-high walls climbed, walls up to
     ~2.4 m jumped at and climbed. Is the hand placement convincing? Does anything clip or snap?
   - **C** crouch, **Q** take cover against a wall (A/D slides along it, Q or move away to leave).
   - Mouse wheel switches to **fists**; LMB punches (three-hit combo).
   - The **pool** in the palm plaza (the blue square on the minimap): jump in, swim, climb out at the edge.
   - Jump off something high (or drive up and bail out) to see the ragdoll fall and get-up.
   - Run and let go of the keys (skid stop); from standing, press the opposite direction (turn on the spot).
3. Camera: does it feel smooth in vaults/climbs, sprinting and when backed against a wall?

## v0.1.1 — Milestone 1 vertical slice (use v0.1.1, not v0.1.0: v0.1.0 has an untextured player)
Download `PortSolano-v0.1.1-windows-x86_64.zip` from the GitHub Releases page, unzip, run `PortSolano.exe`.

1. **Benchmark (most important):** main menu → *Graphics* until it says **HIGH** → *Benchmark*. It flies through the
   city for ~75 s, then writes `benchmark_<date>.txt` next to the exe. Please paste that file's contents back.
   Repeat with **ULTRA** if you have time. (Command line alternative: `PortSolano.exe -- --benchmark`; the report is written next to the exe.)
2. **Play** and try: walk (WASD), run (default), sprint (Shift), walk slowly (Alt), jump (Space), aim (RMB) and shoot
   (LMB) the pistol, reload (R), enter/exit the nearby cars (F), drive (W/S/A/D, Space = handbrake, L = headlights),
   F3 = performance overlay, Esc = pause menu. A gamepad should also work.
3. Tell me anything that looks wrong or feels bad, especially: feet sliding, stutters/hitches, the camera, how the car
   handles, anything that looks cheap. Rough FPS from the F3 overlay while driving around is useful too.
