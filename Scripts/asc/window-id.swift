// Prints the CGWindowID of the named app's main window — `screencapture -l`
// wants one for a clean, click-free window grab (Scripts/shoot.sh, dev-only).
import CoreGraphics
import Foundation

let target = CommandLine.arguments.dropFirst().first ?? "Donpa Squad"
let info =
    CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
for window in info {
    guard let owner = window[kCGWindowOwnerName as String] as? String, owner == target,
        let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
        let number = window[kCGWindowNumber as String] as? Int
    else { continue }
    print(number)
    exit(0)
}
FileHandle.standardError.write(Data("no on-screen window for \(target)\n".utf8))
exit(1)
