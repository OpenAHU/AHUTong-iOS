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
        if let generation = event.tags?["ahu.generation"].flatMap(Int.init),
           generation != DiagnosticLog.shared.generation { return nil }
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
        event.breadcrumbs = event.breadcrumbs?.compactMap(sanitizeBreadcrumb)
        event.serverName = nil
        event.transaction = tags["ui.route"]
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
            case "dau_id": UUID(uuidString: value) != nil
            case "ui.route": value.range(of: #"^[a-z][a-z0-9._-]{0,79}$"#, options: .regularExpression) != nil
            case "ui.theme": ["light", "dark"].contains(value)
            case "ui.wallpaper": ["true", "false"].contains(value)
            default: false
            }
        }
    }

    static func sanitizeBreadcrumb(_ breadcrumb: Breadcrumb) -> Breadcrumb? {
        guard ["app.lifecycle", "app.navigation", "app.diagnostics.runtime", "app.diagnostics.error", "app.network"].contains(breadcrumb.category) else { return nil }
        breadcrumb.message = breadcrumb.message.map { String(DiagnosticText.redacted($0).prefix(2_000)) }
        for key in breadcrumb.data?.keys.map({ $0 }) ?? [] { breadcrumb.setData(value: nil, key: key) }
        return breadcrumb
    }

    static func sanitizeSpan(_ span: any Span) -> (any Span)? {
        if let generation = span.data["ahu.generation"] as? Int, generation != DiagnosticLog.shared.generation { return nil }
        span.spanDescription = span.spanDescription.map { DiagnosticText.redacted($0) }
        let allowed = Set(["dau_id", "dau_date", "http.request.method", "http.response.status_code", "server.address", "ui.route", "frames.total", "frames.slow", "frames.frozen"])
        for (key, value) in span.data {
            if !allowed.contains(key) { span.removeData(key: key) }
            else if key == "dau_id" {
                if let id = value as? String, UUID(uuidString: id) != nil { span.setData(value: id, key: key) }
                else { span.removeData(key: key) }
            } else if let text = value as? String { span.setData(value: DiagnosticText.redacted(text), key: key) }
        }
        for key in span.tags.keys where safeTags([key: span.tags[key]!]).isEmpty { span.removeTag(key: key) }
        return span
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
        options.enableAutoSessionTracking = true
        options.enableSwizzling = true
        options.enableAutoBreadcrumbTracking = false
        options.enableNetworkBreadcrumbs = false
        options.enableCaptureFailedRequests = false
        options.enableNetworkTracking = false
        options.enableAutoPerformanceTracing = true
        options.enableUIViewControllerTracing = true
        options.enableUserInteractionTracing = false
        options.enableFileIOTracing = false
        options.enableCoreDataTracing = false
        options.enableDataSwizzling = false
        options.enableFileManagerSwizzling = false
        options.tracePropagationTargets = []
        #if DEBUG
        options.tracesSampleRate = 1
        #else
        options.tracesSampleRate = 0.1
        #endif
        options.enableLogs = false
        options.enableMetrics = false
        options.enableAppHangTracking = false
        options.enableWatchdogTerminationTracking = true
        options.enableMetricKit = true
        options.enableMetricKitRawPayload = true
        options.enableTimeToFullDisplayTracing = false
        options.sendClientReports = false
        options.enableMemoryIntrospection = false
        options.attachScreenshot = false
        options.attachViewHierarchy = false
        options.sessionReplay.sessionSampleRate = 0
        options.sessionReplay.onErrorSampleRate = 0
        options.maxBreadcrumbs = 100
        options.maxCacheItems = 10
        options.cacheDirectoryPath = cacheURL.path
        options.shutdownTimeInterval = 0
        options.beforeBreadcrumb = DiagnosticsSanitizer.sanitizeBreadcrumb
        options.beforeSendSpan = DiagnosticsSanitizer.sanitizeSpan
        options.beforeSend = { DiagnosticsSanitizer.sanitize($0) }
        return options
    }
}

final class AppDiagnostics: @unchecked Sendable {
    static let shared = AppDiagnostics()
    private let lock = NSLock()
    private var enabled = false
    private var recorded: Set<DiagnosticRecord> = []
    private var lastErrorID: String?
    private let activity = DiagnosticActivityStore()

