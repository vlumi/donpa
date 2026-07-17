// Prints the CGWindowID of the given PID's main window — `screencapture -l`
// wants one for a clean, click-free window grab (Scripts/shoot.sh, dev-only).
// Matched by OWNER PID, not app name: the window server reports the LOCALIZED
// app name (ドンパ隊 under -AppleLanguages ja), so names don't survive the
// demo's language cycling.
import CoreGraphics
import Foundation

guard let arg = CommandLine.arguments.dropFirst().first, let pid = Int(arg) else {
    FileHandle.standardError.write(Data("usage: window-id.swift <pid>\n".utf8))
    exit(2)
}
let info =
    CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
for window in info {
    guard let owner = window[kCGWindowOwnerPID as String] as? Int, owner == pid,
        let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
        let number = window[kCGWindowNumber as String] as? Int
    else { continue }
    print(number)
    exit(0)
}
FileHandle.standardError.write(Data("no on-screen window for pid \(pid)\n".utf8))
exit(1)
