import Foundation
import Network

/// TCP server trong iPhone: PC kết nối tới (qua Wi-Fi hoặc đường hầm USB) và nhận mỗi giây 1 dòng JSON.
final class MonitorServer {

    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "iphonemonitor.server")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var statusText = "Đang khởi động..."

    /// (trạng thái, số PC đang kết nối) - được gọi từ queue nội bộ.
    var onStatus: ((String, Int) -> Void)?

    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() {
        queue.async { [weak self] in self?.startListener() }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.listener?.cancel()
            self.listener = nil
            for c in self.connections.values { c.cancel() }
            self.connections.removeAll()
        }
    }

    /// Gửi 1 dòng (đã có "\n") tới mọi PC đang kết nối.
    func broadcast(_ line: Data) {
        queue.async { [weak self] in
            guard let self = self else { return }
            for c in self.connections.values {
                c.send(content: line, completion: .contentProcessed({ _ in }))
            }
        }
    }

    // MARK: - Nội bộ (chạy trên queue)

    private func startListener() {
        listener?.cancel()
        let p = port
        do {
            let l = try NWListener(using: .tcp, on: p)
            // Quảng bá Bonjour -> iOS hiện hộp thoại xin quyền "Mạng cục bộ"
            l.service = NWListener.Service(name: "iPhoneMonitor", type: "_iphonemonitor._tcp")

            l.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.statusText = "Đang lắng nghe cổng \(p.rawValue)"
                    self.report()
                case .failed(let err):
                    self.statusText = "Lỗi: \(err.localizedDescription). Thử lại..."
                    self.report()
                    self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startListener() }
                case .waiting(let err):
                    self.statusText = "Chờ mạng/quyền: \(err.localizedDescription)"
                    self.report()
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            l.start(queue: queue)
            listener = l
        } catch {
            statusText = "Không mở được cổng \(p.rawValue): \(error.localizedDescription)"
            report()
        }
    }

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.remove(id)
            default:
                break
            }
        }
        connections[id] = conn
        conn.start(queue: queue)
        receiveLoop(conn, id)
        report()
    }

    /// Chỉ để phát hiện PC ngắt kết nối (không xử lý dữ liệu PC gửi lên).
    private func receiveLoop(_ conn: NWConnection, _ id: ObjectIdentifier) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, isComplete, error in
            if isComplete || error != nil {
                conn.cancel()
                self?.remove(id)
                return
            }
            self?.receiveLoop(conn, id)
        }
    }

    private func remove(_ id: ObjectIdentifier) {
        if connections.removeValue(forKey: id) != nil { report() }
    }

    private func report() {
        onStatus?(statusText, connections.count)
    }
}
