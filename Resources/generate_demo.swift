import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { exit(2) }
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let width: CGFloat = 1100
let height: CGFloat = 680
let magenta = NSColor(calibratedRed: 1, green: 0.12, blue: 0.58, alpha: 1)
let cyan = NSColor(calibratedRed: 0.05, green: 0.86, blue: 1, alpha: 1)
let acid = NSColor(calibratedRed: 0.72, green: 1, blue: 0.16, alpha: 1)
let violet = NSColor(calibratedRed: 0.55, green: 0.18, blue: 1, alpha: 1)
let panel = NSColor(calibratedRed: 0.08, green: 0.055, blue: 0.15, alpha: 1)

func text(_ value: String, at point: NSPoint, size: CGFloat, color: NSColor, bold: Bool = false) {
    let font = bold ? NSFont.monospacedSystemFont(ofSize: size, weight: .bold) : NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    value.draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
}

func box(_ rect: NSRect, color: NSColor, stroke: NSColor? = nil) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
    if let stroke {
        stroke.setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        path.lineWidth = 2
        path.stroke()
    }
}

for frame in 0..<48 {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor(calibratedRed: 0.025, green: 0.018, blue: 0.075, alpha: 1).setFill()
    NSRect(origin: .zero, size: NSSize(width: width, height: height)).fill()

    box(NSRect(x: 18, y: 18, width: 230, height: 644), color: panel)
    text("MAC SWEEP", at: NSPoint(x: 42, y: 610), size: 22, color: .white, bold: true)
    text("NIGHTSHIFT EDITION", at: NSPoint(x: 42, y: 589), size: 10, color: cyan, bold: true)
    text("CLEANUP", at: NSPoint(x: 42, y: 548), size: 10, color: cyan, bold: true)
    let side = [("✦  Smart Scan", magenta), ("◈  System Junk", NSColor.white), ("◇  Mail Attachments", NSColor.white), ("▱  Trash Bins", NSColor.white), ("◌  My Clutter", NSColor.white)]
    for (index, item) in side.enumerated() {
        let y = CGFloat(515 - index * 38)
        if (frame >= 16 && frame < 32 && index == 4) || (frame >= 32 && index == 0) {
            box(NSRect(x: 34, y: y - 7, width: 198, height: 29), color: magenta.withAlphaComponent(0.18))
        }
        text(item.0, at: NSPoint(x: 46, y: y), size: 12, color: item.1, bold: true)
    }
    text("SAFE MODE // ACTIVE", at: NSPoint(x: 42, y: 58), size: 10, color: acid, bold: true)
    text("TRASH SAFE · LOCAL ONLY", at: NSPoint(x: 42, y: 40), size: 9, color: NSColor.lightGray)

    text(frame < 16 ? "SMART SCAN" : frame < 32 ? "MY CLUTTER" : "PROTECTION", at: NSPoint(x: 286, y: 614), size: 22, color: .white, bold: true)
    text(frame < 16 ? "A complete overview of your Mac" : frame < 32 ? "Large, old, and duplicate files" : "Read-only local security checks", at: NSPoint(x: 286, y: 590), size: 12, color: NSColor.lightGray)

    box(NSRect(x: 286, y: 435, width: 790, height: 130), color: NSColor(calibratedRed: 0.12, green: 0.03, blue: 0.22, alpha: 1), stroke: magenta.withAlphaComponent(0.7))
    text(frame < 16 ? "SCANNING YOUR MAC" : frame < 32 ? "REVIEW CLUTTER" : "LOCAL CHECKS COMPLETE", at: NSPoint(x: 320, y: 520), size: 22, color: .white, bold: true)
    let progress = min(1, CGFloat(frame + 1) / 16)
    box(NSRect(x: 320, y: 478, width: 520, height: 10), color: NSColor(calibratedWhite: 1, alpha: 0.1))
    box(NSRect(x: 320, y: 478, width: 520 * progress, height: 10), color: frame < 16 ? cyan : acid)
    text(frame < 16 ? "Checking caches, logs, and attachments" : frame < 32 ? "Choose what moves to Trash" : "No settings were changed", at: NSPoint(x: 320, y: 452), size: 12, color: NSColor.lightGray)

    if frame < 16 {
        let cards = [("CLEANUP", "12.4 GB", magenta), ("PROTECTION", "5 / 5", acid), ("CLUTTER", "2 FILES", violet)]
        for (index, card) in cards.enumerated() {
            let x = CGFloat(286 + index * 270)
            box(NSRect(x: x, y: 255, width: 250, height: 135), color: panel, stroke: card.2.withAlphaComponent(0.45))
            text(card.0, at: NSPoint(x: x + 22, y: 350), size: 11, color: card.2, bold: true)
            text(card.1, at: NSPoint(x: x + 22, y: 310), size: 23, color: .white, bold: true)
            text("LOCAL RESULT", at: NSPoint(x: x + 22, y: 278), size: 10, color: NSColor.lightGray)
        }
    } else if frame < 32 {
        let rows = [("archive-2024.zip", "2.8 GB", violet), ("duplicate-presentation.key", "760 MB", magenta), ("duplicate-presentation-copy.key", "760 MB", magenta)]
        for (index, row) in rows.enumerated() {
            let y = CGFloat(355 - index * 50)
            box(NSRect(x: 286, y: y, width: 790, height: 38), color: panel)
            text("□  \(row.0)", at: NSPoint(x: 310, y: y + 12), size: 12, color: .white)
            text(row.1, at: NSPoint(x: 935, y: y + 12), size: 12, color: row.2, bold: true)
        }
    } else {
        let rows = [("FileVault encryption", "SECURE", acid), ("Application firewall", "REVIEW", magenta), ("Gatekeeper", "SECURE", acid), ("System Integrity Protection", "SECURE", acid)]
        for (index, row) in rows.enumerated() {
            let y = CGFloat(355 - index * 50)
            box(NSRect(x: 286, y: y, width: 790, height: 38), color: panel)
            text("◉  \(row.0)", at: NSPoint(x: 310, y: y + 12), size: 12, color: .white)
            text(row.1, at: NSPoint(x: 960, y: y + 12), size: 11, color: row.2, bold: true)
        }
    }
    text("REVIEW AND CLEAN  →", at: NSPoint(x: 900, y: 45), size: 11, color: magenta, bold: true)
    image.unlockFocus()
    guard let data = NSBitmapImageRep(data: image.tiffRepresentation!)?.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: output.appendingPathComponent(String(format: "frame-%03d.png", frame)))
}
