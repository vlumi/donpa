# Roadmap

How Donpa gets from classic Minesweeper to the full "epic" vision at **v1.0**.
Two architectural seams — `Topology` (logical neighbours) and `CellLayout` (pixel
geometry) — let most features land as a new conformer plus UI, without touching
game logic.

Versions are indicative, not contractual. Each minor groups related work into one
meaty release: v0.4.0 = friendly rivalry (score sharing); v0.5.0 = progression
(achievements, gating, practice); v0.6.0 = finishing touches;
v1.0.0 = the store release.

**Shipped milestones live in [CHANGELOG.md](CHANGELOG.md)** (full detail) and are
summarized in the [README](README.md) version history — this roadmap stays
forward-looking. For the record: **v0.1.0** (classic), **v0.2.0** (cross-device
sync + big boards), and **v0.3.0** (board variants — wrapped + hex — and the New
Game / scoreboard redesign), and **v0.4.0** (friendly rivalry — score sharing,
rivals + squads, the home-screen redesign, per-board saves, the forced-guess
luck tracking, and the Lunatic tier) shipped to TestFlight. **v0.5.0
(progression) is now in development.** Carry-over notes from shipped milestones
live in the Backlog below.

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
  found its purpose as the **Drills practice family** (shipped in v0.5.0 —
  repair-based generation, far beyond resampling; see CHANGELOG).

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

Engagement features grouped because they turn on the same "what counts toward
stats" question. Held **last on purpose**: achievement IDs are permanent (like the
scoreboard keys), so they're designed once the full variant matrix exists. The
full implementation-ready spec — exact unlock rules, the complete achievement
list with IDs/titles/rules, the rank ladder — lives in the **Progression spec**
section below; this block is the build order. Note the sequencing freedom: the
UnlockEngine derives from win RECORDS (not events), so **gating can ship first,
standalone**; only achievements need the game-end event.

**The milestone SHIPPED in full** (b18–b21; see CHANGELOG): gating and
achievements (`UnlockEngine`/`UnlockGates`, `AchievementEngine`/`AchievementStore`
+ the Decorations grid), with the Progression spec below staying as the
reference for value tuning. The one intentionally-deferred piece — the **Game
Center reporter** — moved to the v1.0.0 runway (GC only goes live at the store
release anyway).

**Practice mode — SHIPPED as the Drills family** (FI Soha, JA 演習; see
CHANGELOG): verified no-guess boards, XS–XL at 12 %, leftmost New Game page,
per-size best times (Drills times are only comparable to Drills times, so its
own scoreboard rows are honest). The Basic → "Boot camp" reframe resolved
itself: practice took its own family and name, Basic stays Basic. The Drills ×
achievements/gating rules are pinned in the Progression spec (gentle feats and
milestones count, skill feats exclude Drills, Drills wins climb the size
ladder).

**How to play — SHIPPED** (see CHANGELOG): the `?` on the home screen (and in
About) opens the static in-app guide — true-to-board mini diagrams, the
forced-guess stamp and the exact-but-conservative luck fine print included —
with the expanded English version live at donpa.app/how-to-play. The in-app
page stays canonical (offline, localized); interactive teach stays deferred to
Drills, as planned.

**Post-b19 tail — SHIPPED** (decided 2026-07-09; see CHANGELOG). The Rivals
pass plus four small features, done:

- **Rivals end-to-end UX pass** — walked share → add → compare → nearby with
  fresh eyes; the sync toggle now also lives in the Mess hall, sharing is
  gated on a name, signed-out iOS points to Settings, and a finished Nearby
  exchange keeps the received card.
- **Question-mark flag cycle** (flag → ? → clear) as an opt-in Settings toggle,
  default off; a `?` never counts toward the mine counter or chording but still
  rules out a Bare Hands win, and — as pinned — carries no achievement.
- **Minimal sound**, on by default (mutable from Settings, home, or pause; the
  iPhone ringer switch mutes it via an `.ambient` session). **Procedural**,
  generated by `Scripts/assets/make-sounds.swift` — no licensing, no deps,
  tunable by editing numbers.
- **Richer haptics** (iOS only), on by default; the Settings toggle now also
  gates the win/lose result buzz. Flag/chord/dig transients, dig scaled by
  cascade size.
- **Drills as the newcomer default** — a fresh install's New Game opens on
  Drills; veterans keep their remembered family.

Note for future audio work: the flood-open sound is keyed on hitting a 0
(the fuller variant plays whenever a region cascades, however it was opened).

## v0.6.0 — Finishing touches

