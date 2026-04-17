.pragma library

// ===================================
// i18n fallback helper
// ===================================
// Noctalia's pluginApi.tr() returns "!!key!!" when the key is missing.
// Wrap lookups so the caller's fallback is used in that case.
function cleanTr(trValue, fallback) {
  if (trValue && typeof trValue === "string" && trValue.length > 0
      && !(trValue.length >= 4 && trValue.substring(0, 2) === "!!"
           && trValue.substring(trValue.length - 2) === "!!")) {
    return trValue;
  }
  return fallback;
}

// ===================================
// Provider Constants
// ===================================

var LlmProviders = {
  GROQ: "groq",
  ANTHROPIC: "anthropic",
  GOOGLE: "google"
};

var SttProviders = {
  GROQ: "groq"
};

var LlmProviderConfig = {
  groq: {
    name: "Groq",
    defaultModel: "llama-3.3-70b-versatile",
    endpoint: "https://api.groq.com/openai/v1/chat/completions",
    keyUrl: "https://console.groq.com/keys"
  },
  anthropic: {
    name: "Anthropic Claude",
    defaultModel: "claude-sonnet-4-20250514",
    endpoint: "https://api.anthropic.com/v1/messages",
    keyUrl: "https://console.anthropic.com/settings/keys"
  },
  google: {
    name: "Google Gemini",
    defaultModel: "gemini-2.5-flash",
    streamEndpoint: "https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse&key={apiKey}",
    keyUrl: "https://aistudio.google.com/app/apikey"
  }
};

// ===================================
// Speech-to-Text: Groq Whisper
// ===================================

function buildWhisperCommand(audioFilePath, apiKey, language) {
  var args = [
    "curl", "-s", "-X", "POST",
    "https://api.groq.com/openai/v1/audio/transcriptions",
    "-H", "Authorization: Bearer " + apiKey,
    "-F", "file=@" + audioFilePath,
    "-F", "model=whisper-large-v3-turbo",
    "-F", "response_format=json"
  ];

  if (language && language !== "auto") {
    args.push("-F", "language=" + language);
  }

  return { args: args };
}

function parseWhisperResponse(responseText) {
  if (!responseText || responseText.trim() === "") {
    return { error: "Empty response from Whisper API" };
  }

  try {
    var json = JSON.parse(responseText);
    if (json.error) {
      return { error: json.error.message || JSON.stringify(json.error) };
    }
    if (json.text !== undefined) {
      return { text: json.text };
    }
    return { error: "Unexpected Whisper response format" };
  } catch (e) {
    return { error: "Failed to parse Whisper response: " + e };
  }
}

// ===================================
// LLM: Groq (OpenAI-compatible)
// ===================================

function buildGroqLlmCommand(apiKey, model, systemPrompt, history, temperature) {
  var messages = [];

  if (systemPrompt && systemPrompt.trim() !== "") {
    messages.push({ role: "system", content: systemPrompt });
  }

  for (var i = 0; i < history.length; i++) {
    messages.push(history[i]);
  }

  var payload = {
    model: model || LlmProviderConfig.groq.defaultModel,
    messages: messages,
    temperature: temperature,
    stream: true
  };

  var args = [
    "curl", "-s", "-S", "--no-buffer", "-X", "POST",
    "-H", "Content-Type: application/json",
    "-H", "Authorization: Bearer " + apiKey,
    "-d", JSON.stringify(payload),
    LlmProviderConfig.groq.endpoint
  ];

  return { args: args, url: LlmProviderConfig.groq.endpoint };
}

function parseOpenAIStream(data) {
  if (!data) return null;
  var line = data.trim();
  if (line === "") return null;

  if (line.startsWith("data: ")) {
    var jsonStr = line.substring(6).trim();
    if (jsonStr === "[DONE]") return { done: true };

    try {
      var json = JSON.parse(jsonStr);
      if (json.choices && json.choices[0]) {
        if (json.choices[0].delta && json.choices[0].delta.content) {
          return { content: json.choices[0].delta.content };
        } else if (json.choices[0].message && json.choices[0].message.content) {
          return { content: json.choices[0].message.content };
        }
      }
    } catch (e) {
      return { error: "Error parsing SSE: " + e };
    }
  } else {
    return { raw: line };
  }
  return null;
}

// ===================================
// LLM: Anthropic Claude
// ===================================

