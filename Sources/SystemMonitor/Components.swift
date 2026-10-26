import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension Color {
    static let cpuTint = Palette.ochre
    static let memoryTint = Palette.sienna
    static let diskTint = Palette.verdigris
    static let powerTint = Palette.sapGreen
    static let networkTint = Palette.lapis
    static let uploadTint = Palette.madder
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.well))
                    .overlay(Circle().strokeBorder(tint.opacity(0.6), lineWidth: 1))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Typo.title(19)).foregroundStyle(Palette.ivory)
                    if let subtitle {
                        Text(subtitle).font(Typo.titleItalic(12)).foregroundStyle(Palette.parchment)
                    }
                }
                Spacer(minLength: 8)
                if let detail {
                    Text(detail).font(Typo.caption()).foregroundStyle(Palette.parchment).lineLimit(1)
                }
            }
            Rectangle()
                .fill(LinearGradient(colors: [tint.opacity(0.8), Palette.gilt.opacity(0.25), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .giltFrame(accent: tint)
    }
}

// MARK: - Gauges & meters

struct RingGauge<Center: View>: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 10
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle().fill(Palette.well)
            Circle().stroke(Palette.giltDark.opacity(0.45), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
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
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.well)
                Capsule().strokeBorder(Palette.giltDark.opacity(0.5), lineWidth: 0.5)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
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
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments.indices, id: \.self) { i in
                    Rectangle().fill(segments[i].color)
                        .frame(width: max(0, geo.size.width * min(max(segments[i].fraction, 0), 1) - 1))
                }
                Spacer(minLength: 0)
            }
            .background(Palette.well)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Palette.giltDark.opacity(0.5), lineWidth: 0.5))
        }
        .frame(height: height)
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
            ZStack {
                if filled, let first = points.first, let last = points.last {
                    Path { p in
                        p.move(to: CGPoint(x: first.x, y: geo.size.height))
                        p.addLines(points)
                        p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.38), tint.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                }
                Path { p in p.addLines(points) }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
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
}

/// A sparkline set in a recessed "well", like a small painting within the frame.
struct ChartWell<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 4).fill(Palette.well.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.giltDark.opacity(0.55), lineWidth: 0.6))
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
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .serif))
            .foregroundStyle(Palette.gilt)
            .tracking(1.6)
    }
}

/// A wax-seal style status badge.
struct StatusPill: View {
    var status: OverallStatus
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbol).font(.system(size: 10, weight: .bold))
            Text(status.title).font(Typo.title(13))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .background(Capsule().fill(Palette.well))
        .overlay(Capsule().strokeBorder(status.color.opacity(0.7), lineWidth: 1))
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
