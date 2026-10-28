import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Color {
    static var cpuTint: Color { Palette.ochre }
    static var memoryTint: Color { Palette.sienna }
    static var diskTint: Color { Palette.verdigris }
    static var powerTint: Color { Palette.sapGreen }
    static var networkTint: Color { Palette.lapis }
    static var uploadTint: Color { Palette.madder }
}

extension OverallStatus {
    var color: Color {
        switch self {
        case .healthy: return Palette.good
        case .attention: return Palette.warn
        case .critical: return Palette.danger
        }
    }
    var symbol: String {
        switch self {
        case .healthy: return "heart.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
    /// Shown in italics under the status, in keeping with the painted theme.
    var motto: String {
        switch self {
        case .healthy: return "in good health"
        case .attention: return "requires attention"
        case .critical: return "in distress"
        }
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
    var color: Color {
        switch self {
        case .nominal: return Palette.good
        case .fair: return Palette.ochre
        case .serious: return Palette.warn
        default: return Palette.danger
        }
    }
}

/// Section pigment, shifting to warning colors as a value approaches its threshold.
func loadColor(_ fraction: Double, warn: Double = 0.75, critical: Double = 0.9, base: Color) -> Color {
    if fraction >= critical { return Palette.danger }
    if fraction >= warn { return Palette.warn }
    return base
}

// MARK: - Card (a framed painting)

struct Card<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let tint: Color
    var detail: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        let look = Appearance.current
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                IconBadge(symbol: icon, tint: tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Typo.title(19)).foregroundStyle(Palette.ivory)
                    if let subtitle, look != .glass {
                        Text(subtitle).font(Typo.titleItalic(12)).foregroundStyle(Palette.parchment)
                    }
                }
                Spacer(minLength: 8)
                if let detail {
                    Text(detail).font(Typo.caption()).foregroundStyle(Palette.parchment).lineLimit(1)
                }
            }
            switch look {
            case .gallery:
                Rectangle()
                    .fill(LinearGradient(colors: [tint.opacity(0.8), Palette.gilt.opacity(0.25), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
            case .canvas:
                BrushStroke(seed: title.count &* 13 &+ 5, roughness: 0.35)
                    .fill(tint.opacity(0.5))
                    .frame(width: 96, height: 5)
            case .glass:
                EmptyView()
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .giltFrame(accent: tint)
    }
}

/// Round icon badge used in card headers and compact rows: an enamel medallion (Gallery),
/// a dab of paint (Canvas) or a plain tinted symbol (Mac Glass).
struct IconBadge: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 28

    var body: some View {
        let image = Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
        switch Appearance.current {
        case .gallery:
            image
                .background(Circle().fill(Palette.well))
                .overlay(Circle().strokeBorder(tint.opacity(0.6), lineWidth: 1))
        case .canvas:
            image.background(
                BrushBlob(seed: symbol.count &* 7 &+ 1, wobble: 0.16)
                    .fill(tint.opacity(0.2))
                    .frame(width: size * 1.25, height: size * 1.08)
            )
        case .glass:
            image.background(Circle().fill(tint.opacity(0.14)))
        }
    }
}

// MARK: - Gauges & meters

struct RingGauge<Center: View>: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 10
    @ViewBuilder var center: Center

    var body: some View {
        let f = min(max(fraction, 0), 1)
        switch Appearance.current {
        case .gallery:
            ZStack {
                Circle().fill(Palette.well)
                Circle().stroke(Palette.giltDark.opacity(0.45), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: f)
                    .stroke(AngularGradient(colors: [tint.opacity(0.65), tint, Palette.giltLight],
                                            center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .strokeBorder(Palette.gilt.opacity(0.5), lineWidth: 0.8)
                    .padding(-lineWidth / 2 - 3)
                center
            }
            .padding(lineWidth / 2 + 3)
        case .canvas:
            // An ensō: a loose wash for the track, a loaded stroke for the value.
            ZStack {
                PaintedRing(value: f, color: tint, lineWidth: lineWidth * 1.3, seed: Int(lineWidth) &* 3 &+ 1)
                center.padding(lineWidth * 1.3)
            }
        case .glass:
            ZStack {
                Circle().stroke(Palette.giltDark, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: f)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                center.padding(lineWidth / 2)
            }
            .padding(lineWidth / 2)
        }
    }
}

struct BigValue: View {
    var value: String
    var caption: String
    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(Typo.numeral(21))
                .foregroundStyle(Palette.ivory)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caption).font(Typo.titleItalic(11)).foregroundStyle(Palette.parchment)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
    }
}

struct BarMeter: View {
    var fraction: Double
    var tint: Color
    var height: CGFloat = 6

