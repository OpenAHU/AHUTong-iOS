import SwiftUI

@main
struct AHUTongApp: App {
    init() {
        RetiredPreferenceCleaner.clean()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
