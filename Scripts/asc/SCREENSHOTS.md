# App Store screenshots — capture guide

The carousel's job: make someone scrolling past their 500th minesweeper stop
and think *"wait, this one's different."* Lead with spectacle and breadth, then
show depth. Manual capture, demo mode (seeded data + fixed blue accent, starts
in Light).

**Gameplay and functional UI only — no title/manga art.** Show the game, not
the packaging. The demo seeds a couple of resumable in-progress games, so a
gameplay shot is a tap on the Continue list — no live setup, identical every
launch.

## Workflow — one command

```sh
make shots PLATFORM=mac        # or iphone / ipad; LANGS=en,fi,ja by default
```

It builds, then for each language: launches the demo, walks the shot list —
*"stage this, press ⏎"* — and **captures each shot itself** (window grab on
Mac, `simctl` on the simulators), straight to
`shots/<platform>/<lang>/<shot>-<platform>.png`. Retake with `r`, skip with
`s`. No ⌘S, no renaming, no moving files: `shots/` is the handoff for the ASC
upload.

Before a Mac run, once:

- Set System Settings ▸ Appearance ▸ Accent to **Blue** — the Mac's selection
  colour comes from the system and the app can't pin it (iOS is pinned
  automatically).
- The first window grab asks for Screen Recording permission for your
  terminal; grant it and re-run.

During the run: the demo starts in **Light**. Shots 1–2 are the same board —
capture **big-map** in Light, flip Settings ▸ Appearance to **Dark** in-app,
capture **big-map-dark**, flip back. Every language gets the same full set, in
that language (a JP listing must never show English screenshots).

Manual fallback (freehand capture, then rename by capture order):
`make demo-mac DEMO_LANG=fi` to just launch, then
`make asc-shots DIR=<folder> PLATFORM=mac [LANGS=en,fi,ja]`.

## Demo isolation & the seeded boards

`-uitest-clean` routes **every** store (scores, rivals, daily, settings,
saves) to wiped ephemeral storage with no iCloud — demo runs can't touch real
player data. The Continue list is seeded with three fixed in-progress boards
(XXL, Hive, Beginner), so gameplay shots are a tap on Continue, identical in
every language.

To replace the generated boards with hand-staged ones (your own flag
placement): `make demo-mac`, arrange the boards in-app, quit, then
`make demo-freeze` — it copies the boards into `Scripts/asc/demo-saves/`;
commit them and every later demo launch (all platforms) resumes exactly those.

## Sizes

iPhone 6.9" (1320×2868) · iPad 13" (2064×2752) · Mac 1440×900.

## The shots — ordered by persuasion (the carousel shows ~3, so front-load)

1. **big map** — THE opener. Resume the seeded **XXL** save, zoom out so the
   minimap + sheer scale fill the frame. Nobody expects this from minesweeper
   — lead with spectacle.
2. **big map, Dark** — the same board with Appearance set to Dark: the one
   dark-mode taster, so the listing shows the app isn't light-only.
3. **a variant board** — resume the seeded **Hive** (hex) game, showing the hex
   numbers. The mechanical hook: "boards you haven't played."
4. **New Game picker** — families × sizes × edges × difficulties laid out. The
   "look how much is here" shot; proves the earlier boards weren't one-offs.
5. **a clean mid-game** — resume the seeded **Beginner** game: a normal board
   part-cleared, numbers and flags showing. The core loop, legible.
6. **Service Record** — Tour of Duty, scrolled to show a pace figure and the
   Daily orders / streak section. "It tracks your skill; it has depth."
7. **daily challenge** — the calendar (via History) or the review screen. "One
   shared board a day, a reason to come back."
8. **rivalry** *(iPhone only)* — the Mess hall, rivals list + share row. Skip on
   iPad (small centred sheet, dead space) — use another board shot there.

Avoid the home/title screen in every set (the AI title art). Every language
gets this same set, in that language.

Optional captions (add in ASC), one concrete idea each: "A million cells." ·
"The world wraps around." · "Square, hex, flat or round." · "A new board every
day."

## After capturing

Hand over the PNGs for the ASC upload (or upload in the version's Media Manager
per size).
