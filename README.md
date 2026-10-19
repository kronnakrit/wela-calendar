# Wela Calendar

A macOS menu bar calendar (เวลา, "time"): month grid, agenda, one-click join and RSVP for Microsoft 365 and Google calendars. No backend; calendar data stays on the Mac.

- Plan: [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md), progress: [`docs/PROGRESS.md`](docs/PROGRESS.md)
- Requires macOS 14, Xcode 15.3+ (Swift 5.10).

```sh
make bootstrap   # installs xcodegen + swift-format, creates Config/Secrets.xcconfig
make gen build test
make run         # launches with mock data (Debug)
```

OAuth client IDs go in `Config/Secrets.xcconfig` (gitignored); see `Config/Secrets.example.xcconfig`.
