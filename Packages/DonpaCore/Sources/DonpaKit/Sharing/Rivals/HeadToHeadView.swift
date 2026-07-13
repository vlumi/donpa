import DonpaCore
import SwiftUI

/// A head-to-head: your best times against one friend's (or a group's best) across
/// every board either side has cleared, with a win/loss tally. Reached from the
/// friends list.
struct HeadToHeadView: View {
    @ObservedObject var scoreboard: Scoreboard
    /// The opponent's display name (friend's name, or the group's name).
    let opponentName: String
    /// The computed head-to-head (built by `FriendRanking` from the live stores).
    let result: FriendRanking.H2H
    /// Career totals to compare (yours vs. theirs), or nil — only for a single rival who
    /// opted to share career (a group's career isn't meaningfully aggregated).
    var career: (yours: SharedCareer, theirs: SharedCareer)?
    /// Start a fresh game on a row's board — the "I'm trailing here, rematch" loop.
    /// The host owns the navigation (dismissing this sheet included).
    var onPlay: ((GameConfig) -> Void)?
    @Environment(\.dismiss) private var dismiss
    /// The keyboard-focused board row (arrow navigation across all groups);
    /// inert off macOS.
    @State private var keyIndex: Int?

    /// The your/their value columns, grown with Dynamic Type (×1 at the
    /// default size) so enlarged times actually enlarge. Shared by the career
    /// rows, the group headers, and the per-board rows so they stay aligned.
    @ScaledMetric(relativeTo: .callout) private var yourColumnWidth: CGFloat = 76
    @ScaledMetric(relativeTo: .callout) private var theirColumnWidth: CGFloat = 72

