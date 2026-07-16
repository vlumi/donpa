import DonpaCore
import SwiftUI

/// The end-of-game result screen: a comic frame that slams in over the board and
/// stays until dismissed (X / tap / Esc). Dims the BOARD only — the control strip
/// stays live, so the panel carries no buttons. The art is a drop-in PNG; the FX
/// (accent glow, slam-in, record badge) are procedural.
struct MangaPanelView: View {
    /// Whether a loss beat the prior best clear-%, and by how much.
    enum LossBest: Equatable {
        case notBest  // didn't beat the prior best — no pill
        case first  // first recorded progress on this config — no delta to show
        case improved(by: Double)  // beat the prior best by this progress fraction
    }

    enum Kind: Equatable {
        case win
        /// A win that set a new best time. `centiseconds` is the new best; `improvedBy`
        /// is the centiseconds shaved off the prior best, or nil on a first-ever clear
        /// (no prior best to beat). The badge shows the improvement, not the final
        /// time — the time is already on the timer.
        case record(centiseconds: Int, improvedBy: Int?)
        /// A loss: fraction of safe cells cleared, safe cells still unopened, and the
        /// best-progress status. `safeRemaining` lets the display show "N left"
        /// instead of a misleading "100%" on a last-cell loss.
        case loss(progress: Double, safeRemaining: Int, best: LossBest)

        var isWin: Bool {
            if case .loss = self { return false }
            return true
        }
        var imageName: String { isWin ? "PanelWin" : "PanelLoss" }
        var accent: Color { isWin ? .green : .red }
        /// Spoken description for VoiceOver (the art conveys nothing to it).
        /// `hexCells` picks the board's cell word for the loss line (tiles/cells).
        func a11yLabel(hexCells: Bool = false, isDaily: Bool = false) -> String {
            switch self {
            case .win:
                return isDaily
                    ? String(localized: "Daily challenge cleared", bundle: .module)
                    : String(localized: "Minefield cleared", bundle: .module)
            case .record(let cs, _):
                let time = TimeFormat.mmsst(centiseconds: cs)
                return isDaily
                    ? String(
                        localized: "Today's best! Daily challenge cleared in \(time)",
                        bundle: .module)
                    : String(
                        localized: "New record! Minefield cleared in \(time)", bundle: .module)
            case .loss(let progress, let safeRemaining, _):
                let cleared = Self.clearedDisplay(
                    progress, safeRemaining: safeRemaining, hexCells: hexCells)
                var line = String(
                    localized: "Boom — you stepped on a mine. \(cleared).", bundle: .module)
                // The best-loss corner pill's news, which the visual-only overlay
                // would otherwise keep from VoiceOver.
                if bestLossHeadline != nil {
                    let best =
                        if let improved = lossImprovedBy {
                            String(
                                localized:
                                    "New best clear (\(Kind.progressImprovement(improved))).",
                                bundle: .module)
                        } else {
                            String(localized: "Your best clear on this board.", bundle: .module)
                        }
                    line += " " + best
                }
                return line
            }
        }
        var recordCentiseconds: Int? {
            if case .record(let cs, _) = self { return cs }
            return nil
        }
        var recordImprovedBy: Int? {
            if case .record(_, let by) = self { return by }
            return nil
        }
        /// The headline string for a *best* loss pill — "N left" when the player
        /// lost on the last cells (would otherwise read a misleading "100%"),
        /// otherwise the cleared percent. `nil` unless this is a new-best loss.
        var bestLossHeadline: String? {
            if case .loss(let p, let rem, let best) = self, best != .notBest {
                return Self.lossHeadline(p, safeRemaining: rem)
            }
            return nil
        }
        var lossImprovedBy: Double? {
            if case .loss(_, _, .improved(let by)) = self { return by }
            return nil
        }

        /// Whole-percent string, FLOORED to match the scoreboard's "Best %" and the
        /// live readout (so 87.6% reads "87%", not a higher figure than reached).
        static func percent(_ fraction: Double) -> String {
            "\(Int((fraction * 100).rounded(.down)))%"
        }

        /// Short loss headline: the cleared percent, except when it would round to
        /// 100% on a non-clear — then "N left" (rounded, so a 99.6% near-clear still
        /// reads "N left" as the "so close" cue, not a flat "99%").
        static func lossHeadline(_ fraction: Double, safeRemaining: Int) -> String {
            if Int((fraction * 100).rounded()) >= 100 && safeRemaining > 0 {
                return String(localized: "\(safeRemaining) left", bundle: .module)
            }
            return percent(fraction)
        }

        /// Sentence fragment for the consolation/a11y line. The cell word follows
        /// the board's shape — tiles on square boards, cells on hive boards (FI
        /// ruudut/kennot, matching the family names Ruutu/Kenno).
        static func clearedDisplay(
            _ fraction: Double, safeRemaining: Int, hexCells: Bool = false
        ) -> String {
            if Int((fraction * 100).rounded()) >= 100 && safeRemaining > 0 {
                return hexCells
                    ? String(localized: "So close — \(safeRemaining) cells left", bundle: .module)
                    : String(localized: "So close — \(safeRemaining) tiles left", bundle: .module)
            }
            return String(localized: "Cleared \(percent(fraction))", bundle: .module)
        }

        /// A time improvement as "−m:ss.t" (or "−s.t" under a minute) — how much was
        /// shaved off the prior best. The minus sign reads as "faster".
        static func timeImprovement(_ centiseconds: Int) -> String {
            "−" + TimeFormat.mmsst(centiseconds: centiseconds)
        }

