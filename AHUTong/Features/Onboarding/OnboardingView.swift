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

    func load(resetForUITesting: Bool = false) async {
        guard !isLoaded else {
            return
        }
        do {
            if resetForUITesting {
                try await store.reset()
            }
            consent = try await store.load()
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("欢迎使用安大通")
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("onboarding.title")
                    Text("继续前请阅读并确认必要说明。社区与商业合作为可选内容。")
                        .foregroundStyle(.secondary)
                }

                ForEach(AgreementDocument.allCases) { document in
                    agreementRow(document)
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("onboarding.error")
                }

                VStack(spacing: 12) {
                    Button("同意并继续") {
                        Task { await model.confirmRequiredDocuments() }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!model.canContinue)
                    .accessibilityIdentifier("onboarding.continue")

                    Button("暂不同意") {
                        model.showsDeclineExplanation = true
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("onboarding.decline")
                }
            }
            .padding(24)
        }
        .navigationDestination(for: AgreementDocument.self) { document in
            AgreementDetailView(document: document)
        }
        .alert("需要你的同意", isPresented: $model.showsDeclineExplanation) {
            Button("继续查看", role: .cancel) { }
        } message: {
            Text("我们不会保存同意状态，也不会进入应用。你可以继续阅读并在准备好后选择同意。")
        }
    }

    @ViewBuilder
    private func agreementRow(_ document: AgreementDocument) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: document) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(document.title)
                            .font(.headline)
                        if !document.isRequired {
                            Text("可选")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(document.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if document.isRequired {
                Button {
                    Task { await model.toggle(document) }
                } label: {
                    Image(systemName: model.consent.isAccepted(document) ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("同意\(document.title)")
                .accessibilityIdentifier("agreement.toggle.\(document.id)")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct AgreementDetailView: View {
    let document: AgreementDocument

    var body: some View {
        ScrollView {
            Text(document.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
