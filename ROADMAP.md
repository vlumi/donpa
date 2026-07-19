# Roadmap

Open, future work only. **Shipped milestones live in
[CHANGELOG.md](CHANGELOG.md)** (full detail) and are summarized in the
[README](README.md) version history; **settled design choices and scrapped
ideas are recorded in [DECISIONS.md](DECISIONS.md)**; the technical "why" is
[ARCHITECTURE.md](ARCHITECTURE.md).

Versions are indicative, not contractual. For the record: v0.1.0 (classic),
v0.2.0 (cross-device sync + big boards), v0.3.0 (board variants + the New
Game / scoreboard redesign), v0.4.0 (friendly rivalry), v0.5.0 (progression),
and v0.6.0 (keyboard & accessibility) all shipped to TestFlight — everything
before 1.0 is beta by definition.

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


## Your devices (post-1.0)

The registry COLLECTION shipped ahead of every reader (a metadata entry
beside each device's KVS blob: name, model, class, first-seen/last-active;
sync-gated, wipe-immune, never in the share payload — deliberately: device
names identify people in a way score tables don't, so rivals stay
device-blind). Because each blob holds only its own device's records and the
cross-device view merges at read time, all readers below are derivable with
no new collection. The whole feature is sync-gated and hides without it.

- [x] **Scores by device** (the list, SHIPPED first) — named by what it
      is: the record by where it was earned, not a device manager (theme
      names like "Duty stations" were considered and dropped as
      under-selling it). Lives beside the Record's Sync toggle. Read-only;
      forget-a-device joins later.
- [ ] **Record attribution** — the expanded Record row (and top-5 entries)
      gets a small class glyph beside a best: derived at merge time from
      whose blob carries it, retroactively. Ties/unknown blobs show nothing.
- [ ] **Career by device class** — All / Mac / iPhone / iPad segmented
      filter on the career (filter the blob set before the merge); appears
      only when two or more classes have data, like the Edges control.
      Per-individual-device was considered and rejected — class is where
      the insight lives. The Breakdown block could gain a by-class bar
      (same shape as its Edges bar).

**Migration semantics** (DeviceID is a UUID in UserDefaults, so it travels
with backup/transfer — the ID must ride with the data it describes, or
history double-counts):

- Normal migration (old device retired): clean takeover — same ID, same
  blob, registry entry re-describes itself, nickname follows. Correct as-is.
- Fresh reinstall: new ID, old blob remains merged in (no data loss) but
  its registry entry goes stale — a ghost row in the list, cleaned by
  forget-a-device eventually.
- [ ] **Fork this device** — "Start as a new device" on the This-device
      row: mints a fresh DeviceID, zeroes the local mine-table, publishes a
      fresh registry entry. Pre-fork history stays owned by the old blob —
      totals preserved exactly, only provenance reassigns (pre-fork records
      keep the old device's class in attribution: frozen at earn time, by
      design). For the kept-both-devices-after-cloning case. Sync-gated.
- [ ] **Clone detection** — a ThisDeviceOnly Keychain marker doesn't
      survive restore onto new hardware: "ID present, marker missing" =
      migrated/cloned. Offer the choice up front ("continue as ⟨old
      name⟩" / "start fresh" = fork). If the user continues but the old
      device is still alive, catch the mix-up anyway: stamp each blob
      write with a per-install token; a device reading its own slot with
      someone else's newer token knows two live installs share one ID —
      surface it on both ("this ID is in use on another device") and
      suggest the fork, instead of today's silent last-writer-wins
      flip-flop.


## v1.0.0 — The store release

**Build 30 is submitted for App Review** (both platforms, one Universal
Purchase record; sharing is Nearby-only for 1.0 and squads are hidden — the
rationale and the way back live in [DECISIONS.md](DECISIONS.md)). Store
assets (listing text, screenshots, achievements) are live in ASC and synced
from this repo via the `asc-*` targets. What remains:

- [ ] **Await App Review**; on approval, release (manual release is set)
- [ ] **Update donpa.app after release** — App Store links (and any launch
      wording) on the live site
- [ ] Delete `release/0.5.x` once 1.0.0 ships (superseded-line rule in
      [RELEASING.md](RELEASING.md))
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

## Publishing & distribution

The paid account exists, both apps ship to TestFlight under one Universal
Purchase record, and the local release lane does the whole cut (see
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
