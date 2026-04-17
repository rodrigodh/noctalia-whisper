# Whisper

Live voice-activated AI assistant for [Noctalia Shell](https://noctalia.dev). Talk; it listens, detects when you stop, transcribes, and answers — no buttons, no submit. Built for interviews, meetings, and always-on voice workflows.

![preview](preview.png)

## Features

- **Live mode (default)** — Continuous listening. When you pause, the assistant answers automatically.
- **Push-to-talk fallback** — Manual one-shot recording when you want explicit control.
- **Speech-to-Text** — Groq Whisper API (free tier).
- **Streaming LLM** — Groq (default, free), Anthropic Claude, or Google Gemini.
- **Persistent chat** — Markdown-rendered history, kept across sessions.
- **Keyboard-shortcut driven** — Bind one key; no UI fiddling during use.
- **Text input** — Type at any time, even while Live is listening.

## Requirements

- Noctalia Shell 4.1.2+
- PipeWire (with the `pipewire-pulse` compatibility layer, which is standard)
- `ffmpeg` on `$PATH` — used for the live audio pipeline
- A Groq API key ([free at console.groq.com](https://console.groq.com/keys))

Optional: `pw-record` for the legacy push-to-talk mode (usually comes with PipeWire).

## Setup

1. Install the plugin through Noctalia's plugin manager or manually.
2. Go to **Settings > Plugins > Whisper** and enter your Groq API key.
3. Add the bar widget in **Settings > Bar**.
4. Bind a keyboard shortcut in your compositor:

```bash
qs -c noctalia-shell ipc call plugin:whisper toggle
```

Press the shortcut → panel opens, Live mode starts. Talk → pause ~1 s → answer streams in. Press again to stop.

### Compositor examples

**Niri:**
```kdl
binds {
    Mod+Shift+W { spawn "sh" "-c" "qs -c noctalia-shell ipc call plugin:whisper toggle"; }
}
```

**Hyprland:**
```ini
bind = SUPER SHIFT, W, exec, qs -c noctalia-shell ipc call plugin:whisper toggle
```

**Sway:**
```
bindsym $mod+Shift+w exec qs -c noctalia-shell ipc call plugin:whisper toggle
```

## Tuning Live mode

Live mode uses **Voice Activity Detection** (silence threshold + pause duration) to decide when you've finished speaking. If it feels wrong, three sliders in **Settings > Plugins > Whisper > Live Mode** control it:

| Setting | Default | What it does | When to change |
| --- | --- | --- | --- |
| Silence threshold | -18 dB | Audio quieter than this counts as silence. | Laptop mic w/ high noise floor: move toward 0 (e.g. -15). Quiet room + good mic: move toward -30. |
| Pause duration | 1.0 s | How long to stay silent before the assistant answers. | Too slow: lower to 0.7 s. Cuts you off: raise to 1.5 s. |
| Min speech length | 0.5 s | Ignore speech bursts shorter than this. | Filters coughs, clicks, short "uhh". Rarely needs changing. |

**If the assistant never answers**, the threshold is too low (silence is never detected). Check logs — you should see `VAD: silence_end @ N.NNs` and `VAD: silence_start @ N.NNs` events when you talk and pause.

**If the assistant answers mid-sentence**, raise Pause duration. If it answers with nonsense / a lone "." it transcribed noise — raise Min speech length or Silence threshold.

## AI Providers

| Provider | Free Tier | Use Case |
| --- | --- | --- |
| **Groq** (default) | Yes | Handles both STT and LLM with one key. Fastest first-token. |
| **Anthropic Claude** | No | Higher-quality answers when quality beats latency. |
| **Google Gemini** | Yes | Alternative free option. |

## IPC commands

```bash
# Primary: open panel + toggle Live (or PTT if Live is disabled in Settings)
qs -c noctalia-shell ipc call plugin:whisper toggle

# Panel controls
qs -c noctalia-shell ipc call plugin:whisper open
qs -c noctalia-shell ipc call plugin:whisper close

# Explicit Live toggle (independent of the `liveMode` setting)
qs -c noctalia-shell ipc call plugin:whisper live

# One-shot push-to-talk
qs -c noctalia-shell ipc call plugin:whisper record
qs -c noctalia-shell ipc call plugin:whisper stop

# Send a typed message
qs -c noctalia-shell ipc call plugin:whisper send "What is Wayland?"

# Clear chat history
qs -c noctalia-shell ipc call plugin:whisper clear
```

## Environment variables

API keys can also be set via env vars (takes priority over Settings):

```bash
export WHISPER_GROQ_API_KEY="gsk_..."
export WHISPER_ANTHROPIC_API_KEY="sk-ant-..."
export WHISPER_GOOGLE_API_KEY="AI..."
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Panel shows `!!panel.title!!` literals | i18n load failure in Noctalia | Check `i18n/en.json` is present in the installed plugin dir; the plugin has a fallback helper so most strings still read normally. |
| Live starts but nothing happens when I pause | Silence threshold too low for your mic | Raise toward 0 dB in Settings. Check logs for `VAD: silence_...` events. |
| Assistant answers with just `.` | Noise transcribed as near-silence by Whisper | Raise Silence threshold or increase Min speech length. |
| `Audio file is too short` in logs | A very short burst slipped through as a chunk | Raise Min speech length to 0.7 s. |

## Architecture

For the design of the live pipeline, state machine, and IPC contract, see [ARCHITECTURE.md](ARCHITECTURE.md).

## License

MIT
