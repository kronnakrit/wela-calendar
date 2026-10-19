import XCTest

@testable import WelaSync

final class WelaSyncTests: XCTestCase {
  func testModuleName() {
    XCTAssertEqual(WelaSyncModule.name, "WelaSync")
  }
}
