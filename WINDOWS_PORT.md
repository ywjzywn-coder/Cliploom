# Cliploom Windows Port Handoff

> **Status:** ready for implementation
>
> **Product baseline:** `v0.1.0`
>
> Recommended target: Windows 11 22H2 or later

This document is the handoff contract for another developer or coding agent.
The macOS app is the behavior reference, not a code template. Preserve the
workflows and data guarantees while replacing Apple frameworks with
Windows-native APIs.

## Product Goal

Build a lightweight Windows version of Cliploom with these primary workflows:

- `Alt+V` opens searchable clipboard history.
- `Alt+A` starts screenshot capture.
- Text, links, images, and files are classified automatically.
- Enter pastes into the previously active application.
- Screenshots support window selection, free selection, annotations, mosaic,
  OCR, QR/barcode scanning, save, and clipboard output.
- Favorites, settings, history, and panel position survive restart.
- Clipboard, screenshots, OCR, and scan results remain local.

## Source Of Truth

Read these macOS files before implementing an equivalent module:

| Behavior | macOS reference |
| --- | --- |
| Clipboard model and categories | `PasteBox/Models/ClipboardItem.swift` |
| Parsing, classification, and hashing | `PasteBox/Services/ClipboardPayload.swift` |
| Deduplication and cleanup | `PasteBox/Services/ClipboardStore.swift` |
| Clipboard monitoring | `PasteBox/Services/ClipboardMonitor.swift` |
| Hotkey configuration | `PasteBox/Services/GlobalHotKeyManager.swift` |
| Direct paste behavior | `PasteBox/Services/PasteCoordinator.swift` |
| Clipboard panel UX | `PasteBox/UI/ClipboardPanelView.swift` |
| Screenshot lifecycle | `PasteBox/Screenshot/ScreenshotCoordinator.swift` |
| Selection and annotation behavior | `PasteBox/Screenshot/ScreenshotOverlayController.swift` |
| Pixel-coordinate conversion | `PasteBox/Screenshot/ScreenshotModels.swift` |
| Final PNG rendering | `PasteBox/Screenshot/ScreenshotRenderer.swift` |
| OCR result layout | `PasteBox/Screenshot/ScreenshotOCRPanelView.swift` |
| QR/barcode result layout | `PasteBox/Screenshot/ScreenshotBarcodePanelView.swift` |
| Existing behavior tests | `PasteBoxTests/` |

Do not translate these files line by line. Extract the contracts, write Windows
tests for them, and implement behind platform-specific services.

## Recommended Stack

- **Language/runtime:** C# and .NET 8
- **Desktop UI:** WinUI 3 with Windows App SDK
- **Persistence:** SQLite through `Microsoft.Data.Sqlite`
- **Clipboard:** `AddClipboardFormatListener` and Win32 clipboard APIs
- **Global hotkeys:** `RegisterHotKey` / `UnregisterHotKey`
- **Capture:** Windows Graphics Capture; use DXGI Desktop Duplication only when
  the first API cannot meet latency or monitor requirements
- **OCR:** `Windows.Media.Ocr`
- **Barcode:** ZXing.Net
- **Image rendering:** Win2D or Direct2D
- **Tests:** xUnit for domain/services and WinAppDriver or Appium for UI flows

Third-party packages should be limited to clear platform gaps. Keep storage,
classification, hotkey dispatch, and lifecycle code dependency-light.

## Platform Mapping

| macOS implementation | Windows implementation |
| --- | --- |
| `NSPasteboard` polling | `AddClipboardFormatListener` and Win32 clipboard APIs |
| Carbon global hotkeys | `RegisterHotKey` / `UnregisterHotKey` |
| AppKit floating panels | WinUI 3 `Window` + `AppWindow` + Win32 styles |
| `ScreenCaptureKit` | Windows Graphics Capture |
| Vision OCR | `Windows.Media.Ocr` |
| Vision barcode request | ZXing.Net image decoding |
| `NSWorkspace` / Finder | `Process.Start` / Explorer |
| SwiftData | SQLite repository |
| `CGEvent` paste | foreground restoration + `SendInput` |
| Login item API | packaged `StartupTask` or Registry startup entry |
| `UserDefaults` | local app settings |

## Required Solution Layout

The exact project names may change, but keep platform-independent behavior away
from Win32 and WinUI code.

