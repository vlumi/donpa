import DonpaCore
import Foundation

/// The feats' rule lines, shown in the Decorations grid (and, at A6, the ASC
/// definitions). Wording uses the app's REAL tier vocabulary — the spec's
/// early drafts said "Insane", but that rank's shipped name is Legend.
extension AchievementID {
    var featDescription: String {
        switch self {
        case .winFirst: return String(localized: "Win your first board.", bundle: .module)
        case .drillsL:
            return String(localized: "Win a Drills board at size L.", bundle: .module)
        case .hiveFirst:
            return String(localized: "Win your first Hive board.", bundle: .module)
        case .roundFirst:
            return String(localized: "Win a board with Round edges.", bundle: .module)
        case .hiveInsane:
            return String(
                localized: "Win a Hive board at Legend, M or larger.", bundle: .module)
        case .purityNoFlag:
            return String(
                localized: "Win without placing a single flag — M or larger, Sapper or denser.",
                bundle: .module)
        case .speedExpert:
            return String(
                localized: "Clear Expert in under 100 / 60 / 40 seconds.", bundle: .module)
        case .insaneWin:
            return String(localized: "Win a Legend board, M or larger.", bundle: .module)
        case .lunaticWin:
            return String(localized: "Win a Lunatic board — any size.", bundle: .module)
        case .luckCoinFlip:
            return String(
                localized: "Survive a forced guess at even odds or worse.", bundle: .module)
        case .luckLongShot:
            return String(
                localized: "Survive a forced guess at one-in-three or worse.", bundle: .module)
        case .luckMiracle:
            return String(
                localized: "Survive a forced guess at one-in-four or worse.", bundle: .module)
        case .fullClearSize:
            return String(
                localized: "Win every rank of one size, L or smaller.", bundle: .module)
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
                localized: "Open 100,000 / 1,000,000 tiles.", bundle: .module)
        case .milesDisarmed:
            return String(
                localized: "Disarm 1,000 / 10,000 / 100,000 mines.", bundle: .module)
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
