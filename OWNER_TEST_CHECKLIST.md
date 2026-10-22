# Owner test checklist

Things only you can do. Each item says what to run and what to send back. Nothing here blocks development —
reply whenever convenient and the next session will act on it.

## Repository housekeeping
- [ ] **Default branch:** on GitHub open *Settings → General → Default branch*, switch it to `main`, then delete the
  branch `claude/tmp-push-test` (*Code → Branches*). The session's proxy does not allow changing the default branch or
  deleting branches.

## v0.1.0 — Milestone 1 vertical slice
Download `PortSolano-v0.1.0-windows-x86_64.zip` from the GitHub Releases page, unzip, run `PortSolano.exe`.

1. **Benchmark (most important):** main menu → *Graphics* until it says **HIGH** → *Benchmark*. It flies through the
   city for ~75 s, then writes `benchmark_<date>.txt` next to the exe. Please paste that file's contents back.
   Repeat with **ULTRA** if you have time. (Command line alternative: `PortSolano.exe -- --benchmark`.)
2. **Play** and try: walk (WASD), run (default), sprint (Shift), walk slowly (Alt), jump (Space), aim (RMB) and shoot
   (LMB) the pistol, reload (R), enter/exit the nearby cars (F), drive (W/S/A/D, Space = handbrake, L = headlights),
   F3 = performance overlay, Esc = pause menu. A gamepad should also work.
3. Tell me anything that looks wrong or feels bad, especially: feet sliding, stutters/hitches, the camera, how the car
   handles, anything that looks cheap. Rough FPS from the F3 overlay while driving around is useful too.
