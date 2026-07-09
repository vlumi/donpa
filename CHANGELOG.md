# Changelog

All notable changes to Donpa are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Grouped by **marketing version** (a roadmap milestone), then by **build number**
within it — the version stays steady while the build climbs each TestFlight
upload (see [RELEASING.md](RELEASING.md)). Newest first.

Each version's top section, **Unreleased (next build)**, collects entries merged
to `main` but not yet in a TestFlight build; cutting a release renames it to that
build's heading and opens a fresh empty one. Keep that heading immediately
followed by its list items (no prose between), so the release script can promote
it with a one-line edit.

## [0.5.0] — Progression

**Achievements, progressive gating & practice mode** (see ROADMAP.md). In
development — entries land under Unreleased as they merge.

### Unreleased (next build)

- **Haptics on every move (iOS).** A light tap when you place a flag, a firmer
  one when a chord fires, and a soft bump on a dig that swells with the size of
  the region it opens. On by default, toggleable in Settings.
- **Sound effects.** A soft tick when you open a tile (a chord sounds the
  same — it's just opening several), a subtly fuller version whenever a whole
  area floods open (however it was opened), an up-tick for placing a flag and a
  soft downward wipe for clearing one, and distinct result stings — a bright
  rising chime for a win, a dark "ドーン!" boom for a loss. On by default and
  mutable from Settings, the home screen, or the pause screen; on iPhone the
  Ring/Silent switch mutes it too (and it never interrupts your music).
- **Question marks (opt-in).** A new Settings toggle adds a "?" step to the
  flag cycle — flag, then ?, then clear — for marking a maybe. Off by default.
  A "?" is only a note: it never counts toward the mine counter or satisfies a
  number for chording, though (like a flag) it does rule out a Bare Hands win.
- **New players start in Drills.** A fresh install now opens New Game on the
  Drills family — the no-guess on-ramp — instead of Basic, so a newcomer meets
  the fair, learnable boards first. Anyone who's played before keeps their own
  remembered family; only a genuinely blank slate lands on Drills.
- **Mess hall polish.** The iCloud sync switch now lives in the Mess hall too,
  not only the Service Record — it's where sharing raises the question. Sharing
  is gated on entering a name (no more nameless "?" cards going out), a
  signed-out iOS device points you to Settings instead of a dead end, and
  closing a finished Nearby exchange no longer drops the card you just
  received.

### build 19 — 2026-07-09

- **Nearby exchange.** A new button in the Mess hall swaps score cards with
  a player in the same room, both directions in one handshake — over local
  Wi-Fi/Bluetooth, no server, works between iPhone, iPad and Mac. Each side
  still confirms the import, exactly like a scanned code.
- **How to play.** A `?` on the home screen (and in About) opens a static
  reference: every mechanic as a small true-to-the-board diagram — the goal,
  dig/flag, chording, the mine counter, endings, forced guesses and the luck
  line, and where Drills fits — with a link to the longer read on donpa.app.
- **Decorations: 22 achievements land in the Service Record.** A medal grid
  with a distinct hand-drawn emblem per feat — starters, skill feats with
  real floors, luck feats that read your recorded forced guesses
  retroactively, tiered milestones with bronze/silver/gold, and four hidden
  gags shown as "?" until you stumble into them. Earning one stamps a gold
  sticker on the result panel; feats sync across your devices and survive a
  stats reset (they're history, not statistics).
- **Progression: the board matrix unlocks as you play.** A fresh install
  starts with XS/S/M at Trainee/Sapper on the square families; each win
  opens the next rung (sizes, ranks, the Hive after your first win, Round
  edges after an M win). Locked options stay visible as teasers with their
  requirement, wins stamp an UNLOCKED sticker on the result panel, and a
  stats reset locks the ladder again. Veterans' existing records already
  open everything — nothing changes on an established install.
- **Drills shows up in the breakdown bars.** The Service Record's
  family/size distribution silently skipped Drills games (the sweep
  predated the family).

### build 18 — 2026-07-08

- **Drills: practice without the dice.** A new leftmost board family in
  New Game (FI *Soha*, JA *演習*): every board is verified fully solvable by
  pure deduction — no forced guesses, ever. Five sizes (XS–XL) at a
  Sapper-grade 12 % mines, with its own hi-scores per size: learn the
  patterns, then speedrun them.
- **Readability & VoiceOver pass.** The result pills are restyled as
  ink-on-paper stickers (the old white-on-green sat at 2.2:1 contrast) and
  now scale with your text size; the dark-mode mine counter and leaderboard
  medals gain proper contrast; the lucky-guess toast is announced to
  VoiceOver and respects Reduce Motion; picker chips speak their parked-game
  dot; rival and head-to-head rows read as single, sided utterances; size and
  difficulty chips grow to full tap-target height.
- **The cell word follows the board's shape.** Square boards count tiles,
  hive boards count cells (FI *ruudut*/*kennot* — and FI's Grid family is now
  **Ruutu**, one square, pairing with Kenno, one honeycomb cell).

## [0.4.0] — Friendly rivalry

**Peer-to-peer score sharing: rivals, squads, the home screen — and the
forced-guess luck tracking** (see ROADMAP.md). Shipped to TestFlight (both
platforms).

### build 17 — 2026-07-07

- **Toasts only for real luck.** Surviving better-than-even odds is Tuesday,
  not luck: the survived-guess toast now fires only at coin-flip odds or worse
  (an 85% tap into the open field stays tracked in the Record, without
  fanfare), and a better-than-even guess that happens to win the game stamps
  the neutral "forced guess" instead of claiming "lucky guess".
- **Sharing remembers the career toggle.** "Include career stats" on the
  share card no longer resets to off every time you open the Mess hall.

### build 16 — 2026-07-07

- **The Record now tracks your luck.** Sometimes the board corners you — no safe
  move exists anywhere, and you have to guess. Donpa now recognizes those
  moments exactly, computing the true odds of the cell you clicked from what
  the board showed at that instant, and keeps score: how many forced guesses
  you've faced, how many you survived, and your luckiest escape — down to the
  odds, like walking away from a one-in-four. Only genuine gambles count: if a
  safe move existed that could still have shed light on your cells, gambling
  early is on you, not on luck — but a sealed coin flip that no amount of play
  could ever resolve counts the moment you take it (why wait?).
  Chords count too — a chord's gamble is every cell it opens at once, so a
  throwaway flag placed just to skip switching modes still gets its guess
  scored honestly. Shown in the Tour of Duty and each board's expanded stats
  once a board has forced your hand — on every board; the million-cell
  XXXL scores its sealed pockets. The bookkeeping is exact but conservative:
  a recorded guess always carries its true odds, and a position too tangled
  to analyze goes unrecorded rather than mis-scored.
- **Luck shows itself in the moment.** Survive a forced guess mid-game and a
  small toast says so, with the odds — and the wording escalates with the odds
  beaten: a lucky guess, a coin flip, a long shot, a MIRACLE. When a forced
  guess ends the game, the result screen stamps the same words in the corner —
  the brag on a win, "forced guess" as the consolation on a loss (fate, not
  error). And silence teaches too: no message on a guess-death means playing
  on could still have resolved those cells — the board had more to say.
- **A sixth difficulty: Lunatic.** Past Legend lies 20% mines (Hive: 22%) —
  classic Expert's density on Donpa's boards, where essentially every game
  forces real gambles and the new luck tracking earns its keep. The crescent
  moon in the laurel marks it. Heads up for full-clear chasers: size groups now
  count six tiers, so an old "Full clear" reads 5/6 until you beat the moon.

### build 15 — 2026-07-06

- **Head-to-head names every board fully — and offers a rematch.** Rows used to
  read just "M · Veteran", leaving Grid vs Hive and Flat vs Round boards
  indistinguishable. The list now groups under sticky family sections titled
  with the New Game glyphs (Round called out), so each row stays as slim as the
  Service Record's: the size with the difficulty as its rank insignia. And when
  you spot a board where you're trailing, a play button on the row jumps
  straight into a fresh game on it. The Mac sheet also got room to breathe — a
  long comparison no longer lives behind a deep scroll in a cramped window.
- **A typed squad name can no longer vanish.** In the add-rival and rival-detail
  sheets, a new squad only existed after tapping the field's own button — typing
  a name and confirming the sheet silently threw it away. Confirming now creates
  the squad (and puts the rival in it), and the field's button says Create, so
  it no longer mirrors the sheet's Add.
- **Your share name follows you across devices.** The name on your share card
  was stored per device, so your Mac could introduce you blankly (or as someone
  else) even though it shares under the same identity. The name now travels
  with the signing key via iCloud Keychain; a name you'd already set is adopted
  automatically.
- **The name-collision prompt looks like the warning it is.** When a share
  arrives under an already-taken name from a different person, the prompt now
  carries an alert triangle and an amber Keep both — clearly not the routine add
  sheet — and Return no longer triggers Keep both while you're typing a name:
  accepting a same-name share is a deliberate tap now.

### build 14 — 2026-07-06

- **The Mess hall.** Everything social now lives in one place, straight off the home
  screen: share your scores, add rivals by scanning theirs, and manage your rivals and
  squads — no more hunting through the Service Record's toolbar. The Record keeps the
  rival comparisons themselves, with a Manage rivals link right by the comparison
  picker. Adding a rival now drops you in the Mess hall so you see exactly where they
  landed.
- **Share your scores.** In the Mess hall, tap Share my scores for a QR code (or copy
  a link) built from your best scores. Someone adds you as a rival by scanning the code
  or opening the link — no account, no server. Shares are signed, so once you've added
  a rival, updates to their scores can only come from that same person — someone else
  reusing the name can't overwrite them. And a rival's scores stay separate from your
  own: remove them and their data is simply gone.
- **Rivals list.** Add rivals from their shared scores, give each your own nickname, or
  remove them — all in the Mess hall. Their scores are a snapshot from when they
  last shared (with the date shown), not a live feed. You can nickname a rival and put
  them straight into squads as you add them, too.
- **Squads.** Sort rivals into named squads (work, family, …): create and manage your
  squads, then put each rival in as many as you like. Renaming a squad keeps its
  members; deleting one just un-groups them. Tap a squad to see who's in it.
- **See how you rank against rivals.** Expand any board in the Service Record for a
  leaderboard — your best time slotted in among your rivals', fastest first. A little
  medal on each board shows your standing at a glance, and you can narrow the comparison
  to a single group.
- **Head-to-head.** From the rivals list, compare all your best times against one
  rival — or a whole group's best — board by board, with a running tally of who leads.
- **Rivals and squads sync across your devices.** With iCloud sync on, the rivals and
  squads you set up on one device show up on the rest — the same switch that syncs your
  scores. Removing a rival removes them everywhere.
- **A game in progress on every board.** Each board keeps its own in-progress game now,
  not one shared slot — so starting a quick round on another board no longer discards
  the big one you had going. In New Game, the Start button becomes Continue when the
  current board has a game going, and a small dot marks each selector that leads to
  one — so you can drill down to any saved board. A game is cleared when you win or
  lose it.
- **The title screen is now a home screen.** The app opens to a proper menu: a Continue
  card showing your latest in-progress board (with its progress, time, and when you
  last played — expandable to all of them), a New Game button, and the Service Record.
  No more silent jump into whichever game you played last — continuing is one
  predictable tap, and the title art still works as that shortcut. On a wide screen
  (Mac, iPad, landscape) the art and menu sit side by side.
- **Full-clear times.** The Service Record now groups each family's boards by size,
  and once you've won every difficulty at a size, the group shows your combined
  best — the full-clear time for that tier. Until then it counts down the boards
  left (2/5 cleared). Basic gets a Total for the classic trifecta. Sums stay within
  one size on purpose: adding XXXL to XS would make everything else a rounding
  error.
- **Breakdown bars in your career.** The Tour of Duty now shows where your play
  goes — proportion bars across family, size, and difficulty, switchable between
  playtime and game count. One glance answers "have I really only been playing
  S-size Sapper?"
- **The Mac Game menu speaks Barracks.** ⌘B now takes you home, pausing and saving
  the game (the old ⌘T "Title Screen" retires with the title screen itself), and the
  in-game home button's tooltip says Barracks too. The ⌘1–3 shortcuts that jumped
  straight into the classic presets are gone — every new game goes through the New
  Game screen, where all the boards live.
- **Start sits where you expect it.** In New Game's wide layout (Mac, iPad,
  landscape phone), the Start/Continue button moved to the bottom of the card, full
  width — it used to sit under the family list, leaving the Flat/Round toggle in the
  spot where a start button usually lives (and getting tapped as one). On a short
  landscape phone the card slims its captions so everything still fits without
  scrolling.
- **Browsing New Game no longer costs clock time.** Opening the New Game screen during
  a game now pauses it, just like the Service Record does; closing without starting
  picks the clock right back up.
- **The New Game screen no longer balloons on a portrait phone.** A layout feedback
  loop could stretch the card to fill the screen, pushing its close button behind the
  Dynamic Island.
- **Times never round up.** A clear at 49.95s used to record as "50.0" while the
  in-game clock still read 49 — every time display now truncates to the tenth, so a
  result never shows more than the timer did. The "improved by" note on a new record
  now shows how much the displayed best changed (no more "improved by 0.0 s" when the
  record moved from 18.24s to 18.15s — that now reads 0.1s, or skips the note when the
  shown value didn't move).

- **About speaks the game's language.** The genre blurb ("A Minesweeper game for
  Apple platforms") gave way to the game's own tagline — 地雷を除去し、命を守れ /
  Clear the mines, save lives.
## [0.3.0] — Board variants

**Board-topology variants: wrapped (torus) + hex grids** (see ROADMAP.md).
Shipped to TestFlight (both platforms).

### build 13 — 2026-07-04

- **Localization polish (FI + JA).** A fresh-eyes pass over both languages:
  consistent terminology (FI "alueavaus" for chording, unified "tulokset"; JA
  デバイス/記録 unified), career-stat labels in a consistent plural form, several
  awkward or plain-wrong lines fixed, and a dose of light Finnish army flavor in
  the taglines ("Pakkaa sissimuonat", "Iltavapaa peruttu", "Puhdasta
  simputusta") to match the Japanese tone — plus the scoreboard is now the
  **Sotilaspassi** in Finnish. The pause screen gained a drill-command title in
  every language: **At ease! / Lepo! / 休め！**
- **Filter labels fit.** Family/edge filter buttons shrink a long label to fit
  rather than truncating it (e.g. "Ruudukko").

### build 12 — 2026-07-04

- **The board can't go dead after a game ends (Mac).** Rapid-clicking through the
  end-of-game panel could leave the board silently ignoring *every* click until
  you paused for a second: the dismissing panel stayed clickable through its
  fade-out, and a click landing on it wedged the click handling for as long as
  the rapid clicking continued. The panel now stops taking input the instant
  it's dismissed, so post-restart clicks land immediately.
- **Sloppy clicks land (Mac).** A quick click that slid a few points — the Magic
  Mouse does this under its own click force — was silently eaten as a tiny pan;
  during rapid play that could swallow *every* click until the hand settled,
  leaving the board seemingly dead. A brief press that barely moved now counts as
  the click it was meant to be; real drags still pan exactly as before.
- **Website link in About.** The About panel now links to **donpa.app** alongside
  the source-code link.

### build 11 — 2026-07-03

- **Play straight from the scoreboard.** Expand any board's row in the Service
  Record and tap **New game on this board** to jump right into it — handy for
  taking another run at a time you were just looking at.
- **Steadier New Game toggle.** The **Flat / Round** control no longer stretches
  tall on a taller iPhone, where the extra height read as dead space that didn't
  respond to taps.

### build 10 — 2026-07-03

- **Hex grids.** A new Modern **Shape** option: play on a hexagonal board where each
  cell has six neighbours instead of eight. Pick **Hex** in the New Game screen
  (alongside size/difficulty). Works with both bounded and **wrapped** edges — a hex
  torus that scrolls seamlessly in every direction. Scores are tracked separately
  from square boards. Hex carries a touch more mines at each difficulty (its six-
  neighbour cascades play easier otherwise, so it's tuned to match square).
- **Wrapped (torus) boards.** A new Modern option: the board's edges connect, so it
  scrolls seamlessly in every direction — pan off one side and the other flows in,
  forever. Pick **Wrapped** in the New Game screen (next to the size/difficulty).
  Scores are tracked separately from bounded boards.
- **Boards are picked by family: Basic / Grid / Hive.** The New Game popup was
  redesigned around three board-family **pages** — **Basic** presets, **Grid**
  (square cells), and **Hive** (hex) — each with its own hand-drawn glyph tab
  (swipe between pages on a phone; a roomier screen shows the families in a
  sidebar with the options beside them; or ←/→ on the Mac). Grid and Hive share
  one page: rank-insignia **difficulty chips**, a **size chip row** (XS…XXXL),
  and an **edges toggle** that's now **Flat / Round** — a framed-map glyph
  against a globe, because a Round world curves back on itself and wraps. The
  Hive page shows its honest (denser) mine percentage, and **each family
  remembers its own difficulty / size / edges** — a huge Round hive spree
  doesn't retune your next Grid game. The High Scores table
  follows the same names, Round boards carry a tag on their row, and — new —
  **Hive and Round boards get scoreboard rows at all** (they were missing from
  the table before). Scores stay tracked separately per family × edges; the
  clean-slate reset announced below covers this change too.
- **Service Record redesign: filter your scores and expand any board.** The High
  Scores table now has **Family** and **Flat / Round** filters (the same glyphs as
  the New Game screen) that narrow it to one board type at a time, so the list
  stays short. **Tap any row to expand it** into that board's own record — games,
  wins, tiles, flags, mines, no-flag / no-chord wins, chords, time, your top five
  times (each with a relative date like "2 days ago"), and when you started playing
  it — laid out with the same stat block as the lifetime career at the top. The
  sheet uses one responsive layout from iPhone to Mac.
- **Board sizes rebalanced to powers of two** (8, 16, 32, 64, 128, 256, 1024). Every
  board is now even-sided (which the wrapped-hex torus needs), and the size ladder is
  cleaner. Mine-density tiers were re-tuned to 10/12/14/16/18% so the five
  difficulties stay distinct on the larger boards. **All existing scores are reset**
  (a clean pre-release slate) — this one-off clears local and iCloud stats across
  every device, and an in-progress game saved by an older build is discarded rather
  than restored onto a board it no longer fits.
- **Erase synced scores on all your devices.** The stats-sheet reset now offers a
  true cross-device wipe when iCloud sync is on: it erases every device's scores and
  **stays erased** — a device that was offline during the wipe clears itself when it
  reconnects, rather than re-uploading old data. With sync off it stays a local-only
  clear (the cloud is never touched).
- **Leaner rendering, and the minimap follows appearance changes.** Every visible
  tile was silently rebuilt twice per move (and once per mouse-move while
  dragging the minimap); now only when the board actually changes. The minimap
  also recolours when the system switches light/dark (it kept stale colours until
  the next move), its "you are here" box traces the true viewport (it ran a
  couple of cells large), and right-click / long-press over the minimap no longer
  acts on the board cell hiding underneath it.
- **Sync behaves offline.** The scoreboard now updates while offline with sync on
  (new wins and resets showed only after reconnecting — or not at all if you
  relaunched); a reset or sync-off done offline now cleans up its cloud data on
  reconnect instead of leaving other devices counting stale scores; and if scores
  were erased everywhere while your sync was off, turning sync back on **asks
  first** before resetting this device.
- **Minimap shows/hides reliably.** The corner minimap no longer pops in mid-game
  after a small pan on a board that fits (or stays hidden when it shouldn't) — its
  visibility now tracks the zoom level, not the camera position. Wrapped boards
  always show it (there's no edge to fit).
- **Clearer top status bar.** The current-game badge (difficulty insignia + size)
  is larger and easier to read, and the mines / clear-% / timer readouts next to
  it reclaim the width that was sitting empty before the High Scores medal.
- **Finnish and Japanese coverage completed.** Several macOS menu commands (New
  Game…, Toggle Minimap Size, Zoom In/Out) and the macOS app name now have fi/ja
  translations, the result panel's "first clear" pill and the scoreboard's
  new-best marker are localized, and VoiceOver reads localized names for the
  settings and New Game pickers.

## [0.2.0] — Cross-device & big boards

**Cross-device sync & big boards** (see ROADMAP.md). Both pillars have landed;
cross-device sync awaits a real two-device verification pass.

### build 9 — 2026-06-30

- **Big boards are much lighter.** The board scene was being rebuilt on every UI
  tick (the running clock alone re-creates the view ~10×/s), leaving extra scenes
  redrawing in the background — on a huge board that pinned the CPU even at rest.
  Now built once: idle CPU on a big opened board drops dramatically (both iOS and
  macOS; macOS showed it worst).
- **Lighter still while the clock runs.** The running timer now re-draws only the
  timer readout each tick instead of the whole game chrome — a further idle-CPU and
  battery saving (most noticeable on iOS).
- **Toggle-side picker reads the right way.** The Left/Right control in Settings
  showed its options reversed (Right on the left); they're now in natural order.
- **iCloud sync row is honest when signed out.** The toggle no longer turns on
  when iCloud isn't available (it can't sync), and on iOS the status is plain
  guidance to sign in rather than a link that just opened the app's own settings.

### build 8 — 2026-06-29

- **Scoreboard orientation.** The board you're playing gets a persistent "you are
  here" row band; opening the scoreboard mid-game scrolls that row into view (from
  the title it stays at the top). The result panel now shows the *improvement* —
  how much faster a new best ("−m:ss.t", or "first clear") and "+N%" on a
  better-than-before loss — instead of the final time (already on the timer). The
  just-improved value carries a small "↑" marker (a shape, not colour, so it's
  colour-blind safe and accent-independent).
- **Minimap is a navigator.** Tap or drag inside the corner minimap to move the
  camera there — the quick way around a board too big to see at once.
- **Resizable minimap.** Drag the caret hugging its corner to resize it freely, or
  tap the caret to snap between min and max; on macOS ⌘0 toggles the size. The
  chosen size persists across new game, restart, and resume. (Replaces the old
  full-screen board overview.)
- **Over-flagged numbers are flagged.** A revealed number with more flags around it
  than its value gets a faint ring — a guaranteed mistake, surfaced so you can fix
  the slip. It marks only the impossible number, not which flag is wrong, so it's a
  nudge, not a solver.
- **Huge boards stay smooth.** Fixed a runaway where a very large board (超特大)
  could peg the CPU and stall after opening tiles; reveals, flagging, and idle are
  all much lighter now, especially on macOS.

### build 7 — 2026-06-28

- **Minimap appears immediately** on a board that only slightly exceeds the
  viewport (e.g. Modern S on an iPhone 14) — it no longer stayed hidden until a
  small pan.

### build 6 — 2026-06-28

- **Resuming keeps the dig/flag input mode** — it no longer reset to dig on
  restore.
- **Wider pan margin on all edges** so edge tiles never sit flush to the window,
  minimap or not.
- The in-game clear-% and the loss screen's "best %" now floor (matching the
  scoreboard) instead of rounding up; flags survive a loss; correctly-flagged
  ("disarmed") mines no longer detonate in the loss shockwave.
- **Offline merged-stats cache** so combined cross-device totals survive going
  offline; a fix so a new record set on another device isn't double-counted.
- Carousel modal no longer overflows on small iPhones (edges fade instead).

### builds 4–5 (initial 0.2.0) — 2026-06-28

- **Cross-device scoreboard sync (iCloud).** High scores and career totals follow
  the player across their devices via iCloud Key-Value Storage. Opt-in (off by
  default), in a footer toggle on the stats sheet; silent and account-free
  otherwise, degrading to local-only when signed out. The merge is conflict-free —
  each device owns its slot; counters sum across devices and best times merge by
  min — so concurrent play on two devices Just Works. Turning sync off (or
  resetting) removes this device's contribution everywhere. In-progress games stay
  local.
- **Stats sheet, reworked.** The scoreboard is now a single "Service Record" sheet
  — "Tour of Duty" (career totals) beside "Commendations" (per-board high scores),
  two-column on a wide window — with the sync control in the footer. Lifetime
  totals use locale digit-grouping and localized time units.
- **Big boards, XS–XXXL.** The Modern size ladder is now XS / S / M / L / XL /
  XXL / XXXL (9 / 16 / 25 / 50 / 100 / 300 / 1000²; ja 極小…超巨大). XS is the new
  floor, L (50²) fills the old gap, XXL (300²) is an epic-but-finishable summit,
  and XXXL (1000², 1M cells) is the sandbox extreme. Scoreboard keys are
  geometry-based, so the rename leaves existing scores intact.
- **Save/restore camera view.** Resuming a saved game returns to where you were
  looking — `GameSnapshot` persists the camera centre (normalized) + zoom,
  re-clamped to the current viewport so it restores sensibly across window/device.
- **Carousel board-config picker.** The New Game difficulty and size rows are now
  a horizontal "drum" of cards (the segmented control truncated once a row had
  many or long options — Size's 7 tiers, "Intermediate"). A `detail · tagline`
  line under the pick shows the board facts plus a short flavour line, and the
  difficulty cards carry the rank insignia. On iOS the selected card centres with
  edge-clamped scrolling; on macOS cards lay out statically when they fit, and a
  click moves keyboard focus to that row.
- **Cumulative career stats.** Per-device, conflict-free running totals (games
  played, tiles opened, flags placed, mines hit, mines disarmed, playtime) shown
  in the scoreboard — no win/loss ratio. Built on a grow-only `DeviceCounter` (the
  foundation the cross-device sync above builds on).
- **Mouse + keyboard zoom (macOS).** ⌘-scroll and ⌘+/⌘− zoom the board; ⌘0 opens
  the board overview.
- **Huge boards are responsive.** Reveal/mine-placement compute off the main
  thread (the board never freezes; a debounced overlay gates input); mines are
  pre-armed off-thread on New Game so the first tap is instant; placement and
  end-game effects scale with the mine count, not the cell count; the minimap
  overview renders off the main thread; autosave is debounced + written on a
  background actor; `Cell` is bit-packed to one byte. Mine-hit shows the burst
  tile instantly; Esc closes the fullscreen overview.

## [0.1.0] — TestFlight beta

First release — classic Minesweeper on iOS and macOS. TestFlight pre-release
only. iOS shipped builds 2–3; macOS build 1.

### Added

- Classic Minesweeper game logic with first-click safety, flood-fill reveal,
  flagging, chording, and win/lose detection.
- Two board modes: **Classic** (the original Beginner / Intermediate / Expert
  presets) and **Modern** — a Difficulty (Easy / Normal / Hard / Brutal / Insane
  mine-density) × Size (Small 9×9 / Medium 16×16 / Large 25×25) grid, chosen in
  the New Game popup and persisted between launches.
- A logical Minesweeper solver (single-constraint deduction) plus a dev-only
  `TierAnalysis` tool (`swift run TierAnalysis`) used to pick the Modern
  difficulty tiers from measured guess-dependence.
- `Topology` and `CellLayout` seams that isolate all future "epic" variation
  (wrapped/torus boards already pass a full-game test with unchanged logic).
- SpriteKit board renderer (`SKScene` + camera) hosted in SwiftUI, with
  pan and zoom.
- iOS and macOS app targets (XcodeGen-generated project).
- A board-side **dig / flag** input-mode toggle (a single-tap segmented pair, so
  flags can be placed without risk of an accidental reveal). A long-press (or
  macOS Control-click) performs the opposite primary action; tapping a revealed
  number always chords. Unopened tiles carry a faint manga screentone keyed to
  the mode (dots for dig, hatch for flag).
- Local per-config stats (`UserDefaults`), shown from the 🏆 button in Classic
  and Modern sections: best time plus games cleared for each board. Beating a
  best time opens the scoreboard. Stats are keyed by a versioned, geometry-
  bearing key (`v1|modern|sq|bounded|16x16|m41`) that names future shape/edges
  axes with defaults — so adding wrapped/hex boards or re-tuning tiers later
  creates new entries rather than corrupting old scores (no migration).
- macOS: a mode-aware board cursor — a pointing hand to dig, a flag to flag (a
  plain arrow otherwise); holding Control shows the other mode's cursor, since
  Control-click does the opposite action.
- App icon: a procedural detonating mine in a halftone comic burst, generated by
  `Scripts/make-icon.swift` (pure CoreGraphics; `--mono` renders a B&W variant,
  `--launch` the launch image). The same flat burst-mine marks the hit cell on a
  loss in-game.
- iOS launch screen (`UILaunchScreen`: the mono burst-mine on a charcoal ground)
  plus a brief matching in-app splash that fades into the title.
- Manga theme: comic end-of-game result panels (win / loss / new-record) and a
  "squad resting" pause panel over the board, an interactive manga title screen,
  and procedural manga chrome glyphs (`MangaIcon`) — a war-medal High Scores
  button, a Quonset-hut Home, a swallowtail flag, a pause/play toggle, and an
  army boot-print "dig" glyph. The framed panels are keyed assets built by
  `Scripts/make-panels.swift` (transparent margin + thin white "page" outline);
  the title is a full-bleed poster.
- Modern difficulty shown as ascending **military rank insignia** (chevron
  stripes → star → star-in-laurel) instead of text, so the five tiers stay
  compact and language-independent — in the New Game picker, the in-game config
  badge, and the scoreboard.
- Pause + resume: a pause control (and Esc on macOS) freezes the clock and blurs
  the board behind the pause panel; tapping the panel or the play toggle resumes.
  The timer is segmented (`accumulatedCentiseconds` + `runningSince`).
- Save & restore: an in-progress game is autosaved (atomic, crash-safe) and, on
  next launch, offered to Resume or Discard. The save clears on finish / new game
  / returning home.
- The scoreboard highlights the row whose record was just set, until the next
  game ends.
- Local-only UI tests (XCUITest, `Tests/UITests/`, run via `make uitest`) covering
  the title → New Game → game, sheet, and pause/resume flows. Not run by CI.
- Light/dark/system appearance, chosen from a ⚙️ settings sheet and saved
  between launches. The board and chrome share one palette resolved from a
  single effective scheme.
- macOS: pan a zoomed-in board by click-drag (with a small threshold so clicks
  aren't mistaken for drags) or two-finger trackpad scroll.
- Win/loss feedback: the board animates on game end (the hit mine detonates with
  a staggered mine wave and a brief shake on loss; a green ripple on win), the
  restart button pops, iOS plays a success/error haptic, and a small banner at
  the bottom shows the result (with the finishing time on a win). Respects
  Reduce Motion.
- Precise timing: play time is tracked from the wall clock and best times are
  recorded and shown as `m:ss.t` (tenths, uncapped) in the scoreboard and
  banner. The top status strip keeps the classic 3-digit whole-second LED (capped
  at 999 for display). A loss on the last cell shows "N tiles left" rather than a
  misleading "100%" (the scoreboard floors the cleared %, so only a true clear
  reads 100%).
- An **About** screen (app name, version, credits), opened from the title
  screen's ⓘ button and, on macOS, the app menu.
- Keyboard shortcuts: Space toggles mode (handled in the scene so it fires
  reliably), plus macOS menu commands ⌘N (new game), ⌘F (toggle mode),
  ⌘1/2/3 (classic presets).
- GitHub Actions CI: SwiftLint + swift-format checks, logic tests (with
  coverage), plus iOS and macOS builds.
- SwiftLint (`.swiftlint.yml`) and swift-format (`.swift-format`) configuration.

- The title screen doubles as the home hub: tapping the manga art opens the New
  Game popup; the 🏆 High Scores, ⚙️ Settings, and ⓘ About buttons sit on the
  art's corner. Return to it any time via the in-game Home action or ⌘T (macOS).
- Navigation: all game configuration lives in one **New Game popup** (Mode, then
  Difficulty + Size for Modern), opened from the title art, the status-bar config
  badge, the result screen, or ⌘N; keyboard-drivable on macOS (arrows choose,
  Return starts, Esc closes). The result panel dims the board only, leaving the
  control strip live, so it carries no buttons. Settings/High Scores are on the
  macOS menus (`⌘,` / `⇧⌘S`) and the title hub.
- Sheets (Settings, High Scores, About): on iOS, a `NavigationStack` with a Done
  nav-bar item and a fit-content detent; on macOS, inline with a bottom Done.

### Project decisions

- Minimum platforms: **iOS 16** and **macOS 14 (Sonoma)** — two native targets,
  no Mac Catalyst.
- Panning is constrained to the board edges; when the whole board fits on screen,
  panning is disabled so a stray drag can't move it.

### Fixed

- The board follows system light/dark changes on iOS/iPadOS (a
  System → Dark → System toggle could leave the grid stuck dark).
- Restoring a saved game ignores out-of-bounds coordinates and recomputes the
  cleared-cell count from the board, so a corrupt or tampered save can't produce a
  broken or unwinnable game.

<!-- Releases are tagged per platform + build (ios/vX.Y.Z-N, mac/vX.Y.Z-N) — no
single plain vX.Y.Z tag — so each version links to its filtered list of GitHub
releases rather than one tag. -->

[0.4.0]: https://github.com/vlumi/donpa/releases?q=v0.4.0
[0.3.0]: https://github.com/vlumi/donpa/releases?q=v0.3.0
[0.2.0]: https://github.com/vlumi/donpa/releases?q=v0.2.0
[0.1.0]: https://github.com/vlumi/donpa/releases?q=v0.1.0
