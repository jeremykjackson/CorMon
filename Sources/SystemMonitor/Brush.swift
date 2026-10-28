import SwiftUI

// Painterly primitives for the Canvas (V2) look. Every shape is deterministic (seeded),
// so a stroke keeps its character between refreshes instead of shimmering.

enum Noise {
    static func hash(_ i: Int, _ seed: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: i &* 0x27D4_EB2D &+ seed &* 0x1656_67B1)
        h ^= h >> 15; h = h &* 0x85EB_CA6B
        h ^= h >> 13; h = h &* 0xC2B2_AE35
        h ^= h >> 16
        return Double(h % 10_000) / 10_000
    }

    /// Smooth value noise in 0...1.
    static func value(_ x: Double, seed: Int) -> Double {
        let fl = floor(x)
        let i = Int(fl)
        let f = x - fl
        let t = f * f * (3 - 2 * f)
        let a = hash(i, seed), b = hash(i + 1, seed)
        return a + (b - a) * t
    }

    /// Two-octave noise in -1...1.
    static func fbm(_ x: Double, seed: Int) -> Double {
        (value(x, seed: seed) * 0.65 + value(x * 2.7, seed: seed &+ 17) * 0.35) * 2 - 1
    }
}

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A single loaded-brush swipe filling its rect: ragged edges, a slight wander, a blunt start and a dry, tapered end.
struct BrushStroke: Shape {
    var seed = 1
    var roughness: CGFloat = 0.22
    var vertical = false

    func path(in rect: CGRect) -> Path {
        let length = vertical ? rect.height : rect.width
        let thick = vertical ? rect.width : rect.height
        guard length > 1, thick > 0.5 else { return Path() }
        let n = max(10, Int(length / 4))
        let half = thick / 2

        func map(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            vertical ? CGPoint(x: rect.minX + across, y: rect.maxY - along)
                     : CGPoint(x: rect.minX + along, y: rect.minY + across)
        }

        var edgeA: [CGPoint] = [], edgeB: [CGPoint] = []
        for k in 0...n {
            let t = CGFloat(k) / CGFloat(n)
            let along = t * length
            let s = Double(along) / 38                       // noise in absolute units → stable as length animates
            let startEnv = min(1, along / (thick * 0.8))
            let endEnv = min(1, (length - along) / (thick * 1.8))
            let env = pow(max(0, min(startEnv, endEnv)), 0.5)
            let drift = CGFloat(Noise.fbm(s * 0.6, seed: seed)) * half * 0.16
            let ra = 1 - roughness * CGFloat(abs(Noise.fbm(s * 3.3, seed: seed &+ 11)))
            let rb = 1 - roughness * CGFloat(abs(Noise.fbm(s * 3.3, seed: seed &+ 23)))
            edgeA.append(map(along, half - half * env * ra + drift))
            edgeB.append(map(along, half + half * env * rb + drift))
        }
        var p = Path()
        p.move(to: edgeA[0])
        p.addLines(edgeA)
        p.addLines(edgeB.reversed())
        p.closeSubpath()
        return p
    }
}

/// Fine bristle streaks running along a stroke; mask with the stroke for texture.
struct BristleStreaks: Shape {
    var seed = 1
    var count = 7
    var vertical = false

