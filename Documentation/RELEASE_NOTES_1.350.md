# Zebtron Camera Zapper 1.350 - Controlled Beta

## Flickr OAuth hotfix

- Signed Flickr REST account checks now use Flickr's canonical `api.flickr.com` endpoint, matching Flickr's maintained SDK.
- Flickr's raw OAuth `debug_sbs` response is no longer shown or logged because it can contain the API key and access token.
- Authorization failures now provide a short, actionable reconnect message without exposing provider diagnostics.

## Flickr authorization and completion fixes

- Flickr now validates saved credentials against `flickr.test.login` instead of trusting a local Boolean.
- The service configuration shows the connected account and provides **Test Live Login**, **Reconnect**, and **Disconnect** actions.
- API credentials and the resulting access token are saved atomically only after the complete OAuth exchange succeeds.
- Cancelling or failing reauthorization no longer leaves a new API secret paired with an old access token.
- Oversized photos and videos are clearly counted as skipped. They no longer make an optional Flickr destination look completely broken.
- An oversized item blocks source deletion only when Flickr is marked required and Flickr accepts that item's media type.

## One-button workflow with visible progress and recovery

Version 1.350 makes the normal workflow one obvious action: **Sync All Locations & Delete**. The connected-device page shows the service and file currently being processed, per-service state, counts, and a detailed timestamped log. After a failure or interruption, the button changes to **Resume Sync All Locations & Delete** and safely reuses completed receipts.

## Actionable errors and direct service configuration

- Dashboard warnings identify the affected service and retain the useful provider error instead of displaying only “Problem.”
- Service problems provide a direct **Open [Service] Settings** repair action.
- Every service now has a clearly labeled **Configure…** button outside the first-run wizard.
- Google Photos configuration directly exposes OAuth JSON selection/reauthorization and authorization testing. Flickr and YouTube provide equivalent controls.
- Detailed activity is visible by default and can be collapsed with **Show detailed activity**.

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
- Updated the app, manual, website copy, bug-report template, and package metadata to 1.350.

## Safety behavior

Source deletion is confirmation-only by default. Camera Zapper completes a non-destructive preflight for every candidate before the first delete call. All applicable required services need verified receipts; local and mounted file copies are rechecked for regular-file status, byte size, and SHA-256 content.

## Distribution status

This artifact is ad-hoc signed for controlled testing. It is not yet the final public binary. Developer ID signing, hardened-runtime review, notarization/stapling, and production OAuth/API review remain release gates.
