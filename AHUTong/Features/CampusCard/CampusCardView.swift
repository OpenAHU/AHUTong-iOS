import CoreImage.CIFilterBuiltins
import CryptoKit
import SwiftUI

extension Notification.Name {
    static let homeRefreshRequested = Notification.Name("AHUTong.homeRefreshRequested")
}
import UIKit

@MainActor
final class CampusCardViewModel: ObservableObject {
    enum BalanceState: Equatable {
        case idle
        case loading(Double?)
        case loaded(Double)
        case failed(String, Double?)
    }

    enum QRState: Equatable {
        case idle
        case loading
        case loaded(String)
        case failed(String)
    }

    @Published private(set) var balanceState: BalanceState = .idle
    @Published private(set) var qrState: QRState = .idle

    private let api: any CampusCoreAPI
    private let cacheKey: String
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    // The API does not supply an expiry time. Reuse a prefetched code only briefly.
    private static let maximumQRCodeAge: TimeInterval = 15
    private var qrLoadedAt: Date?
    #if DEBUG
    private var demoQRRequests = 0
    #endif
    private var qrRequestTask: Task<String, Error>?
    private var balanceRequestTask: Task<Double, Error>?
    private var latestQRRequestID: UUID?
    private var latestBalanceRequestID: UUID?

    init(
        api: any CampusCoreAPI, userID: String, defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.defaults = defaults
        self.now = now
        cacheKey = Self.cacheKey(for: userID)
    }

    deinit {
        qrRequestTask?.cancel()
        balanceRequestTask?.cancel()
    }

    static func cacheKey(for userID: String) -> String {
        let digest = SHA256.hash(data: Data("campus-card:\(userID)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "campus-card.balance.\(digest)"
    }

    var balance: Double? {
        switch balanceState {
        case let .loading(value), let .failed(_, value): value
        case let .loaded(value): value
        case .idle: cachedBalance
        }
    }

    func load(demo: Bool, refresh: Bool = false) async {
        if case .loading = qrState { return }
        if case .loaded = balanceState, !refresh { return }
        if demo {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo-slow-card-balance") {
                balanceState = .loading(nil)
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
            }
            #endif
            switch DemoDataState.current {
            case .normal, .empty:
                defaults.set(126.35, forKey: cacheKey)
                balanceState = .loaded(126.35)
            case .loading:
                balanceState = .loading(nil)
            case .error:
                balanceState = .failed("Mock 场景：接口返回 500", nil)
            }
            return
        }
        let requestID = UUID()
        balanceRequestTask?.cancel()
        latestBalanceRequestID = requestID
        let cached = cachedBalance
        balanceState = .loading(cached)
        let task = Task { [api] in try await api.cardBalance(allowsInteractiveLogin: false) }
        balanceRequestTask = task
        do {
            let value = try await task.value
            guard latestBalanceRequestID == requestID else { return }
            balanceRequestTask = nil
            defaults.set(value, forKey: cacheKey)
            balanceState = .loaded(value)
        } catch {
            guard latestBalanceRequestID == requestID else { return }
            balanceRequestTask = nil
            balanceState = .failed(error.localizedDescription, cached)
        }
    }

    func prefetchQRCode(demo: Bool) async {
        await loadQRCode(demo: demo)
        if case .failed = qrState { await load(demo: demo) }
    }

    func loadQRCode(demo: Bool, force: Bool = false, retryFailure: Bool = false) async {
        if case .loading = qrState, !force { return }
        if !force {
            switch qrState {
            case .loaded:
                if let qrLoadedAt, (0..<Self.maximumQRCodeAge).contains(now().timeIntervalSince(qrLoadedAt)) {
                    return
                }
            case .failed where !retryFailure: return
            case .failed: break
            case .idle, .loading:
                break
            }
        }
        qrRequestTask?.cancel()
        // Opening or refreshing a payment code takes precedence over a passive balance read.
        balanceRequestTask?.cancel()
        balanceRequestTask = nil
        latestBalanceRequestID = nil
        let requestID = UUID()
        latestQRRequestID = requestID
        qrLoadedAt = nil
        qrState = .loading
        #if DEBUG
        demoQRRequests += 1
        let failsDemoRequest = demo && ProcessInfo.processInfo.arguments.contains("--demo-card-qr-fails-twice") && demoQRRequests <= 2
        #endif
        let task = Task(priority: .userInitiated) { [api] in
            #if DEBUG
            if demo && ProcessInfo.processInfo.arguments.contains("--demo-card-qr-fails-twice") {
                try await Task.sleep(for: .seconds(1))
                if failsDemoRequest { throw URLError(.cannotConnectToHost) }
            }
            #endif
            if demo { return "AHUTONG-DEMO-PAYMENT-CODE" }
            return try await api.cardQRCode()
        }
        qrRequestTask = task
        do {
            let payload = try await task.value
            guard latestQRRequestID == requestID else { return }
            qrRequestTask = nil
            qrLoadedAt = now()
            qrState = .loaded(payload)
            await load(demo: demo, refresh: true)
        } catch {
            guard latestQRRequestID == requestID else { return }
            qrRequestTask = nil
            let message: String
            if let networkError = error as? URLError {
                message = networkError.code == .notConnectedToInternet ? "请检查网络连接" : "暂时无法连接校园服务"
            } else {
                message = error.localizedDescription
            }
            qrState = .failed(message)
        }
    }

    func invalidateQRCode() {
        latestQRRequestID = nil
        qrRequestTask?.cancel()
        qrRequestTask = nil
        qrLoadedAt = nil
        qrState = .idle
        latestBalanceRequestID = nil
        balanceRequestTask?.cancel()
        balanceRequestTask = nil
    }

    func refreshQRCodeAndBalance(demo: Bool) async {
        await loadQRCode(demo: demo, force: true)
        if case .failed = qrState { await load(demo: demo, refresh: true) }
    }

    private var cachedBalance: Double? {
        defaults.object(forKey: cacheKey) == nil ? nil : defaults.double(forKey: cacheKey)
    }
}

struct CampusCardPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inlineQRSize: CGFloat = 150
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: CampusCardViewModel
    @State private var showsQRCode = false
    @State private var showsFullQRCode = false
    @State private var previousBrightness: CGFloat?
    @State private var expandedHeight: CGFloat = 280
    private let demo: Bool
    private let paymentCodeRequestID: UUID?
    private let onRecharge: () -> Void

