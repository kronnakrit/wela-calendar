# Decisions

One line each: what was chosen, and why.

- No Swift toolchain in the cloud container, so every build and test runs on a macOS GitHub Actions runner (`.github/workflows/ci.yml`); that is the build check.
- MSAL, AppAuth and Sparkle are added to `project.yml` in the milestone that first uses them (M3, M4, M8) instead of M0, to keep M0 builds fast and avoid unused binary dependencies. KeyboardShortcuts is in from M0.
- GRDB pinned `from: 6.29.0` (stays on 6.x; 7.x needs the Swift 6 toolchain).
- Dots: one dot per event (first four by start time, all-day first), not one per distinct calendar; cancelled events get no dot.
- `Day N of M` labels are English-only until the M7 localization pass.
- FTS5 uses the `unicode61` tokenizer, which does not segment Thai words; prefix matching still works. Revisit in M7.
- All-day events keep `start`/`end` at UTC midnight of their dates purely for range queries; placement uses `startDay`/`endDay`.
