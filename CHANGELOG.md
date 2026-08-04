# autokbisw

Modernized fork of ohueter/autokbisw.

This project aims to improve stability, diagnostics and long-term maintainability while preserving compatibility with the original utility.

## Changelog

## 2.1.0-beta1 - 2026-08-03

### Added
- Added `doctor` diagnostic command.
- Added keyboard link groups for USB/Bluetooth identities.
- Improved HID diagnostic logging.

### Fixed
- Fixed a deadlock during input source switching.
- Improved synchronization in the keyboard event monitor.

### Changed
- Modernized CLI behavior.
- Updated tests for Swift/Xcode compatibility.
