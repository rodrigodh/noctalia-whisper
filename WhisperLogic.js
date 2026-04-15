.pragma library

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
