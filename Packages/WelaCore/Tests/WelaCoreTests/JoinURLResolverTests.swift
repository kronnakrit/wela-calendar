import XCTest

@testable import WelaCore

final class JoinURLResolverTests: XCTestCase {
  func testTeamsPrefersNativeScheme() {
    let url = URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?context=x")!
    let c = JoinURLResolver.candidates(for: url)
    XCTAssertEqual(c.count, 2)
    XCTAssertEqual(c[0].scheme, "msteams")
    XCTAssertTrue(c[0].absoluteString.hasPrefix("msteams:/l/meetup-join/19%3ameeting_abc/0"))
    XCTAssertEqual(c[1], url)
  }

  func testZoomBuildsConfnoAndPassword() {
    let url = URL(string: "https://us02web.zoom.us/j/123456789?pwd=AbC")!
    let c = JoinURLResolver.candidates(for: url)
    XCTAssertEqual(c[0].absoluteString, "zoommtg://zoom.us/join?confno=123456789&pwd=AbC")
    XCTAssertEqual(c.last, url)
  }

  func testZoomWithoutNumericIdFallsBack() {
    let url = URL(string: "https://zoom.us/my/room")!
    XCTAssertEqual(JoinURLResolver.candidates(for: url), [url])
  }

  func testMeetAndWebexAreBrowserOnly() {
    let meet = URL(string: "https://meet.google.com/abc-defg-hij")!
    XCTAssertEqual(JoinURLResolver.candidates(for: meet), [meet])
    let webex = URL(string: "https://acme.webex.com/meet/x")!
    XCTAssertEqual(JoinURLResolver.candidates(for: webex), [webex])
  }
}
