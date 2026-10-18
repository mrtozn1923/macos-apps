# NabızTut — Desktop Uptime Monitor for macOS (Design)

Date: 2026-10-18
Status: Approved in brainstorming, pending written-spec review

## Goal

A native macOS app that periodically checks websites, APIs and servers, and
shows whether they are up, how fast they answer and their recent history in a
small panel that sits on the desktop. Fully local: no server, no account.

Display name **NabızTut** ("keep the pulse"), ASCII name `NabizTut` for the
folder, executable, bundle (`NabizTut.app`) and bundle id
`com.mertozen.nabiztut`. Lives in `macos-apps/NabizTut/`, fully independent
of other apps in the repo (no shared code or paths).

## Scope

### Check types
| Type | What is checked |
|---|---|
| HTTP(S) | Reachability, status code, response time; optional rules below |
| Ping | ICMP echo round-trip (unprivileged `SOCK_DGRAM` ICMP socket) |
| TCP port | Connection to `host:port` succeeds within timeout |

HTTP options per monitor:
- Method (`GET`, `HEAD`, `POST`, `PUT`, `PATCH`, `DELETE`), headers, body.
- Expected status codes, e.g. `200-299, 301` (default `200-399`).
- Keyword rule: response body *contains* / *does not contain* a string
  (case-insensitive, first 1 MB of the body only).
- Follow redirects (default on, max 5); when off, the 3xx itself is evaluated.
- SSL expiry warning threshold in days (default 14).
- Requests use `HEAD` automatically when method is `GET`, there is no keyword
  rule and no body is needed; falls back to `GET` if the server answers 405/501.

Common per-monitor fields: name, interval, timeout (default 10 s, 1–60 s),
notifications on/off, paused on/off.

### Rate limits (avoid being blocked)
- Intervals: **1, 2, 5, 10, 15, 30, 60 minutes. Minimum 1 minute, default 5.**
- Start times are staggered across the interval; launching the app never fires
  all checks at once.
- On the first failure, **one** confirmation check runs 30 s later instead of
  waiting a full interval. No extra requests while healthy.
- `User-Agent: NabizTut/<version> (+https://github.com/mrtozn1923/macos-apps)`.
- Caching disabled (`URLSessionConfiguration.ephemeral`, no cookies).

### Status rules
- **Down:** 2 consecutive failed checks (the failure + its confirmation).
- **Up:** first successful check after being down.
- **Warning (yellow):** up, but response time > 3× the monitor's 24 h median,
  or SSL expires within the threshold.
- **Paused (grey)** and **Offline** (Mac has no network) are separate states.
- Incidents: a record opens when a monitor goes down and closes when it comes
  back, with start, end and reason.

### Notifications
- macOS notification + alert sound when a monitor goes down
  ("api.example.com yanıt vermiyor (502)").
- Notification (no sound) when it recovers ("tekrar ayakta · 4 dk kesinti").
- SSL warning once per certificate (keyed by certificate expiry date).
- Per-monitor notification toggle; global sound toggle.
- If notification permission is denied, everything else keeps working and
  Settings shows a warning with a link to System Settings.

### History
- Raw checks kept **7 days** (used by 1 h sparkline, 24 h and 7 d charts).
- Older data rolled up to **hourly summaries** (checks, failures, avg / max /
  p95 latency) kept **30 days** (used by the 30 d chart).
- Incidents kept 30 days.
- Rollup + cleanup runs at launch and every 6 hours.

### Out of scope
Public status pages, team accounts, sync, SMS/email/Slack alerts, multi-step
transactions, unit tests (user preference: none unless asked).

## UI

### Desktop panel
- Borderless, translucent (`NSVisualEffectView`) panel at desktop level:
  above wallpaper and desktop icons, below normal windows
  (`kCGDesktopIconWindowLevel + 1`), visible on all Spaces, not in Cmd-Tab.
- Default width ~320 pt. Moved at any time by dragging its top bar (header is
  the grab handle; rows stay clickable). **Resize mode** (menu bar ›
  "Resize panel…") enables edge resizing until "Done".
- Header: `● 5/6 ayakta`, refresh-all button, settings button.
- One row per monitor: status dot, name, last response time, 24 h uptime %,
  sparkline of the last hour. Down rows show the reason and duration
  ("502 · 4 dk") and are sorted to the top.
- Colors: green up, red down, yellow warning, grey paused.
- Click a row → detail window.
- Opacity adjustable in Settings; follows light/dark appearance.
- Position and size remembered per screen configuration.

### Menu bar
- Icon tinted green (all up), red (any down), yellow (warning), grey (offline).
- Menu: monitor list with status, "Şimdi kontrol et", "Paneli göster/gizle",
  "Paneli boyutlandır…", "Site ekle…", "Ayarlar…", "Çık".

### Detail window
- Header: status, last check time, SSL expiry date (HTTPS).
- Swift Charts response-time chart with 24 h / 7 d / 30 d tabs; incidents shown
  as red bands; hover shows the value at that time.
