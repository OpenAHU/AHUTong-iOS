import CryptoKit
import Foundation
import SwiftUI
#if canImport(Darwin)
import Darwin
#endif

enum PaymentFeature: String, Codable, CaseIterable, Sendable {
    case cardRecharge
    case bathroom
    case electricity
    case networkRecharge

    var displayName: String {
        switch self {
        case .cardRecharge: "校园卡充值"
        case .bathroom: "浴室缴费"
        case .electricity: "电控缴费"
        case .networkRecharge: "网费充值"
        }
    }
}

enum PaymentMethod: String, Codable, Sendable {
    case bankCard
    case alipay
    case campusAccount
}

enum PaymentValidationError: LocalizedError, Equatable, Sendable {
    case missingAmount
    case invalidAmount
    case tooManyFractionDigits
    case exceedsLimit
    case missingAccount
    case invalidPassword
    case invalidTransactionContext

    var errorDescription: String? {
        switch self {
        case .missingAmount: "请输入缴费金额"
        case .invalidAmount: "请输入有效金额"
        case .tooManyFractionDigits: "金额最多保留两位小数"
        case .exceedsLimit: "单次金额不能超过 500 元"
        case .missingAccount: "请先选择缴费账户"
        case .invalidPassword: "密码必须是 6 位数字"
        case .invalidTransactionContext: "支付业务上下文与当前功能不匹配"
        }
    }
}

struct PaymentAmount: Equatable, Sendable {
    let value: Decimal

    init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PaymentValidationError.missingAmount }
        guard value.range(of: #"^\d+(\.\d{0,2})?$"#, options: .regularExpression) != nil else {
            if value.range(of: #"^\d+\.\d{3,}$"#, options: .regularExpression) != nil {
                throw PaymentValidationError.tooManyFractionDigits
            }
            throw PaymentValidationError.invalidAmount
        }
        guard let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), amount > 0 else {
            throw PaymentValidationError.invalidAmount
        }
        guard amount <= 500 else { throw PaymentValidationError.exceedsLimit }
        self.value = amount
    }

    var text: String {
        let number = NSDecimalNumber(decimal: value)
        return String(format: "%.2f", number.doubleValue)
    }
}

enum PaymentTransactionContext: Equatable, Sendable {
    case card(cardType: String)
    case bathroom(feeItemID: String, thirdPartyJSON: String)
    case electricity(thirdPartyJSON: String)
    case networkRecharge(thirdPartyJSON: String)
    case demo

    fileprivate func supports(_ feature: PaymentFeature) -> Bool {
        switch (self, feature) {
        case (.card, .cardRecharge),
             (.bathroom, .bathroom),
             (.electricity, .electricity),
             (.networkRecharge, .networkRecharge):
            true
        case (.demo, _):
            true
        default:
            false
        }
    }
}

final class TransientPaymentAuthorization: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: ContiguousArray<UInt8>
    private var consumed = false

    init(digits: String) throws {
        let bytes = ContiguousArray(digits.utf8)
        guard bytes.count == 6,
              bytes.allSatisfy({ (48...57).contains($0) }) else {
            throw PaymentValidationError.invalidPassword
        }
        storage = bytes
    }

    deinit {
        clear()
    }

    var isCleared: Bool {
        lock.withLock {
            storage.allSatisfy { $0 == 0 }
        }
    }

    func consumeASCIIBytes() throws -> ContiguousArray<UInt8> {
        try lock.withLock {
            guard !consumed else {
                throw PaymentValidationError.invalidPassword
            }
            consumed = true
            let bytes = storage
            wipeStorage()
            return bytes
        }
    }

    func clear() {
        lock.withLock {
            consumed = true
            wipeStorage()
        }
    }

    private func wipeStorage() {
        for index in storage.indices {
            storage[index] = 0
        }
    }
}

struct PaymentRequest: Equatable, Sendable {
    let feature: PaymentFeature
    let method: PaymentMethod
    let amount: PaymentAmount
    let accountID: String
    let accountLabel: String
    let context: PaymentTransactionContext

    init(
        feature: PaymentFeature,
        method: PaymentMethod,
        amount: PaymentAmount,
        accountID: String,
        accountLabel: String,
        context: PaymentTransactionContext
    ) throws {
        guard !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PaymentValidationError.missingAccount
        }
        guard context.supports(feature) else {
            throw PaymentValidationError.invalidTransactionContext
        }
        self.feature = feature
        self.method = method
        self.amount = amount
        self.accountID = accountID
        self.accountLabel = accountLabel
        self.context = context
    }
}

struct PaymentOrder: Equatable, Sendable {
    let id: String
    let externalURL: URL?
}

enum PaymentOrderStatus: Equatable, Sendable {
    case pending(String)
    case confirmed(String)
    case rejected(String)
    case unknown(String)
}

enum PaymentGatewayError: LocalizedError, Equatable, Sendable {
    case automatedDebitDisabled
    case timedOut
    case invalidResponse
    case featureMismatch
    case definitelyRejected(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .automatedDebitDisabled: "自动化环境禁止连接真实扣款接口，未发起任何扣款"
        case .timedOut: "支付请求超时，请先查询订单结果，勿重复提交"
        case .invalidResponse: "支付服务返回了无法识别的结果"
        case .featureMismatch: "支付请求与当前功能不匹配"
        case let .definitelyRejected(message): message
        case let .server(message): message
        }
    }
}

