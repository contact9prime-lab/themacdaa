# Macda 🐣

A tiny desk companion for macOS. Macda is a customizable little character that
lives on the **right edge of your screen** and in your **menu bar**. During calls
it listens, transcribes locally, turns the conversation into **notes**, **to-dos**,
and **summaries**, recognizes **who's speaking** by voiceprint, and lets you
**chat with an agent** over all of your local data.

> Native Swift (SwiftUI + AppKit). System audio via ScreenCaptureKit, microphone
> via AVAudioEngine, local transcription via whisper.cpp, and your own LLM
> (Ollama by default) for notes & chat. Local-first and private.

---

## Features

- 🎙 **Listens to your calls** — captures **your mic + everyone else** (system
  audio via ScreenCaptureKit), mixed time-aligned at 16kHz. Resilient: if one
  source goes silent (e.g. a dead mic) the other still flows.
- 🎚 **Pick your microphone** — choose any input device with a **live level
  meter**, not just the system default.
- ✂️ **Batched, parallel transcription** — audio is cut on natural silence gaps
  and transcribed concurrently. A spinning badge shows it working in the
  background.
- 🤫 **Knows when it's quiet** — voice-activity detection auto-stops after a
  configurable silence timeout.
- 👂 **Auto-listen** — optionally start recording automatically the moment it
  hears sustained speech (toggle in Settings or the mascot's right-click menu).
- 📝 **Sorts your life** — complete notes, action **to-dos** (with due dates),
  and a summary extracted by your LLM after each call.
- 🗣 **Who said what — voiceprints** — each chunk gets an acoustic fingerprint.
  Speakers are matched to known **People**; a new voice is surfaced for tagging,
  and **tagging it enrolls the voiceprint** so the same person is auto-recognized
  next time.
- 💬 **Chat with your data** — an on-device agent that searches and edits your
  notes / to-dos / meetings via tools (transparent, on-device with Ollama).
- 🗓 **Meeting aware** — register a call (title / attendees / tags) for better
  context; browse past meetings with the **full transcript** and detected
  speakers.
- 🎭 **Customizable mascot** — size, color, show/hide. Blinks, breathes, perks
  its ears up while listening, reacts to your voice level.
- 💾 **Local storage with limits** — everything in a folder you can see/change;
  recordings pruned by age **and** a max-size cap (oldest first).
- ⌨️ **Global shortcuts** + a **right-click quick menu** on the mascot.
- 🔌 **Bring your own models** — transcription: whisper.cpp (recommended),
  OpenAI Whisper, Gemini, or experimental Ollama-audio; notes/chat: Ollama,
  OpenAI, or Gemini — with a **model picker fetched from your Ollama server**.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| **⌥ Space** | Start / stop listening |
| **⌥ ⌘ D** | Open the dashboard |
| **⌥ ⌘ N** | Quick note |

Right-click the mascot for quick controls (listen, auto-listen, size, color,
hide, and dashboard tabs).

## Build & run

```bash
# One-time: create a stable signing identity so macOS permissions persist
./scripts/setup_signing.sh
# Then authorize codesign to use it (asks for your login password once):
security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db

# Build the .app bundle and launch it
./scripts/run.sh

# …or just build (release) without launching
./scripts/build_app.sh

# Dev iteration without bundling
swift run
```

The app builds into `build/Macda.app`. It's a menu-bar agent — **no Dock icon**;
look for the face in your menu bar and the mascot on the right edge.

### Why the stable signing step?

macOS ties permissions (Microphone, Screen Recording) to an app's code
signature. Ad-hoc signatures change every rebuild, so macOS would forget the
permission each time. `setup_signing.sh` creates a self-signed "Macda Dev"
identity; signing with it keeps a stable identity so your grants persist.

### Permissions (macOS prompts on first use)

- **Microphone** — to hear your voice (and for auto-listen).
- **Screen Recording** — required by ScreenCaptureKit to capture *system audio*
  (the other people on the call). Turn off "Capture system audio" in Settings if
  you only want your mic.

## Local setup (recommended, fully private)

**Transcription — whisper.cpp** (auto-detected if installed):

```bash
brew install whisper-cpp
mkdir -p ~/models && curl -L -o ~/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

Macda auto-detects `whisper-cli` and a model in `~/models`. whisper.cpp is the
**recommended** transcriber — it's fast, local, and accurate.

**Notes & chat — Ollama:**

```bash
ollama pull gemma4:12b      # or llama3.1 / qwen2.5 / mistral
# On a remote machine, serve it on the network:
OLLAMA_HOST=0.0.0.0 ollama serve
```

Settings → Notes → pick your model from the dropdown (fetched from your server).
Set the Ollama URL to `http://<machine>:11434` for a remote box.

> ⚠️ A general LLM (gemma4) is great for **notes** but unreliable for
> **transcription** — it tends to summarize/rephrase audio instead of
> transcribing verbatim. Use whisper.cpp for transcripts.

## Cloud setup (optional)

Settings → Cloud keys → paste an OpenAI or Gemini key, then choose that provider
for transcription and/or notes. Audio is only sent to a cloud service when you
explicitly select it.

## How it works

```
 mic (AVAudioEngine) ─┐
                      ├─► TimelineMixer (16kHz mono, additive, stall-tolerant)
 system (ScreenKit) ──┘            │
                                   ├─ level ─► mascot animation
                                   ├─ VAD: cut on pause / cap, auto-stop on silence
                                   ▼
                       per chunk ──► VoiceEmbedder (acoustic fingerprint)
                                   ▼
              TranscriptionPipeline ──(parallel)──► whisper.cpp / OpenAI / Gemini / Ollama-audio
                                   ▼
                 TranscriptBuffer ──► NoteExtractor (Ollama / OpenAI / Gemini)
                                   │
        VoiceMatcher (speakers) ◄──┤
                                   ▼
   summary + notes + to-dos + speakers ──► Store (JSON + retained WAVs)
                                   ▲
                        AgentEngine (chat tools over the same local data)
```

## Project layout

```
Sources/Macda/
  App/            entry point, AppDelegate, AppState (the brain)
  Audio/          capture engine, system audio, mixer, devices, VAD, voiceprints, auto-listen
  Transcription/  pipeline + whisper.cpp / OpenAI / Gemini / Ollama-audio, cleaning
  LLM/            provider protocol + Ollama/OpenAI/Gemini, NoteExtractor, model list, conn test
  Chat/           ChatModels + AgentEngine (tool loop over local data)
  Model/          Meeting / Note / Todo / Person, Settings (tolerant + on-disk), Store
  UI/             mascot window + view, menu bar, hotkeys, dashboard tabs, color helpers
  Util/           networking, process runner, async semaphore
bundle/           Info.plist + entitlements for the .app
scripts/          setup_signing.sh, build_app.sh, run.sh
```

## Data & privacy

- All data lives in `~/Library/Application Support/Macda/` (notes, meetings,
  people, chat, `settings.json`, and `recordings/`). Change the folder in
  Settings → Storage.
- Recordings are retained for a configurable number of days and capped by a max
  size; oldest are pruned first.
- With whisper.cpp + Ollama, **nothing leaves your Mac** (or your LAN/VPN for a
  remote Ollama).

## Notes & limits

- Voiceprints are a best-effort acoustic similarity fingerprint (mel-spectrogram
  embedding), not a biometric — good for telling a handful of voices apart.
- Cloud API keys are stored in `UserDefaults`/`settings.json` for simplicity —
  move them to the Keychain before shipping for real.
