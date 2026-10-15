import XCTest

@testable import WelaUI

final class WelaUITests: XCTestCase {
  func testModuleName() {
    XCTAssertEqual(WelaUIModule.name, "WelaUI")
  }
}
