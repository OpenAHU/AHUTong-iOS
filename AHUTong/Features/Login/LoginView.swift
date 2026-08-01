import SwiftUI

struct LoginView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var appModel: AppModel
    @State private var studentID = ""
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var focusedField: Field = .studentID
    @State private var state: LoginState = .idle
    @FocusState private var inputFocus: Field?

    private enum Field { case studentID, password }
    private enum LoginState: Equatable {
        case idle
        case working
        case failed(String)
        case succeeded(String)
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 16) {
                    Text("登录")
                        .font(.largeTitle)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 32)
                        .accessibilityIdentifier("login.title")

                    if let message = appModel.reauthenticationMessage {
                        Label(message, systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .accessibilityIdentifier("login.reauthentication-message")
                    }

                    Spacer(minLength: 0)
                    loginFace
                    Spacer(minLength: 0)
                    fieldContainer {
                        TextField("学号", text: $studentID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .keyboardType(.asciiCapable)
                            .font(.system(.body, design: .monospaced))
                            .focused($inputFocus, equals: .studentID)
                            .submitLabel(.next)
                            .onSubmit { inputFocus = .password }
                            .accessibilityIdentifier("login.student-id")
                    }
                    fieldContainer {
                        HStack {
                            Group {
                                if passwordVisible {
                                    TextField("智慧安大密码", text: $password)
                                } else {
                                    SecureField("智慧安大密码", text: $password)
                                }
                            }
                            .textContentType(.password)
                            .font(.system(.body, design: .monospaced))
                            .focused($inputFocus, equals: .password)
                            .submitLabel(.done)
                            .onSubmit { submit() }
                            .accessibilityIdentifier("login.password")

                            Button { passwordVisible.toggle() } label: {
                                Image(systemName: passwordVisible ? "eye" : "eye.slash")
                                    .frame(width: 48, height: 48)
                            }
                            .accessibilityLabel(passwordVisible ? "隐藏密码" : "显示密码")
                        }
                    }
                }
                .padding(.bottom, 112)
                .frame(minHeight: 700)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: inputFocus) { _, newValue in
                if let newValue { focusedField = newValue }
            }
            .overlay(alignment: .bottom) { dynamicLoginButton }
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

    private var loginFace: some View {
        ZStack(alignment: .bottom) {
            Text(focusedField == .password ? "🙈" : "🙂")
                .font(.system(size: 112))
                .frame(height: 128)
            if focusedField == .password {
                HStack(spacing: 48) {
                    Text("🫲")
                    Text("🫱")
                }
                .font(.system(size: 48))
                .offset(y: 24)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: focusedField)
        .accessibilityHidden(true)
    }

    private func fieldContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 24)
            .frame(height: 64)
            .background(AndroidParityPalette.surface(colorScheme), in: Capsule())
            .padding(.horizontal, 16)
    }

    private var dynamicLoginButton: some View {
        Button(action: submit) {
            HStack(spacing: 12) {
                switch state {
                case .working:
                    ProgressView().tint(.white)
                    Text("正在登录")
                case let .failed(message):
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(message).lineLimit(1)
                case let .succeeded(message):
                    Image(systemName: "checkmark.circle.fill")
                    Text(message).lineLimit(1)
                case .idle:
                    Image(systemName: "arrow.right")
                    Text("登录")
                }
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

    private func submit() {
        guard state != .working else { return }
        let normalizedID = studentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty, !password.isEmpty else {
            state = .failed("请将信息填写完整")
            return
        }
        inputFocus = nil
        state = .working
        Task {
            do {
                try await appModel.login(studentID: normalizedID, password: password)
                state = .succeeded("登录成功")
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