function buildAnthropicCommand(apiKey, model, systemPrompt, history, temperature) {
  var messages = [];

  for (var i = 0; i < history.length; i++) {
    messages.push(history[i]);
  }

  var payload = {
    model: model || LlmProviderConfig.anthropic.defaultModel,
    max_tokens: 2048,
    stream: true,
    messages: messages
  };

  if (systemPrompt && systemPrompt.trim() !== "") {
    payload.system = systemPrompt;
  }

  if (temperature !== undefined) {
    payload.temperature = temperature;
  }

  var args = [
    "curl", "-s", "-S", "--no-buffer", "-X", "POST",
    "-H", "Content-Type: application/json",
    "-H", "x-api-key: " + apiKey,
    "-H", "anthropic-version: 2023-06-01",
    "-d", JSON.stringify(payload),
    LlmProviderConfig.anthropic.endpoint
  ];

  return { args: args, url: LlmProviderConfig.anthropic.endpoint };
}

function parseAnthropicStream(data) {
  if (!data) return null;
  var line = data.trim();
  if (line === "") return null;

  // Skip event: lines
  if (line.startsWith("event:")) return null;

  if (line.startsWith("data: ")) {
    var jsonStr = line.substring(6).trim();
    if (jsonStr === "[DONE]") return { done: true };

    try {
      var json = JSON.parse(jsonStr);

      // content_block_delta with text
      if (json.type === "content_block_delta" && json.delta) {
        if (json.delta.type === "text_delta" && json.delta.text) {
          return { content: json.delta.text };
        }
      }

      // message_stop
      if (json.type === "message_stop") {
        return { done: true };
      }

      // error
      if (json.type === "error" && json.error) {
        return { error: json.error.message || "Anthropic API error" };
      }

      // Other event types (message_start, content_block_start, etc.) - ignore
      return null;

    } catch (e) {
      return { error: "Error parsing Anthropic SSE: " + e };
    }
  } else {
    // Try to parse raw JSON errors
    if (line.startsWith("{")) {
      try {
        var errorJson = JSON.parse(line);
        if (errorJson.error) {
          return { error: errorJson.error.message || "API error" };
        }
      } catch (e) {}
    }
    return { raw: line };
  }
}

// ===================================
// LLM: Google Gemini
// ===================================

function buildGeminiCommand(apiKey, model, systemPrompt, history, temperature) {
  var contents = [];

  if (systemPrompt && systemPrompt.trim() !== "") {
    contents.push({
      role: "user",
      parts: [{ text: "System instruction: " + systemPrompt }]
    });
    contents.push({
      role: "model",
      parts: [{ text: "Understood. I will follow these instructions." }]
    });
  }

  for (var i = 0; i < history.length; i++) {
    contents.push({
      role: history[i].role === "assistant" ? "model" : "user",
      parts: [{ text: history[i].content }]
    });
  }

  var payload = {
    contents: contents,
    generationConfig: { temperature: temperature }
  };

  var finalModel = model || LlmProviderConfig.google.defaultModel;
  var finalUrl = LlmProviderConfig.google.streamEndpoint
    .replace("{model}", finalModel)
    .replace("{apiKey}", apiKey);

  var args = [
    "curl", "-s", "--no-buffer", "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", JSON.stringify(payload),
    finalUrl
  ];

  return { args: args, url: finalUrl };
}

function parseGeminiStream(data) {
  if (!data) return null;
  var line = data.trim();
  if (line === "") return null;

  if (line.startsWith("data: ")) {
    var jsonStr = line.substring(6).trim();
    if (jsonStr === "[DONE]") return { done: true };

    try {
      var json = JSON.parse(jsonStr);
      if (json.candidates && json.candidates[0] && json.candidates[0].content) {
        var parts = json.candidates[0].content.parts;
        if (parts && parts[0] && parts[0].text) {
          return { content: parts[0].text };
        }
      }
    } catch (e) {
      return { error: "Error parsing Gemini SSE: " + e };
    }
  } else {
    if (line.startsWith("{") && line.endsWith("}")) {
      try {
        var errorJson = JSON.parse(line);
        if (errorJson.error) {
          return { error: errorJson.error.message || "Gemini API error" };
        }
      } catch (e) {}
    }
    return { raw: line };
  }
  return null;
}

// ===================================
// Live Mode: two-process pipeline
// ===================================
//
// The single-ffmpeg approach (record + silencedetect in one process) looks
// elegant but breaks in practice: ffmpeg's WAV muxer buffers 8-12 seconds
// before first flush, partial files corrupt mid-extract, and early chunks
// arrive at "empty file" state causing "Audio file is too short" errors
// from Whisper. Splitting into two processes fixes all three:
//
//   Process A (pw-record): writes the session WAV. pw-record flushes
//   progressively from t=0 and uses a clean 44-byte header that ffmpeg
//   can read back while the file is still being written.
//
//   Process B (ffmpeg silencedetect to null): just emits VAD events on
//   stderr, no output file. Drift vs process A is ≤ ~50 ms.

