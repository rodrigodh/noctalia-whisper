import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import "WhisperLogic.js" as Logic

ColumnLayout {
  id: root

  property var pluginApi: null

  // STT Settings
  property string editSttProvider: pluginApi?.pluginSettings?.sttProvider || "groq"

  // LLM Settings
  property string editLlmProvider: pluginApi?.pluginSettings?.llmProvider || "groq"
  property string editLlmModel: pluginApi?.pluginSettings?.llmModel || ""
  property var editApiKeys: pluginApi?.pluginSettings?.apiKeys || {}
  property real editTemperature: pluginApi?.pluginSettings?.temperature ?? 0.5
  property string editSystemPrompt: pluginApi?.pluginSettings?.systemPrompt || pluginApi?.manifest?.metadata?.defaultSettings?.systemPrompt || ""
  property string editLanguage: pluginApi?.pluginSettings?.language || "auto"
  property int editMaxHistoryLength: pluginApi?.pluginSettings?.maxHistoryLength || 50

  // Live / VAD Settings
  property bool editLiveMode: pluginApi?.pluginSettings?.liveMode ?? true
  property real editVadSilenceDb: pluginApi?.pluginSettings?.vadSilenceDb ?? -30
  property real editVadSilenceSec: pluginApi?.pluginSettings?.vadSilenceSec ?? 1.0
  property real editVadMinSpeechSec: pluginApi?.pluginSettings?.vadMinSpeechSec ?? 0.7
  property real editVadMaxSpeechSec: pluginApi?.pluginSettings?.vadMaxSpeechSec ?? 10.0

  // Panel Settings
  property bool editPanelDetached: pluginApi?.pluginSettings?.panelDetached ?? true
  property string editPanelPosition: pluginApi?.pluginSettings?.panelPosition || "center"
  property real editPanelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio || 0.75
  property int editPanelWidth: pluginApi?.pluginSettings?.panelWidth ?? 520

  // Env key detection
  readonly property string envGroqKey: Quickshell.env("WHISPER_GROQ_API_KEY") || ""
  readonly property string envAnthropicKey: Quickshell.env("WHISPER_ANTHROPIC_API_KEY") || ""
  readonly property string envGoogleKey: Quickshell.env("WHISPER_GOOGLE_API_KEY") || ""

  function isKeyManagedByEnv(provider) {
    if (provider === "groq") return envGroqKey !== "";
    if (provider === "anthropic") return envAnthropicKey !== "";
    if (provider === "google") return envGoogleKey !== "";
    return false;
  }

  function t(key, fallback) {
    return Logic.cleanTr(pluginApi ? pluginApi.tr(key) : null, fallback);
  }

  spacing: Style.marginM

  Component.onCompleted: {
    Logger.i("Whisper", "Settings UI loaded");
  }

  // ==================
  // STT Section
  // ==================
  NText {
    text: root.t("settings.sttSection", "Speech-to-Text")
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NText {
    Layout.fillWidth: true
    text: root.t("settings.sttNote", "Speech recognition is powered by Groq's Whisper API (free tier available).")
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
    wrapMode: Text.Wrap
  }

  // Groq API Key (required for STT)
  NTextInput {
    Layout.fillWidth: true
    label: root.t("settings.groqApiKey", "Groq API Key")
    description: {
      if (isKeyManagedByEnv("groq")) return root.t("settings.keyManagedByEnv", "Managed via WHISPER_GROQ_API_KEY env variable");
      return root.t("settings.groqApiKeyDesc", "Get your free key at") + ": " + Logic.LlmProviderConfig.groq.keyUrl;
    }
    placeholderText: isKeyManagedByEnv("groq") ? root.t("settings.envPlaceholder", "Set via environment variable") : root.t("settings.apiKeyPlaceholder", "Enter API key...")
    text: isKeyManagedByEnv("groq") ? "" : (editApiKeys["groq"] || "")
    enabled: !isKeyManagedByEnv("groq")
    inputMethodHints: Qt.ImhHiddenText
    onTextChanged: {
      if (!isKeyManagedByEnv("groq")) {
        editApiKeys = Object.assign({}, editApiKeys, { "groq": text });
      }
    }
  }

  // Language
  NComboBox {
    Layout.fillWidth: true
    label: root.t("settings.language", "Speech Language")
    description: root.t("settings.languageDesc", "Language for speech recognition")
    model: [
      { key: "en", name: "English" },
      { key: "es", name: "Spanish" },
      { key: "fr", name: "French" },
      { key: "de", name: "German" },
      { key: "it", name: "Italian" },
      { key: "pt", name: "Portuguese" },
      { key: "nl", name: "Dutch" },
      { key: "ja", name: "Japanese" },
      { key: "ko", name: "Korean" },
      { key: "zh", name: "Chinese" },
      { key: "ar", name: "Arabic" },
      { key: "ru", name: "Russian" },
      { key: "auto", name: "Auto-detect" }
    ]
    currentKey: root.editLanguage
    onSelected: function (key) { root.editLanguage = key; }
    defaultValue: "en"
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  // ==================
  // LLM Section
  // ==================
  NText {
    text: root.t("settings.llmSection", "AI Model")
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  // LLM Provider
  NComboBox {
    Layout.fillWidth: true
    label: root.t("settings.llmProvider", "AI Provider")
    description: root.t("settings.llmProviderDesc", "Choose which AI model to use for responses")
    model: [
      { key: "groq", name: "Groq (Free)" },
      { key: "anthropic", name: "Anthropic Claude" },
      { key: "google", name: "Google Gemini (Free)" }
    ]
    currentKey: root.editLlmProvider
    onSelected: function (key) { root.editLlmProvider = key; }
    defaultValue: "groq"
  }

  // Model name
  NTextInput {
    Layout.fillWidth: true
    label: root.t("settings.model", "Model")
    description: root.t("settings.modelDesc", "Leave empty for default model")
    text: root.editLlmModel
    placeholderText: Logic.LlmProviderConfig[root.editLlmProvider]?.defaultModel || ""
    onTextChanged: root.editLlmModel = text
  }

  // Anthropic API Key (only when Anthropic selected)
  NTextInput {
    Layout.fillWidth: true
    visible: root.editLlmProvider === "anthropic"
    label: root.t("settings.anthropicApiKey", "Anthropic API Key")
    description: {
      if (isKeyManagedByEnv("anthropic")) return root.t("settings.keyManagedByEnv", "Managed via WHISPER_ANTHROPIC_API_KEY env variable");
      return root.t("settings.anthropicApiKeyDesc", "Get key at") + ": " + Logic.LlmProviderConfig.anthropic.keyUrl;
    }
    placeholderText: isKeyManagedByEnv("anthropic") ? root.t("settings.envPlaceholder", "Set via environment variable") : root.t("settings.apiKeyPlaceholder", "Enter API key...")
    text: isKeyManagedByEnv("anthropic") ? "" : (editApiKeys["anthropic"] || "")
    enabled: !isKeyManagedByEnv("anthropic")
    inputMethodHints: Qt.ImhHiddenText
    onTextChanged: {
      if (!isKeyManagedByEnv("anthropic")) {
        editApiKeys = Object.assign({}, editApiKeys, { "anthropic": text });
      }
    }
  }

  // Google API Key (only when Google selected)
  NTextInput {
    Layout.fillWidth: true
    visible: root.editLlmProvider === "google"
    label: root.t("settings.googleApiKey", "Google API Key")
    description: {
      if (isKeyManagedByEnv("google")) return root.t("settings.keyManagedByEnv", "Managed via WHISPER_GOOGLE_API_KEY env variable");
      return root.t("settings.googleApiKeyDesc", "Get key at") + ": " + Logic.LlmProviderConfig.google.keyUrl;
    }
    placeholderText: isKeyManagedByEnv("google") ? root.t("settings.envPlaceholder", "Set via environment variable") : root.t("settings.apiKeyPlaceholder", "Enter API key...")
    text: isKeyManagedByEnv("google") ? "" : (editApiKeys["google"] || "")
    enabled: !isKeyManagedByEnv("google")
    inputMethodHints: Qt.ImhHiddenText
    onTextChanged: {
      if (!isKeyManagedByEnv("google")) {
        editApiKeys = Object.assign({}, editApiKeys, { "google": text });
      }
    }
  }

  // Temperature
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: root.t("settings.temperature", "Temperature") + ": " + root.editTemperature.toFixed(1)
      description: root.t("settings.temperatureDesc", "Higher = more creative, Lower = more focused")
    }

    NSlider {
      Layout.fillWidth: true
      from: 0
      to: 2
      stepSize: 0.1
      value: root.editTemperature
      onValueChanged: root.editTemperature = value
    }
  }

  // System prompt
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: root.t("settings.systemPrompt", "System Prompt")
      description: root.t("settings.systemPromptDesc", "Instructions for the AI assistant")
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 140
      color: Color.mSurface
      radius: Style.radiusS
      border.color: Color.mOutline
      border.width: 1

      TextArea {
        anchors.fill: parent
        anchors.margins: Style.marginS
        text: root.editSystemPrompt
        placeholderText: root.t("settings.systemPromptPlaceholder", "You are a helpful assistant...")
        placeholderTextColor: Color.mOnSurfaceVariant
        color: Color.mOnSurface
        font.pointSize: Style.fontSizeS
        wrapMode: TextArea.Wrap
        background: null
        onTextChanged: root.editSystemPrompt = text
      }
    }
  }

  // Max history
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: root.t("settings.maxHistory", "Max History") + ": " + root.editMaxHistoryLength
      description: root.t("settings.maxHistoryDesc", "Maximum number of messages to keep in history")
    }

    NSlider {
      Layout.fillWidth: true
      from: 10
      to: 200
      stepSize: 10
      value: root.editMaxHistoryLength
      onValueChanged: root.editMaxHistoryLength = value
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  // ==================
  // Live Mode Section
  // ==================
  NText {
    text: root.t("settings.liveSection", "Live Mode")
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NToggle {
    Layout.fillWidth: true
    label: root.t("settings.liveModeDefault", "Start in Live mode")
    description: root.t("settings.liveModeDefaultDesc", "When enabled, the keybind (IPC 'toggle') auto-starts continuous listening. Requires ffmpeg + pulseaudio/PipeWire-pulse.")
    checked: root.editLiveMode
    onToggled: function (checked) { root.editLiveMode = checked; }
    defaultValue: true
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: root.t("settings.vadSilenceDb", "Silence threshold") + ": " + root.editVadSilenceDb.toFixed(0) + " dB"
      description: root.t("settings.vadSilenceDbDesc", "Quieter than this counts as silence. -15 = sensitive, -40 = needs clear voice.")
    }

    NSlider {
      Layout.fillWidth: true
      from: -60
      to: -10
      stepSize: 1
      value: root.editVadSilenceDb
      onValueChanged: root.editVadSilenceDb = value
    }

    NLabel {
      label: root.t("settings.vadSilenceSec", "Pause duration") + ": " + root.editVadSilenceSec.toFixed(1) + "s"
      description: root.t("settings.vadSilenceSecDesc", "How long you must pause before the assistant answers.")
    }

    NSlider {
      Layout.fillWidth: true
      from: 0.3
      to: 3.0
      stepSize: 0.1
      value: root.editVadSilenceSec
      onValueChanged: root.editVadSilenceSec = value
    }

    NLabel {
      label: root.t("settings.vadMinSpeechSec", "Min speech length") + ": " + root.editVadMinSpeechSec.toFixed(1) + "s"
      description: root.t("settings.vadMinSpeechSecDesc", "Ignore speech bursts shorter than this (filters coughs, clicks).")
    }

    NSlider {
      Layout.fillWidth: true
      from: 0.1
      to: 2.0
      stepSize: 0.1
      value: root.editVadMinSpeechSec
      onValueChanged: root.editVadMinSpeechSec = value
    }

    NLabel {
      label: root.t("settings.vadMaxSpeechSec", "Max speech length") + ": " + root.editVadMaxSpeechSec.toFixed(0) + "s"
      description: root.t("settings.vadMaxSpeechSecDesc", "Force a chunk break after this many seconds of continuous speech.")
    }

    NSlider {
      Layout.fillWidth: true
      from: 4
      to: 30
      stepSize: 1
      value: root.editVadMaxSpeechSec
      onValueChanged: root.editVadMaxSpeechSec = value
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  // ==================
  // Panel Section
  // ==================
  NText {
    text: root.t("settings.panelSection", "Panel Layout")
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NToggle {
    Layout.fillWidth: true
    label: root.t("settings.panelDetached", "Detached Panel")
    description: root.t("settings.panelDetachedDesc", "Panel floats freely instead of attaching to bar")
    checked: root.editPanelDetached
    onToggled: function (checked) {
      root.editPanelDetached = checked;
      if (checked && (root.editPanelPosition === "top" || root.editPanelPosition === "bottom")) {
        root.editPanelPosition = "center";
      }
    }
    defaultValue: true
  }

  NComboBox {
    Layout.fillWidth: true
    label: root.t("settings.panelPosition", "Panel Position")
    description: root.t("settings.panelPositionDesc", "Where the panel appears on screen")
    model: root.editPanelDetached ? [
      { key: "left", name: "Left" },
      { key: "center", name: "Center" },
      { key: "right", name: "Right" }
    ] : [
      { key: "left", name: "Left" },
      { key: "top", name: "Top" },
      { key: "bottom", name: "Bottom" },
      { key: "right", name: "Right" }
    ]
    currentKey: root.editPanelPosition
    onSelected: function (key) { root.editPanelPosition = key; }
    defaultValue: "center"
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: root.t("settings.panelHeightRatio", "Panel Height") + ": " + (root.editPanelHeightRatio * 100).toFixed(0) + "%"
      description: root.t("settings.panelHeightRatioDesc", "Percentage of screen height")
    }

    NSlider {
      Layout.fillWidth: true
      from: 0.3
      to: 1.0
      stepSize: 0.01
      value: root.editPanelHeightRatio
      onValueChanged: root.editPanelHeightRatio = value
    }

    NLabel {
      label: root.t("settings.panelWidth", "Panel Width") + ": " + root.editPanelWidth + "px"
      description: root.t("settings.panelWidthDesc", "Width of the panel in pixels")
    }

    NSlider {
      Layout.fillWidth: true
      from: 320
      to: 1200
      stepSize: 1
      value: root.editPanelWidth
      onValueChanged: root.editPanelWidth = value
    }
  }

  // ==================
  // IPC Info
  // ==================
  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  NText {
    text: root.t("settings.ipcSection", "Keyboard Shortcut")
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NText {
    Layout.fillWidth: true
    text: root.t("settings.ipcNote", "Bind this command to a keyboard shortcut in your compositor:\nqs -c noctalia-shell ipc call plugin:whisper toggle")
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
    wrapMode: Text.Wrap
  }

  function saveSettings() {
    if (!pluginApi) {
      Logger.e("Whisper", "Cannot save settings: pluginApi is null");
      return;
    }

    pluginApi.pluginSettings.sttProvider = root.editSttProvider;
    pluginApi.pluginSettings.llmProvider = root.editLlmProvider;
    pluginApi.pluginSettings.llmModel = root.editLlmModel;
    pluginApi.pluginSettings.apiKeys = root.editApiKeys;
    pluginApi.pluginSettings.temperature = root.editTemperature;
    pluginApi.pluginSettings.systemPrompt = root.editSystemPrompt;
    pluginApi.pluginSettings.language = root.editLanguage;
    pluginApi.pluginSettings.maxHistoryLength = root.editMaxHistoryLength;
    pluginApi.pluginSettings.liveMode = root.editLiveMode;
    pluginApi.pluginSettings.vadSilenceDb = root.editVadSilenceDb;
    pluginApi.pluginSettings.vadSilenceSec = root.editVadSilenceSec;
    pluginApi.pluginSettings.vadMinSpeechSec = root.editVadMinSpeechSec;
    pluginApi.pluginSettings.vadMaxSpeechSec = root.editVadMaxSpeechSec;
    pluginApi.pluginSettings.panelDetached = root.editPanelDetached;
    pluginApi.pluginSettings.panelPosition = root.editPanelPosition;
    pluginApi.pluginSettings.panelHeightRatio = root.editPanelHeightRatio;
    pluginApi.pluginSettings.panelWidth = root.editPanelWidth;

    pluginApi.saveSettings();
    Logger.i("Whisper", "Settings saved successfully");
  }
}
