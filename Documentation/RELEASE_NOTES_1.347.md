# Zebtron Camera Zapper 1.347 - Controlled Beta

## First-run setup without false errors

Version 1.347 adds a first-run Setup Wizard and corrects the configuration-state model. A brand-new install now starts with a verified local safety archive and neutral, disabled destinations instead of treating example NAS values as errors.

## Setup Wizard and service states

- Automatically opens on first launch and whenever setup remains incomplete after an upgrade.
- Walks through welcome, local archive, service selection, deletion gates, per-service configuration, priority, and first-run review.
- Distinguishes **Not set up**, **Configuring**, **Operational**, and **Needs attention**. Only a configured failing service may show an error.
- Unselected services do not warn, nag, count as required, or block deletion.
- A selected file destination is tested using write → SHA-256 read-back → delete, and the checker immediately uses the newly chosen path.
- Setup is skippable and remains available from the dashboard and Settings.

## Settings that survive upgrades and move between Macs

- Camera Zapper continuously keeps a latest settings snapshot and a daily snapshot under `~/Library/Application Support/Zebtron Camera Zapper/Settings Backups/`.
- Settings → General includes **Export Settings**, **Import Settings**, and **Show Automatic Backups**.
- Exported JSON includes destinations, priorities, media rules, cache behavior, and safety settings.
- Passwords, API secrets, OAuth tokens, and Keychain contents are never exported. Google Photos, private YouTube, and Flickr must be authorized on each Mac after import.

## Pre-release hardening

- Replaced developer-specific NAS, volume, coordinator, and device defaults with generic public defaults.
- Fresh installs begin in standalone mode with only a local archive enabled.
- Added a first-run destination review and warnings for missing or unwritable enabled storage.
- Added clear Android Platform Tools installation guidance when ADB is unavailable.
- Made optional compatibility conversion report the built-in macOS `avconvert` dependency accurately.
- Added VoiceOver semantics to saved/connected device rows.
- Added deletion-preflight regression tests for verified content, wrong size, wrong hash, and partial-file cleanup.
- Updated the app, manual, website copy, bug-report template, and package metadata to 1.347.

## Safety behavior

Source deletion is confirmation-only by default. Camera Zapper completes a non-destructive preflight for every candidate before the first delete call. All applicable required services need verified receipts; local and mounted file copies are rechecked for regular-file status, byte size, and SHA-256 content.

## Distribution status

This artifact is ad-hoc signed for controlled testing. It is not yet the final public binary. Developer ID signing, hardened-runtime review, notarization/stapling, and production OAuth/API review remain release gates.
