# Changelog

All notable changes to this project are documented in this file.

## 2.0.7 - 2026-03-27

This release hardens Delve inspect behavior so it cannot interfere with normal inspect usage outside Delves.

### Changed
- Scoped Delve inspect state handling so scans reset immediately when Delve conditions are no longer active.
- Restricted inspect-ready processing to addon-initiated Delve inspect requests only.

### Fixed
- Fixed inspect leakage that could interrupt manual player inspection outside Delves.

### Added
- Added `/dirtytricks debug` counters for pending and cached Delve inspect state visibility.

## 2.0.6 - 2026-03-20

This release improves Delve tank detection for groups where role assignments are unavailable.

### Added
- Added Delve inspect scan support for party members in tank-capable classes.
- Added inspected specialization cache handling for asynchronous tank detection updates.

### Changed
- Changed Delve scan behavior to only run inspect logic when at least one real player (besides the user) is in the party.
- Updated grouped Delve profile label output from `Party` to `Delve`.

### Fixed
- Fixed Delve grouped detection where role-based APIs return no assigned tank roles.

## 2.0.5 - 2026-03-19

This release improves raid/party stability, reduces chat spam, and adds better raid targeting controls.

### Added
- Added a default-off raid option to prefer tanks in the same odd/even raid subgroup parity as the player.
- Added ready check triggered macro refresh support for near-immediate target updates before pull.
- Added extended `/dirtytricks debug` output for raid subgroup parity and final tank ordering visibility.

### Changed
- Changed automatic chat notifications to fire once per context transition (`solo`, `party`, `raid`) instead of repeatedly during roster churn.
- Added a short raid settle window before automatic macro refresh to reduce target thrash while raid groups are reorganizing.
- Updated tank selection ordering to keep settings panel and runtime detection behavior aligned.

### Fixed
- Fixed settings tank list class coloring so each detected tank name uses its own class color.

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
