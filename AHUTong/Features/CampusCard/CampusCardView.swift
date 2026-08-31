import CoreImage.CIFilterBuiltins
import CryptoKit
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
        cacheKey = Self.cacheKey(for: userID)
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
    @State private var previousBrightness: CGFloat?
    private let demo: Bool
    private let onRecharge: () -> Void

    init(api: any CampusCoreAPI, userID: String, demo: Bool, onRecharge: @escaping () -> Void) {
        self.demo = demo
        self.onRecharge = onRecharge
        _model = StateObject(wrappedValue: CampusCardViewModel(api: api, userID: userID))
    }

    var body: some View {
        Group {
            if showsQRCode { qrCard } else { balanceCard }
        }
        .frame(height: showsQRCode ? nil : 140)
        .background(AndroidParityPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .task { await model.load(demo: demo) }
        .fullScreenCover(isPresented: $showsFullQRCode) {
            ZStack {
                Color.black.opacity(0.82).ignoresSafeArea()
                qrImage(size: 320)
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .onTapGesture { showsFullQRCode = false }
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
                Button { showsQRCode = false } label: { Image(systemName: "arrow.left") }
                Spacer()
                Button {
                    Task { await model.loadQRCode(demo: demo) }
                    showsFullQRCode = true
                } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
            }
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(height: 48)

            qrImage(size: 138)
                .contentShape(Rectangle())
                .onTapGesture { Task { await model.loadQRCode(demo: demo) } }

            balanceText
                .font(.title2.bold())
                .padding(.top, 12)
                .frame(maxWidth: .infinity)

        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .overlay {
            Color.clear
                .accessibilityElement()
                .accessibilityIdentifier("campus-card.qr-panel")
                .allowsHitTesting(false)
        }
        .task { await model.loadQRCode(demo: demo) }
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
            PaymentQRCode(payload: payload)
                .frame(width: size, height: size)
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1) }
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
                .accessibilityIdentifier("campus-card.qr-image")
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
