import Foundation
import Combine

// MARK: - Preferences

enum Prefs {
    static let refreshInterval = "refreshInterval"
    static let runInBackground = "runInBackground"
    static let legacyShowDockIcon = "showDockIcon"

    static let glanceCorner = "glanceCorner"             // GlanceCorner raw value
    static let glanceDelay = "glanceDelay"               // seconds the pointer must rest in the corner
    static let glanceShowApps = "glanceShowApps"

    static let showApps = "showApps"
    static let groupApps = "groupApps"
    static let topAppCount = "topAppCount"

    static let showSystem = "showSystem"
    static let showCPU = "showCPU"
    static let showMemory = "showMemory"
    static let showDisk = "showDisk"
    static let showPower = "showPower"
    static let showNetwork = "showNetwork"
    static let showPerCore = "showPerCore"

    static let mbIcon = "mbIcon"
    static let mbCPU = "mbCPU"
    static let mbMemory = "mbMemory"
    static let mbNetwork = "mbNetwork"
    static let mbBattery = "mbBattery"
    static let mbPower = "mbPower"
    static let mbDisk = "mbDisk"

    static let cpuWarn = "cpuWarn"                       // %
    static let diskFreeWarn = "diskFreeWarn"             // % free
    static let batteryHealthWarn = "batteryHealthWarn"   // % of design capacity
    static let batteryTempWarn = "batteryTempWarn"       // °C
    static let swapWarnGB = "swapWarnGB"                 // GB

    static let useFahrenheit = "useFahrenheit"
    static let networkInBits = "networkInBits"

    static func registerDefaults() {
        // v1 had "Show icon in Dock"; turning that off meant the same as running in the background.
        // (Checked before registering defaults, which would otherwise mask "never set".)
        let d = UserDefaults.standard
        if d.object(forKey: runInBackground) == nil, d.object(forKey: legacyShowDockIcon) != nil {
            d.set(!d.bool(forKey: legacyShowDockIcon), forKey: runInBackground)
        }
        d.register(defaults: [
            refreshInterval: 2.0,
            runInBackground: false,
            glanceCorner: GlanceCorner.bottomLeft.rawValue,
            glanceDelay: 0.35,
            glanceShowApps: true,
            showApps: true, groupApps: true, topAppCount: 5,
            showSystem: true, showCPU: true, showMemory: true, showDisk: true,
            showPower: true, showNetwork: true, showPerCore: true,
            mbIcon: true, mbCPU: true, mbMemory: false, mbNetwork: true,
            mbBattery: false, mbPower: false, mbDisk: false,
            cpuWarn: 85.0, diskFreeWarn: 10.0, batteryHealthWarn: 80.0,
            batteryTempWarn: 40.0, swapWarnGB: 4.0,
            useFahrenheit: false, networkInBits: false
        ])
    }

    static func double(_ key: String) -> Double { UserDefaults.standard.double(forKey: key) }
}

// MARK: - Monitor

