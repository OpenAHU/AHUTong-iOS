import CoreImage.CIFilterBuiltins
import SwiftUI
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

    init(api: any CampusCoreAPI, userID: String, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        cacheKey = "campus-card.balance.\(userID)"
    }

    var balance: Double? {
        switch balanceState {
        case let .loading(value), let .failed(_, value): value
        case let .loaded(value): value
        case .idle: cachedBalance
        }
    }

    func load(demo: Bool, force: Bool = false) async {
        if case .loaded = balanceState, !force { return }
        if demo {
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
        let cached = cachedBalance
        balanceState = .loading(cached)
        do {
            let value = try await api.cardBalance()
            defaults.set(value, forKey: cacheKey)
            balanceState = .loaded(value)
        } catch {
            balanceState = .failed(error.localizedDescription, cached)
        }
    }

    func loadQRCode(demo: Bool) async {
        qrState = .loading
        do {
            let payload: String
            if demo {
                payload = "AHUTONG-DEMO-PAYMENT-CODE"
            } else {
                payload = try await api.cardQRCode()
            }
            qrState = .loaded(payload)
        } catch {
            qrState = .failed(error.localizedDescription)
        }
    }

    private var cachedBalance: Double? {
        defaults.object(forKey: cacheKey) == nil ? nil : defaults.double(forKey: cacheKey)
    }
}

struct CampusCardPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: CampusCardViewModel
    @State private var showsQRCode = false
    @State private var showsFullQRCode = false
    @State private var showsRechargeNotice = false
    @State private var isScreenCaptured = UIScreen.main.isCaptured
    private let demo: Bool

    init(api: any CampusCoreAPI, userID: String, demo: Bool) {
        self.demo = demo
        _model = StateObject(wrappedValue: CampusCardViewModel(api: api, userID: userID))
    }

    var body: some View {
        Group {
            if showsQRCode { qrCard } else { balanceCard }
        }
        .frame(height: 140)
        .background(AndroidParityPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            if showsQRCode && isScreenCaptured {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.black.opacity(0.88))
                    .overlay {
                        Text("正在录屏，付款码已隐藏")
                            .font(.caption.bold()).foregroundStyle(.white)
                    }
            }
        }
        .task { await model.load(demo: demo) }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            isScreenCaptured = UIScreen.main.isCaptured
        }
        .alert("校园卡充值", isPresented: $showsRechargeNotice) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("充值写操作仍在安全整改阶段，本轮只开放与 Android 一致的余额和付款码读取。")
        }
        .fullScreenCover(isPresented: $showsFullQRCode) {
            ZStack {
                Color.black.opacity(0.82).ignoresSafeArea()
                qrImage(size: 320)
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .onTapGesture { showsFullQRCode = false }
        }
        .accessibilityIdentifier("home.campus-card")
    }

    private var balanceCard: some View {
        HStack(spacing: 0) {
            Button { showsQRCode = true } label: {
                VStack(alignment: .leading, spacing: 18) {
                    Text("校园卡余额").font(.headline.bold()).padding(.top, 15)
                    balanceText.font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("campus-card.balance")

            Rectangle().fill(AndroidParityPalette.background(colorScheme)).frame(width: 2)

            Button { showsRechargeNotice = true } label: {
                Text("充\n值").font(.headline).multilineTextAlignment(.center)
                    .frame(width: 48)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var qrCard: some View {
        VStack(spacing: 0) {
            HStack {
                Button { showsQRCode = false } label: { Image(systemName: "arrow.left") }
                Spacer()
                Button {
                    Task { await model.loadQRCode(demo: demo) }
                    showsFullQRCode = true
                } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
            }
            .font(.headline)
            .padding(.horizontal, 12)
            .frame(height: 40)

            HStack(spacing: 10) {
                qrImage(size: 78)
                VStack(alignment: .leading, spacing: 4) {
                    balanceText.font(.headline.bold())
                    Button("刷新付款码") { Task { await model.loadQRCode(demo: demo) } }
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await model.loadQRCode(demo: demo) }
        .accessibilityIdentifier("campus-card.qrcode")
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
            PaymentQRCode(payload: payload).frame(width: size, height: size)
        case .loading:
            ProgressView().frame(width: size, height: size)
        case let .failed(message):
            Text("加载失败\n\(message)").font(.caption2).multilineTextAlignment(.center)
                .frame(width: size, height: size)
        case .idle:
            Color.clear.frame(width: size, height: size)
        }
    }
}

private struct PaymentQRCode: View {
    let payload: String

    var body: some View {
        if let image = Self.makeImage(payload) {
            Image(uiImage: image).resizable().interpolation(.none)
                .padding(4).background(.white)
                .accessibilityLabel("校园卡付款码")
        } else {
            Text("加载失败")
        }
    }

    private static func makeImage(_ payload: String) -> UIImage? {
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
