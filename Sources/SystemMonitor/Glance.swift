import SwiftUI
import AppKit

// MARK: - Hot corner

/// macOS doesn't let third-party apps appear in System Settings › Hot Corners, so CorMon
/// watches the pointer itself (no special permissions needed) and opens the glance panel
/// when it rests in the chosen corner.
enum GlanceCorner: Int, CaseIterable, Identifiable {
    case off = 0, topLeft, topRight, bottomLeft, bottomRight

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }

    func contains(_ p: NSPoint, in frame: NSRect) -> Bool {
        let tolerance: CGFloat = 4
        guard p.x >= frame.minX - 1, p.x <= frame.maxX + 1,
              p.y >= frame.minY - 1, p.y <= frame.maxY + 1 else { return false }
        let left = p.x <= frame.minX + tolerance
        let right = p.x >= frame.maxX - tolerance - 1
        let bottom = p.y <= frame.minY + tolerance
        let top = p.y >= frame.maxY - tolerance - 1
        switch self {
        case .off: return false
        case .topLeft: return top && left
        case .topRight: return top && right
        case .bottomLeft: return bottom && left
        case .bottomRight: return bottom && right
        }
    }
}

// MARK: - Opening SwiftUI windows from AppKit

/// Lets AppKit code (the glance panel) open SwiftUI windows by id.
final class WindowRouter {
    static let shared = WindowRouter()
    private var opener: OpenWindowAction?

    func register(_ action: OpenWindowAction) { opener = action }

    func open(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        opener?(id: id)
    }
}

// MARK: - Panel controller

final class GlancePanelController: NSObject {
    static let shared = GlancePanelController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var watchTimer: Timer?
    private var clickMonitor: Any?
    private var cornerEnteredAt: Date?
    private var lastInsideAt = Date()
    private var openedFromCorner = false
    private(set) var isVisible = false

    /// Starts polling the pointer position (10×/second; negligible CPU).
    func startWatching() {
        watchTimer?.invalidate()
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    func toggle() {
        isVisible ? hide() : show(corner: nil, screen: nil, fromCorner: false)
    }

    private func tick() {
        let corner = GlanceCorner(rawValue: UserDefaults.standard.integer(forKey: Prefs.glanceCorner)) ?? .off
        let mouse = NSEvent.mouseLocation

        var inCorner = false
        var cornerScreen: NSScreen?
        if corner != .off {
            for screen in NSScreen.screens where corner.contains(mouse, in: screen.frame) {
                inCorner = true
                cornerScreen = screen
                break
            }
        }

        if inCorner {
            let enteredAt = cornerEnteredAt ?? Date()
            cornerEnteredAt = enteredAt
            let delay = UserDefaults.standard.double(forKey: Prefs.glanceDelay)
            if !isVisible, Date().timeIntervalSince(enteredAt) >= delay {
                show(corner: corner, screen: cornerScreen, fromCorner: true)
            }
        } else {
            cornerEnteredAt = nil
        }

        // A corner-opened panel stays while the pointer is over it, and fades once it leaves.
        if isVisible, openedFromCorner, let panel {
            if inCorner || panel.frame.insetBy(dx: -20, dy: -20).contains(mouse) {
                lastInsideAt = Date()
            } else if Date().timeIntervalSince(lastInsideAt) > 0.6 {
                hide()
            }
        }
    }

    func show(corner: GlanceCorner?, screen: NSScreen?, fromCorner: Bool) {
        let panel = self.panel ?? makePanel()
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        // The SwiftUI content only exists while the panel is on screen, so a hidden
        // panel doesn't keep re-rendering every sample.
        let host = hostingView ?? makeHostingView()
        if panel.contentView !== host { panel.contentView = host }
        host.layoutSubtreeIfNeeded()
        panel.setContentSize(host.fittingSize)
        let size = panel.frame.size
        let area = screen.visibleFrame
        let margin: CGFloat = 4
        let origin: NSPoint
        switch corner ?? .topRight {
        case .topLeft: origin = NSPoint(x: area.minX + margin, y: area.maxY - size.height - margin)
        case .bottomLeft: origin = NSPoint(x: area.minX + margin, y: area.minY + margin)
        case .bottomRight: origin = NSPoint(x: area.maxX - size.width - margin, y: area.minY + margin)
        case .topRight, .off: origin = NSPoint(x: area.maxX - size.width - margin, y: area.maxY - size.height - margin)
        }
        panel.setFrameOrigin(origin)

        openedFromCorner = fromCorner
        lastInsideAt = Date()
        isVisible = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }

        // A panel opened by hand closes when you click anywhere else.
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, self.isVisible, !self.openedFromCorner else { return }
                if let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) { self.hide() }
            }
        }
    }

    func hide() {
        guard let panel, isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isVisible else { return }
            panel.orderOut(nil)
            panel.contentView = nil
            self.hostingView = nil
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: 480),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false                 // the SwiftUI frame draws its own shadow
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        self.panel = panel
        return panel
    }

    private func makeHostingView() -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(
            GlanceView(close: { [weak self] in self?.hide() })
                .environmentObject(SystemMonitor.shared)
        ))
        hostingView = host
        return host
    }
}