**OPEN as of 2026-07-10** (0.5.0 shipped in full through b21). From the
2026-07-09 backlog + platform-capability review: items that each land a more
finished 1.0, none individually a gate — evaluate each and cut freely; every
one should be a modest build. (The smaller half of the original list — the
Rivals UX pass, `?`-flags, sound, the Drills default, haptics — was pulled
into 0.5.0 and shipped there.)

**From the backlog / parked ideas:**

- [ ] **A focused-cell cursor model** — the highest-value item here: unblocks
      **keyboard play on Mac** (arrow-key move + reveal/flag keys — a store-front
      Mac game shouldn't need a mouse) and **per-cell board VoiceOver** (the one
      a11y gap left) with one navigable cursor, scaled to huge boards. Also the
      seam that iPad hardware-keyboard play and game-controller support would
      share. Co-design with big-board navigation.
- [ ] **macOS windows must fit small/scaled displays** (found on-device,
      2026-07-10): fixed window/sheet minimums can beat low-resolution logical
      sizes and the "larger text" scaled modes (accessibility), and macOS
      sheets CAN outgrow their window — the Mess hall did (~784pt against the
      640pt-min window) until the share-card redesign (Nearby promoted, QR
      behind a button) brought it inside. Remaining: audit every fixed
      window/sheet minimum (game window 680×640, How to play, Head-to-head,
      QR zoom) against the smallest scaled-display heights, with "fits WITHIN
      the window at every window size" (the Scoreboard's
      `available: windowSize` convention) as the acceptance criterion.

**Platform capabilities (all native, all serverless):**

- [ ] **App Intents / App Shortcuts** (iOS 16+) — "Continue my board" / "Start
      Drills" from Spotlight and Siri; small, no UI beyond the intent
      definitions.
- [ ] **Widgets** (WidgetKit, home + lock screen) — a continue-your-board deep
      link and a career-stats/luck-line widget. Needs an app group to share the
      stores.
- [ ] **Review prompt** (`SKStoreReviewController`) — ask after a new best
      time, never after a loss. Small, and it matters for a small app's store
      trajectory.
- [ ] **App Clip** — a rival's donpa.app share link offers "play a board now"
      without installing (an instant Drills board as the hook). Rides the
      Universal Link infrastructure; turns the social loop into an acquisition
      loop. The largest item here.
- [ ] **SharePlay** (GroupActivities) — race the *same generated board* over
      FaceTime; Apple's session infrastructure, so still no server. Real
      multiplayer that respects the no-server principle.
- [ ] **TipKit contextual tips** (iOS 17+, availability-gated) — one-time
      nudges like "this number's flags match — tap it to chord". Lower value
      now that how-to-play shipped; keep only if it earns its place.

