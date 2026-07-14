import DonpaCore
import SwiftUI

/// The Record's anchored scrolling — a sibling-file ScoreboardView extension.
extension ScoreboardView {
    /// A ScrollView that jumps the current config's row into view when opened
    /// in-game (`currentConfigKey` set); opened from the title it stays at the top.
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
            // Expanding a row scrolls it into view — expanding the LAST row
            // otherwise opens content below the fold. A beat later so the taller
            // row has laid out first.
            .onChangeCompat(of: expandedKey) { key in
                guard let key else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(key, anchor: .center)
                    }
                }
            }
            #if os(macOS)
            .onChangeCompat(of: keyRowKey) { key in
                guard let key else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(key, anchor: .center)
                }
            }
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
