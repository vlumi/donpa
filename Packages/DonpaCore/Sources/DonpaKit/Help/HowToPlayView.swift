import DonpaCore
import SpriteKit
import SwiftUI

/// The static how-to-play reference (the progression milestone's "?" page):
/// every mechanic as a small ACCURATE board diagram plus a line or two of
/// text — a real rendered mini-board teaches chording better than prose or a
/// comic panel, tracks dark mode for free, and needs no per-locale art. The
/// deep-dive lives on donpa.app (linked below); Drills is the interactive
/// half. Reachable from the title screen's "?" and from About.
public struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    private var palette: Palette { Palette.resolved(for: colorScheme) }

    public var body: some View {
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
            HStack {
                Text("How to play", bundle: .module).font(.headline)
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
            Divider()
            content
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 640)
        #endif
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                goal
                modes
                chording
                counter
                endings
                luck
                drills
                webLink
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

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
                // Captioned: the boot-print reads as "dig" in the toggle's
                // context, but not floating alone in a help diagram.
                captioned(Text("Dig", bundle: .module)) {
                    MangaIconView(symbol: .reveal, size: 30)
                }
                TileDiagram(rows: [[.hidden, .flagged]])
                captioned(Text("Flag", bundle: .module)) {
                    MangaIconView(symbol: .flag, size: 30)
                }
            },
            text: Text(
                """
                The corner toggle switches what a tap does: dig (open the \
                tile) or plant a flag on a suspected mine. Flags are your \
                notes — they can be wrong, and you can clear them. Your \
                first dig of a game is always safe.
                """, bundle: .module)
        )
    }

    private var chording: some View {
        section(
            title: Text("Chording", bundle: .module),
            diagram: TileDiagram(rows: [
                [.flagged, .revealed(1), .revealed(0)],
                [.hidden, .revealed(1), .revealed(0)],
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
                [.revealed(1), .hidden, .hidden, .revealed(1)]
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

    /// A tiny mode-name caption under a glyph, so an icon can't float unexplained.
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

/// A tiny, ACCURATE board rendering for the help diagrams — the same visual
/// vocabulary as the real board (palette tiles, classic number colours, the
/// flag/mine glyphs), at caption scale.
struct TileDiagram: View {
    enum Tile {
        case hidden
        case revealed(Int)
        case flagged
        case mine
    }

    let rows: [[Tile]]
    var tileSize: CGFloat = 26

    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { Palette.resolved(for: colorScheme) }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        tile(rows[r][c])
                    }
                }
            }
        }
    }

    @ViewBuilder private func tile(_ tile: Tile) -> some View {
        let base = RoundedRectangle(cornerRadius: 3)
        ZStack {
            switch tile {
            case .hidden, .flagged:
                base.fill(Color(skColor: palette.hiddenTile))
            case .revealed, .mine:
                base.fill(Color(skColor: palette.revealedTile))
            }
            switch tile {
            case .hidden:
                EmptyView()
            case .revealed(let n) where n > 0:
                Text(verbatim: "\(n)")
                    .font(.system(size: tileSize * 0.62, weight: .heavy, design: .monospaced))
                    .foregroundStyle(numberColor(n))
            case .revealed:
                EmptyView()
            case .flagged:
                MangaIconView(symbol: .flag, size: tileSize * 0.7)
            case .mine:
                Text(verbatim: "✸")
                    .font(.system(size: tileSize * 0.66, weight: .black))
                    .foregroundStyle(Color(skColor: palette.mineTile))
            }
        }
        .frame(width: tileSize, height: tileSize)
    }

    private func numberColor(_ n: Int) -> Color {
        let index = min(max(n, 1), palette.numbers.count) - 1
        return Color(skColor: palette.numbers[index])
    }
}

/// The mine counter, redrawn at help scale (the status bar's pill).
private struct CounterDiagram: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(verbatim: "⚑ 038")
            .font(.system(size: 15, weight: .heavy, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Palette.resolved(for: colorScheme).counter))
    }
}

/// SwiftUI wrappers over the Canvas glyph vocabularies, at help scale.
private struct MangaIconView: View {
    let symbol: MangaIcon.Symbol
    var size: CGFloat = 30

    var body: some View {
        Canvas { ctx, area in
            ctx.translateBy(x: (area.width - size) / 2, y: (area.height - size) / 2)
            MangaIcon.draw(symbol, in: ctx, side: size, color: .primary)
        }
        .frame(width: size, height: size)
    }
}

private struct BoardGlyphView: View {
    let kind: BoardGlyph.Kind
    var size: CGFloat = 30

    var body: some View {
        BoardGlyph(kind: kind, size: size)
    }
}

extension Color {
    /// Bridge the palette's SpriteKit colours into SwiftUI.
    init(skColor: SKColor) {
        #if canImport(UIKit)
        self.init(uiColor: skColor)
        #else
        self.init(nsColor: skColor)
        #endif
    }
}
