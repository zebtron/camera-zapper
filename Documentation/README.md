# Camera Zapper Documentation Index

## App documentation

- `INSTALLATION.md` - macOS installation, permissions, Android/ADB setup, and first-run configuration.
- `USER_MANUAL.md` - complete current-app workflow, services, formats, privacy, recovery, deletion safety, and troubleshooting.
- `Zebtron-Camera-Zapper-1.346-User-Manual.pdf` - formatted distributable edition of the current manual.
- `DEVELOPER_HANDOFF.md` - architecture, safety invariants, repository map, build steps, and public-release requirements.
- `Screenshots/camera-zapper-finished-app.png` - real finished-app dashboard capture for documentation.

## Website documentation

- `WEBSITE_BRANDING_AND_CONTENT.md` - authoritative brand identity, product positioning, site copy, page order, feature language, format summary, privacy wording, accessibility, and asset directions.
- The editable website implementation is in the sibling `Website-Source/` directory of the packaged handoff.
- Website assets are in `Website-Source/public/`, including the application icon and real app screenshot.

Another LLM working on the website should read `WEBSITE_BRANDING_AND_CONTENT.md`, then `USER_MANUAL.md`, then inspect `Website-Source/app/page.tsx` and `Website-Source/app/globals.css`. The current manual overrides older mockup-era claims. Do not claim Apple notarization, automatic updates, or future Pro destinations until those features ship.
