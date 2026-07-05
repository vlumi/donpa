import DonpaCore
import SwiftUI

/// The title's "pick up where you left off" sheet: every in-progress board, newest
/// played first, each a tappable row that resumes it — plus a New Game row at the
/// bottom for starting fresh. Shown from the title art when at least one save exists;
/// with none, the art opens New Game directly (this sheet never appears empty).
///
/// The New Game modal's Continue button + drill-down dots cover resuming a *specific*
/// selection; this list is the flat, chronological view — "what do I have going?".
struct ResumeListView: View {
    /// In-progress boards, already sorted newest-played first by the caller.
    let snapshots: [GameSnapshot]
    /// Resume a saved board.
    let onResume: (GameConfig) -> Void
    /// Start fresh — opens the New Game modal.
    let onNewGame: () -> Void
    /// Dismiss without choosing.
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(snapshots, id: \.config) { snapshot in
                        Button {
                            onResume(snapshot.config)
                        } label: {
                            ResumeRow(snapshot: snapshot)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("In progress", bundle: .module)
                }

                Section {
                    Button(action: onNewGame) {
                        Label {
                            Text("New game…", bundle: .module)
                        } icon: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("resume.newGame")
                }
            }
            .navigationTitle(Text("Continue", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onClose()
                    } label: {
                        Text("Close", bundle: .module)
                    }
                }
            }
        }
    }
}

/// One in-progress board: its glyph, the config name (family · size · density ·
/// edges), and — trailing — the elapsed clock over a relative "last played" line.
private struct ResumeRow: View {
    let snapshot: GameSnapshot

    var body: some View {
        HStack(spacing: 12) {
            BoardGlyph(kind: .family(snapshot.config.family), size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: snapshot.config.family.label)
                    .font(.headline)
                Text(verbatim: snapshot.config.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: Self.clock(snapshot.elapsedCentiseconds))
                    .font(.subheadline.monospacedDigit())
                Self.lastPlayed(snapshot.updatedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// `m:ss` elapsed, matching the in-game timer's larger form.
    static func clock(_ centiseconds: Int) -> String {
        let seconds = max(0, centiseconds / 100)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// A localized relative age ("2 hours ago", "yesterday") for when it was last
    /// touched. `.distantPast` (a pre-`updatedAt` save) reads as very old, which is
    /// honest — it hasn't been played this era.
    static func lastPlayed(_ date: Date) -> Text {
        Text(date, format: .relative(presentation: .named))
    }
}
