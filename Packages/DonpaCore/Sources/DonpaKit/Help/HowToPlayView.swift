import DonpaCore
import SpriteKit
import SwiftUI

/// The static how-to-play reference: every mechanic as a small ACCURATE board
/// diagram plus a line or two of text. The deep-dive lives on donpa.app
/// (linked below); Drills is the interactive half.
public struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    #if os(macOS)
    /// The section the arrows last scrolled to (keyboard paging).
    @State private var keySection: Int?
    #endif

    public init() {}

    private var palette: Palette { Palette.resolved(for: colorScheme) }

    public var body: some View {
        sheet
            .escDismisses { dismiss() }
    }

    @ViewBuilder private var sheet: some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle(Text("How to play", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done", bundle: .module)
                        }
                        .accessibilityIdentifier("sheet.done")
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            Text("How to play", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            Divider()
            content
            Divider()
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("sheet.done")
            }
            .padding()
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 640)
        #endif
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    goal.id(Section.goal)
                    modes.id(Section.modes)
                    chording.id(Section.chording)
                    counter.id(Section.counter)
                    endings.id(Section.endings)
                    luck.id(Section.luck)
                    drills.id(Section.drills)
                    #if os(macOS)
                    keyboardPlay.id(Section.keyboardPlay)
                    #endif
                    webLink.id(Section.webLink)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            #if os(macOS)
            // Arrows/Tab step section by section — a plain SwiftUI ScrollView
            // has no keyboard scrolling without system Full Keyboard Access.
            .background(
                KeyCatcher { key in
                    switch key {
                    case .down, .tab: stepSection(1, proxy: proxy)
                    case .up, .backTab: stepSection(-1, proxy: proxy)
                    case .enter, .escape: dismiss()
                    default: break
                    }
                }
            )
            #endif
        }
    }

    /// The content sections, in scroll order — the `.id` anchors and the
    /// keyboard paging both derive from this, so they can't drift.
    private enum Section: CaseIterable {
        case goal, modes, chording, counter, endings, luck, drills
        #if os(macOS)
        case keyboardPlay
        #endif
        case webLink
    }

    #if os(macOS)
    private func stepSection(_ delta: Int, proxy: ScrollViewProxy) {
        let all = Section.allCases
        guard let next = KeyStep.moved(keySection, by: delta, count: all.count) else { return }
        keySection = next
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(all[next], anchor: .top)
        }
    }
    #endif

    // MARK: Sections

    private var goal: some View {
        section(
            title: Text("The goal", bundle: .module),
            diagram: TileDiagram(rows: [
                [.revealed(0), .revealed(1), .hidden],
                [.revealed(0), .revealed(2), .hidden],
                [.revealed(0), .revealed(1), .hidden],
            ]),
            text: Text(
                """
                Open every tile that isn't a mine. A number counts the mines \
                touching that tile — here, the mines are somewhere in the \
                hidden column.
                """, bundle: .module)
        )
    }

    private var modes: some View {
        section(
            title: Text("Dig and flag", bundle: .module),
            diagram: HStack(alignment: .top, spacing: 14) {
                // The glyphs as the TOGGLE renders them (white on the mode
                // colour) — bare on the sheet the bootprint reads as inkblots;
                // this is what the player recognizes from the board's corner.
                captioned(Text("Dig", bundle: .module)) {
                    modeChip(.reveal, fill: palette.digColor)
                }
                TileDiagram(rows: [[.hidden, .flagged]])
                captioned(Text("Flag", bundle: .module)) {
                    modeChip(.flag, fill: palette.flagColor)
                }
            },
            text: Text(
                """
                The corner toggle switches what a tap does: dig (open the \
                tile) or plant a flag on a suspected mine. A long-press \
                does the other one. Flags are your notes — they can be \
                wrong, and you can clear them. Your first dig of a game \
                is always safe.
                """, bundle: .module)
        )
    }

    private var chording: some View {
        section(
            title: Text("Chording", bundle: .module),
            diagram: TileDiagram(rows: [
                [.hidden, .revealed(1), .revealed(0)],
                [.flagged, .revealed(1), .revealed(0)],
                [.hidden, .revealed(1), .revealed(0)],
            ]),
            text: Text(
                """
                When a number already has that many flags beside it, tap the \
                NUMBER to open all its other neighbours at once. Here the 1s \
                are satisfied by the flag, so tapping them opens the rest of \
                the column. Fast — but if the flag is wrong, it's the flag \
                that was the mistake.
                """, bundle: .module)
        )
    }

    private var counter: some View {
        section(
            title: Text("The mine counter", bundle: .module),
            diagram: CounterDiagram(),
            text: Text(
                """
                The top-bar counter is mines minus flags — how many mines \
                you haven't marked yet. It trusts your flags, right or wrong.
                """, bundle: .module)
        )
    }

    private var endings: some View {
        section(
            title: Text("Winning and losing", bundle: .module),
            diagram: TileDiagram(rows: [[.revealed(1), .mine, .revealed(1)]]),
            text: Text(
                """
                Open the last safe tile and the board is cleared — flags \
                don't need to be placed to win. Dig a mine and the game \
                ends; your cleared percentage still goes on the record.
                """, bundle: .module)
        )
    }

    private var luck: some View {
        section(
            title: Text("Forced guesses and luck", bundle: .module),
            diagram: TileDiagram(rows: [
                [.revealed(0), .revealed(1), .hidden],
                [.revealed(0), .revealed(1), .hidden],
            ]),
            text: Text(
                """
                Sometimes no safe move exists — the board forces a guess, \
                like one mine hiding in two identical tiles. When you \
                survive one, Donpa stamps the odds your click had at that \
                moment (50% here); your record keeps a luck line. The \
                tracking is exact but conservative: a guess only counts \
                when the game is sure no safe move existed — if it stays \
                silent about a death, a safe move was still on the board.
                """, bundle: .module)
        )
    }

    private var drills: some View {
        section(
            title: Text("Practice on Drills", bundle: .module),
            diagram: BoardGlyphView(kind: .practice, size: 34),
            text: Text(
                """
                The Drills family (leftmost in New game) generates boards \
                that never force a guess — every board falls to pure \
                deduction. Learn the patterns there, then speedrun them.
                """, bundle: .module)
        )
    }

    #if os(macOS)
    private var keyboardPlay: some View {
        section(
            title: Text("Keyboard play", bundle: .module),
            diagram: Image(systemName: "keyboard")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .frame(width: 34),
            text: Text(
                """
                Arrows or WASD move the cursor, Enter digs, F flags, Space \
                switches dig/flag. Everything else works from the keyboard \
                too — press ⌘/ for the full reference.
                """, bundle: .module)
        )
    }
    #endif

    private var webLink: some View {
        Link(destination: URL(string: "https://donpa.app/how-to-play")!) {
            Label {
                Text("More on the web", bundle: .module)
            } icon: {
                Image(systemName: "safari")
            }
            .font(.callout.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// The in-game mode toggle's segment, EXACTLY as the board renders it —
    /// same glyph size, frame, fill, and screentone. A scaled-down imitation
    /// loses what legibility the bootprint has.
    private func modeChip(_ symbol: MangaIcon.Symbol, fill: Color) -> some View {
        MangaIcon(symbol: symbol, size: 34, tint: .white)
            .frame(width: 50, height: 60)
            .background {
                ZStack {
                    fill
                    ScreentonePattern(
                        dots: symbol == .reveal, color: .white.opacity(0.35))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func captioned(_ caption: Text, @ViewBuilder icon: () -> some View) -> some View {
        VStack(spacing: 2) {
            icon()
            caption.font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    // MARK: Layout

    private func section(
        title: Text, diagram: some View, text: Text
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title.font(.headline)
            HStack(alignment: .top, spacing: 14) {
                diagram
                    .accessibilityHidden(true)  // the text carries the meaning
                text.font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
