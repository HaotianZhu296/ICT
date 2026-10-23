# ICT · InClass Translator

**English** | [简体中文](README.zh-CN.md)

ICT is a small macOS app that listens to your **microphone** (a lecture, a meeting, a conversation in the room) and/or the **audio your Mac is playing** (videos, online classes, video calls), turns the speech into text, translates it, and shows **floating bilingual subtitles** on top of everything. Every session is saved as a transcript, and you can summarize it with one click or ask the built-in AI assistant "what did they just say?".

It was built for sitting in a lecture with a strong-accented speaker and still following along in your own language.

## Highlights

- **On-device speech recognition**: Apple `SpeechAnalyzer` on macOS 26, `SFSpeechRecognizer` on macOS 14.2–15. Audio never leaves your Mac.
- **Works out of the box**: Google Translate (free web endpoint, no API key) is the default; English → Simplified Chinese by default.
- **Other translators**: Apple Translation (offline, macOS 26), Claude Code, your own API key (OpenAI-compatible or Anthropic), or a local model through Ollama / LM Studio.
- **Low latency**: long run-on sentences are split at the speaker's breaths and translated early, and Google/Apple requests run in parallel. In our tests the first half of a 45-word sentence went from 11.7 s to 0.9 s.
- **Accent correction** (on by default): when recognition confidence drops, a language model fixes misheard words from pronunciation and context (e.g. "Chithon" → Python, "things P" → ThingSpeak). With Google/Apple translation, ICT temporarily switches to Claude Sonnet while correcting.
- **Transcripts and history**: every sentence is written to `~/Documents/ICT/<start time>.md`. The history window lists past sessions and summarizes any of them with one click.
- **AI assistant** beside the subtitles: ask questions about what was just said, or have it save notes to files.
- **Light / dark appearance** (follows the system by default), English and Simplified Chinese UI.

## Requirements

- macOS 14.2 or later (Apple silicon or Intel).

  | Feature | macOS 14.2–15 | macOS 26+ |
  |---|---|---|
  | Speech recognition | `SFSpeechRecognizer` | `SpeechAnalyzer`, lower latency |
  | Apple Translation (offline) and fallback | – | ✓ |
  | Filter nearby Chinese speech | – | ✓ |
  | Accent correction | – (no confidence scores) | ✓ |

- Xcode Command Line Tools to build from source (`xcode-select --install`). The full Xcode is not needed.

## Install

### Download

