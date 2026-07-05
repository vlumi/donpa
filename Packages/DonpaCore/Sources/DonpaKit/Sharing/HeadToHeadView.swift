import DonpaCore
import SwiftUI

/// A head-to-head: your best times against one friend's (or a group's best) across
/// every board either side has cleared, with a win/loss tally. Reached from the
/// friends list. Read-only.
struct HeadToHeadView: View {
    @ObservedObject var scoreboard: Scoreboard
    /// The opponent's display name (friend's name, or the group's name).
    let opponentName: String
    /// The computed head-to-head (built by `RivalRanking` from the live stores).
    let result: RivalRanking.H2H
    /// Career totals to compare (yours vs. theirs), or nil — only for a single rival who
    /// opted to share career (a group's career isn't meaningfully aggregated).
    var career: (yours: SharedCareer, theirs: SharedCareer)?
    @Environment(\.dismiss) private var dismiss

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
                List {
                    Section {
                        ForEach(result.rows) { rowView($0) }
                    } header: {
                        header
                    }
                    if let career { careerSection(career) }
                }
            }
        }
    }

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
            careerRow("Tiles cleared", career.yours.tilesOpened, career.theirs.tilesOpened)
            careerRow("Flags placed", career.yours.flagsPlaced, career.theirs.flagsPlaced)
            careerRow("Mines disarmed", career.yours.minesDisarmed, career.theirs.minesDisarmed)
            careerRow("Mines hit", career.yours.minesHit, career.theirs.minesHit, lowerBetter: true)
            careerRow("Chords used", career.yours.chordsUsed, career.theirs.chordsUsed)
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
            careerValue(fmt(theirs), lead: theyLead)
        }
        .font(.callout)
    }

    private func careerValue(_ text: String, lead: Bool) -> some View {
        Text(verbatim: text)
            .font(.callout.monospaced())
            .fontWeight(lead ? .bold : .regular)
            .foregroundStyle(lead ? Color.accentColor : .primary)
            // A long duration ("10 h 39 min") mustn't wrap to two lines — shrink it.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 76, alignment: .trailing)
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

    private var header: some View {
        HStack {
            Text("Board", bundle: .module)
            Spacer()
            Text("You", bundle: .module).frame(width: 76, alignment: .trailing)
            Text(verbatim: opponentName).frame(width: 72, alignment: .trailing).lineLimit(1)
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func rowView(_ row: RivalRanking.H2HRow) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.label).lineLimit(1).minimumScaleFactor(0.7)
                // Group compare: who on the other side holds this board's best.
                if let holder = row.holderName {
                    Text(verbatim: holder).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            // YOUR column: your time, and — beneath it — your signed, colored gap vs.
            // them, so the delta unambiguously reads as *yours* (not the rival's).
            VStack(alignment: .trailing, spacing: 1) {
                time(row.yourBest, winner: row.lead == .you)
                if let gap = row.gap, gap != 0 { gapLabel(gap) }
            }
            .frame(width: 76, alignment: .trailing)
            time(row.theirBest, winner: row.lead == .them)
                .frame(width: 72, alignment: .trailing)
        }
        .font(.callout)
    }

    /// Your signed gap vs. theirs: −faster (green), +slower (red). Placed under YOUR
    /// time so it clearly describes you.
    private func gapLabel(_ gap: Int) -> some View {
        let faster = gap < 0
        let text = (faster ? "−" : "+") + TimeFormat.mmsst(centiseconds: abs(gap))
        return Text(verbatim: text)
            .font(.caption2.monospaced())
            .foregroundStyle(faster ? Color.green : Color.red)
    }

    /// A time cell — bolded/tinted when it's the faster (winning) side, "—" if unwon.
    @ViewBuilder private func time(_ centis: Int?, winner: Bool) -> some View {
        if let centis {
            Text(TimeFormat.mmsst(centiseconds: centis))
                .font(.body.monospaced())
                .fontWeight(winner ? .bold : .regular)
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
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 420)
        #endif
    }
}
