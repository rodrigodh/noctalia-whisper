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
  property real editTemperature: pluginApi?.pluginSettings?.temperature || 0.7
  property string editSystemPrompt: pluginApi?.pluginSettings?.systemPrompt || pluginApi?.manifest?.metadata?.defaultSettings?.systemPrompt || ""
  property string editLanguage: pluginApi?.pluginSettings?.language || "en"
  property int editMaxHistoryLength: pluginApi?.pluginSettings?.maxHistoryLength || 50

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

  spacing: Style.marginM

  Component.onCompleted: {
    Logger.i("Whisper", "Settings UI loaded");
  }

  // ==================
  // STT Section
  // ==================
  NText {
    text: pluginApi?.tr("settings.sttSection") || "Speech-to-Text"
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NText {
    Layout.fillWidth: true
    text: pluginApi?.tr("settings.sttNote") || "Speech recognition is powered by Groq's Whisper API (free tier available)."
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeXS
    wrapMode: Text.Wrap
  }

  // Groq API Key (required for STT)
  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.groqApiKey") || "Groq API Key"
    description: {
      if (isKeyManagedByEnv("groq")) return pluginApi?.tr("settings.keyManagedByEnv") || "Managed via WHISPER_GROQ_API_KEY env variable";
      return (pluginApi?.tr("settings.groqApiKeyDesc") || "Get your free key at") + ": " + Logic.LlmProviderConfig.groq.keyUrl;
    }
    placeholderText: isKeyManagedByEnv("groq") ? (pluginApi?.tr("settings.envPlaceholder") || "Set via environment variable") : (pluginApi?.tr("settings.apiKeyPlaceholder") || "Enter API key...")
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
    label: pluginApi?.tr("settings.language") || "Speech Language"
    description: pluginApi?.tr("settings.languageDesc") || "Language for speech recognition"
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
    text: pluginApi?.tr("settings.llmSection") || "AI Model"
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  // LLM Provider
  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.llmProvider") || "AI Provider"
    description: pluginApi?.tr("settings.llmProviderDesc") || "Choose which AI model to use for responses"
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
    label: pluginApi?.tr("settings.model") || "Model"
    description: pluginApi?.tr("settings.modelDesc") || "Leave empty for default model"
    text: root.editLlmModel
    placeholderText: Logic.LlmProviderConfig[root.editLlmProvider]?.defaultModel || ""
    onTextChanged: root.editLlmModel = text
  }

  // Anthropic API Key (only when Anthropic selected)
  NTextInput {
    Layout.fillWidth: true
    visible: root.editLlmProvider === "anthropic"
    label: pluginApi?.tr("settings.anthropicApiKey") || "Anthropic API Key"
    description: {
      if (isKeyManagedByEnv("anthropic")) return pluginApi?.tr("settings.keyManagedByEnv") || "Managed via WHISPER_ANTHROPIC_API_KEY env variable";
      return (pluginApi?.tr("settings.anthropicApiKeyDesc") || "Get key at") + ": " + Logic.LlmProviderConfig.anthropic.keyUrl;
    }
    placeholderText: isKeyManagedByEnv("anthropic") ? (pluginApi?.tr("settings.envPlaceholder") || "Set via environment variable") : (pluginApi?.tr("settings.apiKeyPlaceholder") || "Enter API key...")
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
    label: pluginApi?.tr("settings.googleApiKey") || "Google API Key"
    description: {
      if (isKeyManagedByEnv("google")) return pluginApi?.tr("settings.keyManagedByEnv") || "Managed via WHISPER_GOOGLE_API_KEY env variable";
      return (pluginApi?.tr("settings.googleApiKeyDesc") || "Get key at") + ": " + Logic.LlmProviderConfig.google.keyUrl;
    }
    placeholderText: isKeyManagedByEnv("google") ? (pluginApi?.tr("settings.envPlaceholder") || "Set via environment variable") : (pluginApi?.tr("settings.apiKeyPlaceholder") || "Enter API key...")
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
      label: (pluginApi?.tr("settings.temperature") || "Temperature") + ": " + root.editTemperature.toFixed(1)
      description: pluginApi?.tr("settings.temperatureDesc") || "Higher = more creative, Lower = more focused"
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
      label: pluginApi?.tr("settings.systemPrompt") || "System Prompt"
      description: pluginApi?.tr("settings.systemPromptDesc") || "Instructions for the AI assistant"
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 100
      color: Color.mSurface
      radius: Style.radiusS
      border.color: Color.mOutline
      border.width: 1

      TextArea {
        anchors.fill: parent
        anchors.margins: Style.marginS
        text: root.editSystemPrompt
        placeholderText: pluginApi?.tr("settings.systemPromptPlaceholder") || "You are a helpful assistant..."
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
      label: (pluginApi?.tr("settings.maxHistory") || "Max History") + ": " + root.editMaxHistoryLength
      description: pluginApi?.tr("settings.maxHistoryDesc") || "Maximum number of messages to keep in history"
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
  // Panel Section
  // ==================
  NText {
    text: pluginApi?.tr("settings.panelSection") || "Panel Layout"
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.panelDetached") || "Detached Panel"
    description: pluginApi?.tr("settings.panelDetachedDesc") || "Panel floats freely instead of attaching to bar"
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
    label: pluginApi?.tr("settings.panelPosition") || "Panel Position"
    description: pluginApi?.tr("settings.panelPositionDesc") || "Where the panel appears on screen"
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
      label: (pluginApi?.tr("settings.panelHeightRatio") || "Panel Height") + ": " + (root.editPanelHeightRatio * 100).toFixed(0) + "%"
      description: pluginApi?.tr("settings.panelHeightRatioDesc") || "Percentage of screen height"
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
      label: (pluginApi?.tr("settings.panelWidth") || "Panel Width") + ": " + root.editPanelWidth + "px"
      description: pluginApi?.tr("settings.panelWidthDesc") || "Width of the panel in pixels"
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
    text: pluginApi?.tr("settings.ipcSection") || "Keyboard Shortcut"
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NText {
    Layout.fillWidth: true
    text: pluginApi?.tr("settings.ipcNote") || "Bind this command to a keyboard shortcut in your compositor:\nqs -c noctalia-shell ipc call plugin:whisper toggle"
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
    pluginApi.pluginSettings.panelDetached = root.editPanelDetached;
    pluginApi.pluginSettings.panelPosition = root.editPanelPosition;
    pluginApi.pluginSettings.panelHeightRatio = root.editPanelHeightRatio;
    pluginApi.pluginSettings.panelWidth = root.editPanelWidth;

    pluginApi.saveSettings();
    Logger.i("Whisper", "Settings saved successfully");
  }
}
