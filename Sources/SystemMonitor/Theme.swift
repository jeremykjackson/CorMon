import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Appearance (user-selectable look)

/// The three looks. Chosen in Settings › General › Appearance and stored under `Prefs.appearance`.
enum Appearance: String, CaseIterable, Identifiable {
    /// V1 default: 19th-century academic oil painting — umber grounds, gilt frames, Baskerville.
    case gallery
    /// V2: light and painterly — warm paper, watercolor washes, every gauge drawn as a brushstroke.
    case canvas
    /// Mirrors macOS: SF Pro, system colors and accent, Light/Dark, Liquid Glass on macOS 26.
    case glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gallery: return "Gallery"
        case .canvas: return "Canvas"
        case .glass: return "Mac Glass"
        }
    }

    var summary: String {
        switch self {
        case .gallery: return "The original look: dark oil painting with gilt frames"
        case .canvas: return "Light and painterly, with brushstroke gauges and graphs"
        case .glass: return "Matches macOS: SF Pro, your accent color, Liquid Glass"
        }
    }

    /// The look every view draws with. Updated by `cormonStyle()` before its subtree renders.
    private(set) static var current: Appearance = load()

    static func load() -> Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: Prefs.appearance) ?? "") ?? .gallery
    }

    /// Gallery is always dark and Canvas always light; Mac Glass follows the system setting.
    var appKitAppearance: NSAppearance? {
        switch self {
        case .gallery: return NSAppearance(named: .darkAqua)
        case .canvas: return NSAppearance(named: .aqua)
        case .glass: return nil
        }
    }

    /// Corner radius for a panel: Gallery keeps tight picture-frame corners, the others are softer.
    func frameRadius(_ base: CGFloat) -> CGFloat { self == .gallery ? base : base * 2.5 }

    /// Picks up a change the moment the preference is written (synchronously, before SwiftUI's
    /// next update), so every view body that runs afterwards reads the new look.
    static func startObserving() {
        _ = observer
        activate(load())
    }

    private static let observer: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
            let a = Appearance.load()
            guard a != Appearance.current else { return }
            if Thread.isMainThread {
                Appearance.activate(a)
            } else {
                DispatchQueue.main.async { Appearance.activate(a) }
            }
        }

    static func activate(_ a: Appearance) {
        let changed = a != current
        current = a
        if changed || NSApp?.appearance?.name != a.appKitAppearance?.name {
            // Set on the next turn of the run loop: AppKit appearance changes trigger layout,
            // which must not happen in the middle of a SwiftUI update.
            DispatchQueue.main.async { NSApp?.appearance = a.appKitAppearance }
        }
    }
}

// MARK: - Palette
//
// Semantic roles keep the original Gallery names (umber ground, gilt frame, ivory text, earth
// pigments), so every view reads the same property and gets the right color for the active look.

struct PaletteSet {
    // Grounds
    var umberDeep, umber, panelTop, panelBottom, well: Color
    // Frame / accent
    var gilt, giltLight, giltDark: Color
    // Text
    var ivory, parchment, faded: Color
    // Pigments (one per section)
    var ochre, sienna, verdigris, sapGreen, lapis, madder, leadWhite: Color
    // States
    var good, warn, danger: Color

    /// Gallery (V1): drawn from 19th-century academic oil painting in the manner of Fernand Cormon.
    static let gallery = PaletteSet(
        umberDeep: Color(hex: 0x120D09), umber: Color(hex: 0x1F1710),
        panelTop: Color(hex: 0x33261A), panelBottom: Color(hex: 0x241A12), well: Color(hex: 0x17110B),
        gilt: Color(hex: 0xC9A24A), giltLight: Color(hex: 0xE8CB7A), giltDark: Color(hex: 0x7A5F2A),
        ivory: Color(hex: 0xF1E6CB), parchment: Color(hex: 0xC9B691), faded: Color(hex: 0x8C7B60),
        ochre: Color(hex: 0xDDA94A), sienna: Color(hex: 0xC8673E), verdigris: Color(hex: 0x74A48C),
        sapGreen: Color(hex: 0xA3B45C), lapis: Color(hex: 0x7C9BCB), madder: Color(hex: 0xC0566A),
        leadWhite: Color(hex: 0xE9DFC9),
        good: Color(hex: 0xA3B45C), warn: Color(hex: 0xE5913F), danger: Color(hex: 0xD04A3A))

