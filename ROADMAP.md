# Roadmap

Open, future work only. **Shipped milestones live in
[CHANGELOG.md](CHANGELOG.md)** (full detail) and are summarized in the
[README](README.md) version history; **settled design choices and scrapped
ideas are recorded in [DECISIONS.md](DECISIONS.md)**; the technical "why" is
[ARCHITECTURE.md](ARCHITECTURE.md).

Versions are indicative, not contractual. **1.0.0 shipped to the App Store
2026-07-31** (both platforms, Universal Purchase); 1.0.1 followed as the
first update. The pre-1.0 line (v0.1.0 classic → v0.6.0 keyboard &
accessibility) shipped to TestFlight; full history is in
[CHANGELOG.md](CHANGELOG.md).

---

## Backlog (unversioned)

Polish and smaller features that can land in any release — not milestone
gates.

**Keyboard follow-ons:**

- [ ] **Game controllers** — the cursor seam is ready.
- [ ] **A real VoiceOver session** to validate the spoken-cell flow.

**Carry-overs (deferred, revisit when relevant):**

- [ ] **KVS blob pruning** — a reinstall mints a new sync slot, orphaning the old
      blob. Deferred (a dead reinstall looks like an offline device; blobs are
      tiny). Revisit only near KVS storage limits; the friendly face is
      forget-a-device in the devices list (see "Your devices" below).


## Your devices (mostly shipped)

The device suite shipped in 1.0.1: **Scores by device** (the per-device
record list + nicknames), record attribution glyphs, the class-filtered
career, and **fork + clone detection** for migrations. The technical model
(DeviceID rides UserDefaults; the ThisDeviceOnly marker; staged fork) is in
[ARCHITECTURE.md](ARCHITECTURE.md). One follow-on remains:

- [ ] **Forget a device** — remove a stale/ghost device entry (and prune its
      orphaned KVS blob) from the devices list. The friendly face of the
      KVS-blob-pruning carry-over above.


## Open items

**1.0.0 shipped** to the App Store (both platforms, Universal Purchase) on
2026-07-31; **1.0.1** (the devices suite, the daily-wins fix, and the Nearby
mutual-tap rework) followed as the first update. Shipped detail lives in
[CHANGELOG.md](CHANGELOG.md).

- [ ] **UI smoke tests on CI?** A local XCUITest suite already exists (`make
      uitest`, `Tests/UITests/`, shipped in v0.1) but is deliberately *not* run
      by CI — it needs a job that builds the `.xcodeproj` and boots a simulator
      (today CI runs SPM `swift test` + `xcodebuild build` only), which is slow
      and flaky mid-iteration. Decide whether the regression value is worth
      wiring it into CI.

## Sharing regrows (post-1.0)

Remote sharing returns **bounded**, not as it was:

- [ ] **Challenge cards** — share a single score (or a small named block) by
      QR/link: small by construction, nothing to trim, nothing to explain.
      Full records stay a Nearby-only, in-person, two-way swap. The parked
      code (codec, QR pipeline, scanner) is intact in the tree.
- [ ] **Squads return** when remote sharing regrows rosters past what a
      flat rivals list handles comfortably — group data and sync stayed
      live underneath the hidden UI.
- [ ] **Nearby failure reasons.** The exchange reports success on transport
      and verifies the card only later in the receive sheet, so a rejected
      card (peer on an older app that can't read the v3 envelope, or a bad
      signature) and a transport failure (never connected, or Local Network
      permission off) both surface as a generic "failed." Distinguish them:
      an actionable message ("their app is older than yours" / "check Local
      Network permission") beats a blank retry. A field pass with a friend
      that always dropped mid-exchange — and had AirDrop trouble generally —
      pointed at a device-level `awdl0`/Local-Network problem, not our code;
      the app should say so. Ties into the discoverability finding (Nearby is
      hard to find *and* hard to diagnose when it fails).

## Publishing & distribution

The paid account exists, both platforms ship to the App Store under one
Universal Purchase record, and the local release lane does the whole cut (see
[RELEASING.md](RELEASING.md); the two-native-targets / shared-bundle-id
story is in [ARCHITECTURE.md](ARCHITECTURE.md)). Open items:

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
score *sharing* (the friendly-rivalry milestone) is a peer-to-peer swap between
people in the same room — neither involves a server or a global social layer.) A **tip jar** — optional,
content-neutral support — is the one monetization form under consideration.
