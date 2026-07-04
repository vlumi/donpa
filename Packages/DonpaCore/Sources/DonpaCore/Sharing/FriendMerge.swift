import Foundation

/// The trust-on-first-use decision for an incoming, ALREADY-SIGNATURE-VERIFIED
/// share (run `ShareCodec.decode` first — it proves authenticity; this decides what
/// to DO with an authentic share given who you already track). Pure, so the whole
/// TOFU/collision/rotation matrix is unit-testable without any UI or store.
public enum FriendMerge {
    /// What the receive flow should do with a verified payload.
    public enum Outcome: Equatable {
        /// A new identity, and its name is free → pin it (add a friend).
        case add
        /// Known identity (pinned before), and this share is newer → refresh in place.
        case refresh
        /// Known identity, but this share is the same-or-older than what's pinned →
        /// ignore (replay/downgrade guard).
        case stale
        /// A NEW identity, but it carries a rotation endorsement from an OLD identity
        /// you already track → migrate the existing friend's pin to the new key,
        /// silently (no prompt). Carries the old key so the store can re-key.
        case migrate(fromPublicKey: Data)
        /// A new identity whose display NAME collides with a DIFFERENT tracked
        /// friend → ask the human (replace / keep-both / rename). Never silent.
        case nameCollision(withPublicKey: Data)
    }

    /// Decide the outcome. `existing` is the current friends list; `payload` is a
    /// verified `SharePayload`. `now` is passed in (Core stays clock-injectable).
    public static func outcome(for payload: SharePayload, existing: [Friend]) -> Outcome {
        let key = payload.publicKey

        // 1. Already tracking this exact identity → newest-wins refresh vs. stale.
        if let known = existing.first(where: { $0.publicKey == key }) {
            return payload.body.issuedAt > known.lastIssuedAt ? .refresh : .stale
        }

        // 2. New identity, but a rotation endorsement vouches for it from an OLD key
        //    we already track (and the endorsement verifies) → silent migrate.
        if let rot = payload.body.rotation,
            existing.contains(where: { $0.publicKey == rot.oldPublicKey }),
            ShareIdentity.verifyRotation(rot, newPublicKey: key)
        {
            return .migrate(fromPublicKey: rot.oldPublicKey)
        }

        // 3. New identity whose NAME matches a different tracked friend → prompt.
        if let clash = existing.first(where: { $0.name == payload.body.name }) {
            return .nameCollision(withPublicKey: clash.publicKey)
        }

        // 4. Otherwise a clean new friend.
        return .add
    }

    /// Build the `Friend` record to store for an accepted `add`/`refresh`/`migrate`.
    /// `migrate` reuses the existing friend's groups/addedAt but adopts the new key.
    public static func friend(
        from payload: SharePayload, existing: Friend?, now: Date
    ) -> Friend {
        Friend(
            publicKey: payload.publicKey,
            name: payload.body.name,
            groups: existing?.groups ?? [],
            lastIssuedAt: payload.body.issuedAt,
            scores: payload.body.scores,
            career: payload.body.career,
            addedAt: existing?.addedAt ?? now)
    }
}
