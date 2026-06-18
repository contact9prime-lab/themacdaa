#!/usr/bin/env bash
# Build the .app bundle and launch it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/build_app.sh" "${1:-release}"
# Relaunch cleanly so permission changes take effect.
pkill -x Macda 2>/dev/null || true
open "$ROOT/build/Macda.app"
echo "✓ Macda launched — look for the face in your menu bar and the mascot on the right edge."
