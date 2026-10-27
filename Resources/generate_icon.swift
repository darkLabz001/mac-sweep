import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { exit(2) }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let bounds = NSRect(origin: .zero, size: size)
let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 16, dy: 16), xRadius: 220, yRadius: 220)
NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.01, blue: 0.22, alpha: 1), NSColor(calibratedRed: 0.02, green: 0.18, blue: 0.30, alpha: 1)])!.draw(in: background, angle: -35)

NSColor(calibratedRed: 1, green: 0.04, blue: 0.52, alpha: 0.9).setStroke()
let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 115, dy: 115))
ring.lineWidth = 13
ring.stroke()

NSColor(calibratedRed: 0.05, green: 0.86, blue: 1, alpha: 0.45).setStroke()
let innerRing = NSBezierPath(ovalIn: bounds.insetBy(dx: 150, dy: 150))
innerRing.lineWidth = 4
innerRing.stroke()

let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 575, y: 855))
bolt.line(to: NSPoint(x: 350, y: 535))
bolt.line(to: NSPoint(x: 500, y: 535))
bolt.line(to: NSPoint(x: 425, y: 170))
bolt.line(to: NSPoint(x: 700, y: 585))
bolt.line(to: NSPoint(x: 545, y: 585))
bolt.close()
NSColor(calibratedRed: 0.78, green: 1, blue: 0.15, alpha: 1).setFill()
bolt.fill()
NSColor.white.setStroke()
bolt.lineWidth = 7
bolt.stroke()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let data = representation.representation(using: .png, properties: [:]) else { exit(3) }
try data.write(to: output)