Evaluated and NOT parked (recorded so the next review doesn't redo it): Live
Activities (the game is foreground by nature), CloudKit save-sync (KVS is too
small for board blobs; per-device saves were a deliberate call), Spotlight
indexing beyond App Intents, minimap drag-to-reposition/resize (the hide
toggle covers the pain — stays in the backlog).

## v1.0.0 — The store release

The features are in by 0.5; 1.0 makes them ship-shape for the public App Store.
(The original "epic set composes" goal was reached in 0.3.0.)

- [ ] **Game Center reporter** (from 0.5.0 — GC only goes live at the store
      release): ASC achievement definitions per the tier-flattening mapping in
      the Progression spec (sandbox from day one; they only go LIVE — and
      permanent — with the first App Store release), a GKAchievement reporter
      behind the store, graceful degradation when auth is declined. **Every ASC
      definition needs its own 1024×1024 image (29 after tier-flattening)** —
      export them from `MedalView` (the MedalGalleryRender harness is the seam).
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

## Progression spec — gating, achievements, rank (implementation-ready)

The v0.5.0 progression pillars, specified to build-from. Fine-tune values here
BEFORE implementation; IDs and requirement rules are permanent once shipped.

### Progressive gating (`UnlockEngine`)

**Shape:** a pure, stateless DonpaCore type — no stored unlock set, no event
feed. `unlocked(_ config: GameConfig, records: [String: ScoreRecord]) -> Bool`
plus `requirement(for:) -> UnlockRequirement?` (nil = never locked; otherwise
the teaser's copy key + progress). Inputs are the scoreboard's merged display
records; recompute whenever they change (already `@Published`). Veterans
auto-pass everything; sync is free; **no migration and no event layer needed —
gating can ship before achievements.**

**Win-credit table** (what a win counts FOR — the previously fuzzy part):

| Win on | Size ladder | Rank ladder | Hive gate | Round gate |
|---|---|---|---|---|
| Grid / Hive | ✓ its size | ✓ its rank, if size ≥ S | ✓ | ✓ if size ≥ M |
| Drills | ✓ its size | — (no rank axis) | ✓ | ✓ if size ≥ M |
| Basic | ✓ mapped size | — (no rank axis) | ✓ | ✓ if mapped ≥ M |

Basic preset → ladder-size mapping (declared, geometry-spirited): Beginner = XS,
Intermediate = S (exact geometry), Expert = M. Drills wins climbing the size
ladder is deliberate: the practice range literally trains you up to bigger
boards, and gates are access, not goals.

**The gates** (everything not listed is open from install):

- **Sizes**: XS/S/M open. Any credited win at M → L; L → XL; XL → XXL;
  XXL → XXXL. Applies uniformly in every sized family — including Drills
  (Drills L needs an M win somewhere, same predicate, no special case).
- **Ranks** (global, not per-family): Trainee/Sapper open. A credited Sapper win
  (≥ S) → Veteran; Veteran → Ace; Ace → Legend; Legend → Lunatic.
- **Hive**: first credited win in any square family (Drills/Basic/Grid) — the
  "you've cleared a board, here's a new shape" discovery moment.
- **Round edges**: first credited win at ≥ M (any family). One gate covers Grid
  and Hive.
- **Never gated**: Drills, Basic, Grid, Flat edges, the XS/S/M · Trainee/Sapper
  starting matrix.

**Reset semantics (decided 2026-07-09):** the stats reset RE-LOCKS gated
content — pure derive-don't-store, reset means a truly fresh start, and every
gate re-opens in one sitting for a returning player. The reset confirmation
copy must say so ("also re-locks boards"). Achievements are the opposite:
permanent, exempt from the wipe (see the store note below).

**Escape hatches (decided):** a board arriving from OUTSIDE the picker is always
playable — head-to-head "play this board", a share/deep link, and resuming any
in-progress save all bypass gates (an invitation from a rival IS the discovery
moment; blocking it would punish the social loop). Such play earns unlock credit
normally. There is NO unlock-all setting: every gate opens in one sitting for a
player who's simply good, and veterans derive-pass anyway.

**Teaser UI** (locked = visible, never hidden):

- Locked **size/rank chip**: rendered at 0.45 opacity with a small `lock.fill`
  badge (SaveDot's corner idiom, bottom-trailing). Tapping does NOT select; it
  swaps the row's caption to the requirement line for a few seconds. A11y: the
  chip keeps its label, gains value "Locked — <requirement>".
- Locked **Hive page**: the pager page shows the family glyph large + the
  requirement as its caption (detail "Locked" / tagline "Win any board to
  unlock"); its tab renders dimmed with the padlock badge. The pager still
  swipes to it (teaser = seeing the next rung).
- Locked **Round segment**: dimmed + padlock in the segmented toggle; tap shows
  the requirement caption. Keyboard ←/→ skips locked entries (`stepped(within:)`
  over the unlocked slice — the Drills-ladder helper generalizes).
- Requirement copy (localize EN/FI/JA at build): "Win an M board to unlock" /
  "Win any board to unlock the Hive" / "Win an M board to unlock Round edges" /
  "Win a Sapper board (S or larger) to unlock".
- **Unlock moment**: when a win flips any predicate (diff before/after), the
  result panel adds an "UNLOCKED: <thing>" corner sticker (PillStamp dress,
  bottom-trailing corner) + a VoiceOver announcement; several at once collapse
  to "New boards unlocked". The scoreboard's per-row play button follows the
  same predicate (row stays visible; button hidden while locked).
- **Testability**: `-donpa.gates.fresh` launch argument makes the engine see
  empty records (TestFlight veterans can experience gates); predicate unit
  tests + one UI test ride it.

### Achievements — architecture

Unchanged decisions: internal layer first, in-app display, offline; **Game
Center achievements yes, leaderboards no** (scores are user-editable by design;
feats only cheat yourself); GC bolts on later as a reporter behind the store,
degrading gracefully when auth is declined. IDs are permanent.

**GC mapping (for the Game Center reporter step):** Game Center has no tier
concept — a flat list where each
achievement has a point value (≤ 100 each, 1 000 budget per game), a
`percentComplete` bar, and an optional hidden flag (the four gags use it). So
the reporter FLATTENS our tiers: one-shot feats map 1:1
(`fi.misaki.donpa.<id>`), each tier of a tiered feat becomes its own ASC entry
(`fi.misaki.donpa.miles.wins.10` / `.100` / `.1000`), and the reporter feeds
`percentComplete` on the next unearned tier so GC shows live progress
("470/1000 wins = 47 %"). 22 internal IDs = 18 one-shots + 11 tier steps →
**29 ASC definitions**; assign the point budget across them when building the
reporter.

**Two evaluation modes, one engine:**

- **Derivable** feats compute from the synced records/career counters (wins,
  best times, full-clear standings, `luckiestGuess`, no-flag/no-chord win
  counters) — so they're **retroactive**: veterans get them stamped on first
  launch, and a cloud restore recovers them.
- **Momentary** feats need the game-end instant (`GameEndEvent`: config, won,
  timeCentiseconds, progress, revealActions) and are stored when earned. Only
  the FOUR HIDDEN feats need this (the purity collapse removed the last
  non-hidden momentary one — the bits keep feeding the stats counters, but the
  event no longer carries them). New data required: a per-game **reveal-action
  counter** (reveals + chords, for "second reveal") — everything else ships.
- `AchievementStore`: earned map id → firstEarnedDate; UserDefaults + the KVS
  sync blob (union merge, earliest date wins). **EXEMPT from the stats wipe's
  reset-epoch (decided 2026-07-09): achievements are permanent**, per platform
  convention — the hidden feats are momentary (un-re-derivable) and Game
  Center can't un-report, so a wiping store would desync from GC forever. A
  feat may outlive the stats that earned it; that's history, not a bug.
  Derivable feats are stamped into the store when first observed (stable
  dates + a single GC report each).

**Drills rules (pinned):** gentle/starter feats and career milestones count on
Drills; skill feats never do — enforced structurally, since every skill feat
floors on a RANK and Drills has none. Luck feats can't happen there (no forced
guesses on a no-guess board, by construction).

**Presentation:** a **Decorations** section (FI *Kunniamerkit*, JA *勲章*) in
the Service Record above Commendations: a medal grid — earned = inked with date,
unearned = silhouette + requirement, hidden = "?" until earned, tiers as
bronze/silver/gold laurels. Earn moment = result-panel sticker + VoiceOver
announcement (same slot as the unlock sticker; queue if both fire).

### The achievement list (22 IDs; tiers noted)

Floors write as "≥ M Sapper" = size M or larger AND rank Sapper or denser
(rank floor structurally excludes Drills/Basic). Titles EN · FI · JA — tune
freely; IDs lock at build.

**Starters & identity**

- `win.first` — **Boots On** · *Saappaat jalkaan* · *初陣* — "Win your first
  board." Any family, Drills included (the on-ramp).
- `drills.l` — **Graduation Exercise** · *Loppukoe* · *卒業演習* — "Win a
  Drills board at size L." The practice capstone (ceiling L per one-sitting).
- `hive.first` — **Into the Hive** · *Kennostoon* · *ハイブ初制覇* — "Win your
  first Hive board."
- `round.first` — **Full Circle** · *Täysi kierros* · *世界一周* — "Win a board
  with Round edges." Any size — the first-torus identity moment (the L+ skill
  variant was cut as redundant).
- `hive.insane` — **Hornet's Nest** · *Herhiläispesä* · *スズメバチの巣* — "Win
  a Hive board at Insane, M or larger." Donpa-only feat; generic minesweeper
  can't offer it. (No Grid twin on purpose: `win.first` is effectively
  grid-first, and Grid mastery already lives in `insane.win` + the speed
  ladder + the trifecta.)

**Skill & mastery** (all ≥ M Sapper unless stated)

- `purity.noflag` — **Bare Hands** · *Paljain käsin* · *素手で* — "Win without
  placing a single flag — every mine held in your head." Derivable (per-config
  no-flag counter + floor). ONE purity feat, not three (collapsed 2026-07-09):
  a chord can only fire on matching flags, so no-flag strictly IMPLIES
  no-chord — "bare hands" was the same feat twice — and no-chord alone (flag
  freely, click one by one) is slower play, not harder play. Resumed games
  can't earn it (the purity bit defaults to violated on restore — decided).
