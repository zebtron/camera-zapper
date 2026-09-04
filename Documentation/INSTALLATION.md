# Installing Zebtron Camera Zapper

## Requirements

- macOS 14 or later on Apple silicon or Intel
- Temporary disk space for the media being ingested
- For Android: a data-capable USB cable and Android Platform Tools (`adb`)
- Optional configured destinations: mounted NAS, Photos, Google Photos, Flickr, YouTube, and NeoFinder

## Install from the DMG

1. Open `Zebtron-Camera-Zapper-1.348.dmg`.
2. Drag **Zebtron Camera Zapper** into **Applications**.
3. Control-click the app and choose **Open** the first time.
4. Approve requested Photos, removable-media, folder, and automation permissions.

This testing build is ad-hoc signed. A public release will be Developer ID signed and notarized.

## Android setup

1. Open **Settings → About tablet/phone → Software information**.
2. Tap **Build number** seven times and enter the device PIN.
3. Open **Settings → Developer options** and enable **USB debugging**.
4. Connect a data-capable cable and choose **Transferring files / Android Auto**.
5. Accept **Allow USB debugging?** and select **Always allow from this computer**.
6. In Camera Zapper, choose **Probe Again** if needed.

Install ADB with `brew install android-platform-tools` if it is missing.

ADB is not bundled. Camera Zapper displays installation guidance when it cannot find Android Platform Tools. ADB is used for device detection, media listing, on-device SHA-256 hashing, transfer, and confirmed source deletion.

## First-run configuration

1. Open **Services & Priority**.
2. Configure the local staging directory and mounted NAS destination.
3. Authorize each desired cloud service.
4. Drag services into execution order.
5. Mark only destinations that truly must succeed before deletion.
6. Leave automatic deletion disabled until several manual runs have been checked.

New installs start with only a local archive at `~/Pictures/Camera Zapper/Archive`. NAS and cloud services are disabled. `/Volumes/NAS`, `your-nas.local`, and `Media` are examples—not a configured server. Clear the first-run warning only after every enabled file destination is present and writable.

Do not store OAuth JSON or service secrets in the app bundle or shared source archive. Camera Zapper imports credentials into Keychain.
