# Roadmap

How Donpa gets from classic Minesweeper to the full "epic" vision at **v1.0**.
Two architectural seams — `Topology` (logical neighbours) and `CellLayout` (pixel
geometry) — let most features land as a new conformer plus UI, without touching
game logic.

Versions are indicative, not contractual. Each minor groups related work into one
meaty release: v0.2.0 = cross-device sync + big boards; v0.3.0 = board-topology
variants; v0.4.0 = achievements + practice mode; v1.0.0 = the composed epic set.
**v0.1.0 and v0.2.0 have shipped to TestFlight; v0.3.0 (board variants) is in
progress.**

---

## v0.1.0 — Classic release (shipped to TestFlight)

Classic Minesweeper on iOS + macOS (see [CHANGELOG.md](CHANGELOG.md)). TestFlight
pre-release. Carry-over notes for later milestones:

- **Per-cell board VoiceOver deferred** — needs a scalable cursor model (swiping
  10k cells doesn't scale); co-design with big-board navigation.
- **JA/FI strings are drafts** (`needs_review`) — refined from test feedback; not
  a release gate.

## v0.2.0 — Cross-device & big boards

Both strands shipped; only a real-device verification pass remains, folded into
pre-1.0 device testing.

### Cross-device scoreboard sync

**Shipped.** Scores + career totals sync via iCloud KVS, keyed by Apple ID: each
device owns one blob, the display merges all conflict-free (counters sum, best
times by min), so concurrent play never double-counts. Opt-in, off by default;
local-only when signed out; in-progress games stay local. Detail in
[CHANGELOG.md](CHANGELOG.md).

**Still open:**

- [ ] **Real two-device verification** — KVS is unreliable on the simulator;
      confirm on a real iPhone + Mac (one Apple ID) in the pre-1.0 device pass.
- [x] **PRIVACY.md note** — done (PRIVACY.md covers the iCloud-sync line).
- [ ] **Churn / pruning** — a reinstall mints a new slot, orphaning the old KVS
      blob. Deferred (a dead reinstall is indistinguishable from an offline device;
      blobs are tiny). Revisit only near KVS limits.

### Big boards

**Shipped.** The full XS–XXXL ladder (up to 1000² = 1M cells), flat bit-packed
storage, viewport culling + texture batching, bounded zoom-out, the minimap, and
the off-main work that keeps a million-cell board responsive. Detail in
[CHANGELOG.md](CHANGELOG.md). Non-blocking follow-ups (real-device pass, minimap
polish) live in the Backlog.

## Backlog (unversioned)

Polish and smaller features that can land in any release — not milestone gates.
The numbered milestones are the real pillars (scale, then board variants); these
slot into whichever release they're ready for.

**Gameplay fairness** (builds on the v0.1 logical solver):

- **"No-guess" generation is NOT a fairness fix for the normal game** — a chance
  of a forced guess is part of classic Minesweeper's character, so the standard
  modes keep it. The solver-gated no-guess machinery (cheap; `Solver` +
  `TierAnalysis` already exist, generation just resamples until solvable) instead
  finds its purpose as a **practice mode** — see v0.4.
- [ ] Safe-reveal / question-mark flag cycle (classic third flag state).

**Navigation / UX:**

- [ ] **macOS `⌘1/2/3`** (classic presets) jump straight into a Classic game,
      jarringly switching mode mid-play. Rethink: pre-select in the New Game
      popup instead of starting immediately? Or be Modern-aware?
- [ ] **Minimap drag-to-reposition** — move the HUD out of the way (the toggle
      hides it; dragging relocates it). Also wire an opener for when it's hidden.
- [ ] **Minimap polish** — higher-contrast revealed shading; handedness-aware
      corner.

**Verify before 1.0:**

- [ ] **Real-device test pass** — everything so far is iPhone-sim + Mac only;
      need older/slower devices, iPad, and small screens (the SE status-bar
      truncation escaped exactly this gap). Profile huge boards on real hardware
      (the simulator software-renders SpriteKit and overstates cost), and confirm
      the XXXL (1M) first-arm/reveal feel + baseline memory in Instruments.

**Code cleanup (next refactor round):**

- [ ] **Pause as a UI play-state.** `isPaused` is a UI-only flag on
      `GameViewModel` while `GameStatus` (Core) stays pure (`notStarted/playing/
      won/lost`, also Codable-saved + used by the `Solver`). The smell is the
      scattered `status == .playing && !isPaused` checks. Fold them into one
      view-model computed enum (e.g. `playState` with a `.paused` case) the UI
      reads — without pushing a UI concept into Core/solver/save. Decide during a
      later refactor pass.
- [ ] **`GameStatus` convenience accessors.** Replace the repeated
      `status == .notStarted || status == .playing` with computed properties on
      the enum (`isLive` / `isFinished` / `isPlaying`). Pure readability; no
      behaviour change.

## v0.3.0 — Board variants (wrapped + hex)

The two board-topology pillars, grouped: both exercise the `Topology` /
`CellLayout` seams and share the "select a variant, score it separately" UI work.

### Wrapped (torus) boards

**Shipped.** Bounded/wrapped selector, seamless infinite scroll (no edges to clamp
to, tap/minimap wrap around), and topology-keyed scoreboards. Detail in
[CHANGELOG.md](CHANGELOG.md).

### Hex grids

**Shipped.** Pointy-top `HexTopology` (6-neighbour, odd-r offset) + `HexLayout`
(nearest-centre hit-testing) + hex-aware tile/glow rendering, in both bounded and
**wrapped** (torus) edges. The size ladder was moved to powers of two so every board
is even-sided — the property a hex torus needs for consistent wrap. Difficulty tiers
re-tuned across the new ladder (this reset pre-1.0 scores). Detail in
[CHANGELOG.md](CHANGELOG.md).

With square + hex × bounded + wrapped all playable, the **New Game + scoreboard
redesign** (graphical shape/edge pickers over the full matrix) is the next UX pass.

## v0.4.0 — Achievements & practice mode

Two engagement features grouped because both turn on the same "what counts toward
stats" question. Held **late on purpose**: achievement IDs are permanent (like the
scoreboard keys), so they're designed once the full variant matrix (square + hex +
wrapped) exists and can be referenced without churn.

