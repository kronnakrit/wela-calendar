import XCTest

@testable import WelaCore

final class HTMLStripperTests: XCTestCase {
  func testBasicStructure() {
    let html = "<html><head><style>p{color:red}</style></head><body><p>Hello&nbsp;<b>world</b></p><p>Line&nbsp;two<br>three</p></body></html>"
    XCTAssertEqual(HTMLStripper.plainText(from: html), "Hello world\nLine two\nthree")
  }

  func testEntities() {
    XCTAssertEqual(HTMLStripper.plainText(from: "<div>Fish &amp; chips &lt;3 &#169; &#x41;</div>"), "Fish & chips <3 © A")
  }

  func testAnchorsKeepTheirURL() {
    let out = HTMLStripper.plainText(from: #"<a href="https://teams.microsoft.com/l/meetup-join/abc">Join the meeting now</a>"#)
    XCTAssertEqual(out, "Join the meeting now (https://teams.microsoft.com/l/meetup-join/abc)")
    XCTAssertEqual(JoinLinkParser.parse(location: nil, notes: out)?.kind, .teams)
  }

  func testAnchorWithSameTextNotDuplicated() {
    XCTAssertEqual(HTMLStripper.plainText(from: #"<a href="https://a.com/x">https://a.com/x</a>"#), "https://a.com/x")
  }

  func testBlankLinesCollapsed() {
    XCTAssertEqual(HTMLStripper.plainText(from: "<p>a</p><p></p><p></p><p></p><p>b</p>"), "a\n\nb")
  }
}
