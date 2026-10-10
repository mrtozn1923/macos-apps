# TıkKare — Local Screenshot Tool for macOS (Design)

Date: 2026-10-10
Status: Approved by user (all decisions delegated)

## Goal

Replace Lightshot (Intel-only, will stop working on macOS 28) with a native
Apple-silicon menu bar app that captures, annotates, copies and saves
screenshots entirely locally. No cloud, no upload, no accounts.

## Scope

### Capture modes
| Mode | Default hotkey | Behavior |
|---|---|---|
| Area / Window | `⌥⇧1` | Screen freezes; drag to select an area, or click a highlighted window to capture it |
| Full screen | `⌥⇧2` | Captures the display under the mouse, opens the on-screen editor over it |
| Scrolling | `⌥⇧3` | Select area → user scrolls → frames are stitched → result opens in Editor window |
| OCR (text) | `⌥⇧4` | Select area → recognized text (tr + en) copied to clipboard, HUD confirms |

`⌥⇧` chosen to avoid collision with macOS built-in `⌘⇧3/4/5`. All hotkeys are
re-bindable in Settings.

### Editing flows (option C)
1. **On-screen (default):** after selection, a toolbar appears next to the
   selection on the frozen screen; annotation happens in place.
2. **Editor window:** "Open in Editor" button moves the capture + existing
   annotations into a regular resizable window with zoom (pinch / ⌘+ ⌘-).

Both flows use the same canvas, tools and renderer.

### Tools (all in v1)
Arrow, Rectangle, Ellipse, Freehand pen, Line, Text, Highlighter
(semi-transparent marker), Blur/Pixelate, Numbered step badges (auto
increment 1, 2, 3…), Color picker (8 presets + custom) + stroke width
(S/M/L), Undo/Redo (⌘Z / ⌘⇧Z).

Shortcuts in canvas: `A` arrow, `R` rect, `E` ellipse, `P` pen, `L` line,
`T` text, `H` highlighter, `B` blur, `N` number; `⌘C`/`Enter` copy & close,
`⌘S` save & close, `⌘⇧S` save as…, `Esc` cancel. Selection can be adjusted
(move/resize handles) before the first annotation is drawn.

### Output
- Copy: PNG to `NSPasteboard` (with Retina scale preserved).
- Save: PNG to `~/Pictures/Screenshots` (configurable), filename
  `Screenshot 2026-10-10 at 13.45.12.png`.

### Settings window
Hotkey recorders (4), save folder, launch at login (`SMAppService`),
capture sound on/off, "copy to clipboard also on save" toggle.

### Out of scope
Cloud upload/share links, video/GIF recording, history browser, unit tests
(user preference: none unless asked).

## Architecture

Native Swift 6, AppKit-first (overlay and canvas need precise event/window
control), SwiftUI only for Settings. Minimum macOS 14 (ScreenCaptureKit
`SCScreenshotManager`). Menu bar only app (`LSUIElement`).

Build: Swift Package (`Package.swift`) + `scripts/build.sh` that runs
`swift build -c release`, assembles `TikKare.app` (Info.plist, icon), signs
with the "Apple Development" identity so the Screen Recording grant
survives rebuilds, and optionally installs to `~/Applications`.

### Units

```
Sources/TikKare/
  App/          AppDelegate, MenuBarController, main.swift
  Hotkeys/      HotkeyManager (Carbon RegisterEventHotKey), KeyCombo, HotkeyRecorderView
  Capture/      ScreenCapturer (SCK: displays, windows), Permissions,
                WindowLocator (window frames under cursor)
  Overlay/      OverlayController (one borderless window per screen),
                SelectionView (drag/resize selection, window highlight),
                ToolbarView (floating tool palette)
  Annotation/   Annotation model (enum of shapes), AnnotationDocument
                (annotations + undo/redo), AnnotationRenderer (CoreGraphics,
                shared by screen + export), Pixelator (CIPixellate), TextEditing
  Canvas/       CanvasView (NSView: tool interaction + rendering)
  Editor/       EditorWindowController (NSScrollView + CanvasView, zoom)
  Scrolling/    ScrollCaptureController (frame timer, click-through frame
                window, Done panel), ImageStitcher (row-overlap matching)
  OCR/          TextRecognizer (Vision, tr+en), HUD
  Output/       Exporter (flatten to PNG), ClipboardWriter, FileSaver
  Settings/     Preferences (UserDefaults), SettingsView (SwiftUI)
```

Boundaries:
- `AnnotationRenderer` is a pure function of (base image, annotations, scale)
  → drawing; on-screen view and exporter both call it, so what you see is what
  is exported.
- `AnnotationDocument` owns state + undo; views only send intents.
- `ScreenCapturer` is the only type touching ScreenCaptureKit.

### Data flow (area capture)
Hotkey → `ScreenCapturer` grabs every display as CGImage (freeze) →
`OverlayController` shows frozen images full-screen → user drags (or clicks
a window, which is re-captured cleanly via `SCContentFilter(desktopIndependentWindow:)`)
→ crop → `CanvasView` in place → user annotates → Copy/Save →
`Exporter` flattens at native pixel scale → clipboard/file → overlay closes.

### Scrolling capture
After region selection, overlay is replaced by a click-through border window
and a small floating panel ("Bitti" / Esc). Region is captured every ~150 ms
while content changes; `ImageStitcher` finds the vertical offset between
consecutive frames by comparing row fingerprints (ignoring sticky
header/footer rows that match at identical positions), appends new rows.
On finish, result opens in Editor window. Max height cap 30 000 px.

### Error handling
- No Screen Recording permission → alert with button opening
  `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.
- Hotkey registration failure (taken by another app) → shown in Settings
  next to the recorder.
- Save failure → alert with the error, image remains in editor.
- OCR finds no text → HUD "Metin bulunamadı".

## UI language
UI strings in Turkish; code, comments, identifiers in English.

## Verification
Manual: build, launch, exercise each mode on a multi-display setup if
available; check copy/paste into another app and saved file pixel size
(Retina).