- Summary cards: uptime %, average, p95, incident count for the selected range.
- Incident list: start, duration, reason.

### Settings window
- **Monitors:** list on the left, form on the right (type, name, address,
  interval, timeout; advanced section for HTTP options). "Test et" runs one
  check without saving and shows the result. Add / duplicate / delete / pause.
- **General:** panel opacity, lock panel, launch at login (`SMAppService`),
  alert sound on/off, notification permission status.

## Architecture

Swift 6 toolchain, Swift 5 language mode, SwiftUI for windows and panel
content, AppKit for the desktop-level panel and menu bar item, Swift Charts,
URLSession, Network framework, UserNotifications, system `libsqlite3`
(no third-party dependencies). Minimum macOS 14, arm64. Menu-bar-only app
(`LSUIElement`). Built with Swift Package Manager + `scripts/build.sh`
(same approach as TıkKare, own copy). English + Turkish UI following the
macOS language.

```
NabizTut/Sources/NabizTut/
  App/          main, AppDelegate, MenuBarController, Localization
  Model/        Monitor (Codable), CheckResult, MonitorStatus, Incident
  Config/       MonitorStore (JSON in Application Support), SecretStore (Keychain)
  Checks/       Checker protocol, HTTPChecker, PingChecker, TCPChecker,
                CertificateInspector
  Engine/       Scheduler (per-monitor tasks, staggering, confirmation check),
                StatusEngine (state machine, incidents), NetworkWatcher
                (NWPathMonitor), SleepWatcher
  Storage/      Database (SQLite wrapper), HistoryRepository (insert, queries,
                rollup, cleanup)
  Alerts/       Notifier (UserNotifications + sound)
  Panel/        DesktopPanelController (NSPanel), PanelView, MonitorRow, Sparkline
  Detail/       DetailWindowController, DetailView, LatencyChart, IncidentList
  Settings/     SettingsWindowController, MonitorListView, MonitorFormView,
                GeneralSettingsView, Preferences
```

Boundaries:
- `Checker.check(monitor) async -> CheckResult` is the only network code; the
  engine never touches URLSession directly.
- `StatusEngine` is pure state logic: input `CheckResult`s, output status
  changes and incident open/close events.
- `HistoryRepository` is the only type that issues SQL.
- UI observes an `@Observable AppState` (monitors + current statuses); views
  query history through the repository.

### Data
`monitors.json` (Application Support/NabizTut): list of monitors. Header values
marked secret are stored in the Keychain (service `com.mertozen.nabiztut`,
account `<monitorID>.<headerName>`); JSON keeps only the header name.

SQLite (`history.sqlite`, WAL mode):
```sql
CREATE TABLE checks (
  monitor_id TEXT NOT NULL, ts INTEGER NOT NULL, ok INTEGER NOT NULL,
  status_code INTEGER, latency_ms INTEGER, error TEXT
);
CREATE INDEX checks_monitor_ts ON checks(monitor_id, ts);
CREATE TABLE hourly (
  monitor_id TEXT NOT NULL, hour INTEGER NOT NULL, total INTEGER NOT NULL,
  failed INTEGER NOT NULL, avg_ms INTEGER, max_ms INTEGER, p95_ms INTEGER,
  PRIMARY KEY (monitor_id, hour)
);
CREATE TABLE incidents (
  id INTEGER PRIMARY KEY, monitor_id TEXT NOT NULL, started INTEGER NOT NULL,
  ended INTEGER, reason TEXT NOT NULL
);
CREATE TABLE ssl_warnings (monitor_id TEXT NOT NULL, expiry INTEGER NOT NULL,
  PRIMARY KEY (monitor_id, expiry));
```

### Data flow
Scheduler → Checker → CheckResult → HistoryRepository (insert) + StatusEngine
→ status change → AppState (panel, menu bar) + Notifier.

## Error handling
- **Offline:** `NWPathMonitor` unsatisfied → pause scheduling, panel shows
  "Çevrimdışı", no down states or notifications; resume staggered when back.
- **Sleep:** pause on `NSWorkspace.willSleepNotification`; on wake wait 10 s,
  resume staggered. Sleep time is not counted as downtime.
- **Error reasons** recorded verbatim-but-friendly: DNS not found, timeout,
  connection refused, TLS invalid/expired, unexpected status (code + phrase),
  keyword missing/present, ICMP blocked ("ping engellenmiş olabilir, TCP
  kontrolü deneyin").
- **Database corrupt / unopenable:** move file aside with a timestamp suffix,
  create a fresh one; monitors are unaffected (separate JSON).
- **Invalid monitor config** (bad URL, empty host): form validation prevents
  saving; a broken JSON file on disk is backed up and the app starts empty with
  an alert.

## Verification
No unit tests (user preference). During development:
- A throwaway local test server (scratchpad) serving 200, 500, slow and
  keyword pages; a closed TCP port; a non-routable host for timeouts.
- SSL expiry read against a real HTTPS site.
- Down → notification + sound → recovery flow by stopping and restarting the
  test server.
- Run the app and check panel, detail charts and settings in both languages.
