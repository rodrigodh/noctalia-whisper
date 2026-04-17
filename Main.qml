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
  // Legacy PTT State (kept for the `record` IPC)
  // =====================
  property bool isRecording: false
  property bool recordingCancelled: false
  property real recordingDuration: 0
  property string recordingFilePath: "/tmp/whisper-recording-" + Date.now() + ".wav"

  // =====================
  // Live Mode State
  // =====================
  property bool isLive: false
  property string liveSessionFilePath: ""
  property real liveSessionStartMs: 0
  // Seconds-from-start where the current speech burst began.
  // -1 means "no confirmed speech since the last chunk was cut".
  property real lastSilenceEndTime: -1
  property int liveChunkCounter: 0
  property var pendingChunks: []           // queue of { path, startSec, endSec }
  property bool isChunkPipelineBusy: false
  property string lastHeardText: ""
  property bool liveFailed: false

  // =====================
  // Transcription State
  // =====================
  property bool isTranscribing: false
  property string transcribedText: ""
  property string transcriptionError: ""
  // Tracks which file to delete after transcription + what to do with the text.
  // "legacy" = PTT flow (from recordingFilePath); "live" = live chunk (from pendingChunks).
  property string _transcribeSource: "legacy"
  property string _transcribingFilePath: ""

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
  readonly property real temperature: pluginApi?.pluginSettings?.temperature || 0.5
  readonly property string systemPrompt: pluginApi?.pluginSettings?.systemPrompt
                                        || pluginApi?.manifest?.metadata?.defaultSettings?.systemPrompt
                                        || ""
  readonly property string language: pluginApi?.pluginSettings?.language || "auto"

  // Live/VAD config (with manifest defaults as fallback)
  readonly property bool liveModeDefault: pluginApi?.pluginSettings?.liveMode ?? true
  readonly property real vadSilenceDb: pluginApi?.pluginSettings?.vadSilenceDb ?? -15
  readonly property real vadSilenceSec: pluginApi?.pluginSettings?.vadSilenceSec ?? 0.7
  readonly property real vadMinSpeechSec: pluginApi?.pluginSettings?.vadMinSpeechSec ?? 0.7
  readonly property real vadMaxSpeechSec: pluginApi?.pluginSettings?.vadMaxSpeechSec ?? 12.0

  // API Keys - env vars take priority
  readonly property string envGroqKey: Quickshell.env("WHISPER_GROQ_API_KEY") || ""
  readonly property string envAnthropicKey: Quickshell.env("WHISPER_ANTHROPIC_API_KEY") || ""
  readonly property string envGoogleKey: Quickshell.env("WHISPER_GOOGLE_API_KEY") || ""

  function getApiKey(provider) {
    if (provider === "groq" && envGroqKey !== "") return envGroqKey;
    if (provider === "anthropic" && envAnthropicKey !== "") return envAnthropicKey;
    if (provider === "google" && envGoogleKey !== "") return envGoogleKey;
    var keys = pluginApi?.pluginSettings?.apiKeys || {};
    return keys[provider] || "";
  }

  readonly property string sttApiKey: getApiKey(sttProvider)
  readonly property string llmApiKey: getApiKey(llmProvider)

  // i18n helper — Noctalia's tr() returns "!!key!!" on miss; collapse that to fallback.
  function t(key, fallback) {
    return Logic.cleanTr(pluginApi ? pluginApi.tr(key) : null, fallback);
  }

  // =====================
  // Cache
  // =====================
  readonly property string cacheDir: typeof Settings !== 'undefined' && Settings.cacheDir ? Settings.cacheDir + "plugins/whisper/" : ""
  readonly property string stateCachePath: cacheDir + "state.json"

  Component.onCompleted: {
    Logger.i("Whisper", "Plugin initialized");
    ensureCacheDir();
  }

  Component.onDestruction: {
    if (root.isLive) stopLive();
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
  // Recording Duration Timer (used by both PTT and Live)
  // =====================
  Timer {
    id: recordingTimer
    interval: 100
    repeat: true
    running: root.isRecording || root.isLive
    onTriggered: {
      root.recordingDuration += 0.1;
    }
  }

  // =====================
  // Legacy PTT Recording (pw-record)
  // =====================
  Process {
    id: recordProcess
    command: ["pw-record", "--media-category", "Capture", "--rate", "16000", "--channels", "1", root.recordingFilePath]

    onExited: function (exitCode, exitStatus) {
      Logger.i("Whisper", "PTT recording process exited: code=" + exitCode);
      if (root.isRecording) root.isRecording = false;
      if (root.recordingCancelled) {
        root.recordingCancelled = false;
        cleanupLegacyRecording();
        return;
      }
      if (root.recordingDuration > 0.3) {
        root.startLegacyTranscription();
      } else {
        Logger.w("Whisper", "PTT recording too short, skipping transcription");
        cleanupLegacyRecording();
      }
    }
  }

  function startRecording() {
    if (root.isRecording || root.isLive) return;

    root.recordingFilePath = "/tmp/whisper-recording-" + Date.now() + ".wav";
    root.recordingDuration = 0;
    root.recordingCancelled = false;
    root.transcribedText = "";
    root.transcriptionError = "";
    root.errorMessage = "";
    root.isRecording = true;

    Logger.i("Whisper", "Starting PTT recording: " + root.recordingFilePath);
    recordProcess.command = ["pw-record", "--media-category", "Capture", "--rate", "16000", "--channels", "1", root.recordingFilePath];
    recordProcess.running = true;
  }

  function stopRecording() {
    if (!root.isRecording) return;
    Logger.i("Whisper", "Stopping PTT recording (" + root.recordingDuration.toFixed(1) + "s)");
    root.isRecording = false;
    recordProcess.running = false;
  }

  function cancelRecording() {
    if (!root.isRecording) return;
    root.recordingCancelled = true;
    root.isRecording = false;
    recordProcess.running = false;
  }

  function cleanupLegacyRecording() {
    Quickshell.execDetached(["rm", "-f", root.recordingFilePath]);
  }

  function startLegacyTranscription() {
    if (!sttApiKey || sttApiKey.trim() === "") {
      root.transcriptionError = root.t("errors.noSttKey", "No STT API key configured");
      cleanupLegacyRecording();
      return;
    }
    root._transcribeSource = "legacy";
    root._transcribingFilePath = root.recordingFilePath;
    root.isTranscribing = true;
    root.transcriptionError = "";

    var cmd = Logic.buildWhisperCommand(root.recordingFilePath, sttApiKey, language);
    Logger.i("Whisper", "Starting PTT transcription");
    transcribeProcess.command = cmd.args;
    transcribeProcess.running = true;
  }

  // =====================
  // Live Mode: pw-record (session file) + ffmpeg silencedetect (VAD)
  // =====================

  // Safety net: if the VAD hasn't reported silence_start after `vadMaxSpeechSec`
  // of continuous speech, force a chunk break so Whisper isn't handed a 30s+
  // monologue (which it reliably hallucinates on).
  Timer {
    id: maxSpeechTimer
    repeat: false
    onTriggered: root.forceChunkBreak()
  }

  function forceChunkBreak() {
    if (!root.isLive) return;
    if (root.lastSilenceEndTime < 0) return; // no speech in progress

    // Estimate ffmpeg's current position from wall clock. Slight drift is fine;
    // `-ignore_length 1 -t <dur>` reads byte-stream bytes and tolerates short reads.
    var nowFfmpegTime = (Date.now() - root.liveSessionStartMs) / 1000;
    if (nowFfmpegTime <= root.lastSilenceEndTime) return;

    var speechStart = root.lastSilenceEndTime;
    var speechEnd = nowFfmpegTime;
    var dur = speechEnd - speechStart;
    if (dur < root.vadMinSpeechSec) return;

    Logger.i("Whisper", "VAD: force break at " + speechEnd.toFixed(2) + "s (max speech " + root.vadMaxSpeechSec + "s reached)");
    var chunkPath = "/tmp/whisper-live-chunk-" + root.liveSessionStartMs + "-" + root.liveChunkCounter + ".wav";
    root.liveChunkCounter += 1;
    root.pendingChunks = [...root.pendingChunks, {
      path: chunkPath,
      startSec: speechStart,
      endSec: speechEnd
    }];
    // Continue treating the current moment as still-speaking.
    root.lastSilenceEndTime = speechEnd;
    maxSpeechTimer.interval = Math.max(1000, Math.round(root.vadMaxSpeechSec * 1000));
    maxSpeechTimer.restart();
    processNextChunk();
  }

  // Session recorder: pw-record writes a growing WAV that ffmpeg can
  // reliably chunk-extract from while still being written.
  Process {
    id: sessionRecorderProcess

    onExited: function (exitCode, exitStatus) {
      Logger.i("Whisper", "Session recorder exited: code=" + exitCode);
      // If the recorder dies unexpectedly while Live is on, the whole pipeline
      // is useless — stop cleanly.
      if (root.isLive && exitCode !== 0) {
        root.liveFailed = true;
        root.errorMessage = root.t("toast.liveFailed", "Live mode failed");
        ToastService.showError(root.errorMessage);
        root.stopLive();
      }
      // Cleanup is gated on liveSessionFilePath still being set so we don't
      // race a still-running chunk extract.
      Qt.callLater(function () {
        if (!root.isLive && root.liveSessionFilePath) {
          Quickshell.execDetached(["rm", "-f", root.liveSessionFilePath]);
          root.liveSessionFilePath = "";
        }
      });
    }
  }

  // VAD monitor: ffmpeg with silencedetect → -f null. No output file,
  // events go to stderr and get parsed line-by-line.
  Process {
    id: vadProcess

    stderr: SplitParser {
      onRead: function (data) {
        var evt = Logic.parseSilenceEvent(data);
        if (evt) root.handleSilenceEvent(evt);
      }
    }

    onExited: function (exitCode, exitStatus) {
      Logger.i("Whisper", "VAD monitor exited: code=" + exitCode);
      if (root.isLive && exitCode !== 0) {
        root.liveFailed = true;
        root.errorMessage = root.t("toast.liveFailed", "Live mode failed");
        ToastService.showError(root.errorMessage);
        root.stopLive();
      }
    }
  }

  function startLive() {
    if (root.isLive) return;
    if (root.isRecording) stopRecording();

    if (!sttApiKey || sttApiKey.trim() === "") {
      root.transcriptionError = root.t("errors.noSttKey", "No STT API key configured");
      ToastService.showError(root.transcriptionError);
      return;
    }

    var ts = Date.now();
    root.liveSessionFilePath = "/tmp/whisper-live-" + ts + ".wav";
    root.liveSessionStartMs = ts;
    // Start assuming speech is in progress from t=0. Covers the common
    // "user speaks immediately when Live starts" case — otherwise the
    // first real silence_end would never fire and we'd never get a chunk.
    root.lastSilenceEndTime = 0;
    root.liveChunkCounter = 0;
    root.pendingChunks = [];
    root.isChunkPipelineBusy = false;
    root.liveFailed = false;
    root.recordingDuration = 0;
    root.transcribedText = "";
    root.transcriptionError = "";
    root.errorMessage = "";
    root.lastHeardText = "";
    root.isLive = true;

    // Arm the max-speech safety timer now so that even if the VAD never
    // emits silence_end (continuous speech) the force-break eventually fires.
    maxSpeechTimer.interval = Math.max(1000, Math.round(root.vadMaxSpeechSec * 1000));
    maxSpeechTimer.restart();

    var recCmd = Logic.buildSessionRecorderCommand(root.liveSessionFilePath);
    var vadCmd = Logic.buildVadMonitorCommand(root.vadSilenceDb, root.vadSilenceSec);
    Logger.i("Whisper", "Starting Live pipeline → " + root.liveSessionFilePath);
    sessionRecorderProcess.command = recCmd.args;
    sessionRecorderProcess.running = true;
    vadProcess.command = vadCmd.args;
    vadProcess.running = true;
    ToastService.showNotice(root.t("toast.liveStarted", "Live mode on"));
  }

  function stopLive() {
    if (!root.isLive && !sessionRecorderProcess.running && !vadProcess.running) return;
    Logger.i("Whisper", "Stopping Live pipeline");
    root.isLive = false;
    maxSpeechTimer.stop();
    // Drop any queued chunks that haven't started yet.
    root.pendingChunks = [];
    // Stop VAD first (fewer side effects); recorder second so any in-flight
    // chunk extract can still find the session file on disk.
    vadProcess.running = false;
    sessionRecorderProcess.running = false;
    ToastService.showNotice(root.t("toast.liveStopped", "Live mode off"));
  }

  function toggleLive() {
    if (root.isLive) stopLive();
    else startLive();
  }

  // Called from vadProcess.stderr
  function handleSilenceEvent(evt) {
    Logger.i("Whisper", "VAD: silence_" + evt.type + " @ " + evt.time.toFixed(2) + "s");
    if (evt.type === "end") {
      // Speech just started (silence ended). Arm the max-speech safety timer.
      root.lastSilenceEndTime = evt.time;
      maxSpeechTimer.interval = Math.max(1000, Math.round(root.vadMaxSpeechSec * 1000));
      maxSpeechTimer.restart();
    } else if (evt.type === "start") {
      // Speech just ended (silence started). Real endpoint found → cancel safety timer.
      maxSpeechTimer.stop();
      if (root.lastSilenceEndTime < 0) return; // no speech yet
      var speechStart = root.lastSilenceEndTime;
      var speechEnd = evt.time;
      root.lastSilenceEndTime = -1;
      var dur = speechEnd - speechStart;
      if (dur < root.vadMinSpeechSec) {
        Logger.w("Whisper", "VAD: dropped short burst (" + dur.toFixed(2) + "s < minSpeech " + root.vadMinSpeechSec + "s)");
        return;
      }
      var chunkPath = "/tmp/whisper-live-chunk-" + root.liveSessionStartMs + "-" + root.liveChunkCounter + ".wav";
      root.liveChunkCounter += 1;
      root.pendingChunks = [...root.pendingChunks, {
        path: chunkPath,
        startSec: speechStart,
        endSec: speechEnd
      }];
      Logger.i("Whisper", "Queued chunk " + root.liveChunkCounter + " [" + speechStart.toFixed(2) + "→" + speechEnd.toFixed(2) + "]");
      processNextChunk();
    }
  }

  function processNextChunk() {
    if (root.isChunkPipelineBusy) return;
    if (root.pendingChunks.length === 0) return;
    // Serialize: wait for any in-flight transcription, PTT, or LLM response
    // before starting the next chunk. Keeps output strictly sequential.
    if (root.isTranscribing || root.isRecording || root.isGenerating) return;

    var chunk = root.pendingChunks[0];
    root.pendingChunks = root.pendingChunks.slice(1);
    root.isChunkPipelineBusy = true;

    var cmd = Logic.buildChunkExtractCommand(root.liveSessionFilePath,
                                             chunk.path,
                                             chunk.startSec,
                                             chunk.endSec);
    chunkExtractProcess._pendingChunkPath = chunk.path;
    chunkExtractProcess.command = cmd.args;
    chunkExtractProcess.running = true;
  }

  Process {
    id: chunkExtractProcess
    property string _pendingChunkPath: ""

    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim() !== "") {
          Logger.w("Whisper", "chunk-extract stderr: " + text);
        }
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0 || !_pendingChunkPath) {
        Logger.e("Whisper", "Chunk extract failed (code=" + exitCode + ")");
        root.isChunkPipelineBusy = false;
        Quickshell.execDetached(["rm", "-f", _pendingChunkPath]);
        _pendingChunkPath = "";
        // Try next queued chunk anyway.
        root.processNextChunk();
        return;
      }

      // Hand off to transcription.
      root._transcribeSource = "live";
      root._transcribingFilePath = _pendingChunkPath;
      root.isTranscribing = true;
      root.transcriptionError = "";
      var cmd = Logic.buildWhisperCommand(_pendingChunkPath, root.sttApiKey, root.language);
      transcribeProcess.command = cmd.args;
      transcribeProcess.running = true;
      _pendingChunkPath = "";
    }
  }

  // =====================
  // Transcription Process (shared by PTT and Live)
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
          root.transcriptionError = root.t("errors.transcriptionFailed", "Transcription failed");
        }
        cleanupTranscribeFile();
        // Unblock live pipeline if this was a live chunk.
        if (root._transcribeSource === "live") {
          root.isChunkPipelineBusy = false;
          root.processNextChunk();
        }
      }
    }
  }

  function cleanupTranscribeFile() {
    if (root._transcribingFilePath) {
      Quickshell.execDetached(["rm", "-f", root._transcribingFilePath]);
      root._transcribingFilePath = "";
    }
  }

  function handleTranscriptionResult(responseText) {
    root.isTranscribing = false;
    var source = root._transcribeSource;
    cleanupTranscribeFile();

    var result = Logic.parseWhisperResponse(responseText);
    if (result.error) {
      root.transcriptionError = result.error;
      Logger.e("Whisper", "Transcription error: " + result.error);
      if (source === "live") {
        root.isChunkPipelineBusy = false;
        root.processNextChunk();
      }
      return;
    }

    var text = (result.text || "").trim();
    if (text === "" || Logic.isLikelyHallucination(text)) {
      if (source === "live") {
        Logger.w("Whisper", "Dropping transcript as empty/hallucination: '" + text + "'");
        root.isChunkPipelineBusy = false;
        root.processNextChunk();
      } else {
        root.transcriptionError = root.t("errors.noSpeechDetected", "No speech detected");
      }
      return;
    }

    if (source === "live") {
      root.lastHeardText = text;
      Logger.i("Whisper", "Live transcript: " + text);
      // Fire LLM. The queue continues from the LLM onExited hook.
      root.sendMessage(text);
    } else {
      root.transcribedText = text;
      Logger.i("Whisper", "PTT transcript: " + text);
      root.sendMessage(text);
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
    if (root.isGenerating) {
      // User-typed message raced with an in-flight LLM response.
      // Drop the incoming text and unblock the live queue so the next chunk
      // can proceed after the current generation completes.
      Logger.w("Whisper", "Dropping message; generation already in progress");
      if (root._transcribeSource === "live") {
        root.isChunkPipelineBusy = false;
      }
      return;
    }

    if (!llmApiKey || llmApiKey.trim() === "") {
      root.errorMessage = root.t("errors.noLlmKey", "No LLM API key configured");
      ToastService.showError(root.errorMessage);
      // If this was a live chunk, unblock the queue.
      if (root._transcribeSource === "live") {
        root.isChunkPipelineBusy = false;
      }
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
      if (root._transcribeSource === "live") {
        root.isChunkPipelineBusy = false;
      }
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
    // Advance live queue even if user stopped mid-generation.
    afterLlmDone();
  }

  // Hook called at the end of every LLM run (success, failure, or stop).
  function afterLlmDone() {
    if (root.isLive || root._transcribeSource === "live") {
      root.isChunkPipelineBusy = false;
      root.processNextChunk();
    }
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
        if (root.errorMessage === "") root.errorMessage = root.t("errors.requestFailed", "Request failed");
        root.afterLlmDone();
        return;
      }
      if (root.currentResponse.trim() !== "") {
        root.addMessage("assistant", root.currentResponse.trim());
      }
      root.currentResponse = "";
      root.afterLlmDone();
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
        if (root.errorMessage === "") root.errorMessage = root.t("errors.requestFailed", "Request failed");
        root.afterLlmDone();
        return;
      }
      if (root.currentResponse.trim() !== "") {
        root.addMessage("assistant", root.currentResponse.trim());
      }
      root.currentResponse = "";
      root.afterLlmDone();
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
        if (root.errorMessage === "") root.errorMessage = root.t("errors.requestFailed", "Request failed");
        root.afterLlmDone();
        return;
      }
      if (root.currentResponse.trim() !== "") {
        root.addMessage("assistant", root.currentResponse.trim());
      }
      root.currentResponse = "";
      root.afterLlmDone();
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
  // Primary toggle (keybind-facing)
  // =====================
  // If anything is active, stop it. Otherwise, start Live (or PTT if Live is disabled).
  function primaryToggle() {
    if (root.isLive) { stopLive(); return; }
    if (root.isRecording) { stopRecording(); return; }
    if (root.liveModeDefault) startLive();
    else startRecording();
  }

  // Back-compat alias so Panel buttons / old bindings still work.
  function toggleRecording() { primaryToggle(); }

  // =====================
  // IPC Handlers
  // =====================
  IpcHandler {
    target: "plugin:whisper"

    function toggle() {
      if (!pluginApi) return;
      pluginApi.withCurrentScreen(function (screen) {
        pluginApi.openPanel(screen);
      });
      Qt.callLater(function () { root.primaryToggle(); });
    }

    function open() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.openPanel(screen);
        });
      }
    }

    function close() {
      if (!pluginApi) return;
      if (root.isLive) root.stopLive();
      if (root.isRecording) root.cancelRecording();
      pluginApi.withCurrentScreen(function (screen) {
        pluginApi.closePanel(screen);
      });
    }

    function live() {
      if (!pluginApi) return;
      pluginApi.withCurrentScreen(function (screen) {
        pluginApi.openPanel(screen);
      });
      Qt.callLater(function () { root.toggleLive(); });
    }

    function record() {
      if (!pluginApi) return;
      pluginApi.withCurrentScreen(function (screen) {
        pluginApi.openPanel(screen);
      });
      Qt.callLater(function () { root.startRecording(); });
    }

    function stop() {
      if (root.isLive) root.stopLive();
      else if (root.isRecording) root.stopRecording();
    }

    function send(message: string) {
      if (message && message.trim() !== "") {
        root.sendMessage(message);
      }
    }

    function clear() {
      root.clearMessages();
      ToastService.showNotice(root.t("toast.historyCleared", "History cleared"));
    }
  }
}
