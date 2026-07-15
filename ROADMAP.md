# Roadmap

Open, future work only. **Shipped milestones live in
[CHANGELOG.md](CHANGELOG.md)** (full detail) and are summarized in the
[README](README.md) version history; **settled design choices and scrapped
ideas are recorded in [DECISIONS.md](DECISIONS.md)**; the technical "why" is
[ARCHITECTURE.md](ARCHITECTURE.md).

Versions are indicative, not contractual. For the record: v0.1.0 (classic),
v0.2.0 (cross-device sync + big boards), v0.3.0 (board variants + the New
Game / scoreboard redesign), v0.4.0 (friendly rivalry), v0.5.0 (progression)
all shipped to TestFlight; **v0.6.0 (keyboard & accessibility) is in beta**.

---

## Backlog (unversioned)

Polish and smaller features that can land in any release — not milestone
gates.

**Keyboard follow-ons:**

- [ ] **Game controllers** — the cursor seam is ready.
- [ ] **A real VoiceOver session** to validate the spoken-cell flow.

**Carry-overs (deferred, revisit when relevant):**

- [ ] **Device registry readers** — the COLLECTION shipped (a metadata
      entry beside each device's KVS blob: name, model, class, first-seen/
      last-active; published under the sync gate, wipe-immune, never in
      the share payload). Readers to build on it later: record-attribution
      lines ("set on MacBook"), playtime by device class, a Settings "Your
      devices" list, and eventually forget-a-device (the KVS-blob-pruning
      item wearing a friendlier face). iOS names are generic until the
      user-assigned-device-name entitlement ships with that UI.

- [ ] **KVS blob pruning** — a reinstall mints a new sync slot, orphaning the old
      blob. Deferred (a dead reinstall looks like an offline device; blobs are
      tiny). Revisit only near KVS storage limits.


## v0.6.0 — Keyboard & accessibility (in beta)

Code complete — the substance shipped (see CHANGELOG). The scope cuts
(widgets, App Clip, SharePlay, TipKit) and the sync-flag scope rule are
recorded in DECISIONS.md.

## v0.7.0 — Skill & social play

May fold into 0.6.0 if it stays thin — semantics, decide at cut time.

