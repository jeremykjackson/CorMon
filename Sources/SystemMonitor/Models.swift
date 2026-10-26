import Foundation

struct CPUMetrics {
    var total: Double = 0          // 0...1
    var user: Double = 0
    var system: Double = 0
    var perCore: [Double] = []
    var load1: Double = 0
    var load5: Double = 0
    var load15: Double = 0
    var coreCount: Int = 0
    var performanceCores: Int?
    var efficiencyCores: Int?
    var brand: String = ""
}

struct MemoryMetrics {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressureLevel: Int = 0     // 1 normal, 2 warning, 4 critical

    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct DiskVolume: Identifiable {
    var id: String { mountPath }
    var name: String
    var mountPath: String
    var total: UInt64
    var available: UInt64
    var isInternal: Bool
    var isRoot: Bool

    var used: UInt64 { total > available ? total - available : 0 }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var freeFraction: Double { 1 - usedFraction }
}

struct DiskIO {
    var readRate: Double = 0       // bytes/sec
    var writeRate: Double = 0
}

struct DiskHealth {
    var smartStatus: String = "Checking…"
    var mediaName: String = ""
    var wearPercent: Int?          // NVMe "percentage used"
    var availableSpare: Int?
    var dataWritten: UInt64?
    var dataRead: UInt64?
    var powerOnHours: Int?
    var powerCycles: Int?
    var unsafeShutdowns: Int?
    var mediaErrors: Int?
    var smartctlAvailable = false
    var checked = false
}

struct MetricHistory {
    static let capacity = 90
    var cpu: [Double] = []
    var memory: [Double] = []
    var netDown: [Double] = []
    var netUp: [Double] = []
    var diskRead: [Double] = []
    var diskWrite: [Double] = []
    var power: [Double] = []

    mutating func push(_ value: Double, _ path: WritableKeyPath<MetricHistory, [Double]>) {
        self[keyPath: path].append(value)
        let overflow = self[keyPath: path].count - Self.capacity
        if overflow > 0 { self[keyPath: path].removeFirst(overflow) }
    }
}

struct BatteryMetrics {
    var present = false
    var percent = 0
    var isCharging = false
    var externalConnected = false
    var fullyCharged = false
    var cycleCount: Int?
    var designCapacity: Int?       // mAh
    var maxCapacity: Int?          // mAh (current full-charge capacity)
    var currentCapacity: Int?      // mAh
    var condition: String?
    var temperatureC: Double?
    var voltage: Double?           // V
    var amperage: Double?          // A (negative = discharging)
    var systemPowerW: Double?      // whole-system draw (Apple Silicon telemetry)
    var adapterWatts: Int?
    var adapterName: String?
    var minutesRemaining: Int?
    var lowPowerMode = false

    var healthFraction: Double? {
        guard let d = designCapacity, let m = maxCapacity, d > 0 else { return nil }
        return Double(m) / Double(d)
    }
    var batteryPowerW: Double? {
        guard let v = voltage, let a = amperage else { return nil }
        return v * a
    }
    var stateText: String {
        if fullyCharged && externalConnected { return "Charged" }
        if isCharging { return "Charging" }
        if externalConnected { return "Plugged In" }
        return "On Battery"
    }
}

struct InterfaceRate: Identifiable {
    var id: String { name }
    var name: String
    var down: Double
    var up: Double
}

struct NetworkMetrics {
    var downRate: Double = 0
    var upRate: Double = 0
    var sessionDown: UInt64 = 0
    var sessionUp: UInt64 = 0
    var bootDown: UInt64 = 0
    var bootUp: UInt64 = 0
    var primaryInterface: String?
    var localIP: String?
    var wifiInterface: String?
    var wifiRSSI: Int?
    var wifiNoise: Int?
    var wifiTxRate: Double?
    var active: [InterfaceRate] = []
}

struct SystemInfo {
    var model = ""
    var chip = ""
    var osVersion = ""
    var hostName = ""
    var uptime: TimeInterval = 0
    var thermalState: ProcessInfo.ThermalState = .nominal
}

struct HealthIssue: Identifiable {
    enum Level { case warning, critical }
    let id = UUID()
    let level: Level
    let message: String
}

enum OverallStatus {
    case healthy, attention, critical
    var title: String {
        switch self {
        case .healthy: return "Healthy"
        case .attention: return "Needs Attention"
        case .critical: return "Critical"
        }
    }
}
