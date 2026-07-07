# Donpa Squad

[![CI](https://github.com/vlumi/donpa/actions/workflows/ci.yml/badge.svg)](https://github.com/vlumi/donpa/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/vlumi/donpa/branch/main/graph/badge.svg)](https://codecov.io/gh/vlumi/donpa)

**Donpa Squad** (ドンパ隊) — a manga-styled Minesweeper for Apple platforms
(iOS 16+ and macOS 14+). Classic mode shipped first, and the "epic" variants it
was architected for are landing on schedule: huge zoomable maps, **Round
(torus) edges**, and **hex grids** (the Hive family) — each added without
touching the game logic.

**v0.1.0** (classic mode), **v0.2.0** (big boards + cross-device sync), and
**v0.3.0** (board variants + the config/scoreboard redesign) have shipped to
TestFlight; **v0.4.0** (friendly rivalry — peer-to-peer score sharing, rivals
and squads, plus the home-screen redesign and per-board saves) is
feature-complete on `main`, awaiting its release build. See
[CHANGELOG.md](CHANGELOG.md) for the version history, [ROADMAP.md](ROADMAP.md) for
the path to v1.0, and [ARCHITECTURE.md](ARCHITECTURE.md) for the key design
decisions.

## Contents

- [Board families](#board-families)
- [Controls](#controls)
- [Start and end of a game](#start-and-end-of-a-game)
- [Scores](#scores)
- [Rivals — the Mess hall](#rivals--the-mess-hall)
- [Settings](#settings)
- [AI assistance](#ai-assistance)
- [Version history](#version-history)
- [Development](#development)
- [License](#license)

## Board families

A **Basic / Grid / Hive** switch in the **New Game popup** chooses the board
family (open it from the home screen's **New game** button, the in-game
**config badge**, the result screen, or `⌘N`):

- **Basic** — the original Beginner / Intermediate / Expert presets.
- **Grid** — square cells (eight neighbours); pick a **Difficulty** and a
  **Size**, plus the board's **Edges**: **Flat** (a map with edges) or **Round**
  (the world curves back — a torus that scrolls seamlessly in every direction).
- **Hive** — hexagonal cells (six neighbours), same Difficulty / Size / Edges
  axes; each tier carries a touch more mines than Grid so the difficulty matches.

The Grid/Hive size ladder runs XS / S / M / L / XL / XXL / XXXL as powers of two
(8² up to 1024² = a million cells); the larger boards are panned and zoomed, with
a minimap for navigation. Difficulty is mine density, so it composes with any
size — six tiers from Trainee up to **Lunatic** (classic Expert's 20%, where
essentially every game forces real gambles). Each tier carries its **military
rank insignia** — chevron stripes for the lower ranks, a star, a star-in-laurel,
and the crescent moon for Lunatic. The chosen family and selections are
remembered.

The size and difficulty rows are **chip rows** — every option visible, one tap
to pick — with a line below each showing the board facts and a short flavour
tagline. A small dot on a chip marks a selection path with a game in progress
(family → size → difficulty → edges, each level filtered by the ones above), so
you can find a parked game by following the lit chips down — and the **Start**
button becomes **Continue** when the exact selection has one.

On macOS the popup is keyboard-drivable: **⌘1/2/3** pick the board family (Basic /
Grid / Hive), **↑/↓** move between the remaining rows (Difficulty / Size / Edges),
**←/→** cycle the selection within the highlighted row, **Return** starts, **Esc**
closes.

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
| Return   | On the home screen: continue the latest game       |
| Esc      | Pause / resume; close a popup or the result panel  |
| ⌘N       | New Game (opens the config popup, macOS menu)      |
| ⌘R       | Restart with the same setup (macOS menu)           |
| ⌘B       | Return home to the Barracks (macOS menu)           |
| ⌘F       | Toggle mode (macOS menu)                           |
| ⌘⇧S      | High Scores (macOS menu)                           |
| ⌘,       | Settings (macOS app menu)                          |
| ⌘+ / ⌘−  | Zoom the board in / out (also ⌘-scroll)            |
| ⌘0       | Toggle the minimap between small and large         |
| ⌘1/2/3   | New Game popup: pick family (Basic/Grid/Hive)      |

## Start and end of a game

The app opens on a **home screen** built around the title art: a **Continue**
card shows your latest in-progress board (its progress, time, and when you last
played — expandable to every board you have going), with **New game**, the
**Service Record**, and the **Mess hall** below, and ⚙️ Settings / ⓘ About in
the corner. Tapping the art continues the latest game (or opens New Game when
nothing's in progress).

**Every board keeps its own in-progress game** — starting a quick round on
another board no longer discards the big one you had going; a game is cleared
when you win or lose it, and opening New Game or the Service Record mid-game
pauses the clock. Return home any time from the in-game **Home** button or the
**Barracks** menu item (⌘B) on macOS — the game pauses and saves, never
discards.

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

The 🎖️ button (in the top strip in-game, or on the home screen) opens the
**Service Record**: per-board records — best time, games cleared, and best
cleared-% from losses — plus lifetime career totals (games, tiles, flags, mines,
playtime) and a **Breakdown** of where your play goes (proportion bars across
family, size, and difficulty, by playtime or game count). The board list groups
by size, and once you've won every difficulty at a size the group shows your
combined best — the **full-clear time** for that tier (Basic gets a Total for
the classic trifecta). The row for the board you're playing is highlighted, and
a new best is celebrated on the result panel (with the improvement over your
old record).

Scores live locally (via `UserDefaults`) and can optionally sync across your
devices with **iCloud** — an opt-in toggle in the Service Record footer, off by
default. Synced devices merge their records for display while each device keeps
ownership of its own history; the reset action then offers a true cross-device
erase (a device that was offline during the wipe clears itself when it
reconnects). With sync off, everything stays on-device.

Stats are keyed by board geometry, not by tier name, so the format stays stable
across variants: every family × edges combination — and any re-tuned tier — gets
its own scoreboard entries rather than reinterpreting existing scores.

## Rivals — the Mess hall

The **Mess hall** (from the home screen) is the social room — peer-to-peer,
with **no server and no accounts**:

- **Share your scores.** Your share card sits right on the screen: type a
  display name, optionally include career totals, and hand someone the **QR
  code** (tap it to enlarge to scanning size) or the **donpa.app link** — or
  share the branded card as an image (macOS can also save it to disk). Shares
  are **signed** by a key in your Keychain. The signature is what keeps a rival
  *being* the same person over time: the first share is taken on trust, but from
  then on updates apply only when they come from that same person — someone else
  reusing the name shows up as a separate add, never a silent overwrite. Your
  own devices present one identity via iCloud Keychain.
- **Add rivals.** Scan a rival's QR (**Add rival**; macOS imports or drags an
  image) or just open their link — it works from the system Camera and Messages
  too. What you receive is a **snapshot** of the scores they chose to share
  (updated only when they share again), kept strictly separate from your own
  records; removing a rival simply deletes their data. You can nickname a rival
  and sort them into **squads** (work, family, …), and compare **head-to-head**
  against one rival or a whole squad's best, board by board with a running
  tally.
- **See where you stand.** In the Service Record, expand any board for a
  leaderboard — your best slotted in among your rivals', fastest first, with a
  standing medal on the row — and narrow the comparison to a single squad with
  the **Compare with** picker.
- With iCloud sync on, your rivals and squads follow you across your own
  devices under the same switch as scores.

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

### 0.4.0 — friendly rivalry & the home screen

- **New:** **peer-to-peer score sharing** — hand someone a QR code or a
  donpa.app link built from your best times (career totals opt-in). Shares are
  signed, so once someone adds you, later updates to your scores can only come
  from you; no server, no accounts. Opens from the system Camera and Messages
  too.
- **New:** **rivals and squads** — people you add stay as read-only snapshots,
  nicknamed and sorted into squads, with **head-to-head** comparisons and your
  rank slotted into every board's leaderboard. The **Mess hall** gathers all of
  it on one screen, and rivals/squads sync across your own devices with the same
  switch as scores.
- **New:** **a game in progress on every board** — starting a quick round no
  longer discards the big board you had going; New Game marks selections with a
  game in progress and offers **Continue**.
- **Changed:** the title screen became a **home screen** — a Continue card for
  your latest board (expandable to all of them), New Game, the Service Record,
  and the Mess hall. The Mac Game menu speaks it too (**⌘B** for home).
- **New:** the Service Record shows **full-clear times** (your combined best
  once every difficulty at a size is won) and a **Breakdown** of where your play
  goes, by playtime or game count.
- **New:** **luck, tracked honestly** — when no safe move exists (or a sealed
  pocket could never be resolved anyway), the exact odds of the guess you take
  are computed from what the board showed; the Record counts forced guesses
  faced, survived, and your luckiest escape, with a toast mid-game and the
  verdict stamped on the result screen. Chords count too.
- **New:** a sixth difficulty, **Lunatic** (20% mines; Hive 22%) — the tier
  where the board fights back.
- **Changed:** times **truncate** instead of rounding up (a 49.95s clear is
  49.9, matching the in-game clock), record improvements show the change you
  actually see, and long clears roll into `h:mm:ss.t`.

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
- **Changed:** board sizes rebalanced to powers of two (up to 1024² ≈ a million
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
