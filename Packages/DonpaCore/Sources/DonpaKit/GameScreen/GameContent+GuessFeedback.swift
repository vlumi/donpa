import DonpaCore
import SwiftUI

/// In-the-moment forced-guess feedback: a transient toast when a mid-game guess
/// is survived, and the odds handed to the result panel's corner pill when the
/// game-ending action was a genuine forced guess. Without these the tracking is
/// honest but mute — you can't tell "I got lucky", "I died to fate" and "I died
/// to a deduction I missed" apart. (No message on a guess-death means playing
/// on could still have resolved those cells — see GuessOdds+Unresolvable.)
extension GameContent {

    /// A new verdict landed (async, off the reveal/chord that produced it).
    /// Mid-game survivals toast; game-ending verdicts render on the result panel
    /// instead (reactively — `mangaPanel` reads `lastForcedGuess` directly).
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

    /// The odds for the result panel's pill: only when the LATEST analyzed action
    /// matches the way the game ended (a survived guess on a win, a fatal one on
    /// a loss) — `lastForcedGuess` is cleared on every new action, so on a
    /// finished game it can only describe the action that ended it.
    var panelGuessOdds: String? {
        guard let event = viewModel.lastForcedGuess, let panel,
            event.survived == panel.isWin
        else { return nil }
        return StatBlock.percent(event.survival)
    }

    /// The survived-guess toast, top-center over the board, self-dismissing.
    @ViewBuilder var guessToastOverlay: some View {
        if let toast = guessToast {
            HStack(spacing: 7) {
                Image(systemName: "dice")
                    .font(.caption.weight(.black))
                Text(
                    "Survived a forced guess (\(StatBlock.percent(toast.survival)))",
                    bundle: .module
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
}
