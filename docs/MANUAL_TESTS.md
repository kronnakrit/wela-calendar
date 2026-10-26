# Manual tests

Steps for checks that need a person (visual match, VoiceOver, real accounts). Added per milestone.

## M0
1. Run `make bootstrap gen build`, then `make run`.
2. Expect: no Dock icon and no menu bar item yet; the process `Wela` is running (Activity Monitor).

M0 note: CI (`.github/workflows/ci.yml`) already runs gen, build and tests on a clean checkout; step 2 above still needs a Mac.

## M2: panel shell (needs a Mac)
Run `make bootstrap gen run` (launches Debug with `-UseMockData`).

1. **Status item:** the menu bar shows a calendar glyph with today's day number. Change the system date past midnight, or the time zone; the number updates.
2. **Open and close:** click the icon; the 340 pt panel appears under it. Esc, clicking elsewhere, the icon again, and the hotkey (Control-Option-C) each close it. Menu (≡) → Pin panel (or Control-Command-P) keeps it open on outside clicks.
3. **Full-screen apps:** with another app in full screen, the hotkey still shows the panel.
4. **Visual match** against the spec mockup, in light and dark (System Settings → Appearance):
   - zones: search, month title (serif, year in red), weekday labels (today's in red), grid, agenda header, agenda, footer
   - today: slightly rotated red ellipse; selected day: thin ring; current week: yellow band; other-month days faint; up to 4 dots
   - agenda marks: filled = accepted, dashed ring = tentative / not responded, hollow ring + strikethrough = cancelled; past events grey
   - the in-progress meeting sits on a card with "N min left" and a blue Join pill
5. **Keyboard:** Left/Right month; Shift+Left/Right day; Shift+Up/Down week; Cmd-T today; Up/Down agenda rows; Return opens detail (Esc goes back); Cmd-J joins the selected (or in-progress) event; typing a letter starts a search; Esc clears the search, then closes.
6. **Agenda:** on today the list is scrolled so the current or next event is at the top; double-clicking a day opens its first event.
7. **Month memory:** go to next month, close, reopen within 5 minutes: same month. After 5 minutes: back on today.
8. **Calendar filter:** footer pill → untick "Work": its dots and rows disappear immediately.
9. **VoiceOver (Cmd-F5):** a row reads like "10:00 AM to 11:00 AM, OP Weekly Meeting, Spark Room, accepted"; a day reads like "Wednesday 14 October, 4 events, today"; every button has a label.
10. **Open time:** record warm-open time here with `os_signpost` (target < 150 ms). Not instrumented yet: add signposts around `PanelController.show()` and measure in Instruments.

Results: _pending_

## M5/M6 (needs credentials and a Mac)

1. **Microsoft sign-in:** First-run → Connect Outlook; complete sign-in; events appear within seconds; quit and relaunch: still signed in.
2. **Google sign-in:** same with Google; record whether the bounded initial sync returned a `nextSyncToken` (see DECISIONS.md).
3. **RSVP:** Accept/Tentative/Decline on a real event; check it in Outlook / Google Calendar. Turn Wi-Fi off, respond, turn on: it syncs.
4. **Join:** Cmd-J on a Teams/Zoom/Meet event opens the native app (or browser).
5. **Notifications:** allow when asked; an event 5 min away produces a banner with Join and Snooze; Snooze re-fires after 5 min.
6. **Settings:** week start, calendar system, 12/24 h, text size apply live; launch at login toggles in System Settings → Login Items; hotkey recorder changes the shortcut.
7. **Accounts tab:** remove an account: its events disappear.

Results: _pending_