    init(
        api: any CampusCoreAPI, userID: String, demo: Bool,
        paymentCodeRequestID: UUID? = nil, onRecharge: @escaping () -> Void
    ) {
        self.demo = demo
        self.paymentCodeRequestID = paymentCodeRequestID
        self.onRecharge = onRecharge
        _model = StateObject(wrappedValue: CampusCardViewModel(api: api, userID: userID))
    }

    var body: some View {
        ZStack(alignment: .top) {
            balanceCard
                .frame(height: 140)
                .opacity(showsQRCode ? 0 : 1)
                .allowsHitTesting(!showsQRCode)
                .accessibilityHidden(showsQRCode)
            if showsQRCode {
                qrCard
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { expandedHeight = $0 }
                    .transition(.opacity)
            }
        }
        .frame(height: showsQRCode ? expandedHeight : 140, alignment: .top)
        .background(AndroidParityPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.86), value: showsQRCode)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: expandedHeight)
        .sensoryFeedback(.selection, trigger: showsQRCode)
        .onGeometryChange(for: CGFloat.self) { min(150, max(100, $0.size.width - 32)) } action: { inlineQRSize = $0 }
        .task { await model.prefetchQRCode(demo: demo) }
        .task(id: paymentCodeRequestID) {
            guard paymentCodeRequestID != nil else { return }
            showsQRCode = true
            await model.loadQRCode(demo: demo, force: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.prefetchQRCode(demo: demo) }
            } else if phase == .background {
                model.invalidateQRCode()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeRefreshRequested)) { _ in
            Task { await model.refreshQRCodeAndBalance(demo: demo) }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            guard scenePhase == .active, !showsQRCode, !showsFullQRCode else { return }
            Task { await model.load(demo: demo, refresh: true) }
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
            guard scenePhase == .active, showsQRCode || showsFullQRCode else { return }
            Task { await model.loadQRCode(demo: demo) }
        }
        .onDisappear {
            if !showsFullQRCode { model.invalidateQRCode() }
        }
        .fullScreenCover(isPresented: $showsFullQRCode) {
            ZStack {
                Color.black.opacity(0.82).ignoresSafeArea()
                    .onTapGesture { showsFullQRCode = false }
                qrImage(size: 320)
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .onAppear {
                previousBrightness = UIScreen.main.brightness
                UIScreen.main.brightness = 1
            }
            .onDisappear {
                if let previousBrightness { UIScreen.main.brightness = previousBrightness }
                previousBrightness = nil
            }
        }
    }

    private var balanceCard: some View {
        HStack(spacing: 0) {
            Button { showsQRCode = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("校园卡余额").font(.headline.bold())
                    balanceText.font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.72)
                    if case .failed = model.balanceState {
                        Text("余额刷新失败")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("campus-card.balance")

            Rectangle().fill(AndroidParityPalette.background(colorScheme)).frame(width: 2)

            Button(action: onRecharge) {
                Text("充\n值").font(.headline).multilineTextAlignment(.center)
                    .frame(width: 48)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("campus-card.recharge")
        }
    }

    private var qrCard: some View {
        VStack(spacing: 0) {
            HStack {
                Button { showsQRCode = false } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("收起校园码")
                    .accessibilityIdentifier("campus-card.qr-collapse")
                Spacer()
                if case .loaded = model.qrState {
                    Button { showsFullQRCode = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityIdentifier("campus-card.qr-expand")
                }
            }
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(height: 48)

            qrImage(size: inlineQRSize)

            balanceText
                .font(.title2.bold())
                .padding(.top, 12)
                .frame(maxWidth: .infinity)

        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .overlay {
            Color.clear
                .accessibilityElement()
                .accessibilityIdentifier("campus-card.qr-panel")
                .allowsHitTesting(false)
        }
        .task { await model.loadQRCode(demo: demo, retryFailure: true) }
    }

    @ViewBuilder
    private var balanceText: some View {
        if let balance = model.balance {
            Text("¥ \(balance, specifier: "%.2f")")
        } else if case .loading = model.balanceState {
            ProgressView()
        } else {
            Text("¥ --")
        }
    }

    @ViewBuilder
    private func qrImage(size: CGFloat) -> some View {
        switch model.qrState {
        case let .loaded(payload):
            Button {
                Task { await model.refreshQRCodeAndBalance(demo: demo) }
            } label: {
                PaymentQRCode(payload: payload)
                    .frame(width: size, height: size)
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("校园卡付款码，点按刷新")
            .accessibilityIdentifier("campus-card.qr-refresh")
        case .loading:
            ProgressView().frame(width: size, height: size)
                .accessibilityIdentifier("campus-card.qr-loading")
        case let .failed(message):
            Button {
                Task { await model.refreshQRCodeAndBalance(demo: demo) }
            } label: {
                Text("加载失败\n\(message)\n点此重试")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .frame(width: size, height: size)
            }
            .accessibilityIdentifier("campus-card.qr-retry")
        case .idle:
            Button("获取付款码") {
                Task { await model.refreshQRCodeAndBalance(demo: demo) }
            }
            .font(.caption)
            .frame(width: size, height: size)
            .accessibilityIdentifier("campus-card.qr-load")
        }
    }
}

private struct PaymentQRCode: View {
    let payload: String

    @State private var image: UIImage?

    var body: some View {
        Group {
        if let image {
            Image(uiImage: image).resizable().interpolation(.none)
                .padding(4).background(.white)
                .accessibilityLabel("校园卡付款码")
                .accessibilityIdentifier("campus-card.qr-image")
        } else {
            ProgressView()
        }
        }
        .task(id: payload) {
            image = nil
            let rendered = await Task.detached(priority: .userInitiated) { Self.makeImage(payload) }.value
            guard !Task.isCancelled else { return }
            image = rendered
        }
    }

    nonisolated private static func makeImage(_ payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
