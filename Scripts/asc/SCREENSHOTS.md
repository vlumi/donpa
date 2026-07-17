# App Store screenshots — capture guide

The carousel's job: make someone scrolling past their 500th minesweeper stop
and think *"wait, this one's different."* Lead with spectacle and breadth, then
show depth. Manual capture, demo mode (seeded data + fixed blue accent, starts
in Light).

**Gameplay and functional UI only — no title/manga art.** Show the game, not
the packaging. The demo seeds a couple of resumable in-progress games, so a
gameplay shot is a tap on the Continue list — no live setup, identical every
launch.

## Workflow

1. `make demo-iphone` (or `demo-ipad` / `demo-mac`) — builds, launches the app
   in demo mode, and prints the annotated shot list. Mac opens at a fixed
   1440×900 window (reproducible across runs — no manual resizing).
   Pick the language with `DEMO_LANG=en|fi|ja` (default `en`), e.g.
   `make demo-mac DEMO_LANG=fi`. Each language is its own clean launch.
   **macOS accent:** the Mac uses the *system* accent for its selection/
   highlight colour, which the app can't override — set System Settings ▸
   Appearance ▸ Accent to **Blue** before shooting Mac, for consistency with
   the iOS sets. (iOS/iPad are pinned to blue by the demo automatically.)
2. Capture in the printed order: simulator **⌘S** (iOS/iPad), or **⌘⇧4-space**
   on the Mac window. **Where to put the files:** one folder per platform —
   dump every raw shot straight into it, in capture order (no subfolders; the
   organizer sorts by capture order and makes the subfolders itself).
3. The demo starts in **Light**. Shots 1–2 are the same board: shoot **big-map**
   in Light, flip Settings ▸ Appearance to **Dark**, shoot **big-map-dark**,
   flip back to Light, then carry on. Everything else is Light.
4. **Every language needs its own full set** (a JP listing must show JP
   screenshots — never English ones). Relaunch with `DEMO_LANG=fi`, then `ja`,
   and shoot the SAME shot list each time, all **back-to-back into one folder**
   in language order: en set, then fi set, then ja set.
5. Organize:
   - one language → `make asc-shots DIR=<folder> PLATFORM=mac`
   - several → `make asc-shots DIR=<folder> PLATFORM=mac LANGS=en,fi,ja`
     (splits into `<folder>/en/…`, `/fi/…`, `/ja/…`, canonically named).
6. Hand the folder over for the ASC upload.

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