    func path(in rect: CGRect) -> Path {
        let length = vertical ? rect.height : rect.width
        let thick = vertical ? rect.width : rect.height
        guard length > 2 else { return Path() }
        var p = Path()
        for i in 0..<count {
            let across = thick * CGFloat(0.12 + 0.76 * Noise.hash(i, seed &+ 3))
            let a0 = length * CGFloat(0.02 + 0.18 * Noise.hash(i, seed &+ 5))
            let a1 = length * CGFloat(0.55 + 0.45 * Noise.hash(i, seed &+ 7))
            guard a1 > a0 else { continue }
            let steps = max(4, Int((a1 - a0) / 6))
            for k in 0...steps {
                let along = a0 + (a1 - a0) * CGFloat(k) / CGFloat(steps)
                let wob = CGFloat(Noise.fbm(Double(along) / 22, seed: seed &+ i)) * thick * 0.06
                let pt = vertical ? CGPoint(x: rect.minX + across + wob, y: rect.maxY - along)
                                  : CGPoint(x: rect.minX + along, y: rect.minY + across + wob)
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
        return p
    }
}

/// A painted arc (an ensō when nearly closed). Angles in degrees, 0 = 12 o'clock, clockwise.
struct PaintedArc: Shape {
    var start: Double = 0
    var end: Double
    var thickness: CGFloat
    var seed = 1
    var radialShift: CGFloat = 0

    var animatableData: Double {
        get { end }
        set { end = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let span = end - start
        guard span > 0.5 else { return Path() }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2 - thickness / 2 - 2 + radialShift
        let n = max(16, Int(span / 2.5))
        let arcLen = CGFloat(span * .pi / 180) * r
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        for k in 0...n {
            let t = Double(k) / Double(n)
            let deg = start + span * t
            let along = CGFloat(t) * arcLen
            let env = pow(max(0, min(1, min(along / (thickness * 0.7), (arcLen - along) / (thickness * 2.2)))), 0.5)
            let s = deg / 24
            let w = thickness / 2 * env
            let wobble = CGFloat(Noise.fbm(s * 0.7, seed: seed)) * thickness * 0.10
            let ro = r + w * (1 - 0.25 * CGFloat(abs(Noise.fbm(s * 3, seed: seed &+ 5)))) + wobble
            let ri = r - w * (1 - 0.25 * CGFloat(abs(Noise.fbm(s * 3, seed: seed &+ 9)))) + wobble
            let a = (deg - 90) * .pi / 180
            outer.append(CGPoint(x: c.x + ro * CGFloat(cos(a)), y: c.y + ro * CGFloat(sin(a))))
            inner.append(CGPoint(x: c.x + ri * CGFloat(cos(a)), y: c.y + ri * CGFloat(sin(a))))
        }
        var p = Path()
        p.move(to: outer[0])
        p.addLines(outer)
        p.addLines(inner.reversed())
        p.closeSubpath()
        return p
    }
}

/// Thin bristle lines that follow a PaintedArc.
struct ArcStreaks: Shape {
    var start: Double = 0
    var end: Double
    var thickness: CGFloat
    var seed = 1
    var count = 4

    var animatableData: Double {
        get { end }
        set { end = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let span = end - start
        guard span > 8 else { return Path() }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2 - thickness / 2 - 2
        var p = Path()
        for i in 0..<count {
            let off = CGFloat(Noise.hash(i, seed) - 0.5) * thickness * 0.6
            let a0 = start + span * 0.04 + span * 0.12 * Noise.hash(i, seed &+ 2)
            let a1 = end - span * 0.25 * Noise.hash(i, seed &+ 4)
            guard a1 > a0 else { continue }
            var deg = a0
            var first = true
            while deg <= a1 {
                let rr = r + off + CGFloat(Noise.fbm(deg / 18, seed: seed &+ i)) * thickness * 0.05
                let a = (deg - 90) * .pi / 180
                let pt = CGPoint(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a)))
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                deg += 3
            }
        }
        return p
    }
}

/// An irregular dab of paint — used behind icons, pills and selections.
struct BrushBlob: Shape {
    var seed = 1
    var wobble: CGFloat = 0.12

    func path(in rect: CGRect) -> Path {
        let n = 64
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2 / (1 + wobble), ry = rect.height / 2 / (1 + wobble)
        let p1 = Noise.hash(1, seed) * 6.28, p2 = Noise.hash(2, seed) * 6.28, p3 = Noise.hash(3, seed) * 6.28
        var p = Path()
        for k in 0...n {
            let a = Double(k) / Double(n) * 2 * .pi
            let r = 1 + wobble * CGFloat(0.5 * sin(2 * a + p1) + 0.3 * sin(3 * a + p2) + 0.2 * sin(5 * a + p3))
            let pt = CGPoint(x: c.x + rx * r * CGFloat(cos(a)), y: c.y + ry * r * CGFloat(sin(a)))
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Composite painted controls

/// A horizontal (or vertical) painted meter: a faint wash for the track and a loaded stroke for the value.
struct PaintedBar: View {
    let value: Double
    let color: Color
    var seed = 3
    var thickness: CGFloat = 14
    var vertical = false

    var body: some View {
        GeometryReader { g in
            let v = CGFloat(min(max(value, 0), 1))
            let length = vertical ? g.size.height : g.size.width
            let filled = max(thickness * 1.2, length * v)
            ZStack(alignment: vertical ? .bottom : .leading) {
                BrushStroke(seed: seed &+ 100, roughness: 0.3, vertical: vertical)
                    .fill(color.opacity(0.13))
                ZStack {
                    BrushStroke(seed: seed, vertical: vertical).fill(color.opacity(0.85))
                    BristleStreaks(seed: seed, vertical: vertical)
                        .stroke(Color.white.opacity(0.30), lineWidth: 0.8)
                        .mask(BrushStroke(seed: seed, vertical: vertical))
                    BristleStreaks(seed: seed &+ 5, count: 5, vertical: vertical)
                        .stroke(color, lineWidth: 0.6)
                        .mask(BrushStroke(seed: seed, vertical: vertical))
                }
                .frame(width: vertical ? nil : filled, height: vertical ? filled : nil)
                .opacity(v > 0.002 ? 1 : 0)
            }
        }
        .frame(width: vertical ? thickness : nil, height: vertical ? nil : thickness)
    }
}

/// A painted ring gauge: an ensō-like wash for the track, layered pigment for the value.
struct PaintedRing: View {
    let value: Double
    let color: Color
    var lineWidth: CGFloat = 12
    var seed = 1

    var body: some View {
        let deg = 360 * min(max(value, 0), 1)
        ZStack {
            PaintedArc(start: -8, end: 340, thickness: lineWidth * 1.1, seed: seed &+ 50)
                .fill(color.opacity(0.13))
            PaintedArc(end: deg, thickness: lineWidth, seed: seed)
                .fill(color.opacity(0.85))
            PaintedArc(end: deg, thickness: lineWidth * 0.4, seed: seed &+ 9, radialShift: lineWidth * 0.14)
                .fill(Color.white.opacity(0.16))
            ArcStreaks(end: deg, thickness: lineWidth, seed: seed)
                .stroke(Color.white.opacity(0.28), lineWidth: 0.7)
            ArcStreaks(end: deg, thickness: lineWidth, seed: seed &+ 21, count: 3)
                .stroke(color, lineWidth: 0.6)
        }
    }
}
