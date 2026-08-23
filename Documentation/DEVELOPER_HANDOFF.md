# Developer / LLM Handoff

## Product intent

Camera Zapper is a safety-first native macOS ingest orchestrator. Its core invariant is: **never delete a source file until the exact content has verified receipts from every enabled destination marked required**. One Mac must work independently; multi-machine coordination is optional.

## Repository map

- `Package.swift` — Swift package definition, macOS 14 minimum
- `Sources/CameraBackup/` — SwiftUI UI, models, persistence, transfer engine, service adapters
- `Sources/CSQLite/` — SQLite system module
- `Tests/CameraBackupTests/` — automated tests
- `Resources/CameraZapper.icns` and `Assets/` — icon files
- `Documentation/` — installation, manual, branding/content, and screenshots
- `build-app.sh` — bundle assembly, Info.plist, and ad-hoc signing
- `dist/` — generated app and DMG, not source of truth

## Architectural invariants

1. Content identity is SHA-256, not filename or timestamp.
2. Copy into `.partial` staging, verify, then atomically place the final file.
3. Receipts survive app restarts and source disconnects.
4. Required services gate deletion only when applicable to the media type.
5. Per-file failures should not unnecessarily abort unrelated files.
6. Cloud uploads are private-only and expose no visibility control.
7. Credentials live in Keychain, never source, logs, bundles, or database.
8. Offline cache is temporary safety staging, not an assumed permanent archive.

## Build and test

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox

./build-app.sh
codesign --verify --deep --strict "dist/Zebtron Camera zapper - automated backup.app"
```

Runtime state lives in `~/Library/Application Support/Zebtron Camera Zapper/` and must never be included in a handoff. Version 1.345 is ad-hoc signed. Public distribution still requires Apple Developer ID signing, hardened runtime/entitlements review, notarization, OAuth production setup, privacy/API verification, and an updater.

## 1.345 pre-release hardening

- New-user defaults contain no personal hostnames, device nicknames, shares, or volume names.
- Local archive defaults to `~/Pictures/Camera Zapper/Archive`; NAS/cloud destinations start disabled.
- First run presents a destination review and validates missing or unwritable storage.
- Coordination defaults to standalone and derives the coordinator name from `Host.current().localizedName`.
- Missing ADB produces installation guidance instead of silently appearing to find no devices.
- Optional video conversion uses macOS `/usr/bin/avconvert`; MP4 and MKV remain unchanged.
- Destructive actions remain off/confirmation-only by default and use a complete two-phase preflight.
- Sidebar device rows have explicit VoiceOver labels, hints, and button traits.
- `BackupEngine.archivedCopyIsVerified` is exercised for verified copies, wrong size, wrong hash, and failed-copy cleanup.

Do not describe the ad-hoc beta DMG as a production-ready public download. Stable distribution requires a Developer ID Application certificate, hardened runtime, notarization/stapling, and repeatable release signing. Mac App Store sandboxing is not the recommended initial channel because mounted NAS volumes, ADB, external integrations, and user-selected folders require a broader entitlement redesign.

The handoff archive excludes build caches, runtime databases, OAuth JSON, API keys, tokens, Keychain entries, and user media.
