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
                    header
                    ForEach(result.rows) { row in
                        rowView(row)
                    }
                }
            }
        }
    }

    /// The scoreline: how many boards each side leads.
    private var tally: some View {
        HStack {
            Text("You", bundle: .module).fontWeight(.bold)
            Text(verbatim: "\(result.youLead)").font(.title3.monospaced().bold())
            Spacer()
            Text(verbatim: "\(result.theyLead)").font(.title3.monospaced().bold())
            Text(verbatim: opponentName).fontWeight(.bold).lineLimit(1)
        }
        .padding(.horizontal, 4)
    }

    private var header: some View {
        HStack {
            Text("Board", bundle: .module)
            Spacer()
            Text("You", bundle: .module).frame(width: 72, alignment: .trailing)
            Text(verbatim: opponentName).frame(width: 72, alignment: .trailing).lineLimit(1)
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func rowView(_ row: RivalRanking.H2HRow) -> some View {
        HStack {
            Text(verbatim: row.label).lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            time(row.yourBest, winner: row.lead == .you)
                .frame(width: 72, alignment: .trailing)
            time(row.theirBest, winner: row.lead == .them)
                .frame(width: 72, alignment: .trailing)
        }
        .font(.callout)
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
