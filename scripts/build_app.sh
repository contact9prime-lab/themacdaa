#!/usr/bin/env bash
# Builds Macda and assembles a proper macOS .app bundle so TCC permissions
# (Microphone, Screen Recording) can be granted and persist.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/build/Macda.app"

echo "▶︎ Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Macda"
if [[ ! -f "$BIN" ]]; then
  echo "✗ Executable not found at $BIN" >&2
  exit 1
fi

echo "▶︎ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Macda"
cp "$ROOT/bundle/Info.plist" "$APP/Contents/Info.plist"
echo "APPL????" > "$APP/Contents/PkgInfo"

# Prefer the stable "Macda Dev" identity so TCC permissions persist across
# rebuilds. Fall back to ad-hoc if it's missing or not yet authorized.
IDENTITY="Macda Dev"
sign() { codesign --force --deep --sign "$1" --entitlements "$ROOT/bundle/Macda.entitlements" "$APP"; }

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1 && sign "$IDENTITY" 2>/dev/null; then
  echo "✓ Signed with stable identity '$IDENTITY' (TCC permissions will persist)."
else
  echo "▶︎ Stable identity unavailable — ad-hoc signing instead."
  echo "  (Run ./scripts/setup_signing.sh, then authorize codesign, for persistent permissions.)"
  sign -
fi

echo "✓ Built $APP"
echo "  Launch with:  open \"$APP\"   (or ./scripts/run.sh)"
