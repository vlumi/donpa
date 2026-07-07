import DonpaCore
import SwiftUI

/// How lucky a survived guess was — drives the toast's escalating wording and
/// the win pill's stamp. The cuts mirror the planned 0.5.0 achievement tiers
/// (Coin flip / Long shot / Miracle), so the achievements will land on words
/// the player already knows. A hair of tolerance keeps the boundary odds
/// (exactly 1/2, 1/3, 1/4) inside their tier.
enum GuessTier {
    case lucky, coinFlip, longShot, miracle

    init(survival: Double) {
        let eps = 1e-9
        if survival <= 0.25 + eps {
            self = .miracle
        } else if survival <= 1.0 / 3.0 + eps {
            self = .longShot
        } else if survival <= 0.5 + eps {
            self = .coinFlip
        } else {
            self = .lucky
        }
    }

    /// The pill's stamp word (rendered uppercased; the loss pill says
    /// "forced guess" instead — dying is never lucky).
    var pillLabel: LocalizedStringKey {
        switch self {
        case .lucky: return "lucky guess"
        case .coinFlip: return "coin flip"
        case .longShot: return "long shot"
        case .miracle: return "miracle"
        }
    }
}

/// In-the-moment forced-guess feedback: a transient toast when a mid-game guess
/// is survived, and the odds handed to the result panel's corner pill when the
/// game-ending action was a genuine forced guess. Without these the tracking is
/// honest but mute — you can't tell "I got lucky", "I died to fate" and "I died
/// to a deduction I missed" apart. (No message on a guess-death means playing
/// on could still have resolved those cells — see GuessOdds+Unresolvable.)
extension GameContent {

    /// A new verdict landed (async, off the reveal/chord that produced it).
    /// Mid-game survivals toast; game-ending verdicts render on the result panel
    /// instead (reactively — `mangaPanel` reads `lastForcedGuess` directly), so
    /// the final move never shows both.
    func handleGuessEvent(_ event: ForcedGuessEvent?) {
        guard let event, event.survived, viewModel.status == .playing else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { guessToast = event }
        guessToastTask?.cancel()
        guessToastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { guessToast = nil }
        }
    }

    /// The result panel's guess pill: only when the LATEST analyzed action
    /// matches the way the game ended (a survived guess on a win, a fatal one on
    /// a loss) — `lastForcedGuess` is cleared on every new action, so on a
    /// finished game it can only describe the action that ended it. A win's
    /// stamp escalates with the toast's tier words; a loss stamps "forced guess".
    var panelGuess: (odds: String, label: LocalizedStringKey)? {
        guard let event = viewModel.lastForcedGuess, let panel,
            event.survived == panel.isWin
        else { return nil }
        let odds = StatBlock.percent(event.survival)
        let label: LocalizedStringKey =
            panel.isWin ? GuessTier(survival: event.survival).pillLabel : "forced guess"
        return (odds, label)
    }

    /// The survived-guess toast, top-center over the board, self-dismissing.
    /// The wording escalates with the odds beaten.
    @ViewBuilder var guessToastOverlay: some View {
        if let toast = guessToast {
            HStack(spacing: 7) {
                Image(systemName: "dice")
                    .font(.caption.weight(.black))
                toastText(
                    tier: GuessTier(survival: toast.survival),
                    percent: StatBlock.percent(toast.survival)
                )
                .font(.caption.weight(.heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.82)))
            .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            .padding(.top, 14)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private func toastText(tier: GuessTier, percent: String) -> Text {
        switch tier {
        case .lucky: return Text("Lucky guess! (\(percent))", bundle: .module)
        case .coinFlip: return Text("Coin flip! (\(percent))", bundle: .module)
        case .longShot: return Text("Long shot! (\(percent))", bundle: .module)
        case .miracle: return Text("A MIRACLE! (\(percent))", bundle: .module)
        }
    }
}
