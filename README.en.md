# CalendarCountdown

> A native macOS tracker for important dates. Apple Calendar remains the source of truth, while users, widgets, and AI agents get a clear and portable countdown layer.

[中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [Français](README.fr.md)

## Screenshots

<p align="center">
  <img src="Documentation/Images/app-window-demo.png" width="900" alt="CalendarCountdown main-window demo">
</p>

<p align="center">
  <img src="Documentation/Images/widget-demo.png" width="720" alt="CalendarCountdown desktop-widget demo">
</p>

<p align="center">
  <img src="Documentation/Images/menu-bar-demo.png" width="420" alt="CalendarCountdown menu-bar demo">
</p>

> Every calendar, person, and date shown here is fictional demo data. No real user information is included.

## What it is

CalendarCountdown is not another calendar database. Accounts, calendars, events, and colors stay under Apple Calendar’s control. The project reads and writes calendars authorized by the user through EventKit, then focuses on one job: keeping meaningful dates visible, computable, exportable, and automation-friendly.

## Core capabilities

- Read authorized Apple calendars while preserving their native accounts, categories, and colors.
- Track birthdays, anniversaries, holidays, and non-recurring important dates.
- Support yearly Gregorian and Chinese lunar rules, including leap-month and short-month fallback policies.
- Calculate “today,” “tomorrow,” and remaining days using the local system calendar.
- Native macOS app, menu-bar glance, and WidgetKit desktop widget.
- Add regular events, Gregorian birthdays, and lunar birthdays to an explicitly selected Apple calendar.
- Export every currently tracked important date with one click in the app.
- Universal Binary for Apple Silicon and Intel Macs, requiring macOS 14 or later.

## Designed for AI agents

`calcount` is a local command-line interface that can be exposed directly as an agent shell tool. Every structured command emits JSON without interactive text, and explicit exit codes distinguish usage errors, missing calendar authorization, and runtime failures.

Agent-friendly properties:

- **Predictable reads:** list calendars, query events, retrieve upcoming countdowns, and read the tracking index.
- **Stable JSON envelopes:** success uses `{ "ok": true, "data": ... }`; failure uses `{ "ok": false, "error": { "code": ..., "message": ... } }`.
- **Reviewable writes:** write operations require an explicit Apple calendar, and bulk imports support `--dry-run`.
- **Idempotent imports:** `externalId` prevents duplicate creation when an agent retries a request.
- **Portable context:** `tracked-events.json` retains the start year, calendar system, month and day, recurrence rules, next occurrence, and Apple Calendar references.
- **Local first:** no server or cloud calendar replica is required. The agent only accesses EventKit data authorized on the current Mac.

Common read and export commands:

```bash
./calcount doctor
./calcount calendars list
./calcount events list --days 365
./calcount next --limit 10 --days 3653
./calcount tracking refresh
./calcount tracking list
./calcount tracking export --output tracked-events.json
```

Agent code can consume the output directly with `jq`:

```bash
./calcount next --limit 5 | jq '.data[] | {title, eventDate, calendarTitle}'
```

Preview a bulk import before writing anything:

```bash
./calcount import /path/to/import.json --dry-run
```

`calcount` currently provides a local CLI contract. It does not claim to be an MCP server or remote API, but any agent framework with shell tool calling can wrap it as a tool.

## Tracked-events JSON

Apple Calendar always remains the source of truth for event content. `tracked-events.json` is not a second calendar database; it is a versioned, exportable index of the items currently visible in the countdown experience.

Each record includes:

- Stable UUID, title, and kind: birthday, anniversary, important date, or other.
- Start year, month, day, and Gregorian/lunar calendar marker.
- Recurrence frequency, recurrence calendar, and lunar edge-case policies.
- Next occurrence, time, time zone, and all-day state.
- Apple Calendar source, calendar, color, and identifiers for relinking.
- Tracking mode, tracking start time, and pinned state.

See the complete anonymized [tracked-events.example.json](Documentation/tracked-events.example.json).

## Install

Current version: **1.0.0**

1. [Download CalendarCountdown-1.0.0-macos-universal.dmg from GitHub Releases](https://github.com/MyKWK/CalendarCountdown/releases/download/v1.0.0/CalendarCountdown-1.0.0-macos-universal.dmg).
2. Drag CalendarCountdown into Applications.
3. Launch the app and grant full Apple Calendar access.

The 1.0.0 build is currently ad-hoc signed, not signed with an Apple Developer ID or notarized. On first launch, you may need to Control-click the app in Finder and choose Open.

## Build from source

Requires macOS 14+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd Source
./Scripts/bootstrap.sh
./Scripts/build.sh
xcodebuild -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdown \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO test
./Scripts/package-dmg.sh
```

## Data and privacy boundaries

- Calendar events remain in Apple Calendar; the project does not operate its own cloud calendar service.
- Tracking selections and `tracked-events.json` stay on the Mac for display and user-initiated export.
- Writes affect only the Apple calendar explicitly selected by the user.
- Real user anniversary files are excluded by `.gitignore` and must not enter the public repository or release package.

## Current scope

- macOS is supported today. An iPhone app, iPhone widgets, and CloudKit rule sync are future work.
- This project is not a CalDAV server and does not duplicate Apple Calendar’s account or category hierarchy.
- See [Documentation/PRODUCT.md](Documentation/PRODUCT.md) for the detailed product and data contract.

## Repository layout

- `Source/`: Swift source, XcodeGen configuration, tests, and build scripts.
- `Documentation/`: product contract, installation notes, and anonymized JSON examples.
- `Releases/1.0.0/`: release notes and SHA-256 checksum; the DMG is distributed through GitHub Releases.

## License

This project is available under the [MIT License](LICENSE).
