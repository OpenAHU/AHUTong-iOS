import SwiftUI
import UIKit

struct CardRechargeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @AppStorage private var prefersCMB: Bool
    @StateObject private var coordinator: PaymentCoordinator
    @StateObject private var accountModel: CardRechargeAccountViewModel
    @State private var amount = ""
    @State private var showsMethodDialog = false
    @State private var showsCMBPreferenceDialog = false
    @State private var showsCMBRecharge = false
    @State private var validationMessage: String?
    private let appModel: AppModel
    private let demo: Bool

    init(
        appModel: AppModel,
        gateway: (any PaymentGateway)? = nil,
        accountDataSource: (any CardRechargeAccountDataSource)? = nil
    ) {
        self.appModel = appModel
        let isDemo = AppRuntime.isDemoSession
        demo = isDemo
        let resolved = gateway ?? PaymentGatewayFactory.make(
            demo: isDemo,
            production: YCardProductionPaymentGateway(
                campusAPI: appModel.campusAPI
            )
        )
        let resolvedAccountDataSource: any CardRechargeAccountDataSource
        if let accountDataSource {
            resolvedAccountDataSource = accountDataSource
        } else if isDemo {
            resolvedAccountDataSource = DemoCardRechargeAccountDataSource()
        } else {
            resolvedAccountDataSource = OfficialCardRechargeAccountDataSource(
                campusAPI: appModel.campusAPI
            )
        }
        let userID = if case let .authenticated(user) = appModel.sessionState { user.studentID } else { "demo" }
        let preferenceUserID = if case let .authenticated(user) = appModel.sessionState {
            user.studentID
        } else {
            "guest"
        }
        _prefersCMB = AppStorage(
            wrappedValue: false,
            AccountPreferenceKey.make(
                "payment.cmb-card-recharge-preferred",
                userID: preferenceUserID
            )
        )
        _coordinator = StateObject(wrappedValue: PaymentCoordinator(feature: .cardRecharge, gateway: resolved, userID: userID))
        _accountModel = StateObject(
            wrappedValue: CardRechargeAccountViewModel(
                dataSource: resolvedAccountDataSource
            )
        )
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "校园卡充值", large: true)
                        .accessibilityIdentifier("payment.card.screen")
                    accountCard
                    PaymentAmountCard(title: "充值金额", amount: $amount, identifier: "payment.card.amount")
                    PaymentStateButton(
                        phase: coordinator.phase,
                        identifier: "payment.card.state",
                        leadingTitle: "招商银行充值点这里",
                        leadingIdentifier: "payment.card.cmb-entry"
                    ) {
                        validateAndShowMethods()
                    } continueConfirmation: {
                        Task { await coordinator.continuePendingOrder() }
                    } reconcile: {
                        Task { await coordinator.resumeExternalReturn() }
                    } reset: {
                        coordinator.reset()
                    } leadingAction: {
                        showsCMBPreferenceDialog = true
                    }
                }
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)

            if showsMethodDialog {
                AndroidPaymentDialog(title: "确认支付", identifier: "payment.card.method-dialog") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(methodDescription)
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
            }

            if showsCMBPreferenceDialog {
                AndroidPaymentDialog(
                    title: "使用招商银行充值",
                    identifier: "payment.card.cmb-preference-dialog"
                ) {
                    Text("是否以后都默认使用招商银行充值？")
                        .foregroundStyle(.secondary)
                } actions: {
                    Button("取消", role: .cancel) {
                        showsCMBPreferenceDialog = false
                    }
                    .accessibilityIdentifier("payment.card.cmb-cancel")
                    Button("仅本次") {
                        showsCMBPreferenceDialog = false
                        showsCMBRecharge = true
                    }
                    .accessibilityIdentifier("payment.card.cmb-once")
                    Button("以后都用") {
                        prefersCMB = true
                        showsCMBPreferenceDialog = false
                        showsCMBRecharge = true
                    }
                    .accessibilityIdentifier("payment.card.cmb-always")
                }
            }
        }
        .task {
            await coordinator.resumePendingOrder()
            await accountModel.load()
        }
        .onOpenURL { url in
            guard url.scheme == "ahutong", url.host == "payment-return" else { return }
            Task { await coordinator.resumeExternalReturn() }
        }
        .navigationDestination(isPresented: $showsCMBRecharge) {
            CMBRechargeView(appModel: appModel).androidDetailScreen()
        }
        .onChange(of: coordinator.phase) { _, phase in
            guard case .succeeded = phase else { return }
            Task { await accountModel.load() }
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
                switch accountModel.state {
                case .loading:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("正在查询校园卡账户…")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16)
                    .accessibilityIdentifier("payment.card.account-loading")
                case let .ready(account):
                    PaymentValueRow(
                        title: "校园卡账户",
                        value: account.displayName.ifEmpty("--")
                    )
                    PaymentValueRow(
                        title: "账户余额",
                        value: "￥\(account.balance.currencyText)"
                    )
                case .empty:
                    PaymentReadOnlyStateRow(
                        title: "未查询到校园卡账户",
                        retryIdentifier: "payment.card.account-retry"
                    ) {
                        Task { await accountModel.load() }
                    }
                case let .failed(message):
                    PaymentReadOnlyStateRow(
                        title: message,
                        retryIdentifier: "payment.card.account-retry"
                    ) {
                        Task { await accountModel.load() }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .accessibilityIdentifier("payment.card.account")
    }

    private var user: User {
        if case let .authenticated(user) = appModel.sessionState { return user }
        return User(name: "未登录", studentID: "--")
    }

    private func validateAndShowMethods() {
        do {
            _ = try accountModel.requireReadyAccount()
            _ = try PaymentAmount(amount)
            showsMethodDialog = true
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func submit(method: PaymentMethod) {
        showsMethodDialog = false
        if !demo, method == .alipay {
            openAlipayCampusCard()
            return
        }
        Task {
            do {
                let account = try accountModel.requireReadyAccount()
                let request = try PaymentRequest(
                    feature: .cardRecharge,
                    method: method,
                    amount: PaymentAmount(amount),
                    accountID: account.id,
                    accountLabel: account.displayName,
                    context: demo ? .demo : .card(cardType: account.type)
                )
                if let url = await coordinator.submit(request) {
                    if demo {
                        await coordinator.resumeExternalReturn()
                    } else {
                        if UIApplication.shared.canOpenURL(url) {
                            openURL(url)
                        } else if AlipayCampusCardHandoff.isAllowed(
                            AlipayCampusCardHandoff.fallbackURL
                        ) {
                            openURL(AlipayCampusCardHandoff.fallbackURL)
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

    private var methodDescription: String {
        if demo {
            return "请选择支付方式。银行卡支付将从绑定的银行卡扣除￥\(amount)元；支付宝支付会跳转校园卡小程序。"
        }
        return "请选择支付方式。银行卡支付将按校园卡协议提交￥\(amount)元；支付宝支付只打开校园卡小程序，App 不传递姓名、学号、金额或支付凭据。"
    }

    private func openAlipayCampusCard() {
        guard AlipayCampusCardHandoff.isAllowed(
            AlipayCampusCardHandoff.appURL
        ) else {
            validationMessage = "支付宝校园卡入口校验失败"
            return
        }
        if UIApplication.shared.canOpenURL(AlipayCampusCardHandoff.appURL) {
            openURL(AlipayCampusCardHandoff.appURL)
        } else if AlipayCampusCardHandoff.isAllowed(
            AlipayCampusCardHandoff.fallbackURL
        ) {
            openURL(AlipayCampusCardHandoff.fallbackURL)
        } else {
            validationMessage = "支付宝校园卡入口暂不可用"
        }
    }
}

struct BathroomPaymentView: View {
    @StateObject private var coordinator: PaymentCoordinator
    @StateObject private var accountModel: BathroomAccountViewModel
    @State private var selectedName = "竹园/龙河"
    @State private var phone = ""
    @State private var amount = ""
    @State private var passwordEntry = CampusPaymentPasswordEntry()
    @State private var showsPasswordDialog = false
    @State private var validationMessage: String?
    private let demo: Bool

    init(
        appModel: AppModel,
        gateway: (any PaymentGateway)? = nil,
        accountDataSource: (any BathroomAccountDataSource)? = nil
    ) {
        let isDemo = AppRuntime.isDemoSession
        demo = isDemo
        let userID = if case let .authenticated(user) = appModel.sessionState { user.studentID } else { "demo" }
        let resolvedAccountDataSource: any BathroomAccountDataSource
        if let accountDataSource {
            resolvedAccountDataSource = accountDataSource
        } else if isDemo {
            resolvedAccountDataSource = DemoBathroomAccountDataSource()
        } else {
            resolvedAccountDataSource = OfficialBathroomAccountDataSource(
                campusAPI: appModel.campusAPI
            )
        }
        _coordinator = StateObject(wrappedValue: PaymentCoordinator(
            feature: .bathroom,
            gateway: gateway ?? PaymentGatewayFactory.make(
                demo: isDemo,
                production: YCardProductionPaymentGateway(
                    campusAPI: appModel.campusAPI
                )
            ),
            userID: userID
        ))
        _accountModel = StateObject(
            wrappedValue: BathroomAccountViewModel(
                dataSource: resolvedAccountDataSource
            )
        )
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "浴室缴费", large: true)
                        .accessibilityIdentifier("payment.bathroom.screen")
                    lookupCard
                    PaymentAmountCard(title: "缴费金额", amount: $amount, identifier: "payment.bathroom.amount")
                    PaymentStateButton(phase: coordinator.phase, identifier: "payment.bathroom.state") {
                        validateAndShowPassword()
                    } continueConfirmation: {
                        showsPasswordDialog = true
                    } reconcile: {
                        Task { await coordinator.resumePendingOrder() }
                    } reset: { resetOrContinueConfirmation() }
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
        .task {
            await coordinator.resumePendingOrder()
        }
        .onChange(of: coordinator.phase) { _, phase in
            guard case .succeeded = phase else { return }
            lookup()
        }
        .onDisappear {
            passwordEntry.reset()
            showsPasswordDialog = false
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
                        Button("竹园/龙河") {
                            selectedName = "竹园/龙河"
                            lookup()
                        }
                        Button("桔园/蕙园") {
                            selectedName = "桔园/蕙园"
                            lookup()
                        }
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
                            let normalized = String(
                                YCardReadOnlyContract.normalizedPhone(value)
                                    .prefix(11)
                            )
                            if normalized != value {
                                phone = normalized
                                return
                            }
                            if normalized.count == 11 {
                                lookup()
                            } else {
                                accountModel.reset()
                            }
                        }
                        .accessibilityIdentifier("payment.bathroom.phone")
                }
                .padding(16)
                PaymentValueRow(title: "信息", value: bathroomInformation)
                if case .loading = accountModel.state {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在查询浴室账户…")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .accessibilityIdentifier(
                        "payment.bathroom.account-loading"
                    )
                } else if shouldOfferBathroomRetry {
                    Button("重新查询") {
                        lookup()
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .accessibilityIdentifier(
                        "payment.bathroom.account-retry"
                    )
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var bathroomInformation: String {
        switch accountModel.state {
        case .idle, .loading:
            return ""
        case let .ready(account):
            return "\(account.phone)\n现金金额：\(account.cashBalance.compactText)元\n赠送金额：\(account.giftBalance.compactText)元"
        case let .empty(message), let .failed(message):
            return message
        }
    }

    private var shouldOfferBathroomRetry: Bool {
        switch accountModel.state {
        case .empty, .failed:
            phone.count == 11
        default:
            false
        }
    }

    private func lookup() {
        guard phone.count == 11 else {
            accountModel.reset()
            return
        }
        Task {
            await accountModel.lookup(
                bathroomName: selectedName,
                phone: phone
            )
        }
    }

    private func resetOrContinueConfirmation() {
        coordinator.reset()
        if case .awaitingConfirmation = coordinator.phase {
            showsPasswordDialog = true
        }
    }

    private func validateAndShowPassword() {
        do {
            guard accountModel.account != nil else {
                throw PaymentValidationError.missingAccount
            }
            _ = try PaymentAmount(amount)
            showsPasswordDialog = true
        } catch { validationMessage = error.localizedDescription }
    }

    private func submit() {
        guard passwordEntry.validate() else { return }
        if case .awaitingConfirmation = coordinator.phase {
            do {
                let authorization = try TransientPaymentAuthorization(
                    digits: passwordEntry.value
                )
                passwordEntry.reset()
                showsPasswordDialog = false
                Task {
                    await coordinator.continuePendingOrder(
                        authorization: authorization
                    )
                }
            } catch {
                passwordEntry.reset()
                showsPasswordDialog = false
                validationMessage = error.localizedDescription
            }
            return
        }
        guard let account = accountModel.account else { return }
        do {
            let context: PaymentTransactionContext
            if demo {
                context = .demo
            } else {
                guard let data = accountModel.thirdPartyJSON,
                      let thirdPartyJSON = String(data: data, encoding: .utf8) else {
                    throw PaymentValidationError.invalidTransactionContext
                }
                let feeItemID = selectedName == "竹园/龙河" ? "409" : "430"
                context = .bathroom(
                    feeItemID: feeItemID,
                    thirdPartyJSON: thirdPartyJSON
                )
            }
            let request = try PaymentRequest(
                feature: .bathroom,
                method: .campusAccount,
                amount: PaymentAmount(amount),
                accountID: account.id,
                accountLabel: account.name,
                context: context
            )
            let authorization = try TransientPaymentAuthorization(
                digits: passwordEntry.value
            )
            passwordEntry.reset()
            showsPasswordDialog = false
            Task {
                await coordinator.submit(
                    request,
                    authorization: authorization
                )
            }
        } catch {
            passwordEntry.reset()
            showsPasswordDialog = false
            validationMessage = error.localizedDescription
        }
    }

    private func passwordDialog(title: String, identifier: String, submit: @escaping () -> Void) -> some View {
        AndroidPaymentDialog(title: title, identifier: identifier) {
            SecureField(
                "密码（6 位数字）",
                text: Binding(
                    get: { passwordEntry.value },
                    set: { passwordEntry.update($0) }
                )
            )
                .accessibilityIdentifier("payment.bathroom.password")
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            if let inlineError = passwordEntry.inlineError {
                Text(inlineError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("payment.bathroom.password-error")
            }
        } actions: {
            Button("确认", action: submit)
                .accessibilityIdentifier("payment.bathroom.confirm")
            Button("取消", role: .cancel) {
                passwordEntry.reset()
                showsPasswordDialog = false
            }
        }
    }

}

struct ElectricityPaymentView: View {
    @StateObject private var coordinator: PaymentCoordinator
    @StateObject private var chargeHistory: ElectricityChargeHistoryModel
    @StateObject private var accountModel: ElectricityAccountViewModel
    @State private var amount = ""
    @State private var passwordEntry = CampusPaymentPasswordEntry()
    @State private var showsPasswordDialog = false
    @State private var showsChargeHistoryReset = false
    @State private var validationMessage: String?
    private let demo: Bool

    init(
        appModel: AppModel,
        gateway: (any PaymentGateway)? = nil,
        accountDataSource: (any ElectricityAccountDataSource)? = nil
    ) {
        let isDemo = AppRuntime.isDemoSession
        demo = isDemo
        let userID = if case let .authenticated(user) = appModel.sessionState { user.studentID } else { "demo" }
        let resolvedAccountDataSource: any ElectricityAccountDataSource
        if let accountDataSource {
            resolvedAccountDataSource = accountDataSource
        } else if isDemo {
            resolvedAccountDataSource = DemoElectricityAccountDataSource()
        } else {
            resolvedAccountDataSource =
                OfficialElectricityAccountDataSource(
                    campusAPI: appModel.campusAPI
                )
        }
        _coordinator = StateObject(wrappedValue: PaymentCoordinator(
            feature: .electricity,
            gateway: gateway ?? PaymentGatewayFactory.make(
                demo: isDemo,
                production: YCardProductionPaymentGateway(
                    campusAPI: appModel.campusAPI
                )
            ),
            userID: userID
        ))
        _chargeHistory = StateObject(
            wrappedValue: ElectricityChargeHistoryModel(userID: userID)
        )
        _accountModel = StateObject(
            wrappedValue: ElectricityAccountViewModel(
                dataSource: resolvedAccountDataSource
            )
        )
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "电控缴费", large: true)
                        .accessibilityIdentifier("payment.electricity.screen")
                    locationCard
                    if let feedback = chargeHistory.feedback {
                        Text(feedback)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.horizontal, 24)
                            .accessibilityIdentifier(
                                "payment.electricity.charge-history-message"
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    PaymentAmountCard(title: "缴费金额", amount: $amount, identifier: "payment.electricity.amount")
                    PaymentStateButton(phase: coordinator.phase, identifier: "payment.electricity.state") {
                        validateAndShowPassword()
                    } continueConfirmation: {
                        showsPasswordDialog = true
                    } reconcile: {
                        Task { await coordinator.resumePendingOrder() }
                    } reset: { resetOrContinueConfirmation() }
                }
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)

            if showsPasswordDialog {
                AndroidPaymentDialog(
                    title: "请输入校园卡密码",
                    identifier: "payment.electricity.password-dialog"
                ) {
                    SecureField(
                        "密码（6 位数字）",
                        text: Binding(
                            get: { passwordEntry.value },
                            set: { passwordEntry.update($0) }
                        )
                    )
                        .accessibilityIdentifier("payment.electricity.password")
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    if let inlineError = passwordEntry.inlineError {
                        Text(inlineError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("payment.electricity.password-error")
                    }
                } actions: {
                    Button("确认") { submit() }
                        .accessibilityIdentifier("payment.electricity.confirm")
                    Button("取消", role: .cancel) {
                        passwordEntry.reset()
                        showsPasswordDialog = false
                    }
                }
            }
        }
        .task {
            await coordinator.resumePendingOrder()
            await accountModel.load()
        }
        .onDisappear {
            passwordEntry.reset()
            showsPasswordDialog = false
            Task { await accountModel.clearCredentials() }
        }
        .onChange(of: coordinator.phase) { _, phase in
            guard case .succeeded = phase else { return }
            accountModel.retry()
        }
        .alert("确认操作", isPresented: $showsChargeHistoryReset) {
            Button("确认", role: .destructive) {
                withAnimation { chargeHistory.clear() }
                scheduleFeedbackDismissal()
            }
            .accessibilityIdentifier("payment.electricity.charge-history-reset-confirm")
            Button("取消", role: .cancel) { }
        } message: {
            Text("您确定要将累计充值金额清零吗？此操作不可撤销。")
        }
        .paymentValidationAlert($validationMessage)
    }

    private var locationCard: some View {
        AndroidCard(radius: 16) {
            VStack(spacing: 0) {
                PaymentMenuRow(
                    title: "选择校区",
                    value: accountModel.selectedCampus?.name ?? "请选择校区",
                    options: accountModel.campuses.map(\.name),
                    identifier: "payment.electricity.campus"
                ) { value in
                    accountModel.selectCampus(named: value)
                }
                PaymentMenuRow(
                    title: "选择楼栋",
                    value: accountModel.selectedBuilding?.name ?? "请选择楼栋",
                    options: accountModel.buildings.map(\.name),
                    identifier: "payment.electricity.building"
                ) { value in
                    accountModel.selectBuilding(named: value)
                }
                PaymentMenuRow(
                    title: "选择楼层",
                    value: accountModel.selectedFloor?.name ?? "请选择楼层",
                    options: accountModel.floors.map(\.name),
                    identifier: "payment.electricity.floor"
                ) { value in
                    accountModel.selectFloor(named: value)
                }
                PaymentMenuRow(
                    title: "选择房间",
                    value: accountModel.selectedRoomOption?.name ?? "请选择房间",
                    options: accountModel.rooms.map(\.name),
                    identifier: "payment.electricity.room"
                ) { value in
                    accountModel.selectRoom(named: value)
                }
                PaymentValueRow(title: "信息", value: electricityInformation)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { chargeHistory.revealInfo() }
                        scheduleFeedbackDismissal()
                    }
                    .onLongPressGesture {
                        showsChargeHistoryReset = true
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("信息")
                    .accessibilityValue(electricityInformation)
                    .accessibilityHint("连续点击五次查看累计充值记录，长按清空记录")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("payment.electricity.info")
                if accountModel.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在查询电控账户…")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .accessibilityIdentifier(
                        "payment.electricity.account-loading"
                    )
                }
                if let message = accountModel.errorMessage {
                    PaymentReadOnlyStateRow(
                        title: message,
                        retryIdentifier: "payment.electricity.account-retry"
                    ) {
                        accountModel.retry()
                    }
                } else if let message = accountModel.emptyMessage {
                    PaymentReadOnlyStateRow(
                        title: message,
                        retryIdentifier: "payment.electricity.account-retry"
                    ) {
                        accountModel.retry()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var electricityInformation: String {
        guard let selectedRoom = accountModel.selectedRoom else { return "" }
        if let information = selectedRoom.information {
            return selectedRoom.balance == nil
                ? "\(information)\n当前余量：未获取"
                : information
        }
        let amount = selectedRoom.balance.map { "￥\($0.currencyText)" }
            ?? "未获取"
        return "房间：\(selectedRoom.campus) \(selectedRoom.building) \(selectedRoom.floor) \(selectedRoom.room)\n当前余量：\(amount)"
    }

    private func validateAndShowPassword() {
        do {
            guard accountModel.selectedRoom != nil else {
                throw PaymentValidationError.missingAccount
            }
            _ = try PaymentAmount(amount)
            showsPasswordDialog = true
        } catch { validationMessage = error.localizedDescription }
    }

    private func resetOrContinueConfirmation() {
        coordinator.reset()
        if case .awaitingConfirmation = coordinator.phase {
            showsPasswordDialog = true
        }
    }

    private func submit() {
        guard passwordEntry.validate() else { return }
        if case .awaitingConfirmation = coordinator.phase {
            do {
                let authorization = try TransientPaymentAuthorization(
                    digits: passwordEntry.value
                )
                passwordEntry.reset()
                showsPasswordDialog = false
                Task {
                    await coordinator.continuePendingOrder(
                        authorization: authorization
                    )
                }
            } catch {
                passwordEntry.reset()
                showsPasswordDialog = false
                validationMessage = error.localizedDescription
            }
            return
        }
        guard let selectedRoom = accountModel.selectedRoom else { return }
        do {
            let context: PaymentTransactionContext
            if demo {
                context = .demo
            } else {
                guard let data = accountModel.selectedRoomThirdPartyJSON,
                      let thirdPartyJSON = String(data: data, encoding: .utf8) else {
                    throw PaymentValidationError.invalidTransactionContext
                }
                context = .electricity(thirdPartyJSON: thirdPartyJSON)
            }
            let paymentAmount = try PaymentAmount(amount)
            let request = try PaymentRequest(
                feature: .electricity,
                method: .campusAccount,
                amount: paymentAmount,
                accountID: selectedRoom.id,
                accountLabel: selectedRoom.label,
                context: context
            )
            let authorization = try TransientPaymentAuthorization(
                digits: passwordEntry.value
            )
            passwordEntry.reset()
            showsPasswordDialog = false
            Task { @MainActor in
                await coordinator.submit(
                    request,
                    authorization: authorization
                )
                chargeHistory.record(
                    amount: paymentAmount,
                    after: coordinator.phase
                )
            }
        } catch {
            passwordEntry.reset()
            showsPasswordDialog = false
            validationMessage = error.localizedDescription
        }
    }

    private func scheduleFeedbackDismissal() {
        guard let message = chargeHistory.feedback else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            withAnimation {
                chargeHistory.dismissFeedback(ifMatching: message)
            }
        }
    }

}

private struct PaymentReadOnlyStateRow: View {
    let title: String
    let retryIdentifier: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("重试", action: retry)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(retryIdentifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
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

struct PaymentStateButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let phase: PaymentPhase
    let identifier: String
    let leadingTitle: String?
    let leadingIdentifier: String?
    let leadingAction: (() -> Void)?
    let confirm: () -> Void
    let continueConfirmation: () -> Void
    let reconcile: () -> Void
    let reset: () -> Void

    init(
        phase: PaymentPhase,
        identifier: String,
        leadingTitle: String? = nil,
        leadingIdentifier: String? = nil,
        confirm: @escaping () -> Void,
        continueConfirmation: (() -> Void)? = nil,
        reconcile: @escaping () -> Void,
        reset: @escaping () -> Void,
        leadingAction: (() -> Void)? = nil
    ) {
        self.phase = phase
        self.identifier = identifier
        self.leadingTitle = leadingTitle
        self.leadingIdentifier = leadingIdentifier
        self.leadingAction = leadingAction
        self.confirm = confirm
        self.continueConfirmation = continueConfirmation ?? confirm
        self.reconcile = reconcile
        self.reset = reset
    }

    var body: some View {
        HStack {
            if let leadingTitle, let leadingAction {
                Button(leadingTitle, action: leadingAction)
                    .buttonStyle(.plain)
                    .foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 16)
                    .accessibilityIdentifier(leadingIdentifier ?? "")
            }
            Spacer()
            Group {
                switch phase {
                case .idle:
                    Button("确认", action: confirm)
                case .creating, .confirming, .reconciling:
                    HStack(spacing: 12) { ProgressView(); Text("支付中...").fontWeight(.bold) }
                case .awaitingConfirmation:
                    Button("继续确认支付", action: continueConfirmation)
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
                case let .creationUnknown(message):
                    Label("建单待确认：\(message)", systemImage: "questionmark")
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
        case .unknown, .creationUnknown: .orange
        case .idle: AndroidParityPalette.primaryTone90
        default: AndroidParityPalette.primaryTone80
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .failed, .unknown, .creationUnknown: .white
        default: .black
        }
    }
}

struct AndroidPaymentDialog<Content: View, Actions: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let identifier: String
    let content: Content
    let actions: Actions

    init(
        title: String,
        identifier: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.identifier = identifier
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title3.bold())
                    .accessibilityIdentifier(identifier)
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
