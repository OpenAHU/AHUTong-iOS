import Foundation
import OSLog

struct RedactingLogger: Sendable {
    private let logger: Logger

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.openahu.ahutong", category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func notice(_ message: String) {
        let sanitized = Self.sanitize(message)
        logger.notice("\(sanitized, privacy: .public)")
        AppDiagnostics.shared.log(.runtime, sanitized)
    }

    static func sanitize(_ message: String) -> String {
        // Keep an internal comma-delimited marker until every expression has run.
        // In particular, the JSON-style field pass cannot quote a header placeholder.
        let redactionMarker = ",__AHUTONG_REDACTION_MARKER__,"
        let sensitiveName =
            #"(?:password|token|cookie|set-cookie|authorization|proxy-authorization|secret|student(?:id)?|phone|synjones-auth|ticket|x-ahutong-token|x-api-key|api[-_]?key)"#

        func decodePercentEscapesTolerantly(_ input: String) -> String {
            func hexValue(_ byte: UInt8) -> UInt8? {
                switch byte {
                case 48...57: byte - 48
                case 65...70: byte - 55
                case 97...102: byte - 87
                default: nil
                }
            }

            let inputBytes = Array(input.utf8)
            var outputBytes: [UInt8] = []
            outputBytes.reserveCapacity(inputBytes.count)
            var index = 0
            while index < inputBytes.count {
                if inputBytes[index] == 37,
                   index + 2 < inputBytes.count,
                   let high = hexValue(inputBytes[index + 1]),
                   let low = hexValue(inputBytes[index + 2]) {
                    outputBytes.append(high * 16 + low)
                    index += 3
                } else {
                    outputBytes.append(inputBytes[index])
                    index += 1
                }
            }
            return String(decoding: outputBytes, as: UTF8.self)
        }

        func redact(_ input: String) -> String {
            var redacted = input
            // Credential-bearing headers are fail-closed even when embedded in
            // another log line. Their grammar can contain arbitrary spaces and
            // commas (for example Digest), so retaining the suffix is unsafe.
            redacted = redacted.replacingOccurrences(
                of: #"(?i)(\b(?:authorization|proxy-authorization|cookie|set-cookie|synjones-auth|x-ahutong-token|x-api-key)\s*:\s*)[^\r\n]+"#,
                with: "$1\(redactionMarker)",
                options: .regularExpression
            )
            redacted = redacted.replacingOccurrences(
                of: #"(?i)(\b(?:authorization|proxy-authorization)\s*=\s*)[^\r\n]+"#,
                with: "$1\(redactionMarker)",
                options: .regularExpression
            )
            // Equals-style dumps and query fragments can still contain a
            // Basic/Bearer scheme followed by one credential token.
            redacted = redacted.replacingOccurrences(
                of: #"(?i)(\b(?:authorization|proxy-authorization|synjones-auth|x-ahutong-token)\s*[:=]\s*)(?:(?:bearer|basic)\s+)?[a-z0-9._~+/%=-]+"#,
                with: "$1\(redactionMarker)",
                options: .regularExpression
            )
            redacted = redacted.replacingOccurrences(
                of: "(?i)([\\\"']?\(sensitiveName)[\\\"']?\\s*:\\s*)(?:[\\\"'][^\\\"'\\r\\n]*[\\\"']|[^,}\\]\\s]+)",
                with: "$1\"\(redactionMarker)\"",
                options: .regularExpression
            )
            redacted = redacted.replacingOccurrences(
                of: "(?i)((?:\(sensitiveName))\\s*=)[^&\\s]+",
                with: "$1\(redactionMarker)",
                options: .regularExpression
            )
            redacted = redacted.replacingOccurrences(
                of: #"(?i)bearer\s+[a-z0-9._~+/=-]+"#,
                with: "Bearer \(redactionMarker)",
                options: .regularExpression
            )
            return redacted.replacingOccurrences(
                of: #"\b[0-9]{10,}\b"#,
                with: "<redacted-number>",
                options: .regularExpression
            )
        }

        var value = message.replacingOccurrences(
            of: "<redacted>",
            with: redactionMarker
        )
        for _ in 0..<3 {
            // Redact before decoding so an encoded delimiter such as `%20`
            // cannot turn one credential into a visible second token.
            value = redact(value)
            let decoded = decodePercentEscapesTolerantly(value)
            guard decoded != value else {
                break
            }
            value = decoded
        }
        value = redact(value)
        return value.replacingOccurrences(of: redactionMarker, with: "<redacted>")
    }
}

struct ReleaseDiagnostics: Equatable, Sendable {
    let version: String
    let build: String

    static func current(bundle: Bundle = .main) -> ReleaseDiagnostics {
        ReleaseDiagnostics(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "--",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "--"
        )
    }
}
