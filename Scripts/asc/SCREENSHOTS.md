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
2. Capture in the printed order: simulator **⌘S** (iOS/iPad), or **⌘⇧4-space**
   on the Mac window. **Where to put the files:** one folder per platform is
   enough — dump every raw shot straight into it (subfolders aren't needed;
   the organizer sorts by capture order, so just don't reorder them).
3. The demo starts in **Light**: shoot the full set in Light. Then, for one
   dark-mode taster, switch to **Dark** (in-app Settings ▸ Appearance) and
   re-shoot just shot 1 (big-map) — a full dark set isn't worth the effort.
4. **Languages:** to ship localized shots, relaunch with `DEMO_LANG=fi` (then
   `ja`) and shoot each language's full set **back-to-back into the same
   folder** — en set, then fi set, then ja set, in order.
5. Organize:
   - one language → `make asc-shots DIR=<folder> PLATFORM=mac`
   - several → `make asc-shots DIR=<folder> PLATFORM=mac LANGS=en,fi,ja`
     (splits into `<folder>/en/…`, `/fi/…`, `/ja/…`, canonically named).
6. Hand the folder over for the ASC upload.

## Sizes

iPhone 6.9" (1320×2868) · iPad 13" (2064×2752) · Mac 1440×900.

## The shots — ordered by persuasion (the carousel shows ~3, so front-load)

1. **million-cell map** — THE opener. Resume the Grid save (or start an
   XXL/XXXL board), open a big region, zoom out so the minimap + sheer scale
   fill the frame. Nobody expects this from minesweeper — lead with spectacle.
2. **a variant board** — resume the seeded **Hive** (hex) game, showing the hex
   numbers. The mechanical hook: "boards you haven't played." (Or start a
   **Round** wrap-around board if you'd rather show the wrap.)
3. **New Game picker** — families × sizes × edges × difficulties laid out. The
   "look how much is here" shot; proves 1–2 weren't one-offs.
4. **a clean mid-game** — resume the seeded **Beginner** game: a normal board
   part-cleared, numbers and flags showing. The core loop, legible.
5. **Service Record** — Tour of Duty, scrolled to show a pace figure and the
   Daily orders / streak section. "It tracks your skill; it has depth."
6. **daily challenge** — the calendar (via History) or the review screen. "One
   shared board a day, a reason to come back."
7. **rivalry** *(iPhone only)* — the Mess hall, rivals list + share row. Skip on
   iPad (small centred sheet, dead space) — use another board shot there.

Avoid the home/title screen in every set (the AI title art). Shoot the set in
Light; add one Dark re-shoot of shot 1 (big-map) as a dark-mode taster.

Optional captions (add in ASC), one concrete idea each: "A million cells." ·
"The world wraps around." · "Square, hex, flat or round." · "A new board every
day."

## After capturing

Hand over the PNGs for the ASC upload (or upload in the version's Media Manager
per size).