- `speed.expert` (tiers 180/120/90) — **Expert Sweep** · *Salamaraivaus* ·
  *エキスパート速攻* — "Clear Basic Expert in under 180 / 120 / 90 seconds."
  (Retuned from 100/60/40 pre-release: even bronze was near-world-class,
  towering over the rest of the set; thresholds are tunable, only IDs lock.)
  Derivable from the Expert best time.
- `insane.win` — **Stuff of Legends** · *Legendojen ainesta* · *生ける伝説* —
  "Win a Legend board, M or larger." (XS Legend is a lottery.) Renamed from
  the draft "Certifiably Insane": the spec predated checking the SHIPPED tier
  vocabulary — `.insane`'s in-app label is **Legend** (Trainee/Sapper/Veteran/
  Ace/Legend/Lunatic), so every feat description says Legend, not Insane.
- `lunatic.win` — **Full Moon** · *Täysikuu* · *満月* — "Win a Lunatic board —
  any size. At 20 %, the tier is the feat." (Name = the crescent-moon insignia.)

**Luck** (derivable from `luckiestGuess` — retroactive to 0.4.0 data; names
match the in-game toasts)

- `luck.coinflip` — **Coin Flip** · *Kolikonheitto* · *コイントス* — "Survive a
  forced guess at even odds or worse."
