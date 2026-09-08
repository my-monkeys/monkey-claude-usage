#!/usr/bin/env swift

// Draws the application icon and assembles it into an .icns.
//
//   swift scripts/make-icon.swift [--preview <dir>]
//
// Writes Sources/MonkeyClaudeUsage/Resources/AppIcon.icns and docs/icon.png.
// With --preview, also dumps 32 px and 128 px PNGs there to eyeball small sizes.

import AppKit
import Foundation

// MARK: - Art direction

enum Palette {
    /// Warm espresso, lit from the top — neutral ground for a single warm accent.
    static let backgroundTop = NSColor(srgbRed: 0.290, green: 0.220, blue: 0.176, alpha: 1)
    static let backgroundBottom = NSColor(srgbRed: 0.094, green: 0.071, blue: 0.067, alpha: 1)
    static let highlight = NSColor(white: 1, alpha: 0.07)
    static let rim = NSColor(white: 1, alpha: 0.10)
    static let monkey = NSColor(srgbRed: 0.960, green: 0.933, blue: 0.898, alpha: 1)
    static let gaugeTrack = NSColor(white: 1, alpha: 0.16)
    static let gaugeFill = NSColor(srgbRed: 0.851, green: 0.463, blue: 0.341, alpha: 1)
}

/// Fractions of the canvas, so every exported size is the same drawing.
enum Layout {
    /// Apple's macOS grid: the icon body is 824 pt inside a 1024 pt canvas.
    static let bodyInset: CGFloat = 100.0 / 1024.0
    static let bodyCurvature: CGFloat = 5

    static let monkeyWidth: CGFloat = 0.54
    static let monkeyTop: CGFloat = 0.165

    static let gaugeWidth: CGFloat = 0.42
    static let gaugeHeight: CGFloat = 0.060
    static let gaugeCenterY: CGFloat = 0.775
    /// Enough to read as "partly used" rather than empty or full.
    static let gaugeFraction: CGFloat = 0.68
}

/// Same head as Sources/MonkeyClaudeUsage/UI/MonkeyGlyph.swift, same unit square, y growing
/// downwards — but split in two. The glyph is one even-odd path because a template image has
/// to be a single shape; that rule also punches a hole wherever an ear overlaps the head,
/// which only goes unnoticed at 14 pt. The icon composites the two instead.
func monkeySilhouette() -> NSBezierPath {
    let path = NSBezierPath()
    path.appendOval(in: NSRect(x: 0.00, y: 0.26, width: 0.30, height: 0.30))   // left ear
    path.appendOval(in: NSRect(x: 0.70, y: 0.26, width: 0.30, height: 0.30))   // right ear
    path.appendOval(in: NSRect(x: 0.13, y: 0.10, width: 0.74, height: 0.80))   // head
    return path
}

func monkeyFeatures() -> NSBezierPath {
    let path = NSBezierPath()
    path.appendOval(in: NSRect(x: 0.31, y: 0.34, width: 0.11, height: 0.13))   // left eye
    path.appendOval(in: NSRect(x: 0.58, y: 0.34, width: 0.11, height: 0.13))   // right eye
    path.appendOval(in: NSRect(x: 0.28, y: 0.58, width: 0.44, height: 0.26))   // muzzle
    return path
}

