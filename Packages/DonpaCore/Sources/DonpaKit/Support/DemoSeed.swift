import DonpaCore
import Foundation
import SwiftUI

/// Populates the stores with believable demo data for the screenshot harness
/// (`-uitest-demo`), so gallery and App Store captures show a real player's
/// app — scores across boards, a couple of rivals, a daily streak — rather
/// than empty state. Never runs outside that launch arg; ships inert.
@MainActor
public enum DemoSeed {
    public static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-demo")
    }

    /// `-uitest-dump-saves`: mirror each autosaved demo game to a JSON file on
    /// the Desktop, so a board you've flagged by hand can be frozen and shipped
    /// verbatim as a seed (hand the files back to embed under Resources).
    static var isDumpingSaves: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-dump-saves")
    }

    /// Write the in-progress `snapshot` (flags and all) to
    /// ~/Desktop/donpa-demo-saves/<configKey>.json. macOS only (that's where
    /// boards are set up for capture); a no-op elsewhere and unless dumping.
    public static func dumpSave(_ snapshot: GameSnapshot) {
        guard isDumpingSaves else { return }
        #if os(macOS)
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/donpa-demo-saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = snapshot.config.storageKey.replacingOccurrences(of: "|", with: "_")
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: dir.appendingPathComponent("\(safe).json"))
        #endif
    }

    /// The app rides the SYSTEM accent by design (colour is never the sole
    /// cue — see the scoreboard-highlight decision), so captures would inherit
    /// the machine's personal Highlight colour (a red Mac, say). Under the
    /// screenshot arg only, pin a neutral blue so the store images are
    /// deterministic on any machine. Real users keep their system accent.
    static var screenshotAccent: Color? { isRequested ? .blue : nil }

    /// Seed once at launch. Times are hand-picked to look earned, not random,
    /// and to sort into a satisfying spread on the Service Record.
    static func apply(
        scoreboard: Scoreboard, friends: FriendsStore, daily: DailyStore, settings: Settings,
        saveStore: SaveStore
    ) {
        // Start in Light every launch so the light screenshot set is captured
        // deliberately (then switch to Dark in-app for the dark set), rather
        // than inheriting whatever the capture machine happens to be in.
        settings.appearance = .light
        seedScores(scoreboard)
        seedRivals(friends, settings: settings)
        seedDaily(daily)
        seedSaves(saveStore)
    }

    /// A couple of fixed in-progress games so the demo Home shows a real
    /// "Continue" list and a tap resumes a genuine mid-game board — no live
    /// clicking to set up, and identical every launch (any language) because
    /// each save is built deterministically from a seed + scripted reveals.
    private struct SavedGame {
        let config: GameConfig
        let seed: UInt64
        let reveals: [Coord]
        let flags: [Coord]
        let elapsed: Int
    }

    private static func seedSaves(_ store: SaveStore) {
        // Prefer hand-crafted saves committed under Scripts/asc/demo-saves (the
        // boards you flagged yourself, dumped via -uitest-dump-saves) — they
        // carry your exact flag placement. Fall back to generating boards from
        // seeds when none are committed. Repo-relative, resolved via
        // DONPA_REPO_ROOT (set by the demo scripts); never in the shipped app.
        if loadCommittedSaves(into: store) { return }
        generateSaves(into: store)
    }

    private static func committedSavesDir() -> URL? {
        guard let root = ProcessInfo.processInfo.environment["DONPA_REPO_ROOT"] else { return nil }
        let dir = URL(fileURLWithPath: root)
            .appendingPathComponent("Scripts/asc/demo-saves", isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    private static func loadCommittedSaves(into store: SaveStore) -> Bool {
        guard let dir = committedSavesDir(),
            let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil),
            !files.isEmpty
        else { return false }
        var loaded = 0
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: data)
            else { continue }
            store.save(snapshot)
            loaded += 1
        }
        return loaded > 0
    }

    private static func generateSaves(into store: SaveStore) {
        let games: [SavedGame] = [
            // A partly-cleared Beginner: the familiar square board mid-solve.
            SavedGame(
                config: .beginner, seed: 635, reveals: [Coord(4, 4)],
                flags: [Coord(3, 0), Coord(6, 0)], elapsed: 2_340),
            // A Hive (hex) board so the Continue list shows a second board type
            // and the variant-board screenshot resumes rather than sets up.
            SavedGame(
                config: .hive(.s, .normal, .flat), seed: 5, reveals: [Coord(8, 8)],
                flags: [Coord(0, 0)], elapsed: 5_110),
            // A vast XXL board (256²) so the big-map / scale shot is a resume
            // too — identical across languages, no hand setup. A single central
            // reveal opens a region to zoom out from.
            SavedGame(
                config: .grid(.xxl, .normal, .flat), seed: 42, reveals: [Coord(128, 128)],
                flags: [], elapsed: 18_450),
        ]
        for g in games {
            var rng = SeededGenerator(seed: g.seed)
            var game = Game(config: g.config)
            game.placeMinesEagerly(using: &rng)
            for c in g.reveals { game.reveal(c, using: &rng) }
            for c in g.flags { game.toggleFlag(c) }
            guard
                let snapshot = GameSnapshot(
                    game: game, config: g.config, elapsedCentiseconds: g.elapsed)
            else { continue }
            store.save(snapshot)
        }
    }

    /// One seeded board result: a best time, a win count, and the 3BV that
    /// drives its pace line.
    private struct Run {
        let config: GameConfig
        let best: Int
        let wins: Int
        let threeBV: Int
    }

    /// One seeded rival's clear on a board.
    private struct RivalScore {
        let config: GameConfig
        let best: Int
    }

    /// Best times + a plausible win/loss history across a representative
    /// spread of the config matrix (the presets, a couple of Grid/Hive sizes).
    private static func seedScores(_ scoreboard: Scoreboard) {
        let runs: [Run] = [
            Run(config: .basic(.beginner), best: 812, wins: 40, threeBV: 22),
            Run(config: .basic(.intermediate), best: 4_355, wins: 18, threeBV: 96),
            Run(config: .basic(.expert), best: 11_920, wins: 9, threeBV: 214),
            Run(config: .grid(.s, .normal, .flat), best: 1_640, wins: 12, threeBV: 38),
            Run(config: .grid(.m, .hard, .flat), best: 8_770, wins: 5, threeBV: 168),
            Run(config: .grid(.s, .normal, .round), best: 2_010, wins: 7, threeBV: 41),
            Run(config: .hive(.s, .normal, .flat), best: 1_890, wins: 10, threeBV: 44),
            Run(config: .hive(.m, .normal, .flat), best: 6_240, wins: 4, threeBV: 121),
        ]
        for run in runs {
            // Coherent counters: one outcome + one activity flush PER game, so
            // games ≈ wins+losses, and tiles/flags/playtime aren't left at zero.
            // The board's own geometry sets believable per-game magnitudes.
            let safeTiles = run.config.width * run.config.height - run.config.mineCount
            let losses = max(1, run.wins / 6)
            _ = scoreboard.submit(run.best, for: run.config, threeBV: run.threeBV)
            for i in 0..<run.wins {
                if i > 0 {
                    _ = scoreboard.submit(run.best + 600, for: run.config, threeBV: run.threeBV)
                }
                scoreboard.recordGameOutcome(
                    for: run.config, won: true, minesHit: 0,
                    minesDisarmed: run.config.mineCount, chordsUsed: run.wins / 4)
                scoreboard.recordActivity(
                    for: run.config, tilesOpened: safeTiles,
                    flagsPlaced: run.config.mineCount, playtimeCentiseconds: run.best + 400)
            }
            for _ in 0..<losses {
                scoreboard.recordGameOutcome(
                    for: run.config, won: false, minesHit: 1,
                    minesDisarmed: run.config.mineCount / 2, chordsUsed: 1)
                scoreboard.recordActivity(
                    for: run.config, tilesOpened: safeTiles / 2,
                    flagsPlaced: run.config.mineCount / 2, playtimeCentiseconds: run.best / 2)
            }
        }
    }

    /// Two rivals via signed payloads (the only way in — the store applies
    /// real shares), each with a handful of times so the head-to-head reads.
    private static func seedRivals(_ friends: FriendsStore, settings: Settings) {
        settings.shareName = "You"
        let rosters: [(name: String, scores: [RivalScore])] = [
            (
                "Aoi",
                [
                    RivalScore(config: .basic(.beginner), best: 744),
                    RivalScore(config: .basic(.expert), best: 13_050),
                    RivalScore(config: .hive(.s, .normal, .flat), best: 2_120),
                ]
            ),
            (
                "Rei",
                [
                    RivalScore(config: .basic(.beginner), best: 905),
                    RivalScore(config: .basic(.intermediate), best: 3_980),
                    RivalScore(config: .grid(.m, .hard, .flat), best: 8_010),
                ]
            ),
        ]
        for roster in rosters {
            let identity = ShareIdentity()
            let scores = roster.scores.map { entry in
                SharedConfigScore(
                    key: entry.config.storageKey, best: entry.best, wins: 5,
                    bestProgress: nil, recentPace: nil, bestPace: nil)
            }
            if let payload = try? identity.makePayload(
                name: roster.name, scores: scores, career: nil, issuedAt: Date())
            {
                _ = friends.apply(payload)
            }
        }
    }

    /// A short live streak ending today, plus a couple of earlier days, so the
    /// Home card and calendar show a run rather than "not played yet".
    private static func seedDaily(_ daily: DailyStore) {
        let today = DailyChallenge.dayOrdinal(of: DailyChallenge.dateKey()) ?? 0
        for back in 0..<5 {
            guard let key = DailyMerge.dateKey(ordinal: today - back) else { continue }
            daily.recordAttempt(
                dateKey: key,
                .init(
                    won: true, centiseconds: 1_500 + back * 120, threeBV: 40, progress: 1,
                    live: true))
        }
    }
}

extension View {
    /// Applies the deterministic screenshot accent when capturing; a no-op in
    /// normal use (the app keeps the system accent). Sets both `tint` and
    /// `accentColor` so SwiftUI controls and `Color.accentColor` fills pin to
    /// blue on iOS. macOS is the exception: AppKit resolves the selection/
    /// control accent from the SYSTEM setting regardless, so for Mac captures
    /// set the machine's accent to Blue (System Settings ▸ Appearance) — see
    /// SCREENSHOTS.md. The tint here still fixes the SwiftUI-drawn accents.
    @ViewBuilder public func screenshotAccent() -> some View {
        if let accent = DemoSeed.screenshotAccent {
            tint(accent).accentColor(accent)
        } else {
            self
        }
    }
}
