import SwiftUI

/// App "About": name, version, and credits — one view shared by the title
/// screen's "i" button and the macOS app menu.
public struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Open the how-to-play reference (the host swaps sheets); nil hides the row.
    var onHowTo: (() -> Void)?

    /// Measured content height, for the iOS fit-content detent.

    public init(onHowTo: (() -> Void)? = nil) {
        self.onHowTo = onHowTo
    }

    private var palette: Palette { Palette.resolved(for: colorScheme) }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    /// The build's git commit (`GitCommitSHA`, injected at build time); absent
    /// on older builds — hidden when missing.
    private var commitSHA: String? {
        Bundle.main.infoDictionary?["GitCommitSHA"] as? String
    }

    /// Whether the UI is in Japanese. The app/author names are the same entities in
    /// two scripts (not translated text), so they pick their form from this rather
    /// than the string catalog.
    private var isJapanese: Bool {
        Bundle.module.preferredLocalizations.first?.hasPrefix("ja") ?? false
    }

    private var appName: String { isJapanese ? "ドンパ隊" : "Donpa Squad" }
    private var authorName: String { isJapanese ? "三﨑ヴィッレ" : "Ville Misaki" }

    public var body: some View {
        chrome
            .escDismisses { dismiss() }
            .background(palette.pageBackground.ignoresSafeArea())
            .accessibilityElement(children: .contain)
    }

    private var content: some View {
        VStack(spacing: 16) {
            appIcon
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)

            VStack(spacing: 4) {
                Text(verbatim: appName).font(.title2.bold())
                // Kana subtitle only when the title isn't already kana.
                if !isJapanese {
                    Text(verbatim: "ドンパ隊").font(.title3).foregroundStyle(.secondary)
                }
            }

            // The game's own tagline (the title art's subtitle), not a genre blurb.
            Text("Clear the mines, save lives.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Version pill, matching the in-game config badge.
            Text("Version \(versionString)", bundle: .module)
                .font(.footnote.monospaced().weight(.semibold))
                .foregroundStyle(palette.counter)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(palette.counter.opacity(0.15)))
                .overlay(Capsule().stroke(palette.counter.opacity(0.3), lineWidth: 1))

            if let sha = commitSHA {
                Text(verbatim: sha)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Divider().frame(maxWidth: 220)

            if let onHowTo {
                Button(action: onHowTo) {
                    Label {
                        Text("How to play", bundle: .module)
                    } icon: {
                        Image(systemName: "questionmark.circle")
                    }
                    .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .tint(palette.counter)
                .foregroundStyle(palette.counter)
            }

            VStack(spacing: 6) {
                Text(verbatim: "© 2026 \(authorName)").font(.footnote)
                Link(destination: URL(string: "https://donpa.app")!) {
                    Label {
                        Text(verbatim: "donpa.app")
                    } icon: {
                        Image(systemName: "globe")
                    }
                    .font(.footnote)
                }
                .tint(palette.counter)
                Link(destination: URL(string: "https://github.com/vlumi/donpa")!) {
                    Label {
                        Text(verbatim: "github.com/vlumi/donpa")
                    } icon: {
                        Image(systemName: "link")
                    }
                    .font(.footnote)
                }
                .tint(palette.counter)
            }
        }
    }

    private var chrome: some View {
        SheetScaffold("About", fitContentDetent: true) {
            content
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
        }
    }

    /// The app icon, dug out of the bundle (the `AppIcon` set isn't directly
    /// loadable as a UI image).
    @ViewBuilder private var appIcon: some View {
        #if os(macOS)
        if let nsImage = NSApplication.shared.applicationIconImage {
            Image(nsImage: nsImage).resizable()
        } else {
            placeholderIcon
        }
        #else
        if let ui = uiAppIcon {
            Image(uiImage: ui).resizable()
        } else {
            placeholderIcon
        }
        #endif
    }

    private var placeholderIcon: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.secondary.opacity(0.2))
            .overlay(Image(systemName: "flag.fill").font(.largeTitle).foregroundStyle(.secondary))
    }

    #if os(iOS)
    private var uiAppIcon: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let name = files.last
        else { return nil }
        return UIImage(named: name)
    }
    #endif
}
