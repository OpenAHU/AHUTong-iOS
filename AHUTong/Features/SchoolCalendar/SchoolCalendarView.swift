import Photos
import SwiftUI
import UIKit

enum SchoolCalendarPhotoError: LocalizedError, Equatable {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "没有照片添加权限，请在系统设置中允许后重试。"
        }
    }
}

protocol SchoolCalendarPhotoSaving: Sendable {
    func saveImage(at fileURL: URL) async throws
}

struct PhotoKitSchoolCalendarSaver: SchoolCalendarPhotoSaving {
    func saveImage(at fileURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SchoolCalendarPhotoError.permissionDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
        }
    }
}

@MainActor
final class SchoolCalendarViewModel: ObservableObject {
    @Published private(set) var state: LoadableState<SchoolCalendarSnapshot> = .idle
    @Published var saveMessage: String?

    private let repository: SchoolCalendarRepository
    private let photoSaver: any SchoolCalendarPhotoSaving

    init(
        repository: SchoolCalendarRepository = .live(),
        photoSaver: any SchoolCalendarPhotoSaving = PhotoKitSchoolCalendarSaver()
    ) {
        self.repository = repository
        self.photoSaver = photoSaver
    }

    func load(policy: SchoolCalendarLoadPolicy = .cacheFirst) async {
        guard !state.isLoading else { return }
        state = .loading
        do {
            state = .loaded(try await repository.load(policy: policy))
        } catch {
            state = .failed(
                AppErrorState(
                    title: "校历获取失败",
                    message: "请检查网络后重试；已下载的校历仍可离线使用。"
                )
            )
        }
    }

    func savePhoto(at fileURL: URL) async {
        do {
            try await photoSaver.saveImage(at: fileURL)
            saveMessage = "校历已保存到系统照片"
        } catch {
            saveMessage = error.localizedDescription
        }
    }
}

struct SchoolCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SchoolCalendarViewModel

    init(repository: SchoolCalendarRepository = .live()) {
        _model = StateObject(
            wrappedValue: SchoolCalendarViewModel(repository: repository)
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.ignoresSafeArea()
            if demo {
                Color.gray
                    .frame(maxWidth: .infinity)
                    .frame(height: 304)
                    .frame(maxHeight: .infinity)
                    .accessibilityIdentifier("school-calendar.demo")

                HStack(spacing: 24) {
                    Button("保存") { model.saveMessage = "演示模式不会写入系统照片" }
                    Button("退出") { dismiss() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(16)
            } else {
                switch model.state {
            case .idle, .loading:
                VStack(spacing: 16) {
                    ProgressView().tint(.white)
                    Text("正在获取校历...")
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("school-calendar.loading")
                }
            case let .loaded(snapshot):
                SchoolCalendarZoomView(fileURL: snapshot.fileURL)

                HStack(spacing: 12) {
                    Button("保存") {
                        Task { await model.savePhoto(at: snapshot.fileURL) }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    Button("退出") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                }
                .padding(16)
                .background(Color.black.opacity(0.4))

                if snapshot.source == .staleCache {
                    Text("网络不可用，正在显示已缓存校历")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.4), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                    }
            case .empty:
                Text("暂无校历")
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("school-calendar.empty")
            case let .failed(error):
                VStack(spacing: 16) {
                    Text(error.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("school-calendar.error")
                    Text(error.message).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await model.load(policy: .refresh) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(32)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { if !demo { await model.load() } }
        .alert("校历", isPresented: Binding(
            get: { model.saveMessage != nil },
            set: { if !$0 { model.saveMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { model.saveMessage = nil }
        } message: {
            Text(model.saveMessage ?? "")
        }
    }

    private var demo: Bool { AppRuntime.isDemoSession }
}

private struct SchoolCalendarZoomView: View {
    let fileURL: URL

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            if let image = UIImage(contentsOfFile: fileURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnificationGesture.simultaneously(with: dragGesture))
                    .onTapGesture(count: 2, perform: resetTransform)
                    .accessibilityLabel("安徽大学校历，可双指缩放")
                    .accessibilityIdentifier("school-calendar.image")
            } else {
                ContentUnavailableView(
                    "校历文件不可读",
                    systemImage: "photo.badge.exclamationmark"
                )
            }
        }
        .background(Color.black.opacity(0.92))
        .clipped()
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = (lastScale * value.magnification).clamped(to: 0.5...5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale == 1 { resetOffset() }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func resetTransform() {
        withAnimation(.snappy) {
            scale = 1
            lastScale = 1
            resetOffset()
        }
    }

    private func resetOffset() {
        offset = .zero
        lastOffset = .zero
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