    private var isEnabled: Bool { lock.withLock { enabled } }
    var latestErrorID: String? { lock.withLock { lastErrorID } }

    @MainActor
    func updateConsent(_ consent: AgreementConsent) {
        let allowed = DiagnosticsConsentPolicy.allowsReporting(
            consent, isolated: AppRuntime.usesIsolatedUITestStorage
        )
        let changed = lock.withLock {
            guard enabled != allowed else { return false }
            enabled = allowed
            recorded.removeAll()
            lastErrorID = nil
            return true
        }
        if changed { DiagnosticLog.shared.setEnabled(allowed) }
        if allowed, changed {
            SentryConfiguration.removeRetiredCache()
            let options = SentryConfiguration.options()
            options.beforeSendWithHint = { [weak self] event, hint in
                guard self?.isEnabled == true else { return nil }
                // Backfilled crash/MetricKit reports keep their own persisted context.
                if hint.originalError != nil || hint.originalException != nil {
                    hint.attachments += self?.automaticAttachments() ?? []
                }
                return DiagnosticsSanitizer.sanitize(event)
            }
            SentrySDK.start(options: options)
            SentrySDK.configureScope { $0.setTag(value: self.activity.installationID, key: "dau_id") }
            log(.runtime, "diagnostics.started")
            foreground()
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
        log(.error, "\(record.signal.rawValue) \(record.failure.rawValue)")
        SentrySDK.capture(event: event)
    }

    func log(_ category: DiagnosticLogCategory, _ message: String, generation: Int? = nil) {
        guard isEnabled, let generation = generation ?? DiagnosticLog.shared.activeGeneration else { return }
        let safe = DiagnosticText.redacted(message, includeIdentity: category != .network)
        guard DiagnosticLog.shared.append(category, text: safe, generation: generation), category != .network else { return }
        let breadcrumb = Breadcrumb(level: category == .error ? .error : .info, category: "app.diagnostics.\(category.rawValue)")
        breadcrumb.message = String(safe.prefix(2_000))
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    func accountChanged() {
        DiagnosticLog.shared.clear()
        lock.withLock { lastErrorID = nil; recorded.removeAll() }
        SentrySDK.configureScope { $0.clearBreadcrumbs() }
    }

    func foreground(now: Date = Date()) {
        guard isEnabled else { return }
        log(.runtime, "app.foreground")
        activity.reportIfNeeded(now: now) { id, day in
            let context = TransactionContext(name: "AHUTong DAU", operation: "app.dau", sampled: .yes, sampleRate: 1, sampleRand: nil)
            let span = SentrySDK.startTransaction(transactionContext: context, bindToScope: false)
            span.setTag(value: id, key: "dau_id")
            span.setData(value: id, key: "dau_id")
            span.setData(value: day, key: "dau_date")
            span.finish(status: .ok)
            return SentrySDK.isEnabled
        }
    }

    func page(_ route: String, dark: Bool, wallpaper: Bool) {
        guard isEnabled else { return }
        SentrySDK.configureScope {
            $0.setTag(value: route, key: "ui.route")
            $0.setTag(value: dark ? "dark" : "light", key: "ui.theme")
            $0.setTag(value: wallpaper ? "true" : "false", key: "ui.wallpaper")
        }
        log(.runtime, "page.\(route)")
    }

    func startNetwork(_ request: URLRequest, generation: Int) -> (any Span)? {
        guard isEnabled, !Self.isCampusCode(request) else { return nil }
        let span = SentrySDK.startTransaction(name: "\(request.httpMethod ?? "GET") \(DiagnosticText.endpoint(request.url))", operation: "http.client", bindToScope: false)
        span.setTag(value: String(generation), key: "ahu.generation")
        span.setData(value: request.httpMethod ?? "GET", key: "http.request.method")
        span.setData(value: request.url?.host ?? "unknown", key: "server.address")
        return span
    }

    func recordNetwork(_ request: URLRequest, response: HTTPURLResponse?, data: Data?, error: Error?,
                       generation: Int, started: TimeInterval, span: (any Span)?) {
        span?.setData(value: response?.statusCode, key: "http.response.status_code")
        span?.finish(status: error == nil && (response?.statusCode ?? 0) < 400 ? .ok : .internalError)
        guard isEnabled, generation == DiagnosticLog.shared.generation, !Self.isCampusCode(request) else { return }
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
        let summary = "\(request.httpMethod ?? "GET") \(DiagnosticText.endpoint(request.url)) \(response?.statusCode ?? 0) \(elapsed)ms"
        log(error == nil ? .runtime : .error, summary, generation: generation)
        let path = request.url?.path.lowercased() ?? ""
        // Payment codes, payment credentials and mailbox content never enter a diagnostic body.
        let sensitive = ["qrcode", "paycode", "payment", "recharge", "password", "login", "auth", "mail", "ocr", "captcha"].contains { path.contains($0) }
            || request.url?.host?.contains("163.com") == true
        guard !sensitive else { return }
        let responseHeaders = response?.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) } ?? [:]
        let details = [summary, DiagnosticText.headers(request.allHTTPHeaderFields ?? [:]),
                       DiagnosticText.body(request.httpBody, contentType: request.value(forHTTPHeaderField: "Content-Type")),
                       DiagnosticText.headers(responseHeaders), DiagnosticText.body(data, contentType: response?.mimeType)].filter { !$0.isEmpty }.joined(separator: "\n")
        log(.network, details, generation: generation)
    }

