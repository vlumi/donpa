import Foundation

/// The pure, deterministic merge at the heart of cross-device scoreboard sync.
///
/// Each device owns one cloud blob keyed by its `DeviceID`, holding ONLY its own
/// counts (a stored `othersTotal` is ignored on read, so no double-counting). To
/// display the cross-device view, a device merges its own records with every
/// other device's blob:
///
/// - **Cumulative counters**: `mine` stays this device's count; `othersTotal`
///   becomes Σ of every other device's `mine`. So `total = mine + Σ others` —
///   conflict-free, order- and duplicate-independent.
/// - **"Best" fields**: idempotent `min`/`max` across all blobs, nil-safe.
///
/// Pure (no I/O, no clock), so it's unit-testable headless.
enum StatsMerge {
    /// Merge this device's records (`mine`) with the other devices' blobs
    /// (`others`, which must NOT contain this device's own id).
    static func merge(
        mine: [String: ScoreRecord], others: [String: [String: ScoreRecord]]
    ) -> [String: ScoreRecord] {
        var configKeys = Set(mine.keys)
        for table in others.values { configKeys.formUnion(table.keys) }

        var merged: [String: ScoreRecord] = [:]
        for key in configKeys {
            let ownRecord = mine[key] ?? ScoreRecord()
            let othersRecords = others.values.compactMap { $0[key] }
            merged[key] = mergeOne(own: ownRecord, others: othersRecords)
        }
        return merged
    }

    /// Merge one config's record: this device's own record against the other
    /// devices' records for the same config.
    /// Union of pace-window entries (dedup by whole entry, so a blob that
    /// already contains own entries collapses), newest first, capped.
    static func mergedRecent(_ own: [RecentWin], _ others: [[RecentWin]]) -> [RecentWin] {
        var all = Set(own)
        for list in others { all.formUnion(list) }
        return Array(all.sorted { $0.date > $1.date }.prefix(ScoreRecord.recentWinLimit))
    }

    private static func mergeOne(own: ScoreRecord, others: [ScoreRecord]) -> ScoreRecord {
        var out = own

        // Counters: keep my `mine`, set othersTotal = Σ each other device's `mine`.
        func foldCounter(_ kp: WritableKeyPath<ScoreRecord, DeviceCounter>) {
            let othersSum = others.reduce(0) { $0 + $1[keyPath: kp].mine }
            out[keyPath: kp].setOthersTotal(othersSum)
        }
        foldCounter(\.wins)
        foldCounter(\.gamesPlayed)
        foldCounter(\.losses)
        foldCounter(\.tilesOpened)
        foldCounter(\.flagsPlaced)
        foldCounter(\.minesHit)
        foldCounter(\.minesDisarmed)
        foldCounter(\.playtimeCentiseconds)
        foldCounter(\.chordsUsed)
        foldCounter(\.noFlagWins)
        foldCounter(\.noChordWins)
        foldCounter(\.forcedGuesses)
        foldCounter(\.guessesSurvived)

        // Luckiest guess is device-owned like the best time: project the
        // cross-device min (whole entries, so odds and date stay paired).
        out.luckiestGuess = ([own] + others).compactMap(\.luckiestGuess).min()

        // Best time + top times are DEVICE-OWNED: `own` keeps this device's own best
        // untouched; the DISPLAY record projects the cross-device view. Because each
        // `BestTime` carries its own timestamp, picking whole entries by their time
        // keeps every (time, date) pair intact — the timestamp is never merged apart.
        out.topTimes = own.topTimes.mergedTop(
            with: others.map(\.topTimes), limit: ScoreRecord.topTimeLimit)
        out.best = out.topTimes.first ?? own.best

        // The pace window: union across devices (whole entries, deduped),
        // newest first, same cap — the display view of every device's log.
        out.recentWins = Self.mergedRecent(own.recentWins, others.map(\.recentWins))
        // Best pace: cross-device max, whole entry (pace and date stay paired).
        out.bestPace = ([own] + others).compactMap(\.bestPace).max { $0.pace < $1.pace }

        // Loss progress: idempotent max across all devices.
        out.bestLossProgress = ([own] + others).compactMap(\.bestLossProgress).max()

        // Dates: earliest first-played, latest last-played across all devices.
        out.firstPlayed = ([own] + others).compactMap(\.firstPlayed).min()
        out.lastPlayed = ([own] + others).compactMap(\.lastPlayed).max()

        return out
    }

    /// Offline projection: FRESH own records over the last cloud merge. The cache
    /// keeps each counter's mine/othersTotal split, so the other devices' sums are
    /// recoverable without their blobs — own values come live from `own`, so offline
    /// play (and resets) show immediately instead of freezing at the cached snapshot.
    /// The cache can't be fed to `merge` as a pseudo-device: its `mine` fields ARE
    /// this device's stale counts and would double-count.
    ///
    /// Known limit: own top-time entries retired since the last sync (e.g. by a
    /// reset) can linger in the cached top list until the next online merge.
    static func offlineMerge(
        own: [String: ScoreRecord], cached: [String: ScoreRecord]
    ) -> [String: ScoreRecord] {
        var configKeys = Set(own.keys)
        configKeys.formUnion(cached.keys)

        var merged: [String: ScoreRecord] = [:]
        for key in configKeys {
            var out = own[key] ?? ScoreRecord()
            let last = cached[key]
            func foldCounter(_ kp: WritableKeyPath<ScoreRecord, DeviceCounter>) {
                out[keyPath: kp].setOthersTotal(last?[keyPath: kp].othersTotal ?? 0)
            }
            foldCounter(\.wins)
            foldCounter(\.gamesPlayed)
            foldCounter(\.losses)
            foldCounter(\.tilesOpened)
            foldCounter(\.flagsPlaced)
            foldCounter(\.minesHit)
            foldCounter(\.minesDisarmed)
            foldCounter(\.playtimeCentiseconds)
            foldCounter(\.chordsUsed)
            foldCounter(\.noFlagWins)
            foldCounter(\.noChordWins)
            foldCounter(\.forcedGuesses)
            foldCounter(\.guessesSurvived)
            out.luckiestGuess =
                [own[key]?.luckiestGuess, last?.luckiestGuess].compactMap { $0 }.min()
            // The cached top list already contains own entries — the (time, date)
            // dedup collapses them, so fresh own bests appear without doubling.
            out.topTimes = (own[key]?.topTimes ?? []).mergedTop(
                with: [last?.topTimes ?? []], limit: ScoreRecord.topTimeLimit)
            out.best = out.topTimes.first ?? out.best
            out.recentWins = Self.mergedRecent(
                own[key]?.recentWins ?? [], [last?.recentWins ?? []])
            out.bestPace = [own[key]?.bestPace, last?.bestPace]
                .compactMap { $0 }.max { $0.pace < $1.pace }
            out.bestLossProgress =
                [own[key]?.bestLossProgress, last?.bestLossProgress].compactMap { $0 }.max()
            out.firstPlayed = [own[key]?.firstPlayed, last?.firstPlayed].compactMap { $0 }.min()
            out.lastPlayed = [own[key]?.lastPlayed, last?.lastPlayed].compactMap { $0 }.max()
            merged[key] = out
        }
        return merged
    }
}
