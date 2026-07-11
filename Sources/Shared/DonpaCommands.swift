import DonpaCore
import DonpaKit
import SwiftUI

/// The shared menu commands: the macOS menu bar, and on iPadOS the hold-⌘
/// shortcut HUD — both platforms expose the same keyboard vocabulary. About
/// stays in the macOS app (its menu slot is an AppKit concept).
///
/// Menu titles are wrapped in explicit `Text(...)` (not the bare
/// `Button("literal")` initializer): SwiftUI's string extractor picks up `Text`
/// literals reliably, whereas the bare-String `Button` init was extracted
/// inconsistently and got flagged `extractionState: stale` on every Xcode open
/// despite being live and translated.
struct DonpaCommands: Commands {
    @ObservedObject var viewModel: GameViewModel
    // Qualified: SwiftUI has a macOS-only `Settings` scene type.
    @ObservedObject var settings: DonpaKit.Settings
    @ObservedObject var navigator: Navigator
    /// Disabled while any modal is presented, so a shortcut can't mutate or
    /// navigate the game hidden beneath it (the host folds its own modals in).
    let modalOpen: Bool

    var body: some Commands {
        // Settings at the standard ⌘, slot, presented as the in-window sheet.
        CommandGroup(replacing: .appSettings) {
            Button {
                navigator.showingSettings = true
            } label: {
                Text("Settings…")
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(modalOpen)
        }
        CommandGroup(replacing: .newItem) {
            // New Game opens the config popup (pick mode/size, then Start) — the
            // ONLY path to a fresh board, deliberately: the picker is where the
            // families/sizes/densities live, so no preset quick-starts here.
            // Restart replays the same board.
            Button {
                navigator.showingNewGame = true
            } label: {
                Text("New Game…")
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(modalOpen)
            Button {
                viewModel.newGame()
            } label: {
                Text("Restart Game")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(modalOpen)
            Button {
                // Pause + save (handled in GameContent), not discard. "Barracks"
                // is the army vocabulary's name for Home — B for Barracks.
                navigator.homeRequested &+= 1
            } label: {
                Text("Barracks")
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(modalOpen)
            Button {
                navigator.showingMessHall = true
            } label: {
                Text("Mess Hall…")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(modalOpen)
        }
        // Help menu: the in-app guide at the standard ⌘? slot, and the
        // keyboard reference at ⌘/.
        CommandGroup(replacing: .help) {
            Button {
                navigator.showingHowTo = true
            } label: {
                Text("How to Play")
            }
            .keyboardShortcut("?", modifiers: .command)
            .disabled(modalOpen)
            Button {
                navigator.showingShortcuts = true
            } label: {
                Text("Keyboard Shortcuts")
            }
            .keyboardShortcut("/", modifiers: .command)
            .disabled(modalOpen)
        }
        CommandMenu(Text("Game")) {
            Button {
                navigator.showingScores = true
            } label: {
                Text("High Scores")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(modalOpen)

            Divider()

            Button {
                viewModel.inputMode.toggle()
            } label: {
                // Two separate literals (not a ternary inside one string) so both
                // extract as static keys.
                if viewModel.inputMode == .flag {
                    Text("Switch to Reveal Mode")
                } else {
                    Text("Switch to Flag Mode")
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(modalOpen)

            Button {
                settings.sound.toggle()
            } label: {
                if settings.sound {
                    Text("Turn Sound Off")
                } else {
                    Text("Turn Sound On")
                }
            }
            .disabled(modalOpen)

            Divider()

            // ⌘0 toggles the corner minimap between its min and max size — it
            // pairs with ⌘+/⌘− as the "fit / actual-size" slot many apps use.
            Button {
                navigator.toggleMinimapRequested &+= 1
            } label: {
                Text("Toggle Minimap Size")
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(modalOpen)

            // ⌘+ / ⌘− zoom the board (about its centre). Bind zoom-in to the
            // "+" *character*, not a physical key: SwiftUI matches on the char
            // the keystroke produces, so this follows "+" wherever a layout puts
            // it — Finnish ⌘+ (its own key), US ⌘⇧=, JIS ⌘⇧;. Binding to "="
            // instead failed on Finnish, where "=" isn't on that key.
            Button {
                navigator.zoomInRequested &+= 1
            } label: {
                Text("Zoom In")
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(modalOpen)
            Button {
                navigator.zoomOutRequested &+= 1
            } label: {
                Text("Zoom Out")
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(modalOpen)
        }
    }
}
