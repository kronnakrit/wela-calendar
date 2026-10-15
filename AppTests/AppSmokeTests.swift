import XCTest

@testable import Wela

final class AppSmokeTests: XCTestCase {
  func testAppDelegateExists() {
    XCTAssertNotNil(AppDelegate())
  }
}
