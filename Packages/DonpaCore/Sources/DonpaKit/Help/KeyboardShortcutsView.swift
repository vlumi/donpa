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
            Text("Keyboard Shortcuts", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            Divider()
            ScrollViewReader { proxy in
                scrollBody(proxy)
            }
            Divider()
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .escDismisses { dismiss() }
        #if os(macOS)
        .frame(
            minWidth: 380, idealWidth: 440, maxWidth: 560,
            minHeight: 420, idealHeight: 715, maxHeight: 815)
        #endif
    }

    @ViewBuilder private func scrollBody(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                boardSection
                listsSection
                anywhereSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        #if os(macOS)
        // Arrows/Tab step section by section (no keyboard scrolling on a bare
        // SwiftUI ScrollView without system Full Keyboard Access).
        .background(
            KeyCatcher { key in
                switch key {
                case .down, .tab: stepSection(1, proxy: proxy)
                case .up, .backTab: stepSection(-1, proxy: proxy)
                case .enter, .escape: dismiss()
                default: break
                }
            }
        )
        #endif
    }

    #if os(macOS)
    @State private var keySection: Int?

    private func stepSection(_ delta: Int, proxy: ScrollViewProxy) {
        let next = min(max((keySection ?? -1) + delta, 0), 2)
        keySection = next
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("section-\(next)", anchor: .top)
        }
    }
    #endif

    private var boardSection: some View {
        section(
            Text("On the board", bundle: .module),
            rows: [
                ("↑ ↓ ← →", Text("Move the cursor", bundle: .module)),
                ("⏎", Text("Dig — or chord a revealed number", bundle: .module)),
                ("F", Text("Plant or clear a flag", bundle: .module)),
                ("Space", Text("Switch dig/flag mode", bundle: .module)),
                ("Esc", Text("Pause and resume", bundle: .module)),
            ]
        )
        .id("section-0")
    }

    private var listsSection: some View {
        section(
            Text("In lists and pickers", bundle: .module),
            rows: [
                ("↑ ↓ ← →", Text("Move the selection", bundle: .module)),
                ("⏎", Text("Press the focused button, or Done", bundle: .module)),
                ("Space", Text("Toggle the focused control", bundle: .module)),
                ("Tab", Text("Next control group", bundle: .module)),
                ("E", Text("Edit the selection · flip Flat/Round", bundle: .module)),
                ("P", Text("Play the selected board", bundle: .module)),
                ("⌘1–⌘4", Text("Pick the family or tab", bundle: .module)),
                ("Esc", Text("Close the screen", bundle: .module)),
            ]
        )
        .id("section-1")
    }

    private var anywhereSection: some View {
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
            ]
        )
        .id("section-2")
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
