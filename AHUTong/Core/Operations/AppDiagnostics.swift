import Foundation
import Sentry

enum DiagnosticSignal: String, CaseIterable, Sendable {
    case widgetSharingUnavailable = "widget-sharing-unavailable"
    case widgetWriteFailed = "widget-write-failed"
    case sessionRefreshFailed = "session-refresh-failed"
    case verification = "installation-verification"
}

enum DiagnosticStage: String, CaseIterable, Sendable {
    case startup, widgetPublish, refresh, verification
}

enum DiagnosticFailure: String, CaseIterable, Sendable {
    case none, network, sessionExpired, credentialsUnavailable, credentialsRejected
    case invalidResponse, service, unknown

    static func classify(_ error: Error) -> Self {
        if error is URLError { return .network }
        if let error = error as? CampusCoreError {
            if error == .unauthorized { return .sessionExpired }
            if error == .credentialsUnavailable { return .credentialsUnavailable }
            if error == .credentialsRejected { return .credentialsRejected }
            if error == .invalidResponse { return .invalidResponse }
            return .service
        }
        return .unknown
    }
}

enum DiagnosticsConsentPolicy {
    static func allowsReporting(_ consent: AgreementConsent, isolated: Bool) -> Bool {
        !isolated && consent.isComplete && consent.privacyDecision == .accepted
    }
}

/// Error values and NSError.userInfo never enter an event. Only closed enums and
/// numeric URL error codes are accepted; duplicate failures are bounded per launch.
struct DiagnosticRecord: Hashable, Sendable {
    let signal: DiagnosticSignal
    let stage: DiagnosticStage
    let failure: DiagnosticFailure
    var scope: CampusSessionScope? = nil
    var networkCode: Int? = nil
    var widgetIssue: WidgetSharingResolution.Issue? = nil

    var tags: [String: String] {
        var values = ["ahu.signal": signal.rawValue, "ahu.stage": stage.rawValue,
                      "ahu.failure": failure.rawValue]
        if let scope { values["ahu.scope"] = scope.rawValue }
        if let networkCode { values["ahu.network_code"] = String(networkCode) }
        if let widgetIssue { values["ahu.widget_issue"] = widgetIssue.rawValue }
        return values
    }
}

enum DiagnosticsSanitizer {
    static func sanitize(_ event: Event) -> Event? {
        if let signal = event.tags?["ahu.signal"], DiagnosticSignal(rawValue: signal) == nil {
            return nil
        }
        let tags = safeTags(event.tags ?? [:])
        let signal = tags["ahu.signal"].flatMap(DiagnosticSignal.init(rawValue:))
        event.message = SentryMessage(formatted: signal.map { "AHUTong: \($0.rawValue)" }
            ?? "AHUTong native diagnostic")
        event.user = nil
        event.request = nil
        event.error = nil
        event.extra = nil
        event.breadcrumbs = nil
        event.serverName = nil
        event.transaction = nil
        event.modules = nil
        event.logger = "ahutong"
        event.tags = tags
        event.fingerprint = signal.map { ["ahutong", $0.rawValue, tags["ahu.failure"] ?? "none",
                                        tags["ahu.widget_issue"] ?? "none"] }
        // Preserve only OS/device characteristics useful for compatibility bugs.
        let keys: [String: Set<String>] = [
            "os": ["name", "version", "build"],
            "device": ["family", "model", "model_id", "arch", "simulator"]
        ]
        event.context = event.context?.reduce(into: [:]) { result, item in
            if let allowed = keys[item.key] {
                result[item.key] = item.value.filter { allowed.contains($0.key) }
            }
        }
        for exception in event.exceptions ?? [] {
            exception.value = "[redacted]"
            exception.mechanism?.data = nil
            exception.mechanism?.desc = nil
            exception.mechanism?.helpLink = nil
            scrub(exception.stacktrace)
        }
        for thread in event.threads ?? [] {
            thread.name = nil
            scrub(thread.stacktrace)
        }
        scrub(event.stacktrace)
        for image in event.debugMeta ?? [] {
            image.codeFile = image.codeFile.map { URL(fileURLWithPath: $0).lastPathComponent }
        }
        return event
    }

    static func safeTags(_ tags: [String: String]) -> [String: String] {
        tags.filter { key, value in
            switch key {
            case "ahu.signal": DiagnosticSignal(rawValue: value) != nil
            case "ahu.stage": DiagnosticStage(rawValue: value) != nil
            case "ahu.failure": DiagnosticFailure(rawValue: value) != nil
            case "ahu.scope": CampusSessionScope(rawValue: value) != nil
            case "ahu.widget_issue": WidgetSharingResolution.Issue(rawValue: value) != nil
            case "ahu.network_code": Int(value).map { (-1_200 ... -1).contains($0) } ?? false
            default: false
            }
        }
    }

