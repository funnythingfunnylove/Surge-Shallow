import AppKit
import XCTest
@testable import SurgeShallow

@MainActor
final class ApplicationAppearanceSynchronizerTests: XCTestCase {
    func testFollowingSystemClearsAnExplicitApplicationAppearance() {
        var appliedNames: [NSAppearance.Name?] = []
        let synchronizer = ApplicationAppearanceSynchronizer { appearance in
            appliedNames.append(appearance?.name)
        }

        synchronizer.apply(.dark)
        synchronizer.apply(.system)

        XCTAssertEqual(appliedNames.count, 2)
        XCTAssertEqual(appliedNames[0], .darkAqua)
        XCTAssertNil(appliedNames[1])
    }
}
