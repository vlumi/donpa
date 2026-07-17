# Demo saves (screenshot harness)

Hand-crafted in-progress games for the App Store demo, dumped from a real
played board (flags placed by hand) so the seeded "Continue" list resumes
exactly those boards.

**These are dev-only** — read via `DONPA_REPO_ROOT` when the demo scripts run,
never bundled into the shipped app.

## Regenerate
1. `make demo-mac DUMP=1`
2. Resume a board, place flags / reveal as you want it to look, then ⌘Q (or
   background it) — each board writes to `~/Desktop/donpa-demo-saves/<config>.json`.
3. Copy the JSON(s) here and commit. `DemoSeed` loads them verbatim; delete one
   to fall back to the generated board for that config.
