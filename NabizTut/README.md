**English** | [Türkçe](README.tr.md)

# NabızTut

A desktop uptime monitor for macOS. It checks your websites, APIs and servers on the
schedule you choose and shows whether they are up, how fast they answer and their recent
history in a small panel that sits on your desktop. Fully local: no server, no account.

*NabızTut* is Turkish for "keep the pulse".

> The interface follows your macOS language: Turkish or English.

## Features

- **Desktop panel:** sits above the wallpaper and below your windows, on every Space.
  One row per site: status, last response time, 24 h uptime and a one-hour sparkline.
  Sites that are down move to the top.
- **Check types:**
  - **HTTP(S):** status code, response time, expected codes (e.g. `200-299, 301`),
    keyword in the response body (contains / does not contain), custom method, headers and body,
    redirect handling, SSL certificate expiry warning
  - **Ping** (ICMP)
  - **TCP port** (databases, SSH, any service)
- **Alerts:** macOS notification and an alert sound when a site goes down, a notification
  when it recovers (with outage duration), a one-time warning before an SSL certificate expires.
  Per-site notification toggle.
- **History:** response-time chart for 24 hours / 7 days / 30 days with outages marked,
  uptime %, average and p95 response time, outage list.
- **Menu bar icon:** green / yellow / red overall status and a quick list of all sites.
- **Secret headers** (API keys, tokens) are stored in the macOS Keychain, not in the settings file.

## Polite by design

Checking too often can get you rate-limited or blocked, so NabızTut keeps traffic low:

- Intervals: 1, 2, 5, 10, 15, 30 or 60 minutes (minimum 1, default 5).
- Checks are spread out, never fired all at once.
- A site is marked down only after **two** failed checks; the confirmation runs 30 seconds after
  the first failure. No extra requests while everything is healthy.
- Uses `HEAD` when the page content isn't needed and identifies itself with a clear `User-Agent`.
- Checks pause while the Mac sleeps or is offline, and that time never counts as downtime.

## Data

- Raw checks are kept for 7 days, then summarized per hour and kept for 30 days.
- Everything lives in `~/Library/Application Support/NabizTut/`:
  `monitors.json` (your sites, readable and easy to back up) and `history.sqlite`.

## Usage

- **Add a site:** menu bar icon › *Add site…* (on first launch the form opens automatically).
  *Test* runs a single check before you save.
- **Move the panel:** drag it by its top bar.
- **Resize the panel:** menu bar icon › *Resize panel…*, drag the edges, then *Done*.
- **Details:** click a row in the panel.

## Installation

### Prebuilt release

Download [`NabizTut.zip`](https://github.com/mrtozn1923/macos-apps/releases/download/nabiztut-v1.0.0/NabizTut.zip)
from the [Releases](https://github.com/mrtozn1923/macos-apps/releases) page and move `NabizTut.app`
into your `Applications` folder.

The app is not notarized by Apple, so macOS blocks it on first launch:

1. Try to open `NabizTut.app` once.
2. Go to **System Settings › Privacy & Security** and click **Open Anyway**.
3. Allow notifications when asked, so you are alerted when a site goes down.

### Build from source

```bash
git clone https://github.com/mrtozn1923/macos-apps.git
cd macos-apps/NabizTut
./scripts/build.sh --install
```

The app is installed to `~/Applications/NabizTut.app` and launched. If an "Apple Development"
certificate is available on your Mac it is used for signing; otherwise the app is signed ad-hoc.

## Requirements

macOS 14 or later, Apple silicon.
