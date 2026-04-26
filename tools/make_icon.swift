#!/usr/bin/env swift

// One-shot icon generator. Produces Resources/AppIcon.icns from an SF
// Symbol on a rounded-square background. Run from the repo root:
//
//     swift tools/make_icon.swift
//
// Re-run only when changing the design. The resulting .icns is committed
// to the repo and copied into the .app bundle by build.sh.

import AppKit
import Foundation

let repoRoot = FileManager.default.currentDirectoryPath
let resources = repoRoot + "/Resources"
let iconset = resources + "/AppIcon.iconset"
let icns = resources + "/AppIcon.icns"

let fm = FileManager.default
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// Warm orange like macOS's Voice Memos accent.
let bgColor = NSColor(red: 1.00, green: 0.42, blue: 0.21, alpha: 1.0)
let symbolColor = NSColor.white

/// Render the master icon once at 1024×1024. SF Symbols don't downscale
/// cleanly at very small point sizes, so we render once at full res and
/// downsample for each iconset slot via `NSGraphicsContext` interpolation.
func renderMaster() -> NSImage? {
    let s: CGFloat = 1024
    let canvas = NSImage(size: NSSize(width: s, height: s))
    canvas.lockFocus()

    let cornerRadius = s * 0.225
    let bg = NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )
    bgColor.setFill()
    bg.fill()

    let pointSize = s * 0.55
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [symbolColor]))

    if let symbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig)
    {
        let symSize = symbol.size
        let origin = NSPoint(x: (s - symSize.width) / 2, y: (s - symSize.height) / 2)
        symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    } else {
        canvas.unlockFocus()
        FileHandle.standardError.write(Data("Failed to load mic.fill SF Symbol\n".utf8))
        return nil
    }
    canvas.unlockFocus()
    return canvas
}

func resampledPNG(from master: NSImage, to pixels: Int) -> Data? {
    let s = CGFloat(pixels)
    let target = NSImage(size: NSSize(width: s, height: s))
    target.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(
        in: NSRect(x: 0, y: 0, width: s, height: s),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
    target.unlockFocus()

    guard let tiff = target.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { return nil }
    return bitmap.representation(using: .png, properties: [:])
}

// Apple's expected iconset layout.
let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16",       16),
    ("icon_16x16@2x",    32),
    ("icon_32x32",       32),
    ("icon_32x32@2x",    64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]

guard let master = renderMaster() else { exit(1) }

for (name, pixels) in entries {
    guard let data = resampledPNG(from: master, to: pixels) else {
        FileHandle.standardError.write(Data("Failed to render \(name)\n".utf8))
        exit(1)
    }
    let url = URL(fileURLWithPath: "\(iconset)/\(name).png")
    try data.write(to: url)
    print("  ✓ \(name).png (\(pixels)×\(pixels))")
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", icns]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

print("Generated \(icns)")

// Cleanup the iconset folder; we keep only the compiled .icns.
try? fm.removeItem(atPath: iconset)