protocol PreparedPaymentConfirmation: Sendable {
    func clear()
}

protocol PaymentGateway: Sendable {
    func createOrder(request: PaymentRequest, idempotencyKey: String) async throws -> PaymentOrder
    func prepareConfirmation(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod,
        authorization: TransientPaymentAuthorization?
    ) async throws -> any PreparedPaymentConfirmation
    func submitPreparedConfirmation(
        _ prepared: any PreparedPaymentConfirmation
    ) async throws -> PaymentOrderStatus
    func status(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod
    ) async throws -> PaymentOrderStatus
}

enum PaymentPhase: Equatable {
    case idle
    case creating
    case confirming(String)
    case awaitingConfirmation(String)
    case awaitingExternal(String)
    case reconciling(String)
    case succeeded(String, String)
    case failed(String)
    case cancelled
    case creationUnknown(String)
    case unknown(String, String)

    var isBusy: Bool {
        switch self {
        case .creating, .confirming, .reconciling: true
        default: false
        }
    }
}

enum PendingPaymentStage: String, Codable, Equatable, Sendable {
    case creating
    case creationUnknown
    case orderCreated
    case finalSubmissionStarted
    case resultUnknown
}

struct PendingPayment: Codable, Equatable, Sendable {
    static let currentVersion = 2

    let version: Int
    let feature: PaymentFeature
    let orderID: String?
    let method: PaymentMethod
    let stage: PendingPaymentStage

    init(
        version: Int = Self.currentVersion,
        feature: PaymentFeature,
        orderID: String?,
        method: PaymentMethod,
        stage: PendingPaymentStage
    ) {
        self.version = version
        self.feature = feature
        self.orderID = orderID
        self.method = method
        self.stage = stage
    }

    var isValid: Bool {
        guard version == Self.currentVersion else { return false }
        let hasValidOrderID = orderID.map(Self.isValidOrderID) == true
        switch stage {
        case .creating, .creationUnknown:
            guard orderID == nil else { return false }
        case .orderCreated, .finalSubmissionStarted, .resultUnknown:
            guard hasValidOrderID else { return false }
        }
        switch feature {
        case .cardRecharge:
            return method == .bankCard || method == .alipay
        case .bathroom, .electricity, .networkRecharge:
            return method == .campusAccount
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case feature
        case orderID
        case method
        case stage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        feature = try container.decode(PaymentFeature.self, forKey: .feature)
        orderID = try container.decodeIfPresent(String.self, forKey: .orderID)
        if let version = try container.decodeIfPresent(Int.self, forKey: .version) {
            self.version = version
            method = try container.decode(PaymentMethod.self, forKey: .method)
            stage = try container.decode(PendingPaymentStage.self, forKey: .stage)
        } else {
            // Legacy records had only feature + orderID. Treat them as an
            // already-submitted unknown result so an upgrade can never repeat
            // either mutation.
            self.version = Self.currentVersion
            method = Self.legacyMethod(for: feature)
            stage = .resultUnknown
        }
        guard isValid else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid pending payment state"
                )
            )
        }
    }

    private static func legacyMethod(for feature: PaymentFeature) -> PaymentMethod {
        switch feature {
        case .cardRecharge: .bankCard
        case .bathroom, .electricity, .networkRecharge: .campusAccount
        }
    }

    static func isValidOrderID(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 256
            && value.unicodeScalars.allSatisfy {
                $0.value >= 0x21 && $0.value <= 0x7e
            }
    }
}

enum PendingPaymentLoadResult: Equatable, Sendable {
    case empty
    case value(PendingPayment)
    case corrupt
}

enum PendingPaymentStoreWriteFault: Equatable, Sendable {
    case none
    case beforeRename
    case directorySynchronization(Int)
}

@MainActor
final class PendingPaymentStore {
    private let defaults: UserDefaults
    private let key: String
    private let fileManager: FileManager
    private let durableDirectoryURL: URL?
    private let durableLogURL: URL?
    private let durabilityAnchorURL: URL?
    private let usesDurableLog: Bool
    private let writeFault: PendingPaymentStoreWriteFault
    private var directorySynchronizationAttempt = 0

    private var legacySubmissionKey: String { "\(key).submission" }

    convenience init(key: String = "payments.pending-order") {
        let fileManager = FileManager.default
        let applicationSupportURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.init(
            resolvedDurableDirectoryURL: applicationSupportURL?
                .appendingPathComponent("AHUTong", isDirectory: true)
                .appendingPathComponent("PaymentTransactions", isDirectory: true),
            durabilityAnchorURL: applicationSupportURL?
                .deletingLastPathComponent(),
            legacyDefaults: .standard,
            key: key,
            fileManager: fileManager,
            writeFault: .none
        )
    }

    init(defaults: UserDefaults, key: String = "payments.pending-order") {
        self.defaults = defaults
        self.key = key
        fileManager = .default
        durableDirectoryURL = nil
        durableLogURL = nil
        durabilityAnchorURL = nil
        usesDurableLog = false
        writeFault = .none
    }

