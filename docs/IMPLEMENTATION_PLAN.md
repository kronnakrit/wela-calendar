# Wela Calendar: Implementation Plan

> **Who this is for:** a coding agent, such as Claude Sonnet in Claude Code, running on a Mac with Xcode installed.
> **Source spec:** "Wela Calendar: Features & Requirements" (https://claude.ai/code/artifact/b2770c34-a531-4ee3-9721-3300207bf6fa). This plan includes everything you need from it. If the plan and the spec disagree, follow the plan and leave a note in `docs/DECISIONS.md`.

---

## 0. How to work through this plan

1. Do the milestones in order (M0 to M8). Don't start a milestone until the previous one meets its **Done when** checks.
2. After each milestone:
   - run `make test` and `make build`; both must pass
   - commit with a message like `M3: Microsoft sign-in and sync`
   - tick that milestone's boxes in `docs/PROGRESS.md`
3. Steps marked **[HUMAN]** need the project owner (accounts, keys, signing). When you reach one:
   - stop and print exactly what the owner must do and which file or value they must give you
   - carry on with work that doesn't depend on it, using the `MockProvider` (M2)
4. **Never** commit secrets, tokens or personal calendar data.
   - OAuth client IDs live in `Config/Secrets.xcconfig`, which is gitignored.
   - Commit `Config/Secrets.example.xcconfig` with placeholder values instead.
5. Keep the UI reading **only** from the local store. No view may call a network API directly.
6. When unsure between two approaches, pick the simpler one that meets the **Done when** checks and record the choice in `docs/DECISIONS.md` (one line each).
7. Some **Done when** checks need a person: visual match, VoiceOver, or signing in with a real account. For those:
   - write numbered steps in `docs/MANUAL_TESTS.md`
   - ask the owner to run them
   - carry on with the next milestone's code while you wait; don't mark the milestone done until the owner confirms
8. Don't add features this plan doesn't list.
   - Weather is deliberately excluded.
   - So are a full calendar window, task lists, and natural-language quick-add before M8.

---

## 1. Product in one paragraph

Wela Calendar (from เวลา, Thai for "time") is a macOS **menu bar** calendar.
- **Opening it:** clicking the menu bar icon, or pressing a global hotkey, drops down a 340 pt wide "paper"-styled panel.
- **Panel contents:**
  - search field
  - month grid with coloured event dots
  - agenda for the selected day
  - footer with menu, calendar filter and settings
- **Accounts:** syncs **Microsoft 365 / Outlook.com** (Microsoft Graph) and **Google / Gmail** (Google Calendar API) directly from the Mac. There is no backend server, and calendar data never leaves the Mac.
- **One-click actions:** joining a Teams, Meet, Zoom or Webex meeting, and Accept, Tentative or Decline on invites.

---

## 2. Tech stack (fixed, don't substitute)

| Concern | Choice |
| --- | --- |
| Language / UI | Swift 5.10+, SwiftUI hosted in AppKit |
| Minimum OS | macOS 14 Sonoma |
| Project generation | XcodeGen (`project.yml`). Never hand-edit `.xcodeproj` |
| Menu bar | `NSStatusItem` plus a borderless, non-activating `NSPanel` hosting SwiftUI via `NSHostingView`. **Not** `MenuBarExtra` |
| Global hotkey | `KeyboardShortcuts` (sindresorhus) via SPM |
| Local store | `GRDB.swift` (SQLite) via SPM |
| Microsoft auth | MSAL (`microsoft-authentication-library-for-objc`) via SPM |
| Google auth | `AppAuth-iOS` (supports macOS) via SPM; PKCE, system browser / `ASWebAuthenticationSession`; no embedded web views |
| HTTP | `URLSession` with async/await; no Alamofire |
| Notifications | `UserNotifications` |
| Launch at login | `SMAppService.mainApp` |
| Tests | XCTest; snapshot tests are optional and must not need network access |
| Lint | `swift-format` with default rules |
| Auto-update (M8) | Sparkle 2, only for the direct-download build |

---

## 3. Repository layout

```
wela-calendar/
├─ project.yml                  # XcodeGen
├─ Makefile                     # bootstrap, gen, build, test, lint, run
├─ Config/
│  ├─ Base.xcconfig
│  ├─ Secrets.example.xcconfig  # MS_CLIENT_ID, GOOGLE_CLIENT_ID, GOOGLE_REDIRECT_SCHEME
│  └─ Secrets.xcconfig          # gitignored
├─ App/                         # app target: entry point, AppDelegate, status item, panel
│  ├─ WelaApp.swift
│  ├─ AppDelegate.swift
│  ├─ StatusItemController.swift
│  ├─ PanelController.swift
│  ├─ Info.plist                # LSUIElement = YES, URL schemes
│  └─ Wela.entitlements
├─ Packages/
│  ├─ WelaCore/                 # models, calendar math, store, join-link parser (no UI, no network)
│  ├─ WelaSync/                 # providers, auth, sync engine, outbox (depends on WelaCore)
│  └─ WelaUI/                   # SwiftUI views, theme, view models (depends on WelaCore)
├─ docs/
│  ├─ PROGRESS.md
│  ├─ DECISIONS.md
│  └─ MANUAL_TESTS.md
└─ .gitignore
```

Each package has its own `Tests/` folder. Put most logic in `WelaCore` so it can be unit-tested without UI.

**Wiring rule:** `WelaUI` must not import `WelaSync`.
- `WelaCore` defines the protocols the UI needs: `EventActions` (join, RSVP, refresh) and `AccountActions` (add, remove, reconnect).
- `WelaSync` implements them.
- The `App` target creates the store, the sync engine and the views, and injects the implementations. This keeps the UI testable with fakes.

---

## 4. Domain model (WelaCore)

```swift
enum ProviderKind: String, Codable { case microsoft, google, mock }

struct Account: Identifiable, Codable, Hashable {
  let id: String              // uuid
  let provider: ProviderKind
  var email: String
  var displayName: String
  var status: AccountStatus   // .ok, .needsSignIn, .error(String)
}

struct CalendarInfo: Identifiable, Codable, Hashable {
  let id: String              // "\(accountId):\(providerCalendarId)"
  let accountId: String
  let providerCalendarId: String
  var name: String
  var providerColorHex: String
  var userColorHex: String?   // user override
  var isVisible: Bool
  var canEdit: Bool
}

enum ResponseStatus: String, Codable { case accepted, tentative, declined, notResponded, organizer, none }
enum EventStatus: String, Codable { case confirmed, tentative, cancelled }

struct EventInstance: Identifiable, Codable, Hashable {
  let id: String              // "\(calendarId):\(providerEventId)"
  let calendarId: String
  let providerEventId: String
  var seriesId: String?
  var title: String
  var start: Date             // UTC instant (timed events only; see note below)
  var end: Date
  var isAllDay: Bool
  var startDay: String?       // "yyyy-MM-dd", all-day events only
  var endDay: String?         // exclusive, all-day events only
  var originalTimeZone: String?
  var location: String?
  var notes: String?          // plain text; strip HTML
  var organizerEmail: String?
  var attendees: [Attendee]
  var myResponse: ResponseStatus
  var status: EventStatus
  var joinURL: URL?
  var conferenceKind: ConferenceKind?   // .teams, .meet, .zoom, .webex, .other
  var isBirthday: Bool
  var etag: String?
  var updatedAt: Date
}
```

**All-day events are dates, not instants.**
- Store them as `startDay` / `endDay` and place them on the grid by date in the user's calendar.
- Never convert them to UTC instants. Otherwise a holiday on 14 October can show from 07:00 on the 14th to 07:00 on the 15th in Bangkok.
- Both providers send all-day events date-only: Google uses `start.date`; Microsoft uses `isAllDay` with midnight times. Take only the date part.

Store tables: `account`, `calendar`, `event_instance`, `sync_state` (per calendar: `deltaLink` / `syncToken`, window start/end, `lastSyncedAt`), `outbox` (pending writes). Index `event_instance(start)` and `event_instance(calendarId)`.

Add a full-text index (FTS5) on title, location, notes and attendee names for search.

---

## 5. Paper theme tokens (WelaUI/Theme)

Define these as `Color` assets or a `Theme` struct with light ("Paper") and dark ("Night Paper") values that follow the system appearance.

| Token | Paper | Night Paper | Use |
| --- | --- | --- | --- |
| page | #F7F2E8 | #1F1D1A | panel background |
| rule | #DDD3C0 | #3A362F | dividers, panel border, card border |
| field | #EEE6D6 | #2A2722 | search field, footer pill |
| ink | #2B2925 | #ECE6D9 | titles, day numbers |
| softInk | #6F685C | #A39B8C | times, locations, icons, **past events** |
| pencil | #A9A192 | #6E685D | other-month days, placeholders, canceled events. **Decorative only; never for text users must read** |
| redPen | #B8402C | #E0715C | today ring, TODAY label, year in title |
| highlighter | #F3DF8E @55% | #5A4E22 @60% | current-week band |
| blueInk | #3D5A96 | #8FA8DE | default work calendar, Join button |
| greenInk | #5F8A5E | #93BE8F | default personal calendar |
| plumInk | #7B5486 | #B994C4 | shared calendars |
| ochre | #BF8A2C | #DDB15E | birthdays / holidays |

**Type:**
- Month title: New York (`Font.system(.title, design: .serif)`), 26 pt semibold.
- Agenda date: serif, 15 pt.
- Everything else: SF Pro.
  - Event title 13.5 pt
  - Time and location 11.5 pt, with `.monospacedDigit()` on times
  - Weekday labels 10.5 pt semibold caps

**Text size setting:** Small 0.9×, Default 1×, Large 1.15×.

**Panel:**
- 340 pt wide, 14 pt corner radius, soft shadow
- **opaque** (no vibrancy or blur)
- 16 pt horizontal padding

**Motion:** 150 ms ease-out fades and slides only. With Reduce Motion on, changes are instant.

**User calendar colours:** lower the saturation of user-picked colours by about 15% before drawing.

---

## 6. Milestones

### M0. Scaffold

**Tasks**
- [ ] `project.yml`:
  - app target `Wela`, bundle id `$(WELA_BUNDLE_ID)` from xcconfig (default `com.example.wela`)
  - the three local packages and SPM dependencies from section 2
- [ ] `Info.plist`: `LSUIElement = YES`, plus a URL scheme for the Google redirect (from xcconfig).
- [ ] Entitlements:
  - App Sandbox on
  - `com.apple.security.network.client`
  - **Don't** add the MSAL Keychain access group yet. It needs a signing team, and adding it now breaks local builds. It's added in M3.
- [ ] `Config/Base.xcconfig` pulls in secrets with an **optional** include (`#include? "Secrets.xcconfig"`), so a clean clone builds before the owner adds keys.
- [ ] `Makefile` targets:
  - `bootstrap`: brew install xcodegen and swift-format if missing, and copy `Secrets.example.xcconfig` to `Secrets.xcconfig` if it doesn't exist
  - `gen`, `build` (xcodebuild, Debug), `lint`, `run`
  - `test`: `swift test --package-path` for each of the three packages, then `xcodebuild test` for the app target. Package tests must not need code signing.
- [ ] `docs/PROGRESS.md` with every milestone checklist copied in; empty `DECISIONS.md` and `MANUAL_TESTS.md`.
- [ ] `.gitignore`: `*.xcodeproj` (generated), `Config/Secrets.xcconfig`, `DerivedData`, `.build`.

**Done when:**
- `make bootstrap gen build test` succeeds on a clean clone.
- Launching the app shows nothing in the Dock and nothing in the menu bar yet.

### M1. Core: model, calendar math, store

**Tasks**
- [ ] Models from section 4 in `WelaCore`.
- [ ] `CalendarMath`:
  - builds a 6×7 month grid for any `Calendar` (identifier `.gregorian` or `.buddhist`), locale and `firstWeekday`
  - returns `[DayCell(date, isInMonth, isToday)]`
  - **never** formats years by hand; uses `DateFormatter` with the user's calendar so Buddhist Era years print as 2569
- [ ] `AgendaBuilder`: for a given day and set of visible calendars, returns sections:
  - all-day items first, birthdays included
  - then timed items sorted by start time
  - multi-day items labelled "Day 2 of 3"
  - declined events dropped by default (setting)
  - cancelled events kept, flagged `isCancelled` (setting to hide)
- [ ] `DotSummary`: for each day, up to 4 calendar colours ordered by start time. More than 4 shows no extra mark (decision still open in the spec).
- [ ] `JoinLinkParser`. Order of precedence:
  1. the provider's structured field (passed in)
  2. regex over location, then notes, for:
     - Teams `https://teams\.microsoft\.com/l/meetup-join/\S+` and `https://teams\.live\.com/meet/\S+`
     - Meet `https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}`
     - Zoom `https://([a-z0-9-]+\.)?zoom\.us/(j|my|w)/\S+`
     - Webex `https://[a-z0-9-]+\.webex\.com/\S+`

  Trim trailing `>`, `)`, `"` and `.` characters. Return `(URL, ConferenceKind)`.
- [ ] `Store` (GRDB):
  - migrations
  - CRUD for every table
  - `observeEvents(in: DateInterval, calendars:)`, returning an `AsyncStream` or a GRDB `ValueObservation`
  - FTS search returning results grouped by day
- [ ] `HTMLStripper` for event notes (Graph returns HTML bodies).

**Tests (required)**
- Grid for October 2026, Gregorian, Sunday first: the first cell is Sep 27 and the last is Nov 7.
- The same month with Buddhist calendar and `th_TH` locale: the title formats as "ตุลาคม 2569".
- Monday-first grid.
- A DST transition month (America/New_York, March 2026).
- `AgendaBuilder`:
  - an all-day event spanning midnight in UTC+7
  - multi-day labels
  - declined and cancelled handling
- `JoinLinkParser`: at least 12 cases, including Teams links wrapped in `<...>` and Zoom links with passwords.
- Store: insert, update and delete round-trips, and FTS search finding an attendee name.

**Done when:** all tests pass and the core package has no UIKit, AppKit or SwiftUI imports.

### M2. Panel shell with mock data

**Tasks**
- [ ] `StatusItemController`:
  - a `NSStatusItem` whose button shows a calendar glyph with today's day number (SF Symbol `calendar` plus the number, or a custom template image)
  - refreshes at local midnight (`NSCalendarDayChanged`) and on time zone change (`NSSystemTimeZoneDidChange`)
- [ ] `PanelController`:
  - a non-activating `NSPanel` with `.nonactivatingPanel`, `.borderless` and `canBecomeKey = true`
  - positioned under the status button and clamped to the screen
  - closes on Esc, on the hotkey, and when the panel stops being key (`NSWindow.didResignKeyNotification`), which covers clicks outside
  - on open, call `makeKeyAndOrderFront` so the panel takes typing without activating the app
  - optional **pin** keeps it open (toggle in the menu, Control-Command-P)
- [ ] Global hotkey via `KeyboardShortcuts`. Default **Control-Option-C**.
  - **Don't use Control-Option-Space**: macOS uses it to switch input sources, and Thai users rely on that.
- [ ] `MockProvider` in `WelaSync`, compiled only in Debug builds (`#if DEBUG`) and switched on with the launch argument `-UseMockData`. Release builds must never show mock events. It seeds the store with a realistic month, including:
  - 4+ events a day
  - a birthday
  - a cancelled meeting
  - a not-responded invite
  - a Teams meeting in progress "now"
  - events in two calendars of different colours
- [ ] SwiftUI views in `WelaUI`, matching the mockup in the spec:
  - `PanelView` (VStack: SearchField, MonthHeader, MonthGrid, divider, AgendaHeader, AgendaList, Footer)
  - `MonthHeader`: serif month name, year in redPen, ‹ › buttons; clicking the title jumps to today
  - `MonthGrid`:
    - weekday labels, with today's weekday in redPen
    - 6 rows; the current-week row has the highlighter band
    - today has a slightly rotated (-10°) redPen ellipse stroke; the selected non-today day has a thin rule-colour ring
    - up to 4 dots under each day
    - other-month days drawn in pencil
  - `AgendaHeader`: "TODAY" / "TOMORROW" / weekday in redPen caps, plus the date in serif and an "N events" count on the right
  - `AgendaRow`:
    - status mark: filled circle = accepted/organizer, dashed ring = tentative/not responded, hollow ring with strikethrough text = cancelled
    - time range, title (max 2 lines), location or meeting type, conference icon
    - past events use softInk; hairline rule between rows
  - `NowCard`: the in-progress event lifts onto a white card (page lightened ~70%) with "N min left" and a filled blueInk **Join** pill. At most one at a time.
  - `Footer`: menu button (≡), "All Calendars ▾" pill, settings gear.
- [ ] Keyboard:
  - Left/Right: month
  - Shift+Left/Right: day; Shift+Up/Down: week
  - Cmd-T: today
  - Up/Down: agenda rows
  - Return: detail
  - Cmd-J: join selected
  - Esc: close
  - typing printable characters focuses search
- [ ] The agenda auto-scrolls so the current or next event is the first visible timed row.
- [ ] The panel remembers the viewed month for 5 minutes, then resets to today on open.
- [ ] Accessibility: VoiceOver labels on every row ("10:00 to 11:00, OP Weekly Meeting, Spark Room, accepted"), every day cell ("Wednesday 14 October, 4 events, today") and every button.

**Done when:**
- With mock data, the panel matches the spec mockup closely: same zones, colours and status shapes, in both light and dark.
- Opening is under 150 ms warm. Measure with `os_signpost` and record the result in `MANUAL_TESTS.md`.
- Every keyboard shortcut works.
- VoiceOver reads rows correctly.
- Add `MANUAL_TESTS.md` steps for all of the above.

### M3. Microsoft sign-in and sync (first, because the owner's main calendar is Outlook)

**[HUMAN] before this milestone:** in Microsoft Entra admin center, register an app:
- supported account types: "Accounts in any organizational directory and personal Microsoft accounts" (multi-tenant + MSA)
- add the **iOS / macOS** platform with the bundle id; this creates the redirect URI `msauth.<bundle id>://auth`
- delegated permissions: `User.Read`, `Calendars.ReadWrite`, `offline_access`

Also choose a development team in Xcode. A free Personal Team is fine for development. Put the client ID and team ID in `Secrets.xcconfig`.

**Tasks**
- [ ] Add the Keychain access group entitlement `$(AppIdentifierPrefix)com.microsoft.identity.universalstorage` (MSAL needs it on macOS), and the `msauth.<bundle id>` URL scheme to `Info.plist`.
- [ ] `MicrosoftAuth` (MSAL):
  - authority `https://login.microsoftonline.com/common`
  - interactive sign-in with `MSALWebviewParameters` and `webviewType = .authenticationSession` (system browser sheet, not an embedded web view)
  - silent token acquisition before every call
  - `MSALErrorInteractionRequired` ⇒ mark the account `.needsSignIn`
- [ ] `MicrosoftProvider`:
  - `listCalendars()` → `GET /me/calendars` (name, hexColor/color, canEdit). If `hexColor` is empty, assign the next ink colour from the theme.
  - **Initial sync per calendar:**
    - `GET /me/calendars/{id}/calendarView/delta?startDateTime=<today-90d ISO>&endDateTime=<today+365d ISO>`
    - header `Prefer: outlook.timezone="UTC", odata.maxpagesize=100`
    - follow `@odata.nextLink`; store `@odata.deltaLink`
  - **Incremental:** GET the stored deltaLink, sending the **same `Prefer` header** as the initial request. Items with `@removed` ⇒ delete locally.
  - **Window roll:** if the stored window's end is under 358 days ahead, run a fresh initial sync with a new window (about weekly).
    - Write the fresh results into a staging table.
    - Swap them in one transaction, so the panel never shows an empty calendar.
  - Note: delta doesn't support `$select`, so parse full objects.
  - Mapping:
    - `isAllDay`, `start/end.dateTime` (UTC)
    - `responseStatus.response`:
      - `accepted` ⇒ accepted
      - `tentativelyAccepted` ⇒ tentative
      - `declined` ⇒ declined
      - `none` or `notResponded` ⇒ notResponded
      - `organizer` ⇒ organizer
    - `isCancelled` ⇒ cancelled
    - `onlineMeeting.joinUrl` (+ `onlineMeetingProvider`) → joinURL
    - `location.displayName`
    - `body.content` (HTML ⇒ strip)
    - `seriesMasterId` → seriesId
- [ ] Handle HTTP 429 and 503 using `Retry-After`, with exponential backoff capped at 5 minutes.
- [ ] Unit tests with fixtures in `Tests/Fixtures/microsoft/`, covering:
  - a Teams meeting
  - a cancelled meeting
  - a series occurrence and an exception
  - an `@removed` item
  - a 429 with Retry-After

**Done when:** a real Microsoft 365 account shows real events in the panel within 60 s of a change made in Outlook on the web. Verify by hand and record in MANUAL_TESTS.md.

### M4. Google sign-in and sync

**[HUMAN] before this milestone:** create a Google Cloud project and enable the Google Calendar API, then create an OAuth client of type **iOS** with the app's bundle id.
- Its redirect uses the reversed client ID scheme (`com.googleusercontent.apps.<id>:/oauthredirect`), which works inside the sandbox.
- Don't use the "Desktop app" type: its loopback redirect needs a local HTTP server and the sandbox's `network.server` entitlement.

Put the client ID and redirect scheme in `Secrets.xcconfig`. Add the owner's account as a test user (the app stays in Testing until M8).

**Tasks**
- [ ] `GoogleAuth` (AppAuth):
  - authorization code + PKCE
  - scopes `openid email https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.calendarlist.readonly`
  - store the `OIDAuthState` (refresh token) in the Keychain, keyed by account id
  - access tokens in memory only
- [ ] `GoogleProvider`:
  - `listCalendars()` → `GET calendar/v3/users/me/calendarList` → `CalendarInfo` (`backgroundColor`, `accessRole` writer/owner ⇒ canEdit)
  - **Initial sync per calendar:**
    - `GET calendar/v3/calendars/{id}/events?singleEvents=true&maxResults=250&timeMin=<today-90d>&showDeleted=true`
    - follow `nextPageToken`
    - store `nextSyncToken` from the last page
    - **First, verify against a real account** before building on it. Write a small debug command that tries the initial request with `timeMin` alone, then with both `timeMin` and `timeMax=<today+365d>`, and logs whether each returns a `nextSyncToken`.
      - Prefer the bounded version (both limits) if it returns a token. It stops endless recurring meetings from expanding into thousands of far-future copies.
      - If neither returns a token, drop both, and discard instances older than 90 days or more than 365 days ahead before writing them.
      - Record the result in DECISIONS.md.
  - **Incremental sync:**
    - same endpoint with `syncToken=<token>` only (no timeMin, timeMax, q or orderBy) and the same `singleEvents=true`
    - items with `status == "cancelled"` are deleted locally
    - HTTP **410** ⇒ clear the token and redo the initial sync
  - Mapping:
    - `start.dateTime` / `start.date` (all-day; a date-only end is exclusive)
    - `attendees[].self == true` → `myResponse` from `responseStatus` (`needsAction` ⇒ notResponded)
    - `conferenceData.entryPoints[entryPointType == "video"].uri` → joinURL (else the parser)
    - `eventType == "birthday"` → isBirthday
- [ ] Settings → Accounts: "Add Google account" runs sign-in and adds the account and its calendars, all visible by default.
- [ ] Unit tests with recorded JSON fixtures in `Tests/Fixtures/google/`, covering:
  - an all-day event
  - a recurring instance with an exception
  - a cancelled instance
  - a needsAction invite
  - a Meet link
  - a 410 response

**Done when:** a real Microsoft 365 account and a real Google account show together in one agenda, coloured by calendar, and both reflect remote changes within 60 s.

### M5. Sync engine, actions, outbox

**Tasks**
- [ ] `SyncEngine` actor:
  - one task per account, polling every 60 s while awake and online (`NWPathMonitor`)
  - immediate sync on `NSWorkspace.didWakeNotification`, on network return, and on panel open if the last sync was over 30 s ago
  - never runs two syncs for the same calendar concurrently
- [ ] Errors never clear existing data.
  - Show "Last synced HH:mm" in the footer when offline or erroring.
  - Show an inline "Reconnect" banner for `.needsSignIn` accounts. Never a modal.
- [ ] **Join**:
  - opens joinURL with `NSWorkspace.shared.open`
  - for Teams, try `msteams:` (replace `https://teams.microsoft.com` with `msteams:`); for Zoom, `zoommtg://zoom.us/join?confno=…`; fall back to https if the app isn't installed (`NSWorkspace.urlForApplication(toOpen:)`)
- [ ] **RSVP** (Accept, Tentative, Decline) from the agenda hover buttons and the detail card:
  - Microsoft: `POST /me/events/{id}/accept|tentativelyAccept|decline` with `{"sendResponse": true}`
  - Google: `PATCH /calendars/{calId}/events/{id}?sendUpdates=all` with the attendees array, changing only the `self` attendee's `responseStatus`. Read-modify-write; use the stored etag in `If-Match`. On HTTP 412, re-fetch the event and retry once.
  - Hide the RSVP buttons when you are the organizer or the event has no attendees.
  - Behaviour:
    - write to `outbox`, then update the store optimistically (row updates in under 100 ms)
    - send when online
    - on failure, roll back and show an inline message on the row for 5 s
- [ ] **Event detail card**: clicking a row (or pressing Return) pushes a detail pane inside the panel (no new window). It shows:
  - title, time with time zone, calendar
  - location, plus an "Open in Maps" link if it's an address
  - a Join button
  - organizer and attendees with response icons
  - notes with clickable links
  - RSVP buttons
  - "Open in Outlook / Google Calendar" (web URLs)

**Tests**
- Outbox: offline RSVP is queued, then sent and cleared on reconnect.
- Rollback on failure.
- The SyncEngine doesn't double-run (use a fake provider with delays).

**Done when:** accepting an invite in Wela shows as accepted in Outlook on the web or Google Calendar, and offline RSVPs send after reconnecting.

### M6. Search, filter, settings, notifications, first run

**Tasks**
- [ ] **Search**:
  - typing in the header field filters with FTS across 90 days back and 365 days ahead
  - results grouped by date and replacing the agenda while the query is non-empty
  - Up/Down and Return open a result; Esc clears the search first, then closes the panel
- [ ] **Calendar filter**: the footer pill opens a menu that:
  - lists each account, its calendars with checkboxes, and "All Calendars"
  - saves the choice
  - immediately updates the grid dots and agenda
- [ ] **Settings window** (a standard SwiftUI `Settings` scene opened from the gear), with tabs:
  - Accounts: add, remove (removal deletes cached data and Keychain items), reconnect
  - Calendars: visibility and colour override
  - General:
    - launch at login (`SMAppService`) and hotkey recorder
    - first weekday: System / Sunday / Monday
    - calendar system: System / Gregorian / Buddhist
    - time format: System / 12h / 24h
    - text size
    - show canceled events, show declined events
  - Notifications: default alert lead time and on/off
- [ ] **Notifications**:
  - ask for permission (`requestAuthorization`) after the first account connects, not at launch
  - a category `EVENT` with actions **Join** (shown only if joinURL) and **Snooze 5 min**
  - schedule a rolling window of upcoming alerts (next 48 h), rescheduled after each sync
  - use the provider reminder if present (Microsoft `isReminderOn` + `reminderMinutesBeforeStart`; Google `reminders`, falling back to the calendar's `defaultReminders`), else the user default (10 min)
- [ ] **First run**: if there are no accounts, the panel shows three steps instead of the grid:
  1. Connect Microsoft / Connect Google buttons
  2. Choose calendars
  3. Set the hotkey (prefilled)

  Write each sync page to the store as it arrives, so the panel fills in progressively. Show "Syncing…" in the footer until the first full sync finishes. Don't try to fetch the next 30 days separately: each provider's sync token covers its whole window.
- [ ] Menu (≡): Open Outlook on the web, Open Google Calendar, Refresh now, Pin panel, Settings…, Quit Wela.

**Done when:**
- Every FR in section 7 marked M6 passes its manual test.
- Removing an account leaves no rows in the store and no Keychain items. Verify with a test.

### M7. Hardening

**Tasks**
- [ ] Performance:
  - 3 accounts and 2,000 cached events (generate them with MockProvider)
  - panel open < 150 ms warm, < 400 ms cold
  - month change < 50 ms
  - idle CPU < 0.5%, idle memory < 80 MB

  Measure with Instruments, record in MANUAL_TESTS.md, and fix any regressions.
- [ ] No timers firing more often than once a minute while the panel is closed. Use `NSBackgroundActivityScheduler` or tolerant timers.
- [ ] Recurrence and time zones: fixtures for an organizer in America/Los_Angeles viewed in Asia/Bangkok, and DST edges.
- [ ] Localization:
  - String Catalog with English and Thai
  - all dates via formatters
  - check that Thai text doesn't clip vertically (Thai glyphs are taller; add line spacing where needed)
- [ ] Accessibility:
  - full keyboard traversal
  - VoiceOver pass
  - text contrast ≥ 4.5:1 in both themes (never use the pencil token for meaningful text)
  - Reduce Motion respected
- [ ] Offline:
  - airplane mode shows cached data with "Last synced"
  - no spinners stuck on screen
- [ ] Privacy:
  - no logging of event titles or attendees in release builds (`os_log` with `.private`)
  - crash reporting off unless the user opts in (or none at all)

**Done when:** every NFR in section 7 meets its target, with evidence in MANUAL_TESTS.md.

### M8. Release prep (mostly [HUMAN])

- [ ] **[HUMAN]**:
  - Apple Developer Program membership
  - Developer ID certificate and notarization credentials, or App Store Connect if the App Store is chosen (still an open decision)
- [ ] `make release`: archive, sign, notarize (`notarytool`), staple, zip.
- [ ] Direct download only: Sparkle 2 with an appcast hosted as a static file on the same site as the privacy policy. The app is sandboxed, so follow Sparkle's sandboxing guide (installer XPC service and its entitlements).
- [ ] **[HUMAN]**:
  - public homepage and privacy policy on an owned domain, saying calendar data stays on the user's Mac and is never sent to the developer
  - Google OAuth consent screen: brand verification and sensitive-scope verification (justification and demo video)
  - Microsoft publisher verification
- [ ] Write `README.md` (build, configure secrets, architecture overview) and `PRIVACY.md`.

**Done when:** a notarized build installs on a clean Mac, and signing in with both providers works for a non-test user.

---

## 7. Requirement checklist (trace each to a milestone)

| ID | Requirement | Milestone |
| --- | --- | --- |
| FR-01 | Status item shows today's day number; updates at midnight and on time zone change | M2 |
| FR-02 | Click or global hotkey toggles the panel; works from full-screen apps | M2 |
| FR-03 | Panel anchored under the icon; closes on Esc, outside click or hotkey; can be pinned | M2 |
| FR-04 | 6-week grid; first weekday and calendar system follow macOS, overridable | M1, M6 |
| FR-05 | Up to 4 calendar-coloured dots per day | M1, M2 |
| FR-06 | Click a day to show its agenda; double-click opens the first event | M2 |
| FR-07 | All-day first, then timed; multi-day "Day 2 of 3" | M1 |
| FR-08 | Row: status shape, time, conference icon, title, location | M2 |
| FR-09 | Cancelled struck through (hideable); declined hidden by default | M1, M6 |
| FR-10 | Ended events in softInk; in-progress shows time left | M2 |
| FR-11 | Join URL from the provider field, then regex over location and notes | M1, M3, M4 |
| FR-12 | Join opens the native app if installed, else the browser | M5 |
| FR-13 | RSVP writes back; optimistic, with rollback | M5 |
| FR-14 | Detail card contents | M5 |
| FR-15 | Footer calendar filter persists | M6 |
| FR-16 | Search over cached events, grouped by date | M6 |
| FR-17 | Multiple Microsoft and Google accounts; removal deletes data and tokens | M3, M4, M6 |
| FR-18 | Per-calendar visibility and colour override | M6 |
| FR-19 | Remote changes visible within 60 s; manual Refresh | M5 |
| FR-20 | Notifications with Join and Snooze | M6 |
| FR-21 | Settings list | M6 |
| FR-22 | Recurring series and exceptions correct across time zones | M3, M4, M7 |
| NFR-01 | Open < 150 ms warm, < 400 ms cold | M7 |
| NFR-02 | Month change < 50 ms, smooth scrolling | M7 |
| NFR-03 | Freshness 60 s; 10 s after wake or network return | M5 |
| NFR-04 | Idle < 0.5% CPU, < 80 MB | M7 |
| NFR-05 | Incremental sync only; respects 429 / Retry-After | M3, M4 |
| NFR-06 | Offline read; queued RSVPs | M5 |
| NFR-07 | No server; no content analytics | all |
| NFR-08 | Tokens in Keychain only; minimum scopes | M3, M4 |
| NFR-09 | A failed sync never blanks the UI; bad tokens trigger a full resync | M5 |
| NFR-10 | macOS 14+, Apple silicon and Intel | M0 |
| NFR-11 | VoiceOver, keyboard, 4.5:1 contrast | M2, M7 |
| NFR-12 | English and Thai; Buddhist and Gregorian | M1, M7 |
| NFR-13 | Signed, notarized; Sparkle for direct download | M8 |

---

## 8. Out of scope for this plan

These are v1.1 or later; don't build them unless the owner asks:
- weather
- next-event text in the menu bar
- natural-language quick-add
- creating and editing events
- calendar sets
- widgets
- iCloud via EventKit
- multi-day agenda
- extra time zones
- find-a-time
- tasks
- full calendar window
- iPhone app

## 9. Open decisions (ask the owner; use the default meanwhile)

| Decision | Default until answered |
| --- | --- |
| Mac App Store or direct download | Build for direct download (Developer ID + Sparkle); keep App Store sandbox-compatible |
| Price model | None; no purchase code |
| Day with more than 4 events | No extra mark |
| Show declined events | Hidden |
| Next-event text in the menu bar in MVP | No |
