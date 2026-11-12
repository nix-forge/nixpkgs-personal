import AppKit
import Foundation

// Template images use alpha as their ink mask. A full-colour app icon with an
// opaque background therefore becomes a solid tile, regardless of its RGB art.
let resources = URL(fileURLWithPath: CommandLine.arguments[1])
for (name, width, height) in [("MenuBarIcon", 26, 20), ("MenuBarIcon@2x", 52, 40)] {
    let url = resources.appendingPathComponent(name + ".png")
    guard let data = try? Data(contentsOf: url),
          let bitmap = NSBitmapImageRep(data: data),
          bitmap.pixelsWide == width, bitmap.pixelsHigh == height,
          bitmap.hasAlpha else {
        fatalError("Invalid menu bar representation: \(name)")
    }
    var ink = 0.0
    for y in 0..<height {
        for x in 0..<width {
            guard let color = bitmap.colorAt(x: x, y: y) else {
                fatalError("Unreadable menu bar pixel: \(name)")
            }
            ink += Double(color.alphaComponent)
        }
    }
    let coverage = ink / Double(width * height)
    // Leave ample room for antialiasing and small artwork changes, but reject
    // both an empty glyph and a background-filled square at either scale.
    guard (0.1...0.6).contains(coverage) else {
        fputs("FAIL: \(name) alpha coverage \(coverage); expected an open template glyph\n", stderr)
        exit(1)
    }
    print("PASS: \(name) \(width)x\(height), alpha coverage \(coverage)")
}
