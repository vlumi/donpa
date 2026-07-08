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

Engagement features grouped because they turn on the same "what counts toward
stats" question. Held **last on purpose**: achievement IDs are permanent (like the
scoreboard keys), so they're designed once the full variant matrix exists. The
full implementation-ready spec — exact unlock rules, the complete achievement
list with IDs/titles/rules, the rank ladder — lives in the **Progression spec**
section below; this block is the build order. Note the sequencing freedom: the
UnlockEngine derives from win RECORDS (not events), so **gating can ship first,
standalone**; only achievements need the game-end event.

**Build order** (each step = roughly one PR; spec section has the details):

- [ ] **G1 — UnlockEngine (DonpaCore)**: the pure predicate + requirement model +
      the win-mapping table, unit-tested (ladder walk, Basic mapping, Drills
      credit, veteran auto-pass on synthetic full records).
- [ ] **G2 — Teaser UI**: locked chips/segments/family page in New Game per the
      spec (dim + padlock + requirement caption), keyboard skip, a11y values.
- [ ] **G3 — Unlock moments + edges**: result-panel "UNLOCKED" sticker +
      VoiceOver announcement; scoreboard play-button rule; the rival/share
      escape hatch; `-donpa.gates.fresh` launch flag + UI test.
- [ ] **A1 — GameEndEvent**: one struct emitted at game end (config, outcome,
      time, progress, action count, purity bits, best survived odds) — the
      purity bits and luck plumbing already exist.
- [ ] **A2 — AchievementEngine (DonpaCore)**: `AchievementID` enum (IDs locked
      per the spec list), derivable predicates over records + momentary matchers
      over the event, per-achievement unit tests.
- [ ] **A3 — AchievementStore**: earned map (id → date), local persistence +
      KVS-blob union merge (earliest date wins; follows the same reset-epoch as
      the stats wipe), retroactive stamping of derivable feats on first launch.
- [ ] **A4 — Decorations UI**: medal grid in the Service Record (earned inked /
      unearned silhouette / hidden as "?"), tier laurels, result-panel earn
      sticker + announcement (shared slot with G3's, queued if both).
- [ ] **A5 — Feat rank** (TENTATIVE — user go/no-go first; the rest of the
      milestone doesn't depend on it): derived rank from the earned set
      (ladder in the spec), rank in the share payload + Mess hall/H2H rows.
- [ ] **A6 (later) — Game Center**: ASC achievement definitions
      (`fi.misaki.donpa.<id>` 1:1), GKAchievement reporter behind the store,
      graceful degradation when auth is declined.

**Practice mode — SHIPPED as the Drills family** (FI Soha, JA 演習; see
CHANGELOG): verified no-guess boards, XS–XL at 12 %, leftmost New Game page,
per-size best times (Drills times are only comparable to Drills times, so its
own scoreboard rows are honest). The Basic → "Boot camp" reframe resolved
itself: practice took its own family and name, Basic stays Basic. The Drills ×
achievements/gating rules are pinned in the Progression spec (gentle feats and
milestones count, skill feats exclude Drills, Drills wins climb the size
ladder).

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
- [ ] …and that the luck stats are **exact but conservative** (best effort, user
      call): recorded guesses always carry true odds, but positions too tangled
      to analyze — and on XXXL anything but a sealed pocket — go unrecorded
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
degrading gracefully when auth is declined. IDs are permanent; ASC IDs =
`fi.misaki.donpa.<id>` 1:1.

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
  sync blob (union merge, earliest date wins; obeys the stats wipe's
  reset-epoch). Derivable feats are stamped into the store when first observed
  (stable dates + a single GC report each).

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
- `speed.expert` (tiers 100/60/40) — **Expert Sweep** · *Ekspertin partio* ·
  *エキスパート速攻* — "Clear Basic Expert in under 100 / 60 / 40 seconds."
  Derivable from the Expert best time.
- `insane.win` — **Certifiably Insane** · *Hullun paperit* · *狂気の沙汰* —
  "Win an Insane board, M or larger." (XS Insane is a lottery.)
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
  "Full-clear every rank of one size, L or smaller (any family × edges leaf)."
- `trifecta` — **The Classics** · *Klassikot* · *クラシック三冠* — "Win
  Beginner, Intermediate and Expert."
- `trifecta.time` — **Hat Trick** · *Hattutemppu* · *ハットトリック* — "The
  classic trifecta with combined bests under 5:00." (Tune the bar here.)

**Milestones** (tiered; career counters, Drills included — texture, not goals)

- `miles.wins` (10/100/1000) — **Campaigner** · *Sotaretkeläinen* · *歴戦* —
  "Win 10 / 100 / 1 000 boards."
- `miles.tiles` (100k/1M) — **Ground Covered** · *Kilometrejä takana* ·
  *開拓者* — "Open 100 000 / 1 000 000 tiles."
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
anything above size L or multi-session (one-sitting cap; the Service Record is
the trophy for those), per-size/per-rank attrition filler.

### Feat rank (the public face) — TENTATIVE: go/no-go before A5

Whether the public rank is wanted AT ALL is still open (user, 2026-07-09) —
confirm before building A5; everything else in this spec stands without it.
If built: derived from the earned set — named feats, not points, so a rank
*says something* and faking it means faking the feat. Cumulative: each rank
also requires the one below. Luck feats deliberately count toward NO rank
(variance again). Surfaces in the share payload, Mess hall rows, and
head-to-head; raw times stay trusted-circle. The ladder deliberately shares no
word with the difficulty tiers in any locale (the tiers read as soldier
archetypes a board demands; the rank is the player's own grade — and rung 1 is
a civilian precisely so the first win "makes you a soldier"):

1. **Civilian** · *Siviili* · *民間人* — everyone starts here.
2. **Private** · *Sotamies* · *二等兵* — Boots On.
3. **Corporal** · *Korpraali* · *伍長* — The Classics + Campaigner I (10 wins).
4. **Sergeant** · *Kersantti* · *軍曹* — Into the Hive + Bare Hands.
5. **Lieutenant** · *Luutnantti* · *中尉* — Certifiably Insane + Expert Sweep
   bronze (sub-100 s).
6. **Major** · *Majuri* · *少佐* — Sector Secure + Full Circle.
7. **General** · *Kenraali* · *大将* — Full Moon + Hornet's Nest + Expert Sweep
   silver (sub-60 s).

Wire format: the share payload carries the rank's ID string (not the earned
set); receivers render it as-is, so future rank additions don't break old
readers.

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
