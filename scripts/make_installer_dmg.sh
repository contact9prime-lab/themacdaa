#!/usr/bin/env bash
# Builds Macda.app and packages a guided-installer DMG: the app + a
# "Setup Macda.command" that installs it and checks/sets up dependencies.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/Macda.app"
STAGING="$ROOT/build/installer-dmg"
DMG="$ROOT/build/Macda-Installer.dmg"
VOLNAME="Macda Installer"

"$ROOT/scripts/build_app.sh" release

echo "▶︎ Staging installer DMG…"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
cp "$ROOT/installer/Setup Macda.command" "$STAGING/"
chmod +x "$STAGING/Setup Macda.command"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/READ ME FIRST.txt" <<'EOF'
Macda — Installation

Recommended: double-click "Setup Macda.command". It installs Macda and checks /
sets up what it needs (whisper.cpp + model for transcription, Ollama for notes).
  • If macOS blocks it: right-click the file → Open → Open.

Manual: drag Macda onto the Applications shortcut. Then install whisper.cpp
(brew install whisper-cpp), a model in ~/models, and Ollama (or point Macda at a
remote Ollama in Settings).

On first listen, macOS asks for Microphone (and Screen Recording for system
audio) — please allow them.
EOF

echo "▶︎ Creating DMG…"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

SIZE="$(du -h "$DMG" | cut -f1)"
echo "✓ Created $DMG ($SIZE)"
