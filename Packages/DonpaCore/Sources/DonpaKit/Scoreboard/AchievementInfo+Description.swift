import DonpaCore
import Foundation

/// The feats' rule lines. Wording uses the shipped rank name "Legend" — the
/// `insane` case names predate the rename.
extension AchievementID {
    var featDescription: String {
        switch self {
        case .winFirst: return String(localized: "Win your first board.", bundle: .module)
        case .drillsL:
            return String(localized: "Win a Drills board at size L.", bundle: .module)
        case .hiveFirst:
            return String(localized: "Win your first Hive board.", bundle: .module)
        case .roundFirst:
            return String(
                localized: "Win a board with Round edges — the world wraps around.",
                bundle: .module)
        case .hiveInsane:
            return String(
                localized: "Win a Hive board at Legend, M or larger.", bundle: .module)
        case .purityNoFlag:
            return String(
                localized: "Win without placing a single flag — M or larger, Sapper or denser.",
                bundle: .module)
        case .speedExpert:
            return String(
                localized: "Clear Expert in under three minutes.", bundle: .module)
        case .insaneWin:
            return String(localized: "Win a Legend board, M or larger.", bundle: .module)
        case .lunaticWin:
            return String(localized: "Win a Lunatic board — any size.", bundle: .module)
        case .luckCoinFlip:
            return String(
                localized: "Survive a forced guess at even odds or worse.", bundle: .module)
        case .fullClearSize:
            return String(
                localized: "Win every rank of one size.", bundle: .module)
        case .trifecta:
            return String(
                localized: "Win Beginner, Intermediate and Expert.", bundle: .module)
        case .trifectaTime:
            return String(
                localized: "The classic trifecta with combined bests under 5:00.",
                bundle: .module)
        case .milesWins:
            return String(localized: "Win 10 / 100 / 1,000 boards.", bundle: .module)
        case .milesTiles:
            return String(
                localized: "Open 10,000 / 100,000 / 1,000,000 tiles.", bundle: .module)
        case .milesDisarmed:
            return String(
                localized: "Disarm 1,000 / 10,000 / 100,000 mines.", bundle: .module)
        case .dailyStreak:
            return String(
                localized: "Play the daily challenge 1 / 7 / 30 days running.",
                bundle: .module)
        case .hiddenSecond:
            return String(localized: "Lose on your second reveal.", bundle: .module)
        case .hiddenThirteen:
            return String(
                localized: "Win with a final time of 13.x seconds.", bundle: .module)
        case .hiddenSoClose:
            return String(localized: "Lose with 99% or more cleared.", bundle: .module)
        case .hiddenOvertime:
            return String(
                localized: "Win a board after more than 999 seconds.", bundle: .module)
        }
    }
}
