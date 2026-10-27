## Port Solano v1.3.0 — solid houses, smooth pavements, stunt ramps

- **Houses are solid.** The suburban houses and the hillside villas had their walls, doors and gable ends facing
  inwards, so from outside you saw straight through the near walls into the far ones. Fixed.
- **No more ledge between the grass and the pavement.** The outer edge of every pavement was a bare 15 cm step
  you had to jump; it now has a gentle invisible ramp down to the lawn, so you walk (and drive) straight on. The
  pavements' collision also follows the street's slope on hills instead of stepping, and the kerbs (junction
  corners included) have a gentle ramp up from the road, so you don't snag on them on foot.
- **Stunt ramps**, just for fun: three along Playa Solano beach, one on the sand north of the beach, one on the
  open ground by the harbour, and a gap jump out on the harbour headland (launch ramp, landing ramp). They're on the map (J),
  and God Mode can take you to them.
- **Helicopter:** the flight controls stay on screen while you fly. Climb with Space / RB, **descend with
  Ctrl or C / LB**, nose down / up with W / S (RT / LT), turn with A / D (left stick).
- **God Mode on the controller:** hold VIEW for a moment (a quick tap at the wheel still changes the camera).
- **Controller menus:** A now selects and B goes back in every menu (Godot's menu actions had no pad buttons).

## Port Solano v1.2.1 — Xbox controller

Plug in an Xbox controller (wired, or Bluetooth / wireless adapter) and play the whole game on it; prompts and
menus switch to the pad as soon as you touch it.

| On foot | | At the wheel | |
|---|---|---|---|
| Left stick | move (push lightly to walk) | Left stick | steer |
| Right stick | look | Right stick | look |
| A (hold) | sprint | RT / LT | accelerate / brake and reverse |
| X | jump, vault, climb | RB | handbrake |
| Y | enter vehicle / use | Y | get out |
| B | reload | LS (click) | horn (tap: siren on emergency vehicles) |
| LT / RT | aim / shoot | RS (click) | look behind |
| LB (hold) | weapon wheel | D-pad up | headlights |
| D-pad left / right | previous / next weapon | D-pad left / right | previous / next radio station |
| RB | take cover | A | indicator the way you're steering (centred: off) |
| LS (click) | crouch | B | hazard lights |
| RS (click) | swap shoulder | LB + X | aim and shoot from the window |
| D-pad down | map | VIEW | camera view |
| MENU | pause (God Mode is in the pause menu) | RB / LB | helicopter up / down |

- The controller rumbles when you shoot (harder for the shotgun, sniper and launcher), take a hit, crash or are
  near an explosion. Turn it off in Settings → Gameplay → Controller vibration.
- Buttons are named the Xbox way everywhere (MENU, VIEW, LS, RS); every pad button can be rebound in
  Settings → Controls.
- God Mode shows pad hints: D-pad to move and change, A to do it, LB / RB for tabs, B to close.

**Fix**
- v1.2.0 could build the same city block twice as you moved around, which spammed errors and could crash the
  game when quitting. Fixed.

## Port Solano v1.2.0 — God Mode, smoother cars and a tidier island

**God Mode** (F1, or GOD MODE in the pause menu; the game pauses while it is open)
- PLAYER: invincible, infinite ammo, never wanted, indestructible vehicle; set the wanted level; fill health and
  armour; every weapon with full ammo; +$10,000; repair the vehicle; respawn here, at the start or at the hospital.
- SPAWN: any vehicle in front of you (or spawn it and drive), a pedestrian or a police officer, crates, drums,
  boxes, cones and footballs; remove everything you spawned.
- WORLD: time of day (slider, or dawn / noon / dusk / night), freeze the clock, pick the weather.
- TELEPORT: the districts, the pier, the lookout, the hospital, the police station or your map waypoint (in a car
  you keep the car).
- DEBUG: performance overlay, game speed (25–200 %), traffic and pedestrians on or off.
- Cheats are never saved with the game.

**Getting in and out of cars, carjacking**
- No more twitching: the carjack clips had their keyframes scrambled when they were sped up, and every entry,
  exit and carjack snapped the body between clips (the hips slid up to 1.9 m sideways as the sitting pose faded
  in). The body now stays on the seat through every hand-over, rises or drops to match tall cabs and low cars,
  and steps out with the feet on the road.
- The driver you pull out stays in step with you, is dragged out and breaks into a run while still on their
  feet, instead of snapping up from the ground.
- Drivers and passengers sit inside the car: some models (the coupe most of all) had bounds nearly twice their
  real width, which put the driver's head through the door.

**The island**
- Las Lomas: houses no longer sit across streets or Ocean Drive, no fences or gates in the road, and the ground
  rises gently from the beach instead of a 10 m bank that left houses half buried and streets in trenches.
- No more roads ending at the freeway: the Sunset Ave connectors curve into the junctions, and Ocean Drive runs
  on to the northernmost Las Lomas street. Every other plot (car parks, shops, warehouses) keeps off the roads too.
- The Mirador Hills villas sit on level terraces instead of towering plinths.
- The pier's ramp is the right way round: walk or drive straight up from the boardwalk.
- Swimming works in the sea (the sea's water sat 2 m below the waves) and you can stand up again in the shallows.
- Respawning (wasted, busted, or from God Mode) is a clean start: the wanted level is cleared.

**Smoother at speed**
- Street lights no longer flicker as you drive: each light stays on its lamp, fades in and out, and far ones
  fade with distance. Far-off cars' headlights fade out instead of popping.
- The city streams ahead of you: the blocks you are driving towards load first.
- Ultra is lighter on the GPU for nearly the same picture (indirect light at half resolution like High, the
  high-quality shadow filter on the 8192 shadow map, five GI cascades instead of six).
- The benchmark report now lists the game's own CPU costs per system and every frame over 50 ms with where it
  happened: please send new reports.

## Port Solano v1.1.3 — swimming

- Swimming is a proper head-up stroke at the surface, and you tread water when you stop (it used to be an
  underwater dive pose and a float). Animations by Quaternius (CC0).

## Port Solano v1.1.2 — sand to the boardwalk

- Playa Solano is sand all the way up to the boardwalk (a strip of lawn used to separate the two).
- Looking through the sniper scope no longer shows your own shoulder and head.

## Port Solano v1.1.1 — sharper cars, clearer map, livelier rooms

- Car bodies, tyres, glass, the vending machines and the ATMs now use compressed, mip-mapped textures: they no
  longer shimmer at a distance and take far less video memory.
- The full-screen map keeps district names clear of the place icons (DOWNTOWN was hidden under them).
- Lit shops at night glow warmly with their shelves showing, instead of reading as flat white panels.
- The safehouse feels lived in: a reading corner by the bookshelf, a sideboard, rugs, plants and pictures.

## Port Solano v1.1.0 — fences, glass and things to push

- **Fences:** white picket fences now front the suburban yards, and chain-link runs along the industrial yards.
  Drive through a picket fence and it splinters into flying pickets; chain-link gets torn out by a car or a blast.
  A few rounds or a couple of punches break a picket bay too.
- **Glass:** the windows of the diner, the safehouse, the gun shop and the hospital, police station and garage
  shatter when you shoot them, punch them, ram them or blow them up. They get fixed a few minutes later.
- **Things to push:** crates, oil drums and boxes in the industrial yards and the port, traffic cones by the quay
  cranes and in car parks, footballs in the parks, on the beach and in front yards. Walk into them to shove them
  along (or dribble a ball), kick them, shoot them, drive through them. They stay where you leave them.

## Port Solano v1.0.2 — on the road

- Tyres sit on the road instead of sinking a few centimetres into it.
- Traffic no longer T-bones a car still crossing a junction on amber: cross traffic waits for the junction to
  clear before pulling away on green.

## Port Solano v1.0.1 — beachfront

- The beach hotels on Ocean Drive now have sea-view balconies on every floor: glass balustrades, dark rails and
  dividers, with shadows that give the fronts depth.

## Port Solano v1.0.0 — Milestone 10: polish

Unzip and run `PortSolano.exe`. **Esc** (START) pauses.

**Polish**
- Car doors now swing open when you get in or out (both sides), and shut behind you. Buses are boarded through
  their front door on the kerb side.
- The car radio sits over the engine: engine and tyre sounds dip while music plays.
- Rain looks like rain: a grey, dull overcast with wet streets, instead of a bright haze.
- The safehouse is a proper flat now (lounge, kitchen, a bedroom behind a partition, rugs and books); the diner's
  back bar is stocked; pigeons and gulls look like birds; the airliner shows up against the sky.
- Lucky coins are all reachable on open ground.

**Performance**
- Fewer shadow-casting objects (furniture indoors, wheels, the gun shop's wall rack): lighter frames around the
  start of the game; radio music loads in the background so getting into a car never stalls.

**Fixes**
- No more error spam from foot placement or from parked cars that had been driven away.

The whole game, milestone by milestone, is described in `PROGRESS.md`. See `OWNER_TEST_CHECKLIST.md` in the zip for
what to try and what to send back (most of all: the benchmark report from your PC). Credits: `ASSET_CREDITS.md`.

## Port Solano v0.9.0 — Milestone 9: a city you can touch and listen to

Unzip and run `PortSolano.exe`. **Esc** (START) pauses.

**Knock it over, break it, use it**
- Lamp posts, hydrants, bins, utility boxes, vending machines, payphones and ATMs break when you drive into them,
  shoot them, kick them or blow them up; burst hydrants shoot a jet of water that can lift a car.
- Buy a drink from a vending machine, check your balance at an ATM (or beat the cash out of it), sit on a bench,
  and when the police are after you, a payphone call can make a star go away, for a price.

**Places to go**
- Your safehouse is across the avenue from where you start: walk in, put your feet up, sleep through the night in
  the bed and save. The Solano Diner next door serves a meal that fixes you right up.
- Doors swing open as you walk up to them, for you and for passers-by; the gun shop has proper doors now.
- 30 lucky coins are hidden around the island, from the pier to the hilltop lookout: $100 each and a $10,000 bonus
  for finding them all. Your count is in STATS and in your saves.

**A living city**
- Pigeons peck about on the plaza and in the parks and scatter when you come close or fire; gulls wheel over the
  beach and the port; airliners cross the sky.
- The soundscape follows where you are and the hour: traffic downtown, surf on the beach, birdsong by day and
  crickets at night, wind on the hills, construction sites, ship horns, sirens across town. Indoors the street
  goes quiet and rooms have their own sound.

**Car radio**
- Five stations: VIBE 94.1 (funk & soul), COSTA 101.3 (latin), THE REEF 88.5 (rock), NIGHT SHIFT 103.7
  (electronic) and LOW TIDE 99.9 (lounge & lo-fi). Change station with `.` / `,` or D-pad right. Music by Kevin
  MacLeod (incompetech.com, CC-BY 4.0) and CC0 artists from OpenGameArt.

See `OWNER_TEST_CHECKLIST.md` in the zip for what to try and what to send back. Credits: `ASSET_CREDITS.md`.

## Port Solano v0.8.0 — Milestone 8: menus, settings and saving

Unzip and run `PortSolano.exe`. **Esc** (START) pauses.

**Settings for everything**
- Graphics: pick a preset or set each option yourself (global illumination, ambient occlusion, reflections,
  volumetric fog, shadows, anti-aliasing, render scale with FSR, model detail) plus how much traffic, how many
  people and parked cars the city has.
- Display: fullscreen, borderless or windowed, window size, V-sync, frame-rate limit and field of view.
- Audio: separate volumes for radio/music, effects, vehicles and the city ambience.
- Gameplay: aim assist, blood, subtitles, HUD on/off, invert look, mouse and gamepad sensitivity.
- Controls: rebind every action, separately for keyboard/mouse and gamepad; button prompts follow your bindings.
- The menus work with mouse, keyboard or gamepad (LB/RB switch tabs) and scale to any resolution.

**Save and load**
- Three save slots from the pause menu (on foot, with no police after you). CONTINUE on the main menu picks up the
  latest one: where you were, your money, weapons and ammo, health and armour, the time of day and the weather.
- STATS in the pause menu: time played, distances, cars stolen, shots and accuracy, head shots, kills, highest
  wanted level, times busted and wasted, money earned and spent.

**Finding your way**
- Set a waypoint on the map (M) and a GPS route along the roads appears on the minimap and the map.
- The map marks the gun shop, the respray garage, the hospital and the police station, with a legend.

**Also**
- Subtitles for the police radio and for witnesses calling the police.
- Menu sounds.

See `OWNER_TEST_CHECKLIST.md` in the zip for what to try and what to send back. Credits: `ASSET_CREDITS.md`.

## Port Solano v0.7.0 — Milestone 7: police

Unzip and run `PortSolano.exe`. **Esc** lists all controls.

**Five stars of trouble**
- Commit a crime in front of an officer (or where a witness can phone it in) and the stars appear: shooting,
  fighting, killing, stealing or jacking cars, running people over, explosions. Attacking the police, or taking
  one of their cars or the helicopter, always counts.
- The response grows with every star: officers on foot and patrol cars with sirens, then roadblocks across the
  road ahead of you, a SWAT van with rifle teams, and at five stars the police helicopter overhead.
- Officers wear uniforms (cap and duty vest; SWAT in helmets and black vests) and chat on the radio.

**Losing them**
- Get out of sight: the stars blink and the minimap shows the search area round where you were last seen.
  Patrol cars cruise it and officers comb the streets. Stay hidden outside the circle and they give up.
- Or drive into the respray garage (RESPRAY sign, east of the start): $100 for new paint and repairs, and the
  police lose track of you if nobody saw you go in.

**Busted and wasted**
- With one to three stars and no gun in your hand, an officer who reaches you makes an arrest: BUSTED, you walk
  out of the police station without your weapons. With a gun out, they shoot.
- Dying shows WASTED and you come round at the hospital. Each costs $100.

See `OWNER_TEST_CHECKLIST.md` in the zip for what to try and what to send back. Credits: `ASSET_CREDITS.md`.

## Port Solano v0.6.0 — Milestone 6: population

Unzip and run `PortSolano.exe`. **Esc** lists all controls.

**Streets that are alive**
- Traffic drives the roads: cars, vans, trucks and buses keep to their lane, stop at red lights, give way at
  junctions, keep their distance, indicate and change lanes round obstacles, overtake slow vehicles when the road
  ahead is clear and honk when you hold them up. At night they drive with their lights on.
- New traffic lights hang over the downtown junctions and cycle green, amber, red.
- Fourteen different people walk the pavements, more downtown and by the beach, fewer in the hills, at night or in
  the rain. They wait for the green man (or a gap) at crossings, chat in pairs, take phone calls, text, smoke and
  sit on benches.

**People react**
- Gunfire, explosions and bodies send people running along the pavements, cowering against walls or crouching
  with their hands over their heads. Panic spreads to the people around them. Some pull out their phones and call
  the police; some men put up their fists if you hit them.
- Drivers slam on the brakes or flee when shooting starts, and pull over for sirens.

**Emergency services**
- Kill someone and an ambulance arrives with its siren on; the paramedic kneels by the body and may bring them
  back. Set a car on fire and a fire engine comes, and its crew puts the fire out.

**Also**
- Dying now shows WASTED and you come round outside the hospital ($100 fee).
- Officers at the wheel of police cars wear a uniform (cap and duty vest), ready for the police in the next build.
- The fire engine's front wheels no longer leave a gap in the wheel arch; every gun now plays its shot sound.

See `OWNER_TEST_CHECKLIST.md` in the zip for what to try and what to send back. Credits: `ASSET_CREDITS.md`.

## Port Solano v0.5.0 — Milestone 5: combat

Unzip and run `PortSolano.exe`. **Esc** lists all controls.

**Ten ways to settle an argument**
- Fists, knife, baseball bat, pistol, SMG, pump shotgun, assault rifle, sniper rifle (with a scope), rocket
  launcher and grenades. Hold **Tab** (LB on a pad) for the weapon wheel — time slows while you choose — or roll
  the mouse wheel / D-pad.
- Every gun has its own sound, recoil, spread (the crosshair opens up as you fire), magazine and reload. Grenades
  show their arc while you aim. Rockets leave a smoke trail and explode on impact.
- Long guns are held with both hands, and the body bends to follow your aim up and down.

**Hits that land where you aim**
- Shots are checked against the body, so head shots do triple damage and a bullet past the shoulder misses.
- People flinch, run from gunfire, get knocked down by cars and explosions (and get back up), and fall limp when
  they die. Impacts spark, chip or splash differently on metal, concrete and flesh.
- Explosions throw cars and people and leave scorch marks; burning cars set off their neighbours.

**Shopping and scavenging**
- The gun shop is across the street from where you start: walk in, step up to the counter and press **F** to buy
  weapons, ammo and body armour (the weapon you browse turns on the counter).
- Weapons, health, armour and cash lie around the city, the beach, the docks and the hills.

**Shooting from vehicles**
- In a car or on a bike, hold **RMB** (LB) to lean out with a pistol or SMG and **LMB** (X) to fire.

See `OWNER_TEST_CHECKLIST.md` in the zip for what to try and what to send back. Credits: `ASSET_CREDITS.md`.

## Port Solano v0.4.0 — Milestone 4: vehicles

Unzip and run `PortSolano.exe`. **Esc** lists all controls; **F** gets in and out of anything with a seat.

**Something for every road (and the sea and sky)**
- 19 vehicles: compact, hatchback, sedan, estate, coupé, sports car, muscle car, SUV, minivan, pickup, off-roader,
  van, box truck, town bus, police cruiser, ambulance, fire engine, dirt bike, bicycle, speedboat and a police
  helicopter. Every one can be entered and driven, each with its own weight, power and handling.
- Parked cars line the streets and fill the car parks in many colours; now and then someone waits at the wheel
  with the engine running.
- **Carjacking:** walk up to an occupied car and press F to pull the driver out and take it. Cars can also be
  entered through the passenger door (you slide across).
- Bikes lean into corners and throw you off if you hit something. The bicycle is pedalled.
- The speedboat floats on the waves (moored by the pier); the helicopter waits in the south car park:
  Space/Ctrl climb and descend, W/S pitch, A/D turn.

**Damage you can see**
- Crashes dent and crumple the body where you hit, smash lamps, crack glass and hurt the engine. A wrecked engine
  smokes, catches fire and explodes, leaving a burnt-out shell. Bullets crack glass and break lights.

**Lights, sound, cameras**
- Indicators (Z / X), hazards (B), headlights (L), horn (H); emergency vehicles: tap H for siren and light bar.
- Engine sound that follows the revs, tyre squeal, crashes, doors, sirens, the indicator click — plus footsteps on
  every surface, punches, splashes and rain.
- Vehicle cameras (V): chase, far chase, hood and a new cinematic view; E looks behind.

See `OWNER_TEST_CHECKLIST.md` in the zip for what to try and what to send back. Credits: `ASSET_CREDITS.md`.

## Port Solano v0.3.0 — Milestone 3: world expansion

Unzip and run `PortSolano.exe`. **M** (or D-pad down) opens the map; **Esc** lists all controls.

**A whole island to explore**
- Six districts on a ~2 km island: Downtown's towers, the Playa Solano beach with a boardwalk, pier and lifeguard
  towers, the Port of Solano (container yard, gantry cranes, sheds), Eastside warehouses, the Las Lomas suburbs and
  the oak-covered Mirador Hills with Canyon Road up to a lookout.
- A road network with a six-lane freeway ring, avenues, Ocean Drive, Harbor Blvd and winding hill roads.
- Terrain, beaches and a living ocean with waves, shoreline foam and clear shallows.
- Everything streams in around you while you drive; distant areas stay visible as simplified skyline.

**Time and weather**
- Day and night (a full day is 48 minutes) with a new sky, clouds, stars, lit windows and street lights.
- Weather that changes on its own: clear, cloudy, overcast, rain (wet, reflective streets), storms with
  lightning, and fog.

**Also**
- Full-screen map with district names and waypoints (shown on the minimap).
- The benchmark now flies across the whole island at speed.

See `OWNER_TEST_CHECKLIST.md` in the zip for what to try and what to send back.
