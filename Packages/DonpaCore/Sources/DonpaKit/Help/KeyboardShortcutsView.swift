import SwiftUI

/// The keyboard reference (⌘/): every shortcut grouped by where it works —
/// the discoverability layer over the keyboard vocabulary. The ⌘-commands are
/// also visible in the macOS menus / the iPadOS hold-⌘ HUD; this sheet is the
/// one place the UNMODIFIED keys (arrows, Return, F, E, P…) are written down.
public struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts", bundle: .module).font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section(
                        Text("On the board", bundle: .module),
                        rows: [
                            ("↑ ↓ ← →", Text("Move the cursor", bundle: .module)),
                            ("⏎", Text("Dig — or chord a revealed number", bundle: .module)),
                            ("F", Text("Plant or clear a flag", bundle: .module)),
                            ("Space", Text("Switch dig/flag mode", bundle: .module)),
                            ("Esc", Text("Pause and resume", bundle: .module)),
                        ])
                    section(
                        Text("In lists and pickers", bundle: .module),
                        rows: [
                            ("↑ ↓ ← →", Text("Move the selection", bundle: .module)),
                            ("⏎", Text("Open, expand, or start", bundle: .module)),
                            ("E", Text("Edit the selection · flip Flat/Round", bundle: .module)),
                            ("P", Text("Play the selected board", bundle: .module)),
                            ("⌘1–⌘4", Text("Pick the family or tab", bundle: .module)),
                            ("Esc", Text("Close the screen", bundle: .module)),
                        ])
                    section(
                        Text("Anywhere", bundle: .module),
                        rows: [
                            ("⌘N", Text("New game", bundle: .module)),
                            ("⌘R", Text("Restart the board", bundle: .module)),
                            ("⌘B", Text("Barracks (home)", bundle: .module)),
                            ("⇧⌘M", Text("Mess hall", bundle: .module)),
                            ("⇧⌘S", Text("Service Record", bundle: .module)),
                            ("⌘F", Text("Switch dig/flag mode", bundle: .module)),
                            ("⌘0", Text("Toggle minimap size", bundle: .module)),
                            ("⌘+ ⌘−", Text("Zoom the board", bundle: .module)),
                            ("⌘/", Text("This reference", bundle: .module)),
                        ])
                }
                .padding(20)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
        }
        .escDismisses { dismiss() }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 440, minHeight: 420, idealHeight: 620)
        #endif
    }

    private func section(_ title: Text, rows: [(String, Text)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title.font(.subheadline.weight(.semibold))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: row.0)
                        .font(.callout.monospaced().weight(.medium))
                        .frame(width: 90, alignment: .trailing)
                    row.1.font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
