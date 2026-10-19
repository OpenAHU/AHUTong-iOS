import AppIntents
import Foundation

struct OpenPaymentCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "打开付款码"
    static let description = IntentDescription("打开安大通并显示校园卡付款码；需要登录真实校园账号。")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutNavigation.shared.request(.paymentCode)
        return .result()
    }
}

struct QueryScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "查询指定日期课表"
    static let description = IntentDescription("查询指定日期的本机课表并返回文字。无课、尚无数据和超出已同步学期会分别说明；数据以安大通最近同步或导入为准。")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "日期", kind: .date, requestValueDialog: "要查询哪一天的课表？")
    var date: Date

    static var parameterSummary: some ParameterSummary {
        Summary("查询 \(\.$date) 的课表")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = await ScheduleShortcutService().query(date: date)
        return .result(value: result.text, dialog: "\(result.text)")
    }
}

struct AHUTongShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPaymentCodeIntent(),
            phrases: ["打开\(.applicationName)付款", "打开\(.applicationName)付款码", "用\(.applicationName)打开付款码", "打开\(.applicationName)校园码"],
            shortTitle: "打开付款码",
            systemImageName: "qrcode"
        )
        AppShortcut(
            intent: QueryScheduleIntent(),
            phrases: ["用\(.applicationName)查询课表", "查询\(.applicationName)课表"],
            shortTitle: "查询指定日期课表",
            systemImageName: "calendar"
        )
    }
}
