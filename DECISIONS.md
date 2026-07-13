# Design decisions

Settled design choices and scrapped ideas, on record so future reviews don't
redo them. This file is the "why it is the way it is" for PRODUCT design;
[ARCHITECTURE.md](ARCHITECTURE.md) covers the technical counterpart, shipped
detail lives in [CHANGELOG.md](CHANGELOG.md), and open future work in
[ROADMAP.md](ROADMAP.md). Decisions are dated where the date carries meaning.

---

## Progression — gating & achievements (shipped 0.5.0; reference)

The implementation reference for the shipped progression systems. IDs and
requirement rules are PERMANENT (like scoreboard keys); titles and tuning
values may still drift — this list is canonical for the ASC achievement
definitions (points, hidden flags, localized titles).

### Gating (`UnlockEngine`)

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
  the requirement caption. Keyboard ←/→ skips locked entries
  (`KeyStep.clamped(within:)` over the unlocked slice).
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
("470/1000 wins = 47 %"). 20 internal IDs = 17 one-shots + 3×3 tier steps →
**26 ASC definitions**; assign the point budget across them when building the
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

### The achievement list (20 IDs; tiers noted)

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
- `speed.expert` (single rung, <180 s) — **Expert Sweep** · *Salamaraivaus* ·
  *エキスパート速攻* — "Clear Expert in under three minutes." (Collapsed from a
  180/120/90 ladder 2026-07-13: tiered SKILL thresholds are progress tracking
  in badge costume — that's the scoreboard's job (best times, pace later);
  the single rung is the rite of passage "you've genuinely learned Expert,"
  honest on any device. Only VOLUME milestones keep tiers.)
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
  forced guess at even odds or worse." (The ONE luck decoration — decided
  2026-07-13: the ladder's Long Shot/Miracle rungs were degrees of pure RNG,
  and Miracle's ≤1/4 trigger practically never occurs on real boards. The
  toast tiers and the luckiest-escape stat keep tracking anything rarer.)

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

## Game Center reporting — opt-in by design

GC only goes live at the store release: ASC achievement definitions follow
the tier-flattening mapping above (sandbox from day one; they only go LIVE —
and permanent — with the first App Store release), reported by a
GKAchievement reporter behind the store, degrading gracefully when auth is
declined. **Every ASC definition needs its own 1024×1024 image (26 after
tier-flattening)** — export them from `MedalView` (the MedalGalleryRender
harness is the seam).
**Opt-in by design (decided 2026-07-13; some players dislike achievements
and the choice is respected):** a toggle INSIDE the Decorations block's
footer (the sync-toggle placement principle — where the feature's
questions arise; a collapsed block hides it entirely), OFF by default;
`authenticate` is called only when enabled, so GC's sign-in sheet can
only appear as a consequence of the player's own choice; enabling
reports retroactively (the engine is derivable, so late opt-in loses
nothing); GC's own banners suppressed (`showsCompletionBanner = false` —
the in-game pill is the celebration) and no `GKAccessPoint`; toggling
off just stops reporting — never wire GC's all-or-nothing reset (local
decorations are permanent; wipes don't touch them, GC shouldn't either).
Keyboard: the toggle joins the medals zone (keyFocused + Pulse, like
sync). **The ask happens at the FIRST DECORATION EARNED** (decided
2026-07-13), not first launch — the first moment the question means
anything, and early enough that GC dates barely suffer; the
asked-and-answer state syncs via KVS OUTSIDE the syncScores gate (the
shareName-Keychain precedent for small preference state), so one answer
covers all devices — GC auth itself stays per-device and lazy.
**Merge rules (decided 2026-07-13):** "asked" merges OR (asked anywhere
= asked; a no-iCloud device may re-ask once — fine); "enabled" merges
LWW by decision timestamp — OR would be a ratchet where the OPT-OUT
loses every conflict to a stale true, the one direction this design
can't afford. Newest human decision wins, both directions.
**Timestamp caveat:** GC cannot be backdated (`lastReportedDate` is
server-stamped at report time), so retroactive reports carry the
enable date; the local store's earned dates (synced) remain the true
record, shown in the app's own grid.
Code SHIPPED 2026-07-13 (`GameCenterMapping` + `GameCenterPrefs` /
`GameCenterReporter`); the remaining ASC-side work is a ROADMAP 1.0 item.