    var body: some View {
        let f = min(max(fraction, 0), 1)
        switch Appearance.current {
        case .gallery:
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.well)
                    Capsule().strokeBorder(Palette.giltDark.opacity(0.5), lineWidth: 0.5)
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * f)
                }
            }
            .frame(height: height)
        case .canvas:
            PaintedBar(value: f, color: tint, seed: Int(height * 11) &+ 7, thickness: max(height * 1.7, 6))
        case .glass:
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.giltDark)
                    Capsule().fill(tint).frame(width: max(f > 0 ? height : 0, geo.size.width * f))
                }
            }
            .frame(height: height)
        }
    }
}

/// One vertical bar per CPU core.
struct CoreBar: View {
    var fraction: Double
    var tint: Color
    var seed: Int
    var height: CGFloat = 34

    var body: some View {
        let f = min(max(fraction, 0), 1)
        Group {
            switch Appearance.current {
            case .gallery:
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.well)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                        .frame(height: max(2, height * f))
                }
            case .canvas:
                GeometryReader { g in
                    PaintedBar(value: f, color: tint, seed: seed, thickness: min(g.size.width, 14), vertical: true)
                        .frame(maxWidth: .infinity)
                }
            case .glass:
                ZStack(alignment: .bottom) {
                    Capsule().fill(Palette.giltDark)
                    Capsule().fill(tint).frame(height: max(4, height * f))
                }
            }
        }
        .frame(height: height)
    }
}

/// Horizontal bar split into colored segments (e.g. memory composition).
struct SegmentedBar: View {
    var segments: [(fraction: Double, color: Color)]
    var height: CGFloat = 8

    var body: some View {
        switch Appearance.current {
        case .canvas:
            // Side-by-side brushstrokes of each pigment over a pale wash.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    BrushStroke(seed: 301, roughness: 0.3).fill(Palette.giltDark.opacity(0.6))
                    HStack(spacing: 2) {
                        ForEach(segments.indices, id: \.self) { i in
                            BrushStroke(seed: 310 + i * 9, roughness: 0.25)
                                .fill(segments[i].color.opacity(0.85))
                                .frame(width: max(0, geo.size.width * min(max(segments[i].fraction, 0), 1) - 2))
                        }
                    }
                }
            }
            .frame(height: height * 1.6)
        default:
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segments.indices, id: \.self) { i in
                        Rectangle().fill(segments[i].color)
                            .frame(width: max(0, geo.size.width * min(max(segments[i].fraction, 0), 1) - 1))
                    }
                    Spacer(minLength: 0)
                }
                .background(Appearance.current == .glass ? Palette.giltDark : Palette.well)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Appearance.current == .glass ? Color.clear : Palette.giltDark.opacity(0.5),
                                                lineWidth: 0.5))
            }
            .frame(height: height)
        }
    }
}

struct Sparkline: View {
    var values: [Double]
    var maxValue: Double? = nil
    var tint: Color
    var filled = true

