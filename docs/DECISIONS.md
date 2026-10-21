# Decisions

One line each: what was chosen, and why.

- No Swift toolchain in the cloud container, so every build and test runs on a macOS GitHub Actions runner (`.github/workflows/ci.yml`); that is the build check.
- MSAL, AppAuth and Sparkle are added to `project.yml` in the milestone that first uses them (M3, M4, M8) instead of M0, to keep M0 builds fast and avoid unused binary dependencies. KeyboardShortcuts is in from M0.
- GRDB pinned `from: 6.29.0` (stays on 6.x; 7.x needs the Swift 6 toolchain).
- Dots: one dot per event (first four by start time, all-day first), not one per distinct calendar; cancelled events get no dot.
- `Day N of M` labels are English-only until the M7 localization pass.
- FTS5 uses the `unicode61` tokenizer, which does not segment Thai words; prefix matching still works. Revisit in M7.
- All-day events keep `start`/`end` at UTC midnight of their dates purely for range queries; placement uses `startDay`/`endDay`.
- Providers (`MicrosoftProvider`, `GoogleProvider`) talk through an injected `HTTPClient` + `AccessTokenProvider`. MSAL / AppAuth plug in later as token providers, so sync logic is tested now without credentials or those dependencies.
- Provider fixtures are inline JSON strings in the test files rather than files under `Tests/Fixtures/`, to avoid SwiftPM resource plumbing.
- Google initial sync tries `timeMin` + `timeMax` first and falls back to unbounded (trimmed locally) if no `nextSyncToken` comes back. **Still to verify against a real account**, as the plan requires; record the result here.
- RSVP: Google reads the event first and sends the fresh etag in `If-Match` (read-modify-write); on 412 it re-reads and retries once.
- Offline writes stay in the outbox (optimistic row kept); any other failure rolls the row back and is reported to the caller.
- Auth: MSAL (Microsoft) and AppAuth (Google) live in the app target (`App/Auth`) and expose `AccessTokenProvider`s; client IDs come from `Config/Secrets.xcconfig` via Info.plist. Nothing in the packages knows about them.
- Entitlements are split: `App/Wela.entitlements` (sandbox + network) is used by default so ad-hoc signed test builds run; `App/Wela.signed.entitlements` adds the MSAL keychain group and is used once `DEVELOPMENT_TEAM` is set.
- Settings are UserDefaults-backed (`SettingsModel`); the VM re-applies them on `objectWillChange`. Notifications are scheduled for a 48 h horizon with Join / Snooze 5 min actions.
- Self-review (fresh-context subagent) fixed: double percent-encoding of ids, offline token refresh now maps to `.offline` (RSVP stays queued), transient RSVP failures stay queued and block later RSVPs for the same event, one failing calendar no longer aborts the account sync, notifications re-plan every 30 min and on settings changes without dropping snoozes, join links open only https/msteams/zoommtg.
- Open from that review, to verify on real accounts: Graph all-day events under `Prefer: outlook.timezone="UTC"` may land a day early in UTC+ zones; Google syncToken path has no window roll; `listCalendars` does not follow paging; footer "last synced" does not observe `sync_state`.
- iOS: one universal app (iPhone + iPad, iOS 17) rather than separate apps. The layout switches on the horizontal size class, which covers Split View, Slide Over, rotation and bigger iPhones. "iPhone duo" from the request was read as iPhone + iPad.
- iOS shares the Mac's bundle id, so one Entra redirect and one Google iOS client serve both. Widget: `<bundle id>.widgets`; App Group `group.<bundle id>`.
- Widget data: the app's SQLite file in the App Group container, opened read-only by the widget (no migrations). The app reloads timelines on store/settings changes; BGAppRefresh syncs when closed. Widget layout and timeline logic live in WelaUI so they are unit-tested and screenshot-tested on the Mac.
- iOS settings use the App Group's UserDefaults so widgets follow week start, calendar system and time format.
- `AppActions` moved out of `AppDelegate.swift` into `App/AppActions.swift`, shared by both apps; only `join` differs per platform.
- Distribution: App Store / TestFlight via `make ios-upload` or the manual TestFlight workflow (cloud-managed signing with an App Store Connect API key).

