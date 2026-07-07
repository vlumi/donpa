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
sync + big boards), and **v0.3.0** (board variants — wrapped + hex — and the New
Game / scoreboard redesign) shipped to TestFlight; **v0.4.0** (friendly rivalry —
score sharing, rivals + squads, the home-screen redesign, per-board saves, and
the forced-guess luck tracking) is in TestFlight. Carry-over notes from those
milestones live in the Backlog below.

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
badge. Content design settled (2026-07):

- **Locked options show as teasers**, not hidden — progression works because you
  can see the next rung. A locked family is a whole page with a teaser, not a
  greyed-out control.
- **Gate on wins, not games played** — fast for the skilled, never grindy; every
  gate openable in one sitting by someone who's simply good.
- **Derive, don't store**: `UnlockEngine` is a pure function over the existing
  per-config win records — veterans auto-pass everything (no migration), and
  sync is free (derived from the already-synced blobs).
- **The ladder**: Basic never gates (the classics are the anchor). Sizes start
  XS/S/M; winning a size unlocks the next (M→L→XL→XXL→XXXL). Ranks start
  Easy/Normal; winning a rank at ≥S unlocks the next (global, not per-family —
  hex's denser table makes per-family fiddly). Hive unlocks on the first Grid
  win (a first-session discovery moment). Round edges unlock on the first win
  at ≥M. Gates are *access, not goals* — the XXL-win→XXXL gate is fine even
  though no achievement demands XXXL.

- [ ] UnlockEngine beside the achievement layer (shared events, separate concept)
- [ ] Locked-page presentation in New Game (ships ungated with the redesign)

**Feat-based public rank** — the hack-resistant face of progression, deferred here
from the friendly-rivalry milestone (it needs this milestone's feat/event layer):
a rank derived from achievements/feats rather than raw times, so faking it means
faking the feat — "you only cheat yourself". Surfaces in the Mess hall; raw scores
stay trusted-circle only. Each rank should require **specific named feats, not
points** — a rank then *says something* ("a Major has beaten Insane") and stays
comparable; sketch ~7 army ranks (Recruit → … → General), with the top ranks built
from full-clears, purity feats and Insane (respecting the one-sitting cap — no
XXXL requirement).

- [ ] Rank derivation from the earned feat set (design the tiers with the
      achievement list, same permanence care)
- [ ] Rank in the share payload + rival rows (a coarse, comparable public face)

**Practice mode (no-guess boards)** — a deduction-only **onboarding** mode, framed
as *practice*, NOT as a "fairer" alternative to the real game (the standard modes
keep the classic forced-guess risk). Solver-gated generation resamples until the
board is fully deducible. When designing it, also settle the **Basic → "Boot
camp"** reframe (deferred to ride this design): either practice claims the name,
or Boot camp becomes the whole training wing — the classic presets plus practice
under one banner.

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
- [ ] Explain the **forced-guess stamp** (the % is the survival odds the click
      had at that moment; silence on a guess-death = a safe move still existed)
      — the pill's one-word label can't carry this alone (user call)
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
(an `AchievementEvent` per game-end carrying `GameConfig` + time + the purity bits —
`usedFlagEver`/`usedChordEver`, defaulting to violated on a restored save — plus the
guess-odds data) with a local store and in-app display; Game Center bolts on later
as one backend behind it, no rework. Achievements can thus be tracked and shown **offline now**. It crosses a
line the app hasn't yet — **online + account-bound** — so the GC auth flow must
degrade gracefully to the local layer when declined/failed.

**Design principles** (content design settled 2026-07; lock IDs when building).
Avoid filler: plain "clear each size/difficulty" is *inevitable, not earned*. Two
hard rules, then the categories:

- **The one-sitting cap**: no achievement may demand more than a single session —
  beyond that, the Service Record itself is the trophy (the full-clear sums
  already celebrate XL+). Achievement ceiling = size **L**; no "win XXXL", no
  "full-clear every size".
- **No win streaks** — luck-heavy on the dense ranks; rewards variance, not nerve.

- **Skill / mastery** (floored at ≥ M Normal so they can't be farmed on XS Easy) —
  no-flag win, no-chord win, both at once ("bare hands"); the classic Expert
  speed ladder (sub-100 s, sub-60, sub-40); an Insane win (≥ M — XS Insane is a
  lottery, and Insane itself must be unlocked first); a Round win at L+; a
  **Lunatic win** (any size — at 20% the tier itself is the feat, and the luck
  stats will show what it cost).
- **Guess-odds feats** — survive a *forced* guess, tiered by the odds: **Coin
  flip** (~1/2), **Long shot** (≤ 1/3), **Miracle** (≤ 1/4). Reads the v0.4.0
  forced-guess tracking (the `luckiestGuess` record makes these retroactive).
  Worse than 1/4 exists but is rare even on Insane — the tiers stop at Miracle.
  Farming bad odds self-punishes: you mostly die.
- **Full-clear tie-ins** — full-clear a size (≤ L), the Basic trifecta, the
  trifecta under a total time (the Record already computes the sums).
- **Tiered milestones** (deliberately few — texture, not the game) — wins
  10/100/1000, tiles opened 100k/1M, mines disarmed 1k/10k/100k.
- **Hidden / playful** — quirky surprises players stumble into and screenshot:
  losing on the *second* click (a wink — the first is safe), the 13-second
  cursed clear, a loss at ≥ 99% progress ("so close"), a win past 999 seconds
  ("Overtime" — the old timer-cap joke).
- **Identity / epic-tied** — feats unique to Donpa's variants: first torus
  clear, hex Insane. Generic Minesweeper can't offer these — the strongest
  long-term hook.

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