/// Superellipse rather than a circular-corner rounded rect: it matches the continuous
/// curvature of macOS app icons instead of visibly kinking where the arc meets the edge.
func squircle(in rect: NSRect, curvature: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let radiusX = rect.width / 2
    let radiusY = rect.height / 2
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let steps = 512
    let exponent = 2 / curvature

    for step in 0...steps {
        let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(steps)
        let cosine = cos(angle)
        let sine = sin(angle)
        let point = NSPoint(
            x: center.x + radiusX * copysign(pow(abs(cosine), exponent), cosine),
            y: center.y + radiusY * copysign(pow(abs(sine), exponent), sine)
        )
        if step == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    return path
}

func pill(in rect: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
}

// MARK: - Rendering

func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("could not allocate a \(pixels)×\(pixels) bitmap")
    }

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not bind a drawing context to the bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    // Draw top-down so the glyph's own coordinate system applies unchanged.
    context.cgContext.translateBy(x: 0, y: size)
    context.cgContext.scaleBy(x: 1, y: -1)

    drawBody(size: size, in: context.cgContext)
    drawMonkey(size: size, in: context.cgContext)
    drawGauge(size: size)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func drawBody(size: CGFloat, in cgContext: CGContext) {
    // Snapped to whole pixels, otherwise the edge smears over two rows at 16 px.
    let inset = (size * Layout.bodyInset).rounded()
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let body = squircle(in: rect, curvature: Layout.bodyCurvature)

    NSGraphicsContext.saveGraphicsState()
    // Tight and faint: a wider shadow turns into a grey halo once the icon is 16 px.
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: size * 0.008)
    shadow.shadowBlurRadius = size * 0.014
    shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    shadow.set()
    Palette.backgroundBottom.setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    cgContext.saveGState()
    body.addClip()
    let colors = [Palette.backgroundTop.cgColor, Palette.backgroundBottom.cgColor] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
    }
    drawTopHighlight(in: rect, cgContext: cgContext)
    cgContext.restoreGState()

    let rimWidth = size * 0.005
    let rim = squircle(in: rect.insetBy(dx: rimWidth / 2, dy: rimWidth / 2), curvature: Layout.bodyCurvature)
    rim.lineWidth = rimWidth
    Palette.rim.setStroke()
    rim.stroke()
}

/// A soft light source above the icon, so the ground has depth instead of reading flat.
func drawTopHighlight(in rect: NSRect, cgContext: CGContext) {
    let colors = [Palette.highlight.cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 1]
    ) else { return }

    let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.18)
    cgContext.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: rect.width * 0.72,
        options: []
    )
}

func drawMonkey(size: CGFloat, in cgContext: CGContext) {
    let side = size * Layout.monkeyWidth
    var transform = AffineTransform.identity
    transform.translate(x: (size - side) / 2, y: size * Layout.monkeyTop)
    transform.scale(side)

    let silhouette = monkeySilhouette()
    silhouette.transform(using: transform)
    let features = monkeyFeatures()
    features.transform(using: transform)

    // The transparency layer keeps the eyes and muzzle cutting into the head only, not into
    // the background painted underneath.
    cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
    Palette.monkey.setFill()
    silhouette.fill()
    cgContext.setBlendMode(.destinationOut)
    features.fill()
    cgContext.setBlendMode(.normal)
    cgContext.endTransparencyLayer()
}

func drawGauge(size: CGFloat) {
    let width = size * Layout.gaugeWidth
    let height = size * Layout.gaugeHeight
    let rect = NSRect(
        x: (size - width) / 2,
        y: size * Layout.gaugeCenterY - height / 2,
        width: width,
        height: height
    )

    Palette.gaugeTrack.setFill()
    pill(in: rect).fill()

    var filled = rect
    filled.size.width = max(height, width * Layout.gaugeFraction)
    Palette.gaugeFill.setFill()
    pill(in: filled).fill()
}

// MARK: - Files

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(url.lastPathComponent)")
    }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url)
}

func convertToICNS(iconset: URL, output: URL) throws {
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["--convert", "icns", iconset.path, "--output", output.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        fatalError("iconutil failed with \(iconutil.terminationStatus)")
    }
}

let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let iconsetDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("MonkeyClaudeUsage-\(UUID().uuidString).iconset")
let icnsURL = repository
    .appendingPathComponent("Sources/MonkeyClaudeUsage/Resources/AppIcon.icns")
let readmeIconURL = repository.appendingPathComponent("docs/icon.png")

// The names iconutil expects; @2x entries are the same pixel sizes under another label.
let iconsetEntries: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)
for entry in iconsetEntries {
    try writePNG(renderIcon(size: entry.pixels), to: iconsetDirectory.appendingPathComponent("\(entry.name).png"))
}
try FileManager.default.createDirectory(
    at: icnsURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try convertToICNS(iconset: iconsetDirectory, output: icnsURL)
try FileManager.default.removeItem(at: iconsetDirectory)

try writePNG(renderIcon(size: 1024), to: readmeIconURL)

if let flag = CommandLine.arguments.firstIndex(of: "--preview"),
   flag + 1 < CommandLine.arguments.count {
    let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    for pixels in [CGFloat(32), 128] {
        try writePNG(renderIcon(size: pixels), to: directory.appendingPathComponent("icon-\(Int(pixels)).png"))
    }
    print("preview  \(directory.path)")
}

print("icns     \(icnsURL.path)")
print("png      \(readmeIconURL.path)")
