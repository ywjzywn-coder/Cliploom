# Changelog

All notable changes to Cliploom are documented here.

## Unreleased

### Added

- Screenshot selections can now be translated after local OCR using Apple's
  system Translation framework. Chinese text defaults to English, while other
  detected languages default to Simplified Chinese.
- OCR image previews now use macOS Live Text so recognized text can be selected,
  right-clicked, and copied directly from the screenshot.
- Barcode and QR results now appear as link buttons centered on each detected
  code in the image preview.

### Changed

- The minimum supported system is now macOS 15 so translation can remain inside
  Apple's native framework without third-party translation services.

### Fixed

- Live Text now receives the image's normalized unit rectangle, fixing OCR
  selection hit testing in letterboxed previews.
- QR link previews now dim the captured image and use larger animated link
  arrows so detected actions are immediately visible.
- Detected non-web codes now show a prohibited marker with an explanatory
  tooltip; scans with no supported result show the same marker at preview
  center.
- Dense multi-code screenshots now receive a second overlapping tiled scan with
  adaptive local enlargement, then merge results back into original-image
  coordinates without duplicate markers.
- The screenshot color inspector now disappears as soon as selection begins and
  stays hidden after mouse release until the pointer moves again.
- Repeated local translations now refresh the active Apple translation session
  reliably instead of invalidating a newly created configuration.
- Repeated barcode scans now replace stale link markers while preserving
  identical links detected at different image positions.
- Screenshot Save now hides the full-screen capture overlay before showing the
  macOS save panel, preventing the app from appearing frozen.
- Screenshot warmup no longer keeps a resident ScreenCaptureKit stream running
  in the background, reducing long-session CPU, GPU, and memory pressure.

## [1.0.0] - 2026-06-14

### Fixed

- Screenshot toolbar buttons now accept clicks at their visual edges and
  spacing, so the Done button no longer falls through as an outside-selection
  click.
- Screenshot capture and the resident frame cache now use the display mode's
  physical pixel dimensions at best quality, preventing scaled Retina and 4K
  previews from appearing soft.

### Release

- Promoted Cliploom to its first stable release after completing the clipboard,
  screenshot, OCR, barcode, color inspection, and cross-platform design
  workflows.
- Ships as an ad-hoc signed, unnotarized Universal DMG for Apple Silicon and
  Intel Macs.

## [0.1.2] - 2026-06-14

### Added

- Screenshot mode now shows a compact color swatch and HEX value beside the
  pointer without obscuring nearby content.
- `Command+C` copies the hovered HEX value without adding it to clipboard
  history.

### Changed

- Right-click and Escape now share the same immediate screenshot cancellation
  behavior from every overlay state.
- Escape is captured at the screenshot session level so it still works when a
  child view or result window owns keyboard focus.
- Automatically detected windows now remain at their original brightness, with
  a stronger high-contrast selection border in both light and dark content.
- Screenshot hotkeys now use a recent in-memory ScreenCaptureKit frame when
  available, preserving QR-code popovers that close as soon as a key is pressed.
- Starting another screenshot from an OCR or QR result window now snapshots the
  visible result first, then closes the previous session.

## [0.1.1] - 2026-06-12

### Added

- Universal macOS Developer Preview DMG for Apple Silicon and Intel Macs.
- Beginner-friendly installation and permission guide.
- Repeatable ad-hoc preview packaging script with SHA-256 checksum output.

### Changed

- README now focuses on product usage and consistent workflows across macOS and
  the planned Windows port.
- Preview builds use a stable application identifier and designated requirement
  to improve permission continuity during in-place updates.

### Distribution

- The downloadable DMG is ad-hoc signed and is not notarized.
- Users must explicitly allow the first launch through macOS security controls.

## [0.1.0] - 2026-06-12

### Added

- Native macOS menu bar clipboard history for text, links, images, and files.
- Search, category filters, favorites, deletion, keyboard navigation, and panel
  position memory.
- Configurable `Option+V` clipboard and `Option+A` screenshot hotkeys.
- Window-aware and free-selection screenshots at native pixel resolution.
- Rectangle, arrow, pen, text, mosaic, undo, save, and clipboard output tools.
- Local OCR with image/text split view and remembered divider ratio.
- Local QR/barcode recognition with safe copy and HTTP/HTTPS open actions.
- Chinese and English localization.
- Local install, Developer ID signing, notarization, and packaging scripts.
- Windows port handoff document for follow-up implementation.

### Privacy

- Clipboard history, screenshots, OCR, and barcode recognition stay local.
- Cliploom contains no cloud sync, telemetry, or automatic content upload.

### Distribution

- This first GitHub release is a source preview.
- A signed and notarized binary is not attached because the repository owner
  has not configured a Developer ID Application certificate in this environment.

[1.0.0]: https://github.com/ywjzywn-coder/Cliploom/releases/tag/v1.0.0
[0.1.2]: https://github.com/ywjzywn-coder/Cliploom/releases/tag/v0.1.2
[0.1.1]: https://github.com/ywjzywn-coder/Cliploom/releases/tag/v0.1.1
[0.1.0]: https://github.com/ywjzywn-coder/Cliploom/releases/tag/v0.1.0
