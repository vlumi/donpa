# Roadmap

How Donpa gets from classic Minesweeper to the full "epic" vision at **v1.0**.
Two architectural seams — `Topology` (logical neighbours) and `CellLayout` (pixel
geometry) — let most features land as a new conformer plus UI, without touching
game logic.

Versions are indicative, not contractual. Each minor groups related work into one
meaty release: v0.4.0 = friendly rivalry (score sharing); v0.5.0 = progression
(achievements, gating, practice); v1.0.0 = the store release.

**Shipped milestones live in [CHANGELOG.md](CHANGELOG.md)** (full detail) and are
summarized in the [README](README.md) version history — this roadmap stays
forward-looking. For the record: **v0.1.0** (classic), **v0.2.0** (cross-device
sync + big boards) shipped to TestFlight; **v0.3.0** (board variants — wrapped +
hex — and the New Game / scoreboard redesign) is feature-complete on `main`,
awaiting a release build. Carry-over notes from those milestones live in the
Backlog below.

---

## Backlog (unversioned)

Polish and smaller features that can land in any release — not milestone gates.
The numbered milestones below are the real pillars (sharing, then progression);
these slot into whichever release they're ready for.

**Gameplay fairness** (builds on the v0.1 logical solver):

- **"No-guess" generation is NOT a fairness fix for the normal game** — a chance
  of a forced guess is part of classic Minesweeper's character, so the standard
  modes keep it. The solver-gated no-guess machinery (cheap; `Solver` +
  `TierAnalysis` already exist, generation just resamples until solvable) instead
  finds its purpose as a **practice mode** — see the progression milestone.
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
- [ ] **Two-device iCloud sync verification** — KVS is unreliable on the simulator;
      confirm score/career sync on a real iPhone + Mac under one Apple ID.
- [ ] **JA/FI native review** — the strings are the maker's drafts; refine from
      play-testing feedback ("report weirdnesses"), not a string-by-string review
      pass. Catalog review markers were dropped as noise while strings churn —
      reintroduce `needs_review` flags only if a systematic pass happens once
      things stabilize. Continuous, not a release gate.

**Carry-overs (deferred, revisit when relevant):**

