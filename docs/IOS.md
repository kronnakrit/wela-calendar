# Wela for iPhone and iPad

One universal iOS app (iPhone and iPad) plus a WidgetKit extension, built from the same
packages as the Mac app. Requires iOS 17.

## What's in it

- **App** (`iOS/App`): the month grid and agenda from the Mac panel, filling the screen.
  - iPhone, and iPad in narrow Split View or Slide Over: month over agenda.
  - Full-width iPad: month on the left, the day's agenda on the right.
  - The layout follows the horizontal size class, so it also adapts to rotation and to larger
    or foldable iPhone screens. Text follows Dynamic Type. There is no foldable iPhone
    simulator yet, so the cover / inner screen previews (`ios-fold-*` on `ci-screenshots`) are
    rendered at approximate sizes: cover 360×760 pt (compact), inner 820×980 pt (regular).
  - Search, calendar filter, settings sheet, event detail with Join and RSVP, pull to refresh.
  - Swipe the month grid left or right to change month.
- **Widgets** (`iOS/Widgets`):
  - *Up Next*: small, medium, large and extra large on the Home Screen; rectangular, inline
    and circular on the Lock Screen. Shows what's on now (with Join on medium and large) and
    what comes next.
  - *Month*: small, medium, large and extra large. The month with today ringed, a dot per
    event, plus the next events on bigger sizes.
  - *StandBy* (iPhone on its side while charging): the small Up Next widget switches to a
    big, background-free layout with a live countdown; Month shows the month. iOS tints both
    red at night.
  - Tapping an event opens it in the app (`wela://event?id=…`); tapping a day opens that day.
- **Data**: the SQLite cache lives in the App Group container so the widget can read it
  (read-only). The app reloads widget timelines whenever events, calendars or settings change,
  and a background app refresh task syncs about every 30 minutes when iOS allows it, so widgets
  stay current while the app is closed. Widgets never touch the network.

Shared code: views and widget logic are in `WelaUI` (`MobileViews.swift`, `WidgetSnapshot.swift`,
`WidgetViews.swift`); sign-in (`App/Auth`), `App/AppActions.swift` and
`App/NotificationScheduler.swift` are compiled into both the Mac and iOS apps.

## Build and run

```sh
make bootstrap gen
open Wela.xcodeproj        # scheme WelaiOS, any iPhone or iPad simulator
make ios-build             # command-line simulator build, unsigned
make ios-screenshots       # mock data on iPhone and iPad simulators → screenshots/
```

The `WelaiOS` scheme runs Debug builds with `-UseMockData`, so the app and widgets show a demo
month without signing in. Remove that argument in the scheme to use real accounts.

CI builds the app for the simulator (Debug) and for devices (Release, unsigned) and publishes
simulator screenshots to the `ci-screenshots-ios` branch.

## Putting it on TestFlight and the App Store

These steps need you (the Apple Developer account owner). Everything else is in the repo.

1. **Apple Developer Program**: enroll at developer.apple.com (99 USD a year). Note your
   Team ID (Membership page).
2. **Bundle id**: pick a real one you own, e.g. `app.wela.calendar`, and set it in
   `Config/Secrets.xcconfig`:
   ```
   WELA_BUNDLE_ID = app.wela.calendar
   DEVELOPMENT_TEAM = ABCDE12345
   ```
   The widget extension uses `<bundle id>.widgets` and the App Group `group.<bundle id>`.
   With automatic signing Xcode registers both ids and the App Group for you the first time you
   build for a device (Xcode → Settings → Accounts, sign in with your Apple ID). If it doesn't,
   create them under Certificates, Identifiers & Profiles and enable *App Groups* on both ids.
3. **Sign-in redirects** (same as the Mac app, since the bundle id is shared):
   - Microsoft Entra: in the app registration, add the **iOS / macOS** platform with the bundle
     id. That registers `msauth.<bundle id>://auth`.
   - Google Cloud: an OAuth client of type **iOS** with the bundle id. Put its client id and
     reversed client id in `GOOGLE_CLIENT_ID` and `GOOGLE_REDIRECT_SCHEME`.
4. **App Store Connect**: My Apps → + → New App. Platform iOS, the bundle id above, a name
   (for example "Wela Calendar"; the name must be unused on the store), SKU anything.
5. **Upload a build**, either way:
   - From your Mac: `make ios-upload` (archives, signs, uploads). Bump
     `CURRENT_PROJECT_VERSION` in `Config/Base.xcconfig` before each new upload.
   - From GitHub: create an App Store Connect API key (Users and Access → Integrations →
     App Store Connect API, role **Admin** so Xcode can create the distribution certificate),
     then add repository secrets `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
     `APP_STORE_CONNECT_KEY` (the .p8 file's contents) and `WELA_SECRETS_XCCONFIG` (the whole
     `Config/Secrets.xcconfig`). Run Actions → TestFlight → Run workflow. The build number is
     the workflow run number.
6. **TestFlight**: after processing (10–30 minutes), add yourself under Internal Testing. For
   people outside your team, create an External group and a public link; the first external
   build goes through a short Beta App Review.
7. **App Store release**, in App Store Connect:
   - Privacy policy URL (required). The privacy answer is *Data Not Collected*: Wela has no
     server, and calendar data goes straight between the device and Microsoft or Google. The
     privacy manifests in `iOS/Resources` and `iOS/Widgets` say the same.
   - Screenshots: 6.9" iPhone and 13" iPad at minimum. `make ios-screenshots` gives a start;
     take final ones on those simulator sizes.
   - Export compliance is answered in Info.plist (`ITSAppUsesNonExemptEncryption = NO`: only
     HTTPS).
   - App Review needs to sign in: give them a test Microsoft or Google account with a few
     events in the review notes. Release builds do not include the demo data.
   - Category: Productivity. Age rating: 4+.

## Notes

- The iPad build is not offered on Apple silicon Macs (`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD
  = NO`), since the Mac has its own app.
- MSAL on iOS keeps tokens in the `com.microsoft.adalcache` Keychain group (entitlement in
  `iOS/App/Wela.entitlements`); with Microsoft Authenticator installed it signs in through it.
- Before the app is suspended it releases its SQLite locks in the shared container
  (`Store.suspend()`), which iOS otherwise punishes by killing the app.
