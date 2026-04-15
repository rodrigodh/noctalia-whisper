# Whisper

Voice-activated AI assistant for [Noctalia Shell](https://noctalia.dev). Press a shortcut, speak, and get instant AI responses.

## Features

- **Voice Recording** — Record from your microphone via PipeWire
- **Speech-to-Text** — Transcription powered by Groq Whisper API (free tier)
- **AI Chat** — Streaming responses from Groq, Anthropic Claude, or Google Gemini
- **Conversation History** — Persistent chat with full markdown rendering
- **Keyboard Shortcut Ready** — IPC commands for compositor keybindings
- **Typed Input** — Also supports regular text chat

## Requirements

- Noctalia Shell 4.1.2+
- PipeWire (for audio recording)
- A Groq API key ([free at console.groq.com](https://console.groq.com/keys))

## Setup

1. Install the plugin through Noctalia's plugin manager or manually
2. Go to **Settings > Plugins > Whisper** and enter your Groq API key
3. Add the bar widget in **Settings > Bar**
4. Bind a keyboard shortcut in your compositor:

```bash
qs -c noctalia-shell ipc call plugin:whisper toggle
```

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

## AI Providers

| Provider | Free Tier | Use Case |
|----------|-----------|----------|
| **Groq** (default) | Yes | Handles both STT and LLM with one key |
| **Anthropic Claude** | No (paid) | Higher quality responses |
| **Google Gemini** | Yes | Alternative free option |

## IPC Commands

```bash
# Toggle: open panel + start/stop recording
qs -c noctalia-shell ipc call plugin:whisper toggle

# Open/close panel
qs -c noctalia-shell ipc call plugin:whisper open
qs -c noctalia-shell ipc call plugin:whisper close

# Recording controls
qs -c noctalia-shell ipc call plugin:whisper record
qs -c noctalia-shell ipc call plugin:whisper stop

# Send a text message
qs -c noctalia-shell ipc call plugin:whisper send "What is Wayland?"

# Clear chat history
qs -c noctalia-shell ipc call plugin:whisper clear
```

## Environment Variables

API keys can also be set via environment variables (takes priority over settings):

```bash
export WHISPER_GROQ_API_KEY="gsk_..."
export WHISPER_ANTHROPIC_API_KEY="sk-ant-..."
export WHISPER_GOOGLE_API_KEY="AI..."
```

## License

MIT
