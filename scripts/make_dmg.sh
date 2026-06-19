#!/usr/bin/env bash
# Builds Macda.app and packages it into a drag-to-install DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/Macda.app"
STAGING="$ROOT/build/dmg"
DMG="$ROOT/build/Macda.dmg"
VOLNAME="Macda"

# Ensure a fresh release build exists.
"$ROOT/scripts/build_app.sh" release

echo "▶︎ Staging DMG contents…"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag-to-install target

cat > "$STAGING/README.txt" <<'EOF'
Macda — your on-device meeting buddy
====================================

INSTALL
  1. Drag "Macda" onto the "Applications" shortcut in this window.

FIRST LAUNCH (important — Macda isn't notarized by Apple)
  If macOS says Macda is "damaged" or "can't be opened", that's just
  Gatekeeper blocking an un-notarized app. To run it, open Terminal and run:

      xattr -cr /Applications/Macda.app && open /Applications/Macda.app

  It opens normally from then on. (Or right-click Macda > Open.)

PERMISSIONS
  On first listen, macOS asks for Microphone (and Screen Recording if you
  capture system audio). Please allow them.

FOR TRANSCRIPTION (recommended: local & free)
  Install whisper.cpp + a model:
      brew install whisper-cpp
      mkdir -p ~/models
      curl -L -o ~/models/ggml-small.bin \
        https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
  (ggml-small.bin is multilingual — handles Hindi + English. ggml-base.en.bin
   is smaller/faster for English only.) Macda auto-detects ~/models/ggml-*.bin.

FOR NOTES & CHAT
  Use Ollama (local, free): https://ollama.com, then `ollama pull llama3.1`.
  Or pick OpenRouter (free models) in Settings. Configure it all in the
  first-run setup, or anytime in Settings.

SHORTCUTS
  Option-Space      start / stop listening
  Option-Cmd-D      open dashboard
  Option-Cmd-S      capture the screen
EOF

echo "▶︎ Creating DMG…"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGING"
SIZE="$(du -h "$DMG" | cut -f1)"
echo "✓ Created $DMG ($SIZE)"
echo "  Install: open the DMG and drag Macda into Applications."
