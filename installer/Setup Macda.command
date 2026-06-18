#!/bin/bash
# Macda guided installer. Installs the app and checks/sets up its dependencies
# (whisper.cpp + model for transcription, Ollama for notes/chat) interactively.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$DIR/Macda.app"
APP_DEST="/Applications/Macda.app"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }
ask()  { read -r -p "  $1 " REPLY; }

clear
bold "==============================================="
bold "        Macda — Guided Installer"
bold "==============================================="
echo "This will install Macda and check what it needs."
echo

# 1) Install the app -----------------------------------------------------------
bold "1) Installing the app"
if [ -d "$APP_SRC" ]; then
  rm -rf "$APP_DEST"
  cp -R "$APP_SRC" "$APP_DEST"
  xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
  ok "Macda installed to /Applications"
else
  warn "Macda.app not found next to this script."
  warn "Run this from the mounted Macda disk image."
fi
echo

# 2) Homebrew ------------------------------------------------------------------
bold "2) Homebrew (needed to install whisper.cpp)"
if command -v brew >/dev/null 2>&1; then
  BREW="$(command -v brew)"; ok "Homebrew found"
elif [ -x /opt/homebrew/bin/brew ]; then
  BREW="/opt/homebrew/bin/brew"; ok "Homebrew found"
else
  warn "Homebrew not installed."
  ask "Install Homebrew now? [y/N]"
  if [[ "$REPLY" =~ ^[Yy] ]]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  BREW="$(command -v brew || echo /opt/homebrew/bin/brew)"
fi
echo

# 3) whisper.cpp (recommended transcription engine) ----------------------------
bold "3) whisper.cpp (local transcription — recommended)"
if command -v whisper-cli >/dev/null 2>&1 || [ -x /opt/homebrew/bin/whisper-cli ] || [ -x /usr/local/bin/whisper-cli ]; then
  ok "whisper.cpp found"
else
  warn "whisper.cpp not installed."
  ask "Install whisper.cpp now? [Y/n]"
  if [[ ! "$REPLY" =~ ^[Nn] ]] && [ -x "$BREW" ]; then
    "$BREW" install whisper-cpp || warn "Install failed — you can run: brew install whisper-cpp"
  fi
fi
echo

# 4) whisper model -------------------------------------------------------------
bold "4) whisper model"
MODEL="$HOME/models/ggml-base.en.bin"
if ls "$HOME"/models/ggml-*.bin >/dev/null 2>&1; then
  ok "A whisper model is already present in ~/models"
else
  warn "No whisper model found."
  ask "Download base.en model (~142MB)? [Y/n]"
  if [[ ! "$REPLY" =~ ^[Nn] ]]; then
    mkdir -p "$HOME/models"
    curl -L --fail -o "$MODEL" \
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin" \
      && ok "Model downloaded to $MODEL" || warn "Download failed — see README for the link."
  fi
fi
echo

# 5) Ollama (notes & chat) -----------------------------------------------------
bold "5) Ollama (for notes, summaries & chat)"
if command -v ollama >/dev/null 2>&1; then
  ok "Ollama found"
  if curl -s --max-time 4 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    ok "Ollama is running locally"
    echo "     Pull a model if you haven't:  ollama pull gemma4:12b"
  else
    warn "Ollama installed but not reachable locally."
    echo "     Start it (ollama serve) or point Macda at a remote Ollama in Settings."
  fi
else
  warn "Ollama not installed (notes & chat need an LLM)."
  echo "     Install from https://ollama.com, OR set a remote Ollama URL in"
  echo "     Macda → Settings → Notes (e.g. http://<machine>:11434)."
fi
echo

# 6) Launch --------------------------------------------------------------------
bold "Done!"
echo "Macda is a menu-bar app: look for the face in the menu bar and the mascot"
echo "on the right edge. macOS will ask for Microphone (and Screen Recording for"
echo "system audio) the first time you start listening — please allow them."
echo
ask "Launch Macda now? [Y/n]"
if [[ ! "$REPLY" =~ ^[Nn] ]]; then
  open "$APP_DEST" 2>/dev/null || open "$APP_SRC"
fi
echo "You can close this window."
