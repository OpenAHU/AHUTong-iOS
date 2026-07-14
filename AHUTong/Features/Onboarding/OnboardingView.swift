import SwiftUI

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published private(set) var consent: AgreementConsent = .empty
    @Published private(set) var isLoaded = false
    @Published var showsDeclineExplanation = false
    @Published private(set) var errorMessage: String?

    private let store: any AgreementConsentStoring

    init(store: any AgreementConsentStoring) {
        self.store = store
    }

    var canContinue: Bool {
        consent.hasAcceptedRequiredDocuments
    }

    func load(resetForUITesting: Bool = false, acceptForUITesting: Bool = false) async {
        guard !isLoaded else {
            return
        }
        do {
            if resetForUITesting {
                try await store.reset()
            }
            if acceptForUITesting {
                for document in AgreementDocument.allCases {
                    _ = try await store.setAccepted(true, document: document)
                }
                consent = try await store.confirmRequiredDocuments()
            } else {
                consent = try await store.load()
            }
            errorMessage = nil
        } catch {
            consent = .empty
            errorMessage = "无法读取协议状态，请重试。"
        }
        isLoaded = true
    }

    func toggle(_ document: AgreementDocument) async {
        do {
            consent = try await store.setAccepted(!consent.isAccepted(document), document: document)
            errorMessage = nil
        } catch {
            errorMessage = "无法保存协议状态，请重试。"
        }
    }

    func resetConsent() async {
        do {
            try await store.reset()
            consent = .empty
            errorMessage = nil
        } catch {
            errorMessage = "无法撤回协议状态，请重试。"
        }
    }

    func confirmRequiredDocuments() async {
        do {
            consent = try await store.confirmRequiredDocuments()
            errorMessage = nil
        } catch {
            errorMessage = "无法保存最终确认，请重试。"
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentIndex = 0

    var body: some View {
        AndroidScreen {
            Color.black.opacity(colorScheme == .dark ? 0.50 : 0.60)
                .ignoresSafeArea()

            AndroidAgreementDialog(
                document: currentDocument,
                errorMessage: model.errorMessage,
                onAgree: acceptCurrent,
                onDecline: declineCurrent
            )
            .frame(width: 320)
        }
        .alert("需要你的同意", isPresented: $model.showsDeclineExplanation) {
            Button("继续查看", role: .cancel) { }
        } message: {
            Text("我们不会保存同意状态，也不会进入应用。你可以继续阅读并在准备好后选择同意。")
        }
    }

    private var documents: [AgreementDocument] { [.community, .privacy, .disclaimer] }

    private var currentDocument: AgreementDocument {
        documents[min(currentIndex, documents.count - 1)]
    }

    private func acceptCurrent() {
        let document = currentDocument
        Task {
            if document.isRequired && !model.consent.isAccepted(document) {
                await model.toggle(document)
            }
            if currentIndex == documents.count - 1 {
                await model.confirmRequiredDocuments()
            } else {
                currentIndex += 1
            }
        }
    }

    private func declineCurrent() {
        if currentDocument.isRequired {
            model.showsDeclineExplanation = true
        } else if currentIndex < documents.count - 1 {
            currentIndex += 1
        } else {
            Task { await model.confirmRequiredDocuments() }
        }
    }
}

private struct AndroidAgreementDialog: View {
    @Environment(\.colorScheme) private var colorScheme
    let document: AgreementDocument
    let errorMessage: String?
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(document.title)
                .font(.system(size: 24, weight: .regular))
                .accessibilityIdentifier("onboarding.title")

            ScrollView {
                Text(document.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .clipped()

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AndroidParityPalette.error)
                    .accessibilityIdentifier("onboarding.error")
            }

            HStack(spacing: 8) {
                Spacer()
                AndroidAgreementButton(
                    title: "拒绝",
                    colorScheme: colorScheme,
                    action: onDecline
                )
                    .accessibilityIdentifier("onboarding.decline")
                AndroidAgreementButton(
                    title: "同意",
                    colorScheme: colorScheme,
                    action: onAgree
                )
                    .accessibilityIdentifier("onboarding.continue")
            }
            .zIndex(1)
        }
        .padding(24)
        .background(
            AndroidParityPalette.surface(colorScheme),
            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )
    }
}

private struct AndroidAgreementButton: View {
    let title: String
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AndroidParityPalette.primaryContainer(colorScheme))
                .frame(width: 88, height: 56)
                .overlay {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                }
        }
        .buttonStyle(.plain)
    }
}

struct AgreementDetailView: View {
    let document: AgreementDocument

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AndroidHeader(title: document.title, large: true)
                    Text(document.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                }
            }
        }
        .androidDetailScreen()
    }
}
