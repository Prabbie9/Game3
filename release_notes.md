## Port Solano v0.1.1 — Milestone 1 hotfix

**Fix:** the v0.1.0 download had an untextured player character (the build server didn't pick up the character's
embedded textures). Character textures are now embedded at import time, and every build is checked for missing or
untextured assets before it is published.

Everything else is as in v0.1.0 — unzip, run `PortSolano.exe`, and see `OWNER_TEST_CHECKLIST.md` inside the zip.
The benchmark (main menu → Benchmark) is the most useful thing to send back.

**Also new:** feet plant on slopes, kerbs and steps (foot IK with pelvis adjustment), and the left hand now supports
the pistol when aiming.
