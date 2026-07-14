import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home
    case schedule
    case tools
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home:
            "主页"
        case .schedule:
            "课表"
        case .tools:
            "小工具"
        case .settings:
            "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house"
        case .schedule:
            "tablecells"
        case .tools:
            "wrench.and.screwdriver"
        case .settings:
            "gearshape"
        }
    }
}
