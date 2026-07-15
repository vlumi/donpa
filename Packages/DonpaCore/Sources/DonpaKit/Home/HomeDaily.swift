import DonpaCore
import SwiftUI

/// The Home menu's "Today's orders" card: the day's board, your standing on
/// it, and the participation streak. Hidden before the feature's epoch.
extension HomeScreen {
    @ViewBuilder func dailyCard(board: DailyChallenge.Board) -> some View {
        Button(action: onDaily) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Today's orders", bundle: .module)
                } icon: {
                    Image(systemName: "calendar.badge.exclamationmark")
                }
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                HStack {
                    Text(verbatim: board.config.fullLabel)
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    dailyStanding
                }
                dailyCardFooter
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentColor.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
        )
        .accessibilityIdentifier("home.daily")
    }

    @ViewBuilder private var dailyCardFooter: some View {
        HStack {
            if dailyStreak.current > 0 {
                Text(
                    "Streak \(dailyStreak.current) · longest \(dailyStreak.longest)",
                    bundle: .module
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            // Hand-drawn chrome on a .plain button, NOT .bordered: a native
            // bordered control is the title's only focusable view, so Tab
            // moved SYSTEM focus onto it — stealing the KeyCatcher's first-
            // responder seat and with it the home cursor's Return.
            Button(action: onDailyCalendar) {
                Label {
                    Text("History", bundle: .module)
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityIdentifier("home.daily.history")
            .modifier(homeRing(.dailyHistory))
        }
    }

    @ViewBuilder private var dailyStanding: some View {
        if let best = dailyDay?.best {
            HStack(spacing: 6) {
                Text(TimeFormat.mmsst(centiseconds: best.centiseconds))
                    .font(.subheadline.monospaced().bold())
                PaceText(pace: best.pace)
            }
        } else if let progress = dailyDay?.bestProgress {
            Text(verbatim: StatBlock.percent(progress))
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
        } else {
            Text("Not played yet", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