    /// Canvas (V2): warm paper and transparent watercolor pigments, ink-dark text.
    static let canvas = PaletteSet(
        umberDeep: Color(hex: 0xEEE6D7), umber: Color(hex: 0xF5EFE4),
        panelTop: Color(hex: 0xFDFAF4), panelBottom: Color(hex: 0xF9F4EA), well: Color(hex: 0xF1EADD),
        gilt: Color(hex: 0x3F5E96), giltLight: Color(hex: 0x2E2925), giltDark: Color(hex: 0xDCD0BC),
        ivory: Color(hex: 0x2E2925), parchment: Color(hex: 0x7A6D60), faded: Color(hex: 0xA6998A),
        ochre: Color(hex: 0xC98F22), sienna: Color(hex: 0xC2553A), verdigris: Color(hex: 0x3B8A74),
        sapGreen: Color(hex: 0x678A34), lapis: Color(hex: 0x2C78AE), madder: Color(hex: 0xB5476A),
        leadWhite: Color(hex: 0x9C8F80),
        good: Color(hex: 0x5B8C4F), warn: Color(hex: 0xD08A22), danger: Color(hex: 0xB33A3A))

    /// Mac Glass: semantic system colors, so it follows Light/Dark mode and the user's accent color.
    static let glass = PaletteSet(
        umberDeep: Color(nsColor: .windowBackgroundColor), umber: Color(nsColor: .windowBackgroundColor),
        panelTop: Color(nsColor: .controlBackgroundColor), panelBottom: Color(nsColor: .controlBackgroundColor),
        well: Color.primary.opacity(0.05),
        gilt: .accentColor, giltLight: .primary, giltDark: Color.primary.opacity(0.12),
        ivory: .primary, parchment: .secondary, faded: Color(nsColor: .tertiaryLabelColor),
        ochre: .blue, sienna: .purple, verdigris: .teal, sapGreen: .green, lapis: .cyan, madder: .pink,
        leadWhite: .gray,
        good: .green, warn: .orange, danger: .red)

    static func `for`(_ a: Appearance) -> PaletteSet {
        switch a {
        case .gallery: return gallery
        case .canvas: return canvas
        case .glass: return glass
        }
    }
}

enum Palette {
    private static var p: PaletteSet { PaletteSet.for(Appearance.current) }

    static var umberDeep: Color { p.umberDeep }
    static var umber: Color { p.umber }
    static var panelTop: Color { p.panelTop }
    static var panelBottom: Color { p.panelBottom }
    static var well: Color { p.well }              // recessed areas inside a panel

    static var gilt: Color { p.gilt }              // frame / accent
    static var giltLight: Color { p.giltLight }    // display titles
    static var giltDark: Color { p.giltDark }      // tracks and hairlines

    static var ivory: Color { p.ivory }            // primary text
    static var parchment: Color { p.parchment }    // secondary text
    static var faded: Color { p.faded }            // tertiary text

    static var ochre: Color { p.ochre }            // CPU
    static var sienna: Color { p.sienna }          // Memory
    static var verdigris: Color { p.verdigris }    // Disk
    static var sapGreen: Color { p.sapGreen }      // Power
    static var lapis: Color { p.lapis }            // Network ↓
    static var madder: Color { p.madder }          // Network ↑ / disk write
    static var leadWhite: Color { p.leadWhite }    // efficiency cores

    static var good: Color { p.good }
    static var warn: Color { p.warn }
    static var danger: Color { p.danger }
}

// MARK: - Type

enum Typo {
    private static var look: Appearance { Appearance.current }

    /// Display face for titles: Baskerville (Gallery), New York (Canvas), SF Pro (Mac Glass).
    static func title(_ size: CGFloat) -> Font {
        switch look {
        case .gallery: return .custom("Baskerville-SemiBold", size: size)
        case .canvas: return .system(size: size, weight: .semibold, design: .serif)
        case .glass: return .system(size: size * 0.92, weight: .semibold)
        }
    }