**Achievements** — see the **Achievements** section below for the architecture,
the no-leaderboards decision, and the design principles. Build-out:

- [ ] Internal achievement layer (events on game-end → local store) + in-app UI
- [ ] Local + iCloud-KVS sync of the earned set (reuses the v0.2 sync blob)
- [ ] Game Center reporter bolted on behind the layer (achievements only)
- [ ] The curated achievement list defined (IDs locked) in App Store Connect

**Practice mode (no-guess boards)** — a deduction-only **onboarding** mode, framed
as *practice*, NOT as a "fairer" alternative to the real game (the standard modes
keep the classic forced-guess risk). Solver-gated generation resamples until the
board is fully deducible.

- [ ] Generate guaranteed-solvable boards (reuse `Solver` / `TierAnalysis`)
- [ ] Frame it clearly as **practice** in the New Game UI — its own thing, not a
      difficulty or a default
- [ ] **No hi-scores**: practice never writes a per-board best time (incomparable
      to real boards + an easier guarantee). **Career totals DO count** (you still
      played — tiles/flags/playtime accrue). Achievements: gentle/onboarding ones
      may count; skill feats (speed, no-flag, Insane) excluded. Its own
      geometry-bearing `GameConfig.storageKey` keeps it cleanly separated.

## v1.0.0 — The epic set

Everything composes: square **or** hex, bounded **or** wrapped, any size.

- [ ] Full board-type matrix selectable and combinable
- [ ] Unified game configuration + scoreboards across all variants
- [ ] Settings, theming, polish pass across all modes
- [ ] Documentation + screenshots for each mode
- [ ] Performance validated on the largest supported boards
- [ ] Release builds for iOS + macOS
- [ ] **UI smoke tests on CI?** A local XCUITest suite already exists (`make
      uitest`, `Tests/UITests/`, shipped in v0.1) but is deliberately *not* run
      by CI — it needs a job that builds the `.xcodeproj` and boots a simulator
      (today CI runs SPM `swift test` + `xcodebuild build` only), which is slow
      and flaky mid-iteration. Decide near 1.0 whether the regression value is
      worth wiring it into CI.

