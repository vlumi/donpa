import Foundation

/// The trust-on-first-use decision for an incoming share that MUST already be
/// signature-verified (run `ShareCodec.decode` first); this only decides what to do
/// with an authentic share. Pure, so the TOFU/collision/rotation matrix is
/// unit-testable without UI or store.
public enum FriendMerge {
    /// What the receive flow should do with a verified payload.
    public enum Outcome: Equatable {
        /// New identity, name free → pin it.
        case add
        /// Known identity, newer share → refresh in place.
        case refresh
        /// Known identity, same-or-older share → ignore (replay/downgrade guard).
        case stale
        /// New identity carrying a verified rotation endorsement from an old identity
        /// you track → silently re-key the existing friend to the new key.
        case migrate(fromPublicKey: Data)
        /// New identity whose display name collides with a different tracked friend →
        /// ask the human (replace / keep-both / rename); never silent.
        case nameCollision(withPublicKey: Data)
    }

    public static func outcome(for payload: SharePayload, existing: [Friend]) -> Outcome {
        let key = payload.publicKey

        if let known = existing.first(where: { $0.publicKey == key }) {
            return payload.body.issuedAt > known.lastIssuedAt ? .refresh : .stale
        }

        if let rot = payload.body.rotation,
            existing.contains(where: { $0.publicKey == rot.oldPublicKey }),
            ShareIdentity.verifyRotation(rot, newPublicKey: key)
        {
            return .migrate(fromPublicKey: rot.oldPublicKey)
        }

        // Collision is on what you SEE (alias if set, else shared name) — a stranger
        // reusing a familiar name is worth a prompt.
        if let clash = existing.first(where: { $0.displayName == payload.body.name }) {
            return .nameCollision(withPublicKey: clash.publicKey)
        }

        return .add
    }

    /// Builds the record to store for an accepted add/refresh/migrate. Local-only
    /// fields (`localAlias`, `groups`) and `addedAt` are preserved from `existing`;
    /// `sharedName` always tracks the latest share.
    public static func friend(
        from payload: SharePayload, existing: Friend?, now: Date
    ) -> Friend {
        Friend(
            publicKey: payload.publicKey,
            sharedName: payload.body.name,
            localAlias: existing?.localAlias,
            groups: existing?.groups ?? [],
            lastIssuedAt: payload.body.issuedAt,
            scores: payload.body.scores,
            career: payload.body.career,
            addedAt: existing?.addedAt ?? now)
    }
}
