import Foundation
import UIKit
import Darwin

/// Thu thập CPU / RAM / pin / nhiệt / đĩa / mạng. Gọi `sample()` mỗi giây từ main thread.
final class MetricsCollector {

    private var prevTicks: (UInt32, UInt32, UInt32, UInt32)?
    private var prevNet: (rx: UInt64, tx: UInt64)?
    private var prevNetTime: TimeInterval = 0
    private var pendingEvents: [String] = []
    private var observers: [NSObjectProtocol] = []

    // MARK: - Sự kiện (nóng máy, tiết kiệm pin, sạc...)

    func startObservingEvents() {
        let nc = NotificationCenter.default

        observers.append(nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.pendingEvents.append("Nhiệt độ đổi: \(Self.thermalString(ProcessInfo.processInfo.thermalState))")
        })

        observers.append(nc.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                        object: nil, queue: .main) { [weak self] _ in
            let on = ProcessInfo.processInfo.isLowPowerModeEnabled
            self?.pendingEvents.append("Chế độ tiết kiệm pin: \(on ? "BẬT" : "TẮT")")
        })

        observers.append(nc.addObserver(forName: UIDevice.batteryStateDidChangeNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.pendingEvents.append("Trạng thái pin: \(Self.batteryStateString(UIDevice.current.batteryState))")
        })

        observers.append(nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.pendingEvents.append("CẢNH BÁO: hệ thống thiếu RAM")
        })
    }

    // MARK: - Lấy mẫu

    func sample() -> Metrics {
        let now = Date().timeIntervalSince1970
        let device = UIDevice.current

        let mem = memory()
        let net = netBytes()
        var rxBps = 0.0, txBps = 0.0
        if let p = prevNet, prevNetTime > 0 {
            let dt = now - prevNetTime
            if dt > 0 {
                if net.rx >= p.rx { rxBps = Double(net.rx - p.rx) / dt }
                if net.tx >= p.tx { txBps = Double(net.tx - p.tx) / dt }
            }
        }
        prevNet = net
        prevNetTime = now

        let level = device.batteryLevel
        let (free, total) = disk()

        let events = pendingEvents
        pendingEvents.removeAll()

        return Metrics(
            time: now,
            deviceName: device.name,
            model: Self.modelIdentifier(),
            systemVersion: device.systemVersion,
            cpu: cpuUsage(),
            memUsed: mem.used,
            memTotal: ProcessInfo.processInfo.physicalMemory,
            appMem: mem.app,
            battery: level < 0 ? -1 : Int((level * 100).rounded()),
            charging: device.batteryState == .charging || device.batteryState == .full,
            batteryState: Self.batteryStateString(device.batteryState),
            thermal: Self.thermalString(ProcessInfo.processInfo.thermalState),
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            diskFree: free,
            diskTotal: total,
            rxBps: rxBps,
            txBps: txBps,
            uptime: ProcessInfo.processInfo.systemUptime,
            events: events
        )
    }

    // MARK: - CPU toàn hệ thống

    private func cpuUsage() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let cur = (info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3)
        defer { prevTicks = cur }
        guard let p = prevTicks else { return 0 }

        let user = Double(cur.0 &- p.0)
        let sys = Double(cur.1 &- p.1)
        let idle = Double(cur.2 &- p.2)
        let nice = Double(cur.3 &- p.3)
        let total = user + sys + idle + nice
        return total > 0 ? (user + sys + nice) / total * 100.0 : 0
    }

    // MARK: - RAM

    private func memory() -> (used: UInt64, app: UInt64) {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        var used: UInt64 = 0
        if r == KERN_SUCCESS {
            // active + wired + compressed ~ RAM đang dùng thực sự
            let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
            used = pages * UInt64(pageSize)
        }

        // RAM của riêng app này
        var tInfo = task_vm_info_data_t()
        var tCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &tInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(tCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &tCount)
            }
        }
        let app: UInt64 = kr == KERN_SUCCESS ? UInt64(tInfo.phys_footprint) : 0
        return (used, app)
    }

    // MARK: - Ổ đĩa

    private func disk() -> (Int64, Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return (0, 0) }
        let free = v.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(v.volumeTotalCapacity ?? 0)
        return (free, total)
    }

    // MARK: - Mạng (Wi-Fi "en*" + di động "pdp_ip*")

    private func netBytes() -> (rx: UInt64, tx: UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let name = String(cString: p.pointee.ifa_name)
            if let addr = p.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               name.hasPrefix("en") || name.hasPrefix("pdp_ip"),
               let data = p.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(d.ifi_ibytes)
                tx += UInt64(d.ifi_obytes)
            }
            ptr = p.pointee.ifa_next
        }
        return (rx, tx)
    }

    // MARK: - Tiện ích

    static func modelIdentifier() -> String {
        var sys = utsname()
        uname(&sys)
        return withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    static func thermalString(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    static func batteryStateString(_ s: UIDevice.BatteryState) -> String {
        switch s {
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        default: return "unknown"
        }
    }

    /// IPv4 Wi-Fi của iPhone (để nhập vào app PC khi dùng chế độ Wi-Fi).
    static func wifiIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let name = String(cString: p.pointee.ifa_name)
            if name == "en0", let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            ptr = p.pointee.ifa_next
        }
        return nil
    }
}
