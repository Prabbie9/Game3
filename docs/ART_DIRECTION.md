# Art Direction — Port Solano

**Setting:** a fictional, sun-bleached Southern-California-style coastal city (present day). Grounded and
realistic, never cartoony. References: late-afternoon LA/San Diego photography, Mediterranean-revival
stucco, palm-lined boulevards, worn asphalt, industrial docks in steel and rust.

## Districts
- **Downtown** — glass/concrete towers (10–40 floors), wide 4-lane avenues, plazas, neon at night.
- **Midtown / Old Town** — 2–6 floor brick & stucco blocks, shopfronts, awnings, alleys, fire escapes.
- **Suburbs (hills)** — single-family stucco houses, lawns, palms, winding roads uphill.
- **Docks** — warehouses, containers, cranes, chain-link, cracked concrete, sodium lights.
- **Beach** — boardwalk, sand, lifeguard towers, pier, ocean.

## Palette
- Day: warm cream/sand stucco (#E8D9C0, #D9B98F), terracotta roofs (#B5583A), sage/olive greens,
  sky-blue accents, asphalt mid-grey (#4A4A4C) bleached toward #6A6A6A in sunlight.
- Accents: teal (#2A9D8F), coral (#E76F51), signal yellow road paint (#E9C46A).
- Night: sodium orange street light (2100 K), cool moon fill (7000 K), neon magenta/cyan signs.
- UI: off-white (#F4EFE6) on deep ink (#14161A), coral highlight (#E76F51), teal secondary (#2A9D8F).
  Fonts: a condensed grotesk for headings + clean sans for body (OFL-licensed).

## Material rules
- Everything PBR (albedo/normal/roughness[/AO]); no unlit or flat-colour surfaces in shipped scenes.
- Texel density: ~512 px/m for surfaces within 10 m of the player (roads, sidewalks, building ground
  floors, props); ~128–256 px/m upper floors and distant geometry. Tiled materials use world-space UVs
  plus a macro variation / grime overlay to break repetition.
- Decals for road markings, manholes, cracks, oil stains, puddles, grime at wall bases.
- Glass: reflective, slightly blue/green, with interior-mapped rooms on building windows; ~30% of
  windows lit at night, warm and cool mix.
- Wear: nothing is perfectly clean — dirt gradients at building bases, faded road paint.

## Lighting / time of day
- Default spawn time 17:30 (golden hour). Full 24 h cycle (1 game day ≈ 48 real minutes).
- PhysicalSky-based sky with sun + moon, AgX tonemapping, auto-exposure, SDFGI (High/Ultra),
  SSAO+SSIL, SSR, volumetric fog (light haze by day, thicker coastal fog in weather).
- Weather states: clear, overcast, rain (wet roads: darker albedo, low roughness, puddle masks), fog.

## Scale & density
- Real-world metric scale: 1 unit = 1 m. Doors 2.1 m, floors 3.2 m (commercial 4 m ground floor),
  lanes 3.5 m, sidewalks 3–4 m, curbs 15 cm. Player ~1.8 m.
- Prop density targets per 100 m of street: 4–6 street lights, 6–10 trees/palms, 2 hydrants,
  3–5 bins/benches, 1–2 bus-stop/phone-booth/vending items, parked cars on ~40% of curb length.

## Asset style rules
- Realistic/semi-realistic assets only. Do not mix low-poly stylised kits (Kenney/Quaternius 3D) into the
  visible city; those sources are only for audio/UI icons or as hidden collision proxies.
- No real brands, logos or vehicle badges — invented brand names only (e.g. "Bravado"-style parody is
  avoided too; use original names: Solano Motors, Kestrel, Vireo, Calder…).