// MARK: - Glance view

struct GlanceView: View {
    @EnvironmentObject var m: SystemMonitor
    @AppStorage(Prefs.glanceShowApps) private var showApps = true
    @AppStorage(Prefs.networkInBits) private var inBits = false
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Fleuron()
            gauges
            network
            if !m.issues.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(m.issues.prefix(2)) { issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .font(Typo.body(11.5, .medium))
                            .foregroundStyle(issue.level == .critical ? Palette.danger : Palette.warn)
                            .lineLimit(1)
                    }
                }
            }
            if showApps {
                Fleuron()
                HStack(alignment: .top, spacing: 14) {
                    AppList(title: "Processor", apps: Array(m.topCPU.prefix(3)), metric: .cpu, compact: true)
                    AppList(title: "Memory", apps: Array(m.topMemory.prefix(3)), metric: .memory, compact: true)
                }
                .frame(height: 78, alignment: .top)
            }
            footer
        }
        .padding(16)
        .frame(width: 330)
        .background(
            CanvasBackground()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        )
        .giltFrame(cornerRadius: 10)
        .padding(14)                     // room for the shadow inside the transparent panel
        .cormonStyle()
        .onAppear { m.setViewer("glance", visible: true) }
        .onDisappear { m.setViewer("glance", visible: false) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(nsImage: HeartMonitorGlyph.normal)
                .renderingMode(.template)
                .foregroundStyle(Palette.giltLight)
            VStack(alignment: .leading, spacing: 0) {
                Text("CorMon").font(Typo.title(18)).foregroundStyle(Palette.giltLight)
                Text("up \(Fmt.duration(m.system.uptime)) · thermal \(m.system.thermalState.label.lowercased())")
                    .font(Typo.titleItalic(11)).foregroundStyle(Palette.parchment)
            }
            Spacer()
            StatusPill(status: m.overallStatus)
        }
    }

    private var gauges: some View {
        HStack(spacing: 6) {
            MiniGauge(label: "CPU", value: Fmt.percent(m.cpu.total), fraction: m.cpu.total, tint: .cpuTint)
            MiniGauge(label: "Memory", value: Fmt.percent(m.memory.usedFraction),
                      fraction: m.memory.usedFraction, tint: .memoryTint)
            if m.battery.present {
                MiniGauge(label: m.battery.isCharging ? "Charging" : "Battery", value: "\(m.battery.percent)%",
                          fraction: Double(m.battery.percent) / 100, tint: .powerTint)
            }
            if let root = m.volumes.first {
                MiniGauge(label: "Disk free", value: Fmt.disk(root.available),
                          fraction: root.usedFraction, tint: .diskTint)
            }
        }
    }

    private var network: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("↓ \(Fmt.rate(m.network.downRate, bits: inBits))").foregroundStyle(Color.networkTint)
                Text("↑ \(Fmt.rate(m.network.upRate, bits: inBits))").foregroundStyle(Color.uploadTint)
            }
            .font(Typo.numeral(12))
            .frame(width: 94, alignment: .leading)
            let top = max(m.history.netDown.max() ?? 0, m.history.netUp.max() ?? 0, 1024)
            ChartWell(height: 34) {
                ZStack {
                    Sparkline(values: m.history.netDown, maxValue: top, tint: .networkTint)
                    Sparkline(values: m.history.netUp, maxValue: top, tint: .uploadTint, filled: false)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let w = m.battery.systemPowerW {
                Text("\(Fmt.watts(w)) draw").font(Typo.titleItalic(11)).foregroundStyle(Palette.parchment)
            }
            Spacer()
            Button("Dashboard") {
                close()
                WindowRouter.shared.open("dashboard")
            }
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
            }
            .help("Close")
        }
        .buttonStyle(.borderless)
        .font(Typo.body(12, .medium))
        .foregroundStyle(Palette.gilt)
    }
}

struct MiniGauge: View {
    var label: String
    var value: String
    var fraction: Double
    var tint: Color

    var body: some View {
        VStack(spacing: 4) {
            RingGauge(fraction: fraction, tint: tint, lineWidth: 5) {
                Text(value)
                    .font(Typo.numeral(11))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 3)
            }
            .frame(width: 62, height: 62)
            Text(label).font(Typo.titleItalic(11)).foregroundStyle(Palette.parchment).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
