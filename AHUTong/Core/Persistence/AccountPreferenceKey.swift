import CryptoKit
import Foundation

enum AccountPreferenceKey {
    static func make(_ name: String, userID: String) -> String {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = normalizedUserID.isEmpty ? "guest" : normalizedUserID
        let digest = SHA256.hash(data: Data("preferences:\(subject)".utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        return "account.\(digest).\(name)"
    }
}

enum RetiredPreferenceCleaner {
    private static let retiredKeys = ["evaluation.preset.v1"]

    static func clean(defaults: UserDefaults = .standard) {
        let keys = defaults.dictionaryRepresentation().keys
        for key in keys where retiredKeys.contains(where: { key == $0 || key.hasSuffix(".\($0)") }) {
            defaults.removeObject(forKey: key)
        }
    }
}
