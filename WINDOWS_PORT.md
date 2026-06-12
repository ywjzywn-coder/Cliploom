# Cliploom Windows Port Handoff

## Goal

Build a Windows 11 version of Cliploom with the same core workflows:

- Clipboard history for text, links, images, and files
- `Alt+V` clipboard panel
- `Alt+A` screenshot overlay
- Window selection, free selection, annotations, mosaic, OCR, and QR scanning
- Favorites, search, cleanup, local-only storage, and direct paste

The macOS source is a product and behavior reference. Its AppKit, SwiftUI,
SwiftData, Vision, ScreenCaptureKit, and Carbon implementations are not
portable to Windows and should be replaced behind equivalent services.

## Recommended Stack

- C# and .NET 8
- WinUI 3 with Windows App SDK
- SQLite for clipboard history and settings that need structured storage
- Win32 interop for clipboard listeners, global hotkeys, foreground windows,
  focus restoration, and synthetic paste
- Windows Graphics Capture or DXGI Desktop Duplication for screenshots
- Windows.Media.Ocr for local OCR
- ZXing.Net for QR and barcode recognition, unless a dependency-free
  requirement is added

## Platform Mapping

| macOS implementation | Windows implementation |
| --- | --- |
| `NSPasteboard` polling | `AddClipboardFormatListener` and Win32 clipboard APIs |
| Carbon global hotkeys | `RegisterHotKey` / `UnregisterHotKey` |
| AppKit floating panels | WinUI 3 window with AppWindow and Win32 styles |
| `ScreenCaptureKit` | Windows Graphics Capture or DXGI Desktop Duplication |
| Vision OCR | `Windows.Media.Ocr` |
| Vision barcode request | ZXing.Net image decoding |
| `NSWorkspace` / Finder | `Process.Start` / Explorer |
| SwiftData | SQLite repository |
| `CGEvent` paste | Restore foreground window and use `SendInput` |
| Login item API | Packaged startup task or Registry startup entry |

## Suggested Architecture

Keep the same service boundaries where practical:

- `ClipboardItem`
- `ClipboardMonitor`
- `ClipboardStore`
- `GlobalHotKeyManager`
- `PasteCoordinator`
- `ScreenshotCoordinator`
- `ScreenshotSession`
- `BarcodeScanner`
- `TextRecognizer`

Do not attempt a line-by-line Swift translation. Port behavior and tests, then
implement each service with Windows-native APIs.

## Delivery Order

1. Clipboard listener, SQLite history, classification, hashing, and cleanup
2. `Alt+V` panel, search, categories, favorites, keyboard navigation
3. Foreground-window restoration and direct paste
4. Screenshot capture and selection overlay
5. Annotation renderer and PNG clipboard output
6. OCR and QR result windows
7. Startup, settings, localization, packaging, and UI automation tests

## Important Windows Differences

- Windows does not use macOS Accessibility or Screen Recording permissions.
- Secure desktop and elevated application windows may block capture or input.
- `Alt+A` can conflict with application menu accelerators while an app is
  focused, even when global registration succeeds.
- Multi-monitor coordinates can be negative and displays can use different DPI
  scaling. Keep screenshot geometry in physical pixels and convert explicitly.
- Clipboard file entries should store paths only and must never delete source
  files.

## Acceptance Baseline

- New clipboard content appears within one second.
- `Alt+V` opens the panel and Enter pastes into the previous application.
- `Alt+A` enters screenshot mode in about one second.
- Screenshots preserve native pixel resolution.
- OCR and QR actions hide the screenshot overlay and show only their result
  window.
- OCR results show the selected image on the left and editable text on the
  right.
- Clipboard history and settings survive restart.
- All data remains local unless the user explicitly exports it.