    private static func isCampusCode(_ request: URLRequest) -> Bool {
        let path = request.url?.path.lowercased() ?? ""
        return path.contains("qrcode") || path.contains("paycode")
    }

    func reportUnexpected(_ error: Error, route: String) {
        guard isEnabled, !(error is CancellationError), !(error is URLError) else { return }
        log(.error, "\(route): \(String(reflecting: type(of: error)))")
        let generation = DiagnosticLog.shared.generation
        let id = SentrySDK.capture(error: error) { $0.setTag(value: route, key: "ui.route") }
        lock.withLock {
            if generation == DiagnosticLog.shared.generation { lastErrorID = id.sentryIdString }
        }
    }

    private func automaticAttachments() -> [Attachment] {
        [DiagnosticLogCategory.runtime, .error].compactMap { category in
            let text = DiagnosticLog.shared.snapshot(category, maxCharacters: 96_000)
            guard !text.isEmpty else { return nil }
            return Attachment(data: Data(text.utf8), filename: "crash-\(category.rawValue).txt", contentType: "text/plain")
        }
    }

    func submitFeedback(_ preview: DiagnosticFeedbackPreview) throws {
        guard isEnabled, preview.generation == DiagnosticLog.shared.generation else { throw DiagnosticFeedbackError.expired }
        let (event, hint) = Self.feedbackPayload(preview)
        // The 9.31 feedback convenience API merges the global scope and skips
        // beforeSend. Use its public serializer with an empty per-event scope
        // so deselected runtime logs cannot reappear as ambient breadcrumbs.
        SentrySDK.capture(event: event, scope: Scope(), hint: hint)
    }

    static func feedbackPayload(_ preview: DiagnosticFeedbackPreview) -> (Event, Hint) {
        let feedback = SentryFeedback(message: preview.message, name: nil, email: nil, source: .custom,
            associatedEventId: preview.associatedEventID.map { SentryId(uuidString: $0) })
        let event = Event()
        event.type = "feedback"
        event.context = ["feedback": feedback.serialize()]
        let hint = Hint()
        hint.attachments = preview.attachments.map { Attachment(data: Data($0.text.utf8), filename: $0.filename, contentType: "text/plain") }
        return (event, hint)
    }
}

final class DiagnosticActivityStore: @unchecked Sendable {
    private let lock = NSLock()
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var installationID: String {
        lock.withLock {
            if let value = defaults.string(forKey: "diagnostics.installation-id"), UUID(uuidString: value) != nil { return value }
            let value = UUID().uuidString.lowercased()
            defaults.set(value, forKey: "diagnostics.installation-id")
            return value
        }
    }
    func reportIfNeeded(now: Date, calendar: Calendar = .current, send: (String, String) -> Bool) {
        let id = installationID
        lock.withLock {
            let parts = calendar.dateComponents([.year, .month, .day], from: now)
            let day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
            guard defaults.string(forKey: "diagnostics.dau-day") != day else { return }
            if send(id, day) { defaults.set(day, forKey: "diagnostics.dau-day") }
        }
    }
}
