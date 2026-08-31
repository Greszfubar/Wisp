#!/bin/bash
# Builds Wisp-<version>.pkg — a signed-if-possible, installable macOS package.
#
# Signing: set DEV_ID_APP / DEV_ID_INSTALLER to Developer ID identities to produce
# a distributable package. Without them the pkg still installs, but only on Macs
# where the user right-clicks to bypass Gatekeeper. See README-DISTRIBUTION.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.1.0"
OUT="$ROOT/dist"
# Staged outside the repo for the same iCloud/FinderInfo reason as build.sh.
STAGE="${TMPDIR:-/tmp}wisp-pkgroot"

cd "$ROOT"

echo "==> Building app"
./Scripts/build.sh release >/dev/null
[ -d "$ROOT/build/Wisp.app" ] || { echo "!! Wisp.app missing"; exit 1; }

if [ -n "${DEV_ID_APP:-}" ]; then
  echo "==> Re-signing app with Developer ID"
  codesign --force --deep --options runtime --timestamp \
           --sign "$DEV_ID_APP" "$ROOT/build/Wisp.app"
fi

echo "==> Staging"
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE/Applications" "$OUT"
ditto --norsrc --noextattr "$ROOT/build/Wisp.app" "$STAGE/Applications/Wisp.app"

echo "==> Component package"
# --component-plist pins BundleIsRelocatable=false: without it the installer will
# happily overwrite some other Wisp.app it finds on disk instead of /Applications.
pkgbuild --root "$STAGE" \
         --identifier com.evan.wisp \
         --version "$VERSION" \
         --scripts "$ROOT/Packaging/scripts" \
         --component-plist "$ROOT/Packaging/component.plist" \
         --install-location / \
         "$OUT/Wisp-component.pkg" >/dev/null

echo "==> Product archive"
PRODUCT_ARGS=(
  --distribution "$ROOT/Packaging/distribution.xml"
  --resources    "$ROOT/Packaging/resources"
  --package-path "$OUT"
)
if [ -n "${DEV_ID_INSTALLER:-}" ]; then
  PRODUCT_ARGS+=(--sign "$DEV_ID_INSTALLER" --timestamp)
  echo "    signing installer as $DEV_ID_INSTALLER"
else
  echo "    UNSIGNED — fine for you, blocked by Gatekeeper for everyone else"
fi
productbuild "${PRODUCT_ARGS[@]}" "$OUT/Wisp-$VERSION.pkg" >/dev/null

rm -f "$OUT/Wisp-component.pkg"
rm -rf "$STAGE"

echo "==> Built $OUT/Wisp-$VERSION.pkg ($(du -h "$OUT/Wisp-$VERSION.pkg" | cut -f1))"
if [ -n "${DEV_ID_INSTALLER:-}" ]; then
  echo "    Next: xcrun notarytool submit \"$OUT/Wisp-$VERSION.pkg\" --keychain-profile wisp --wait"
  echo "          xcrun stapler staple \"$OUT/Wisp-$VERSION.pkg\""
fi
