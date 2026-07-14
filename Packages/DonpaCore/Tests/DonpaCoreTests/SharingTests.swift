import XCTest

@testable import DonpaCore

/// The score-sharing core: signed-payload round-trip, every decode guard, and the
/// full TOFU / rotation / collision decision matrix. Security-critical, so the
/// guards are tested by construction (tamper a byte → reject), not just happy path.
final class SharingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func sampleScores() -> [SharedConfigScore] {
        [
            SharedConfigScore(
                key: "v2|grid|flat|16x16|m31", best: 4200, wins: 3, bestProgress: nil),
            SharedConfigScore(key: "v2|basic|beginner", best: 780, wins: 10, bestProgress: nil),
        ]
    }

    private func makeShare(
        _ id: ShareIdentity = ShareIdentity(), name: String = "Ville",
        issuedAt: Date? = nil, rotation: RotationEndorsement? = nil
    ) throws -> SharePayload {
        try id.makePayload(
            name: name, scores: sampleScores(), career: nil,
            issuedAt: issuedAt ?? t0, rotation: rotation)
    }

    // MARK: Round-trip

    func testRoundTripThroughStringPreservesBody() throws {
        let payload = try makeShare()
        let s = try ShareCodec.encodeToString(payload)
        let back = try ShareCodec.decode(fromString: s)
        XCTAssertEqual(back.publicKey, payload.publicKey)
        XCTAssertEqual(back.body.name, "Ville")
        XCTAssertEqual(back.body.scores, payload.body.scores)
    }

    func testEncodeIsUrlSafe() throws {
        let s = try ShareCodec.encodeToString(makeShare())
        XCTAssertFalse(s.contains("+"))
        XCTAssertFalse(s.contains("/"))
        XCTAssertFalse(s.contains("="))
    }

    // MARK: Signature guards

    func testValidSignatureVerifies() throws {
        XCTAssertTrue(ShareIdentity.verify(try makeShare()))
    }

    func testTamperedBodyFailsSignature() throws {
        var p = try makeShare()
        p = SharePayload(
            publicKey: p.publicKey, signature: p.signature,
            body: ShareBody(name: "Mallory", scores: p.body.scores, career: nil, issuedAt: t0))
        XCTAssertFalse(ShareIdentity.verify(p))
        // And decode rejects it loudly.
        let data = try ShareCodec.encode(p)
        XCTAssertThrowsError(try ShareCodec.decode(data)) {
            XCTAssertEqual($0 as? ShareCodec.DecodeError, .badSignature)
        }
    }

    func testForeignKeyCantClaimSignature() throws {
        let real = try makeShare()
        // Swap in a different public key but keep the (now-mismatched) signature.
        let imposter = SharePayload(
            publicKey: ShareIdentity().publicKey, signature: real.signature, body: real.body)
        XCTAssertFalse(ShareIdentity.verify(imposter))
    }

    // MARK: Decode guards

    func testUnsupportedVersionRejected() throws {
        let p = try makeShare()
        let future = SharePayload(
            version: SharePayload.currentVersion + 1, publicKey: p.publicKey,
            signature: p.signature, body: p.body)
        // Re-sign not needed: version is checked before signature. Encode raw.
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try (enc.encode(future) as NSData).compressed(using: .zlib)) as Data
        XCTAssertThrowsError(try ShareCodec.decode(data)) {
            XCTAssertEqual($0 as? ShareCodec.DecodeError, .unsupportedVersion)
        }
    }

    // MARK: Pace fields (envelope v2)

    func testPaceFieldsRoundTrip() throws {
        let id = ShareIdentity()
        let scores = [
            SharedConfigScore(
                key: "v2|grid|flat|16x16|m31", best: 4200, wins: 3, bestProgress: nil,
                recentPace: 1.84, bestPace: 2.31)
        ]
        let payload = try id.makePayload(name: "Ville", scores: scores, career: nil, issuedAt: t0)
        let back = try ShareCodec.decode(fromString: try ShareCodec.encodeToString(payload))
        XCTAssertEqual(back.body.scores.first?.recentPace, 1.84)
        XCTAssertEqual(back.body.scores.first?.bestPace, 2.31)
    }

    func testV1PayloadWithoutPaceStillDecodes() throws {
        // An old sender: envelope v1, no pace fields. Must decode and verify —
        // absent optionals re-encode identically, so the v1 signature holds.
        let p = try makeShare()
        let v1 = SharePayload(
            version: 1, publicKey: p.publicKey, signature: p.signature, body: p.body)
        let back = try ShareCodec.decode(try ShareCodec.encode(v1))
        XCTAssertNil(back.body.scores.first?.recentPace)
    }

    func testNegativePaceRejected() throws {
        let bad: [[SharedConfigScore]] = [
            [
                SharedConfigScore(
                    key: "v2|basic|beginner", best: 780, wins: 1, bestProgress: nil,
                    recentPace: -0.1)
            ],
            [
                SharedConfigScore(
                    key: "v2|basic|beginner", best: 780, wins: 1, bestProgress: nil,
                    bestPace: -1)
            ],
        ]
        for scores in bad {
            let payload = try ShareIdentity().makePayload(
                name: "V", scores: scores, career: nil, issuedAt: t0)
            XCTAssertThrowsError(try ShareCodec.decode(try ShareCodec.encode(payload))) {
                XCTAssertEqual($0 as? ShareCodec.DecodeError, .malformed)
            }
        }
    }

    // MARK: Pace in comparisons

    func testHeadToHeadCarriesBestPaces() {
        let h = ScoreComparison.headToHead(
            configKeys: ["k"], yourBests: ["k": 100], theirBests: ["k": 200],
            yourPaces: ["k": 1.5], theirPaces: [:])
        XCTAssertEqual(h.rows.first?.yourBestPace, 1.5)
        XCTAssertNil(h.rows.first?.theirBestPace)
    }

    func testGroupBestPaceIsMaxAcrossMembers() {
        let paces = ScoreComparison.groupBestPaces([
            ["k": 1.2, "j": 3.0], ["k": 2.5],
        ])
        XCTAssertEqual(paces["k"], 2.5)
        XCTAssertEqual(paces["j"], 3.0)
    }

    func testRankCarriesPaces() {
        let ranking = ScoreComparison.rank(
            yourName: "V", yourBest: 100, yourBestPace: 2.0,
            rivals: [.init(name: "R", best: 90)])
        XCTAssertEqual(ranking.entries.first?.bestPace, nil)  // R is faster, no pace
        XCTAssertEqual(ranking.entries.last?.bestPace, 2.0)
    }

    func testGarbageRejected() {
        XCTAssertThrowsError(try ShareCodec.decode(fromString: "not-a-share!!"))
        XCTAssertThrowsError(try ShareCodec.decode(Data([0xFF, 0x00, 0x13])))
    }

    func testBadStorageKeyGrammarRejected() throws {
        // A hostile key with illegal chars must be refused by sanitize.
        let bad = ShareBody(
            name: "x",
            scores: [SharedConfigScore(key: "v2|grid|../etc", best: 1, wins: 1, bestProgress: nil)],
            career: nil, issuedAt: t0)
        XCTAssertThrowsError(try ShareCodec.sanitize(bad)) {
            XCTAssertEqual($0 as? ShareCodec.DecodeError, .malformed)
        }
    }

    func testNegativeValuesRejected() throws {
        let bad = ShareBody(
            name: "x",
            scores: [
                SharedConfigScore(key: "v2|basic|beginner", best: -5, wins: 1, bestProgress: nil)
            ],
            career: nil, issuedAt: t0)
        XCTAssertThrowsError(try ShareCodec.sanitize(bad))
    }

    func testDuplicateKeysRejected() throws {
        let dup = ShareBody(
            name: "x",
            scores: [
                SharedConfigScore(key: "v2|basic|beginner", best: 1, wins: 1, bestProgress: nil),
                SharedConfigScore(key: "v2|basic|beginner", best: 2, wins: 2, bestProgress: nil),
            ], career: nil, issuedAt: t0)
        XCTAssertThrowsError(try ShareCodec.sanitize(dup))
    }

    func testNameSanitizationStripsBidiAndCaps() {
        // Bidi-override char removed; length capped.
        let spoof = "A\u{202E}dcba" + String(repeating: "z", count: 100)
        let clean = ShareCodec.sanitizeName(spoof)
        XCTAssertFalse(clean.unicodeScalars.contains { $0.value == 0x202E })
        XCTAssertLessThanOrEqual(clean.count, ShareCodec.maxNameLength)
        XCTAssertEqual(ShareCodec.sanitizeName("   "), "?")  // nothing printable
    }

    // MARK: TOFU / rotation / collision matrix

    func testNewIdentityAdds() throws {
        XCTAssertEqual(FriendMerge.outcome(for: try makeShare(), existing: []), .add)
    }

    func testNewerShareRefreshes() throws {
        let id = ShareIdentity()
        let old = try makeShare(id, issuedAt: t0)
        let existing = FriendMerge.friend(from: old, existing: nil, now: t0)
        let newer = try makeShare(id, name: "Ville", issuedAt: t0.addingTimeInterval(60))
        XCTAssertEqual(FriendMerge.outcome(for: newer, existing: [existing]), .refresh)
    }

    func testOlderShareIsStale() throws {
        let id = ShareIdentity()
        let recent = try makeShare(id, issuedAt: t0.addingTimeInterval(60))
        let existing = FriendMerge.friend(from: recent, existing: nil, now: t0)
        let older = try makeShare(id, issuedAt: t0)
        XCTAssertEqual(FriendMerge.outcome(for: older, existing: [existing]), .stale)
    }

    func testNameCollisionPrompts() throws {
        let a = try makeShare(ShareIdentity(), name: "Ville")
        let friendA = FriendMerge.friend(from: a, existing: nil, now: t0)
        let b = try makeShare(ShareIdentity(), name: "Ville")  // same name, different key
        XCTAssertEqual(
            FriendMerge.outcome(for: b, existing: [friendA]),
            .nameCollision(withPublicKey: friendA.publicKey))
    }

    func testRotationEndorsementMigratesSilently() throws {
        // Old identity tracked; new identity carries a valid endorsement from it.
        let oldID = ShareIdentity()
        let oldShare = try makeShare(oldID, name: "Ville", issuedAt: t0)
        let tracked = FriendMerge.friend(from: oldShare, existing: nil, now: t0)

        let newID = ShareIdentity()
        let endorsement = try oldID.endorse(newPublicKey: newID.publicKey)
        let newShare = try makeShare(
            newID, name: "Ville", issuedAt: t0.addingTimeInterval(120), rotation: endorsement)

        XCTAssertEqual(
            FriendMerge.outcome(for: newShare, existing: [tracked]),
            .migrate(fromPublicKey: oldID.publicKey))
    }

    func testForgedRotationDoesNotMigrate() throws {
        // Endorsement signed by an UNRELATED key (not one we track) → no migrate;
        // falls through to a name collision (same name) or add.
        let tracked = FriendMerge.friend(
            from: try makeShare(ShareIdentity(), name: "Ville"), existing: nil, now: t0)
        let attacker = ShareIdentity()
        let newID = ShareIdentity()
        let fakeEndorsement = try attacker.endorse(newPublicKey: newID.publicKey)
        let share = try makeShare(newID, name: "Rival", issuedAt: t0, rotation: fakeEndorsement)
        XCTAssertEqual(FriendMerge.outcome(for: share, existing: [tracked]), .add)
    }

    // MARK: Universal Link transport

    func testShareLinkRoundTrip() throws {
        let payload = try makeShare(name: "Ville")
        let url = try ShareLink.url(for: payload)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "donpa.app")
        XCTAssertTrue(url.path.hasPrefix("/s/"))
        let back = try ShareLink.payload(from: url)
        XCTAssertEqual(back.publicKey, payload.publicKey)
        XCTAssertEqual(back.body.name, "Ville")
    }

    func testShareLinkAcceptsWwwHost() throws {
        let payload = try makeShare()
        let url = try ShareLink.url(for: payload)
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        c.host = "www.donpa.app"
        XCTAssertNoThrow(try ShareLink.payload(from: c.url!))
    }

    func testNonShareURLsIgnored() {
        for s in [
            "https://example.com/s/abc", "https://donpa.app/about",
            "https://donpa.app/s/", "donpa://s/abc",
        ] {
            XCTAssertNil(ShareLink.blob(from: URL(string: s)!), "should ignore \(s)")
        }
    }

    // MARK: Career-included share

    func testCareerSharedRoundTrips() throws {
        let career = SharedCareer(
            gamesPlayed: 50, wins: 30, noFlagWins: 2, noChordWins: 3,
            tilesOpened: 9000, flagsPlaced: 400, minesDisarmed: 350, minesHit: 20,
            chordsUsed: 120, playtimeCentiseconds: 60000)
        let payload = try ShareIdentity().makePayload(
            name: "Ville", scores: sampleScores(), career: career, issuedAt: t0)
        let back = try ShareCodec.decode(fromString: try ShareCodec.encodeToString(payload))
        XCTAssertEqual(back.body.career, career)
    }

    func testNegativeCareerRejected() throws {
        let bad = ShareBody(
            name: "x", scores: [],
            career: SharedCareer(
                gamesPlayed: -1, wins: 0, noFlagWins: 0, noChordWins: 0, tilesOpened: 0,
                flagsPlaced: 0, minesDisarmed: 0, minesHit: 0, chordsUsed: 0,
                playtimeCentiseconds: 0),
            issuedAt: t0)
        XCTAssertThrowsError(try ShareCodec.sanitize(bad)) {
            XCTAssertEqual($0 as? ShareCodec.DecodeError, .malformed)
        }
    }

    // MARK: Identity persistence (Keychain round-trip)

    func testIdentityPersistsAndSignsSame() throws {
        let id = ShareIdentity()
        let raw = id.privateKeyRepresentation
        let reloaded = try ShareIdentity(privateKeyRepresentation: raw)
        XCTAssertEqual(reloaded.publicKey, id.publicKey)
        // The reloaded identity produces a signature the original's public key accepts.
        let payload = try reloaded.makePayload(
            name: "Ville", scores: sampleScores(), career: nil, issuedAt: t0)
        XCTAssertTrue(ShareIdentity.verify(payload))
    }

    func testBadPrivateKeyBytesThrow() {
        XCTAssertThrowsError(try ShareIdentity(privateKeyRepresentation: Data([1, 2, 3])))
    }

    // MARK: Friend Identifiable + local alias

    func testFriendIdIsPublicKey() throws {
        let f = FriendMerge.friend(from: try makeShare(), existing: nil, now: t0)
        XCTAssertEqual(f.id, f.publicKey)
    }

    func testDisplayNamePrefersLocalAlias() throws {
        var f = FriendMerge.friend(from: try makeShare(name: "Ville"), existing: nil, now: t0)
        XCTAssertEqual(f.displayName, "Ville")  // no alias → shared name
        f.localAlias = "Bro"
        XCTAssertEqual(f.displayName, "Bro")  // alias wins
    }

    func testRefreshPreservesLocalAliasAndGroups_butUpdatesSharedName() throws {
        let id = ShareIdentity()
        var pinned = FriendMerge.friend(
            from: try makeShare(id, name: "Ville"), existing: nil, now: t0)
        pinned.localAlias = "Bro"
        pinned.groups = ["family"]
        // They re-share under a new display name — my alias/groups must survive.
        let renamed = try makeShare(id, name: "Ville_2", issuedAt: t0.addingTimeInterval(60))
        let updated = FriendMerge.friend(from: renamed, existing: pinned, now: t0)
        XCTAssertEqual(updated.sharedName, "Ville_2")  // tracks their latest
        XCTAssertEqual(updated.localAlias, "Bro")  // mine survives
        XCTAssertEqual(updated.groups, ["family"])  // mine survives
        XCTAssertEqual(updated.displayName, "Bro")
    }

    // MARK: Valid-JSON-but-wrong-shape → malformed

    func testWellFormedJsonWrongShapeRejected() throws {
        let data = Data(#"{"hello":"world"}"#.utf8)  // valid JSON, not a SharePayload
        XCTAssertThrowsError(try ShareCodec.decode(data)) {
            XCTAssertEqual($0 as? ShareCodec.DecodeError, .malformed)
        }
    }
}
