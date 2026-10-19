import AppIntents
import SwiftUI

@main
struct AHUTongApp: App {
    init() {
        RetiredPreferenceCleaner.clean()
        AHUTongShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
