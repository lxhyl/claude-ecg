import Foundation

enum AppConfig {
    static let version = "1.0.0"
    static let defaultPort: UInt16 = 7823
    static let repositoryURL = URL(string: "https://github.com/lxhyl/claude-ecg")!

    enum DefaultsKey {
        static let muteBeat = "muteBeat"
        static let muteAlarm = "muteAlarm"
        static let port = "port"
    }

    /// Listening port. Resolution order: `ECGBAR_PORT` environment variable,
    /// then the `port` user default (`defaults write ECGBar port -int 7900`),
    /// then 7823.
    static var port: UInt16 {
        if let raw = ProcessInfo.processInfo.environment["ECGBAR_PORT"],
           let parsed = UInt16(raw), parsed > 0 {
            return parsed
        }
        let stored = UserDefaults.standard.integer(forKey: DefaultsKey.port)
        if (1...65_535).contains(stored) {
            return UInt16(stored)
        }
        return defaultPort
    }
}
