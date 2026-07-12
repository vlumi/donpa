import DonpaCore
import SwiftUI

/// The Record's anchored scrolling (current-config jump, expansion and
/// keyboard-focus following) — a sibling-file ScoreboardView extension.
extension ScoreboardView {
    /// A ScrollView that, when opened in-game (`currentConfigKey` set), jumps the
    /// current config's row into view — so you land on the board you're playing.
    /// Opened from the title (key nil) it stays at the top for plain browsing.
    @ViewBuilder func anchoredScroll<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        let inner = content()
        ScrollViewReader { proxy in
            ScrollView {
                inner
            }
            .onAppear {
                guard let key = currentConfigKey else { return }
                // A beat after layout so the target row exists before we scroll.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(key, anchor: .center)
                    }
                }
            }
            // Expanding a row scrolls it into view — otherwise expanding the LAST
            // row opens content that's off-screen below the fold (and there may be
            // no layout shift to nudge it up). A beat later so the taller row has
            // laid out before we scroll to it.
            .onChangeCompat(of: expandedKey) { key in
                guard let key else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(key, anchor: .center)
                    }
                }
            }
            #if os(macOS)
            // The keyboard focus scrolls with the arrows, like the expansion.
            .onChangeCompat(of: keyRowKey) { key in
                guard let key else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(key, anchor: .center)
                }
            }
            // Tab brings the focused zone into view — career and the medals
            // live above the fold once the scores are long.
            .onChangeCompat(of: keys.zone) { zone in
                let anchor: String? =
                    switch zone {
                    case .career: "zone.career"
                    case .breakdown: "zone.breakdown"
                    case .medals: "zone.medals"
                    case .family, .edges: "zone.filters"
                    case .rivals, .manage: "zone.rivals"
                    case .rows, .sync, nil: nil  // rows self-scroll; sync is pinned
                    }
                guard let anchor else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
            #endif
        }
    }
}
