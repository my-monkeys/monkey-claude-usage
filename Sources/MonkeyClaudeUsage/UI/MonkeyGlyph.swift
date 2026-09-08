import AppKit

/// Monkey head drawn as a single even-odd path so it renders as a template image:
/// solid silhouette, eyes and muzzle punched out. Coordinates are a unit square.
enum MonkeyGlyph {
    nonisolated(unsafe) static let path: NSBezierPath = {
        let path = NSBezierPath()
        path.windingRule = .evenOdd

        path.appendOval(in: NSRect(x: 0.00, y: 0.26, width: 0.30, height: 0.30))   // left ear
        path.appendOval(in: NSRect(x: 0.70, y: 0.26, width: 0.30, height: 0.30))   // right ear
        path.appendOval(in: NSRect(x: 0.13, y: 0.10, width: 0.74, height: 0.80))   // head

        path.appendOval(in: NSRect(x: 0.31, y: 0.34, width: 0.11, height: 0.13))   // left eye
        path.appendOval(in: NSRect(x: 0.58, y: 0.34, width: 0.11, height: 0.13))   // right eye
        path.appendOval(in: NSRect(x: 0.28, y: 0.58, width: 0.44, height: 0.26))   // muzzle

        return path
    }()
}
