# App Store screenshots — capture guide

The carousel's job: make someone scrolling past their 500th minesweeper stop
and think *"wait, this one's different."* Lead with spectacle and breadth, then
show depth. Manual capture, demo mode (seeded data + fixed blue accent).

**Gameplay and functional UI only — no title/manga art.** Show the game, not
the packaging. **Light mode, English, one set per size** — a player deciding to
tap Get doesn't care about a screenshot's background colour or chrome language;
they care what the game is, and a board reads the same in any language. Don't
spend captures on dark or localized sets, or on the title screen.

## Workflow

1. `make demo-iphone` (or `demo-ipad` / `demo-mac`) — builds, launches the app
   in demo mode, and prints the shot list below. Mac opens at a fixed 1440×900
   window (reproducible across runs — no manual resizing).
2. Capture in the printed order: simulator **⌘S** (iOS/iPad), or **⌘⇧4-space**
   on the Mac window. Dump the raw files in one folder.
3. `Scripts/asc/organize-shots.py <iphone|ipad|mac> <folder>` renames them to
   the canonical names by capture order (no need to look at the images).
4. Hand the folder over for the ASC upload.

## Sizes

iPhone 6.9" (1320×2868) · iPad 13" (2064×2752) · Mac 1440×900.

## The shots — ordered by persuasion (the carousel shows ~3, so front-load)

1. **million-cell map** — THE opener. Start an XXL/XXXL board, open a big
   region, zoom out so the minimap + sheer scale fill the frame. Nobody expects
   this from minesweeper — lead with the spectacle.
2. **a variant board** — a **Round** (wrap-around) or **Hive** (hex) board
   mid-clear, showing the wrap or the hex numbers. The mechanical hook: "boards
   you haven't played."
3. **New Game picker** — families × sizes × edges × difficulties laid out. The
   "look how much is here" shot; proves 1–2 weren't one-offs.
4. **a clean mid-game** — a normal board part-cleared: numbers, flags, the mine
   counter and timer running. The core loop, legible. (Tap the board first — a
   blank grid shows nothing.)
5. **Service Record** — Tour of Duty, scrolled to show a pace figure and the
   Daily orders / streak section. "It tracks your skill; it has depth."
6. **daily challenge** — the calendar (via History) or the review screen. "One
   shared board a day, a reason to come back."
7. **rivalry** *(iPhone only)* — the Mess hall, rivals list + share row. Skip on
   iPad (small centred sheet, dead space) — use another board shot there.

Avoid the home/title screen in every set (the AI title art).

Optional captions (add in ASC), one concrete idea each: "A million cells." ·
"The world wraps around." · "Square, hex, flat or round." · "A new board every
day."

## After capturing

Hand over the PNGs for the ASC upload (or upload in the version's Media Manager
per size).
