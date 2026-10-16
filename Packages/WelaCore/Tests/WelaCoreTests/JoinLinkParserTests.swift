import XCTest

@testable import WelaCore

final class JoinLinkParserTests: XCTestCase {
  private func parse(location: String? = nil, notes: String? = nil) -> JoinLink? {
    JoinLinkParser.parse(location: location, notes: notes)
  }

  func testStructuredFieldWins() {
    let url = URL(string: "https://example.com/join")!
    let link = JoinLinkParser.parse(
      structuredURL: url, structuredKind: .teams, location: "https://meet.google.com/abc-defg-hij",
      notes: nil)
    XCTAssertEqual(link, JoinLink(url: url, kind: .teams))
  }

  func testStructuredKindInferredFromHost() {
    let url = URL(string: "https://meet.google.com/abc-defg-hij")!
    XCTAssertEqual(JoinLinkParser.parse(structuredURL: url, location: nil, notes: nil)?.kind, .meet)
  }

  func testTeamsMeetupJoin() {
    let l = parse(
      notes:
        "Join: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%7d"
    )
    XCTAssertEqual(l?.kind, .teams)
    XCTAssertTrue(l!.url.absoluteString.hasPrefix("https://teams.microsoft.com/l/meetup-join/"))
  }

  func testTeamsLinkWrappedInAngleBrackets() {
    let l = parse(
      notes: "Join <https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?x=1> now")
    XCTAssertEqual(
      l?.url.absoluteString, "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?x=1")
  }

  func testTeamsLive() {
    XCTAssertEqual(parse(notes: "https://teams.live.com/meet/9876543210?p=abc")?.kind, .teams)
  }

  func testMeet() {
    let l = parse(location: "https://meet.google.com/abc-defg-hij")
    XCTAssertEqual(l?.kind, .meet)
    XCTAssertEqual(l?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
  }

  func testMeetNotMatchedForNonMeetingPaths() {
    XCTAssertNil(parse(notes: "https://meet.google.com/landing"))
  }

  func testZoomWithPassword() {
    let l = parse(notes: "Zoom https://us02web.zoom.us/j/123456789?pwd=AbCdEf123 passcode 42")
    XCTAssertEqual(l?.kind, .zoom)
    XCTAssertEqual(l?.url.absoluteString, "https://us02web.zoom.us/j/123456789?pwd=AbCdEf123")
  }

  func testZoomWithoutSubdomain() {
    XCTAssertEqual(parse(notes: "https://zoom.us/my/someroom")?.kind, .zoom)
  }

  func testWebex() {
    XCTAssertEqual(parse(notes: "https://acme.webex.com/meet/jdoe")?.kind, .webex)
  }

  func testTrailingPunctuationTrimmed() {
    XCTAssertEqual(
      parse(notes: "Link: https://meet.google.com/abc-defg-hij.")?.url.absoluteString,
      "https://meet.google.com/abc-defg-hij")
    XCTAssertEqual(
      parse(notes: "(https://zoom.us/j/12345)")?.url.absoluteString, "https://zoom.us/j/12345")
    XCTAssertEqual(
      parse(notes: "see \"https://zoom.us/j/12345\"")?.url.absoluteString, "https://zoom.us/j/12345"
    )
  }

  func testLocationBeatsNotes() {
    let l = parse(location: "https://zoom.us/j/111", notes: "https://meet.google.com/abc-defg-hij")
    XCTAssertEqual(l?.kind, .zoom)
  }

  func testEarliestLinkInTextWins() {
    let l = parse(notes: "first https://zoom.us/j/222 then https://meet.google.com/abc-defg-hij")
    XCTAssertEqual(l?.kind, .zoom)
  }

  func testCaseInsensitiveHost() {
    XCTAssertEqual(parse(notes: "HTTPS://MEET.GOOGLE.COM/abc-defg-hij")?.kind, .meet)
  }

  func testNoLink() {
    XCTAssertNil(parse(location: "Room 4", notes: "Bring laptop https://example.com/doc"))
  }

  func testNilInputs() {
    XCTAssertNil(parse())
  }
}