    init(
        durableDirectoryURL: URL,
        durabilityAnchorURL: URL? = nil,
        legacyDefaults: UserDefaults,
        key: String,
        fileManager: FileManager = .default,
        writeFault: PendingPaymentStoreWriteFault = .none
    ) {
        defaults = legacyDefaults
        self.key = key
        self.fileManager = fileManager
        self.durableDirectoryURL = durableDirectoryURL
        self.durabilityAnchorURL = durabilityAnchorURL
            ?? Self.nearestExistingParent(
                of: durableDirectoryURL,
                fileManager: fileManager
            )
        durableLogURL = durableDirectoryURL.appendingPathComponent(
            Self.logFileName(for: key),
            isDirectory: false
        )
        usesDurableLog = true
        self.writeFault = writeFault
    }

    private init(
        resolvedDurableDirectoryURL: URL?,
        durabilityAnchorURL: URL?,
        legacyDefaults: UserDefaults,
        key: String,
        fileManager: FileManager,
        writeFault: PendingPaymentStoreWriteFault
    ) {
        defaults = legacyDefaults
        self.key = key
        self.fileManager = fileManager
        durableDirectoryURL = resolvedDurableDirectoryURL
        self.durabilityAnchorURL = durabilityAnchorURL
        durableLogURL = resolvedDurableDirectoryURL?.appendingPathComponent(
            Self.logFileName(for: key),
            isDirectory: false
        )
        usesDurableLog = true
        self.writeFault = writeFault
    }

    func loadResult() -> PendingPaymentLoadResult {
        guard usesDurableLog else { return legacyLoadResult() }
        if let durableLogURL,
           fileManager.fileExists(atPath: durableLogURL.path) {
            guard let pending = readDurableRecord(at: durableLogURL) else {
                return .corrupt
            }
            removeLegacyValues()
            return .value(pending)
        }

        let legacyResult = legacyLoadResult()
        guard case let .value(pending) = legacyResult else {
            return legacyResult
        }
        guard persistDurably(pending) else { return .corrupt }
        removeLegacyValues()
        return .value(pending)
    }

    func load() -> PendingPayment? {
        guard case let .value(pending) = loadResult() else { return nil }
        return pending
    }

    @discardableResult
    func save(_ pending: PendingPayment) -> Bool {
        guard pending.isValid else { return false }
        if usesDurableLog {
            guard persistDurably(pending) else { return false }
            removeLegacyValues()
            return true
        }
        guard let data = try? JSONEncoder().encode(pending) else { return false }
        defaults.set(data, forKey: key)
        guard legacyLoadResult() == .value(pending) else { return false }
        defaults.removeObject(forKey: legacySubmissionKey)
        return true
    }

    func clear() {
        guard usesDurableLog else {
            removeLegacyValues()
            return
        }
        guard let durableDirectoryURL,
              let durableLogURL else { return }
        do {
            try prepareDurableDirectory(durableDirectoryURL)
            if fileManager.fileExists(atPath: durableLogURL.path) {
                try fileManager.removeItem(at: durableLogURL)
            }
            try synchronizeDirectory(at: durableDirectoryURL)
            guard !fileManager.fileExists(atPath: durableLogURL.path) else {
                return
            }
            removeLegacyValues()
        } catch {
            // Leaving a stale pending record is safer than losing a terminal
            // transition that was not durably committed.
        }
    }

    private func legacyLoadResult() -> PendingPaymentLoadResult {
        if let data = defaults.data(forKey: key) {
            guard let pending = try? JSONDecoder().decode(PendingPayment.self, from: data),
                  pending.isValid else {
                return .corrupt
            }
            return .value(pending)
        }
        // The previous implementation persisted a pre-create submission in a
        // second key. Its presence means a create request may have reached the
        // server; never silently discard it or recreate the order.
        if defaults.object(forKey: legacySubmissionKey) != nil {
            return .corrupt
        }
        return .empty
    }

