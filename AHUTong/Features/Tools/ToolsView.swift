import SwiftUI

struct ToolsView: View {
    var body: some View {
        List {
            Section("校园信息") {
                NavigationLink {
                    PhoneBookView()
                } label: {
                    Label("校园电话本", systemImage: "phone")
                }
                .accessibilityIdentifier("tools.phone-book")

                NavigationLink {
                    SchoolCalendarView()
                } label: {
                    Label("校历", systemImage: "calendar")
                }
                .accessibilityIdentifier("tools.school-calendar")

                NavigationLink {
                    WeatherView()
                } label: {
                    Label("天气", systemImage: "cloud.sun")
                }
                .accessibilityIdentifier("tools.weather")
            }

            Section("学习") {
                NavigationLink {
                    StudyRepositoryView()
                } label: {
                    Label("学习资料", systemImage: "books.vertical")
                }
                .accessibilityIdentifier("tools.study-repository")
            }

            Section("继续迁移") {
                Text("成绩、考试、空闲教室和更多校园服务将按路线图继续接入。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("小工具")
    }
}
