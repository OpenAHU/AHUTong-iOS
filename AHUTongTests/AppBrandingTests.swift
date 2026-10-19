import SwiftUI
import UIKit
import XCTest
@testable import AHUTong

final class AppBrandingTests: XCTestCase {
    @MainActor
    func testSplashRendersWithBundledAppIconInBothAppearances() throws {
        let icon = try XCTUnwrap(UIImage(named: "AppMark"))
        XCTAssertGreaterThan(icon.size.width, 0)

        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content:
                AppSplashView()
                    .frame(width: 402, height: 874)
                    .environment(\.colorScheme, scheme)
            )
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "app-splash-\(scheme == .light ? "light" : "dark")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
