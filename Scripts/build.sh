#!/bin/bash
# Builds Wisp.app — an SPM executable wrapped in a proper bundle so macOS can
# attribute Accessibility and Microphone grants to it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Wisp.app"

cd "$ROOT"
echo "==> Compiling ($CONFIG)"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Wisp"
[ -f "$BIN" ] || { echo "!! binary not found at $BIN"; exit 1; }

# The repo may live in an iCloud-synced folder (~/Documents). The file provider
# stamps com.apple.FinderInfo onto anything it manages, and codesign refuses to
# sign that ("resource fork, Finder information, or similar detritus not allowed")
# — and xattr cannot strip it, because the provider puts it straight back. So the
# bundle is assembled and signed outside the synced tree, then copied in.
STAGE_APP="${TMPDIR:-/tmp}wisp-stage/Wisp.app"

echo "==> Assembling bundle"
rm -rf "$STAGE_APP" "$APP"
mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources" "$(dirname "$APP")"
cp "$BIN" "$STAGE_APP/Contents/MacOS/Wisp"
cp "$ROOT/Resources/Info.plist" "$STAGE_APP/Contents/Info.plist"
cp "$ROOT/Resources/Wisp.icns" "$STAGE_APP/Contents/Resources/Wisp.icns"
printf 'APPL????' > "$STAGE_APP/Contents/PkgInfo"
xattr -cr "$STAGE_APP" 2>/dev/null || true

# A stable ad-hoc signature keeps the TCC grants attached across rebuilds.
# Without --identifier, macOS re-prompts for Accessibility on every build.
echo "==> Signing"
codesign --force --deep --sign - \
         --identifier com.evan.wisp \
         --options runtime \
         --entitlements "$ROOT/Resources/Wisp.entitlements" \
         "$STAGE_APP" 2>&1 | sed 's/^/    /'

# The hardened runtime silently blocks the microphone if this is missing, and the
# failure looks exactly like "the permission prompt never appears".
codesign -d --entitlements - "$STAGE_APP" 2>/dev/null | grep -q "audio-input" \
  || { echo "!! audio-input entitlement missing from signature"; exit 1; }

codesign --verify --strict "$STAGE_APP" || { echo "!! signature invalid"; exit 1; }

# --norsrc --noextattr keeps the synced copy free of the attributes we just avoided.
ditto --norsrc --noextattr "$STAGE_APP" "$APP"

echo "==> Built $APP"
