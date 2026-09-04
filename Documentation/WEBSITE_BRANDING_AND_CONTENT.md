# Website Branding and Content Handoff

This is the starting document for another LLM or web developer building the Camera Zapper site at **https://zebtron.com/zapper/**.

## Source material to read

All paths below are relative to the packaged `Zebtron-Camera-Zapper-1.350` project folder:

1. `App-Source/Documentation/USER_MANUAL.md` — authoritative behavior, workflow, integrations, troubleshooting, privacy, and deletion safety.
2. `App-Source/Documentation/INSTALLATION.md` — installation and Android setup steps.
3. `App-Source/Documentation/DEVELOPER_HANDOFF.md` — architecture, product invariants, and distribution status.
4. `App-Source/Documentation/Screenshots/` — real captures from the finished app; use these rather than fabricated UI mockups.
5. `Branding/CameraZapperIcon-master.png` — full-resolution icon master.
6. `Website-Source/` — existing editable website project and current implemented copy/layout.

If documentation conflicts with older copy, the current user manual and app UI win. Do not claim public notarization or automatic updates until they exist.

## Brand identity

- Product name: **Zebtron Camera Zapper — automated backup**
- Short name: **Camera Zapper**
- Tagline: **move · sync · delete**
- Version-one purpose: verified photo/video ingest and safe multi-destination backup
- Future 2.0 working name: **Belt and Suspenders** (do not market as a current feature)
- Maker: **Zebtron**
- Product URL: **https://zebtron.com/zapper/**
- Support email: **zapper@zebtron.com**
- Donation URL: **https://ko-fi.com/zebtron**

## Visual direction

Use a dark navy/charcoal foundation with electric blue for transfer/action and warm amber for the lightning/energy accent. The icon shows one camera sending media in a clearly one-way fan-out to three generic destinations: cloud, local disk, and NAS. Preserve the arrowheads, generous spacing, and generic destination symbols. Never add circular/bidirectional arrows or service trademarks.

Preferred tone: confident, practical, transparent, slightly playful, and safety-first. Avoid fear marketing and avoid saying a sync is a backup unless it is verified.

## Core website copy

### Hero

**Your camera roll deserves more than one backup.**

Zebtron Camera Zapper moves, verifies, syncs, and—only when you approve—safely deletes media from cameras, cards, Android phones, tablets, and folders on your Mac.

Free for macOS. If it saves you time or a memory, support continued development on Ko-fi.

### Why it exists

I built Camera Zapper for my own Macs because the available sync apps were incomplete, awkward, or tied to one destination. I wanted one understandable workflow for local safety staging, my NAS, Apple Photos, Google Photos, Flickr, private YouTube video backup, and NeoFinder—without guessing what finished or risking originals.

### Features

- One-button scan, verified backup, destination sync, preflight, and safe deletion
- SHA-256 verification and interruption-safe local staging
- NAS catch-up after LAN or VPN reconnects
- Google Photos session albums, Apple Photos, Flickr, private YouTube, and NeoFinder
- Android USB/wireless ADB with guided troubleshooting
- Persistent offline device history, nicknames, facts, and sync status
- Durable deduplication receipts and multi-Mac-aware design
- Advanced per-stage and per-service controls

### Supported originals

Camera Zapper currently ingests common JPEG, HEIC/HEIF, PNG, TIFF, major camera RAW formats (Sony ARW, Fujifilm RAF, Canon CR2/CR3, Nikon NEF/NRW, Olympus ORF, Panasonic RW2, DNG, and GoPro GPR), and video including MP4, MOV, M4V, MKV, AVI, MTS/M2TS, 3GP, and WebM. Local/NAS archives retain originals. Cloud destinations support provider-specific subsets; link to the manual rather than implying every provider accepts every format.

### Private by design

Cloud uploads are private-only. Camera Zapper cannot accidentally publish a YouTube video or Flickr upload, and it never creates a shared Google Photos link. Source deletion stays blocked until every service marked required has verified that exact file.

### How it works

1. Connect a device or choose an ingest folder.
2. Press **Sync, Verify & Safely Delete**.
3. Watch file and destination progress on screen.
4. Eligible originals are deleted only after every required check passes.

### Testing-build notice

The current build is for hands-on testing and is ad-hoc signed. First launch may require Control-click → Open. Do not call it notarized until the release engineering work is complete.

## Page structure

Recommended order: navigation, hero and app screenshot, trust/safety strip, origin story, destinations, offline workflow, how it works, privacy, installation, troubleshooting/manual links, donation, footer.

## Bug-reporting section

Add **Report a bug** to the main navigation and footer. The button should open a prefilled message to `zapper@zebtron.com` requesting the app version, device model, connection method, steps to reproduce, expected result, and last visible error.

Use this expectation-setting copy:

> Camera Zapper is independently maintained in limited spare time. Every useful report is appreciated, but replies and fixes may take a while. Thank you for your patience.

Tell reporters to remove passwords, API secrets, OAuth tokens, personal paths, and private filenames before sending logs or screenshots. The tone should be grateful and candid, never dismissive.

Every download button should state the version and macOS requirement. Link the manual and installation guide near the download—not only in the footer. Put Ko-fi after the value proposition, not before it.

## Accessibility and asset rules

- Use real HTML headings in logical order.
- Maintain WCAG AA contrast and keyboard-visible focus.
- Alt text for the icon: “A camera sending media outward to cloud, local-disk, and NAS destinations.”
- Alt text for screenshots should describe the page and current status shown.
- Never place API keys, OAuth JSON, personal paths, serial numbers, IP addresses, or account names in public screenshots.
- Crop screenshots to the app window and review them for personal data before publishing.