- [ ] **Daily challenge** (the possible social pillar) — one shared board
      per day: the seed derives from the LOCAL date string, so the same
      calendar date is the same board everywhere (timezones only shift when
      it flips; a date-changer can cheat — let them, they cheat themselves).
      Boards are PRE-ARMED with a fixed revealed opening so first-click-safe
      can't diverge them — everyone's luck is identical. The pre-opened
      board never lands as a surprise: every attempt opens in a REVIEW
      state (board visible, input locked, a Start overlay — first-time
      explainer line) and the clock runs from Start, so study is
      explicitly free (memorization is legitimate anyway) and the time
      measures pure execution. Backing out of review costs nothing (an
      attempt = a completed game). Unlimited attempts:
      memorizing the board is the discipline, like fixed-seed speedrunning;
      the per-day record keeps it honest — best time + pace, cleared/best-%,
      attempt count, and which attempt set the best. A CALENDAR view lists
      every day since the feature's epoch (a constant baked at the shipping
      release's cut); any past day is playable, but only TODAY feeds the
      streak — and streaks measure PARTICIPATION, never outcomes (a
      completed attempt, won or lost, marks the day played; no
      notifications, neutral display "12 days · longest 23"). MEDALS ride
      the same line: EXACTLY two participation-streak one-shots,
      `daily.week` (7 days running) and `daily.month` (30) — permanent,
      so the chase is bounded and a later break takes nothing away. No
      daily volume ladder: dailies feed normal stats, so miles.* already
      counts the grind (tiered thresholds are progress-tracking in badge
      costume — the Expert-ladder lesson), and the calendar displays
      volume better than a medal. Never cleared/first-try streaks (the
      luck-based kind the no-streaks rule still forbids). +2 ASC
      definitions and medal images when this ships.
      DATA: full history kept locally + own-device sync forever (a year is
      a few KB zlib'd); ONE aggregate line per day — never per-attempt
      rows — merging across own devices on the scoreboard's proven
      pattern: best time/pace min-wins (device-owned, projected at merge),
      attempts a DeviceCounter (plain counts can't merge across devices);
      the best's attempt ordinal NEVER merges — it's device-owned data
      riding with the best itself (the BestTime pattern), so the merged
      view shows the winner's own ordinal. Display keeps ordinal and
      total as SEPARATE figures ("Best 1:42 (attempt 2)" + "9 attempts")
      — "attempt 2 of 9" would imply a global sequence that doesn't
      exist; the device registry can someday attribute it ("on iPhone"); sharing carries a CHANNEL-SIZED slice of the same
      v3 payload field — full history over Nearby (no size limit), a
      rolling 14–31-day window over QR/link (scan budget) — and the
      receiver merges PER DATE (newest share wins a date; the sharer's own
      day only improves), so rivals' histories accumulate organically
      across swaps and the QR never needs to carry the past.
      UI: Home card (today's board, result, streak) → Daily sheet with a
      month-grid calendar clamped to [epoch, today] — chips show best time
      / ✗ with % / unplayed, today ringed; arrows walk days, Return plays
      (KeyCursor idiom), VoiceOver speaks each day's result; the selected
      day's detail row shows the full record ("best on attempt 2 of 7"),
      Play/Replay, and same-day rival lines where data exists (the H2H
      Dailies section is the per-rival rollup of the same data). May build
      pre-1.0 in three independent slices (core+store, Home card + play
      flow, calendar + payload + H2H) — it rides 1.0 if stable by
      submission, else 1.0.1, without delaying the release.

## v1.0.0 — The store release

The features are in; 1.0 makes them ship-shape for the public App Store.

- [ ] **Game Center, ASC side** (the reporter code shipped 2026-07-13; design
      + merge rules in DECISIONS.md): create the 26 achievement definitions
      per the tier-flattening mapping (`GameCenterMapping.allWireIDs` is
      canonical), assign the ≤ 1 000-point budget, flag the four gags hidden;
      one 1024×1024 image each — export via the MedalGalleryRender harness;
      then a sandbox TestFlight pass of the opt-in flow.
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

The paid account exists, both apps ship to TestFlight under one Universal
Purchase record, and the local release lane does the whole cut (see
[RELEASING.md](RELEASING.md); the two-native-targets / shared-bundle-id
story is in [ARCHITECTURE.md](ARCHITECTURE.md)). Open items:

- [ ] **AI disclosure at submission.** The README carries an honest "AI
      assistance" note; mirror a short version into the App Store description
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
- **GitHub Actions CD** is a possible later step only if the local release
  cadence becomes a bottleneck — not needed now.

## Creative identity & theme

The shipped manga identity (chrome, not board) is recorded in DECISIONS.md.
Ideas to revisit:

- **More screentone accents** — the dot/hatch vocabulary could extend to other UI,
  but it's easy to overdo: keep it meaningful (it *means* "unopened / this mode"),
  not decorative, or the UI gets noisy.
- **Art sources** — the scene panels are DALL·E (commercial-use OK via OpenAI TOS;
  verify before ship); the app icon is *procedural*, not DALL·E. When commissioning
  final art, consider a real manga artist for a consistent character sheet — and a
  human pass to replace AI kana with proper typeset lettering is recommended
  regardless.

## Distribution & extras (later)

- [ ] **Real board images on donpa.app/how-to-play** — replace the monospace
      unicode diagrams with actual rendered boards. Not hand-cropped
      screenshots: export the in-app guide's own `TileDiagram` (+ mode chips)
      headlessly to PNGs, the way `MedalGalleryRender` renders medals — pixel-
      perfect, light + dark variants, regenerable whenever the art changes.
      (The in-app guide keeps its LIVE TileDiagrams — those already render the
      real thing and track dark mode for free.)
- [ ] **watchOS version?** — a big maybe; minesweeper on a tiny screen is its
      own design problem. Parked.
- [ ] **Tip jar?** — see the monetization note below; would be a *deliberate*
      exception to the no-monetization stance, not ads/IAP-for-content.

## Design principles

- **No anti-cheat, by design.** Scores are local and user-editable (low
  security, by choice). This is *why* global leaderboards are out of scope:
  with no validation they'd just fill with impossible scores. Achievements
  stay personal, so tampering only cheats yourself.

## Deliberately out of scope

Per project conventions: **no ads, no microtransactions, no pay-to-win**; no
third-party *runtime* dependencies; the older Intel Mac is not targeted. No online
multiplayer, **no server, no accounts, no global leaderboards** — ever the plan.
(Cross-device *score* sync (shipped in 0.2.0) is the user's own iCloud KVS, and
score *sharing* (the friendly-rivalry milestone) is peer-to-peer QR between people
who know each other — neither involves a server or a global social layer.) A **tip jar** — optional,
content-neutral support — is the one monetization form under consideration.
