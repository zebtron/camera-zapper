# Zebtron Camera Zapper live page source

This directory contains the September 2026 snapshot of the live `https://zebtron.com/zapper/` page, updated for Camera Zapper 1.349.

`index.html` is a complete standalone page. It includes a static, fully functional 1.349 release panel and a progressive enhancement that reads the newest non-draft GitHub release from:

`https://api.github.com/repos/zebtron/camera-zapper/releases?per_page=10`

The script updates the displayed version, DMG, manual, release page, file size, checksum file, and SHA-256 value. It uses the releases list rather than `/releases/latest` because GitHub's latest-release shortcut excludes prereleases, while Camera Zapper is currently distributed as a controlled beta.

If GitHub or its API is unavailable, visitors retain the hardcoded 1.349 links and verified checksum. No API key, deployment password, or other credential is embedded.

For future releases, keep asset names consistent with the existing convention. The live page will then follow the newest release automatically. Copy changes are still manual when features, prerequisites, or safety behavior change.

## Selective FTP upload

`upload-selected-ftp.sh` uploads only the filenames explicitly passed to it. It prompts for the password without displaying it and does not contain saved credentials.

The script connects through `premium342.web-hosting.com`, whose name matches the hosting provider's TLS certificate. Do not replace it with `ftp.zebtron.com` or bypass certificate verification.

Run `./upload-selected-ftp.sh --list` first. If the account opens directly in the Zapper web folder, use `--remote-dir /`; otherwise use the default `/zapper`. Preview an upload with `./upload-selected-ftp.sh --dry-run index.html`, then upload with `./upload-selected-ftp.sh index.html`.
