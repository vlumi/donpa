import DonpaCore
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Compact iCloud-sync control for the stats sheet footer: a toggle plus inline
/// status. Opt-in; the toggle refuses to turn on while iCloud is unavailable
/// (signed out), and the status then tells the player to sign in.
struct SyncFooterControl: View {
    @ObservedObject var settings: Settings
    @ObservedObject var scoreboard: Scoreboard
    var keyFocused: Bool = false
    /// Fired by the host to flip the toggle from the keyboard — routed through
    /// `syncBinding`, so the enable path keeps its wipe-confirm and
    /// iCloud-availability guards.
    var activate = Pulse()

    /// Confirming enable after a global wipe happened while sync was off —
    /// enabling honors the tombstone and clears this device too.
    @State private var confirmingEnable = false

    /// The guarded enable path — never bypass it: ON requires iCloud reachable,
    /// and confirms first when it would wipe local scores. OFF always works.
    private var syncBinding: Binding<Bool> {
        Binding(
            get: { settings.syncScores },
            set: { newValue in
                guard newValue else {
                    settings.syncScores = false
                    return
                }
                guard scoreboard.isCloudAvailable else { return }
                if scoreboard.enablingSyncWouldWipeLocal {
                    confirmingEnable = true  // the toggle stays off until confirmed
                } else {
                    settings.syncScores = true
                }
            })
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: syncBinding) {
                Text("Sync", bundle: .module).font(.subheadline.weight(.medium))
            }
            .toggleStyle(.switch)
            #if os(iOS)
            .controlSize(.mini)
            #endif
            .fixedSize()
            .confirmationDialog(
                Text("Turn on sync?", bundle: .module), isPresented: $confirmingEnable
            ) {
                Button(role: .destructive) {
                    settings.syncScores = true
                } label: {
                    Text("Sync and reset this device", bundle: .module)
                }
            } message: {
                wipeWarningMessage
            }

            if settings.syncScores, scoreboard.isCloudActive {
                Label {
                    Text("via iCloud", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark.icloud")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if !scoreboard.isCloudAvailable {
                signInPrompt
            } else {
                Text("This device only", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .keyFocusRing(keyFocused)
        .onPulse(activate) { syncBinding.wrappedValue = !settings.syncScores }
    }

    /// Extracted so the long localized key fits the line cap.
    private var wipeWarningMessage: Text {
        Text(
            "Scores were erased everywhere while sync was off. Turning sync on will reset this device too.",
            bundle: .module)
    }

    /// macOS deep-links to the Apple-ID pane; iOS has no public URL to iCloud
    /// sign-in (the only one opens THIS app's settings), so it gets guidance
    /// text, not a misleading button.
    @ViewBuilder private var signInPrompt: some View {
        #if os(macOS)
        Button {
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane")
            {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Text("Sign into iCloud", bundle: .module).font(.caption.bold())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        #else
        Text("Sign into iCloud in Settings to sync.", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
        #endif
    }
}
