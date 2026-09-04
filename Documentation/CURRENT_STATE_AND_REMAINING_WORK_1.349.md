# Zebtron Camera Zapper 1.349 — Current State and Remaining Work

Updated: September 3, 2026

## Current state

Version 1.349 is built as a controlled macOS beta. The app, source, documentation, screenshots, PDF manual, DMG, application ZIP, and checksums are stored together in this handoff.

Implemented in 1.349:

- Guided first-run setup wizard with neutral “Not set up” service states.
- Local archive, NAS, Google Photos, Apple Photos, Flickr, NeoFinder, and YouTube configuration paths.
- Required-for-deletion safety gates and ordered services.
- Portable settings export/import. Exports include service choices, order, destinations, and behavior but exclude passwords, API secrets, OAuth tokens, and Keychain data.
- Persistent automatic configuration snapshots under `~/Library/Application Support/Zebtron Camera Zapper/Settings Backups/`.
- A timestamped “Before Import” snapshot is written before imported settings replace the current configuration.
- Existing device history, guided Help content, current icon, website/donation links, and private-only cloud-upload messaging.
- Version and build identifiers: 1.349 / 1349.

Verification completed:

- Five Swift tests pass.
- Release build succeeds.
- DMG filesystem checksum is valid.
- Application ZIP passes archive validation.
- App passes ad-hoc code-signature verification.
- Source and distributable scan found no embedded credential values or private keys. References to credential field names are implementation code only.

## Important beta constraints

- This is ad-hoc signed, not Apple notarized. Gatekeeper may require the documented first-launch procedure.
- OAuth authorization is intentionally machine-local and is not transferred through settings exports.
- Automatic settings backups protect configuration changes and upgrades, but they are not a replacement for backing up the whole Application Support folder.
- Destructive source deletion should remain manually confirmed until each device and required-service combination has been tested.

## Remaining tasks

1. Install the 1.349 DMG on the M1 16 GB Mac and test wizard completion, relaunch persistence, settings export, and settings import.
2. Confirm upgrading over 1.346 preserves the existing configuration in Application Support.
3. Re-authorize cloud services after a settings import and confirm the wizard accurately reports each state.
4. Run plug-in-to-delete tests for the S22 Ultra and Tab S7+ with required destinations enabled.
5. Confirm automatic Settings Backups contain no credentials and restore correctly on another Mac.
6. If testing passes, commit and push the final 1.349 sources to GitHub and create the `v1.349` prerelease with DMG, app ZIP, PDF manual, and checksums.
7. Update `zebtron.com/zapper/` using `Documentation/WEBSITE_UPDATE_HANDOFF_1.349.md` and the two 1.349 screenshots.
8. For public distribution later: Developer ID signing, notarization, an update channel, public OAuth app review/credentials, privacy-policy review, and a support/bug-report workflow.

## Resume point for another LLM

Start with this file, `Documentation/DEVELOPER_HANDOFF.md`, `Documentation/RELEASE_NOTES_1.349.md`, and the repository status. Do not embed or commit OAuth JSON, Flickr credentials, tokens, passwords, Keychain exports, or personal settings backups. Re-run `swift test` and `./build-app.sh` after code changes, then update `dist/SHA256SUMS.txt`.