## Publishing & distribution

The paid account exists and both apps ship to TestFlight. How they reach the
public stores from here:

- **iOS is one universal app**: a single App Store Connect record + binary runs
  on **both iPhone and iPad** and appears on both stores automatically (shared
  page, reviews, price). No extra work — it's the default device family.
- **macOS is a separate native binary** (a distinct native build, not Mac
  Catalyst) — its own archive + review track.
- **Universal Purchase — done.** iOS and macOS now share the **one** bundle ID
  `fi.misaki.donpa` (unified this round), so they're a single App Store Connect
  record / Universal Purchase, not two. (Earlier this section assumed diverging
  IDs; that was reversed — see ARCHITECTURE.md.) Each platform still uploads its
  own binary under the shared record.
- **App age rating**: 4+ / PEGI 3 (App Store Connect questionnaire; nothing in the
  feature set pushes it higher).
- **Release/CD strategy.** A **local release lane** does the whole cut: `make
  release` bumps version/build, opens an auto-merging PR, waits for CI, tags,
  publishes the GitHub release, and uploads to App Store Connect (see
  [RELEASING.md](RELEASING.md)). Credentials stay on the dev machine, so no secret
  management. **GitHub Actions CD** is a possible later step only if the local
  cadence becomes a bottleneck — not needed now.
- **AI disclosure.** The README carries an honest "AI assistance" note. Remaining
  action **at submission**: mirror a short version into the App Store description
  (Apple has no AI flag, so the description is the only store-side lever).
- [ ] **Art assets — licensing (open question).** For now everything stays in
      this repo under the blanket MIT — the assets are AI-generated PNGs with no
      sensitive sources. The concern is **commissioned art**: MIT lets anyone
      redistribute it, which is wrong for art you pay for. So **before the first
      commissioned-art commit** (git history would otherwise retain it under MIT),
      split the license: `LICENSE` (MIT) scoped to code with a carve-out pointing
      to an `ASSETS-LICENSE` (default: all-rights-reserved). Upstream and most
      important: the **commission contract** must actually grant those rights.
      Escalate to a private source-art repo only if source files get
      large/sensitive. (Ties into the AI-disclosure note.)

(The **two-native-targets, no-Catalyst** decision and the distinct Mac bundle id
that follows from it are recorded in [ARCHITECTURE.md](ARCHITECTURE.md).)

## Achievements (the v0.4 milestone — detail)

Mostly an event-plumbing job, but with real permanence to design around.

**No leaderboards — deliberate.** Scores are local and **user-editable by design**
(see Design principles), so a global leaderboard would fill with impossible times
and there's no honest way to police it without server-side validation we've chosen
not to build. Achievements don't have this problem: they're personal, so tampering
only cheats yourself. So: Game Center **achievements yes, leaderboards no.**

**Prerequisites:**

- App registered in **App Store Connect** with the **Game Center** capability
  (the paid account exists; this is just the ASC setup).
- Each achievement defined in ASC. **IDs are permanent once shipped** — add but
  not cleanly rename/remove — so design the scheme up front (e.g.
  `clear.modern.large.insane`, `streak.10`, `time.sub60`).

**Design — keep it decoupled:** the game emits to an **internal achievement layer**
(an `AchievementEvent` per win carrying `GameConfig` + time + streak) with a local
store and in-app display; Game Center bolts on later as one backend behind it, no
rework. Achievements can thus be tracked and shown **offline now**. It crosses a
line the app hasn't yet — **online + account-bound** — so the GC auth flow must
degrade gracefully to the local layer when declined/failed.

**Design principles** (decide the actual list when building). Avoid filler: plain
"clear each size/difficulty" is *inevitable, not earned*. Every achievement should
reward one of:

