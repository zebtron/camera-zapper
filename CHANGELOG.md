# Changelog

All notable changes to **Zebtron Camera Zapper** are documented here.
The format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
releases use the app's build-number versioning.

## [1.346] — 2026-08-23 · Controlled beta

### Changed
- Redesigned the application icon around Camera Zapper's one-way, one-to-many workflow: one camera sends media outward to generic cloud, local-disk, and NAS destinations.
- Removed the former circular-sync and verification-check imagery so the icon cannot be mistaken for bidirectional synchronization.
- Regenerated the complete macOS iconset, application ICNS, 1024 px master, and 512 px website icon.
- Updated icon descriptions, alternative text, documentation, screenshots, and release metadata.

### Security / privacy
- The icon uses generic destination glyphs and contains no third-party service trademarks.
- No product behavior, credentials, telemetry, cloud visibility, or deletion policy changed in this release.

## [1.345] — 2026-08-23 · Controlled beta

First public (controlled-beta) release, open-sourced under the MIT license.

### Added
- Verified backup pipeline: **SHA-256** verification, interruption-safe local staging, and
  **safe delete** that stays blocked until every destination marked *required* has a durable receipt.
- Destinations: local archive, **NAS (SMB)**, Apple Photos, Google Photos (session albums),
  Flickr, **private** YouTube, and NeoFinder.
- Android ingest over **USB/wireless ADB** with guided troubleshooting.
- Offline device history, nicknames, and sync status; deduplication receipts (multi-Mac aware);
  offline cache with NAS catch-up after LAN/VPN reconnects.
- Advanced per-stage and per-service controls.

### Changed
- Genericized first-run defaults — no personal device names, hostnames, or paths. Fresh installs
  start standalone with a local archive at `~/Pictures/Camera Zapper/Archive`; NAS and cloud
  services are disabled until enabled. `/Volumes/NAS`, `your-nas.local`, and "Media" are examples only.
- Coordinator name now derives from the machine name at runtime instead of a hardcoded value.
- Generalized Android help text (no device-model-specific references).

### Security / privacy
- No embedded credentials or API keys; secrets are stored in the macOS Keychain and excluded
  from source and distribution archives.
- Cloud uploads are private-only; the app never creates public or shared links. No telemetry.

### Notes
- This build is **ad-hoc signed** — on first launch, Control-click the app and choose **Open**.
  It is not yet notarized, and cloud OAuth (Google / Flickr / YouTube) is still in review.

[1.346]: https://github.com/zebtron/camera-zapper/releases/tag/v1.346
[1.345]: https://github.com/zebtron/camera-zapper/releases/tag/v1.345