    private func removeLegacyValues() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: legacySubmissionKey)
    }

    private func persistDurably(_ pending: PendingPayment) -> Bool {
        guard pending.isValid,
              let durableDirectoryURL,
              let durableLogURL,
              let data = try? JSONEncoder().encode(pending) else {
            return false
        }
        do {
            try prepareDurableDirectory(durableDirectoryURL)
            try atomicWrite(
                data,
                to: durableLogURL,
                in: durableDirectoryURL
            )
            return readDurableRecord(at: durableLogURL) == pending
        } catch {
            return false
        }
    }

    private func readDurableRecord(at url: URL) -> PendingPayment? {
        guard let data = try? Data(contentsOf: url, options: .uncached),
              let pending = try? JSONDecoder().decode(PendingPayment.self, from: data),
              pending.isValid else {
            return nil
        }
        return pending
    }

    private func prepareDurableDirectory(_ directoryURL: URL) throws {
        guard let durabilityAnchorURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directoryChain = try directoryChain(
            from: durabilityAnchorURL,
            through: directoryURL
        )
        for candidateURL in directoryChain {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(
                atPath: candidateURL.path,
                isDirectory: &isDirectory
            ) {
                guard isDirectory.boolValue else {
                    throw CocoaError(.fileWriteFileExists)
                }
                continue
            }
            try fileManager.createDirectory(
                at: candidateURL,
                withIntermediateDirectories: false,
                attributes: protectionAttributes
            )
            try applyDurabilityMetadata(to: candidateURL)
            // Persist both the new directory inode and its entry in the
            // already-durable parent before creating the next level.
            try synchronizeDirectory(at: candidateURL)
            try synchronizeDirectory(
                at: candidateURL.deletingLastPathComponent()
            )
        }
        try applyDurabilityMetadata(to: directoryURL)
        // Repeat the complete chain on every attempt. If a previous attempt
        // returned after a failed fsync, retrying repairs that parent entry
        // before any transaction request can be sent.
        for candidateURL in directoryChain.reversed() {
            try synchronizeDirectory(at: candidateURL)
        }
        try synchronizeDirectory(at: durabilityAnchorURL)
    }

    private func applyDurabilityMetadata(to directoryURL: URL) throws {
        if !protectionAttributes.isEmpty {
            try fileManager.setAttributes(
                protectionAttributes,
                ofItemAtPath: directoryURL.path
            )
        }
        try excludeFromBackup(directoryURL)
    }

    private func directoryChain(
        from anchorURL: URL,
        through directoryURL: URL
    ) throws -> [URL] {
        let anchorURL = anchorURL.standardizedFileURL
        var cursor = directoryURL.standardizedFileURL
        var reversedChain: [URL] = []
        while cursor.path != anchorURL.path {
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            reversedChain.append(cursor)
            cursor = parent
        }
        return reversedChain.reversed()
    }

    private func atomicWrite(
        _ data: Data,
        to destinationURL: URL,
        in directoryURL: URL
    ) throws {
        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

#if canImport(Darwin)
        try writeAndSynchronize(data, to: temporaryURL)
        if !protectionAttributes.isEmpty {
            try fileManager.setAttributes(
                protectionAttributes,
                ofItemAtPath: temporaryURL.path
            )
        }
        try excludeFromBackup(temporaryURL)
        try synchronizeFile(at: temporaryURL)
        if writeFault == .beforeRename {
            throw CocoaError(.fileWriteUnknown)
        }
        guard Darwin.rename(temporaryURL.path, destinationURL.path) == 0 else {
            throw Self.posixError()
        }
        try synchronizeDirectory(at: directoryURL)
#else
        if writeFault == .beforeRename {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: destinationURL, options: .atomic)
#endif
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    private var protectionAttributes: [FileAttributeKey: Any] {
#if os(iOS)
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
#else
        [:]
#endif
    }

#if canImport(Darwin)
    private func writeAndSynchronize(_ data: Data, to url: URL) throws {
        let descriptor = Darwin.open(
            url.path,
            O_WRONLY | O_CREAT | O_EXCL,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw Self.posixError() }
        defer { Darwin.close(descriptor) }

        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw Self.posixError() }
                offset += written
            }
        }
        try synchronizeFileDescriptor(descriptor, fullSync: true)
    }

    private func synchronizeFile(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw Self.posixError() }
        defer { Darwin.close(descriptor) }
        try synchronizeFileDescriptor(descriptor, fullSync: true)
    }

    private func synchronizeDirectory(at url: URL) throws {
        try failDirectorySynchronizationIfRequested()
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw Self.posixError() }
        defer { Darwin.close(descriptor) }
        try synchronizeFileDescriptor(descriptor, fullSync: false)
    }

    private func synchronizeFileDescriptor(
        _ descriptor: Int32,
        fullSync: Bool
    ) throws {
        if fullSync, Darwin.fcntl(descriptor, F_FULLFSYNC) == 0 {
            return
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw Self.posixError()
        }
    }

    private static func posixError() -> Error {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
#else
    private func synchronizeDirectory(at url: URL) throws {
        try failDirectorySynchronizationIfRequested()
    }
#endif

    private func failDirectorySynchronizationIfRequested() throws {
        directorySynchronizationAttempt += 1
        guard case let .directorySynchronization(failingAttempt) = writeFault,
              directorySynchronizationAttempt == failingAttempt else {
            return
        }
        throw CocoaError(.fileWriteUnknown)
    }

    private static func nearestExistingParent(
        of directoryURL: URL,
        fileManager: FileManager
    ) -> URL? {
        var cursor = directoryURL.standardizedFileURL.deletingLastPathComponent()
        while true {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(
                atPath: cursor.path,
                isDirectory: &isDirectory
            ) {
                return isDirectory.boolValue ? cursor : nil
            }
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { return nil }
            cursor = parent
        }
    }

    private static func logFileName(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "pending-\(digest).json"
    }
}

@MainActor
final class PaymentCoordinator: ObservableObject {
    @Published private(set) var phase: PaymentPhase = .idle

    private let feature: PaymentFeature
    private let gateway: any PaymentGateway
    private let pendingStore: PendingPaymentStore
    private var operationRevision = 0

