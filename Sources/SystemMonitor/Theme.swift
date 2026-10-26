import SwiftUI
import AppKit

// MARK: - Palette
//
// Drawn from 19th-century academic oil painting in the manner of Fernand Cormon:
// warm umber grounds, ochre and sienna earth pigments, varnished shadows,
// gilt picture frames and ivory highlights.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Palette {
    // Grounds
    static let umberDeep = Color(hex: 0x120D09)
    static let umber = Color(hex: 0x1F1710)
    static let panelTop = Color(hex: 0x33261A)
    static let panelBottom = Color(hex: 0x241A12)
    static let well = Color(hex: 0x17110B)          // recessed areas inside a panel

    // Frame
    static let gilt = Color(hex: 0xC9A24A)
    static let giltLight = Color(hex: 0xE8CB7A)
    static let giltDark = Color(hex: 0x7A5F2A)

    // Text
    static let ivory = Color(hex: 0xF1E6CB)
    static let parchment = Color(hex: 0xC9B691)
    static let faded = Color(hex: 0x8C7B60)

    // Pigments (one per section)
    static let ochre = Color(hex: 0xDDA94A)        // CPU
    static let sienna = Color(hex: 0xC8673E)       // Memory
    static let verdigris = Color(hex: 0x74A48C)    // Disk
    static let sapGreen = Color(hex: 0xA3B45C)     // Power
    static let lapis = Color(hex: 0x7C9BCB)        // Network ↓
    static let madder = Color(hex: 0xC0566A)       // Network ↑ / disk write
    static let leadWhite = Color(hex: 0xE9DFC9)

    // States
    static let good = Color(hex: 0xA3B45C)
    static let warn = Color(hex: 0xE5913F)
    static let danger = Color(hex: 0xD04A3A)
}

// MARK: - Type

enum Typo {
    /// Display serif for titles (Baskerville ships with macOS).
    static func title(_ size: CGFloat) -> Font { .custom("Baskerville-SemiBold", size: size) }
    static func titleItalic(_ size: CGFloat) -> Font { .custom("Baskerville-Italic", size: size) }
    /// Numerals: New York serif with tabular digits so values don't jitter.
    static func numeral(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif).monospacedDigit()
    }
    static func body(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func caption(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .regular, design: .serif) }
}

// MARK: - Canvas texture

/// A small, tileable linen-weave noise generated once at launch.
enum CanvasTexture {
    static let image: NSImage = {
        let size = 160
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: size * 4, bitsPerPixel: 32),
              let data = rep.bitmapData else { return NSImage(size: NSSize(width: 1, height: 1)) }
        var seed: UInt32 = 0x9E37_79B9
        func random() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed >> 8) / Double(1 << 24)
        }
        for y in 0..<size {
            for x in 0..<size {
                // Warp and weft threads plus grain.
                let warp = sin(Double(x) * .pi / 2) * 0.5 + 0.5
                let weft = sin(Double(y) * .pi / 2) * 0.5 + 0.5
                let grain = random()
                let v = (warp * 0.35 + weft * 0.35 + grain * 0.6)
                let light = v > 0.7
                let i = (y * size + x) * 4
                let tone: UInt8 = light ? 255 : 0
                data[i] = tone; data[i + 1] = tone; data[i + 2] = tone
                data[i + 3] = UInt8(min(255, abs(v - 0.65) * 70))
            }
        }
        let image = NSImage(size: NSSize(width: size / 2, height: size / 2))
        image.addRepresentation(rep)
        return image
    }()
}

/// Varnished umber ground with a single warm light falling from the upper left (chiaroscuro),
/// canvas weave and a dark vignette.
struct CanvasBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.umber, Palette.umberDeep], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Palette.ochre.opacity(0.20), Palette.sienna.opacity(0.06), .clear],
                           center: UnitPoint(x: 0.18, y: 0.05), startRadius: 0, endRadius: 700)
            Image(nsImage: CanvasTexture.image)
                .resizable(resizingMode: .tile)
                .opacity(0.55)
            RadialGradient(colors: [.clear, Color.black.opacity(0.55)],
                           center: .center, startRadius: 250, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Gilt frame

/// A painting-style frame: dark varnished panel, double gilt fillet, soft drop shadow.
struct GiltFrame: ViewModifier {
    var accent: Color? = nil
    var cornerRadius: CGFloat = 6

    func body(content: Content) -> some View {
        // The shadow, texture and frame live in a background that never changes between
        // samples, so Core Animation renders them once. A shadow on the live content would
        // be recomputed off-screen on every update.
        content
            .background(FrameBackdrop(accent: accent, cornerRadius: cornerRadius))
    }
}

private struct FrameBackdrop: View, Equatable {
    var accent: Color?
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape
                .fill(LinearGradient(colors: [Palette.panelTop, Palette.panelBottom],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 6)
            Image(nsImage: CanvasTexture.image)
                .resizable(resizingMode: .tile)
                .opacity(0.35)
                .clipShape(shape)
            shape
                .strokeBorder(LinearGradient(colors: [Palette.giltLight, Palette.gilt, Palette.giltDark],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.6)
            RoundedRectangle(cornerRadius: max(cornerRadius - 3, 2), style: .continuous)
                .strokeBorder((accent ?? Palette.gilt).opacity(0.28), lineWidth: 0.8)
                .padding(4)
        }
    }
}

extension View {
    func giltFrame(accent: Color? = nil, cornerRadius: CGFloat = 6) -> some View {
        modifier(GiltFrame(accent: accent, cornerRadius: cornerRadius))
    }

    /// Dark, painted look for every window and panel in the app.
    func cormonStyle() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(Palette.gilt)
            .foregroundStyle(Palette.ivory)
    }
}

/// Decorative flourish used between sections, like an engraved rule.
struct Fleuron: View {
    var body: some View {
        HStack(spacing: 10) {
            line
            Text("❦").font(.system(size: 13)).foregroundStyle(Palette.gilt)
            line
        }
    }
    private var line: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, Palette.gilt.opacity(0.7), .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 0.8)
    }
}

// MARK: - Heart-monitor glyph (menu bar)

enum HeartMonitorGlyph {
    /// White heart-monitor trace in a rounded screen, drawn as a template image so the
    /// menu bar renders it in its own foreground color (white on a dark menu bar).
    static func image(alert: Bool = false) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            let frame = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1.5), xRadius: 3.2, yRadius: 3.2)
            frame.lineWidth = 1.3
            frame.stroke()

            let mid = rect.midY - 0.5
            let trace = NSBezierPath()
            let points: [(CGFloat, CGFloat)] = [
                (3.0, 0), (6.6, 0), (7.8, 2.2), (9.3, -4.6), (10.9, 5.4), (12.2, 0), (13.6, 1.4), (14.8, 0), (17.0, 0)
            ]
            trace.move(to: NSPoint(x: points[0].0, y: mid + points[0].1))
            for p in points.dropFirst() { trace.line(to: NSPoint(x: p.0, y: mid + p.1)) }
            trace.lineWidth = 1.5
            trace.lineJoinStyle = .round
            trace.lineCapStyle = .round
            trace.stroke()

            if alert {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static let normal = image(alert: false)
    static let alert = image(alert: true)
}
