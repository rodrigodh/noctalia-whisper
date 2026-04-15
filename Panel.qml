import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null

  // Standard panel properties
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: !_detached

  readonly property bool _detached: pluginApi?.pluginSettings?.panelDetached ?? true
  readonly property string _panelPosition: pluginApi?.pluginSettings?.panelPosition ?? "center"

  readonly property bool panelAnchorRight: _panelPosition === "right"
  readonly property bool panelAnchorLeft: _panelPosition === "left"
  readonly property bool panelAnchorHorizontalCenter: _detached && _panelPosition === "center"
  readonly property bool panelAnchorVerticalCenter: _detached

  property int _panelWidth: pluginApi?.pluginSettings?.panelWidth ?? 520
  property real _panelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio ?? 0.75
  property real contentPreferredWidth: _panelWidth
  property real contentPreferredHeight: screen ? (screen.height * _panelHeightRatio) : 620 * Style.uiScaleRatio

  anchors.fill: parent

  readonly property var mainInstance: pluginApi?.mainInstance

  // State from main instance
  readonly property bool isRecording: mainInstance?.isRecording || false
  readonly property bool isTranscribing: mainInstance?.isTranscribing || false
  readonly property bool isGenerating: mainInstance?.isGenerating || false
  readonly property string currentResponse: mainInstance?.currentResponse || ""
  readonly property string transcribedText: mainInstance?.transcribedText || ""
  readonly property string transcriptionError: mainInstance?.transcriptionError || ""
  readonly property string errorMessage: mainInstance?.errorMessage || ""
  readonly property var messages: mainInstance?.messages || []
  readonly property real recordingDuration: mainInstance?.recordingDuration || 0

  // Focus input when panel shows
  onVisibleChanged: {
    if (visible) {
      Qt.callLater(function () {
        if (inputField) inputField.forceActiveFocus();
      });
    } else {
      // Cancel recording when panel closes
      if (mainInstance && mainInstance.isRecording) {
        mainInstance.cancelRecording();
      }
    }
  }

  Rectangle {
    id: panelContainer
    width: contentPreferredWidth
    height: contentPreferredHeight
    color: "transparent"
    anchors.horizontalCenter: (_detached && _panelPosition === "center" && parent) ? parent.horizontalCenter : undefined
    anchors.verticalCenter: (_detached && _panelPosition === "center" && parent) ? parent.verticalCenter : undefined
    y: (_detached && (_panelPosition === "left" || _panelPosition === "right")) ? (root.height - contentPreferredHeight) / 2 : 0

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      // ==================
      // Header
      // ==================
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: headerRow.implicitHeight + Style.marginM * 2
        color: Color.mSurfaceVariant
        radius: Style.radiusM

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          NIcon {
            icon: "microphone"
            color: Color.mPrimary
            pointSize: Style.fontSizeL
          }

          NText {
            Layout.fillWidth: true
            text: pluginApi?.tr("panel.title") || "Whisper"
            font.weight: Style.fontWeightBold
            pointSize: Style.fontSizeL
            color: Color.mOnSurface
          }

          // Provider badge
          NText {
            text: {
              var provider = mainInstance?.llmProvider || "groq";
              if (provider === "groq") return "Groq";
              if (provider === "anthropic") return "Claude";
              if (provider === "google") return "Gemini";
              return provider;
            }
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeXS
          }

          // Clear history button
          NIconButton {
            icon: "trash"
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              if (mainInstance) mainInstance.clearMessages();
            }
          }
        }
      }

      // ==================
      // Recording Indicator
      // ==================
      Rectangle {
        id: recordingIndicator
        Layout.fillWidth: true
        Layout.preferredHeight: recordingContent.implicitHeight + Style.marginL * 2
        visible: root.isRecording || root.isTranscribing
        color: root.isRecording ? Qt.alpha(Color.mError, 0.1) : Qt.alpha(Color.mPrimary, 0.1)
        radius: Style.radiusL
        border.color: root.isRecording ? Qt.alpha(Color.mError, 0.3) : Qt.alpha(Color.mPrimary, 0.3)
        border.width: 1

        ColumnLayout {
          id: recordingContent
          anchors.centerIn: parent
          spacing: Style.marginM

          // Animated recording dot
          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.marginS

            Rectangle {
              id: recordingDot
              width: 12
              height: 12
              radius: 6
              color: root.isRecording ? Color.mError : Color.mPrimary
              visible: root.isRecording

              SequentialAnimation on opacity {
                running: root.isRecording
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.2; duration: 500; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.2; to: 1.0; duration: 500; easing.type: Easing.InOutSine }
              }
            }

            NIcon {
              visible: root.isTranscribing
              icon: "loader-2"
              color: Color.mPrimary
              pointSize: Style.fontSizeL

              RotationAnimation on rotation {
                running: root.isTranscribing
                from: 0; to: 360; duration: 1000; loops: Animation.Infinite
              }
            }

            NText {
              text: {
                if (root.isRecording) {
                  var secs = Math.floor(root.recordingDuration);
                  var mins = Math.floor(secs / 60);
                  secs = secs % 60;
                  return (pluginApi?.tr("panel.recording") || "Recording") + "  " +
                    (mins < 10 ? "0" : "") + mins + ":" + (secs < 10 ? "0" : "") + secs;
                }
                if (root.isTranscribing) {
                  return pluginApi?.tr("panel.transcribing") || "Transcribing...";
                }
                return "";
              }
              color: root.isRecording ? Color.mError : Color.mPrimary
              pointSize: Style.fontSizeM
              font.weight: Style.fontWeightBold
            }
          }

          // Audio level visualization (simple bars)
          Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 3
            visible: root.isRecording

            Repeater {
              model: 12
              Rectangle {
                width: 4
                height: {
                  // Animated random heights to simulate audio levels
                  var base = 8;
                  var max = 28;
                  return base + Math.random() * (max - base);
                }
                radius: 2
                color: Color.mError
                opacity: 0.7

                // Re-randomize heights periodically
                Timer {
                  interval: 100 + Math.random() * 100
                  repeat: true
                  running: root.isRecording
                  onTriggered: parent.height = 8 + Math.random() * 20
                }

                Behavior on height {
                  NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                }
              }
            }
          }

          // Stop button
          NButton {
            Layout.alignment: Qt.AlignHCenter
            visible: root.isRecording
            text: pluginApi?.tr("panel.stopRecording") || "Stop & Send"
            backgroundColor: Color.mError
            textColor: Color.mOnPrimary
            hoverColor: Qt.lighter(Color.mError, 1.2)
            textHoverColor: Color.mOnPrimary
            onClicked: {
              if (mainInstance) mainInstance.stopRecording();
            }
          }
        }
      }

      // ==================
      // Chat Messages Area
      // ==================
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant
        radius: Style.radiusL
        clip: true

        // Empty state
        Item {
          anchors.fill: parent
          visible: messages.length === 0 && !root.isGenerating && !root.isRecording && !root.isTranscribing

          ColumnLayout {
            anchors.centerIn: parent
            spacing: Style.marginM

            NIcon {
              Layout.alignment: Qt.AlignHCenter
              icon: "microphone"
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXXL * 2
              applyUiScale: false
            }

            NText {
              Layout.alignment: Qt.AlignHCenter
              text: pluginApi?.tr("panel.emptyTitle") || "Ready to listen"
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeM
              applyUiScale: false
              font.weight: Font.Medium
            }

            NText {
              Layout.alignment: Qt.AlignHCenter
              text: pluginApi?.tr("panel.emptyHint") || "Click the record button or use your keyboard shortcut"
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              applyUiScale: false
            }
          }
        }

        // Chat Flickable
        Flickable {
          id: chatFlickable
          anchors.fill: parent
          anchors.margins: Style.marginS
          contentWidth: width
          contentHeight: messageColumn.height
          clip: true
          visible: messages.length > 0 || root.isGenerating
          boundsBehavior: Flickable.StopAtBounds

          property real wheelScrollMultiplier: 4.0
          property bool autoScrollEnabled: true

          readonly property bool isNearBottom: {
            if (contentHeight <= height) return true;
            return contentY >= contentHeight - height - 30;
          }

          function scrollToBottom() {
            if (contentHeight > height) {
              contentY = contentHeight - height;
            }
          }

          onContentHeightChanged: {
            if (autoScrollEnabled && contentHeight > height) {
              scrollToBottom();
            }
          }

          onMovementEnded: autoScrollEnabled = isNearBottom
          onFlickEnded: autoScrollEnabled = isNearBottom

          WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
              const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8;
              const newY = chatFlickable.contentY - (delta * chatFlickable.wheelScrollMultiplier);
              chatFlickable.contentY = Math.max(0, Math.min(newY, chatFlickable.contentHeight - chatFlickable.height));
              chatFlickable.autoScrollEnabled = chatFlickable.isNearBottom;
              event.accepted = true;
            }
          }

          Column {
            id: messageColumn
            width: chatFlickable.width
            spacing: Style.marginM

            Repeater {
              model: messages

              MessageBubble {
                width: messageColumn.width
                message: modelData
                pluginApi: root.pluginApi
                onCopyRequested: function (text) {
                  Quickshell.clipboardText = text;
                  ToastService.showNotice(pluginApi?.tr("toast.copied") || "Copied!");
                }
              }
            }

            // Streaming response bubble
            MessageBubble {
              width: messageColumn.width
              visible: root.isGenerating && currentResponse.trim() !== ""
              pluginApi: root.pluginApi
              message: ({
                id: "streaming",
                role: "assistant",
                content: currentResponse,
                isStreaming: true
              })
            }
          }
        }

        // Scroll to bottom button
        Rectangle {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.marginM
          width: 32
          height: 32
          radius: width / 2
          color: Color.mPrimary
          visible: !chatFlickable.autoScrollEnabled && messages.length > 0

          NIcon {
            anchors.centerIn: parent
            icon: "chevron-down"
            color: Color.mOnPrimary
            pointSize: Style.fontSizeM
            applyUiScale: false
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              chatFlickable.autoScrollEnabled = true;
              chatFlickable.scrollToBottom();
            }
          }
        }
      }

      // ==================
      // Error Display
      // ==================
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: errorRow.implicitHeight + Style.marginS * 2
        visible: (root.errorMessage !== "" || root.transcriptionError !== "")
        color: Qt.alpha(Color.mError, 0.2)
        radius: Style.radiusS

        RowLayout {
          id: errorRow
          anchors.fill: parent
          anchors.margins: Style.marginS
          spacing: Style.marginS

          NIcon {
            icon: "alert-triangle"
            color: Color.mError
            pointSize: Style.fontSizeM
          }

          NText {
            Layout.fillWidth: true
            text: root.transcriptionError || root.errorMessage
            color: Color.mError
            pointSize: Style.fontSizeS
            wrapMode: Text.Wrap
          }
        }
      }

      // ==================
      // Input Area
      // ==================
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: inputLayout.implicitHeight + Style.marginS * 2
        color: Color.mSurface
        radius: Style.radiusM

        RowLayout {
          id: inputLayout
          anchors.fill: parent
          anchors.margins: Style.marginS
          spacing: Style.marginS

          // Record button
          Rectangle {
            width: 40
            height: 40
            radius: 20
            color: {
              if (root.isRecording) return Color.mError;
              if (recordBtnMouse.containsMouse) return Qt.alpha(Color.mPrimary, 0.2);
              return Qt.alpha(Color.mPrimary, 0.1);
            }

            Behavior on color {
              ColorAnimation { duration: 150 }
            }

            NIcon {
              anchors.centerIn: parent
              icon: root.isRecording ? "player-stop" : "microphone"
              color: root.isRecording ? Color.mOnPrimary : Color.mPrimary
              pointSize: Style.fontSizeM
            }

            MouseArea {
              id: recordBtnMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: !root.isTranscribing
              onClicked: {
                if (mainInstance) mainInstance.toggleRecording();
              }
            }

            ToolTip.visible: recordBtnMouse.containsMouse
            ToolTip.text: root.isRecording
              ? (pluginApi?.tr("panel.stopRecording") || "Stop Recording")
              : (pluginApi?.tr("panel.startRecording") || "Start Recording")
          }

          // Text input
          ScrollView {
            Layout.fillWidth: true
            Layout.maximumHeight: 100

            TextArea {
              id: inputField
              text: mainInstance?.chatInputText || ""
              placeholderText: pluginApi?.tr("panel.placeholder") || "Type a message or press record..."
              placeholderTextColor: Color.mOnSurfaceVariant
              color: Color.mOnSurface
              font.pointSize: Style.fontSizeM
              wrapMode: TextArea.Wrap
              background: null
              selectByMouse: true
              enabled: !root.isGenerating && !root.isRecording && !root.isTranscribing

              onTextChanged: {
                if (mainInstance && mainInstance.chatInputText !== text) {
                  mainInstance.chatInputText = text;
                  mainInstance.saveState();
                }
              }

              Keys.onReturnPressed: function (event) {
                if (event.modifiers & Qt.ShiftModifier) {
                  inputField.insert(inputField.cursorPosition, "\n");
                } else {
                  sendTypedMessage();
                }
                event.accepted = true;
              }
            }
          }

          // Send / Stop button
          NIconButton {
            icon: root.isGenerating ? "player-stop" : "send"
            colorFg: root.isGenerating ? Color.mError : (inputField.text.trim() !== "" ? Color.mPrimary : Color.mOnSurfaceVariant)
            enabled: root.isGenerating || inputField.text.trim() !== ""
            tooltipText: root.isGenerating
              ? (pluginApi?.tr("panel.stopGenerating") || "Stop")
              : (pluginApi?.tr("panel.send") || "Send")
            onClicked: {
              if (root.isGenerating) {
                if (mainInstance) mainInstance.stopGeneration();
              } else {
                sendTypedMessage();
              }
            }
          }
        }
      }
    }
  }

  function sendTypedMessage() {
    var text = inputField.text.trim();
    if (text === "" || !mainInstance) return;
    mainInstance.sendMessage(text);
    inputField.text = "";
    if (mainInstance) {
      mainInstance.chatInputText = "";
      mainInstance.saveState();
    }
    inputField.forceActiveFocus();
  }
}
