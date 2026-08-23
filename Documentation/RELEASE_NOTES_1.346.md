# Zebtron Camera Zapper 1.346 - Controlled Beta

## New one-way fan-out icon

Version 1.346 introduces a redesigned app icon showing one camera sending media outward to three generic destinations: cloud, local disk, and NAS. Explicit arrowheads communicate the one-way ingest-and-copy workflow. The previous circular sync arrows and verification-check badge are removed, and no third-party service trademarks appear.

## Pre-release hardening

- Replaced developer-specific NAS, volume, coordinator, and device defaults with generic public defaults.
- Fresh installs begin in standalone mode with only a local archive enabled.
- Added a first-run destination review and warnings for missing or unwritable enabled storage.
- Added clear Android Platform Tools installation guidance when ADB is unavailable.
- Made optional compatibility conversion report the built-in macOS `avconvert` dependency accurately.
- Added VoiceOver semantics to saved/connected device rows.
- Added deletion-preflight regression tests for verified content, wrong size, wrong hash, and partial-file cleanup.
- Updated the app, manual, website copy, bug-report template, and package metadata to 1.346.

## Safety behavior

Source deletion is confirmation-only by default. Camera Zapper completes a non-destructive preflight for every candidate before the first delete call. All applicable required services need verified receipts; local and mounted file copies are rechecked for regular-file status, byte size, and SHA-256 content.

## Distribution status

This artifact is ad-hoc signed for controlled testing. It is not yet the final public binary. Developer ID signing, hardened-runtime review, notarization/stapling, and production OAuth/API review remain release gates.
