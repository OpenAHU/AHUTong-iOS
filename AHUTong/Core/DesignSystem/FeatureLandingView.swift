import SwiftUI

struct FeatureLandingView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ScrollView {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(description)
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, minHeight: 360)
        }
        .navigationTitle(title)
    }
}
