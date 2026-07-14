import Combine
import Foundation

extension GameViewModel {
    /// The UI's one answer to "what is the game doing": `GameStatus` folded
    /// with the pause flag. `.paused` outranks `.playing` (a paused game is
    /// playable-but-frozen); a finished game can't be paused.
    public enum PlayState: Equatable, Sendable {
        case notStarted, playing, paused, finished
    }
    public var playState: PlayState {
        if game.status.isFinished { return .finished }
        if isPaused { return .paused }
        return game.status == .playing ? .playing : .notStarted
    }

    public func pause() {
        guard playState == .playing else { return }
        // Flush while the clock is still live, so a scoreboard opened via a
        // pause shows current tiles/flags/time.
        flushActivity()
        foldRunningSpan()
        timer?.cancel()
        timer = nil
        isPaused = true
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        // The final reveal can finish off-main while paused; don't restart the
        // clock on a decided board — it would tick past the recorded final time.
        if game.status == .playing { startTimer() }
    }

    func startTimer() {
        runningSince = Date()
        // Tick ~10×/sec for tenths; the value is from the wall clock, so no drift.
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.clock.elapsedCentiseconds = self.currentCentiseconds()
            }
    }

    func currentCentiseconds() -> Int {
        guard let runningSince else { return accumulatedCentiseconds }
        let span = max(0, Int((Date().timeIntervalSince(runningSince) * 100).rounded()))
        return accumulatedCentiseconds + span
    }

    func foldRunningSpan() {
        accumulatedCentiseconds = currentCentiseconds()
        runningSince = nil
        clock.elapsedCentiseconds = accumulatedCentiseconds
    }

    func resetTimer() {
        timer?.cancel()
        timer = nil
        accumulatedCentiseconds = 0
        runningSince = nil
        isPaused = false
        clock.elapsedCentiseconds = 0
    }
}
