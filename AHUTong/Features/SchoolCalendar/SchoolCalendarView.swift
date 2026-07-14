import SwiftUI
import UIKit

@MainActor
final class SchoolCalendarViewModel: ObservableObject {
    @Published private(set) var state: LoadableState<SchoolCalendarSnapshot> = .idle

    private let repository: SchoolCalendarRepository

    init(repository: SchoolCalendarRepository = .live()) {
        self.repository = repository
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
            switch model.state {
            case .idle, .loading:
                VStack(spacing: 16) {
                    ProgressView().tint(.white)
                    Text("正在获取校历...").foregroundStyle(.white)
                }
            case let .loaded(snapshot):
                SchoolCalendarZoomView(fileURL: snapshot.fileURL)

                HStack(spacing: 12) {
                    ShareLink(item: snapshot.fileURL) {
                        Text("保存").foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
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
                Text("暂无校历").foregroundStyle(.white)
            case let .failed(error):
                VStack(spacing: 16) {
                    Text(error.title).font(.headline).foregroundStyle(.white)
                    Text(error.message).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await model.load(policy: .refresh) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load() }
        .accessibilityIdentifier("screen.school-calendar")
    }
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
