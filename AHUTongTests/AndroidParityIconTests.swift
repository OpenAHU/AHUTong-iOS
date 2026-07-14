import UIKit
import XCTest
@testable import AHUTong

final class AndroidParityIconTests: XCTestCase {
    func testRequiredToolAndSettingsSymbolsExist() {
        for systemName in AndroidParitySymbol.requiredSystemNames {
            XCTAssertNotNil(
                UIImage(systemName: systemName),
                "Missing SF Symbol: \(systemName)"
            )
        }
    }
}
