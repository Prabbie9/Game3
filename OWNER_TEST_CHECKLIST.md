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
