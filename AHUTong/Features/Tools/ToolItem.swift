import SwiftUI

enum ToolCategory: String, CaseIterable {
    case payment = "缴费充值", academic = "学业教务", campus = "校园生活", learning = "学习工具"
}

enum ToolItem: String, CaseIterable, Identifiable, Sendable {
    case bathroom, electricity, networkRecharge = "network-recharge"
    case grade, exam, schoolCalendar = "school-calendar", programCompletion = "program-completion"
    case freeClassroom = "free-classroom", attendance
    case lostFound = "lost-found", weather, studentMail = "student-mail", phoneBook = "phone-book"
    case canteen, cardBilling = "card-billing", studyRepository = "study-repository"

    var id: String { rawValue }
    // Keep identifiers already stored in home.widget-layout.v2.
    var homeID: String {
        self == .studyRepository ? "repository" : rawValue.replacingOccurrences(of: "-", with: "_")
    }
    var title: String { presentation.title }
    var symbol: String { presentation.symbol }
    var tint: Color { presentation.tint }
    var category: ToolCategory { presentation.category }

    private var presentation: (title: String, symbol: String, tint: Color, category: ToolCategory) {
        switch self {
        case .bathroom: ("浴室缴费", "shower.fill", .teal, .payment)
        case .electricity: ("电控缴费", "bolt.fill", .orange, .payment)
        case .networkRecharge: ("网费充值", "network", .blue, .payment)
        case .grade: ("成绩单", "chart.bar.doc.horizontal", .orange, .academic)
        case .attendance: ("教务考勤", "checkmark.rectangle", .mint, .academic)
        case .canteen: ("必吃榜", "fork.knife", .orange, .campus)
        case .exam: ("考场查询", "mappin.and.ellipse", .green, .academic)
        case .schoolCalendar: ("校历", "square.grid.2x2", .purple, .academic)
        case .programCompletion: ("培养方案", "graduationcap", .indigo, .academic)
        case .freeClassroom: ("空闲教室", "building.2", .cyan, .academic)
        case .phoneBook: ("电话本", "person.crop.rectangle.stack", .teal, .campus)
        case .studentMail: ("校园邮箱", "envelope", .blue, .campus)
        case .lostFound: ("失物招领", AndroidParitySymbol.lostAndFoundBag, .blue, .campus)
        case .weather: ("天气", "sun.max.fill", .orange, .campus)
        case .cardBilling: ("校园卡账单", "list.bullet.rectangle", .teal, .campus)
        case .studyRepository: ("学习资料", "doc.on.doc", .brown, .learning)
        }
    }
}

struct ToolDestination: View {
    let tool: ToolItem
    let appModel: AppModel

    var body: some View {
        content
            .navigationTitle(tool.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .background(NativeNavigationGestureBridge())
    }

    @ViewBuilder
    private var content: some View {
        switch tool {
        case .bathroom: BathroomPaymentView(appModel: appModel)
        case .electricity: ElectricityPaymentView(appModel: appModel)
        case .networkRecharge: NetworkRechargeView(appModel: appModel)
        case .grade: GradeView(appModel: appModel)
        case .exam: ExamView(appModel: appModel)
        case .schoolCalendar: SchoolCalendarView()
        case .programCompletion: ProgramCompletionView(appModel: appModel)
        case .freeClassroom: FreeClassroomView(appModel: appModel)
        case .attendance: AttendanceView(appModel: appModel).id(accountID)
        case .lostFound: LostFoundView(appModel: appModel)
        case .weather: WeatherView()
        case .studentMail: StudentMailView(appModel: appModel)
        case .phoneBook: PhoneBookView()
        case .canteen: CanteenRankingView(appModel: appModel).id(accountID)
        case .cardBilling: CardBillingView(appModel: appModel)
        case .studyRepository: StudyRepositoryView()
        }
    }

    private var accountID: String {
        if case let .authenticated(user) = appModel.sessionState { user.studentID } else { "guest" }
    }
}

struct ToolIcon: View {
    let tool: ToolItem

    var body: some View {
        Image(systemName: tool.symbol)
            .foregroundStyle(tool.tint)
            .overlay {
                if tool == .lostFound {
                    Image(systemName: AndroidParitySymbol.lostAndFoundQuestion)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(tool.tint)
                }
            }
            .accessibilityHidden(true)
    }
}
