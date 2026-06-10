import Foundation
import Network

/// Minimal single-purpose HTTP listener bound to 127.0.0.1.
///
/// Routes:
/// - `POST /heartbeat?e=<event>` — record a beat
/// - `POST /refresh` — legacy endpoint, treated as a generic heartbeat
/// - `GET /healthz` — liveness probe
final class HookServer {
    /// Requests are a single line plus a few headers; anything bigger is dropped.
    private static let maxRequestBytes = 16 * 1024

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ecgbar.hookserver")
    private let onHeartbeat: (String) -> Void

    init(onHeartbeat: @escaping (String) -> Void) {
        self.onHeartbeat = onHeartbeat
    }

    /// Starts listening on 127.0.0.1:`port`.
    ///
    /// NWListener reports a port already in use *asynchronously* via its state
    /// handler, not as a throw from the initializer — hence the `onFailure`
    /// callback, delivered on the main queue.
    func start(port: UInt16, onFailure: @escaping (Error) -> Void) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(integerLiteral: port)
        )
        let listener = try NWListener(using: params)
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                DispatchQueue.main.async { onFailure(error) }
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
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

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerBytes = buffer.subdata(in: 0..<headerEnd.lowerBound)
                if let header = String(data: headerBytes, encoding: .utf8),
                   let firstLine = header.split(separator: "\r\n", omittingEmptySubsequences: false).first,
                   let request = HTTPRequestHead(requestLine: firstLine) {
                    self.respond(to: conn, request: request)
                } else {
                    self.write404(conn)
                }
                return
            }

            guard error == nil, !isComplete, buffer.count <= Self.maxRequestBytes else {
                conn.cancel()
                return
            }
            self.receive(on: conn, accumulated: buffer)
        }
    }

    private func respond(to conn: NWConnection, request: HTTPRequestHead) {
        switch (request.method, request.route) {
        case ("POST", "/heartbeat"):
            onHeartbeat(request.query["e"] ?? "unknown")
            write204(conn)
        case ("POST", "/refresh"):
            onHeartbeat("refresh")
            write204(conn)
        case ("GET", "/healthz"):
            writeText(conn, status: "200 OK", body: "ECGBar \(AppConfig.version) OK\n")
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
        let bytes = body.utf8.count
        send(conn, raw: "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(bytes)\r\nConnection: close\r\n\r\n\(body)")
    }

    private func send(_ conn: NWConnection, raw: String) {
        conn.send(content: Data(raw.utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