final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published private(set) var cpu = CPUMetrics()
    @Published private(set) var memory = MemoryMetrics()
    @Published private(set) var volumes: [DiskVolume] = []
    @Published private(set) var diskIO = DiskIO()
    @Published private(set) var diskHealth = DiskHealth()
    @Published private(set) var battery = BatteryMetrics()
    @Published private(set) var network = NetworkMetrics()
    @Published private(set) var system = SystemInfo()
    @Published private(set) var topCPU: [AppUsage] = []
    @Published private(set) var topMemory: [AppUsage] = []
    @Published private(set) var history = MetricHistory()
    @Published private(set) var issues: [HealthIssue] = []
    @Published private(set) var lastUpdated: Date?

    private let queue = DispatchQueue(label: "SystemMonitor.collect", qos: .utility)
    private let healthQueue = DispatchQueue(label: "SystemMonitor.health", qos: .background)
    private let collector = Collector()
    private var timer: DispatchSourceTimer?
    private var healthTimer: Timer?

    var overallStatus: OverallStatus {
        if issues.contains(where: { $0.level == .critical }) { return .critical }
        return issues.isEmpty ? .healthy : .attention
    }

    func start(interval: Double? = nil) {
        let seconds = max(0.5, interval ?? Prefs.double(Prefs.refreshInterval))
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: seconds, leeway: .milliseconds(150))
        let collector = self.collector
        t.setEventHandler { [weak self] in
            let snapshot = collector.collect()
            DispatchQueue.main.async { self?.apply(snapshot) }
        }
        t.resume()
        timer = t

        if healthTimer == nil {
            refreshDiskHealth()
            healthTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                self?.refreshDiskHealth()
            }
        }
    }

    func refreshDiskHealth() {
        healthQueue.async { [weak self] in
            let health = DiskHealthReader.read()
            DispatchQueue.main.async {
                self?.diskHealth = health
                self?.evaluate()
            }
        }
        let collector = self.collector
        queue.async { collector.forceVolumeRefresh() }
    }

    private func apply(_ s: Snapshot) {
        cpu = s.cpu
        memory = s.memory
        if let v = s.volumes { volumes = v }
        diskIO = s.diskIO
        battery = s.battery
        network = s.network
        system = s.system
        topCPU = s.topCPU
        topMemory = s.topMemory

        var h = history
        h.push(s.cpu.total, \.cpu)
        h.push(s.memory.usedFraction, \.memory)
        h.push(s.network.downRate, \.netDown)
        h.push(s.network.upRate, \.netUp)
        h.push(s.diskIO.readRate, \.diskRead)
        h.push(s.diskIO.writeRate, \.diskWrite)
        h.push(s.battery.systemPowerW ?? abs(s.battery.batteryPowerW ?? 0), \.power)
        history = h

        lastUpdated = Date()
        evaluate()
    }

    /// Builds the list of health issues from the current readings and user thresholds.
    private func evaluate() {
        var found: [HealthIssue] = []

        let recent = history.cpu.suffix(5)
        if recent.count >= 3 {
            let avg = recent.reduce(0, +) / Double(recent.count)
            if avg * 100 >= Prefs.double(Prefs.cpuWarn) {
                found.append(.init(level: .warning, message: "Sustained CPU load at \(Int(avg * 100))%"))
            }
        }

        switch memory.pressureLevel {
        case 4: found.append(.init(level: .critical, message: "Memory pressure is critical"))
        case 2: found.append(.init(level: .warning, message: "Memory pressure is elevated"))
        default: break
        }
        let swapGB = Double(memory.swapUsed) / 1_073_741_824
        if swapGB >= Prefs.double(Prefs.swapWarnGB) {
            found.append(.init(level: .warning, message: String(format: "Swap usage is %.1f GB", swapGB)))
        }

        let freeWarn = Prefs.double(Prefs.diskFreeWarn)
        for v in volumes {
            let freePct = v.freeFraction * 100
            if freePct < freeWarn {
                found.append(.init(level: freePct < freeWarn / 2 ? .critical : .warning,
                                   message: "\(v.name) has only \(Int(freePct))% free"))
            }
        }
        if diskHealth.smartStatus.lowercased().contains("fail") {
            found.append(.init(level: .critical, message: "Disk SMART status: \(diskHealth.smartStatus)"))
        }
        if let wear = diskHealth.wearPercent, wear >= 80 {
            found.append(.init(level: .warning, message: "SSD wear is at \(wear)%"))
        }
        if let errors = diskHealth.mediaErrors, errors > 0 {
            found.append(.init(level: .warning, message: "SSD reports \(errors) media errors"))
        }

        if battery.present {
            if let health = battery.healthFraction, health * 100 < Prefs.double(Prefs.batteryHealthWarn) {
                found.append(.init(level: .warning, message: "Battery health at \(Int(health * 100))% of design"))
            }
            if let condition = battery.condition, condition != "Good" {
                found.append(.init(level: .warning, message: "Battery condition: \(condition)"))
            }
            if let t = battery.temperatureC, t >= Prefs.double(Prefs.batteryTempWarn) {
                found.append(.init(level: .warning, message: String(format: "Battery temperature is %.0f °C", t)))
            }
        }

        switch system.thermalState {
        case .serious: found.append(.init(level: .warning, message: "Mac is thermally throttling"))
        case .critical: found.append(.init(level: .critical, message: "Thermal state is critical"))
        default: break
        }

        issues = found
    }
}

// MARK: - Formatting

enum Fmt {
    static func percent(_ fraction: Double, digits: Int = 0) -> String {
        String(format: "%.\(digits)f%%", fraction * 100)
    }

    static func bytes(_ value: UInt64, style: ByteCountFormatter.CountStyle = .memory) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: style)
    }

    static func disk(_ value: UInt64) -> String { bytes(value, style: .file) }

    static func rate(_ bytesPerSecond: Double, bits: Bool) -> String {
        var v = bits ? bytesPerSecond * 8 : bytesPerSecond
        let units = bits ? ["b/s", "Kb/s", "Mb/s", "Gb/s"] : ["B/s", "KB/s", "MB/s", "GB/s"]
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        return String(format: (i > 0 && v < 10) ? "%.1f %@" : "%.0f %@", v, units[i])
    }

    /// Short form for the menu bar, e.g. "1.2M".
    static func compactRate(_ bytesPerSecond: Double, bits: Bool) -> String {
        var v = bits ? bytesPerSecond * 8 : bytesPerSecond
        let units = bits ? ["b", "K", "M", "G"] : ["B", "K", "M", "G"]
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        return String(format: (i > 0 && v < 10) ? "%.1f%@" : "%.0f%@", v, units[i])
    }

    static func temperature(_ celsius: Double, fahrenheit: Bool) -> String {
        fahrenheit ? String(format: "%.1f °F", celsius * 9 / 5 + 32) : String(format: "%.1f °C", celsius)
    }

    static func watts(_ w: Double) -> String { String(format: "%.1f W", w) }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let d = total / 86_400, h = (total % 86_400) / 3600, m = (total % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func minutes(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
