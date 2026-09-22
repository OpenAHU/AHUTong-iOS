import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var toastCenter: AppToastCenter
    @ObservedObject var appModel: AppModel
    @ObservedObject var onboardingModel: OnboardingViewModel
    @State private var showsWebLogin = false
    @State private var state: LoginState = .idle

    private enum LoginState: Equatable {
        case idle
        case working
        case failed(String)
    }

    var body: some View {
        AndroidScreen {
            VStack(spacing: 24) {
                Text("登录")
                    .font(.largeTitle)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .accessibilityIdentifier("login.title")

                Spacer()

                Text(privacyAccepted ? "🙂" : "📅")
                    .font(.system(size: 112))
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(privacyAccepted ? "使用安徽大学官方页面登录" : "安大通体验用户")
                        .font(.title3.bold())
                    Text(privacyAccepted
                        ? "账号密码和 Cookie 只保存在本机 Keychain，仅用于校园服务登录与前台会话续期。"
                        : "未同意保存登录信息，将只启用课表和设置。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                if let message = appModel.reauthenticationMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AndroidParityPalette.error)
                        .accessibilityIdentifier("login.reauthentication-message")
                }
                if case let .failed(message) = state {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AndroidParityPalette.error)
                        .accessibilityIdentifier("login.error")
                }

                Spacer()

                Button(action: login) {
                    HStack(spacing: 12) {
                        if state == .working {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: privacyAccepted ? "rectangle.portrait.and.arrow.right" : "calendar")
                        }
                        Text(state == .working ? "正在登录" : "登录")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(AndroidParityPalette.brand, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(state == .working)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .accessibilityIdentifier("login.submit")
            }
        }
        .fullScreenCover(isPresented: $showsWebLogin) {
            CampusWebLoginScreen(mode: .visibleAcademic, title: "校园账号登录") { result in
                handle(result)
            }
        }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--demo-login-state=working") {
                state = .working
            } else if arguments.contains("--demo-login-state=error") {
                state = .failed("账号或密码错误")
            }
        }
    }

    private var privacyAccepted: Bool {
        onboardingModel.consent.privacyDecision == .accepted
    }

    private func login() {
        guard state != .working else { return }
        if privacyAccepted {
            showsWebLogin = true
        } else {
            state = .working
            Task {
                await appModel.enterExperienceMode()
                state = .idle
                toastCenter.show("已进入安大通体验账户")
            }
        }
    }

    private func handle(_ result: Result<CampusWebAuthenticationResult, Error>) {
        switch result {
        case let .success(authentication):
            state = .working
            Task {
                do {
                    try await appModel.completeWebLogin(authentication)
                    state = .idle
                } catch {
                    state = .failed(error.localizedDescription)
                }
            }
        case let .failure(error):
            state = .failed(error.localizedDescription)
        }
    }
}
