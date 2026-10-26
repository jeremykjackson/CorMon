import SwiftUI
import AppKit

extension Color {
    static let cpuTint = Color.blue
    static let memoryTint = Color.purple
    static let diskTint = Color.orange
    static let powerTint = Color.green
    static let networkTint = Color.teal
    static let uploadTint = Color.pink
}

extension OverallStatus {
    var color: Color {
        switch self {
        case .healthy: return .green
        case .attention: return .orange
        case .critical: return .red
        }
    }
    var symbol: String {
        switch self {
        case .healthy: return "checkmark.seal.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
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
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        default: return .red
        }
    }
}

/// Green → yellow → red as a value approaches its warning threshold.
func loadColor(_ fraction: Double, warn: Double = 0.75, critical: Double = 0.9, base: Color) -> Color {
    if fraction >= critical { return .red }
    if fraction >= warn { return .orange }
    return base
}

// MARK: - Card

struct Card<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    var detail: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title).font(.headline)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.07)))
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
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            center
        }
        .padding(lineWidth / 2)
    }
}

struct BigValue: View {
    var value: String
    var caption: String
    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
    }
}

struct BarMeter: View {
    var fraction: Double
    var tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.15))
                Capsule().fill(tint)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    .animation(.easeOut(duration: 0.4), value: fraction)
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
            .background(Color.primary.opacity(0.08))
            .clipShape(Capsule())
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
                    .fill(LinearGradient(colors: [tint.opacity(0.30), tint.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                }
                Path { p in p.addLines(points) }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
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

// MARK: - Stats

struct Stat: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var color: Color? = nil
}

struct StatGrid: View {
    var stats: [Stat]
    var columns = 2

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: columns),
                  alignment: .leading, spacing: 10) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(stat.value)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(stat.color ?? .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

struct StatusPill: View {
    var status: OverallStatus
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbol).font(.system(size: 11, weight: .semibold))
            Text(status.title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.14), in: Capsule())
    }
}

struct LegendDot: View {
    var color: Color
    var text: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}
