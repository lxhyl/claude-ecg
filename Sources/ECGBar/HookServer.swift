import Foundation
import Network

final class HookServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ecgbar.hookserver")
    private let onHeartbeat: (String) -> Void

    init(onHeartbeat: @escaping (String) -> Void) {
        self.onHeartbeat = onHeartbeat
    }

    func start(port: UInt16 = 7823) throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(on: conn, accumulated: Data())
    }

    private func receive(on conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if let headerEnd = buffer.range(of: Data([0x0d, 0x0a, 0x0d, 0x0a])) {
                let headerBytes = buffer.subdata(in: 0..<headerEnd.lowerBound)
                if let header = String(data: headerBytes, encoding: .utf8),
                   let firstLine = header.split(separator: "\r\n", omittingEmptySubsequences: false).first {
                    let parts = firstLine.split(separator: " ")
                    if parts.count >= 2 {
                        self.respond(to: conn, method: String(parts[0]), path: String(parts[1]))
                        return
                    }
                }
                self.write404(conn)
                return
            }

            if error != nil || isComplete {
                conn.cancel()
                return
            }
            self.receive(on: conn, accumulated: buffer)
        }
    }

    private func respond(to conn: NWConnection, method: String, path: String) {
        var route = path
        var query: [String: String] = [:]
        if let qIdx = path.firstIndex(of: "?") {
            route = String(path[..<qIdx])
            let qstr = path[path.index(after: qIdx)...]
            for pair in qstr.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    query[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                }
            }
        }

        switch (method, route) {
        case ("POST", "/heartbeat"):
            let event = query["e"] ?? "unknown"
            onHeartbeat(event)
            write204(conn)
        case ("POST", "/refresh"):
            onHeartbeat("refresh")
            write204(conn)
        case ("GET", "/healthz"):
            writeText(conn, status: "200 OK", body: "ECGBar OK\n")
        default:
            write404(conn)
        }
    }

    private func write204(_ conn: NWConnection) {
        send(conn, raw: "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    }

    private func write404(_ conn: NWConnection) {
        send(conn, raw: "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    }

    private func writeText(_ conn: NWConnection, status: String, body: String) {
        let bytes = Array(body.utf8).count
        send(conn, raw: "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(bytes)\r\nConnection: close\r\n\r\n\(body)")
    }

    private func send(_ conn: NWConnection, raw: String) {
        conn.send(content: raw.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