    /// Secondary captions and labels.
    static func titleItalic(_ size: CGFloat) -> Font {
        switch look {
        case .gallery: return .custom("Baskerville-Italic", size: size)
        case .canvas: return .system(size: size, weight: .regular, design: .serif).italic()
        case .glass: return .system(size: size * 0.95)
        }
    }

    /// Numerals with tabular digits so values don't jitter.
    static func numeral(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        switch look {
        case .gallery: return .system(size: size, weight: weight, design: .serif).monospacedDigit()
        case .canvas: return .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        case .glass: return .system(size: size, weight: weight).monospacedDigit()
        }
    }

    static func body(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        switch look {
        case .gallery: return .system(size: size, weight: weight, design: .serif)
        case .canvas, .glass: return .system(size: size, weight: weight)
        }
    }

    static func caption(_ size: CGFloat = 11) -> Font {
        switch look {
        case .gallery: return .system(size: size, weight: .regular, design: .serif)
        case .canvas, .glass: return .system(size: size)
        }
    }
}

// MARK: - Textures

/// A small, tileable linen-weave noise generated once at launch (Gallery).
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

/// Cold-press watercolor paper grain: soft speckle plus a few fibers, tileable, generated once (Canvas).
enum PaperGrain {
    static let image: NSImage = {
        let size = 256
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: size * 4, bitsPerPixel: 32),
              let data = rep.bitmapData else { return NSImage(size: NSSize(width: 1, height: 1)) }
        // Brown ink, varying alpha. Low-frequency "tooth" is value noise on a 32×32 grid that
        // wraps at the tile edge, so the tile repeats seamlessly.
        let cells = 32, cellSize = size / cells
        func cell(_ i: Int, _ j: Int) -> Double { Noise.hash(((i % cells) + cells) % cells &* 131 &+ ((j % cells) + cells) % cells, 9) }
        func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        for y in 0..<size {
            for x in 0..<size {
                let ci = x / cellSize, cj = y / cellSize
                let fx = smooth(Double(x % cellSize) / Double(cellSize))
                let fy = smooth(Double(y % cellSize) / Double(cellSize))
                let top = cell(ci, cj) + (cell(ci + 1, cj) - cell(ci, cj)) * fx
                let bottom = cell(ci, cj + 1) + (cell(ci + 1, cj + 1) - cell(ci, cj + 1)) * fx
                let tooth = top + (bottom - top) * fy
                let speck = Noise.hash(x &* 7919 &+ y, 3)
                var a = (tooth - 0.5) * 22 + (speck > 0.985 ? 38 : 0) + speck * 6
                a = max(0, min(255, a))
                let i = (y * size + x) * 4
                data[i] = 0x5A; data[i + 1] = 0x46; data[i + 2] = 0x32
                data[i + 3] = UInt8(a)
            }
        }
        let image = NSImage(size: NSSize(width: size / 2, height: size / 2))
        image.addRepresentation(rep)
        return image
    }()
}

/// The window ground for the active look.
struct CanvasBackground: View {
    var body: some View {
        Group {
            switch Appearance.current {
            case .gallery:
                // Varnished umber with a single warm light from the upper left (chiaroscuro),
                // canvas weave and a dark vignette.
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
            case .canvas:
                // Warm paper with loose watercolor washes bleeding in from the edges.
                ZStack {
                    LinearGradient(colors: [Palette.umber, Palette.umberDeep], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Palette.ochre.opacity(0.16), .clear],
                                   center: UnitPoint(x: 0.08, y: 0.0), startRadius: 0, endRadius: 520)
                    RadialGradient(colors: [Palette.lapis.opacity(0.11), .clear],
                                   center: UnitPoint(x: 0.95, y: 0.95), startRadius: 0, endRadius: 560)
                    RadialGradient(colors: [Palette.madder.opacity(0.07), .clear],
                                   center: UnitPoint(x: 0.85, y: 0.1), startRadius: 0, endRadius: 380)
                    Image(nsImage: PaperGrain.image)
                        .resizable(resizingMode: .tile)
                }
            case .glass:
                VisualEffectBackground()
            }
        }
        .ignoresSafeArea()
    }
}