    var body: some View {
        GeometryReader { geo in
            let points = Self.points(values, maxValue: maxValue, size: geo.size)
            switch Appearance.current {
            case .gallery:
                ZStack {
                    if filled { area(points, geo.size).fill(LinearGradient(colors: [tint.opacity(0.38), tint.opacity(0.02)],
                                                                         startPoint: .top, endPoint: .bottom)) }
                    Path { p in p.addLines(points) }
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            case .canvas:
                // Layered ink: a broad translucent pass, a firm middle line and a dry-brush wisp,
                // each slightly offset like separate strokes of a brush.
                ZStack {
                    if filled { area(points, geo.size).fill(tint.opacity(0.10)) }
                    Self.smooth(Self.jitter(points, amount: 1.2, seed: 80))
                        .stroke(tint.opacity(0.4), style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
                    Self.smooth(Self.jitter(points, amount: 0.5, seed: 90))
                        .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    Self.smooth(Self.jitter(points, amount: 1.8, seed: 99))
                        .stroke(tint.opacity(0.35), style: StrokeStyle(lineWidth: 0.7, lineCap: .round, lineJoin: .round))
                }
            case .glass:
                ZStack {
                    if filled { area(points, geo.size).fill(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0.02)],
                                                                         startPoint: .top, endPoint: .bottom)) }
                    Self.smooth(points)
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func area(_ points: [CGPoint], _ size: CGSize) -> Path {
        Path { p in
            guard let first = points.first, let last = points.last else { return }
            p.move(to: CGPoint(x: first.x, y: size.height))
            p.addLines(points)
            p.addLine(to: CGPoint(x: last.x, y: size.height))
            p.closeSubpath()
        }
    }

    /// Newest sample sits at the right edge; the line grows leftward as history fills.
    static func points(_ values: [Double], maxValue: Double?, size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let top = max(maxValue ?? (values.max() ?? 1), 0.000_001)
        let step = size.width / CGFloat(MetricHistory.capacity - 1)
        let n = values.count
        return values.enumerated().map { i, v in
            let x = size.width - CGFloat(n - 1 - i) * step
            let y = size.height - CGFloat(min(max(v / top, 0), 1)) * (size.height - 2) - 1
            return CGPoint(x: x, y: y)
        }
    }

    /// Wobbles each point by a stable amount so a painted line keeps its character between samples.
    static func jitter(_ pts: [CGPoint], amount: CGFloat, seed: Int) -> [CGPoint] {
        pts.enumerated().map { i, p in
            CGPoint(x: p.x, y: p.y + CGFloat(Noise.fbm(Double(i) * 0.9, seed: seed)) * amount)
        }
    }

    /// Quadratic smoothing through midpoints.
    static func smooth(_ pts: [CGPoint]) -> Path {
        Path { p in
            guard pts.count > 1 else { return }
            p.move(to: pts[0])
            for i in 1..<pts.count {
                let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
                p.addQuadCurve(to: mid, control: pts[i - 1])
            }
            p.addLine(to: pts[pts.count - 1])
        }
    }
}

/// A sparkline set in a recessed "well", like a small painting within the frame.
struct ChartWell<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        let inner = content
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(height: height)
        switch Appearance.current {
        case .gallery:
            inner
                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.well.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.giltDark.opacity(0.55), lineWidth: 0.6))
        case .canvas:
            inner.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.well.opacity(0.7)))
        case .glass:
            inner.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.well))
        }
    }
}

// MARK: - Stats

struct Stat: Identifiable {
    let label: String
    let value: String
    var color: Color? = nil
    // Labels are unique within a grid; a stable id lets SwiftUI update values in place.
    var id: String { label }
}

struct StatGrid: View {
    var stats: [Stat]
    var columns = 2

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: columns),
                  alignment: .leading, spacing: 10) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.label).font(Typo.titleItalic(12)).foregroundStyle(Palette.parchment).lineLimit(1)
                    Text(stat.value)
                        .font(Typo.numeral(13.5))
                        .foregroundStyle(stat.color ?? Palette.ivory)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        let look = Appearance.current
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: look == .glass ? .default : .serif))
            .foregroundStyle(look == .glass ? Palette.parchment : Palette.gilt)
            .tracking(look == .glass ? 0.8 : 1.6)
    }
}

/// Status badge: a wax seal (Gallery), a dab of paint (Canvas) or a tinted capsule (Mac Glass).
struct StatusPill: View {
    var status: OverallStatus
    var body: some View {
        let label = HStack(spacing: 6) {
            Image(systemName: status.symbol).font(.system(size: 10, weight: .bold))
            Text(status.title).font(Typo.title(13))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        switch Appearance.current {
        case .gallery:
            label
                .foregroundStyle(status.color)
                .background(Capsule().fill(Palette.well))
                .overlay(Capsule().strokeBorder(status.color.opacity(0.7), lineWidth: 1))
        case .canvas:
            label
                .foregroundStyle(Palette.ivory)
                .background(BrushBlob(seed: 23, wobble: 0.14).fill(status.color.opacity(0.28)))
        case .glass:
            label
                .foregroundStyle(status.color)
                .background(Capsule().fill(status.color.opacity(0.15)))
        }
    }
}

struct LegendDot: View {
    var color: Color
    var text: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(Typo.caption()).foregroundStyle(Palette.parchment)
        }
    }
}

// MARK: - App icons for the top-apps lists

final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for usage: AppUsage) -> NSImage {
        let path = usage.bundlePath ?? usage.executablePath
        if let cached = cache[path] { return cached }
        let icon = path.hasPrefix("/")
            ? NSWorkspace.shared.icon(forFile: path)
            : NSWorkspace.shared.icon(for: .unixExecutable)
        icon.size = NSSize(width: 32, height: 32)
        cache[path] = icon
        return icon
    }
}
