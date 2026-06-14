# Changelog

All notable changes to Cliploom are documented here.

## Unreleased

### Fixed

- Screenshot toolbar buttons now accept clicks at their visual edges and
  spacing, so the Done button no longer falls through as an outside-selection
  click.

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

[0.1.2]: https://github.com/ywjzywn-coder/Cliploom/releases/tag/v0.1.2
[0.1.1]: https://github.com/ywjzywn-coder/Cliploom/releases/tag/v0.1.1
[0.1.0]: https://github.com/ywjzywn-coder/Cliploom/releases/tag/v0.1.0
