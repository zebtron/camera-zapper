# Changelog

All notable changes to **Zebtron Camera Zapper** are documented here.
The format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
releases use the app's build-number versioning.

## [1.348] — 2026-09-04 · Controlled beta

### Added
- Added one large **Sync All Locations & Delete** action for each connected device. After an interrupted or failed run it becomes **Resume Sync All Locations & Delete** and safely skips completed receipts.
- Added live per-service workflow status showing the service currently running, current file/action, completed and queued services, item counts, and verbose timestamped activity.
- Added an on-by-default **Show detailed activity** preference; turning it off collapses the verbose log without reducing recorded workflow detail.
- Added actionable dashboard errors that identify the affected service, preserve the provider's useful error detail, and open that service's configuration directly.
- Added clearly labeled per-service **Configure** controls independent of the setup wizard, including Google OAuth JSON selection/reauthorization and connection testing.
- Added an accessible seven-step first-run Setup Wizard covering the local safety archive, service selection, deletion gates, per-service configuration, priority, and first-run review.
- Added a reusable **Run Setup Again** action and a gentle **Finish setup** dashboard affordance.
- Added a real file-destination probe that writes a temporary payload, verifies its SHA-256 after read-back, and deletes the probe.
- Added explicit settings export/import plus automatic version-independent JSON backups in Application Support.

### Changed
- Required-service failures stop deletion with a named reason; optional failures remain visible but do not invalidate completed storage or cloud receipts.
- Advanced partial-workflow actions remain available below the single primary action.
- Introduced explicit **Not set up**, **Configuring**, **Operational**, and **Needs attention** service states.
- Fresh installs now enable only the local archive. Unselected services remain neutral, never warn, and never block deletion.
- Selecting a destination folder immediately updates the path used by validation and re-runs the destination test.
- The dashboard no longer presents example NAS values as a failing configuration.
- Safe deletion remains confirmation-only and is gated solely by enabled services explicitly marked required.
- Settings exports deliberately omit Keychain credentials, OAuth tokens, passwords, and API secrets; cloud accounts must be authorized separately on another Mac.

### Security / privacy
- Cloud services remain private-only; the app has no telemetry.
- No credentials or organization-specific paths are bundled.

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

[1.348]: https://github.com/zebtron/camera-zapper/releases/tag/v1.348
[1.346]: https://github.com/zebtron/camera-zapper/releases/tag/v1.346
[1.345]: https://github.com/zebtron/camera-zapper/releases/tag/v1.345
