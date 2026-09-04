# Camera Zapper 1.350 release handoff

Released September 4, 2026 as a controlled beta.

## Release focus

- Correct Flickr's signed post-authorization account check by using `https://api.flickr.com/services/rest`.
- Suppress Flickr OAuth `debug_sbs` responses because they can contain an API key and OAuth access token.
- Replace raw Flickr provider diagnostics with concise reconnect guidance.

## Published locations

- GitHub release: <https://github.com/zebtron/camera-zapper/releases/tag/v1.350>
- DMG: <https://github.com/zebtron/camera-zapper/releases/download/v1.350/Zebtron-Camera-Zapper-1.350.dmg>
- Manual: <https://github.com/zebtron/camera-zapper/releases/download/v1.350/Zebtron-Camera-Zapper-1.350-User-Manual.pdf>
- NAS source: `/Volumes/Projects/029_VibeCodedApps/Camera-Zapper/Zebtron-Camera-Zapper-1.350/`
- Website mirror: `/Volumes/web/namecheap/zebtron.com/zapper/`

## Validation

- Six Swift tests passed.
- App version/build: 1.350 / 1350.
- DMG verification and ad-hoc bundle signature verification passed.
- DMG SHA-256: `c79d08b548ec7b96093ef7d19902590db5cbd21e6142b3c73a423026d618270c`.
- Source/resource scan found no embedded OAuth JSON, private keys, API secrets, or credential-like 32-character hexadecimal values.
- The app remains ad-hoc signed and unnotarized for controlled beta testing.
