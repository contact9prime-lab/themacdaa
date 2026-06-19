#!/usr/bin/env bash
# Builds Macda and assembles a proper macOS .app bundle so TCC permissions
# (Microphone, Screen Recording) can be granted and persist.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/build/Macda.app"

# Build a UNIVERSAL binary (arm64 + x86_64) so it runs on Apple Silicon AND
# Intel Macs. Built per-arch then lipo'd (the combined --arch flag hits a
# SwiftPM "duplicate .abi.json" bug).
echo "▶︎ Building universal ($CONFIG)…"
swift build -c "$CONFIG" --arch arm64   --scratch-path "$ROOT/.build-arm" >/dev/null
swift build -c "$CONFIG" --arch x86_64  --scratch-path "$ROOT/.build-x86" >/dev/null
ARM="$(swift build -c "$CONFIG" --arch arm64  --scratch-path "$ROOT/.build-arm" --show-bin-path)/Macda"
X86="$(swift build -c "$CONFIG" --arch x86_64 --scratch-path "$ROOT/.build-x86" --show-bin-path)/Macda"
if [[ ! -f "$ARM" || ! -f "$X86" ]]; then
  echo "✗ Per-arch binaries not found" >&2; exit 1
fi

echo "▶︎ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM" "$X86" -output "$APP/Contents/MacOS/Macda"
echo "  arch: $(lipo -archs "$APP/Contents/MacOS/Macda")"
cp "$ROOT/bundle/Info.plist" "$APP/Contents/Info.plist"
echo "APPL????" > "$APP/Contents/PkgInfo"
[ -f "$ROOT/bundle/Macda.icns" ] && cp "$ROOT/bundle/Macda.icns" "$APP/Contents/Resources/Macda.icns"

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