```text
src/
├── Cliploom.App/             WinUI application and composition root
├── Cliploom.Core/            models, classification, hashing, cleanup rules
├── Cliploom.Infrastructure/  SQLite, clipboard, hotkeys, capture, OCR, barcode
└── Cliploom.UI/              panel, settings, overlay, result windows
tests/
├── Cliploom.Core.Tests/
├── Cliploom.Infrastructure.Tests/
└── Cliploom.UI.Tests/
```

## Core Contracts

Use equivalent interfaces so the UI can be tested with fake implementations:

```csharp
public interface IClipboardMonitor
{
    event EventHandler<ClipboardPayload> Changed;
    void Start();
    void Stop();
    void IgnoreNextInternalWrite();
}

public interface IClipboardStore
{
    Task<ClipboardItem> SaveAsync(ClipboardPayload payload, DateTimeOffset now);
    Task<IReadOnlyList<ClipboardItem>> SearchAsync(
        ClipboardFilter filter,
        string query);
    Task ToggleFavoriteAsync(Guid id);
    Task DeleteAsync(Guid id);
    Task CleanupAsync(DateTimeOffset now, int maximumCount, int maximumAgeDays);
}

public interface IHotKeyManager
{
    bool Register(HotKeyAction action, HotKeyGesture gesture);
    bool TryUpdate(HotKeyAction action, HotKeyGesture gesture);
    void Unregister(HotKeyAction action);
}

public interface IPasteCoordinator
{
    Task<PasteResult> CopyAsync(ClipboardItem item);
    Task<PasteResult> PasteAsync(ClipboardItem item, nint targetWindow);
}
```

Add equivalent contracts for screenshot capture, OCR, barcode scanning, and
PNG rendering. Domain tests must not require a real desktop session.

## Clipboard Behavior Contract

Classification priority:

1. Files
2. Bitmap image
3. HTTP/HTTPS link
4. Plain text

Rules:

- Polling is not required on Windows; process `WM_CLIPBOARDUPDATE` events.
- Generate deterministic, type-specific hashes.
- Sort file paths before hashing so copy order does not create duplicates.
- Re-copying identical content updates its timestamp and moves it to the top.
- Store image files as PNG inside app data.
- Store file paths only; never copy or delete the original files.
- Mark missing files unavailable and block paste for them.
- Keep at most 500 non-favorite entries or 30 days of non-favorite history.
- Favorites are exempt from automatic cleanup.
- Internal clipboard writes must not generate duplicate history entries.

Suggested SQLite fields:

```text
id, kind, summary, text_content, content_hash, created_at, updated_at,
is_favorite, image_cache_path, file_paths_json
```

Create indexes for `content_hash`, `updated_at`, `kind`, and `is_favorite`.

## Clipboard Panel Contract

- Default hotkey: `Alt+V`, configurable in settings.
- Filters: All, Text, Links, Images, Files, Favorites.
- Support search, arrow-key selection, Enter to paste, and Escape to close.
- Context actions: favorite, delete, copy only, and show in Explorer.
- Restore the last valid panel position and clamp it to the current monitor.
- If the panel loses focus, it may close; screenshot result windows follow the
  separate lifecycle described below.
- A failed hotkey update must preserve the previous working hotkey.

For direct paste, remember the foreground window before opening Cliploom,
restore it, write the selected content, then send `Ctrl+V`. Elevated windows,
secure desktop, and applications with restricted input may reject this flow;
report a copy-only fallback instead of silently failing.

## Screenshot Contract

- Default hotkey: `Alt+A`, configurable independently from `Alt+V`.
- Capture only the monitor under the pointer.
- Capture before displaying the overlay so Cliploom is not included.
- Keep capture and crop geometry in physical pixels.
- Convert explicitly between physical pixels, DIPs, monitor coordinates, and
  virtual-desktop coordinates.
- Exclude Cliploom, desktop surfaces, transparent windows, and tiny windows
  from automatic window hit testing.
- Clicking a detected window selects it.
- Dragging creates a free selection.
- After a selection exists, clicking outside it cancels the screenshot.
- Selection supports move and eight-direction resize.
- Escape cancels; Enter and double-click complete.

The annotation toolbar must include:

- Rectangle
- Arrow
- Pen
- Text
- Mosaic
- Undo
- OCR
- QR/barcode scan
- Save
- Cancel
- Complete

Annotations remain non-destructive until final rendering. Output is PNG at the
native crop resolution and does not include the pointer.

## OCR And Barcode Result Lifecycle

OCR:

- Hide the screenshot overlay before recognition begins.
- Show the selected image on the left and editable recognized text on the right.
- Size the window from the selected image while keeping it inside the current
  monitor's working area.
