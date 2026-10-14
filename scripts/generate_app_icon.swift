import AppKit
import Foundation

// Run once when regenerating the checked-in icon:
//   mkdir -p /tmp/MacMouseMapper.iconset
//   swift scripts/generate_app_icon.swift /tmp/MacMouseMapper.iconset
//   iconutil -c icns /tmp/MacMouseMapper.iconset -o Sources/MacMouseMapper/Resources/MacMouseMapper.icns

let outputDirectory = CommandLine.arguments.dropFirst().first ?? "/tmp/MacMouseMapper.iconset"
let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let representations: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2)
]

for representation in representations {
    let pixels = representation.points * representation.scale
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "MacMouseMapperIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(representation.scale), y: CGFloat(representation.scale))
    let canvas = CGRect(x: 0, y: 0, width: representation.points, height: representation.points)

    NSColor.clear.setFill()
    NSBezierPath(rect: canvas).fill()

    let background = NSBezierPath(
        roundedRect: canvas.insetBy(dx: 0.8, dy: 0.8),
        xRadius: CGFloat(representation.points) * 0.23,
        yRadius: CGFloat(representation.points) * 0.23
    )
    NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.42, alpha: 1).setFill()
    background.fill()

    let mouseWidth = CGFloat(representation.points) * 0.42
    let mouseHeight = CGFloat(representation.points) * 0.68
    let mouseRect = CGRect(
        x: CGFloat(representation.points) * 0.42,
        y: CGFloat(representation.points) * 0.17,
        width: mouseWidth,
        height: mouseHeight
    )
    let mouse = NSBezierPath(
        roundedRect: mouseRect,
        xRadius: mouseWidth * 0.43,
        yRadius: mouseWidth * 0.43
    )
    NSColor.white.withAlphaComponent(0.96).setFill()
    mouse.fill()

    let centerLine = NSBezierPath()
    centerLine.move(to: NSPoint(x: mouseRect.midX, y: mouseRect.minY + mouseRect.height * 0.64))
    centerLine.line(to: NSPoint(x: mouseRect.midX, y: mouseRect.maxY - mouseRect.height * 0.14))
    NSColor(calibratedWhite: 0.25, alpha: 0.4).setStroke()
    centerLine.lineWidth = max(0.7, CGFloat(representation.points) / 48)
    centerLine.stroke()

    let wheelWidth = CGFloat(representation.points) * 0.075
    let wheelHeight = CGFloat(representation.points) * 0.15
    let wheel = NSBezierPath(
        roundedRect: CGRect(
            x: mouseRect.midX - wheelWidth / 2,
            y: mouseRect.midY + mouseRect.height * 0.12,
            width: wheelWidth,
            height: wheelHeight
        ),
        xRadius: wheelWidth / 2,
        yRadius: wheelWidth / 2
    )
    NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.42, alpha: 0.78).setFill()
    wheel.fill()

    // Two small side-button accents make the motif legible at Finder sizes.
    let sideWidth = CGFloat(representation.points) * 0.12
    let sideHeight = CGFloat(representation.points) * 0.12
    for index in 0..<2 {
        let side = NSBezierPath(
            roundedRect: CGRect(
                x: mouseRect.minX - sideWidth * 0.45,
                y: mouseRect.midY + CGFloat(index - 1) * sideHeight * 1.25,
                width: sideWidth,
                height: sideHeight
            ),
            xRadius: sideWidth * 0.38,
            yRadius: sideWidth * 0.38
        )
        NSColor(calibratedRed: 0.28, green: 0.58, blue: 0.98, alpha: 1).setFill()
        side.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MacMouseMapperIcon", code: 2)
    }
    try pngData.write(to: outputURL.appendingPathComponent(representation.name))
}