1. Download `ICT-<version>-macOS.dmg` from the [latest release](https://github.com/HaotianZhu296/ICT/releases/latest). It runs on both Apple silicon and Intel Macs.
2. Open the dmg and drag **ICT** onto the **Applications** folder next to it.
3. ICT isn't notarized by Apple (that needs a paid developer account), so the first launch is blocked with "Apple could not verify…". Click **Done**, open **System Settings › Privacy & Security**, scroll down to "ICT was blocked…" and click **Open Anyway**, then enter your password. After that ICT opens normally.

When you update, replace the app in Applications and click **Open Anyway** once more. Microphone and system-audio permissions are kept.

### Build from source


```bash
git clone https://github.com/HaotianZhu296/ICT.git
cd ICT
scripts/make-signing-cert.sh    # once: creates a local signing certificate "ICT Local Signing"
scripts/build-app.sh --install  # builds, installs to ~/Applications and opens ICT
```

The local certificate keeps the app's identity stable, so macOS doesn't ask for microphone / system-audio permission again after every rebuild. Without it the app is ad-hoc signed and you will be asked again each time.

## First run

1. Open ICT. A subtitle window appears in the top-right corner of the screen (1/16 of the screen area, 3:1).
2. Click **Start Translating** in the middle and allow **Microphone** and/or **System Audio Recording** when macOS asks.
3. The first time a language is used, macOS downloads its speech model (about 10–20 seconds for English).
4. Optional: to use Claude for accent correction, the AI assistant and summaries, install [Claude Code](https://claude.com/claude-code), run `claude` in Terminal and log in once with `/login`.

## Using ICT

ICT has no menu bar or Dock icon; everything is on the subtitle window. Hover over it to show the toolbar. Hovering a button highlights it and shows its name.

| Button | What it does |
|---|---|
| ▶ / ⏸ | Start / stop |
| 📌 | Keep subtitles above all windows (on by default). When off, other windows can cover them; click the subtitles to bring them back to the front |
| 🎙 | Audio source: microphone, system audio, or both |
| 📄 | This session's transcript: notes, SRT/WebVTT export, new session, and the **history** window |
| ✨ | Show / hide the AI assistant |
| ⚙︎ | Settings |
| ✕ | Quit |

- **⌃⌥L** hides or shows the subtitles; opening ICT again from Spotlight also brings them back.
- **Drag** anywhere to move; drag the edges or corners to resize. The window size only changes when you change it, never with the content.
- **Scroll up** on the subtitles to read earlier lines; click "Back to Live" to return.
- **Settings** has a sidebar (Translation, Audio, Subtitles, Transcripts, Advanced). Changes apply immediately so you can see the effect; click **Done** to keep them. If you close the window instead, ICT asks whether to keep them (Done) or restore what you had before (Cancel).
- **Lock** (Settings › Subtitles) makes the subtitles ignore clicks. Hover and click the lock in the top-right corner to unlock.

## Translators

| Tier | What you need | Accent correction, assistant, summaries |
|---|---|---|
| Basic: Google Translate | Nothing (internet required; text is sent to Google) | Through Claude Code if it's installed |
| Basic: Apple Translation | macOS 26 and the language pack (ICT offers to download it) | Through Claude Code if it's installed |
| Cloud | Claude Code, or your own API key | ✓ |
| Local | Ollama or LM Studio running on your Mac | Depends on the model |

Google Translate uses Google's unofficial free web endpoints: no key is needed, but there are no guarantees and Google rate-limits bursts of requests (HTTP 429). ICT uses two endpoints (the `gtx` endpoint and the one Chrome's dictionary extension uses). When one is limited it switches to the other and rests the limited one for a minute. If both fail it waits 1–4 s and tries once more. If that also fails and the Apple language pack is installed, ICT falls back to Apple Translation. At most two sentences are translated at once.

To add your own API or a local model: Settings › Translation › Model Services › **Manage…** → **Add Model Service**. Templates are included for Anthropic, OpenAI, DeepSeek, Qwen (DashScope), Gemini, OpenRouter, Ollama and LM Studio. API keys are stored in the macOS Keychain.

### Privacy

- Speech recognition always runs on your Mac; audio is never uploaded.
- With Google Translate, Claude or your own API, the recognized text is sent to that service.
- With Apple Translation or a local model, everything stays on your Mac.

## How it works

```
Capture ─▶ Recognition ─▶ Segmentation ─▶ Translation ─▶ Display
 mic /       SpeechAnalyzer   sentences,      Google / Apple /   floating
 system      (volatile +      breath-based    Claude / API /     subtitles
 audio       final results)   early commits   local model             │
                                                                       ▼
                                                               Transcript (.md),
                                                               export, summary
```

- **Segmentation** (`Sources/ICTCore/2-Segmentation`): complete sentences are sent immediately; short fragments ("Okay.", "Right?") are merged with their neighbours; long subtitles are split at commas. For run-on speech, `BreathCutter` detects a short dip in volume and `PartialCommitter` commits the words recognized so far, so the first half is translated without waiting for the speaker to stop.
- **Recognition quality** (`Sources/ICTCore/1-Recognition`): the average word confidence decides when accent correction turns on (quickly) and off (only after a minute of clear speech).
- **Translation queue**: Google and Apple translate several sentences at once; language-model sessions go in order with conversation context. A backlog is merged into one request so the delay never keeps growing.

### Project layout

The code is organized by pipeline stage:

```
Sources/ICT/
  App/                    entry point, app delegate, settings model, hotkey
  Pipeline/
    SubtitleController    runs the whole pipeline (start, stop, restart on settings change)
    1-Capture/            microphone, system audio (Core Audio process tap), test audio files
    2-Recognition/        SpeechAnalyzer / SFSpeechRecognizer engines, recognition events
    4-Translation/        Google, Apple, Claude CLI and HTTP API translators, translation queue
    5-Display/            floating subtitle window
    6-Transcript/         transcript files, export, notes, transcript and history windows
  Assistant/              AI assistant session and panel
  Settings/               settings and model-services windows
Sources/ICTCore/          pure logic with unit tests, same stage folders
Tests/ICTCoreTests/       unit tests (Swift Testing)
scripts/                  build, test and packaging scripts
```

### Development

```bash
swift build
scripts/test.sh                          # unit tests (adds the macro plugin path the CLI toolchain needs)
B=.build/debug/ICT
$B --transcribe-file talk.aiff --realtime                # recognition + segmentation
$B --translate "First sentence." "Second one." --engine google
$B --export-test talk.aiff out.srt                       # whole pipeline, then export SRT
$B --render-window out.png --hover                       # offscreen screenshot of the subtitle window
```

`say -o talk.aiff "..."` makes test audio. The command-line toolchain has no SwiftUI macro plugins, so the UI uses small `@Observable` objects instead of `@State`.

## Known limitations

- Builds are signed with a local certificate, not notarized by Apple.
- The Intel build compiles but hasn't been run on an Intel Mac.
- On macOS 14.2–15 recognition is less accurate and subtitle timestamps are estimated.
- With "both" audio sources and speakers (not headphones), the microphone can pick up the system audio again and produce duplicate lines. Microphone noise reduction (echo cancellation) helps.

## Acknowledgments

ICT borrows ideas from these projects:

- [LiveSub](https://github.com/ShuoYang-cs/LiveSub): a macOS live bilingual subtitle app
- [AirTranslate](https://github.com/himomohi/AirTranslate) (Apache-2.0): a SpeechAnalyzer-based macOS caption app
- [LiveCaptions-Translator](https://github.com/SakiRinn/LiveCaptions-Translator) (Apache-2.0): the backup Google endpoint, context handling for machine translation, a latest-wins translation queue
- [whisper_streaming](https://github.com/ufal/whisper_streaming) (MIT): LocalAgreement, committing a stable prefix early
- [WhisperLiveKit](https://github.com/QuentinFuxa/WhisperLiveKit) (Apache-2.0): splitting committed and buffered text
- [WhisperLive](https://github.com/collabora/WhisperLive) (MIT): committing output that stops changing
- [obs-localvocal](https://github.com/royshil/obs-localvocal) (GPL-2.0): rolling caption buffer
- [my-translator](https://github.com/phuc-nt/my-translator) (MIT): prompt design for local translation
- [Easydict](https://github.com/tisfeng/Easydict), [py-googletrans](https://github.com/ssut/py-googletrans), [pot-desktop](https://github.com/pot-app/pot-desktop): handling Google Translate rate limits

It also relies on Apple's Speech and Translation frameworks, Google Translate, and [Claude Code](https://claude.com/claude-code).

ICT is a small personal project shared as-is.
