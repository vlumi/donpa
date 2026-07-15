import DonpaCore
import SwiftUI

/// Every daily since the epoch: a month grid of day chips with the selected
/// day's record underneath. Any past day is playable — only a day played ON
/// the day feeds the streak, so replays are pure practice/records. Month
/// navigation clamps to [epoch, today].
struct DailyCalendarView: View {
    @ObservedObject var dailyStore: DailyStore
    /// Start an attempt on a day's board; the host owns dismissal + routing.
    let onPlay: (DailyChallenge.Board) -> Void

    @State private var monthAnchor: Date = Date()
    @State private var selectedKey: String = DailyChallenge.dateKey()

    private var calendar: Calendar { .current }
    private var todayKey: String { DailyChallenge.dateKey() }

    var body: some View {
        SheetScaffold(
            title: "Daily challenge", macMinWidth: 380, macIdealWidth: 420,
            content: {
                VStack(spacing: 12) {
                    header
                    monthGrid
                    Divider()
                    dayDetail
                }
                .padding(.horizontal, 12)
            },
            macFooter: { EmptyView() },
            macBackground: {
                #if os(macOS)
                KeyCatcher { handleKey($0) }
                #endif
            })
    }

    // MARK: Month navigation

    private var header: some View {
        HStack {
            monthStepButton(-1, disabled: !canStepBack)
            Spacer()
            Text(verbatim: monthAnchor.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            monthStepButton(1, disabled: !canStepForward)
        }
    }

    private func monthStepButton(_ delta: Int, disabled: Bool) -> some View {
        Button {
            step(months: delta)
        } label: {
            Image(systemName: delta < 0 ? "chevron.left" : "chevron.right")
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .accessibilityLabel(
            delta < 0
                ? Text("Previous month", bundle: .module)
                : Text("Next month", bundle: .module))
    }

    private var canStepBack: Bool {
        guard let epoch = keyDate(DailyChallenge.epochKey) else { return false }
        return monthStart(of: monthAnchor) > monthStart(of: epoch)
    }
    private var canStepForward: Bool {
        monthStart(of: monthAnchor) < monthStart(of: Date())
    }

    private func step(months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: monthAnchor) {
            monthAnchor = next
        }
    }

    // MARK: Grid

    private var monthGrid: some View {
        let days = monthDays()
        return VStack(spacing: 6) {
            weekdayHeader
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, key in
                    if let key {
                        dayChip(key)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
    }

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let ordered = Array(symbols[first...] + symbols[..<first])
        return HStack {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(verbatim: symbol)
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func dayChip(_ key: String) -> some View {
        let day = dailyStore.displayRecords[key]
        let selectable = isPlayable(key)
        Button {
            selectedKey = key
        } label: {
            VStack(spacing: 1) {
                Text(verbatim: String(key.suffix(2).drop(while: { $0 == "0" })))
                    .font(.callout.monospacedDigit())
                if let best = day?.best {
                    Text(TimeFormat.mmsst(centiseconds: best.centiseconds))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                } else if let progress = day?.bestProgress {
                    Text(verbatim: StatBlock.percent(progress))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: " ").font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedKey == key ? Color.accentColor.opacity(0.18) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        key == todayKey ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .opacity(selectable ? 1 : 0.35)
        .accessibilityLabel(Text(verbatim: dayA11y(key, day: day)))
    }

    private func dayA11y(_ key: String, day: DailyDayRecord?) -> String {
        guard let day else {
            return key + ", " + String(localized: "Not played yet", bundle: .module)
        }
        if let best = day.best {
            return key + ", " + TimeFormat.mmsst(centiseconds: best.centiseconds)
        }
        if let progress = day.bestProgress {
            return key + ", " + StatBlock.percent(progress)
        }
        return key
    }

    // MARK: Selected day

    @ViewBuilder private var dayDetail: some View {
        let day = dailyStore.displayRecords[selectedKey]
        VStack(spacing: 8) {
            HStack {
                Text(verbatim: selectedKey).font(.subheadline.monospacedDigit())
                Spacer()
                if let board = DailyChallenge.board(for: selectedKey) {
                    Text(verbatim: board.config.fullLabel)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                detailStanding(day)
                Spacer()
                if let board = DailyChallenge.board(for: selectedKey), isPlayable(selectedKey) {
                    Button {
                        onPlay(board)
                    } label: {
                        Text(day == nil ? "Play" : "Replay", bundle: .module)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("daily.calendar.play")
                }
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder private func detailStanding(_ day: DailyDayRecord?) -> some View {
        if let best = day?.best {
            HStack(spacing: 8) {
                Text(TimeFormat.mmsst(centiseconds: best.centiseconds))
                    .font(.body.monospaced().bold())
                PaceText(pace: best.pace)
                Text("\(day?.attempts.total ?? 0) attempts", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if let day {
            HStack(spacing: 8) {
                Text(verbatim: StatBlock.percent(day.bestProgress ?? 0))
                    .font(.body.monospaced())
                Text("\(day.attempts.total) attempts", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Not played yet", bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: Dates

    /// The month's cells: leading nils pad to the locale's first weekday.
    private func monthDays() -> [String?] {
        let start = monthStart(of: monthAnchor)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: start)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells = [String?](repeating: nil, count: lead)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: start) {
                cells.append(DailyChallenge.dateKey(for: date, calendar: calendar))
            }
        }
        return cells
    }

    /// Inside [epoch, today] — the only days a board exists for.
    private func isPlayable(_ key: String) -> Bool {
        guard let ordinal = DailyChallenge.dayOrdinal(of: key),
            let today = DailyChallenge.dayOrdinal(of: todayKey)
        else { return false }
        return ordinal >= 0 && ordinal <= today
    }

    private func monthStart(of date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func keyDate(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    #if os(macOS)
    /// Arrows walk the days (clamped to playable), Return plays the selected
    /// day, ⌘←/→ (via chevrons) or arrows across a month edge page it.
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .left: moveSelection(-1)
        case .right: moveSelection(1)
        case .up: moveSelection(-7)
        case .down: moveSelection(7)
        case .enter:
            if let board = DailyChallenge.board(for: selectedKey), isPlayable(selectedKey) {
                onPlay(board)
            }
        default: break
        }
    }

    private func moveSelection(_ delta: Int) {
        guard let ordinal = DailyChallenge.dayOrdinal(of: selectedKey),
            let today = DailyChallenge.dayOrdinal(of: todayKey)
        else { return }
        let next = min(max(ordinal + delta, 0), today)
        guard let key = DailyMerge.dateKey(ordinal: next) else { return }
        selectedKey = key
        if let date = keyDate(key), monthStart(of: date) != monthStart(of: monthAnchor) {
            monthAnchor = date
        }
    }
    #endif
}
