import SwiftUI
import UIKit

struct CardRechargeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @StateObject private var coordinator: PaymentCoordinator
    @State private var amount = ""
    @State private var balance: Decimal?
    @State private var showsMethodDialog = false
    @State private var validationMessage: String?
    private let appModel: AppModel
    private let demo: Bool

    init(appModel: AppModel, gateway: (any PaymentGateway)? = nil) {
        self.appModel = appModel
        let isDemo = ProcessInfo.processInfo.arguments.contains("--demo-session")
        demo = isDemo
        let resolved = gateway ?? PaymentGatewayFactory.make(demo: isDemo)
        _coordinator = StateObject(wrappedValue: PaymentCoordinator(feature: .cardRecharge, gateway: resolved))
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "校园卡充值", large: true)
                    accountCard
                    PaymentAmountCard(title: "充值金额", amount: $amount, identifier: "payment.card.amount")
                    PaymentStateButton(phase: coordinator.phase, identifier: "payment.card.state") {
                        validateAndShowMethods()
                    } reconcile: {
                        Task { await coordinator.resumeExternalReturn() }
                    } reset: {
                        coordinator.reset()
                    }
                }
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)

            if showsMethodDialog {
                AndroidPaymentDialog(title: "确认支付") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("请选择支付方式。银行卡支付将从绑定的银行卡扣除￥\(amount)元；支付宝支付会跳转校园卡小程序。")
                            .foregroundStyle(.secondary)
                        Text("姓名：\(user.name)\n学号：\(user.studentID)")
                        Text("iOS 不把姓名、学号或支付凭据复制到剪贴板。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } actions: {
                    Button("支付宝支付") { submit(method: .alipay) }
                        .accessibilityIdentifier("payment.card.alipay")
                    Button("银行卡支付") { submit(method: .bankCard) }
                        .accessibilityIdentifier("payment.card.bank")
                    Button("取消", role: .cancel) { showsMethodDialog = false }
                }
                .accessibilityIdentifier("payment.card.method-dialog")
            }
        }
        .accessibilityIdentifier("payment.card.screen")
        .task {
            if demo {
                balance = PaymentDemoCatalog.cardBalance
            } else if let value = try? await appModel.campusAPI.cardBalance() {
                balance = Decimal(value)
            }
            await coordinator.resumePendingOrder()
        }
        .onOpenURL { url in
            guard url.scheme == "ahutong", url.host == "payment-return" else { return }
            Task { await coordinator.resumeExternalReturn() }
        }
        .alert("无法继续", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { validationMessage = nil }
        } message: { Text(validationMessage ?? "") }
    }

    private var accountCard: some View {
        AndroidCard(radius: 16) {
            VStack(spacing: 0) {
                PaymentValueRow(
                    title: "校园卡账户",
                    value: demo ? PaymentDemoCatalog.cardAccountLabel : "\(user.name) 校园卡"
                )
                PaymentValueRow(title: "账户余额", value: balance.map { "￥\($0.currencyText)" } ?? "￥--")
            }
        }
        .padding(.horizontal, 16)
    }

    private var user: User {
        if case let .authenticated(user) = appModel.sessionState { return user }
        return User(name: "未登录", studentID: "--")
    }

    private func validateAndShowMethods() {
        do {
            _ = try PaymentAmount(amount)
            showsMethodDialog = true
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func submit(method: PaymentMethod) {
        showsMethodDialog = false
        Task {
            do {
                let request = try PaymentRequest(
                    feature: .cardRecharge,
                    method: method,
                    amount: PaymentAmount(amount),
                    accountID: PaymentDemoCatalog.cardAccountID,
                    accountLabel: PaymentDemoCatalog.cardAccountLabel
                )
                if let url = await coordinator.submit(request) {
                    if demo {
                        await coordinator.resumeExternalReturn()
                    } else {
                        if UIApplication.shared.canOpenURL(url) {
                            openURL(url)
                        } else if let fallback = URL(string: "https://www.wmslz.com/s/M6KARh485j3") {
                            openURL(fallback)
                        } else {
                            await coordinator.cancel()
                        }
                    }
                }
            } catch {
                validationMessage = error.localizedDescription
            }
        }
    }
}

struct BathroomPaymentView: View {
    @StateObject private var coordinator: PaymentCoordinator
    @State private var selectedName = "竹园/龙河"
    @State private var phone = ""
    @State private var account: BathroomPaymentAccount?
    @State private var amount = ""
    @State private var password = ""
    @State private var showsPasswordDialog = false
    @State private var validationMessage: String?
    private let demo: Bool

    init(gateway: (any PaymentGateway)? = nil) {
        let isDemo = ProcessInfo.processInfo.arguments.contains("--demo-session")
        demo = isDemo
        _coordinator = StateObject(wrappedValue: PaymentCoordinator(
            feature: .bathroom,
            gateway: gateway ?? PaymentGatewayFactory.make(demo: isDemo)
        ))
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "浴室缴费", large: true)
                    lookupCard
                    PaymentAmountCard(title: "缴费金额", amount: $amount, identifier: "payment.bathroom.amount")
                    PaymentStateButton(phase: coordinator.phase, identifier: "payment.bathroom.state") {
                        validateAndShowPassword()
                    } reconcile: {
                        Task { await coordinator.resumePendingOrder() }
                    } reset: { coordinator.reset() }
                }
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)

            if showsPasswordDialog {
                passwordDialog(title: "请输入校园卡密码", identifier: "payment.bathroom.password-dialog") {
                    submit()
                }
            }
        }
        .accessibilityIdentifier("payment.bathroom.screen")
        .task {
            await coordinator.resumePendingOrder()
        }
        .paymentValidationAlert($validationMessage)
    }

    private var lookupCard: some View {
        AndroidCard(radius: 16) {
            VStack(spacing: 0) {
                HStack {
                    Text("选择浴室").font(.headline)
                    Spacer()
                    Menu {
                        Button("竹园/龙河") { selectedName = "竹园/龙河"; lookup() }
                        Button("桔园/蕙园") { selectedName = "桔园/蕙园"; lookup() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedName)
                            Image(systemName: "arrowtriangle.down.fill").font(.caption2)
                        }
                    }
                    .accessibilityIdentifier("payment.bathroom.selector")
                }
                .padding(16)

                HStack {
                    Text("手机号").font(.headline)
                    Spacer()
                    TextField("请输入手机号", text: $phone)
                        .keyboardType(.phonePad)
                        .multilineTextAlignment(.center)
                        .frame(width: 168)
                        .onSubmit { lookup() }
                        .onChange(of: phone) { _, value in
                            phone = String(value.filter { $0.isNumber }.prefix(11))
                            if phone.count == 11 { lookup() }
                        }
                        .accessibilityIdentifier("payment.bathroom.phone")
                }
                .padding(16)
                PaymentValueRow(title: "信息", value: bathroomInformation)
            }
        }
        .padding(.horizontal, 16)
    }

    private var bathroomInformation: String {
        guard let account else { return "" }
        return "\(phone)\n现金金额：\(account.cashBalance.compactText)元\n赠送金额：\(account.giftBalance.compactText)元"
    }

    private func lookup() {
        guard demo else {
            account = nil
            validationMessage = PaymentGatewayError.safetyServiceUnavailable.localizedDescription
            return
        }
        account = PaymentDemoCatalog.bathrooms.first { $0.name.hasPrefix(selectedName.components(separatedBy: "/").first ?? selectedName) }
    }

    private func validateAndShowPassword() {
        do {
            guard account != nil else { throw PaymentValidationError.missingAccount }
            _ = try PaymentAmount(amount)
            showsPasswordDialog = true
        } catch { validationMessage = error.localizedDescription }
    }

    private func submit() {
        guard let account else { return }
        do {
            let request = try PaymentRequest(
                feature: .bathroom,
                method: .campusAccount,
                amount: PaymentAmount(amount),
                accountID: account.id,
                accountLabel: account.name,
                authorization: password
            )
            password = ""
            showsPasswordDialog = false
            Task { await coordinator.submit(request) }
        } catch { validationMessage = error.localizedDescription }
    }

    private func passwordDialog(title: String, identifier: String, submit: @escaping () -> Void) -> some View {
        AndroidPaymentDialog(title: title) {
            SecureField("密码（6 位数字）", text: $password)
                .accessibilityIdentifier("payment.bathroom.password")
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: password) { _, value in
                    password = String(value.filter { $0.isNumber }.prefix(6))
                }
        } actions: {
            Button("确认", action: submit)
            Button("取消", role: .cancel) { password = ""; showsPasswordDialog = false }
        }
        .accessibilityIdentifier(identifier)
    }
}