## Sync scope rule — device-scoped vs player-scoped (2026-07-13)

**The score-sync flag does NOT sync** (reversed 2026-07-13, same day, on
reflection): the toggle is a statement about A DEVICE ("this device
participates in the score mesh"), not about the player — a deliberately
un-synced device (shared iPad, test machine) would fight an LWW-synced
flag forever, and the flag-exempt-from-its-own-gate wrinkle was the
design smelling wrong. Per-device enablement stays. The line: DEVICE-
scoped settings don't sync; PLAYER-scoped ones (the GC flag, the GC
asked-state) do.

## Pace — the skill metric is a raw number (2026-07-13)

**Metric — pace (3BV/s), the luck-normalized rate.** 3BV = a board's
minimum taps (one per opening flood + one per non-flood safe cell; well-
defined on hex/wrapped via the board's own adjacency). A lucky low-3BV
board gives a fast TIME but a normal PACE, so the number stays honest.
Losses don't log (pace of an unfinished board is undefined).

**Data — log per config, finest grain** (shipped in 0.6.0): rolling
newest-~10 wins per storageKey, plus a per-config best pace. Collecting at
the finest grain keeps every grouping decision above it reversible; the log
format locked at collection launch.

**Raw numbers, NOT rank bands (decided 2026-07-13):** the displayed skill
reading is the pace number itself. A rank band is a cross-config equivalence
claim ("this pace on Hive means the same as that pace on Grid") that would
need population-scale data per family × edges × density to calibrate
honestly; a raw number makes no such claim and needs no such data. The
scoreboard-tracks-your-progress philosophy (see the decorations
recalibration in CHANGELOG 0.6.0) points the same way. The band-ladder
design this replaced is recorded under Scrapped below.

**Round = VIRTUAL families (decided 2026-07-13):** the pace layer keys
its figures by family × edges — Grid, Grid·Round, Hive, Hive·Round, Basic,
Drills (the last two are inherently flat) — shown only where played. NOT
real families: the Flat/Round toggle in New Game stays as shipped,
family-scoped feats untouched, and nothing migrates (storageKey already
includes edges — the data was always separate). A torus removes the easy
edge regions, so a Round specialist is a different kind of good; a separate
figure says so instead of averaging it away.

**Aggregation model — how pace trickles up (decided 2026-07-13):**

- Two safe operations only: RECENT figures aggregate by unioning the
  underlying windows and taking ONE 3BV-weighted median over the union
  (never median-of-medians); BEST figures are max-of-maxes. Everything is
  read-time computation over the per-config logs — no new storage at any
  level.
- The semantic gate: SIZE is the one axis that folds honestly (pace is a
  rate; the 3BV weighting absorbs XS noise). DENSITY doesn't fold raw
  (Easy is flood-clicking, Lunatic is dense deduction — a raw family
  median measures your density diet, not skill); crossing it requires the
  normalization/band machinery. FAMILY/EDGES never fold — the career
  level gets per-virtual-family display, never a scalar.
- So the one honest raw mid-level is family × edges × density, across
  sizes — and it carries a value ONLY when every size in that ladder has
  at least one logged win (the full-clear-line idiom, transposed): the
  aggregate is a demonstrated claim, not a diet artifact, and an unlit
  line is a chase. Applies to Grid/Hive (per edges) and Drills (its
  XS–XL ladder, one line); Basic is exempt (presets vary size and
  density together). "Has a result" = an entry in the pace LOG — pre-pace
  wins carry no 3BV, so the lines light from fresh play only.
- BEST pace never trickles above per-config: a folded best is just the
  easiest cell's outlier (a 0.00 s XS tap would own the whole row).

## Manga identity — chrome, not board (shipped)

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

## Name check — CLOSED (2026-07-13)

**Name native-check — DONE 2026-07-13.** JP-native gut-check passed (owner
confirmed). Web sweep: no "Donpa" app on the App Store (nearest: CAVE's
DoDonPachi shooters — clearly distinct); existing "Donpa" uses are all
in-universe fiction (a Golden Sun NPC, Sonic's Donpa Motors, a Yu-Gi-Oh
card) — character names, not marks on game titles; no meaning in the big
storefront languages. Bonus: ドンパ is HOKKAIDO DIALECT for "same
age / same cohort" — an accidental perfect fit for a squads-and-rivals
game. USPTO queried 2026-07-13: nothing. J-PlatPat queried 2026-07-13:
closest is 登録4936269 "DonPa／ドンパ" (岸本吉二商店, Amagasaki) — a SAKE-
BARREL maker, classes 20/42 (packaging containers + their rental,
similarity codes 18C03/06/09/13, 42X90): no overlap with a game's
classes 9/41 codes, no confusion, no famous-mark concern. NAME CHECK
CLOSED — nothing gates bundle-ID registration.

## No-guess generation is not a fairness fix

**"No-guess" generation is NOT a fairness fix for the normal game** — a chance
of a forced guess is part of classic Minesweeper's character, so the standard
modes keep it. The solver-gated no-guess machinery (cheap; `Solver` +
`TierAnalysis` already exist, generation just resamples until solvable) instead
found its purpose as the **Drills practice family** (shipped in v0.5.0 —
repair-based generation, far beyond resampling; see CHANGELOG).

---

## Scrapped & rejected

Kept on record so the next review doesn't redo the evaluation. Anything here
can return on new merits — but it re-enters through a fresh argument, not by
default.

### Skill-rank band ladder (2026-07-13)

The v0.7.0 sketch had eight army-themed bands (Recruit → General) computed
per virtual family: each logged win's pace converted to a band via a
per-(family × density) reference table, the family rank = the 3BV-weighted
median band over the recent window, promotion toasts on crossing up.
Scrapped in favour of raw pace numbers (above): balancing the reference
tables so ranks roughly MAP ACROSS configs would demand volumes of real
distribution data to support every threshold; the raw number carries the
same information without the calibration debt. With it went the promotion
toast and rank chips as a share-payload field (raw pace figures / the daily
challenge's same-board comparison cover the social side).

### Feat rank — SCRAPPED (2026-07-09)

Decided against, not parked: in Donpa's trusted-circle model every rival
already sees your real times and Decorations, so a one-word rank compresses
information friends already have; cumulative gates park nearly everyone at
the bottom ranks; and it would have been a third status system in the release
that added the other two. If a one-glance comparator proves wanted later, the
idea returns on its own merits (an earlier ladder sketch lives in git
history).

### Cut from 0.6.0 (2026-07-12)

Free-app test applied — no revenue and no DAU target, so a feature must make
the game better for someone who already likes it:

- **Widgets** — a board doesn't change while you're away, so the widget is a
  static screenshot; needs an app-group migration of the save store (the
  layer that just had a data-loss bug patched). High risk, decorative payoff.
- **App Clip** — solves "try without installing", which the store page of a
  small free game already solves; permanent extra target/size/AASA surface.
- **SharePlay** — the biggest lift; Nearby owns the in-the-room story. If
  real-time co-play ever happens it's its own release.
- **TipKit** — How to play + Drills already teach.

### Evaluated, not parked

Recorded so the next review doesn't redo it: Live Activities (the game is
foreground by nature), CloudKit save-sync (KVS is too
small for board blobs; per-device saves were a deliberate call), Spotlight
indexing beyond App Intents, minimap drag-to-reposition/resize (the hide
toggle covers the pain — stays in the backlog).

### Inked-paper board theme (dropped)

A switchable manga board theme (`BoardTheme` enum, paper/screentone tiles +
ink borders) was built and REVERTED — not distinct enough from classic to
justify itself. The manga flavour lives in the chrome and panels; the board
grid stays the classic look. Revisit only with a genuinely different
treatment (real screentone, heavier ink, custom numbers).
