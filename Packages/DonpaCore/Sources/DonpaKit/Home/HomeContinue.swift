import DonpaCore
import SwiftUI

/// The Home hub's Continue section — the latest-board card, the "In progress (N)"
/// row, and the full-list sheet. Split from `HomeScreen` (which keeps the layouts
/// and actions) for the type-length cap; not `private` because Swift `private` is
/// file-scoped.
extension HomeScreen {
    // MARK: Continue

    /// The latest in-progress board as the leading card, plus — when there are more —
    /// a row opening the full list as a sheet. A sheet, NOT an inline accordion: with
    /// dozens of saved boards an expansion swallowed the whole Home (the flexible art
    /// shrank to nothing) and scrolled awkwardly; a modal scrolls naturally and never
    /// reflows the menu.
    func continueCard(latest: SaveStore.SaveSummary) -> some View {
        VStack(spacing: 0) {
            Button {
                onContinue(latest.config)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Continue", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.uturn.forward.circle.fill")
                    }
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    savedGameRow(latest)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.continue")

            if snapshots.count > 1 {
                Divider()
                allGamesRow
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentColor.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.accentColor.opacity(0.55), lineWidth: 1.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// The "In progress (N)" row opening the full list sheet. The count is the
    /// sheet's total (the latest is in it too, so the numbers always agree with
    /// what opens).
    var allGamesRow: some View {
        Button {
            showAll = true
        } label: {
            HStack {
                Text("In progress", bundle: .module)
                Text(verbatim: "(\(snapshots.count))")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.inprogress")
    }

    /// The full in-progress list, newest played first — every saved board is a row
    /// that resumes it. Header + explicit frame instead of NavigationStack chrome:
    /// a bare List in a macOS sheet collapses to nothing (the #206 lesson).
    var inProgressSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("In progress", bundle: .module)
                    .font(.headline)
                Spacer()
                Button {
                    showAll = false
                } label: {
                    Text("Close", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            List {
                ForEach(Array(snapshots.enumerated()), id: \.element.config) { index, snapshot in
                    Button {
                        showAll = false
                        onContinue(snapshot.config)
                    } label: {
                        savedGameRow(snapshot)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(keyFocusRing(index))
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 460, minHeight: 340, idealHeight: 520)
        // Arrows move the row focus, Return resumes it, Esc closes.
        .background(KeyCatcher(onKey: handleKey))
        #endif
    }

    /// The keyboard-focus ring for a row (macOS arrows); a no-op elsewhere.
    private func keyFocusRing(_ index: Int) -> FocusRing {
        #if os(macOS)
        return FocusRing(focused: keyRowIndex == index, inset: 2)
        #else
        return FocusRing(focused: false, inset: 0)
        #endif
    }

    #if os(macOS)
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .down: moveRowFocus(1)
        case .up: moveRowFocus(-1)
        case .enter:
            guard let index = keyRowIndex, snapshots.indices.contains(index) else { return }
            showAll = false
            onContinue(snapshots[index].config)
        case .escape:
            showAll = false
        case .left, .right, .family, .character:
            break
        }
    }

    private func moveRowFocus(_ delta: Int) {
        guard !snapshots.isEmpty else { return }
        guard let current = keyRowIndex else {
            keyRowIndex = 0
            return
        }
        keyRowIndex = min(max(current + delta, 0), snapshots.count - 1)
    }
    #endif

    /// One in-progress board: glyph, family + config (with cleared %), and — trailing —
    /// the elapsed clock over a relative "last played" age.
    func savedGameRow(_ snapshot: SaveStore.SaveSummary) -> some View {
        HStack(spacing: 12) {
            BoardGlyph(kind: .family(snapshot.config.family), size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: snapshot.config.family.label)
                    .font(.headline)
                Text(verbatim: "\(snapshot.config.label) · \(snapshot.progressPercent)%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: Self.clock(snapshot.elapsedCentiseconds))
                    .font(.subheadline.monospacedDigit())
                Text(snapshot.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