    var body: some View {
        chrome
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 12) {
            tally
            if result.rows.isEmpty {
                Text(
                    "No shared boards yet — play some of the same boards to compare.",
                    bundle: .module
                )
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollViewReader { proxy in
                    List {
                        // Sticky family+edges sub-sections (New Game's ordering
                        // falls out of the canonical config order), so the rows
                        // themselves stay as slim as the Service Record's — the
                        // full per-row "Family · Size · …" text truncated on an SE.
                        ForEach(FriendRanking.grouped(result.rows)) { group in
                            Section {
                                ForEach(group.rows) { row in
                                    rowView(row)
                                        .id(row.id)
                                        .keyFocusRing(rowFocused(row), inset: 1)
                                }
                            } header: {
                                groupHeader(group)
                            }
                        }
                        if let career { careerSection(career) }
                    }
                    .background(h2hKeyCatcher(proxy))
                }
                // Plain, not the sheet-default inset-grouped: only plain PINS its
                // section headers while scrolling — the whole point of the family
                // sub-sections on a long comparison.
                .listStyle(.plain)
            }
        }
    }

    private func rowFocused(_ row: FriendRanking.H2HRow) -> Bool {
        keyIndex.map { result.rows.indices.contains($0) && result.rows[$0].id == row.id }
            ?? false
    }

    /// Arrows walk the board rows (following with the scroll); P and Space
    /// rematch the focused board, and so does Return — with no row focused
    /// it's the default, Done. Esc closes (routed here since the catcher owns
    /// keyDown).
    @ViewBuilder private func h2hKeyCatcher(_ proxy: ScrollViewProxy) -> some View {
        #if os(macOS)
        KeyCatcher { key in
            switch key {
            case .down, .tab: moveRowFocus(1, proxy: proxy)
            case .up, .backTab: moveRowFocus(-1, proxy: proxy)
            case .character("p"), .space: playFocused()
            case .enter:
                if keyIndex == nil { dismiss() } else { playFocused() }
            case .escape: dismiss()
            case .click: keyIndex = nil  // mouse takes over
            default: break
            }
        }
        #endif
    }

    #if os(macOS)
    private func moveRowFocus(_ delta: Int, proxy: ScrollViewProxy) {
        guard let next = KeyStep.moved(keyIndex, by: delta, count: result.rows.count) else {
            return
        }
        keyIndex = next
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(result.rows[next].id, anchor: .center)
        }
    }

    private func playFocused() {
        guard let index = keyIndex, result.rows.indices.contains(index) else { return }
        onPlay?(result.rows[index].config)
    }
    #endif

    /// Lifetime career, you vs. them — shown only when the rival shared it. Each stat
    /// is one row; the higher side is tinted so you see who leads at a glance. "More is
    /// better" for every stat here except mines hit, where fewer is better.
    @ViewBuilder private func careerSection(_ career: (yours: SharedCareer, theirs: SharedCareer))
        -> some View
    {
        Section {
            careerRow("Games played", career.yours.gamesPlayed, career.theirs.gamesPlayed)
            careerRow("Wins", career.yours.wins, career.theirs.wins)
            careerRow("No-flag wins", career.yours.noFlagWins, career.theirs.noFlagWins)
            careerRow("No-chord wins", career.yours.noChordWins, career.theirs.noChordWins)
            // Opening actions grouped (tiles + chords), then flags/mines, per StatBlock.
            careerRow("Tiles cleared", career.yours.tilesOpened, career.theirs.tilesOpened)
            careerRow("Chords used", career.yours.chordsUsed, career.theirs.chordsUsed)
            careerRow("Flags placed", career.yours.flagsPlaced, career.theirs.flagsPlaced)
            careerRow("Mines disarmed", career.yours.minesDisarmed, career.theirs.minesDisarmed)
            careerRow("Mines hit", career.yours.minesHit, career.theirs.minesHit, lowerBetter: true)
            careerRow(
                "Time played", career.yours.playtimeCentiseconds,
                career.theirs.playtimeCentiseconds, isTime: true)
        } header: {
            Text("Career", bundle: .module)
        }
    }

    /// One career stat row: label, your value, their value; the leader tinted.
    private func careerRow(
        _ label: LocalizedStringKey, _ mine: Int, _ theirs: Int,
        lowerBetter: Bool = false, isTime: Bool = false
    ) -> some View {
        let iLead = lowerBetter ? mine < theirs : mine > theirs
        let theyLead = lowerBetter ? theirs < mine : theirs > mine
        func fmt(_ v: Int) -> String {
            isTime ? ScoreboardView.durationLabel(v) : ScoreboardView.grouped(v)
        }
        return HStack {
            Text(label, bundle: .module)
            Spacer()
            careerValue(fmt(mine), lead: iLead)
                .accessibilityLabel(Text("You: \(fmt(mine))", bundle: .module))
            careerValue(fmt(theirs), lead: theyLead)
                .accessibilityLabel(Text("Rival: \(fmt(theirs))", bundle: .module))
        }
        .font(.callout)
        // One utterance per stat, with each bare number owned by a side —
        // "Games played, You: 123, Rival: 45" instead of three orphan fragments.
        .accessibilityElement(children: .combine)
    }

    private func careerValue(_ text: String, lead: Bool) -> some View {
        Text(verbatim: text)
            .font(.callout.monospaced())
            .fontWeight(lead ? .bold : .regular)
            .foregroundStyle(lead ? Color.accentColor : .primary)
            // A long duration ("10 h 39 min") mustn't wrap to two lines — shrink it.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: yourColumnWidth, alignment: .trailing)
    }

    /// A centered sports-style scoreline — the two lead counts big and adjacent with a
    /// dash between (8 – 3), each under its side's name.
    private var tally: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            side(name: Text("You", bundle: .module), count: result.youLead, leading: true)
            Text(verbatim: "–").font(.title2).foregroundStyle(.secondary)
            side(name: Text(verbatim: opponentName), count: result.theyLead, leading: false)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    /// One side of the scoreline: the big count with its name caption underneath. The
    /// winning side's count is tinted so the leader reads at a glance.
    private func side(name: Text, count: Int, leading: Bool) -> some View {
        let winning = leading ? result.youLead > result.theyLead : result.theyLead > result.youLead
        return VStack(spacing: 1) {
            Text(verbatim: "\(count)")
                .font(.largeTitle.monospaced().bold())
                .foregroundStyle(winning ? Color.accentColor : .primary)
            name.font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: 120)
    }

    /// A group's sticky title: the family's New Game glyph + name (Round called out
    /// with its glyph; Flat is the unmarked default), with the column captions on
    /// the trailing side — repeated per section so they survive a long scroll.
    private func groupHeader(_ group: FriendRanking.H2HGroup) -> some View {
        HStack(spacing: 5) {
            BoardGlyph(kind: .family(group.family), size: 16, tint: .secondary)
            Text(verbatim: group.family.label)
            if group.edges.wraps {
                // The globe glyph alone — it IS the Round identity (the New Game
                // toggle's icon); the word beside it pushed FI headers past an SE's
                // width even shrunk. VoiceOver still gets the name.
                BoardGlyph(kind: .edges(group.edges), size: 16, tint: .secondary)
                    .padding(.leading, 3)
                    .accessibilityLabel(Text(verbatim: group.edges.label))
            }
            Spacer()
            Text("You", bundle: .module)
                .frame(width: yourColumnWidth, alignment: .trailing)
            Text(verbatim: opponentName)
                .frame(width: theirColumnWidth, alignment: .trailing)
        }
        .font(.caption).foregroundStyle(.secondary)
        // The List's default uppercase transform inflated the FI names past an SE's
        // width ("RUUDUKKO · PYÖREÄ" wrapped mid-word); normal case + shrink-to-fit
        // keeps every header to its one line.
        .textCase(nil)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func rowView(_ row: FriendRanking.H2HRow) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                boardLabel(row.config)
                // Group compare: who on the other side holds this board's best.
                if let holder = row.holderName {
                    Text(verbatim: holder).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let onPlay {
                Button {
                    onPlay(row.config)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("New game on this board", bundle: .module))
            }
            Spacer()
            // YOUR column: your time, and — beneath it — your signed, colored gap vs.
            // them, so the delta unambiguously reads as *yours* (not the rival's).
            VStack(alignment: .trailing, spacing: 1) {
                time(row.yourBest, winner: row.lead == .you)
                if let gap = row.gap, gap != 0 { gapLabel(gap) }
            }
            .frame(width: yourColumnWidth, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text("You: \(timeSpoken(row.yourBest))", bundle: .module))
            time(row.theirBest, winner: row.lead == .them)
                .frame(width: theirColumnWidth, alignment: .trailing)
                .accessibilityLabel(
                    Text("Rival: \(timeSpoken(row.theirBest))", bundle: .module))
        }
        .font(.callout)
    }

    /// The board, Service Record-style: the density as its rank insignia beside the
    /// size letter — the section title already carries the family and edges. Basic
    /// presets are just their name. The full spoken form stays available to
    /// VoiceOver via `fullLabel`.
    @ViewBuilder private func boardLabel(_ config: GameConfig) -> some View {
        HStack(spacing: 6) {
            if let density = config.density, let size = config.size {
                DensityInsignia.image(density)
                    .resizable().scaledToFit().frame(width: 30, height: 20)
                Text(verbatim: size.label).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(verbatim: config.label).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: config.fullLabel))
    }

    /// Your signed gap vs. theirs: −faster (green), +slower (red). Placed under YOUR
    /// time so it clearly describes you.
    private func gapLabel(_ gap: Int) -> some View {
        let faster = gap < 0
        let text = (faster ? "−" : "+") + TimeFormat.mmsst(centiseconds: abs(gap))
        return Text(verbatim: text)
            .font(.caption2.monospaced())
            .numericCell()
            .foregroundStyle(faster ? Color.green : Color.red)
    }

    /// A time as VoiceOver text — the formatted best, or "not won" for the dash.
    private func timeSpoken(_ centis: Int?) -> String {
        centis.map { TimeFormat.mmsst(centiseconds: $0) }
            ?? String(localized: "not won", bundle: .module)
    }

    /// A time cell — bolded/tinted when it's the faster (winning) side, "—" if unwon.
    @ViewBuilder private func time(_ centis: Int?, winner: Bool) -> some View {
        if let centis {
            Text(TimeFormat.mmsst(centiseconds: centis))
                .font(.body.monospaced())
                .fontWeight(winner ? .bold : .regular)
                .numericCell()
                .foregroundStyle(winner ? Color.accentColor : .primary)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var chrome: some View {
        #if os(iOS)
        NavigationStack {
            content.padding(.horizontal, 8)
                .navigationTitle(Text("Head to head", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done", bundle: .module)
                        }
                    }
                }
        }
        #else
        VStack(spacing: 12) {
            Text("Head to head", bundle: .module).font(.title2.bold())
            content.frame(minHeight: 280)
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.defaultAction)
            // Esc closes too (Done carries Return) — dismissal must not depend
            // on the Done button being on-screen.
            .escDismisses { dismiss() }
        }
        .padding(20)
        // Ideal only, no height floor: the minimum derives from the content
        // so small scaled displays fit.
        .frame(minWidth: 520, idealHeight: 600)
        #endif
    }
}