struct ElectricityPaymentView: View {
    @StateObject private var coordinator: PaymentCoordinator
    @State private var campus = ""
    @State private var building = ""
    @State private var floor = ""
    @State private var room = ""
    @State private var amount = ""
    @State private var password = ""
    @State private var showsPasswordDialog = false
    @State private var validationMessage: String?
    private let demo: Bool

    init(gateway: (any PaymentGateway)? = nil) {
        let isDemo = ProcessInfo.processInfo.arguments.contains("--demo-session")
        demo = isDemo
        _coordinator = StateObject(wrappedValue: PaymentCoordinator(
            feature: .electricity,
            gateway: gateway ?? PaymentGatewayFactory.make(demo: isDemo)
        ))
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "电控缴费", large: true)
                    locationCard
                    PaymentAmountCard(title: "缴费金额", amount: $amount, identifier: "payment.electricity.amount")
                    PaymentStateButton(phase: coordinator.phase, identifier: "payment.electricity.state") {
                        validateAndShowPassword()
                    } reconcile: {
                        Task { await coordinator.resumePendingOrder() }
                    } reset: { coordinator.reset() }
                }
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)

            if showsPasswordDialog {
                AndroidPaymentDialog(title: "请输入校园卡密码") {
                    SecureField("密码（6 位数字）", text: $password)
                        .accessibilityIdentifier("payment.electricity.password")
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: password) { _, value in
                            password = String(value.filter { $0.isNumber }.prefix(6))
                        }
                } actions: {
                    Button("确认") { submit() }
                    Button("取消", role: .cancel) { password = ""; showsPasswordDialog = false }
                }
                .accessibilityIdentifier("payment.electricity.password-dialog")
            }
        }
        .accessibilityIdentifier("payment.electricity.screen")
        .task {
            await coordinator.resumePendingOrder()
        }
        .paymentValidationAlert($validationMessage)
    }

    private var locationCard: some View {
        AndroidCard(radius: 16) {
            VStack(spacing: 0) {
                PaymentMenuRow(title: "选择校区", value: campus.ifEmpty("请选择校区"), options: campuses, identifier: "payment.electricity.campus") { value in
                    campus = value; building = ""; floor = ""; room = ""
                }
                PaymentMenuRow(title: "选择楼栋", value: building.ifEmpty("请选择楼栋"), options: buildings, identifier: "payment.electricity.building") { value in
                    building = value; floor = ""; room = ""
                }
                PaymentMenuRow(title: "选择楼层", value: floor.ifEmpty("请选择楼层"), options: floors, identifier: "payment.electricity.floor") { value in
                    floor = value; room = ""
                }
                PaymentMenuRow(title: "选择房间", value: room.ifEmpty("请选择房间"), options: rooms, identifier: "payment.electricity.room") { room = $0 }
                PaymentValueRow(title: "信息", value: electricityInformation)
            }
        }
        .padding(.horizontal, 16)
    }

    private var electricityInformation: String {
        guard let selectedRoom else { return "" }
        return "房间：\(selectedRoom.campus) \(selectedRoom.building) \(selectedRoom.floor) \(selectedRoom.room)\n余额：￥\(selectedRoom.balance.currencyText)"
    }

    private var campuses: [String] {
        unique(PaymentDemoCatalog.electricityRooms.map(\.campus))
    }

    private var buildings: [String] {
        unique(PaymentDemoCatalog.electricityRooms.filter { $0.campus == campus }.map(\.building))
    }

    private var floors: [String] {
        unique(PaymentDemoCatalog.electricityRooms.filter { $0.campus == campus && $0.building == building }.map(\.floor))
    }

    private var rooms: [String] {
        unique(PaymentDemoCatalog.electricityRooms.filter { $0.campus == campus && $0.building == building && $0.floor == floor }.map(\.room))
    }

    private var selectedRoom: ElectricityRoom? {
        PaymentDemoCatalog.electricityRooms.first {
            $0.campus == campus && $0.building == building && $0.floor == floor && $0.room == room
        }
    }

    private func select(_ item: ElectricityRoom) {
        campus = item.campus; building = item.building; floor = item.floor; room = item.room
    }

    private func validateAndShowPassword() {
        do {
            guard selectedRoom != nil else { throw PaymentValidationError.missingAccount }
            _ = try PaymentAmount(amount)
            showsPasswordDialog = true
        } catch { validationMessage = error.localizedDescription }
    }

    private func submit() {
        guard let selectedRoom else { return }
        do {
            let request = try PaymentRequest(
                feature: .electricity,
                method: .campusAccount,
                amount: PaymentAmount(amount),
                accountID: selectedRoom.id,
                accountLabel: selectedRoom.label,
                authorization: password
            )
            password = ""
            showsPasswordDialog = false
            Task { await coordinator.submit(request) }
        } catch { validationMessage = error.localizedDescription }
    }

    private func unique(_ values: [String]) -> [String] {
        values.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}

