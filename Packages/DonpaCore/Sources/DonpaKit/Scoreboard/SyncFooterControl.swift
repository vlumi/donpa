import DonpaCore
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Compact iCloud-sync control for the stats sheet footer: a toggle plus inline
/// status. Opt-in (off by default). The toggle refuses to turn on while iCloud is
/// unavailable (signed out) — there'd be nothing to sync with — and the status then
/// tells the player to sign in. KVS has no in-app permission prompt to surface.
struct SyncFooterControl: View {
    @ObservedObject var settings: Settings
    @ObservedObject var scoreboard: Scoreboard
    /// The host's Tab-focus ring (keyboard zone cycling).
    var keyFocused: Bool = false
    /// Fired by the host to flip the toggle from the keyboard — routed through
    /// `syncBinding`, so the enable path keeps its wipe-confirm and
    /// iCloud-availability guards.
    var activate = Pulse()

    /// Asking the player to confirm enabling sync when a global wipe happened while
    /// sync was off — enabling would honor the tombstone and clear this device too.
    @State private var confirmingEnable = false

    /// Turning sync ON only sticks when iCloud is actually reachable; otherwise the
    /// switch snaps back off (the status row explains why). If a wipe happened while
    /// sync was off, enabling clears this device's local scores — confirm first.
    /// Turning OFF always works.
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
            .controlSize(.mini)  // a quieter switch; the footer bar shouldn't shout
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

    /// The enable-after-wipe warning, extracted so the long localized key fits the
    /// line cap.
    private var wipeWarningMessage: Text {
        Text(
            "Scores were erased everywhere while sync was off. Turning sync on will reset this device too.",
            bundle: .module)
    }

    /// How the player gets iCloud signed in. macOS can deep-link straight to the
    /// Apple-ID pane; iOS can't (the only public URL opens THIS app's settings, not
    /// iCloud sign-in), so there it's plain guidance text, not a misleading button.
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
        // iOS has no public deep link to iCloud sign-in (the only settings URL
        // opens THIS app's pane), so point the way in words instead of a dead button.
        Text("Sign into iCloud in Settings to sync.", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
        #endif
    }
}
