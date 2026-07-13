import SwiftUI

struct HomeView: View {
    var body: some View {
        FeatureLandingView(
            title: "主页",
            systemImage: "house",
            description: "今日课程、校园卡和天气将在对应数据能力迁移后显示。"
        )
    }
}
