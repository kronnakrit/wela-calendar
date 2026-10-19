import XCTest

@testable import Wela

@MainActor
final class AppSmokeTests: XCTestCase {
  func testAppDelegateExists() {
    XCTAssertNotNil(AppDelegate())
  }

  func testStatusIconIsTemplate() {
    XCTAssertTrue(StatusItemController.icon(day: 14).isTemplate)
  }
}