- `luck.longshot` — **Long Shot** · *Kaukolaukaus* · *一か八か* — "…at 1-in-3
  or worse."
- `luck.miracle` — **A MIRACLE** · *IHME* · *奇跡* — "…at 1-in-4 or worse."
  (Worse exists but is rare; the ladder stops here. Farming bad odds mostly
  kills you — self-balancing.)

**Full-clear tie-ins** (derivable from the Record's standings)

- `fullclear.size` — **Sector Secure** · *Sektori varmistettu* · *区域制圧* —
  "Full-clear every rank of one size (any family × edges leaf, any size)." The
  original ≤ L cap was lifted 2026-07-10: an XXXL-only player full-clearing
  their size does something strictly harder, so it counts too.
- `trifecta` — **The Classics** · *Klassikot* · *クラシック三冠* — "Win
  Beginner, Intermediate and Expert."
- `trifecta.time` — **Hat Trick** · *Hattutemppu* · *ハットトリック* — "The
  classic trifecta with combined bests under 5:00." (Tune the bar here.)

**Milestones** (tiered; career counters, Drills included — texture, not goals)

- `miles.wins` (10/100/1000) — **Campaigner** · *Sotaretkeläinen* · *歴戦* —
  "Win 10 / 100 / 1 000 boards."
- `miles.tiles` (10k/100k/1M) — **Ground Covered** · *Kilometrejä takana* ·
  *開拓者* — "Open 10 000 / 100 000 / 1 000 000 tiles." (10k starter tier
  added at review so the ladder reaches gold like its siblings.)
- `miles.disarmed` (1k/10k/100k) — **Bomb Squad** · *Pommiryhmä* ·
  *爆発物処理班* — "Disarm 1 000 / 10 000 / 100 000 mines (flagged on finished
  boards)."

**Hidden** (momentary; shown as "?" until earned)

- `hidden.second` — **Beginner's Unluck** · *Aloittelijan epäonni* · *二歩目*
  — "Lose on your second reveal." (The first is always safe — the wink.)
- `hidden.thirteen` — **Cursed Time** · *Pahan onnen minuutti* · *呪いの13秒*
  — "Win with a final time of 13.x seconds."
- `hidden.soclose` — **So Close** · *Niin lähellä* · *あと一歩* — "Lose with
  99 % or more cleared."
- `hidden.overtime` — **Overtime** · *Jatkoaika* · *延長戦* — "Win a board
  after more than 999 seconds." (The old timer-cap joke.)

Deliberately ABSENT: streaks (luck-heavy — rewards variance, not nerve),
feats that REQUIRE big multi-session boards (the one-sitting cap keeps every
feat earnable in an afternoon; big boards can still *count* toward feats — see
fullclear.size — they're just never the only path), per-size/per-rank
attrition filler.

### Feat rank — SCRAPPED (2026-07-09)

Decided against, not parked: in Donpa's trusted-circle model every rival
already sees your real times and Decorations, so a one-word rank compresses
information friends already have; cumulative gates park nearly everyone at
the bottom ranks; and it would have been a third status system in the release
that added the other two. If a one-glance comparator proves wanted later, the
idea returns on its own merits (an earlier ladder sketch lives in git
history).

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

- **Sounds** — moved to the v0.6.0 tentative list (the "ドーン!" sting + mute
  toggle).
- **Name native-check** — **Donpa Squad / ドンパ隊** is settled (repo + types +
  docs renamed), but worth a JP-native gut-check **before registering bundle IDs
  with Apple** (store name + bundle ID are painful to change post-registration).

## Distribution & extras (later)

- [ ] **Static home page** (marketing/landing site for the app).
- [ ] **Real board images on donpa.app/how-to-play** — replace the monospace
      unicode diagrams with actual rendered boards. Not hand-cropped
      screenshots: export the in-app guide's own `TileDiagram` (+ mode chips)
      headlessly to PNGs, the way `MedalGalleryRender` renders medals — pixel-
      perfect, light + dark variants, regenerable whenever the art changes.
      (The in-app guide keeps its LIVE TileDiagrams — those already render the
      real thing and track dark mode for free.)
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