function buildSessionRecorderCommand(sessionFilePath) {
  return {
    args: [
      "pw-record", "--media-category", "Capture",
      "--rate", "16000", "--channels", "1",
      sessionFilePath
    ]
  };
}

function buildVadMonitorCommand(silenceDb, silenceSec) {
  var db = (silenceDb !== undefined && silenceDb !== null) ? silenceDb : -18;
  var sec = (silenceSec !== undefined && silenceSec !== null) ? silenceSec : 1.0;
  var filter = "silencedetect=noise=" + db + "dB:d=" + sec;
  return {
    args: [
      "ffmpeg", "-hide_banner", "-loglevel", "info",
      "-nostats",
      "-f", "pulse", "-i", "default",
      "-ar", "16000", "-ac", "1",
      "-af", filter,
      "-f", "null", "-"
    ]
  };
}

// Parse one line of ffmpeg stderr. Returns null if not a silencedetect event.
// Examples:
//   [silencedetect @ 0x55a...] silence_start: 3.424
//   [silencedetect @ 0x55a...] silence_end: 5.187 | silence_duration: 1.763
function parseSilenceEvent(line) {
  if (!line) return null;
  var m = line.match(/silence_(start|end):\s*(-?[\d.]+)/);
  if (!m) return null;
  var t = parseFloat(m[2]);
  if (isNaN(t) || t < 0) t = 0;
  return { type: m[1], time: t };
}

// Extract a time slice [startSec, endSec] from the live session WAV into a chunk file.
// -ignore_length 1 tolerates a growing source (header length field is stale).
// Use -t <duration> instead of -to <end>: when the source WAV's RIFF header
// hasn't been finalised, -to gets clamped to the (broken) reported duration
// and yields empty output. -t reads byte-stream bytes for a fixed duration
// regardless of what the header claims.
function buildChunkExtractCommand(sessionFilePath, chunkFilePath, startSec, endSec) {
  var s = Math.max(0, startSec || 0);
  var e = Math.max(s + 0.05, endSec || s + 0.05);
  var duration = e - s;
  var args = [
    "ffmpeg", "-hide_banner", "-loglevel", "error",
    "-y",
    "-ignore_length", "1",
    "-ss", s.toFixed(3),
    "-t", duration.toFixed(3),
    "-i", sessionFilePath,
    "-ar", "16000", "-ac", "1",
    chunkFilePath
  ];
  return { args: args };
}

// ===================================
// Whisper hallucination filter
// ===================================
// Groq Whisper reliably produces a handful of phantom transcripts when fed
// chunks that contain only low-level noise or silence: a bare ".", "you",
// "Thanks for watching", etc. Filter them out before they reach the LLM.
function isLikelyHallucination(text) {
  if (!text) return true;
  var trimmed = text.trim();
  if (trimmed === "") return true;

  // Count characters that are neither whitespace nor common punctuation.
  // Keeps non-latin scripts (pt/es/ja/etc.) because they're neither.
  var punct = ".,!?;:()[]{}'\"`~-_<>/\\|@#$%^&*+=";
  var meaningful = 0;
  for (var i = 0; i < trimmed.length; i++) {
    var c = trimmed.charAt(i);
    if (c === " " || c === "\t" || c === "\n" || c === "\r") continue;
    if (punct.indexOf(c) !== -1) continue;
    meaningful++;
  }
  if (meaningful < 3) return true;

  // Known Whisper phantoms on silent/near-silent audio.
  var normalized = trimmed.toLowerCase().replace(/[.,!?;:'"]/g, "").trim();
  var phantoms = [
    "you", "thanks", "thank you",
    "thanks for watching", "thank you for watching",
    "bye", "bye bye", "music", "applause",
    "subtitles by the amaraorg community"
  ];
  for (var j = 0; j < phantoms.length; j++) {
    if (normalized === phantoms[j]) return true;
  }
  return false;
}

// ===================================
// State Management
// ===================================

function processLoadedState(content) {
  if (!content || content.trim() === "") return null;
  try {
    var cached = JSON.parse(content);
    return {
      messages: cached.messages || [],
      chatInputText: cached.chatInputText || ""
    };
  } catch (e) {
    return { error: e.toString() };
  }
}

function prepareStateForSave(messages, maxHistory, chatInputText) {
  var maxLog = maxHistory || 50;
  var toSave = messages.slice(-maxLog);

  return JSON.stringify({
    messages: toSave,
    chatInputText: chatInputText || "",
    timestamp: Math.floor(Date.now() / 1000)
  }, null, 2);
}
