import DonpaCore
import SwiftUI

/// The receive prompt for a share opened via a donpa.app link or scanned QR. One
/// view over `Navigator.incomingShare`, branching on its already-decoded case:
/// a confirm sheet for a genuine add/refresh, a resolution sheet for a name
/// collision (keep both / replace / cancel), or a loud alert for a share that
/// failed to verify. Verification happened before we got here — this view never
/// checks signatures, it just renders the decision.
struct ReceiveShareView: View {
    let incoming: IncomingShare
    @ObservedObject var friends: FriendsStore
    let onDone: () -> Void
    /// Called INSTEAD of `onDone` when a rival was actually added/updated — the host
    /// opens the Mess hall so the new rival is never invisible. Cancels stay `onDone`.
    var onAdded: (() -> Void)?

    var body: some View {
        switch incoming {
        case .accepted(let payload, let outcome):
            ConfirmAddView(
                payload: payload, outcome: outcome, friends: friends, onDone: onDone,
                onAdded: onAdded)
        case .collision(let payload, let existingKey):
            ResolveCollisionView(
                payload: payload, existingKey: existingKey, friends: friends, onDone: onDone,
                onAdded: onAdded)
        case .failed:
            // A failed share is shown as an alert by the presenter, never as a sheet.
            EmptyView()
        }
    }
}

// MARK: - Confirm a genuine add / refresh

/// TOFU made explicit: show who you're about to trust and a preview of their scores,
/// then Add / Cancel. A refresh (same friend, newer share) reads as "Update" since
/// they're already pinned.
private struct ConfirmAddView: View {
    let payload: SharePayload
    let outcome: FriendMerge.Outcome
    @ObservedObject var friends: FriendsStore
    let onDone: () -> Void
    var onAdded: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    /// Optional local nickname, offered only for a genuine new add — a refresh
    /// mustn't clobber an alias you set earlier with a blank field here.
    @State private var alias = ""
    /// Groups to put the friend in, staged until confirm (they aren't stored yet).
    @State private var groupSelection: Set<String> = []
    /// A typed-but-not-created new squad name; confirm commits it (see GroupPicker).
    @State private var pendingGroupName = ""

    private var isRefresh: Bool {
        if case .add = outcome { return false }
        return true  // refresh or migrate — already a known friend
    }

    var body: some View {
        SharePromptChrome(
            title: isRefresh ? "Update scores?" : "Add rival?",
            confirmTitle: isRefresh ? "Update" : "Add",
            onConfirm: confirm,
            onCancel: finish
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(payload.body.name).font(.title3.bold())
                SharePreview(payload: payload)
                if isRefresh {
                    Text(
                        "You already track this rival — this refreshes their scores.",
                        bundle: .module
                    )
                    .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your name for them (optional)", bundle: .module)
                            .font(.caption).foregroundStyle(.secondary)
                        TextField(text: $alias) {
                            Text("e.g. \(payload.body.name)", bundle: .module)
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Squads (optional)", bundle: .module)
                            .font(.caption).foregroundStyle(.secondary)
                        GroupPicker(
                            friends: friends, selection: $groupSelection,
                            pendingName: $pendingGroupName)
                    }
                }
            }
        }
    }

    private func confirm() {
        friends.apply(payload)
        if !isRefresh {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { friends.setAlias(trimmed, for: payload.publicKey) }
            // A squad name typed but never committed with Create still counts —
            // discarding it silently was how squads "didn't appear".
            var selection = groupSelection
            if let pending = friends.createGroup(named: pendingGroupName) {
                selection.insert(pending.id)
            }
            if !selection.isEmpty {
                friends.setGroups(Array(selection), for: payload.publicKey)
            }
        }
        dismiss()
        (onAdded ?? onDone)()
    }

    private func finish() {
        dismiss()
        onDone()
    }
}

// MARK: - Resolve a name collision

/// Same display name, different key: could be a second real friend or a spoof. Never
/// silently overwrite — offer keep-both (with an optional alias), replace, or cancel.
private struct ResolveCollisionView: View {
    let payload: SharePayload
    let existingKey: Data
    @ObservedObject var friends: FriendsStore
    let onDone: () -> Void
    var onAdded: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var alias = ""

    var body: some View {
        SharePromptChrome(
            title: "Name already taken",
            confirmTitle: "Keep both",
            onConfirm: {
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                friends.addResolvingCollision(payload, alias: trimmed.isEmpty ? nil : trimmed)
                finish(added: true)
            },
            onCancel: { finish(added: false) },
            extraButton: AnyView(
                Button(role: .destructive) {
                    friends.replaceOnCollision(payload, replacing: existingKey)
                    finish(added: true)
                } label: {
                    Text("Replace existing", bundle: .module)
                })
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    "A different person is using the name \u{201C}\(payload.body.name)\u{201D} (new code).",
                    bundle: .module
                )
                .font(.callout).foregroundStyle(.secondary)
                SharePreview(payload: payload)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Give them a different name (optional)", bundle: .module)
                        .font(.caption).foregroundStyle(.secondary)
                    TextField(text: $alias) {
                        Text("e.g. \(payload.body.name) (work)", bundle: .module)
                    }
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func finish(added: Bool) {
        dismiss()
        (added ? (onAdded ?? onDone) : onDone)()
    }
}

// MARK: - Shared pieces

/// A compact read-only preview of what's in the share: how many configs have scores,
/// total wins, and whether career stats are included. Enough to recognise a friend
/// before pinning, without a full comparison (that's the scoreboard's job later).
private struct SharePreview: View {
    let payload: SharePayload

    private var configsWithScores: Int { payload.body.scores.filter { $0.wins > 0 }.count }
    private var totalWins: Int { payload.body.scores.reduce(0) { $0 + $1.wins } }

    var body: some View {
        HStack(spacing: 16) {
            stat("\(configsWithScores)", "boards")
            stat("\(totalWins)", "wins")
            if payload.body.career != nil {
                stat("✓", "career")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func stat(_ value: String, _ labelKey: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline)
            Text(labelKey, bundle: .module).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Shared chrome for the receive prompts: a titled sheet with a confirm + cancel
/// pair and an optional extra (destructive) action, cross-platform. Keeps the two
/// prompt bodies to just their content.
private struct SharePromptChrome<Content: View>: View {
    let title: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let onConfirm: () -> Void
    let onCancel: () -> Void
    var extraButton: AnyView?
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey, confirmTitle: LocalizedStringKey,
        onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void,
        extraButton: AnyView? = nil, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.extraButton = extraButton
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title, bundle: .module).font(.title2.bold())
            content
            buttons
        }
        .padding(24)
        .frame(minWidth: 300, maxWidth: 420)
    }

    @ViewBuilder private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: onConfirm) {
                Text(confirmTitle, bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            if let extraButton {
                extraButton.frame(maxWidth: .infinity)
            }

            Button(role: .cancel, action: onCancel) {
                Text("Cancel", bundle: .module).frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.bordered)
    }
}

extension ShareCodec.DecodeError {
    /// A short, honest reason for the loud rejection alert. We don't leak internals —
    /// just enough for the user to know it's not their fault and what to do.
    var receiveMessage: LocalizedStringKey {
        switch self {
        case .badSignature:
            return "The signature didn't match. Ask them to share again."
        case .unsupportedVersion:
            return "This share needs a newer version of Donpa. Update the app."
        case .tooLarge, .malformed, .notDonpaShare:
            return "That link or code isn't a valid Donpa share."
        }
    }
}
