import Foundation

/// Generates the JSON snippet the user merges into `~/.claude/settings.json`.
enum HooksSnippet {
    /// Every Claude Code hook event ECGBar reacts to, in snippet order.
    static let events = [
        "SessionStart", "SessionEnd",
        "UserPromptSubmit",
        "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "SubagentStart", "SubagentStop",
        "Notification", "PermissionRequest", "PermissionDenied",
        "PreCompact", "PostCompact",
        "Stop", "StopFailure"
    ]

    static func render(port: UInt16) -> String {
        let entries = events.map { event in
            "    \"\(event)\": [{ \"hooks\": [{ \"type\": \"command\", \"command\": \"curl -s -X POST 'http://localhost:\(port)/heartbeat?e=\(event)' >/dev/null 2>&1 || true\" }] }]"
        }
        return "{\n  \"hooks\": {\n" + entries.joined(separator: ",\n") + "\n  }\n}\n"
    }
}
