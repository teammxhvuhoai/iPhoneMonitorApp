import Foundation

/// Gói dữ liệu gửi cho PC (JSON, mỗi dòng 1 gói). Tên khóa phải trùng với LiveMetrics.cs bên C#.
struct Metrics: Codable {
    var time: Double
    var deviceName: String
    var model: String
    var systemVersion: String

    var cpu: Double          // %
    var memUsed: UInt64      // bytes
    var memTotal: UInt64     // bytes
    var appMem: UInt64       // bytes (RAM của riêng app này)

    var battery: Int         // %, -1 = không rõ
    var charging: Bool
    var batteryState: String // unknown / unplugged / charging / full

    var thermal: String      // nominal / fair / serious / critical
    var lowPower: Bool

    var diskFree: Int64
    var diskTotal: Int64

    var rxBps: Double        // bytes/s
    var txBps: Double
    var uptime: Double       // giây

    var events: [String]
}
