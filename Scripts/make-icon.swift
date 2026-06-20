#!/usr/bin/env swift
//
// Generates the app icon (a minesweeper flag on a tile) at every size the
// asset catalog needs. Pure CoreGraphics, so it's reproducible and
// dependency-free.
//
//   swift Scripts/make-icon.swift Sources/Shared/Assets.xcassets/AppIcon.appiconset
//
// Writes icon-16.png … icon-1024.png into the given directory.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// The icon is drawn at any requested pixel size, so it stays crisp at every
// slot in the asset catalog (iOS 1024 plus the macOS 16…512 @1x/@2x set).
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

func renderIcon(size: Int) -> CGImage {
    guard
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("could not create context") }

    let s = CGFloat(size)

    // Background: vertical gradient, dark slate to near-black (matches the board).
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [color(0.16, 0.17, 0.20), color(0.07, 0.07, 0.09)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // A raised tile in the centre.
    let inset = s * 0.16
    let tileRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tile = CGPath(
        roundedRect: tileRect, cornerWidth: s * 0.10, cornerHeight: s * 0.10, transform: nil)
    ctx.addPath(tile)
    ctx.setFillColor(color(0.26, 0.27, 0.31))
    ctx.fillPath()

    // Subtle top highlight on the tile for a little depth.
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let sheen = CGGradient(
        colorsSpace: space,
        colors: [color(0.34, 0.35, 0.40), color(0.22, 0.23, 0.27)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        sheen, start: CGPoint(x: 0, y: tileRect.maxY), end: CGPoint(x: 0, y: tileRect.minY),
        options: [])
    ctx.restoreGState()

    // Flag pole.
    let poleX = s * 0.46
    let poleBottom = s * 0.34
    let poleTop = s * 0.70
    ctx.setStrokeColor(color(0.85, 0.86, 0.90))
    ctx.setLineWidth(s * 0.022)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: poleX, y: poleBottom))
    ctx.addLine(to: CGPoint(x: poleX, y: poleTop))
    ctx.strokePath()

    // Flag base.
    let baseW = s * 0.20
    ctx.setFillColor(color(0.85, 0.86, 0.90))
    ctx.fill(
        CGRect(x: poleX - baseW / 2, y: poleBottom - s * 0.018, width: baseW, height: s * 0.05))

    // Red flag (triangle pointing right-down from the top of the pole).
    ctx.setFillColor(color(0.92, 0.27, 0.24))
    ctx.move(to: CGPoint(x: poleX, y: poleTop))
    ctx.addLine(to: CGPoint(x: poleX + s * 0.22, y: poleTop - s * 0.085))
    ctx.addLine(to: CGPoint(x: poleX, y: poleTop - s * 0.17))
    ctx.closePath()
    ctx.fillPath()

    guard let image = ctx.makeImage() else { fatalError("could not render image") }
    return image
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not create PNG destination") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write PNG") }
    print("Wrote \(path)")
}

// Every pixel size the asset catalog references: iOS 1024 plus the macOS
// 16/32/128/256/512 set at @1x and @2x. Keys match the Contents.json filenames.
let sizes = [16, 32, 64, 128, 256, 512, 1024]
for px in sizes {
    writePNG(renderIcon(size: px), to: "\(outDir)/icon-\(px).png")
}
