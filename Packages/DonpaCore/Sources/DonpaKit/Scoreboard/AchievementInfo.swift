import DonpaCore
import Foundation

/// Feat titles — locked with the IDs in DECISIONS.md ("Progression").
extension AchievementID {
    var title: String {
        switch self {
        case .winFirst: return String(localized: "Boots On", bundle: .module)
        case .drillsL: return String(localized: "Graduation Exercise", bundle: .module)
        case .hiveFirst: return String(localized: "Into the Hive", bundle: .module)
        case .roundFirst: return String(localized: "Full Circle", bundle: .module)
        case .hiveInsane: return String(localized: "Hornet's Nest", bundle: .module)
        case .purityNoFlag: return String(localized: "Bare Hands", bundle: .module)
        case .speedExpert: return String(localized: "Expert Sweep", bundle: .module)
        case .insaneWin: return String(localized: "Stuff of Legends", bundle: .module)
        case .lunaticWin: return String(localized: "Full Moon", bundle: .module)
        case .luckCoinFlip: return String(localized: "Coin Flip", bundle: .module)
        case .fullClearSize: return String(localized: "Sector Secure", bundle: .module)
        case .trifecta: return String(localized: "The Classics", bundle: .module)
        case .trifectaTime: return String(localized: "Hat Trick", bundle: .module)
        case .milesWins: return String(localized: "Campaigner", bundle: .module)
        case .milesTiles: return String(localized: "Ground Covered", bundle: .module)
        case .milesDisarmed: return String(localized: "Bomb Squad", bundle: .module)
        case .hiddenSecond: return String(localized: "Beginner's Unluck", bundle: .module)
        case .hiddenThirteen: return String(localized: "Cursed Time", bundle: .module)
        case .hiddenSoClose: return String(localized: "So Close", bundle: .module)
        case .hiddenOvertime: return String(localized: "Overtime", bundle: .module)
        }
    }
}
