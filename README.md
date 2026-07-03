# Donpa Squad

[![CI](https://github.com/vlumi/donpa/actions/workflows/ci.yml/badge.svg)](https://github.com/vlumi/donpa/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/vlumi/donpa/branch/main/graph/badge.svg)](https://codecov.io/gh/vlumi/donpa)

**Donpa Squad** (ドンパ隊) — a manga-styled Minesweeper for Apple platforms
(iOS 16+ and macOS 14+). Classic mode shipped first, and the "epic" variants it
was architected for are landing on schedule: huge zoomable maps, **Round
(torus) edges**, and **hex grids** (the Hive family) — each added without
touching the game logic.

**v0.1.0** (classic mode) and **v0.2.0** (big boards + cross-device sync) shipped
to TestFlight; **v0.3.0** (board variants + the config/scoreboard redesign) is
feature-complete on `main`, awaiting a release build. See
[CHANGELOG.md](CHANGELOG.md) for the version history, [ROADMAP.md](ROADMAP.md) for
the path to v1.0, and [ARCHITECTURE.md](ARCHITECTURE.md) for the key design
decisions.

## Contents

- [Board families](#board-families)
- [Controls](#controls)
- [Start and end of a game](#start-and-end-of-a-game)
- [Scores](#scores)
- [Settings](#settings)
- [AI assistance](#ai-assistance)
- [Version history](#version-history)
- [Development](#development)
- [License](#license)

## Board families

A **Basic / Grid / Hive** switch in the **New Game popup** chooses the board
family (open it from the title art, the in-game **config badge**, the result
screen, or `⌘N`):

- **Basic** — the original Beginner / Intermediate / Expert presets.
- **Grid** — square cells (eight neighbours); pick a **Difficulty** and a
  **Size**, plus the board's **Edges**: **Flat** (a map with edges) or **Round**
  (the world curves back — a torus that scrolls seamlessly in every direction).
- **Hive** — hexagonal cells (six neighbours), same Difficulty / Size / Edges
  axes; each tier carries a touch more mines than Grid so the difficulty matches.

The Grid/Hive size ladder runs XS / S / M / L / XL / XXL / XXXL as powers of two
(8² up to 1024² = a million cells); the larger boards are panned and zoomed, with
a minimap for navigation. Difficulty is mine density (the deliberately brutal top
tier is near-unguessable), so it composes with any size. Each tier carries its
**military rank insignia** — chevron stripes for the lower ranks, a star, then a
star-in-laurel for the apex. The chosen family and selections are remembered.

The difficulty and size rows are a horizontal **carousel**: scroll/swipe (or
click) to pick, with a line below the selection showing the board facts and a
short flavour tagline.

On macOS the popup is keyboard-drivable: **↑/↓** move between the rows (Family /
Difficulty / Size / Edges), **←/→** cycle the selection within the highlighted
row, **Return** starts, **Esc** closes.

## Controls

A **toggle** in a thumb-reachable corner of the board switches a tap/click
between **Dig mode** and **Flag mode**, so you can place flags without risking an
accidental reveal. Its corner follows the **Toggle side** setting (left/right)
for your grip. A tap on a revealed number always chords in either mode, and a
long-press is always the opposite primary action.

The board chrome is split in two: a thin top strip shows a tappable **config
badge** (the current game's rank insignia + size, which opens the New Game popup)
and read-only metrics — flag counter, live **clear-%**, timer, and the 🎖️ High
Scores button — while a strip beside or below the board holds the **Retry / Pause /
Home** actions plus the dig/flag toggle. Unopened tiles carry a faint manga
screentone keyed to the toggle (dots for dig, hatch for flag).

| Action            | Dig mode      | Flag mode     |
| ----------------- | ------------- | ------------- |
| Tap/click hidden  | Reveal        | Flag / unflag |
| Tap/click number  | Chord         | Chord         |
| Long-press hidden | Flag / unflag | Reveal        |

| Other           | iOS   | macOS                          |
| --------------- | ----- | ------------------------------ |
| Flag (any mode) | —     | Right-click or Control-click   |
| Pan             | Drag  | Two-finger scroll / click-drag |
| Zoom            | Pinch | Pinch (trackpad) or ⌘-scroll   |

On macOS the pointer reflects the mode while a game is in progress — a pointing
hand to dig, a flag to flag (a plain arrow otherwise); holding **Control** shows
the other mode's cursor, since Control-click does the opposite action. Panning is
bounded to the board: it rests with a little breathing room past each edge, and
pulling further rubber-bands with resistance before springing back. When the
whole board already fits on screen, panning is disabled. A **Round** board has
no edges to hit — it pans forever, and the minimap's "you are here" box splits
across the seam.

### Keyboard shortcuts

| Key      | Action                                             |
| -------- | -------------------------------------------------- |
| Space    | Toggle mode while playing                          |
| Esc      | Pause / resume; close a popup or the result panel  |
| ⌘N       | New Game (opens the config popup, macOS menu)      |
| ⌘R       | Restart with the same setup (macOS menu)           |
| ⌘T       | Return to the title screen (macOS menu)            |
| ⌘F       | Toggle mode (macOS menu)                           |
| ⌘⇧S      | High Scores (macOS menu)                           |
| ⌘,       | Settings (macOS app menu)                          |
| ⌘+ / ⌘−  | Zoom the board in / out (also ⌘-scroll)            |
| ⌘0       | Toggle the minimap between small and large         |
| ⌘1/2/3   | Basic presets: Beginner / Intermediate / Expert    |

## Start and end of a game

The app opens on a **title screen** that doubles as the home hub: tapping the
art opens the **New Game popup** to pick a board and start. The 🎖️ High Scores,
⚙️ Settings, and ⓘ About buttons sit on the art's corner. You can return to the
title any time from the in-game **Home** button or the **Title Screen** menu item
(⌘T) on macOS.

When a game ends, a comic **result panel** slides in over the **board** — a
triumphant one on a win, a dramatic one on a loss, with a "new record" flourish
when you beat your best time. It dims only the board, so the control strip stays
live:

- **Retry / Home** (and the config badge for a different game) remain usable on
  the chrome — no need to dismiss the panel first. Retry starts a fresh game with
  the same setup (new mines); the config badge opens the New Game popup.
- Dismiss the panel to inspect the finished board via the **X**, a tap anywhere,
  or **Esc**.

## Scores

The 🎖️ button (in the top strip in-game, or on the title art) opens the
**Service Record**: per-board records — best time, games cleared, and best
cleared-% from losses — plus lifetime career totals (games, tiles, flags, mines,
playtime). The row for the board you're playing is highlighted, and a new best is
celebrated on the result panel (with the improvement over your old record).

Scores live locally (via `UserDefaults`) and can optionally sync across your
devices with **iCloud** — an opt-in toggle in the Service Record footer, off by
default. Synced devices merge their records for display while each device keeps
ownership of its own history; the reset action then offers a true cross-device
erase (a device that was offline during the wipe clears itself when it
reconnects). With sync off, everything stays on-device.

Stats are keyed by board geometry, not by tier name, so the format stays stable
across variants: every family × edges combination — and any re-tuned tier — gets
its own scoreboard entries rather than reinterpreting existing scores.

## Settings

The ⚙️ button opens settings (⌘, on macOS):

- **Appearance** — **System**, **Light**, or **Dark**; the board and chrome share
  one palette that follows the choice (System tracks the OS).
- **Toggle side** — which corner the dig/flag toggle hugs (left/right), for your
  grip.
- **Language** — follow the system, or force English / Finnish / Japanese.

All selections are saved between launches.

## AI assistance

Donpa Squad is built with substantial AI assistance, stated openly rather than
hidden. The project is human-directed — design, gameplay, and every visual
decision are the author's — but the **code is largely AI-written** and the
**current scene art (title, result, pause panels) is AI-generated** (DALL·E). The
procedural visuals (app icon, manga UI glyphs, board screentone) are AI-*written
code*, not generated images. If commissioned art replaces the generated pieces
later, this note will credit it.

## Version history

High-level only — see [CHANGELOG.md](CHANGELOG.md) for the full detail. Donpa is
in TestFlight beta; releases ship as rolling per-platform betas on iOS and macOS.

### 0.3.0 — board variants & the config redesign

- **New:** **Hive (hex) boards** — a six-neighbour hexagonal grid alongside the
  square **Grid**, in both flat and wrapped edges (a hex torus that scrolls
  seamlessly in every direction).
- **New:** **Round (torus) boards** — an edges toggle where the board wraps, so
  panning off one side flows in from the other, forever. Scores are kept separate
  from Flat boards.
- **Changed:** the New Game screen is organized by **board family — Basic / Grid /
  Hive** (classic presets / square / hex), each with a **Flat / Round** edge
  toggle and its own remembered size and difficulty. It adapts to the screen: a
  swipe-pager on a phone, a family sidebar on iPad and Mac.
- **New:** the **Service Record** gained Family and Flat/Round filters and
  **expandable per-board records** — tap any board to see its own games, wins,
  best five times (with dates), and full career stats, shown the same way as your
  lifetime totals.
- **Changed:** board sizes rebalanced to powers of two (up to 1,000² = a million
  cells) and difficulty tiers re-tuned so the five ranks stay distinct on big
  boards. This resets all existing scores — a one-off clean slate before 1.0.
- **New:** a cross-device **erase** that stays erased (an offline device clears
  itself on reconnect instead of resurrecting old scores).
- **Fixed:** offline sync updates promptly, the minimap shows/hides reliably and
  follows light/dark changes, and the top status bar reads clearer.

### 0.2.0 — cross-device sync & big boards

- **New:** iCloud cross-device sync for high scores and career totals (opt-in,
  off by default; conflict-free, degrades to local-only when signed out).
- **New:** lifetime career stats (games, tiles, flags, mines, playtime) in a
  reworked one-sheet Service Record.
- **New:** bigger Modern boards — the size ladder now runs XS to XXXL (up to a
  million cells), panned/zoomed with a resizable corner minimap you can tap or
  drag to jump around.
- **New:** the New Game difficulty/size pickers became a swipeable carousel; a
  resumed game restores your camera position; macOS gained mouse/keyboard zoom.
- **New:** an over-flagged number (more flags around it than its count) gets a
  faint ring — a quiet nudge that you've slipped, without saying which flag.
- **Changed:** huge boards stay responsive (reveal, mine placement, and the
  minimap compute off the main thread; the first tap is always instant).
- **Fixed:** the cleared-% and loss "best %" now floor consistently; flags
  survive a loss; correctly-flagged mines don't detonate.

### 0.1.0 — first release

- Classic Minesweeper on iOS and macOS: first-click safety, flood-fill reveal,
  flagging, and chording, with a dig/flag input-mode toggle.
- Two board modes — **Classic** (Beginner / Intermediate / Expert) and
  **Modern** (a difficulty × size grid), chosen in the New Game popup.
- A SpriteKit board with pan/zoom, a manga theme (comic result, pause, and title
  panels), and a procedural detonating-mine app icon.
- Per-board best times + games-cleared stats, autosave/resume, pause, light/dark
  appearance, haptics, and an About screen.

## Development

The codebase is mostly a Swift package (`Packages/DonpaCore`): a pure
`DonpaCore` logic target with zero UI imports (fully tested) and a `DonpaKit`
SpriteKit + SwiftUI target on top; thin iOS/macOS app shells host it. All board
variation is isolated behind two seams — **`Topology`** (logical neighbours:
square ↔ hex, bounded ↔ wrapped) and **`CellLayout`** (coordinate → pixel) — so
new board types land as new conformers without touching the game logic.
[ARCHITECTURE.md](ARCHITECTURE.md) covers the load-bearing decisions and
[AGENTS.md](AGENTS.md) the conventions, build commands, and asset pipeline.

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`); the `.xcodeproj` is generated, not checked in. A
`Makefile` drives everything from the command line:

```sh
make            # list the available targets
make run-mac    # build + launch the macOS app
make run-ios    # build + launch in an iOS simulator
make test       # run the package logic tests (no Xcode project needed)
make uitest     # run the iOS UI tests in a simulator (local only; not on CI)
```

No third-party runtime dependencies (nothing ships in the app; SwiftLint /
swift-format are dev-only tools, not SPM packages). CI runs SwiftLint (pinned) +
swift-format, the logic tests (with coverage), and both platform builds.

## License

Code: [MIT](LICENSE). The **name and brand assets** ("Donpa Squad" / ドンパ隊, the
icon, and the artwork) are reserved and **not** covered by the MIT grant — see
[TRADEMARKS.md](TRADEMARKS.md). In short: fork the code freely, but a public fork
needs its own name and branding.
