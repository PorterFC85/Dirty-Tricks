# Changelog

All notable changes to this project are documented in this file.

## 2.0.4 - 2026-03-18

This release establishes a clean forward tag flow after the earlier 2.0.3 tag mismatch.

### Changed
- Bumped addon metadata and documentation version references from 2.0.3 to 2.0.4.

### Release
- Created a new release line for clean semantic version and tag progression.

## 2.0.3 - 2026-03-18

This release improves target detection reliability and startup behavior.

### Changed
- Improved group tank detection behavior in mixed and raid-role edge cases.
- Added throttling for automatic tank-change announcements during rapid roster updates.

### Fixed
- Settings dialog initialization now only runs for this addon's ADDON_LOADED event.
- Prevented duplicate settings dialog creation on load.

## 2.0.2 - 2026-03-12

Release pipeline fix release.

### Fixed
- Removed dependency on CurseForge SVN externals during packaging to prevent release failures.
- Updated release workflow configuration for current GitHub Actions runtime compatibility.
- Corrected CurseForge project mapping in package metadata.

## 2.0.1 - 2026-03-12

This is a re-release focused on reliability and polish.

### Changed
- Updated slash command usage from `/sar` to `/dirtytricks`.
- Tuned detection logic for more reliable redirect target selection.
- Improved settings layout by moving version text to the bottom and adding a top-right close button.

### Fixed
- Resolved bundled library packaging issues for a cleaner CurseForge release.
- Minor menu and settings UI behavior fixes.

## 1.1.4 - 2026-03-01

### Added
- ElvUI-aware visual styling fallback support for the settings dialog.

### Improved
- General stability and update flow improvements for macro refresh behavior.
