# Shipping Wisp

## Build

```bash
./Scripts/build.sh          # -> build/Wisp.app
./Scripts/package.sh        # -> dist/Wisp-0.1.0.pkg
```

## The signing problem

The pkg in `dist/` is **unsigned**. It installs fine on this Mac, because this Mac
built it. On anyone else's Mac, Gatekeeper refuses it — and the `xattr` call in the
postinstall script does *not* rescue that, because Gatekeeper blocks the package
before any of its scripts run.

Right-click → Open gets a determined user past it. Nobody else will bother.

## Fixing it properly

Needs an Apple Developer Program membership (£79/$99 a year). With one:

```bash
# 1. Identities appear here once the certificates are in your keychain
security find-identity -v -p codesigning

# 2. Sign both the app and the installer
export DEV_ID_APP="Developer ID Application: Your Name (TEAMID)"
export DEV_ID_INSTALLER="Developer ID Installer: Your Name (TEAMID)"
./Scripts/package.sh

# 3. Store an app-specific password once
xcrun notarytool store-credentials wisp \
  --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PASSWORD

# 4. Notarise and staple
xcrun notarytool submit dist/Wisp-0.1.0.pkg --keychain-profile wisp --wait
xcrun stapler staple dist/Wisp-0.1.0.pkg
```

After stapling, the pkg opens with a normal install dialog on any Mac.

## Hosting the download

`public/downloads/Wisp-0.1.0.pkg` in the evandev.blog repo works, but it puts an
8 MB binary into git permanently, and every future version adds another. A GitHub
Release is the better home — upload the pkg there and point the download link at
the release asset instead.

## Version bumps

Three places, and they must agree or the installer misbehaves:

- `Resources/Info.plist` — `CFBundleShortVersionString`, `CFBundleVersion`
- `Scripts/package.sh` — `VERSION`
- `Packaging/distribution.xml` — `pkg-ref version`