/// Window background that blurs the desktop behind it (Mac Glass).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

// MARK: - Panel frame

/// The frame around every card and panel: a gilt picture frame (Gallery), a sheet of paper with a
/// pigment bloom (Canvas), or Liquid Glass (Mac Glass).
struct GiltFrame: ViewModifier {
    var accent: Color? = nil
    var cornerRadius: CGFloat = 6

    func body(content: Content) -> some View {
        // The frame lives in a background that never changes between samples, so Core Animation
        // renders it once. A shadow on the live content would be recomputed on every update.
        content
            .background(FrameBackdrop(look: Appearance.current, accent: accent, cornerRadius: cornerRadius))
    }
}

private struct FrameBackdrop: View, Equatable {
    var look: Appearance
    var accent: Color?
    var cornerRadius: CGFloat

    var body: some View {
        switch look {
        case .gallery: gallery
        case .canvas: canvas
        case .glass: GlassSurface(cornerRadius: look.frameRadius(cornerRadius))
        }
    }

    private var gallery: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
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

    private var canvas: some View {
        let shape = RoundedRectangle(cornerRadius: look.frameRadius(cornerRadius), style: .continuous)
        let tint = accent ?? Palette.gilt
        return ZStack {
            shape
                .fill(LinearGradient(colors: [Palette.panelTop, Palette.panelBottom],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(hex: 0x6B4F2A).opacity(0.12), radius: 14, x: 0, y: 6)
            // A watercolor bloom of the section's pigment in the top-right corner.
            GeometryReader { g in
                BrushBlob(seed: Int(cornerRadius * 7) + 3, wobble: 0.22)
                    .fill(tint.opacity(0.13))
                    .frame(width: min(g.size.width * 0.6, 240), height: min(g.size.height * 0.55, 170))
                    .blur(radius: 26)
                    .position(x: g.size.width - 30, y: 20)
            }
            .clipShape(shape)
            Image(nsImage: PaperGrain.image)
                .resizable(resizingMode: .tile)
                .opacity(0.7)
                .clipShape(shape)
            shape.strokeBorder(Palette.ivory.opacity(0.07), lineWidth: 1)
        }
    }
}

/// Liquid Glass on macOS 26 (when built with the macOS 26 SDK); a translucent material otherwise.
struct GlassSurface: View {
    var cornerRadius: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            fallback(shape)
        }
        #else
        fallback(shape)
        #endif
    }

    private func fallback(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(.regularMaterial)
            .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }
}

extension View {
    func giltFrame(accent: Color? = nil, cornerRadius: CGFloat = 6) -> some View {
        modifier(GiltFrame(accent: accent, cornerRadius: cornerRadius))
    }

    /// Applies the chosen look to a window or panel. Every root view uses this; when the user
    /// switches looks the subtree is rebuilt so it reads the new palette and type.
    func cormonStyle() -> some View {
        modifier(CorMonStyle())
    }
}

private struct CorMonStyle: ViewModifier {
    @AppStorage(Prefs.appearance) private var raw = Appearance.gallery.rawValue

    func body(content: Content) -> some View {
        let look = Appearance(rawValue: raw) ?? .gallery
        Appearance.activate(look)
        return content
            .id(look)
            .tint(Palette.gilt)
            .foregroundStyle(Palette.ivory)
    }
}

/// Decorative rule between sections: an engraved fleuron (Gallery), a single brushstroke
/// (Canvas), or a hairline (Mac Glass).
struct Fleuron: View {
    var body: some View {
        switch Appearance.current {
        case .gallery:
            HStack(spacing: 10) {
                line
                Text("❦").font(.system(size: 13)).foregroundStyle(Palette.gilt)
                line
            }
        case .canvas:
            BrushStroke(seed: 41, roughness: 0.4)
                .fill(Palette.gilt.opacity(0.22))
                .frame(height: 5)
                .padding(.horizontal, 8)
        case .glass:
            Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 0.5)
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
