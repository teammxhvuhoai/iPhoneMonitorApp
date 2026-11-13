import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: MonitorViewModel

    var body: some View {
        NavigationView {
            List {
                connectionSection
                if let m = vm.latest {
                    liveSection(m)
                    systemSection(m)
                }
                Section {
                    Toggle("Giữ màn hình luôn sáng", isOn: $vm.keepAwake)
                } footer: {
                    Text("iOS tạm dừng app khi ra màn hình chính hoặc khóa máy. Hãy để app ở phía trước khi giám sát.")
                }
            }
            .navigationTitle("iPhone Monitor")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Kết nối

    private var connectionSection: some View {
        Section("Kết nối với PC") {
            row("Trạng thái", vm.serverStatus)
            row("PC đang kết nối", "\(vm.clients)")
            row("IP Wi-Fi", vm.localIP)
            row("Cổng", "\(vm.port)")
        }
    }

    // MARK: - Live

    private func liveSection(_ m: Metrics) -> some View {
        Section("Thời gian thực") {
            gauge("CPU", value: m.cpu / 100.0, text: String(format: "%.0f%%", m.cpu))

            let ram = m.memTotal > 0 ? Double(m.memUsed) / Double(m.memTotal) : 0
            gauge("RAM", value: ram, text: "\(bytes(m.memUsed)) / \(bytes(m.memTotal))")

            if m.battery >= 0 {
                gauge("Pin", value: Double(m.battery) / 100.0,
                      text: "\(m.battery)%" + (m.charging ? " ⚡︎" : ""))
            }
            row("Mạng", "↓ \(speed(m.rxBps))   ↑ \(speed(m.txBps))")
        }
    }

    private func systemSection(_ m: Metrics) -> some View {
        Section("Hệ thống") {
            row("Máy", "\(m.deviceName) (\(m.model))")
            row("iOS", m.systemVersion)
            row("Nhiệt độ", thermalText(m.thermal))
            row("Tiết kiệm pin", m.lowPower ? "Bật" : "Tắt")
            row("Dung lượng trống", "\(bytes(UInt64(max(0, m.diskFree)))) / \(bytes(UInt64(max(0, m.diskTotal))))")
            row("RAM app này", bytes(m.appMem))
        }
    }

    // MARK: - Thành phần nhỏ

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func gauge(_ title: String, value: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(text).foregroundColor(.secondary)
            }
            ProgressView(value: min(max(value, 0), 1))
        }
        .padding(.vertical, 2)
    }

    private func bytes(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: b), countStyle: .memory)
    }

    private func speed(_ bps: Double) -> String {
        if bps < 1024 { return String(format: "%.0f B/s", bps) }
        if bps < 1_048_576 { return String(format: "%.1f KB/s", bps / 1024) }
        return String(format: "%.2f MB/s", bps / 1_048_576)
    }

    private func thermalText(_ s: String) -> String {
        switch s {
        case "nominal": return "Bình thường"
        case "fair": return "Hơi ấm"
        case "serious": return "NÓNG"
        case "critical": return "RẤT NÓNG"
        default: return s
        }
    }
}