    init(
        feature: PaymentFeature,
        gateway: any PaymentGateway,
        userID: String? = nil,
        pendingStore: PendingPaymentStore? = nil
    ) {
        self.feature = feature
        self.gateway = gateway
        let scope = userID.map { value in
            SHA256.hash(data: Data(value.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        } ?? "anonymous"
        self.pendingStore = pendingStore ?? PendingPaymentStore(key: "payments.pending-order.\(scope).\(feature.rawValue)")
    }

    @discardableResult
    func submit(
        _ request: PaymentRequest,
        authorization: TransientPaymentAuthorization? = nil,
        idempotencyKey: String = UUID().uuidString
    ) async -> URL? {
        guard !phase.isBusy else {
            authorization?.clear()
            return nil
        }
        defer { authorization?.clear() }
        guard request.feature == feature else {
            phase = .failed(PaymentGatewayError.featureMismatch.localizedDescription)
            return nil
        }
        operationRevision += 1
        let revision = operationRevision
        switch pendingStore.loadResult() {
        case .empty:
            break
        case .corrupt:
            authorization?.clear()
            lockForCorruptState()
            return nil
        case let .value(pending):
            authorization?.clear()
            guard pending.feature == feature else {
                lockForCorruptState()
                return nil
            }
            await restore(
                pending,
                queryUnknownResult: true,
                revision: revision
            )
            return nil
        }

        if request.method == .campusAccount, authorization == nil {
            phase = .failed(PaymentValidationError.invalidPassword.localizedDescription)
            return nil
        }

        let creating = PendingPayment(
            feature: feature,
            orderID: nil,
            method: request.method,
            stage: .creating
        )
        guard pendingStore.save(creating) else {
            phase = .failed("无法安全保存支付请求状态，未发起建单请求")
            return nil
        }

        phase = .creating
        do {
            let order = try await gateway.createOrder(
                request: request,
                idempotencyKey: idempotencyKey
            )
            let orderID = order.id
            guard PendingPayment.isValidOrderID(orderID) else {
                throw PaymentGatewayError.invalidResponse
            }
            let pending = PendingPayment(
                feature: feature,
                orderID: orderID,
                method: request.method,
                stage: .orderCreated
            )
            let didSavePending = pendingStore.save(pending)
            guard didSavePending else {
                guard revision == operationRevision else { return nil }
                phase = .unknown(
                    orderID,
                    "订单已创建但本机状态未能安全保存，请勿重复提交"
                )
                return nil
            }
            guard revision == operationRevision else {
                phase = phaseForCreatedOrder(pending)
                return nil
            }
            if let externalURL = order.externalURL {
                phase = .awaitingExternal(orderID)
                return externalURL
            }
            await prepareAndSubmit(
                pending,
                authorization: authorization,
                revision: revision
            )
            return nil
        } catch {
            guard revision == operationRevision else { return nil }
            if Self.isDefiniteCreateFailure(error) {
                pendingStore.clear()
                phase = .failed(Self.safeDefiniteFailureMessage(error))
            } else {
                let unknown = PendingPayment(
                    feature: feature,
                    orderID: nil,
                    method: request.method,
                    stage: .creationUnknown
                )
                _ = pendingStore.save(unknown)
                phase = .creationUnknown(
                    "建单结果无法确认，已禁止再次建单；请先人工核验"
                )
            }
            return nil
        }
    }

    func resumePendingOrder() async {
        guard !phase.isBusy else { return }
        operationRevision += 1
        let revision = operationRevision
        switch pendingStore.loadResult() {
        case .empty:
            return
        case .corrupt:
            lockForCorruptState()
        case let .value(pending):
            guard pending.feature == feature else {
                lockForCorruptState()
                return
            }
            await restore(
                pending,
                queryUnknownResult: true,
                revision: revision
            )
        }
    }

    func resumeExternalReturn() async {
        guard !phase.isBusy else { return }
        operationRevision += 1
        let revision = operationRevision
        let loadResult = pendingStore.loadResult()
        guard case let .value(pending) = loadResult else {
            if case .corrupt = loadResult {
                lockForCorruptState()
            }
            return
        }
        guard pending.feature == feature else {
            lockForCorruptState()
            return
        }
        switch pending.stage {
        case .orderCreated:
            guard pending.method == .alipay else {
                await restore(
                    pending,
                    queryUnknownResult: false,
                    revision: revision
                )
                return
            }
            guard let orderID = pending.orderID else {
                lockForCorruptState()
                return
            }
            await reconcile(
                orderID: orderID,
                method: pending.method,
                revision: revision
            )
        case .finalSubmissionStarted, .resultUnknown:
            guard let orderID = pending.orderID else {
                lockForCorruptState()
                return
            }
            await reconcile(
                orderID: orderID,
                method: pending.method,
                revision: revision
            )
        case .creating, .creationUnknown:
            await restore(
                pending,
                queryUnknownResult: false,
                revision: revision
            )
        }
    }

    func continuePendingOrder(
        authorization: TransientPaymentAuthorization? = nil
    ) async {
        guard !phase.isBusy else {
            authorization?.clear()
            return
        }
        defer { authorization?.clear() }
        operationRevision += 1
        let revision = operationRevision
        switch pendingStore.loadResult() {
        case .empty:
            phase = .idle
        case .corrupt:
            lockForCorruptState()
        case let .value(pending):
            guard pending.feature == feature else {
                lockForCorruptState()
                return
            }
            switch pending.stage {
            case .orderCreated:
                guard let orderID = pending.orderID else {
                    lockForCorruptState()
                    return
                }
                if pending.method == .alipay {
                    authorization?.clear()
                    await reconcile(
                        orderID: orderID,
                        method: pending.method,
                        revision: revision
                    )
                    return
                }
                if pending.method == .campusAccount, authorization == nil {
                    phase = .awaitingConfirmation(orderID)
                    return
                }
                await prepareAndSubmit(
                    pending,
                    authorization: authorization,
                    revision: revision
                )
            case .finalSubmissionStarted, .resultUnknown:
                authorization?.clear()
                guard let orderID = pending.orderID else {
                    lockForCorruptState()
                    return
                }
                await reconcile(
                    orderID: orderID,
                    method: pending.method,
                    revision: revision
                )
            case .creating, .creationUnknown:
                authorization?.clear()
                await restore(
                    pending,
                    queryUnknownResult: false,
                    revision: revision
                )
            }
        }
    }

    func cancel() async {
        operationRevision += 1
        let revision = operationRevision
        switch pendingStore.loadResult() {
        case .empty:
            phase = .cancelled
        case .corrupt:
            lockForCorruptState()
        case let .value(pending):
            await restore(
                pending,
                queryUnknownResult: false,
                revision: revision
            )
        }
    }

    func reset() {
        guard !phase.isBusy else { return }
        operationRevision += 1
        switch pendingStore.loadResult() {
        case .empty:
            phase = .idle
        case .corrupt:
            lockForCorruptState()
        case let .value(pending):
            restoreWithoutNetwork(pending)
        }
    }

    private func prepareAndSubmit(
        _ pending: PendingPayment,
        authorization: TransientPaymentAuthorization?,
        revision: Int
    ) async {
        guard revision == operationRevision else {
            authorization?.clear()
            return
        }
        guard pending.feature == feature,
              pending.stage == .orderCreated,
              let orderID = pending.orderID else {
            lockForCorruptState()
            return
        }

        phase = .confirming(orderID)
        let prepared: any PreparedPaymentConfirmation
        do {
            prepared = try await gateway.prepareConfirmation(
                orderID: orderID,
                feature: pending.feature,
                method: pending.method,
                authorization: authorization
            )
        } catch {
            authorization?.clear()
            guard revision == operationRevision else { return }
            phase = .failed(Self.safePreparationFailureMessage(error))
            return
        }
        authorization?.clear()

        guard revision == operationRevision else {
            prepared.clear()
            return
        }

        let finalStarted = PendingPayment(
            feature: pending.feature,
            orderID: orderID,
            method: pending.method,
            stage: .finalSubmissionStarted
        )
        guard pendingStore.save(finalStarted) else {
            prepared.clear()
            phase = .unknown(
                orderID,
                "订单已准备但无法保存最终提交状态，未继续发送；请勿新建订单"
            )
            return
        }

        do {
            defer { prepared.clear() }
            let status = try await gateway.submitPreparedConfirmation(prepared)
            guard revision == operationRevision else { return }
            await apply(
                status,
                orderID: orderID,
                method: pending.method,
                reconcilePending: true,
                revision: revision
            )
        } catch {
            prepared.clear()
            guard revision == operationRevision else { return }
            persistResultUnknown(
                orderID: orderID,
                method: pending.method
            )
            phase = .unknown(
                orderID,
                "最终支付结果无法确认，请先核验，禁止重复提交"
            )
        }
    }

    private func reconcile(
        orderID: String,
        method: PaymentMethod,
        revision: Int
    ) async {
        guard revision == operationRevision else { return }
        if phase.isBusy {
            guard case let .confirming(activeOrderID) = phase,
                  activeOrderID == orderID else { return }
        }
        phase = .reconciling(orderID)
        do {
            let status = try await gateway.status(
                orderID: orderID,
                feature: feature,
                method: method
            )
            guard revision == operationRevision else { return }
            await apply(
                status,
                orderID: orderID,
                method: method,
                reconcilePending: false,
                revision: revision
            )
        } catch {
            guard revision == operationRevision else { return }
            persistResultUnknown(orderID: orderID, method: method)
            phase = .unknown(
                orderID,
                "订单状态暂时无法核验，请稍后重试，勿重复提交"
            )
        }
    }

    private static func safeDefiniteFailureMessage(_ error: Error) -> String {
        guard let gatewayError = error as? PaymentGatewayError else {
            return "支付服务暂不可用，未发起扣款"
        }
        switch gatewayError {
        case .automatedDebitDisabled,
             .featureMismatch,
             .definitelyRejected:
            return gatewayError.localizedDescription
        case .timedOut, .invalidResponse, .server:
            return "支付服务暂不可用，未发起扣款"
        }
    }

    private static func safePreparationFailureMessage(_ error: Error) -> String {
        let reason: String
        if let validationError = error as? PaymentValidationError,
           validationError == .invalidPassword {
            reason = PaymentValidationError.invalidPassword.localizedDescription
        } else if let gatewayError = error as? PaymentGatewayError,
                  gatewayError == .timedOut {
            reason = "支付确认信息获取超时"
        } else if let gatewayError = error as? PaymentGatewayError,
                  gatewayError == .automatedDebitDisabled {
            reason = PaymentGatewayError.automatedDebitDisabled.localizedDescription
        } else {
            reason = "支付确认信息暂时无法获取"
        }
        return "\(reason)，原订单已保留；点击恢复后可继续同一订单"
    }

    private static func isDefiniteCreateFailure(_ error: Error) -> Bool {
        guard let gatewayError = error as? PaymentGatewayError else {
            return false
        }
        switch gatewayError {
        case .automatedDebitDisabled, .featureMismatch, .definitelyRejected:
            return true
        case .timedOut, .invalidResponse, .server:
            return false
        }
    }

    private func restore(
        _ pending: PendingPayment,
        queryUnknownResult: Bool,
        revision: Int
    ) async {
        guard revision == operationRevision else { return }
        switch pending.stage {
        case .creating:
            let unknown = PendingPayment(
                feature: pending.feature,
                orderID: nil,
                method: pending.method,
                stage: .creationUnknown
            )
            _ = pendingStore.save(unknown)
            phase = .creationUnknown(
                "上次建单在完成前中断，结果无法确认；已禁止再次建单"
            )
        case .creationUnknown:
            phase = .creationUnknown(
                "建单结果尚未确认；已禁止再次建单"
            )
        case .orderCreated:
            phase = phaseForCreatedOrder(pending)
        case .finalSubmissionStarted, .resultUnknown:
            guard let orderID = pending.orderID else {
                lockForCorruptState()
                return
            }
            persistResultUnknown(orderID: orderID, method: pending.method)
            if queryUnknownResult {
                await reconcile(
                    orderID: orderID,
                    method: pending.method,
                    revision: revision
                )
            } else {
                phase = .unknown(orderID, "支付结果待确认，禁止重复提交")
            }
        }
    }

    private func restoreWithoutNetwork(_ pending: PendingPayment) {
        switch pending.stage {
        case .creating, .creationUnknown:
            phase = .creationUnknown("建单结果尚未确认；已禁止再次建单")
        case .orderCreated:
            phase = phaseForCreatedOrder(pending)
        case .finalSubmissionStarted, .resultUnknown:
            if let orderID = pending.orderID {
                phase = .unknown(orderID, "支付结果待确认，禁止重复提交")
            } else {
                lockForCorruptState()
            }
        }
    }

    private func phaseForCreatedOrder(_ pending: PendingPayment) -> PaymentPhase {
        guard let orderID = pending.orderID else {
            return .creationUnknown("订单恢复记录不完整；已禁止再次建单")
        }
        return pending.method == .alipay
            ? .awaitingExternal(orderID)
            : .awaitingConfirmation(orderID)
    }

    private func persistResultUnknown(
        orderID: String,
        method: PaymentMethod
    ) {
        _ = pendingStore.save(PendingPayment(
            feature: feature,
            orderID: orderID,
            method: method,
            stage: .resultUnknown
        ))
    }

    private func lockForCorruptState() {
        phase = .creationUnknown(
            "本机支付恢复记录损坏或不匹配；为避免重复扣款，已禁止新建订单"
        )
    }

    private func apply(
        _ status: PaymentOrderStatus,
        orderID: String,
        method: PaymentMethod,
        reconcilePending: Bool,
        revision: Int
    ) async {
        guard revision == operationRevision else { return }
        switch status {
        case let .confirmed(message):
            pendingStore.clear()
            phase = .succeeded(orderID, message)
        case let .rejected(message):
            pendingStore.clear()
            phase = .failed(message)
        case let .pending(message):
            persistResultUnknown(orderID: orderID, method: method)
            if reconcilePending {
                await reconcile(
                    orderID: orderID,
                    method: method,
                    revision: revision
                )
            } else {
                phase = .unknown(orderID, message)
            }
        case let .unknown(message):
            persistResultUnknown(orderID: orderID, method: method)
            phase = .unknown(orderID, message)
        }
    }
}

actor DemoPaymentGateway: PaymentGateway {
    enum Mode: Sendable {
        case success
        case rejected
        case unknown
        case timeout
    }

    private struct OrderRecord: Sendable {
        let feature: PaymentFeature
        let method: PaymentMethod
    }

    private final class Prepared: PreparedPaymentConfirmation, @unchecked Sendable {
        let orderID: String
        private let lock = NSLock()
        private var cleared = false

        init(orderID: String) {
            self.orderID = orderID
        }

        func clear() {
            lock.withLock { cleared = true }
        }

        var isAvailable: Bool {
            lock.withLock { !cleared }
        }
    }

    private let mode: Mode
    private var orders: [String: OrderRecord] = [:]
    private var orderByIdempotencyKey: [String: String] = [:]
    private var sequence = 0

    init(mode: Mode = .success) {
        self.mode = mode
    }

    func createOrder(request: PaymentRequest, idempotencyKey: String) async throws -> PaymentOrder {
        if mode == .timeout { throw PaymentGatewayError.timedOut }
        if let existing = orderByIdempotencyKey[idempotencyKey] {
            return PaymentOrder(id: existing, externalURL: externalURL(for: request, orderID: existing))
        }
        sequence += 1
        let prefix = switch request.feature {
        case .cardRecharge: "MOCK-CARD"
        case .bathroom: "MOCK-BATH"
        case .electricity: "MOCK-ELEC"
        case .networkRecharge: "MOCK-NET"
        }
        let orderID = "\(prefix)-\(String(format: "%04d", sequence))"
        orders[orderID] = OrderRecord(
            feature: request.feature,
            method: request.method
        )
        orderByIdempotencyKey[idempotencyKey] = orderID
        return PaymentOrder(id: orderID, externalURL: externalURL(for: request, orderID: orderID))
    }

    func prepareConfirmation(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod,
        authorization: TransientPaymentAuthorization?
    ) async throws -> any PreparedPaymentConfirmation {
        guard let order = orders[orderID],
              order.feature == feature,
              order.method == method else {
            throw PaymentGatewayError.invalidResponse
        }
        if method == .campusAccount {
            guard let authorization else {
                throw PaymentValidationError.invalidPassword
            }
            var bytes = try authorization.consumeASCIIBytes()
            defer {
                for index in bytes.indices { bytes[index] = 0 }
            }
            guard bytes.count == 6,
                  bytes.allSatisfy({ (48...57).contains($0) }) else {
                throw PaymentValidationError.invalidPassword
            }
        }
        return Prepared(orderID: orderID)
    }

    func submitPreparedConfirmation(
        _ prepared: any PreparedPaymentConfirmation
    ) async throws -> PaymentOrderStatus {
        guard let prepared = prepared as? Prepared,
              prepared.isAvailable,
              orders[prepared.orderID] != nil else {
            throw PaymentGatewayError.invalidResponse
        }
        return .pending("订单已提交，正在核验服务端结果")
    }

    func status(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod
    ) async throws -> PaymentOrderStatus {
        guard let order = orders[orderID],
              order.feature == feature,
              order.method == method else {
            throw PaymentGatewayError.invalidResponse
        }
        switch mode {
        case .success: return .confirmed("服务端已确认支付成功")
        case .rejected: return .rejected("服务端拒绝了本次支付")
        case .unknown: return .unknown("服务端暂未确认结果，请稍后查询")
        case .timeout: throw PaymentGatewayError.timedOut
        }
    }

    private func externalURL(for request: PaymentRequest, orderID: String) -> URL? {
        guard request.method == .alipay else { return nil }
        return URL(string: "alipays://platformapi/startapp?appId=2019090967125695&order=\(orderID)")
    }
}

enum PaymentGatewayFactory {
    static func make(
        demo: Bool,
        production: @autoclosure () -> any PaymentGateway
    ) -> any PaymentGateway {
        if demo {
            let arguments = ProcessInfo.processInfo.arguments
            let mode: DemoPaymentGateway.Mode
            if arguments.contains("--demo-payment-error") { mode = .rejected }
            else if arguments.contains("--demo-payment-unknown") { mode = .unknown }
            else if arguments.contains("--demo-payment-timeout") { mode = .timeout }
            else { mode = .success }
            return DemoPaymentGateway(mode: mode)
        }
        return production()
    }
}

struct BathroomPaymentAccount: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let phone: String
    let cashBalance: Decimal
    let giftBalance: Decimal
}

struct ElectricityRoom: Identifiable, Equatable, Sendable {
    let id: String
    let campus: String
    let building: String
    let floor: String
    let room: String
    let balance: Decimal?
    let information: String?

