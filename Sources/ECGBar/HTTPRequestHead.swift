import Foundation

/// A parsed HTTP/1.1 request line, e.g. `POST /heartbeat?e=Stop HTTP/1.1`.
///
/// ECGBar only routes on method + path + query string, so this is all the HTTP
/// it needs to understand.
struct HTTPRequestHead: Equatable {
    let method: String
    let route: String
    let query: [String: String]

    init?(requestLine: some StringProtocol) {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0])

        let target = parts[1]
        guard let queryStart = target.firstIndex(of: "?") else {
            route = String(target)
            query = [:]
            return
        }
        route = String(target[..<queryStart])

        var parsed: [String: String] = [:]
        for pair in target[target.index(after: queryStart)...].split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2, !kv[0].isEmpty else { continue }
            let value = String(kv[1])
            parsed[String(kv[0])] = value.removingPercentEncoding ?? value
        }
        query = parsed
    }
}
