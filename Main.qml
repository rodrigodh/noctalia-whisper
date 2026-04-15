import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import "WhisperLogic.js" as Logic

Item {
  id: root
  property var pluginApi: null

  // =====================
  // Recording State
  // =====================
  property bool isRecording: false
  property bool recordingCancelled: false
  property real recordingDuration: 0
  property string recordingFilePath: "/tmp/whisper-recording-" + Date.now() + ".wav"

  // =====================
  // Transcription State
  // =====================
  property bool isTranscribing: false
  property string transcribedText: ""
  property string transcriptionError: ""

  // =====================
  // AI Chat State
  // =====================
  property var messages: []
  property bool isGenerating: false
  property string currentResponse: ""
  property string errorMessage: ""
  property bool isManuallyStopped: false
  property string chatInputText: ""

  // =====================
  // Settings Accessors
  // =====================
  readonly property string sttProvider: pluginApi?.pluginSettings?.sttProvider || "groq"
  readonly property string llmProvider: pluginApi?.pluginSettings?.llmProvider || "groq"
  readonly property string llmModel: {
    var saved = pluginApi?.pluginSettings?.llmModel;
    if (saved !== undefined && saved !== "")
      return saved;
    var config = Logic.LlmProviderConfig[llmProvider];
    return config ? config.defaultModel : "";
  }
  readonly property real temperature: pluginApi?.pluginSettings?.temperature || 0.7
  readonly property string systemPrompt: pluginApi?.pluginSettings?.systemPrompt || ""
  readonly property string language: pluginApi?.pluginSettings?.language || "en"

  // API Keys - env vars take priority
  readonly property string envGroqKey: Quickshell.env("WHISPER_GROQ_API_KEY") || ""
  readonly property string envAnthropicKey: Quickshell.env("WHISPER_ANTHROPIC_API_KEY") || ""
  readonly property string envGoogleKey: Quickshell.env("WHISPER_GOOGLE_API_KEY") || ""

  function getApiKey(provider) {
    // Env var priority
    if (provider === "groq" && envGroqKey !== "") return envGroqKey;
    if (provider === "anthropic" && envAnthropicKey !== "") return envAnthropicKey;
    if (provider === "google" && envGoogleKey !== "") return envGoogleKey;
    // Settings
    var keys = pluginApi?.pluginSettings?.apiKeys || {};
    return keys[provider] || "";
  }

  readonly property string sttApiKey: getApiKey(sttProvider)
  readonly property string llmApiKey: getApiKey(llmProvider)

  // =====================
  // Cache
  // =====================
  readonly property string cacheDir: typeof Settings !== 'undefined' && Settings.cacheDir ? Settings.cacheDir + "plugins/whisper/" : ""
  readonly property string stateCachePath: cacheDir + "state.json"

  Component.onCompleted: {
    Logger.i("Whisper", "Plugin initialized");
    ensureCacheDir();
  }

  function ensureCacheDir() {
    if (cacheDir) {
      Quickshell.execDetached(["mkdir", "-p", cacheDir]);
    }
  }

  // =====================
  // State Persistence
  // =====================
  FileView {
    id: stateCacheFile
    path: root.stateCachePath
    watchChanges: false

    onLoaded: {
      var content = stateCacheFile.text();
      var result = Logic.processLoadedState(content);
      if (result && !result.error) {
        root.messages = result.messages;
        root.chatInputText = result.chatInputText;
        Logger.d("Whisper", "Loaded " + root.messages.length + " messages from cache");
      }
    }

    onLoadFailed: function (error) {
      if (error !== 2) {
        Logger.e("Whisper", "Failed to load state cache: " + error);
      }
    }
  }

  Timer {
    id: saveStateTimer
    interval: 500
    onTriggered: performSaveState()
  }

  property bool saveStateQueued: false

  function saveState() {
    saveStateQueued = true;
    saveStateTimer.restart();
  }

  function performSaveState() {
    if (!saveStateQueued || !cacheDir) return;
    saveStateQueued = false;

    try {
      ensureCacheDir();
      var maxHistory = pluginApi?.pluginSettings?.maxHistoryLength || 50;
      var dataStr = Logic.prepareStateForSave(root.messages, maxHistory, root.chatInputText);
      stateCacheFile.setText(dataStr);
    } catch (e) {
      Logger.e("Whisper", "Failed to save state: " + e);
    }
  }

  // =====================
  // Recording Timer
  // =====================
  Timer {
    id: recordingTimer
    interval: 100
    repeat: true
    running: root.isRecording
    onTriggered: {
      root.recordingDuration += 0.1;
    }
  }

  // =====================
  // Audio Recording Process (pw-record)
  // =====================
  Process {
    id: recordProcess
    command: ["pw-record", "--media-category", "Capture", "--rate", "16000", "--channels", "1", root.recordingFilePath]

    onExited: function (exitCode, exitStatus) {
      Logger.i("Whisper", "Recording process exited: code=" + exitCode);
      if (root.isRecording) {
        root.isRecording = false;
      }
      // Skip transcription if recording was cancelled (e.g. panel closed)
      if (root.recordingCancelled) {
        root.recordingCancelled = false;
        cleanupRecording();
        return;
      }
      // After recording stops, start transcription
      if (root.recordingDuration > 0.3) {
        root.startTranscription();
      } else {
        Logger.w("Whisper", "Recording too short, skipping transcription");
        cleanupRecording();
      }
    }
  }

  function startRecording() {
    if (root.isRecording) return;

    // Generate a unique file path for this recording
    root.recordingFilePath = "/tmp/whisper-recording-" + Date.now() + ".wav";
    root.recordingDuration = 0;
    root.recordingCancelled = false;
    root.transcribedText = "";
    root.transcriptionError = "";
    root.errorMessage = "";
    root.isRecording = true;

    Logger.i("Whisper", "Starting recording: " + root.recordingFilePath);
    recordProcess.command = ["pw-record", "--media-category", "Capture", "--rate", "16000", "--channels", "1", root.recordingFilePath];
    recordProcess.running = true;
  }

  function stopRecording() {
    if (!root.isRecording) return;

    Logger.i("Whisper", "Stopping recording (duration: " + root.recordingDuration.toFixed(1) + "s)");
    root.isRecording = false;
    recordProcess.running = false;
  }

  function cancelRecording() {
    if (!root.isRecording) return;
    root.recordingCancelled = true;
    root.isRecording = false;
    recordProcess.running = false;
  }

  function cleanupRecording() {
    Quickshell.execDetached(["rm", "-f", root.recordingFilePath]);
  }

  // =====================
  // Speech-to-Text Transcription
  // =====================
  Process {
    id: transcribeProcess

    stdout: StdioCollector {
      onStreamFinished: {
        root.handleTranscriptionResult(text);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim() !== "") {
          Logger.e("Whisper", "Transcription stderr: " + text);
        }
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0 && root.transcribedText === "") {
        root.isTranscribing = false;
        if (root.transcriptionError === "") {
          root.transcriptionError = pluginApi?.tr("errors.transcriptionFailed") || "Transcription failed";
        }
        cleanupRecording();
      }
    }
  }

  function startTranscription() {
    if (!sttApiKey || sttApiKey.trim() === "") {
      root.transcriptionError = pluginApi?.tr("errors.noSttKey") || "No STT API key configured";
      cleanupRecording();
      return;
    }

    root.isTranscribing = true;
    root.transcriptionError = "";

    var cmd = Logic.buildWhisperCommand(root.recordingFilePath, sttApiKey, language);
    Logger.i("Whisper", "Starting transcription");
    transcribeProcess.command = cmd.args;
    transcribeProcess.running = true;
  }

  function handleTranscriptionResult(responseText) {
    root.isTranscribing = false;
    cleanupRecording();

    var result = Logic.parseWhisperResponse(responseText);
    if (result.error) {
      root.transcriptionError = result.error;
      Logger.e("Whisper", "Transcription error: " + result.error);
      return;
    }

    if (result.text && result.text.trim() !== "") {
      root.transcribedText = result.text;
      Logger.i("Whisper", "Transcription: " + result.text);
      // Automatically send to LLM
      sendMessage(result.text);
    } else {
      root.transcriptionError = pluginApi?.tr("errors.noSpeechDetected") || "No speech detected";
    }
  }

  // =====================
  // Chat Functions
  // =====================
  function addMessage(role, content) {
    var newMessage = {
      id: Date.now().toString(),
      role: role,
      content: content,
      timestamp: new Date().toISOString()
    };
    root.messages = [...root.messages, newMessage];
    saveState();
    return newMessage;
  }

  function clearMessages() {
    root.messages = [];
    saveState();
    Logger.i("Whisper", "Chat history cleared");
  }

  function sendMessage(userMessage) {
    if (!userMessage || userMessage.trim() === "") return;
    if (root.isGenerating) return;

    if (!llmApiKey || llmApiKey.trim() === "") {
      root.errorMessage = pluginApi?.tr("errors.noLlmKey") || "No LLM API key configured";
      ToastService.showError(root.errorMessage);
      return;
    }

    addMessage("user", userMessage.trim());

    root.isGenerating = true;
    root.isManuallyStopped = false;
    root.currentResponse = "";
    root.errorMessage = "";

    if (llmProvider === "groq") {
      sendGroqRequest();
    } else if (llmProvider === "anthropic") {
      sendAnthropicRequest();
    } else if (llmProvider === "google") {
      sendGeminiRequest();
    } else {
      root.errorMessage = "Unknown LLM provider: " + llmProvider;
      root.isGenerating = false;
    }
  }

  function buildConversationHistory() {
    var history = [];
    for (var i = 0; i < root.messages.length; i++) {
      var msg = root.messages[i];
      history.push({ role: msg.role, content: msg.content });
    }
    return history;
  }

  function stopGeneration() {
    if (!root.isGenerating) return;
    Logger.i("Whisper", "Stopping generation");

    root.isManuallyStopped = true;
    if (groqProcess.running) groqProcess.running = false;
    if (anthropicProcess.running) anthropicProcess.running = false;
    if (geminiProcess.running) geminiProcess.running = false;

    root.isGenerating = false;
    if (root.currentResponse.trim() !== "") {
      root.addMessage("assistant", root.currentResponse.trim());
    }
    root.currentResponse = "";
  }

  // =====================
  // Groq LLM Process
  // =====================
  Process {
    id: groqProcess
    property string buffer: ""

    stdout: SplitParser {
      onRead: function (data) {
        var result = Logic.parseOpenAIStream(data);
        if (!result) return;

        if (result.content) {
          root.currentResponse += result.content;
        } else if (result.error) {
          Logger.e("Whisper", "Groq stream error: " + result.error);
        } else if (result.raw) {
          groqProcess.buffer += result.raw;
          try {
            var errorJson = JSON.parse(groqProcess.buffer);
            if (errorJson.error) {
              root.errorMessage = errorJson.error.message || "API error";
            }
            groqProcess.buffer = "";
          } catch (e) {}
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim() !== "") {
          Logger.e("Whisper", "Groq stderr: " + text);
        }
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (root.isManuallyStopped) {
        root.isManuallyStopped = false;
        return;
      }
      root.isGenerating = false;
      groqProcess.buffer = "";
      if (exitCode !== 0 && root.currentResponse === "") {
        if (root.errorMessage === "") root.errorMessage = pluginApi?.tr("errors.requestFailed") || "Request failed";
        return;
      }
      if (root.currentResponse.trim() !== "") {
        root.addMessage("assistant", root.currentResponse.trim());
      }
      root.currentResponse = "";
    }
  }

  function sendGroqRequest() {
    var history = buildConversationHistory();
    var cmd = Logic.buildGroqLlmCommand(llmApiKey, llmModel, systemPrompt, history, temperature);
    Logger.i("Whisper", "Sending Groq request");
    groqProcess.buffer = "";
    groqProcess.command = cmd.args;
    groqProcess.running = true;
  }

  // =====================
  // Anthropic Claude Process
  // =====================
  Process {
    id: anthropicProcess
    property string buffer: ""

    stdout: SplitParser {
      onRead: function (data) {
        var result = Logic.parseAnthropicStream(data);
        if (!result) return;

        if (result.content) {
          root.currentResponse += result.content;
        } else if (result.error) {
          Logger.e("Whisper", "Anthropic stream error: " + result.error);
          root.errorMessage = result.error;
        } else if (result.raw) {
          anthropicProcess.buffer += result.raw;
          try {
            var errorJson = JSON.parse(anthropicProcess.buffer);
            if (errorJson.error) {
              root.errorMessage = errorJson.error.message || "API error";
            }
            anthropicProcess.buffer = "";
          } catch (e) {}
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim() !== "") {
          Logger.e("Whisper", "Anthropic stderr: " + text);
        }
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (root.isManuallyStopped) {
        root.isManuallyStopped = false;
        return;
      }
      root.isGenerating = false;
      anthropicProcess.buffer = "";
      if (exitCode !== 0 && root.currentResponse === "") {
        if (root.errorMessage === "") root.errorMessage = pluginApi?.tr("errors.requestFailed") || "Request failed";
        return;
      }
      if (root.currentResponse.trim() !== "") {
        root.addMessage("assistant", root.currentResponse.trim());
      }
      root.currentResponse = "";
    }
  }

  function sendAnthropicRequest() {
    var history = buildConversationHistory();
    var cmd = Logic.buildAnthropicCommand(llmApiKey, llmModel, systemPrompt, history, temperature);
    Logger.i("Whisper", "Sending Anthropic request");
    anthropicProcess.buffer = "";
    anthropicProcess.command = cmd.args;
    anthropicProcess.running = true;
  }

  // =====================
  // Google Gemini Process
  // =====================
  Process {
    id: geminiProcess
    property string buffer: ""

    stdout: SplitParser {
      onRead: function (data) {
        var result = Logic.parseGeminiStream(data);
        if (!result) return;

        if (result.content) {
          root.currentResponse += result.content;
        } else if (result.error) {
          Logger.e("Whisper", "Gemini stream error: " + result.error);
          if (!result.error.startsWith("Error parsing")) {
            root.errorMessage = result.error;
          }
        } else if (result.raw) {
          geminiProcess.buffer += result.raw;
          try {
            var errorJson = JSON.parse(geminiProcess.buffer);
            if (errorJson.error) {
              root.errorMessage = errorJson.error.message || "API error";
            }
            geminiProcess.buffer = "";
          } catch (e) {}
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim() !== "") {
          Logger.e("Whisper", "Gemini stderr: " + text);
        }
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (root.isManuallyStopped) {
        root.isManuallyStopped = false;
        return;
      }
      root.isGenerating = false;
      geminiProcess.buffer = "";
      if (exitCode !== 0 && root.currentResponse === "") {
        if (root.errorMessage === "") root.errorMessage = pluginApi?.tr("errors.requestFailed") || "Request failed";
        return;
      }
      if (root.currentResponse.trim() !== "") {
        root.addMessage("assistant", root.currentResponse.trim());
      }
      root.currentResponse = "";
    }
  }

  function sendGeminiRequest() {
    var history = buildConversationHistory();
    var cmd = Logic.buildGeminiCommand(llmApiKey, llmModel, systemPrompt, history, temperature);
    Logger.i("Whisper", "Sending Gemini request");
    geminiProcess.buffer = "";
    geminiProcess.command = cmd.args;
    geminiProcess.running = true;
  }

  // =====================
  // Toggle Recording (main action)
  // =====================
  function toggleRecording() {
    if (root.isRecording) {
      stopRecording();
    } else {
      startRecording();
    }
  }

  // =====================
  // IPC Handlers
  // =====================
  IpcHandler {
    target: "plugin:whisper"

    function toggle() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.openPanel(screen);
        });
        // Start recording if not already
        if (!root.isRecording && !root.isTranscribing && !root.isGenerating) {
          Qt.callLater(function() {
            root.startRecording();
          });
        } else if (root.isRecording) {
          root.stopRecording();
        }
      }
    }

    function open() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.openPanel(screen);
        });
      }
    }

    function close() {
      if (pluginApi) {
        if (root.isRecording) root.cancelRecording();
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.closePanel(screen);
        });
      }
    }

    function record() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.openPanel(screen);
        });
        Qt.callLater(function() {
          root.startRecording();
        });
      }
    }

    function stop() {
      root.stopRecording();
    }

    function send(message: string) {
      if (message && message.trim() !== "") {
        root.sendMessage(message);
      }
    }

    function clear() {
      root.clearMessages();
      ToastService.showNotice(pluginApi?.tr("toast.historyCleared") || "History cleared");
    }
  }
}
