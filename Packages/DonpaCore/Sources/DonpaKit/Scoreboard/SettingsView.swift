import DonpaCore
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// App settings: appearance, toggle side, language.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var scoreboard: Scoreboard
    @Environment(\.dismiss) private var dismiss
    /// The reset-scores confirmation (moved here from the scoreboard — rare +
    /// destructive belongs in Settings, not a prominent toolbar button).
    @State private var confirmingReset = false
    /// The language in effect when this sheet appeared. Moving away from it needs a
    /// restart to switch, surfaced via `restartNotice`.
    @State private var launchLanguage: LanguagePreference?

    private var languageChanged: Bool {
        launchLanguage != nil && settings.language != launchLanguage
    }

    /// Measured content height, to size the iOS sheet to a compact card.
    @State private var contentHeight: CGFloat = 0
    #if os(macOS)
    /// The keyboard-focused settings row (Tab/arrow navigation); nil until the
    /// first press. ←/→ or Return operate the focused control.
    @State private var keyRow: SettingsKeyRow?
    #endif

    /// The keyboard-walkable rows, in visual order (haptics is iOS-only).
    enum SettingsKeyRow: CaseIterable {
        case appearance, toggleSide, questionMarks, sound, language, reset
    }

    var body: some View {
        sheetChrome
            .escDismisses { dismiss() }
            .onAppear { launchLanguage = settings.language }
            .animation(.easeInOut(duration: 0.2), value: languageChanged)
            .confirmationDialog(
                scoreboard.isCloudActive
                    ? Text("Erase scores on all your devices?", bundle: .module)
                    : Text("Clear all high scores?", bundle: .module),
                isPresented: $confirmingReset,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    scoreboard.wipeAllSynced()
                } label: {
                    scoreboard.isCloudActive
                        ? Text("Erase everywhere", bundle: .module)
                        : Text("Clear scores", bundle: .module)
                }
                Button(role: .cancel) {
                } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: {
                if scoreboard.isCloudActive {
                    Text(
                        """
                        This erases your high scores and career stats on every device \
                        signed in to your iCloud. Boards unlocked through play lock \
                        again. It can't be undone.
                        """, bundle: .module)
                } else {
                    Text(
                        """
                        This clears your high scores and career stats on this device. \
                        Boards unlocked through play lock again.
                        """, bundle: .module)
                }
            }
    }

    private var settingsList: some View {
        VStack(alignment: .leading, spacing: 20) {
            // The Picker labels are visually hidden but still read by VoiceOver —
            // as Text(bundle: .module) so they resolve in this package's catalog
            // (a bare string key would look in the app bundle: unlocalized).
            settingRow("Appearance", key: .appearance) {
                Picker(selection: $settings.appearance) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(verbatim: pref.label).tag(pref)  // label localized in Settings
                    }
                } label: {
                    Text("Appearance", bundle: .module)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            settingRow("Toggle side", key: .toggleSide) {
                Picker(selection: $settings.handedness) {
                    ForEach(Handedness.allCases) { hand in
                        Text(verbatim: hand.label).tag(hand)
                    }
                } label: {
                    Text("Toggle side", bundle: .module)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            settingRow("Question marks", key: .questionMarks) {
                Toggle(isOn: $settings.questionMarks) {
                    Text("Cycle through a ? mark", bundle: .module)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(
                    "Adds a ? step after the flag — flag, then ?, then clear — for marking a maybe.",
                    bundle: .module
                )
                .font(.caption).foregroundStyle(.secondary)
            }

            settingRow("Sound", key: .sound) {
                Toggle(isOn: $settings.sound) {
                    Text("Play sound effects", bundle: .module)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(
                    "Flag, chord, dig, and the result sting. On iPhone the Ring/Silent switch mutes it too.",
                    bundle: .module
                )
                .font(.caption).foregroundStyle(.secondary)
            }

            #if os(iOS)
            settingRow("Haptics") {
                Toggle(isOn: $settings.haptics) {
                    Text("Vibrate on taps", bundle: .module)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(
                    "A gentle tap for flags, chords, and digs.",
                    bundle: .module
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            #endif

            settingRow("Language", key: .language) {
                Picker(selection: $settings.language) {
                    ForEach(LanguagePreference.allCases) { lang in
                        Text(verbatim: lang.label).tag(lang)
                    }
                } label: {
                    Text("Language", bundle: .module)
                }
                .labelsHidden()
                if languageChanged {
                    restartNotice
                }
            }

            // Score sync lives in the scoreboard; About on the title screen.

            Divider()
            resetRow.modifier(rowRing(.reset))
        }
    }

    /// Reset scores — destructive, so it lives quietly at the bottom of Settings with
    /// a confirmation. Wording + scope follow the sync state (global wipe when synced).
    private var resetRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(role: .destructive) {
                confirmingReset = true
            } label: {
                Text("Reset scores", bundle: .module)
            }
            Text(
                scoreboard.isCloudActive
                    ? "Erases your scores and stats on all your devices."
                    : "Clears your scores and stats on this device.",
                bundle: .module
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// iOS: NavigationStack with a "Done" toolbar item + fit-content detent. macOS:
    /// inline title + bottom Done button.
    @ViewBuilder private var sheetChrome: some View {
        #if os(iOS)
        NavigationStack {
            // Scrolls when the rows outgrow the detent (large accessibility
            // text) — the fit-content detent is measured from the UNSCROLLED
            // content, so nothing changes when everything fits; Done stays a
            // pinned toolbar item either way.
            ScrollView {
                settingsList
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(heightReader)
            }
            .navigationTitle(Text("Settings", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                    .accessibilityIdentifier("sheet.done")
                }
            }
        }
        // +64 leaves room for the nav bar + grabber.
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight + 64)] : [.medium])
        #else
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings", bundle: .module).font(.title2.bold())
            // Scroll fallback for short windows / large text; ViewThatFits so
            // the sheet still hugs its natural height when the rows fit. The
            // title and Done row stay pinned outside the scroller.
            ViewThatFits(in: .vertical) {
                settingsList
                ScrollView { settingsList }
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
        }
        .padding(24)
        .frame(minWidth: 320)
        // Tab/arrows move between rows; ←/→ or Return operate the focused
        // control; Esc closes. (Done keeps Return only until a row is focused.)
        .background(KeyCatcher(onKey: handleKey))
        #endif
    }

    #if os(macOS)
    private func handleKey(_ key: KeyCatcher.Key) {
        switch key {
        case .down, .tab: moveRowFocus(1)
        case .up, .backTab: moveRowFocus(-1)
        case .left: operateFocusedRow(step: -1)
        case .right: operateFocusedRow(step: 1)
        case .enter: operateFocusedRow(step: 1)
        case .escape: dismiss()
        case .family, .character: break
        }
    }

    private func moveRowFocus(_ delta: Int) {
        let rows = SettingsKeyRow.allCases
        guard let current = keyRow, let i = rows.firstIndex(of: current) else {
            keyRow = rows.first
            return
        }
        keyRow = rows[min(max(i + delta, 0), rows.count - 1)]
    }

    /// Operate the focused row: pickers cycle by `step`, toggles flip, Reset
    /// asks for its confirmation (never resets directly).
    private func operateFocusedRow(step: Int) {
        switch keyRow {
        case .appearance: settings.appearance = cycled(settings.appearance, by: step)
        case .toggleSide: settings.handedness = cycled(settings.handedness, by: step)
        case .questionMarks: settings.questionMarks.toggle()
        case .sound: settings.sound.toggle()
        case .language: settings.language = cycled(settings.language, by: step)
        case .reset: confirmingReset = true
        case nil: break
        }
    }

    /// The next case in a CaseIterable, clamped at the ends (no wrap — matches
    /// how the segmented controls read).
    private func cycled<T: CaseIterable & Equatable>(_ value: T, by step: Int) -> T {
        let all = Array(T.allCases)
        guard let i = all.firstIndex(of: value) else { return value }
        return all[min(max(i + step, 0), all.count - 1)]
    }
    #endif

    /// A headline over its control(s), carrying the keyboard-focus ring when
    /// its row is the arrow-focused one.
    private func settingRow<Content: View>(
        _ title: LocalizedStringKey, key: SettingsKeyRow? = nil,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title, bundle: .module).font(.headline)
            content()
        }
        .modifier(rowRing(key))
    }

    private func rowRing(_ key: SettingsKeyRow?) -> FocusRing {
        #if os(macOS)
        return FocusRing(focused: key != nil && keyRow == key, inset: 4)
        #else
        return FocusRing(focused: false, inset: 0)
        #endif
    }

    /// Reports the content's natural height (for the iOS fit-content detent).
    private var heightReader: some View {
        GeometryReader { geo in
            Color.clear.onAppear { contentHeight = geo.size.height }
                .onChangeCompat(of: geo.size.height) { contentHeight = $0 }
        }
    }

    /// Tinted callout shown once the language picker changes: restart to switch.
    private var restartNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Restart the app to change the language.", bundle: .module)
                .font(.callout.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange.opacity(0.5), lineWidth: 1))
        .transition(.opacity)
    }
}