private struct PaymentAmountCard: View {
    let title: String
    @Binding var amount: String
    let identifier: String

    var body: some View {
        AndroidCard(radius: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.headline).padding(16)
                TextField("请输入金额", text: $amount)
                    .accessibilityIdentifier(identifier)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .onChange(of: amount) { _, value in
                        let filtered = value.filter { $0.isNumber || $0 == "." }
                        if filtered != value { amount = filtered }
                    }
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct PaymentValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title).font(.headline)
            Spacer(minLength: 16)
            Text(value).multilineTextAlignment(.trailing)
        }
        .padding(16)
    }
}

private struct PaymentMenuRow: View {
    let title: String
    let value: String
    let options: [String]
    let identifier: String
    let select: (String) -> Void

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { option in Button(option) { select(option) } }
            } label: {
                HStack(spacing: 4) {
                    Text(value)
                    Image(systemName: "arrowtriangle.down.fill").font(.caption2)
                }
            }
            .disabled(options.isEmpty)
            .accessibilityIdentifier(identifier)
        }
        .padding(16)
    }
}

private struct PaymentStateButton: View {
    let phase: PaymentPhase
    let identifier: String
    let confirm: () -> Void
    let reconcile: () -> Void
    let reset: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Group {
                switch phase {
                case .idle:
                    Button("确认", action: confirm)
                case .creating, .confirming, .reconciling:
                    HStack(spacing: 12) { ProgressView(); Text("支付中...").fontWeight(.bold) }
                case .awaitingExternal:
                    Button("核验支付结果", action: reconcile)
                case let .succeeded(orderID, _):
                    Button { reset() } label: { Label("支付成功！订单号：\(orderID)", systemImage: "checkmark") }
                case let .failed(message):
                    Button { reset() } label: { Label("支付失败！\(message)", systemImage: "xmark") }
                case .cancelled:
                    Button { reset() } label: { Label("支付已取消", systemImage: "xmark") }
                case let .unknown(_, message):
                    Button(action: reconcile) { Label("结果待确认：\(message)", systemImage: "questionmark") }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(phaseColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(backgroundColor, in: Capsule())
            .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 16)
    }

    private var backgroundColor: Color {
        switch phase {
        case .failed: .red
        case .unknown: .orange
        case .idle: AndroidParityPalette.primaryTone90
        default: AndroidParityPalette.primaryTone80
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .failed, .unknown: .white
        default: .black
        }
    }
}

private struct AndroidPaymentDialog<Content: View, Actions: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let content: Content
    let actions: Actions

    init(title: String, @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text(title).font(.title3.bold())
                content
                HStack(spacing: 18) {
                    Spacer()
                    actions
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            .padding(24)
            .frame(maxWidth: 350)
            .background(AndroidParityPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(24)
        }
    }
}

private extension View {
    func paymentValidationAlert(_ message: Binding<String?>) -> some View {
        alert("无法继续", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("知道了", role: .cancel) { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "") }
    }
}

private extension Decimal {
    var currencyText: String { String(format: "%.2f", NSDecimalNumber(decimal: self).doubleValue) }
    var compactText: String {
        let value = NSDecimalNumber(decimal: self).doubleValue
        return value.rounded() == value ? String(format: "%.1f", value) : String(format: "%.2f", value)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
