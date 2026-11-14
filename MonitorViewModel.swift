import Foundation
import SwiftUI
import UIKit

final class MonitorViewModel: ObservableObject {

    @Published var latest: Metrics?
    @Published var serverStatus = "Đang khởi động..."
    @Published var clients = 0
    @Published var localIP = "-"
    @Published var keepAwake = true {
        didSet { UIApplication.shared.isIdleTimerDisabled = keepAwake }
    }

    let port: UInt16 = 5050

    private let collector = MetricsCollector()
    private let server: MonitorServer
    private let encoder = JSONEncoder()
    private var timer: Timer?
    private var started = false

    init() {
        server = MonitorServer(port: 5050)
        server.onStatus = { [weak self] text, count in
            DispatchQueue.main.async {
                self?.serverStatus = text
                self?.clients = count
            }
        }
    }

    func start() {
        guard !started else { return }
        started = true

        UIDevice.current.isBatteryMonitoringEnabled = true
        UIApplication.shared.isIdleTimerDisabled = keepAwake

        collector.startObservingEvents()
        server.start()
        localIP = MetricsCollector.wifiIPv4() ?? "Chưa kết nối Wi-Fi"

        // Lấy mẫu 1 lần để khởi tạo bộ đếm CPU / mạng
        _ = collector.sample()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        let m = collector.sample()
        latest = m
        localIP = MetricsCollector.wifiIPv4() ?? "Chưa kết nối Wi-Fi"

        if clients > 0, var data = try? encoder.encode(m) {
            data.append(0x0A) // "\n"
            server.broadcast(data)
        }
    }
}
