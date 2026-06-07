# Changelog

## 1.1.0

### Added
- Added achievement sorting options in the game details screen: original order, A-Z, and unlock date.
- Added persistent sorting preferences for the main games list and achievement list.
- Added a cleaner achievement options panel accessible from the search bar.

### Changed
- Improved the achievement details UI to reduce visual clutter.
- Moved achievement sorting and hidden-description visibility into a bottom sheet.
- Main “Recent” games sorting now uses Steam’s last played timestamp.
- After the first full sync, background sync now scans only the 20 most recently played games.
- Manual refresh now prioritizes recent games instead of re-scanning the whole library.
- Game details now try to load achievements online first and only fall back to cache when offline or loading fails.

### Fixed
- Fixed recent games sorting not showing the actual most recently played games.
- Fixed refresh not updating newly unlocked achievements reliably.
- Fixed repeated full-library scans that could cause slow syncs or temporary Steam API rate limits.
- Fixed the scan notification appearing every time the app opened.
- Fixed a mismatch where a game could show the correct unlocked count in the list but one fewer unlocked achievement in the details screen.
