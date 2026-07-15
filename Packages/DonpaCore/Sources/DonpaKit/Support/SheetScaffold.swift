import SwiftUI

/// The one sheet chrome, both platforms: iOS wraps content in a
/// NavigationStack with an inline title and a Done confirmation item; macOS
/// renders the title, the content, and a bottom bar with an optional leading
/// accessory and the default-action Done. Esc dismisses on both. Sheets keep
/// only their content and sizing knobs.
struct SheetScaffold<Content: View, MacFooter: View>: View {
    let title: LocalizedStringKey
    var macMinWidth: CGFloat = 300
    var macIdealWidth: CGFloat?
    var macMinHeight: CGFloat?
    var macIdealHeight: CGFloat?
    /// iOS: size the sheet's detent to the content's natural height.
    var fitContentDetent = false
    @ViewBuilder var content: Content
    /// macOS bottom bar, leading side (e.g. the Record's sync control).
    @ViewBuilder var macFooter: MacFooter

    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @State private var contentHeight: CGFloat = 0
    #endif

    var body: some View {
        chrome
            .escDismisses { dismiss() }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done", bundle: .module)
        }
        .accessibilityIdentifier("sheet.done")
    }

    #if os(iOS)
    private var chrome: some View {
        NavigationStack {
            content
                .background(heightReader)
                .navigationTitle(Text(title, bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { doneButton }
                }
        }
        .modifier(FitContentDetent(enabled: fitContentDetent, height: contentHeight))
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
            content
            HStack(spacing: 12) {
                macFooter
                Spacer()
                doneButton.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(
            minWidth: macMinWidth, idealWidth: macIdealWidth,
            minHeight: macMinHeight, idealHeight: macIdealHeight)
    }
    #endif
}

extension SheetScaffold where MacFooter == EmptyView {
    init(
        _ title: LocalizedStringKey,
        macMinWidth: CGFloat = 300, macIdealWidth: CGFloat? = nil,
        macMinHeight: CGFloat? = nil, macIdealHeight: CGFloat? = nil,
        fitContentDetent: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title, macMinWidth: macMinWidth, macIdealWidth: macIdealWidth,
            macMinHeight: macMinHeight, macIdealHeight: macIdealHeight,
            fitContentDetent: fitContentDetent, content: content,
            macFooter: { EmptyView() })
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
