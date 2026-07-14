import DonpaCore
import SwiftUI

struct FriendRow: View {
    let friend: Friend
    let groupNames: [String]

    private var boardsWon: Int { friend.scores.filter { $0.wins > 0 }.count }
    private var totalWins: Int { friend.scores.reduce(0) { $0 + $1.wins } }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName).font(.body.bold())
                    .lineLimit(1).minimumScaleFactor(0.7)
                if friend.localAlias != nil {
                    Text(friend.sharedName).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // The share's own timestamp — the data is a snapshot that only changes on re-share.
                Text(
                    "Updated \(friend.lastIssuedAt.formatted(date: .abbreviated, time: .omitted))",
                    bundle: .module
                )
                .font(.caption2).foregroundStyle(.secondary)
                if !groupNames.isEmpty {
                    // .secondary, not .tertiary: tertiary caption2 sat near-invisible for low vision.
                    Text(groupNames.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(totalWins) wins", bundle: .module).font(.subheadline.bold())
                Text("\(boardsWon) boards", bundle: .module)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