- **Skill / mastery** — speed thresholds (sub-N seconds), no-flag wins (flag
  count stayed 0), efficiency (few clicks), conquering the near-unsolvable Insane
  tier, or boards the solver rated unsolvable-without-guessing.
- **Streaks / tension** — N wins in a row (a loss resets); rewards nerve, far
  better than "total wins" grind milestones.
- **Hidden / playful** — quirky surprises players stumble into and screenshot:
  win in under 3 clicks, oddly-specific times (the "13-second cursed clear"), a
  flag-everything win, losing on the *second* click (a wink — the first is safe).
- **Identity / epic-tied** — feats unique to Donpa's variants once they
  ship: first torus clear, hex Insane, "went around the world" (a wrap exploit).
  Generic Minesweeper can't offer these — the strongest long-term hook.

Lean toward a curated set where each entry is interesting; a couple of gentle
starters (first clear) are fine as an on-ramp, but the bulk should be earned.

**Steps when ready:** internal achievement layer + local UI → GameKit auth on
launch → report progress on events → GC achievements UI → define achievements in
App Store Connect.

---

## Creative identity & theme

**Shipped:** manga result screen (win/loss/new-record panels), a "squad resting"
pause panel, the interactive title screen, a procedural app icon, and **procedural
manga chrome glyphs** (`MangaIcon`: war-medal High Scores button, Quonset-hut home
barracks, swallowtail flag, pause/play, boot-print "dig" glyph). The mode toggle is
a dig|flag segmented pair in distinct mode colours; the status bar carries a
tappable config "change game" badge. The **board's unopened tiles carry a faint
manga screentone keyed to the input mode** — Ben-Day dots for dig, diagonal hatch
for flag. The cue is the *pattern*, not colour, so it's colour-blind safe (ink is
brightness-balanced so a screentoned tile averages back to the bare-tile gray).
The manga flavour lives in the chrome; the **board grid stays the classic look**
(a full "inked paper" board theme wasn't distinct enough to justify itself and was
dropped — revisit only with a genuinely different treatment).

**Ideas to revisit:**

- **More screentone accents** — the dot/hatch vocabulary could extend to other UI,
  but it's easy to overdo: keep it meaningful (it *means* "unopened / this mode"),
  not decorative, or the UI gets noisy.
- **Art sources** — the scene panels are DALL·E (commercial-use OK via OpenAI TOS;
  verify before ship); the app icon is *procedural*, not DALL·E. When commissioning
  final art, consider a real manga artist for a consistent character sheet — and a
  human pass to replace AI kana with proper typeset lettering is recommended
  regardless.

Still open:

- **Sounds** — usually a mute-play genre, but a melodramatic manga "ドーン!"
  sting could fit the result-panel gag specifically. Would need a mute toggle.
- **Name native-check** — **Donpa Squad / ドンパ隊** is settled (repo + types +
  docs renamed), but worth a JP-native gut-check **before registering bundle IDs
  with Apple** (store name + bundle ID are painful to change post-registration).

## Distribution & extras (later)

- [ ] **Static home page** (marketing/landing site for the app).
- [x] **TestFlight** beta distribution (iOS + Mac) — live; the channel for
      pre-release testing.
- [ ] **watchOS version?** — a big maybe; minesweeper on a tiny screen is its
      own design problem. Parked.
- [ ] **Tip jar?** — see the monetization note below; would be a *deliberate*
      exception to the no-monetization stance, not ads/IAP-for-content.

## Design principles

- **No anti-cheat, by design.** Scores are local and user-editable (low
  security, by choice). This is *why* global leaderboards are out of scope (see
  Achievements): with no validation they'd just fill with impossible scores.
  Achievements stay personal, so tampering only cheats yourself.

## Deliberately out of scope

Per project conventions: **no ads, no microtransactions, no pay-to-win**; no
third-party dependencies; the older Intel Mac is not targeted. No online
multiplayer for v1.0. (Cross-device *score* sync ships in v0.2.0, but that's the
user's own iCloud KVS — not a server or social layer.) A **tip jar** — optional,
content-neutral support — is the one monetization form under consideration.
