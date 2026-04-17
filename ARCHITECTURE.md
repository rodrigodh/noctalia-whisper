# Architecture

This document describes how the Whisper plugin is put together so future edits can be made safely. It's terse on purpose — read the code for exact behavior.

## Components

```
manifest.json        Plugin metadata + default settings
i18n/en.json         Translation strings; loader falls back to inline English on miss
Main.qml             Headless state machine (recording, VAD, transcription, LLM, IPC)
Panel.qml            Main UI (header, status strip, chat log, input)
BarWidget.qml        Status pill in the Noctalia bar
Settings.qml         In-app settings form
MessageBubble.qml    A single chat message renderer
WhisperLogic.js      Pure-JS helpers (`.pragma library`) — commands + parsers + state save/load
```

Everything user-visible lives in Panel/BarWidget/Settings. All state and process orchestration lives in Main. `WhisperLogic.js` is side-effect-free: it builds command arrays, parses streaming responses, and does the `!!key!!` fallback for i18n.

## Live mode pipeline

The primary experience. One long-running `ffmpeg` process does two jobs:

```
pulse ──▶ ffmpeg (records + silencedetect)
           │
           ├── stdout: /tmp/whisper-live-<ts>.wav    (the session WAV, grows for the whole session)
           │
           └── stderr: [silencedetect] silence_start: T / silence_end: T  (parsed by SplitParser)
```

Command shape (from `Logic.buildLivePipelineCommand`):

```
ffmpeg -hide_banner -loglevel info -y \
       -f pulse -i default \
       -ar 16000 -ac 1 \
       -af silencedetect=noise=<db>dB:d=<sec> \
       /tmp/whisper-live-<ts>.wav
```

Using one process instead of two means `silencedetect`'s timestamps are pts-based and align exactly with byte offsets in the output WAV — a chunk `[startSec, endSec]` can be extracted later without timing drift.

### Silence events → speech chunks

`silencedetect` emits two event types:
- `silence_start: T` — silence began at `T` (i.e. user just stopped talking)
- `silence_end: T` — silence ended at `T` (i.e. user just started talking)

State machine (in `Main.qml::handleSilenceEvent`):

```
initial state: lastSilenceEndTime = -1
on silence_end(T):   lastSilenceEndTime = T           # speech starts
on silence_start(T): if lastSilenceEndTime >= 0:
                         queue chunk [lastSilenceEndTime, T]
                         lastSilenceEndTime = -1
                     # initial silence_start at t≈0 is ignored because no speech preceded it
```

A queued chunk is dropped if its duration is less than `vadMinSpeechSec` (filters coughs, clicks, inhales).

### Chunk → transcription → LLM

When a chunk enters the queue, `processNextChunk()` fires. It runs strictly sequentially — gated by `isChunkPipelineBusy` plus a guard against concurrent `isTranscribing / isRecording / isGenerating`. This means:

- Only one chunk is in flight at a time.
- A user-typed message during Live mode consumes one generation slot; chunk processing resumes after that generation finishes.

Per chunk:

```
1. Extract   ffmpeg -ignore_length 1 -ss S -to E -i session.wav chunk.wav
2. Transcribe  curl ... api.groq.com/v1/audio/transcriptions → JSON { text: "..." }
3. Send       addMessage("user", text) then stream to the selected LLM
4. On LLM exit  afterLlmDone() releases the queue lock and recurses
```

`-ignore_length 1` tolerates the growing (unfinalized) WAV header on the live session file.

### Serialization and failure paths

The one gotcha is keeping `isChunkPipelineBusy` consistent. Every exit from the pipeline — success, parse error, empty transcript, missing API key, LLM error, user-hit-stop, user-typed-while-busy — must release the lock. Grep for `isChunkPipelineBusy = false` in `Main.qml` to see each of these sites. `afterLlmDone()` is the end-of-run hook every LLM `onExited` handler calls.

## Push-to-talk fallback

Kept for users who don't want an always-on mic. Uses `pw-record` directly (no VAD, no ffmpeg):

```
pw-record → /tmp/whisper-recording-<ts>.wav
  │
  └── on process exit → transcribe → send
```

`startRecording()` and `startLive()` are mutually exclusive — either can preempt the other.

## IPC surface

All commands target `plugin:whisper`. Invoke with `qs -c noctalia-shell ipc call plugin:whisper <cmd>`.

| Command | Effect |
| --- | --- |
| `toggle` | Open panel + start/stop the primary mode (Live if `liveMode` setting is on, otherwise PTT). |
| `live` | Explicitly toggle Live mode regardless of settings. |
| `record` | Explicitly start PTT. |
| `stop` | Stop whichever capture is active. |
| `open` / `close` | Panel visibility. `close` also cancels any in-flight capture. |
| `send <message>` | Inject a user message as if typed. |
| `clear` | Wipe chat history. |

## State persistence

Chat history and input draft are saved to `$XDG_CACHE_HOME/noctalia/plugins/whisper/state.json` (debounced, 500 ms). `maxHistoryLength` setting caps what's written to disk. In-memory history is currently unbounded within a session — something to revisit if context/cost become a problem in long interviews.

API keys and settings live in Noctalia's plugin settings (`~/.config/noctalia/plugins/whisper/settings.json`).

## i18n fallback

Noctalia's `pluginApi.tr()` returns the literal `!!key!!` when a translation isn't found. Every QML file uses a small helper:

```qml
function t(key, fallback) {
  return Logic.cleanTr(pluginApi ? pluginApi.tr(key) : null, fallback);
}
```

`Logic.cleanTr` collapses the `!!...!!` sentinel to the supplied fallback. Adding a new UI string? Call `root.t("my.key", "English fallback")` and add the key to `i18n/en.json`. If the loader drops the key for any reason, the English fallback renders instead of garbled text.

## Known limitations

- **VAD threshold is mic-dependent.** Default -18 dB targets laptop mics; external/condenser mics want -25 to -30 dB. Exposed as a setting.
- **Whisper hallucinates on silent chunks.** Sometimes returns a lone `.` or `you` when the chunk contains only low-level noise. Mitigation: raise Min speech length. Long-term: post-filter extremely short transcripts.
- **No barge-in.** The LLM can't be interrupted by your next question while it's still streaming; the new chunk queues.
- **No TTS.** Answers are shown on screen; nothing is spoken back.
- **One shell, one mic.** Live mode reads `-f pulse -i default`; no device picker yet.

## Extending

- **New LLM provider**: add a block to `LlmProviderConfig` in `WhisperLogic.js`, write `buildXCommand` + `parseXStream`, add a `Process { id: xProcess }` + `sendXRequest()` in `Main.qml` mirroring Groq/Anthropic/Gemini, and add `"x"` to the dispatcher in `sendMessage`.
- **New language**: drop `i18n/<lang>.json` next to `en.json`. The loader still needs investigation — see the `!!key!!` fix above.
- **New VAD engine**: the seam is `buildLivePipelineCommand` + `parseSilenceEvent` + `handleSilenceEvent`. Keep the "silence_start = end of burst, queue chunk" contract and the rest of the pipeline is unchanged.
