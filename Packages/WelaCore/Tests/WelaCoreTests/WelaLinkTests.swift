import XCTest

@testable import WelaCore

final class WelaLinkTests: XCTestCase {
  func testRoundTrip() {
    let links: [WelaLink] = [
      .day("2026-10-21"), .event(id: "google:123:primary:abc_20261021T030000Z"),
      .join(id: "microsoft:a b&c=d:AAMk/x+y=="),
    ]
    for link in links {
      XCTAssertEqual(WelaLink(url: link.url), link, link.url.absoluteString)
    }
  }

  func testURLShape() {
    XCTAssertEqual(WelaLink.day("2026-10-21").url.absoluteString, "wela://day?d=2026-10-21")
    XCTAssertEqual(WelaLink.event(id: "a:b").url.host, "event")
  }

  func testRejectsOtherURLs() {
    XCTAssertNil(WelaLink(url: URL(string: "https://day?d=2026-10-21")!))
    XCTAssertNil(WelaLink(url: URL(string: "wela://day?d=not-a-date")!))
    XCTAssertNil(WelaLink(url: URL(string: "wela://event")!))
    XCTAssertNil(WelaLink(url: URL(string: "wela://settings")!))
    XCTAssertNil(WelaLink(url: URL(string: "com.googleusercontent.apps.1:/oauthredirect")!))
  }
}
