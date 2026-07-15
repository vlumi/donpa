import SwiftUI

/// The one sheet chrome, both platforms: iOS wraps content in a
/// NavigationStack with an inline title and a Done confirmation item; macOS
/// renders the title, the content, and a bottom bar with an optional leading
/// accessory and the default-action Done. Esc dismisses on both. Sheets keep
/// only their content and sizing knobs.
struct SheetScaffold<Content: View, MacFooter: View, MacBackground: View>: View {
    /// The sheet's one dismissing control: Done for read-and-close sheets,
    /// Cancel where dismissing means abandoning (scanning, confirm flows).
    enum DismissStyle {
        case done, cancel

        var label: LocalizedStringKey { self == .done ? "Done" : "Cancel" }
    }

    let title: LocalizedStringKey
    var dismissStyle: DismissStyle = .done
    var macMinWidth: CGFloat = 300
    var macIdealWidth: CGFloat?
    var macMinHeight: CGFloat?
    var macIdealHeight: CGFloat?
    /// iOS: size the sheet's detent to the content's natural height.
    var fitContentDetent = false
    /// iOS: wrap the content in a ScrollView (the detent still measures the
    /// UNSCROLLED content, so nothing changes when everything fits).
    var iosScrolls = false
    /// macOS: hug the natural height when the content fits, scroll when not
    /// (short windows, large text). Title and Done stay pinned outside.
    var macScrollFallback = false
    @ViewBuilder var content: Content
    /// macOS bottom bar, leading side (e.g. the Record's sync control).
    @ViewBuilder var macFooter: MacFooter
    /// macOS chrome background — the seat for a sheet's KeyCatcher.
    @ViewBuilder var macBackground: MacBackground

    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @State private var contentHeight: CGFloat = 0
    #endif

    var body: some View {
        chrome
            .escDismisses { dismiss() }
    }

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Text(dismissStyle.label, bundle: .module)
        }
        .accessibilityIdentifier("sheet.done")
    }

    #if os(iOS)
    private var chrome: some View {
        NavigationStack {
            scrollingContent
                .navigationTitle(Text(title, bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(
                        placement: dismissStyle == .done
                            ? .confirmationAction : .cancellationAction
                    ) { dismissButton }
                }
        }
        .modifier(FitContentDetent(enabled: fitContentDetent, height: contentHeight))
    }

    @ViewBuilder private var scrollingContent: some View {
        let measured = content.background(heightReader)
        if iosScrolls {
            ScrollView { measured }
        } else {
            measured
        }
    }

    @ViewBuilder private var heightReader: some View {
        if fitContentDetent {
            GeometryReader { geo in
                Color.clear.onAppear { contentHeight = geo.size.height }
                    .onChangeCompat(of: geo.size.height) { contentHeight = $0 }
            }
        }
    }
    #else
    private var chrome: some View {
        VStack(spacing: 16) {
            Text(title, bundle: .module).font(.title2.bold())
            fittingContent
            HStack(spacing: 12) {
                macFooter
                Spacer()
                dismissButton.keyboardShortcut(
                    dismissStyle == .done ? .defaultAction : .cancelAction)
            }
        }
        .padding(20)
        .frame(
            minWidth: macMinWidth, idealWidth: macIdealWidth,
            minHeight: macMinHeight, idealHeight: macIdealHeight
        )
        .background(macBackground)
    }

    @ViewBuilder private var fittingContent: some View {
        if macScrollFallback {
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
            }
        } else {
            content
        }
    }
    #endif
}

extension SheetScaffold
where MacFooter == EmptyView, MacBackground == EmptyView {
    init(
        _ title: LocalizedStringKey, dismissStyle: DismissStyle = .done,
        macMinWidth: CGFloat = 300, macIdealWidth: CGFloat? = nil,
        macMinHeight: CGFloat? = nil, macIdealHeight: CGFloat? = nil,
        fitContentDetent: Bool = false, iosScrolls: Bool = false,
        macScrollFallback: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title, dismissStyle: dismissStyle,
            macMinWidth: macMinWidth, macIdealWidth: macIdealWidth,
            macMinHeight: macMinHeight, macIdealHeight: macIdealHeight,
            fitContentDetent: fitContentDetent, iosScrolls: iosScrolls,
            macScrollFallback: macScrollFallback, content: content,
            macFooter: { EmptyView() }, macBackground: { EmptyView() })
    }
}

#if os(iOS)
/// `.height(_)` detent from the measured content, `.medium` until measured.
private struct FitContentDetent: ViewModifier {
    let enabled: Bool
    let height: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content.presentationDetents(height > 0 ? [.height(height + 64)] : [.medium])
        } else {
            content
        }
    }
}
#endif
