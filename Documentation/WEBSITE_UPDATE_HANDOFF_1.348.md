# Camera Zapper Website Update Handoff - Version 1.348

## Purpose

Update `zebtron.com/zapper/` for the 1.348 controlled beta. The site source is in the sibling `CameraZapperWebsite` project. This document is the implementation brief for a person or another LLM updating the hosted site.

## Release wording

Use **Version 1.348 controlled beta**. Do not call the current ad-hoc-signed DMG a production-ready public release. Public distribution remains gated on:

- Apple Developer ID Application signing with a stable identity
- hardened-runtime and entitlement review
- Apple notarization and ticket stapling
- production OAuth consent/API review for Google and other providers
- final privacy-policy and third-party trademark review

The intended first public channel is a direct notarized DMG from Zebtron, not the Mac App Store. Sandboxing would require redesign around mounted NAS volumes, ADB, automation, and user-selected folders.

## Required website changes

1. Change every displayed version and bug-report subject from the previous beta to 1.348.
2. Explain that new installs contain no personal device names, hostnames, volume names, or developer paths.
3. State that a fresh install starts in standalone mode with a local archive at `~/Pictures/Camera Zapper/Archive`.
4. State that NAS and cloud services start disabled. `/Volumes/NAS`, `your-nas.local`, and `Media` are examples only.
5. Add Android Platform Tools as an explicit prerequisite. Suggested command: `brew install android-platform-tools`. Explain that ADB supplies detection, file listing, on-device hashes, copying, and confirmed deletion.
6. State that source deletion remains confirmation-only by default and is blocked unless every applicable required receipt passes a complete preflight.
7. Preserve the private-only guarantee: Google Photos albums are not shared by the app, Flickr is private/hidden, and YouTube is private. There is no public/unlisted control.
8. Keep the independent-maintainer bug-report note: reports are welcome, but replies and fixes may take time.
9. Introduce the seven-step Setup Wizard. A fresh install opens with Welcome instead of red configuration errors.
10. Explain the four service states: Not set up (neutral), Configuring, Operational, and Needs attention. Only configured services can need attention; only explicitly required services can block deletion.
11. Mention that file destinations pass a write → SHA-256 read-back → delete verification test.
12. Mention portable settings export/import and automatic backups that survive replacing the app bundle. State clearly that credentials and OAuth tokens are excluded and must be authorized per Mac.

## Recommended install copy

> Install Camera Zapper in Applications, install Android Platform Tools if you use Android, then follow the Setup Wizard. Choose only the destinations you use; everything else remains quietly Not set up. Start with noncritical media and leave deletion confirmation enabled while testing.

## Required links

- Product: `https://zebtron.com/zapper/`
- Bug reports: `mailto:zapper@zebtron.com`
- Donations: `https://ko-fi.com/zebtron`
- Privacy anchor: `https://zebtron.com/zapper/#privacy`

The bug-report template should request app version, macOS version, source device model, connection method, steps, expected result, and last visible error. It must remind users to remove passwords, API secrets, OAuth tokens, personal paths, and private filenames.

## Download presentation

When the notarized artifact exists, present these together:

- `Zebtron-Camera-Zapper-1.348.dmg`
- `Zebtron-Camera-Zapper-1.348-User-Manual.pdf`
- installation guide and release notes
- SHA-256 checksum for the DMG

Until notarization is complete, retain **Request the macOS beta** rather than a broad public download button.

## Content sources

- `Documentation/USER_MANUAL.md` - canonical usage and safety behavior
- `Documentation/INSTALLATION.md` - installation and first-run prerequisites
- `Documentation/WEBSITE_BRANDING_AND_CONTENT.md` - established brand voice and page architecture
- `Documentation/DEVELOPER_HANDOFF.md` - engineering and release constraints
- `Documentation/Screenshots/setup-wizard-1.348.png` - clean first-run Welcome screen
- `Documentation/Screenshots/dashboard-1.348.png` - tidy generic dashboard with NAS neutrally Not set up
- `Documentation/Zebtron-Camera-Zapper-1.348-User-Manual.pdf` - downloadable manual

## Verification checklist

- Version is consistently 1.348.
- No credentials, API client secrets, access tokens, private hostnames, personal email addresses other than the public support address, or absolute user paths appear in HTML or downloadable artifacts.
- macOS 14+ and ADB requirements are visible near installation.
- The site does not imply that local staging alone proves every required destination completed.
- The page remains keyboard navigable, responsive, and readable with reduced motion.
- Download filename and checksum match the final notarized artifact exactly.
