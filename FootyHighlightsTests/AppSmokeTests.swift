import XCTest
@testable import Footy_Highlights

final class AppSmokeTests: XCTestCase {
    func testBundleIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "io.github.ilanladabaum.footyhighlights")
    }
}
