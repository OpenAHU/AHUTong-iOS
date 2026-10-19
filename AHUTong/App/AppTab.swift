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

    var iconAssetName: String {
        switch self {
        case .home:
            "TabHome"
        case .schedule:
            "TabTableChart"
        case .tools:
            "TabBuild"
        case .settings:
            "TabSettings"
        }
    }
}
