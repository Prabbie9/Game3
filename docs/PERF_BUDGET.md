# Performance budget (High preset, 1440p, RX 7800 XT / 7800X3D class)

Hard floor: **60 FPS (16.6 ms)** everywhere; target 90+ average (≤11 ms).
Numbers are per frame, measured from the in-game perf overlay (F3) / benchmark report.

| Metric | Budget (High) | Notes |
|---|---|---|
| Draw calls (total render pass) | ≤ 3,000 | MultiMesh for props/foliage; merged building chunks; HLOD beyond 400 m |
| Visible primitives (triangles) | ≤ 6 M | Auto-LOD on every mesh; visibility ranges |
| Shadow-casting lights | sun + ≤ 4 omni/spot | Headlights cast shadows only for the player vehicle |
| Non-shadow dynamic lights visible | ≤ 48 | Street lights fade out beyond 120 m, emissive-only beyond |
| Active rigid/vehicle bodies | ≤ 60 | Far vehicles become kinematic/frozen |
| NPC pedestrians active | ≤ 60 (≤ 20 full-rate animated) | AI LOD: 0–30 m every frame, 30–80 m every 4th frame, >80 m anim off/impostor |
| Traffic vehicles active | ≤ 35 | |
| GDScript time | ≤ 4 ms | Profiled in benchmark report |
| Physics time | ≤ 3 ms | Jolt |
| Chunk load hitch | 0 frames > 25 ms | Threaded loading only |
| VRAM | ≤ 8 GB | Texture streaming via mipmaps, VRAM compression on |

Graphics presets: Low / Medium / High / Ultra (see `scripts/core/graphics_settings.gd`).
SDFGI + volumetric fog + SSR are the expensive toggles; High enables SSAO, SSIL(half), SSR(half), SDFGI(low cascades).

## Measurements
| Date | Build | Scene | Draws (+shadow) | Primitives | Notes |
|---|---|---|---|---|---|
| 2026-10-22 | v0.1.0 | street view (software render) | 532 (+1249) | 2.26 M | palms are the main shadow-draw cost |
| 2026-10-22 | v0.1.0 | aerial | 644 (+1552) | 2.38 M | |
Real FPS: waiting for the owner's benchmark report (OWNER_TEST_CHECKLIST.md).
| 2026-10-23 | v0.3.0 | street view (software render) | 277 (+699) | 1.91 M | merged cell meshes; reduced street-prop meshes |
| 2026-10-23 | v0.3.0 | downtown aerial | 313 (+440) | 1.57 M | far cells as one-material stand-ins |
| 2026-10-23 | v0.3.0 | hills (oaks) | 172 (+163) | 0.47 M | oak/jacaranda/palm impostors beyond 130 m |
| 2026-10-23 | v0.3.0 | stream_check (headless, 45 m/s) | — | — | p99 7.7 ms, worst 17 ms main-thread frame |
