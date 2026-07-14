import DonpaCore
import SwiftUI

// The result panel's corner overlays — pills, stickers, and their spoken
// suffixes. A sibling-file MangaPanelView extension (the panel body stays in
// MangaPanelView.swift; Swift `private` is file-scoped, so the shared state
// there is internal).
extension MangaPanelView {
    /// The quiet pace caption on wins — the luck pill's sibling (how lucky /
    /// how skilled). Chip dress, not the pill stamp: it appears every win.
    @ViewBuilder var paceChip: some View {
        if kind.isWin, let pace {
            HStack(spacing: 4) {
                Text("Pace", bundle: .module)
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .textCase(.uppercase)
                Text(verbatim: StatBlock.paceDisplay(pace))
                    .font(.system(.caption, design: .rounded).weight(.black).monospacedDigit())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white))
            .overlay(Capsule().stroke(.black, lineWidth: 1.5))
            .foregroundStyle(.black)
            .padding(.bottom, 12)
            .padding(.leading, 10)
            .opacity(appeared ? 1 : 0)
        }
    }

    var paceA11ySuffix: String {
        guard kind.isWin, let pace else { return "" }
        return " "
            + String(localized: "Pace \(StatBlock.paceDisplay(pace)).", bundle: .module)
    }

    /// The guess pill folded into the spoken label (overlays are ignored children).
    var guessA11ySuffix: String {
        guard let odds = guess?.odds else { return "" }
        return " "
            + (kind.isWin
                ? String(localized: "Won on a forced guess (\(odds)).", bundle: .module)
                : String(localized: "That was a forced guess (\(odds)).", bundle: .module))
    }

    /// The ending action was a genuine forced guess: its odds, corner-stamped on
    /// the result. On a loss this is the consolation ("fate, not error"); on a win,
    /// the brag. Bottom corner — the top corners belong to the record/best pills.
    @ViewBuilder var guessPill: some View {
        if let guess {
            VStack(spacing: 0) {
                Text(verbatim: guess.odds)
                    .font(.system(.body, design: .rounded).weight(.black))
                Text(guess.label, bundle: .module)
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .textCase(.uppercase)
            }
            .modifier(PillStamp(accent: kind.accent))
            .rotationEffect(.degrees(6))
            .padding(.bottom, 12)
            .padding(.leading, 10)
            .scaleEffect(appeared ? 1 : 0.5, anchor: .bottomLeading)
        }
    }

    /// A win that opened new content: the gating celebration, corner-stamped in
    /// the same sticker dress as the other pills. One name reads verbatim;
    /// several collapse to the generic line.
    @ViewBuilder var unlockSticker: some View {
        if let headline = Self.unlockHeadline(unlockedLabels) {
            VStack(spacing: 0) {
                Text("UNLOCKED", bundle: .module)
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .textCase(.uppercase)
                Text(verbatim: headline)
                    .font(.system(.body, design: .rounded).weight(.black))
            }
            .modifier(PillStamp(accent: Color.accentColor))
            .rotationEffect(.degrees(-6))
            .padding(.bottom, 12)
            .padding(.trailing, 10)
            .scaleEffect(appeared ? 1 : 0.5, anchor: .bottomTrailing)
        }
    }

    /// A decoration earned this game — the same sticker dress, gold border.
    @ViewBuilder var featSticker: some View {
        if let sticker = Self.featSticker(earnedFeatTitles) {
            VStack(spacing: 0) {
                Text(verbatim: sticker.eyebrow)
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .textCase(.uppercase)
                Text(verbatim: sticker.body)
                    .font(.system(.body, design: .rounded).weight(.black))
            }
            .modifier(PillStamp(accent: MedalView.gold))
            .rotationEffect(.degrees(-6))
            .padding(.bottom, 12)
            .padding(.trailing, 10)
            .scaleEffect(appeared ? 1 : 0.5, anchor: .bottomTrailing)
        }
    }

    /// The VoiceOver announcement for an unlock (nil when nothing opened).
    static func unlockSpoken(_ labels: [String]) -> String? {
        guard !labels.isEmpty else { return nil }
        return String(
            localized: "Unlocked: \(labels.joined(separator: ", "))", bundle: .module)
    }

    var closeButton: some View {
        Button(action: onContinue) {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.4))
                .padding(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close", bundle: .module))
    }

    /// "New record" flourish — a tilted corner ribbon stamp. Shows how much faster
    /// than the prior best (the final time is already on the timer); a first-ever
    /// clear has no prior to beat, so it reads as the first record instead.
    @ViewBuilder var recordBadge: some View {
        if kind.recordCentiseconds != nil {
            VStack(spacing: 0) {
                // Kana headline verbatim in all languages — a manga flourish.
                Text(verbatim: "新記録")
                    .font(.system(.callout, design: .rounded).weight(.black))
                if let improved = kind.recordImprovedBy {
                    Text(verbatim: Kind.timeImprovement(improved))
                        .font(.system(.caption, design: .monospaced).weight(.heavy))
                } else {
                    Text("first clear", bundle: .module)
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                        .textCase(.uppercase)
                }
            }
            .modifier(PillStamp(accent: kind.accent))
            .rotationEffect(.degrees(-8))
            .padding(.top, 10)
            .padding(.leading, 8)
            .scaleEffect(appeared ? 1 : 0.5, anchor: .topLeading)
        }
    }

    /// On a loss that beat the prior best %, a red corner pill mirroring the record
    /// badge. Leads with how much further than the prior best you got (+N%); the
    /// headline % / "N left" stays as the secondary line. A first-ever run has no
    /// prior to beat, so it just shows the headline. A plain loss shows nothing.
    @ViewBuilder var bestLossPill: some View {
        if let headline = kind.bestLossHeadline {
            VStack(spacing: 0) {
                if let improved = kind.lossImprovedBy {
                    Text(verbatim: Kind.progressImprovement(improved))
                        .font(.system(.body, design: .rounded).weight(.black))
                    Text(verbatim: headline)
                        .font(.system(.caption, design: .monospaced).weight(.heavy))
                } else {
                    Text(verbatim: headline)
                        .font(.system(.body, design: .rounded).weight(.black))
                    Text("best", bundle: .module)
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                        .textCase(.uppercase)
                }
            }
            .modifier(PillStamp(accent: Color.red))
            .rotationEffect(.degrees(-8))
            .padding(.top, 10)
            .padding(.leading, 8)
            .scaleEffect(appeared ? 1 : 0.5, anchor: .topLeading)
        }
    }

    /// Slam-in overshoot: starts large, settles to 1.0. Reduce Motion pins scale to 1.
}
