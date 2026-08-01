import CryptoKit
import Combine
import Foundation
import OSLog

struct GrayFeature: Equatable, Sendable {
    let key: String
    let title: String
    let description: String
    let rolloutPercentage: Int

    init(key: String, title: String, description: String, rolloutPercentage: Int) {
        precondition((0...100).contains(rolloutPercentage))
        self.key = key
        self.title = title
        self.description = description
        self.rolloutPercentage = rolloutPercentage
    }
}

enum GrayFeatures {
    static let homeEdit = GrayFeature(
        key: "home_edit",
        title: "首页编辑",
        description: "允许长按首页进入编辑态，并在小工具页显示编辑入口。",
        rolloutPercentage: 0
    )

    static let all = [homeEdit]
}

extension Notification.Name {
    static let grayFeatureOverrideChanged = Notification.Name("AHUTong.grayFeatureOverrideChanged")
}

@MainActor
final class GrayFeatureGateModel: ObservableObject {
    @Published private(set) var homeEditEnabled = false
    private let service = GrayReleaseService()

    func load(userID: String?, demo: Bool = false) async {
        let feature = GrayFeatures.homeEdit
        let stored = UserDefaults.standard.string(forKey: "debug.gray.\(feature.key)")
        let overrideMode = stored.flatMap(GrayOverride.init(rawValue:)) ?? .follow
        let diagnostics = ReleaseDiagnostics.current()
        let state: GrayFeatureState
        if demo {
            state = await service.localState(feature: feature, userID: userID, overrideMode: overrideMode)
        } else {
            state = await service.state(
                feature: feature,
                userID: userID,
                versionCode: Int(diagnostics.build) ?? 0,
                versionName: diagnostics.version,
                overrideMode: overrideMode
            )
        }
        homeEditEnabled = state.enabled
    }
}

enum GrayOverride: String, CaseIterable, Sendable {
    case follow = "follow"
    case enabled = "enabled"
    case disabled = "disabled"

    var label: String {
        switch self {
        case .follow: "跟随灰度"
        case .enabled: "强制开启"
        case .disabled: "强制关闭"
        }
    }
}

enum GrayDecisionSource: String, Sendable {
    case local
    case remote
    case debug
}

struct GrayFeatureState: Equatable, Sendable {
    let feature: GrayFeature
    let overrideMode: GrayOverride
    let bucket: Int
    let rolloutPercentage: Int
    let rolloutEnabled: Bool
    let enabled: Bool
    let source: GrayDecisionSource

    var reason: String {
        switch overrideMode {
        case .enabled: "Debug 强制开启"
        case .disabled: "Debug 强制关闭"
        case .follow:
            switch source {
            case .remote: enabled ? "服务端开启" : "服务端关闭"
            case .local: rolloutEnabled ? "本地兜底命中" : "本地兜底未命中"
            case .debug: enabled ? "Debug 强制开启" : "Debug 强制关闭"
            }
        }
    }
}

enum GrayRollout {
    static func isEnabled(rolloutPercentage: Int, bucket: Int) -> Bool {
        min(max(rolloutPercentage, 0), 100) > min(max(bucket, 0), 99)
    }

    static func bucket(featureKey: String, subjectKey: String) -> Int {
        let digest = SHA256.hash(data: Data("\(featureKey):\(subjectKey)".utf8))
        let bytes = Array(digest.prefix(4))
        let unsigned = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let signed = Int(Int32(bitPattern: unsigned))
        return ((signed % 100) + 100) % 100
    }