- The center divider is draggable, and its ratio persists across sessions.
- Clicking another application may send the result window behind it.

Barcode:

- Hide the screenshot overlay and show a dedicated result window.
- Display every unique result with symbology and payload.
- Allow copy for all non-empty payloads.
- Only offer “Open link” for valid `http` or `https` URLs.
- Never navigate automatically.
- Repeated scans in one app session must not crash or reuse stale view state.

Shared lifecycle:

- Pressing `Alt+A` while an OCR/barcode result window exists closes the old
  result session and starts a fresh capture.
- A hidden or background result window must never block a new screenshot.
- Empty results and recognition failures keep a dismissible result window with
  a retry action.

## Windows-Specific Constraints

- Windows has no macOS Accessibility or Screen Recording permission prompts.
- Secure desktop cannot be captured.
- Elevated applications may reject capture or synthetic input from a
  non-elevated Cliploom process.
- `Alt+A` can conflict with menu accelerators even if global registration works.
- Mixed-DPI monitors and negative virtual-desktop coordinates are normal.
- Clipboard ownership can be delayed or locked; retry briefly without blocking
  the UI thread.
- Windows 11 packaging and startup behavior differ between packaged and
  unpackaged apps. Decide the distribution model before implementing startup.

## Delivery Plan

### Phase 1: Core clipboard

- Create solution and projects.
- Implement payload parsing, classification, hashing, SQLite storage, cleanup.
- Add clipboard event listener and internal-write suppression.
- Add unit tests for Chinese paths, multiple files, empty clipboard, large
  images, duplicate content, and missing files.

Success sign: clipboard tests pass and a console harness records clipboard
updates without duplicates.

### Phase 2: Clipboard UI

- Build the compact `Alt+V` panel.
- Add categories, search, favorites, deletion, keyboard operation, and position
  persistence.
- Restore the previous foreground window and implement copy/paste fallback.

Success sign: copying in Notepad, a browser, and Explorer appears within one
second and Enter pastes back into the original app.

### Phase 3: Screenshot foundation

- Implement monitor capture, window hit testing, selection overlay, coordinate
  conversion, crop, and PNG clipboard output.
- Add mixed-DPI and negative-coordinate tests.

Success sign: `Alt+A` enters capture in about one second and the output keeps
native pixel resolution on every tested monitor.

### Phase 4: Editing and recognition

- Add annotations, mosaic, undo, save, OCR, and barcode scanning.
- Implement independent OCR/barcode result windows and replacement lifecycle.

Success sign: repeated OCR and barcode actions work without stale content,
crashes, or blocked future screenshots.

### Phase 5: Productization

- Add settings, startup, Chinese/English localization, packaging, app icon,
  migration strategy, UI automation, and release documentation.

Success sign: settings and history survive restart, and a clean Windows user
can install, grant no extra permissions, and finish both primary workflows.

## Test Matrix

- Windows 11 at 100%, 125%, 150%, and 200% scaling
- One monitor and mixed-DPI multi-monitor layouts
- Secondary monitors left of and above the primary monitor
- Notepad, Edge/Chrome, Explorer, Office, and an elevated application
- Text, HTTP/HTTPS links, Unicode text, images, one file, and multiple files
- Missing files and paths containing Chinese characters
- First and repeated OCR scans
- First and repeated QR/barcode scans
- App restart, Windows restart, hotkey conflict, and monitor disconnection

## Definition Of Done

- New clipboard content appears within one second.
- `Alt+V` opens the panel and Enter pastes into the previous application.
- `Alt+A` enters screenshot mode in about one second.
- Screenshots preserve native pixel resolution.
- OCR and barcode actions hide the overlay and show only their result window.
- Starting a new screenshot closes any prior result session.
- OCR shows selected image and editable text with a remembered divider ratio.
- Repeated barcode scans display current results and do not crash.
- History, favorites, settings, and panel position survive restart.
- All user content remains local unless explicitly exported.

## Agent Startup Checklist

1. Read this document and the macOS source-of-truth files.
2. Create a dedicated Windows branch, for example `windows/main`.
3. Record the chosen packaging model and capture API in an architecture note.
4. Implement Phase 1 with tests before starting UI work.
5. Keep commits scoped by module and update this document after each phase.
6. Do not change the macOS behavior contract without documenting the divergence.

When handing off again, include the latest passing test command, known platform
limitations, unfinished phase checklist, and exact reproduction steps for any
remaining issue.