    private static func scrub(_ stack: SentryStacktrace?) {
        for frame in stack?.frames ?? [] {
            frame.vars = nil
            frame.contextLine = nil
            frame.preContext = nil
            frame.postContext = nil
            frame.fileName = frame.fileName.map { URL(fileURLWithPath: $0).lastPathComponent }
            frame.package = frame.package.map { URL(fileURLWithPath: $0).lastPathComponent }
        }
        stack?.registers = [:]
    }
}

enum SentryConfiguration {
    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static var cacheURL: URL {
        cachesDirectory.appendingPathComponent("AHUTongDiagnostics-v2", isDirectory: true)
    }

    // Old SDK envelopes can bypass beforeSend when drained. Retire that queue
    // when narrowing collection so cached campus-code events cannot be sent.
    static func removeRetiredCache(in directory: URL? = nil) {
        try? FileManager.default.removeItem(at: (directory ?? cachesDirectory)
            .appendingPathComponent("AHUTongDiagnostics", isDirectory: true))
    }

    static func options(bundle: Bundle = .main) -> Options {
        let options = Options()
        options.dsn = bundle.object(forInfoDictionaryKey: "AHUTongSentryDSN") as? String
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        options.releaseName = "com.openahu.ahutong@\(version)+\(build)"
        options.dist = build
        #if DEBUG
        options.environment = "development"
        #else
        options.environment = "production"
        #endif
        options.debug = false
        options.sendDefaultPii = false
        options.enableAutoSessionTracking = false
        options.enableSwizzling = false
        options.enableAutoBreadcrumbTracking = false
        options.enableNetworkBreadcrumbs = false
        options.enableCaptureFailedRequests = false
        options.enableNetworkTracking = false
        options.enableAutoPerformanceTracing = false
        options.tracesSampleRate = 0
        options.enableLogs = false
        options.enableMetrics = false
        options.enableAppHangTracking = false
        options.enableWatchdogTerminationTracking = false
        options.enableMetricKit = false
        options.enableMetricKitRawPayload = false
        options.enableTimeToFullDisplayTracing = false
        options.sendClientReports = false
        options.enableMemoryIntrospection = false
        options.attachScreenshot = false
        options.attachViewHierarchy = false
        options.sessionReplay.sessionSampleRate = 0
        options.sessionReplay.onErrorSampleRate = 0
        options.maxBreadcrumbs = 0
        options.maxCacheItems = 10
        options.cacheDirectoryPath = cacheURL.path
        options.shutdownTimeInterval = 0
        options.beforeBreadcrumb = { _ in nil }
        options.beforeSend = { DiagnosticsSanitizer.sanitize($0) }
        return options
    }
}

final class AppDiagnostics: @unchecked Sendable {
    static let shared = AppDiagnostics()
    private let lock = NSLock()
    private var enabled = false
    private var recorded: Set<DiagnosticRecord> = []

    private var isEnabled: Bool { lock.withLock { enabled } }

    @MainActor
    func updateConsent(_ consent: AgreementConsent) {
        let allowed = DiagnosticsConsentPolicy.allowsReporting(
            consent, isolated: AppRuntime.usesIsolatedUITestStorage
        )
        let changed = lock.withLock {
            guard enabled != allowed else { return false }
            enabled = allowed
            recorded.removeAll()
            return true
        }
        if allowed, changed {
            SentryConfiguration.removeRetiredCache()
            let options = SentryConfiguration.options()
            options.beforeSend = { [weak self] event in
                guard self?.isEnabled == true else { return nil }
                return DiagnosticsSanitizer.sanitize(event)
            }
            SentrySDK.start(options: options)
            inspectWidgetSharing()
        } else if !allowed, !AppRuntime.usesIsolatedUITestStorage {
            if changed { SentrySDK.close() }
            try? FileManager.default.removeItem(at: SentryConfiguration.cacheURL)
            SentryConfiguration.removeRetiredCache()
        }
    }

    func report(_ signal: DiagnosticSignal, stage: DiagnosticStage,
                error: Error, scope: CampusSessionScope? = nil) {
        guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
        if case .sharingUnavailable? = error as? ScheduleWidgetStoreError {
            inspectWidgetSharing()
            return
        }
        record(DiagnosticRecord(signal: signal, stage: stage, failure: .classify(error),
                                scope: scope, networkCode: (error as? URLError)?.code.rawValue))
    }

    func inspectWidgetSharing() {
        guard isEnabled, let issue = ScheduleWidgetSnapshotStore.sharing.issue else { return }
        record(DiagnosticRecord(signal: .widgetSharingUnavailable, stage: .startup,
                                failure: .none, widgetIssue: issue))
    }

    private func record(_ record: DiagnosticRecord) {
        let allowed = lock.withLock {
            enabled && recorded.count < 20 && recorded.insert(record).inserted
        }
        guard allowed else { return }
        let event = Event(level: .warning)
        event.message = SentryMessage(formatted: "AHUTong: \(record.signal.rawValue)")
        event.tags = record.tags
        SentrySDK.capture(event: event)
    }
}