- [ ] **A focused-cell cursor model** — unblocks two features at once: **keyboard
      play on Mac** (arrow-key move + reveal/flag keys, so the board is playable
      without a mouse — today the keyboard only drives app commands, not cells) and
      **per-cell board VoiceOver** (both need the same navigable cursor, scaled to
      huge boards — swiping/reading 10k cells one-by-one doesn't). Co-design with
      big-board navigation; build the cursor once, serve both.
- [ ] **KVS blob pruning** — a reinstall mints a new sync slot, orphaning the old
      blob. Deferred (a dead reinstall looks like an offline device; blobs are
      tiny). Revisit only near KVS storage limits.

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

## v0.4.0 — Friendly rivalry (score sharing)

Peer-to-peer competition built on **trust, not anti-cheat** (no server, no global
tracking): share scores as a QR code — or a tappable link — between people who know
each other, compare, and track rivals. Design settled 2026-07; depends on the
scoreboard redesign (shipped — the table it overlays). Sequenced BEFORE progression
on purpose: it's self-contained and rides the finished scoreboard, while
progression's permanent commitments (achievement IDs, balance) are best done last.

- [ ] QR share: best + wins per config (career opt-in), display name typed at share
      time — no identity stored in the scores themselves
- [ ] **Universal Link delivery** — the share is an `https://` link (static
      apple-app-site-association, no backend); the QR just encodes it, so it also
      opens from the **system Camera / Messages** and on **macOS**, falling back to
      a web page when the app isn't installed. Self-contained (payload in the URL)
      to keep the no-server stance; the in-app scanner becomes the fallback path
- [ ] Signed payloads (spoof-resistant, trust-on-first-use) with a cross-device
      share identity; hardened decode (size caps, validation, versioned envelope)
- [ ] In-app scanner (iOS; Mac via image import) + a separate, deletable friends
      store — shared data is **never merged into your own stats**
- [ ] **Groups** (receiver-side only): organize contacts into circles — family, a
      tight friend group — with strangers sandboxed in their own; the share payload
      knows nothing of groups
- [ ] Comparison report: career side-by-side + per-board head-to-head + tally
- [ ] Rivals interleave into the high-score table as ranked rows, scoped by **one
      active comparison target — a single friend or a group** (off by default, so
      nothing touches your table unless chosen)
- [ ] Feat-based public **rank** — the hack-resistant face of progression. Depends
      on the progression milestone's feat/event layer, so it lands with or after
      that (deferred from the first sharing pass; raw scores stay trusted-circle only).

## v0.5.0 — Progression: achievements, gating & practice

Engagement features grouped because they all ride one **game-end event layer** and
turn on the same "what counts toward stats" question. Held **last on purpose**:
achievement IDs are permanent (like the scoreboard keys), so they're designed once
the full variant matrix exists and can be referenced without churn.

**Achievements** — see the **Achievements** section below for the architecture,
the no-leaderboards decision, and the design principles. Build-out:

- [ ] Internal achievement layer (events on game-end → local store) + in-app UI
- [ ] Local + iCloud-KVS sync of the earned set (reuses the cross-device sync blob)
- [ ] Game Center reporter bolted on behind the layer (achievements only)
- [ ] The curated achievement list defined (IDs locked) in App Store Connect

**Progressive gating** — content unlocks so a new player isn't hit with the full
size × rank × family matrix at once. A second consumer (`UnlockEngine`) of the same
game-end events — an unlock can trigger on the same signals without being a visible
badge. The paged New Game is built for it: a locked **family is a whole page** with
a teaser ("clear a Grid at Veteran+ to open the Hive"), not a greyed-out control.

- [ ] UnlockEngine beside the achievement layer (shared events, separate concept)
- [ ] Unlock triggers + which axes gate (extreme sizes? families?) decided
- [ ] Locked-page presentation in New Game (ships ungated with the redesign)

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

**How to play (static reference)** — a `?` on the title screen (and reachable from
About) opens a **static** "how to play" page: reveal/flag, what the numbers mean,
chording, flags-remaining, win/lose. Manga/comic-styled **illustrations** (image
assets, like the result panels) carry the explanation with minimal text — clearer
than prose for chording, and light on JA/FI translation. Sibling to practice mode
(the *reference*; practice is the *interactive teach*), which is why it lands here.

- [ ] Static illustrated page + a `?` opener (title + About), no game logic
- [ ] Comic-styled frames (reuse the manga asset-slot pattern), not screenshots
      (authored art reads clearer + ages better than cropped board captures)
- [ ] Interactive teach deferred — let **practice mode** be the "now try it" half
      rather than building a separate tutorial engine

## v1.0.0 — The store release

The features are in by 0.5; 1.0 makes them ship-shape for the public App Store.
(The original "epic set composes" goal was reached in 0.3.0.)

- [ ] Real-device test pass — older/slower devices, iPad, small screens; profile
      huge boards on hardware; XXXL memory/leaks in Instruments
- [ ] Settings, theming, polish sweep across all modes
- [ ] Documentation + screenshots per mode; store listing (incl. the short
      AI-assistance note in the description)
- [ ] App Store submission (age rating is set; review readiness)
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

(The **two-native-targets, no-Catalyst** decision — with the shared bundle id /
Universal Purchase — is recorded in [ARCHITECTURE.md](ARCHITECTURE.md).)

## Achievements (the progression milestone — detail)

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
third-party *runtime* dependencies; the older Intel Mac is not targeted. No online
multiplayer, **no server, no accounts, no global leaderboards** — ever the plan.
(Cross-device *score* sync (shipped in 0.2.0) is the user's own iCloud KVS, and
score *sharing* (the friendly-rivalry milestone) is peer-to-peer QR between people
who know each other — neither involves a server or a global social layer.) A **tip jar** — optional,
content-neutral support — is the one monetization form under consideration.
