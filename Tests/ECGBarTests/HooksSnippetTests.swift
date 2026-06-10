import XCTest
@testable import ECGBar

final class HooksSnippetTests: XCTestCase {
    func testSnippetIsValidJSONCoveringAllEvents() throws {
        let snippet = HooksSnippet.render(port: AppConfig.defaultPort)
        let object = try JSONSerialization.jsonObject(with: Data(snippet.utf8))
        let hooks = try XCTUnwrap((object as? [String: Any])?["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(HooksSnippet.events))
    }

    func testEveryEntryIsACurlCommandHook() throws {
        let snippet = HooksSnippet.render(port: AppConfig.defaultPort)
        let object = try JSONSerialization.jsonObject(with: Data(snippet.utf8))
        let hooks = try XCTUnwrap((object as? [String: Any])?["hooks"] as? [String: [[String: Any]]])
        for (event, matchers) in hooks {
            let hook = try XCTUnwrap((matchers.first?["hooks"] as? [[String: Any]])?.first, event)
            XCTAssertEqual(hook["type"] as? String, "command", event)
            let command = try XCTUnwrap(hook["command"] as? String, event)
            XCTAssertTrue(command.contains("heartbeat?e=\(event)"), event)
        }
    }

    func testSnippetUsesGivenPort() {
        let snippet = HooksSnippet.render(port: 9999)
        XCTAssertTrue(snippet.contains("localhost:9999"))
        XCTAssertFalse(snippet.contains("7823"))
    }
}
