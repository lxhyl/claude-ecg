import XCTest
@testable import ECGBar

final class HTTPRequestHeadTests: XCTestCase {
    func testParsesHeartbeatRequestLine() {
        let head = HTTPRequestHead(requestLine: "POST /heartbeat?e=Stop HTTP/1.1")
        XCTAssertEqual(head?.method, "POST")
        XCTAssertEqual(head?.route, "/heartbeat")
        XCTAssertEqual(head?.query, ["e": "Stop"])
    }

    func testParsesPathWithoutQuery() {
        let head = HTTPRequestHead(requestLine: "GET /healthz HTTP/1.1")
        XCTAssertEqual(head?.method, "GET")
        XCTAssertEqual(head?.route, "/healthz")
        XCTAssertEqual(head?.query, [:])
    }

    func testPercentDecodesQueryValues() {
        let head = HTTPRequestHead(requestLine: "POST /heartbeat?e=Pre%20Tool HTTP/1.1")
        XCTAssertEqual(head?.query, ["e": "Pre Tool"])
    }

    func testKeepsEmptyQueryValue() {
        let head = HTTPRequestHead(requestLine: "POST /heartbeat?e= HTTP/1.1")
        XCTAssertEqual(head?.query, ["e": ""])
    }

    func testParsesMultipleQueryPairs() {
        let head = HTTPRequestHead(requestLine: "POST /heartbeat?a=1&b=2 HTTP/1.1")
        XCTAssertEqual(head?.query, ["a": "1", "b": "2"])
    }

    func testIgnoresPairsWithoutKeyOrEquals() {
        let head = HTTPRequestHead(requestLine: "POST /heartbeat?=x&flag&e=Stop HTTP/1.1")
        XCTAssertEqual(head?.query, ["e": "Stop"])
    }

    func testRejectsGarbage() {
        XCTAssertNil(HTTPRequestHead(requestLine: "GARBAGE"))
        XCTAssertNil(HTTPRequestHead(requestLine: ""))
    }
}
