import QuickLook
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
    @StateObject private var model: SchoolCalendarViewModel
    @State private var previewURL: URL?

    init(repository: SchoolCalendarRepository = .live()) {
        _model = StateObject(
            wrappedValue: SchoolCalendarViewModel(repository: repository)
        )
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView("正在获取校历")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(snapshot):
                VStack(spacing: 0) {
                    if snapshot.source == .staleCache {
                        Label("网络不可用，正在显示已缓存校历", systemImage: "wifi.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    SchoolCalendarZoomView(fileURL: snapshot.fileURL)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("快速预览", systemImage: "doc.text.magnifyingglass") {
                            previewURL = snapshot.fileURL
                        }
                        .labelStyle(.iconOnly)
                        ShareLink(item: snapshot.fileURL) {
                            Label("分享校历", systemImage: "square.and.arrow.up")
                        }
                        .labelStyle(.iconOnly)
                        Button("刷新", systemImage: "arrow.clockwise") {
                            Task { await model.load(policy: .refresh) }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            case .empty:
                ContentUnavailableView("暂无校历", systemImage: "calendar.badge.exclamationmark")
            case let .failed(error):
                ContentUnavailableView {
                    Label(error.title, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.message)
                } actions: {
                    Button("重试") {
                        Task { await model.load(policy: .refresh) }
                    }
                }
            }
        }
        .navigationTitle("校历")
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($previewURL)
        .task { await model.load() }
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
                scale = (lastScale * value.magnification).clamped(to: 1...5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale == 1 { resetOffset() }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
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
