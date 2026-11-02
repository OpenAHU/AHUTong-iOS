import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The selected photo is a local, downsampled JPEG without the source metadata.
@MainActor
final class AppBackgroundStore: ObservableObject {
    static let shared = AppBackgroundStore()

    @Published private(set) var image: UIImage?
    @Published var maskOpacity: Double {
        didSet { defaults.set(maskOpacity, forKey: "background.mask-opacity") }
    }
    @Published var motionEnabled: Bool {
        didSet { defaults.set(motionEnabled, forKey: "background.motion") }
    }
    private let defaults: UserDefaults
    private let fileURL: URL

    init() {
        defaults = AppRuntime.sessionDefaults
        let directory = AppRuntime.usesIsolatedUITestStorage
            ? FileManager.default.temporaryDirectory.appendingPathComponent("ui-tests/background")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Background")
        fileURL = directory.appendingPathComponent("photo.jpg")
        maskOpacity = defaults.object(forKey: "background.mask-opacity") as? Double ?? 0.5
        motionEnabled = defaults.bool(forKey: "background.motion")
        image = UIImage(contentsOfFile: fileURL.path)
    }

    func importPhoto(_ data: Data) async throws {
        let fileURL = fileURL
        let jpeg = try await Task.detached(priority: .userInitiated) {
            let jpeg = try BackgroundPhoto.prepare(data)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jpeg.write(to: fileURL, options: .atomic)
            return jpeg
        }.value
        image = UIImage(data: jpeg)
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        image = nil
        maskOpacity = 0.5
        motionEnabled = false
    }

    var themeColor: String? {
        guard let cgImage = image?.cgImage else { return nil }
        return BackgroundPhoto.dominantColor(cgImage)
    }
}

private enum BackgroundPhoto {
    enum ImportError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "无法读取这张照片，请换一张重试。" }
    }

    static func prepare(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ImportError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ImportError.invalidImage }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImportError.invalidImage }
        return output as Data
    }

    static func dominantColor(_ image: CGImage) -> String? {
        var pixels = [UInt8](repeating: 0, count: 24 * 24 * 4)
        guard let context = CGContext(data: &pixels, width: 24, height: 24, bitsPerComponent: 8,
                                      bytesPerRow: 24 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 24, height: 24))
        var buckets: [Int: Int] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
            guard max(r, g, b) - min(r, g, b) >= 24 else { continue }
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            buckets[key, default: 0] += 1
        }
        guard let key = buckets.max(by: {
            $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value
        })?.key else { return nil }
        return String(format: "#FF%02X%02X%02X", ((key >> 8) & 15) * 17, ((key >> 4) & 15) * 17, (key & 15) * 17)
    }
}

struct AppBackgroundView: View {
    @ObservedObject private var store = AppBackgroundStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        ZStack {
            AndroidParityPalette.background(colorScheme)
            if let image = store.image {
                MotionPhoto(image: image, enabled: store.motionEnabled && isVisible && !reduceMotion && scenePhase == .active)
                (colorScheme == .dark ? Color.black : Color.white).opacity(store.maskOpacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

private struct AppPageBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden).background(AppBackgroundView())
    }
}

extension View {
    func appBackground() -> some View { modifier(AppPageBackground()) }
}

private struct MotionPhoto: UIViewRepresentable {
    let image: UIImage
    let enabled: Bool

    func makeUIView(context: Context) -> MotionPhotoView { MotionPhotoView() }

    func updateUIView(_ view: MotionPhotoView, context: Context) {
        view.photo.image = image
        view.setMotionEnabled(enabled)
    }
}

private final class MotionPhotoView: UIView {
    let photo = UIImageView()
    private var motionEnabled = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        photo.contentMode = .scaleAspectFill
        addSubview(photo)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        photo.bounds = bounds.insetBy(dx: -18, dy: -18)
        photo.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func setMotionEnabled(_ enabled: Bool) {
        guard motionEnabled != enabled else { return }
        motionEnabled = enabled
        photo.motionEffects.forEach { photo.removeMotionEffect($0) }
        if enabled {
            let horizontal = UIInterpolatingMotionEffect(keyPath: "center.x", type: .tiltAlongHorizontalAxis)
            horizontal.minimumRelativeValue = -12
            horizontal.maximumRelativeValue = 12
            let vertical = UIInterpolatingMotionEffect(keyPath: "center.y", type: .tiltAlongVerticalAxis)
            vertical.minimumRelativeValue = -12
            vertical.maximumRelativeValue = 12
            let group = UIMotionEffectGroup()
            group.motionEffects = [horizontal, vertical]
            photo.addMotionEffect(group)
        }
    }
}