    var label: String { "\(campus) · \(building) · \(floor) · \(room)" }

    init(
        id: String,
        campus: String,
        building: String,
        floor: String,
        room: String,
        balance: Decimal?,
        information: String? = nil
    ) {
        self.id = id
        self.campus = campus
        self.building = building
        self.floor = floor
        self.room = room
        self.balance = balance
        self.information = information
    }
}

enum PaymentDemoCatalog {
    static let cardAccountID = "mock-campus-card-main"
    static let cardAccountLabel = "主钱包 01"
    static let cardBalance = Decimal(string: "126.35")!
    static let phone = "13800000000"
    static let bathrooms = [
        BathroomPaymentAccount(id: "bath-zhuyuan", name: "竹园/龙河浴室", phone: phone, cashBalance: 18.60, giftBalance: 2.00),
        BathroomPaymentAccount(id: "bath-juyuan", name: "桔园/蕙园浴室", phone: phone, cashBalance: 12.30, giftBalance: 1.50),
        BathroomPaymentAccount(id: "bath-graduate", name: "研究生公寓浴室", phone: phone, cashBalance: 8.00, giftBalance: 0)
    ]
    static let electricityRooms = [
        ElectricityRoom(id: "qy-zhu-3-305", campus: "磬苑校区", building: "竹园", floor: "3 层", room: "305", balance: 20.00),
        ElectricityRoom(id: "qy-ju-5-512", campus: "磬苑校区", building: "桔园", floor: "5 层", room: "512", balance: 36.40),
        ElectricityRoom(id: "lh-north-2-203", campus: "龙河校区", building: "北楼", floor: "2 层", room: "203", balance: 15.80)
    ]
}
