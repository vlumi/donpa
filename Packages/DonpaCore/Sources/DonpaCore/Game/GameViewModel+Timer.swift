import Combine
import Foundation

/// The game clock: a segmented wall-clock timer (`elapsed = accumulated +
/// (now − runningSince)`), so pausing folds the live span into a plain number
/// that persists cleanly. Split from `GameViewModel` for the file-length budget;
/// the timer state it drives lives on the class (internal, not `private`, which
/// is file-scoped).
extension GameViewModel {
    /// The UI's ONE answer to "what is the game doing right now" — folds the
    /// engine's pure `GameStatus` with the UI-only pause flag, so views stop
    /// hand-combining `status == .playing && !isPaused`. `.paused` outranks
    /// `.playing` (a paused game is playable-but-frozen); a finished game can't
    /// be paused (`pause()` guards on live).
    public enum PlayState: Equatable, Sendable {
        case notStarted, playing, paused, finished
    }
    public var playState: PlayState {
        if game.status.isFinished { return .finished }
        if isPaused { return .paused }
        return game.status == .playing ? .playing : .notStarted
    }

    /// Pause the clock mid-game (game stays playable-but-frozen). No-op unless live.
    public func pause() {
        guard playState == .playing else { return }
        // Flush while the clock is still live, so the scoreboard (opened via a
        // pause) shows current tiles/flags/time.
        flushActivity()
        foldRunningSpan()
        timer?.cancel()
        timer = nil
        isPaused = true
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        // The final reveal can finish OFF-main while paused (pause during the
        // compute); don't restart the clock on a decided board — it would tick
        // past the recorded final time.
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

    /// `accumulated` + the live span (if running).
    func currentCentiseconds() -> Int {
        guard let runningSince else { return accumulatedCentiseconds }
        let span = max(0, Int((Date().timeIntervalSince(runningSince) * 100).rounded()))
        return accumulatedCentiseconds + span
    }

    /// Move the live running span into `accumulated` and clear it.
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