    static func subjectHash(userID: String?) -> String {
        let subject: String
        if let userID, !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            subject = "user:\(userID)"
        } else {
            // Do not create a persistent advertising-style device identifier.
            subject = "guest"
        }
        return SHA256.hash(data: Data(subject.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct RemoteGrayDecision: Decodable, Sendable {
    let enabled: Bool?
    let rolloutPercentage: Int?
    let bucket: Int?
}

actor GrayReleaseService {
    private let session: URLSession
    private let endpoint: URL

    init(
        session: URLSession? = nil,
        endpoint: URL = URL(string: "https://openahu.org/api/gray/check")!
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 5
            self.session = URLSession(configuration: configuration)
        }
        self.endpoint = endpoint
    }

    func state(
        feature: GrayFeature,
        userID: String?,
        versionCode: Int,
        versionName: String,
        overrideMode: GrayOverride = .follow
    ) async -> GrayFeatureState {
        let subject = GrayRollout.subjectHash(userID: userID)
        if overrideMode != .follow {
            return overriddenState(feature: feature, subject: subject, overrideMode: overrideMode)
        }

        do {
            let url = try Self.remoteURL(
                endpoint: endpoint,
                feature: feature.key,
                hashedSubject: subject,
                versionCode: versionCode,
                versionName: versionName
            )
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return fallbackState(feature: feature, subject: subject)
            }
            let decision = try JSONDecoder().decode(RemoteGrayDecision.self, from: data)
            guard let enabled = decision.enabled else {
                return fallbackState(feature: feature, subject: subject)
            }
            let percentage = min(max(decision.rolloutPercentage ?? feature.rolloutPercentage, 0), 100)
            let bucket = min(max(decision.bucket ?? GrayRollout.bucket(featureKey: feature.key, subjectKey: subject), 0), 99)
            return GrayFeatureState(
                feature: feature,
                overrideMode: .follow,
                bucket: bucket,
                rolloutPercentage: percentage,
                rolloutEnabled: GrayRollout.isEnabled(rolloutPercentage: percentage, bucket: bucket),
                enabled: enabled,
                source: .remote
            )
        } catch {
            return fallbackState(feature: feature, subject: subject)
        }
    }

    func localState(
        feature: GrayFeature,
        userID: String?,
        overrideMode: GrayOverride = .follow
    ) -> GrayFeatureState {
        let subject = GrayRollout.subjectHash(userID: userID)
        if overrideMode != .follow {
            return overriddenState(feature: feature, subject: subject, overrideMode: overrideMode)
        }
        return fallbackState(feature: feature, subject: subject)
    }

    static func remoteURL(
        endpoint: URL,
        feature: String,
        hashedSubject: String,
        versionCode: Int,
        versionName: String
    ) throws -> URL {
        guard hashedSubject.count == 64,
              hashedSubject.allSatisfy({ $0.isHexDigit }),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "feature", value: feature),
            URLQueryItem(name: "subject", value: hashedSubject),
            URLQueryItem(name: "versionCode", value: String(versionCode)),
            URLQueryItem(name: "versionName", value: versionName)
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private func fallbackState(feature: GrayFeature, subject: String) -> GrayFeatureState {
        let bucket = GrayRollout.bucket(featureKey: feature.key, subjectKey: subject)
        let enabled = GrayRollout.isEnabled(rolloutPercentage: feature.rolloutPercentage, bucket: bucket)
        return GrayFeatureState(
            feature: feature,
            overrideMode: .follow,
            bucket: bucket,
            rolloutPercentage: feature.rolloutPercentage,
            rolloutEnabled: enabled,
            enabled: enabled,
            source: .local
        )
    }

    private func overriddenState(feature: GrayFeature, subject: String, overrideMode: GrayOverride) -> GrayFeatureState {
        let bucket = GrayRollout.bucket(featureKey: feature.key, subjectKey: subject)
        return GrayFeatureState(
            feature: feature,
            overrideMode: overrideMode,
            bucket: bucket,
            rolloutPercentage: feature.rolloutPercentage,
            rolloutEnabled: GrayRollout.isEnabled(rolloutPercentage: feature.rolloutPercentage, bucket: bucket),
            enabled: overrideMode == .enabled,
            source: .debug
        )
    }
}

struct RedactingLogger: Sendable {
    private let logger: Logger

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.openahu.ahutong", category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func notice(_ message: String) {
        let sanitized = Self.sanitize(message)
        logger.notice("\(sanitized, privacy: .public)")
    }

    static func sanitize(_ message: String) -> String {
        // Keep an internal comma-delimited marker until every expression has run.
        // In particular, the JSON-style field pass cannot quote a header placeholder.
        let redactionMarker = ",__AHUTONG_REDACTION_MARKER__,"
        let sensitiveName =
            #"(?:password|token|cookie|set-cookie|authorization|proxy-authorization|secret|student(?:id)?|phone|synjones-auth|ticket|x-ahutong-token)"#

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
                of: #"(?i)(\b(?:authorization|proxy-authorization|cookie|set-cookie|synjones-auth|x-ahutong-token)\s*:\s*)[^\r\n]+"#,
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

struct PrivacyManifestAudit: Equatable, Sendable {
    let exists: Bool
    let trackingDisabled: Bool
    let declaresPaymentInfo: Bool

    static func inspect(bundle: Bundle = .main) -> PrivacyManifestAudit {
        guard let url = bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any] else {
            return PrivacyManifestAudit(exists: false, trackingDisabled: false, declaresPaymentInfo: false)
        }
        let trackingDisabled = root["NSPrivacyTracking"] as? Bool == false
        let collected = root["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        let payment = collected.contains {
            $0["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypePaymentInfo"
        }
        return PrivacyManifestAudit(exists: true, trackingDisabled: trackingDisabled, declaresPaymentInfo: payment)
    }
}

struct ReleaseDiagnostics: Equatable, Sendable {
    let version: String
    let build: String
    let privacy: PrivacyManifestAudit
    let productionPaymentGatewayConfigured: Bool
    let thirdPartyCrashReportingEnabled: Bool

    static func current(bundle: Bundle = .main) -> ReleaseDiagnostics {
        ReleaseDiagnostics(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "--",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "--",
            privacy: PrivacyManifestAudit.inspect(bundle: bundle),
            productionPaymentGatewayConfigured: false,
            thirdPartyCrashReportingEnabled: false
        )
    }
}
