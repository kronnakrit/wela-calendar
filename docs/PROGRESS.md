# Progress

Tick a milestone's boxes only when its **Done when** checks pass (see `IMPLEMENTATION_PLAN.md`). Checks that need a person are tracked in `MANUAL_TESTS.md`.

## M0. Scaffold

- [x] `project.yml`:
- [x] `Info.plist`: `LSUIElement = YES`, plus a URL scheme for the Google redirect (from xcconfig).
- [x] Entitlements:
- [x] `Config/Base.xcconfig` pulls in secrets with an **optional** include (`#include? "Secrets.xcconfig"`), so a cl
- [x] `Makefile` targets:
- [x] `docs/PROGRESS.md` with every milestone checklist copied in; empty `DECISIONS.md` and `MANUAL_TESTS.md`.
- [x] `.gitignore`: `*.xcodeproj` (generated), `Config/Secrets.xcconfig`, `DerivedData`, `.build`.

## M1. Core: model, calendar math, store

- [x] Models from section 4 in `WelaCore`.
- [x] `CalendarMath`:
- [x] `AgendaBuilder`: for a given day and set of visible calendars, returns sections:
- [x] `DotSummary`: for each day, up to 4 calendar colours ordered by start time. More than 4 shows no extra mark (d
- [x] `JoinLinkParser`. Order of precedence:
- [x] `Store` (GRDB):
- [x] `HTMLStripper` for event notes (Graph returns HTML bodies).

## M2. Panel shell with mock data

Code complete and CI-green; waiting on the manual checks in `MANUAL_TESTS.md` (visual match, timing, VoiceOver) before ticking.

- [ ] `StatusItemController`:
- [ ] `PanelController`:
- [ ] Global hotkey via `KeyboardShortcuts`. Default **Control-Option-C**.
- [ ] `MockProvider` in `WelaSync`, compiled only in Debug builds (`#if DEBUG`) and switched on with the launch argu
- [ ] SwiftUI views in `WelaUI`, matching the mockup in the spec:
- [ ] Keyboard:
- [ ] The agenda auto-scrolls so the current or next event is the first visible timed row.
- [ ] The panel remembers the viewed month for 5 minutes, then resets to today on open.
- [ ] Accessibility: VoiceOver labels on every row ("10:00 to 11:00, OP Weekly Meeting, Spark Room, accepted"), ever

## M3. Microsoft sign-in and sync (first, because the owner's main calendar is Outlook)

Groundwork done and CI-green: `MicrosoftProvider` (delta sync, window roll, Retry-After, RSVP) with fixture tests. Still open: MSAL sign-in, Keychain entitlement, Settings → Accounts, real-account check. Needs the Entra client ID.

- [ ] Add the Keychain access group entitlement `$(AppIdentifierPrefix)com.microsoft.identity.universalstorage` (MSA
- [ ] `MicrosoftAuth` (MSAL):
- [ ] `MicrosoftProvider`:
- [ ] Handle HTTP 429 and 503 using `Retry-After`, with exponential backoff capped at 5 minutes.
- [ ] Unit tests with fixtures in `Tests/Fixtures/microsoft/`, covering:

## M4. Google sign-in and sync

Groundwork done and CI-green: `GoogleProvider` (initial/incremental sync, 410 recovery, RSVP) with fixture tests. Still open: AppAuth sign-in, the real-account check of the bounded initial sync. Needs the Google OAuth client.

- [ ] `GoogleAuth` (AppAuth):
- [ ] `GoogleProvider`:
- [ ] Settings → Accounts: "Add Google account" runs sign-in and adds the account and its calendars, all visible by 
- [ ] Unit tests with recorded JSON fixtures in `Tests/Fixtures/google/`, covering:

## M5. Sync engine, actions, outbox

Groundwork done and CI-green: `SyncEngine` (per-calendar no-double-run, errors keep data) and the RSVP outbox (optimistic, offline queue, rollback). Still open: 60 s polling / wake / network triggers, Join via native apps, full detail card, footer "Last synced" and Reconnect banner.

- [ ] `SyncEngine` actor:
- [ ] Errors never clear existing data.
- [ ] **Join**:
- [ ] **RSVP** (Accept, Tentative, Decline) from the agenda hover buttons and the detail card:
- [ ] **Event detail card**: clicking a row (or pressing Return) pushes a detail pane inside the panel (no new windo

## M6. Search, filter, settings, notifications, first run

- [ ] **Search**:
- [ ] **Calendar filter**: the footer pill opens a menu that:
- [ ] **Settings window** (a standard SwiftUI `Settings` scene opened from the gear), with tabs:
- [ ] **Notifications**:
- [ ] **First run**: if there are no accounts, the panel shows three steps instead of the grid:
- [ ] Menu (≡): Open Outlook on the web, Open Google Calendar, Refresh now, Pin panel, Settings…, Quit Wela.

## M7. Hardening

- [ ] Performance:
- [ ] No timers firing more often than once a minute while the panel is closed. Use `NSBackgroundActivityScheduler` 
- [ ] Recurrence and time zones: fixtures for an organizer in America/Los_Angeles viewed in Asia/Bangkok, and DST ed
- [ ] Localization:
- [ ] Accessibility:
- [ ] Offline:
- [ ] Privacy:

## M8. Release prep (mostly [HUMAN])

- [ ] **[HUMAN]**:
- [ ] `make release`: archive, sign, notarize (`notarytool`), staple, zip.
- [ ] Direct download only: Sparkle 2 with an appcast hosted as a static file on the same site as the privacy policy
- [ ] **[HUMAN]**:
- [ ] Write `README.md` (build, configure secrets, architecture overview) and `PRIVACY.md`.