        /// A progress improvement as "+N%" (floored, so it never overstates).
        static func progressImprovement(_ fraction: Double) -> String {
            "+\(Int((fraction * 100).rounded(.down)))%"
        }
    }

    let kind: Kind
    var hexCells = false
    /// A daily-challenge result: the ribbon and a11y read as the day's own
    /// competition, not an all-time record.
    var isDaily = false
    var unlockedLabels: [String] = []
    var earnedFeatTitles: [String] = []
    let reduceMotion: Bool
    /// The guess that ENDED this game, when its final action was a genuine
    /// forced guess — the "was that luck or my mistake?" answer. Arrives async
    /// (computed off-thread), so the host passes it reactively.
    var guess: (odds: String, label: LocalizedStringKey)?
    /// This win's pace (3BV/s), or nil (losses, or a pre-pace record). A
    /// quiet caption chip, not a pill — it shows on EVERY win, and shouting
    /// every time would cheapen the event pills around it.
    var pace: Double?
    /// This pace beat the config's prior best — the chip dresses up.
    var paceIsRecord = false
    let onContinue: () -> Void

    // Internal (not `private`): the corner overlays live in
    // MangaPanelView+Overlays.swift — Swift `private` is file-scoped.
    @State var appeared = false
    #if os(macOS)
    @FocusState private var focused: Bool
    #endif

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed backdrop over the BOARD only (this view overlays the board,
                // not the window), so the control strip stays live. Tap dismisses.
                Color.black.opacity(appeared ? 0.45 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { onContinue() }
                    .accessibilityHidden(true)

                // Sized to the board area minus a margin, so it's never clipped.
                panelImage
                    .frame(
                        maxWidth: min(panelWidth(in: geo.size), geo.size.width - 24),
                        maxHeight: geo.size.height - 24
                    )
                    .scaleEffect(scale)
                    .opacity(appeared ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #if os(macOS)
            // Hold keyboard focus (ring suppressed) so Esc closes the panel, which
            // the SpriteKit board would otherwise swallow. `.onExitCommand` is the
            // proper Escape hook (a menu key-equivalent isn't delivered by AppKit).
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onExitCommand { onContinue() }
            #endif
        }
        .onAppear { animateIn() }
    }

    /// Responsive panel width: size off the shorter window dimension (the art is
    /// roughly square) and clamp.
    private func panelWidth(in size: CGSize) -> CGFloat {
        let shorter = min(size.width, size.height)
        return min(max(shorter * 0.82, 220), 900)
    }

    private var panelImage: some View {
        Image(kind.imageName, bundle: .module)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            // No white backing: the art's interior is baked opaque-white, only the
            // area outside its border is transparent, so the corners show through.
            .overlay(alignment: .topLeading) { recordBadge }
            .overlay(alignment: .topLeading) { bestLossPill }
            .overlay(alignment: .topLeading) { dailyTag }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    guessPill
                    paceChip
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Both progression stickers share the corner, stacked — a game
                // can unlock a board AND pin a decoration.
                VStack(alignment: .trailing, spacing: 6) {
                    unlockSticker
                    featSticker
                }
            }
            .overlay(alignment: .topTrailing) { closeButton }
            // Subtle accent glow over the mono art (frames rather than tints).
            .shadow(color: kind.accent.opacity(0.7), radius: 28)
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            .contentShape(Rectangle())
            .onTapGesture { onContinue() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                kind.a11yLabel(hexCells: hexCells, isDaily: isDaily) + guessA11ySuffix
                    + paceA11ySuffix
                    + (Self.unlockSpoken(unlockedLabels).map { " " + $0 + "." } ?? "")
            )
            .accessibilityAddTraits(.isImage)
    }

}

// MARK: Sticker headlines

extension MangaPanelView {
    /// One feat reads verbatim under the singular eyebrow; several become a
    /// count under the plural one — a singular eyebrow over a plural body
    /// ("KUNNIAMERKKI / Uusia kunniamerkkejä") read as a number mismatch.
    static func featSticker(_ titles: [String]) -> (eyebrow: String, body: String)? {
        switch titles.count {
        case 0: return nil
        case 1:
            return (String(localized: "Decoration", bundle: .module), titles[0])
        default:
            return (
                String(localized: "Decorations", bundle: .module),
                String(localized: "\(titles.count) new", bundle: .module)
            )
        }
    }

    /// The sticker's second line: the one opened name, or the generic plural.
    static func unlockHeadline(_ labels: [String]) -> String? {
        switch labels.count {
        case 0: return nil
        case 1: return labels[0]
        default: return String(localized: "New boards", bundle: .module)
        }
    }

    private var scale: CGFloat {
        if reduceMotion { return 1 }
        return appeared ? 1 : 1.4
    }

    private func animateIn() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { appeared = true }
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

/// The corner pills' shared dress: a manga sticker — paper fill, ink text, a
/// thick accent border. Ink-on-paper is ~21:1 in either appearance (the old
/// white-on-accent fills measured 2.2:1 on the win green); the accent moves to
/// the border, where it flags win/loss without carrying the text.
/// Internal (not `private`): the corner overlays in MangaPanelView+Overlays
/// wear the same stamp — Swift `private` is file-scoped.
struct PillStamp: ViewModifier {
    let accent: Color
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.black)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white))
            .overlay(Capsule().stroke(accent, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
    }
}
