import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import "WhisperLogic.js" as Logic

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
  readonly property bool isLive: mainInstance?.isLive || false
  readonly property bool isTranscribing: mainInstance?.isTranscribing || false
  readonly property bool isGenerating: mainInstance?.isGenerating || false
  readonly property string currentResponse: mainInstance?.currentResponse || ""
  readonly property string transcribedText: mainInstance?.transcribedText || ""
  readonly property string transcriptionError: mainInstance?.transcriptionError || ""
  readonly property string errorMessage: mainInstance?.errorMessage || ""
  readonly property var messages: mainInstance?.messages || []
  readonly property real recordingDuration: mainInstance?.recordingDuration || 0
  readonly property string lastHeardText: mainInstance?.lastHeardText || ""

  // i18n helper: prefer Main's t() (which cleans !!key!! misses); inline fallback if mainInstance not ready.
  function t(key, fallback) {
    if (mainInstance && mainInstance.t) return mainInstance.t(key, fallback);
    return Logic.cleanTr(pluginApi ? pluginApi.tr(key) : null, fallback);
  }

  // Focus input when panel shows
  onVisibleChanged: {
    if (visible) {
      Qt.callLater(function () {
        if (inputField) inputField.forceActiveFocus();
      });
    } else {
      if (mainInstance) {
        if (mainInstance.isLive) mainInstance.stopLive();
        if (mainInstance.isRecording) mainInstance.cancelRecording();
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
            color: root.isLive ? Color.mError : Color.mPrimary
            pointSize: Style.fontSizeL
          }

          NText {
            Layout.fillWidth: true
            text: root.t("panel.title", "Whisper")
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

          // ==== Live toggle pill ====
          Rectangle {
            id: liveBtn
            Layout.preferredHeight: 28
            Layout.preferredWidth: liveRow.implicitWidth + Style.marginM * 2
            radius: height / 2
            color: root.isLive
              ? Color.mError
              : (liveBtnMouse.containsMouse ? Qt.alpha(Color.mError, 0.18) : Qt.alpha(Color.mError, 0.08))
            border.color: root.isLive ? Color.mError : Qt.alpha(Color.mError, 0.4)
            border.width: 1

            Behavior on color { ColorAnimation { duration: 150 } }

            RowLayout {
              id: liveRow
              anchors.centerIn: parent
              spacing: 6

              Rectangle {
                width: 8
                height: 8
                radius: 4
                color: root.isLive ? Color.mOnPrimary : Color.mError
                SequentialAnimation on opacity {
                  running: root.isLive
                  loops: Animation.Infinite
                  NumberAnimation { from: 1.0; to: 0.25; duration: 500; easing.type: Easing.InOutSine }
                  NumberAnimation { from: 0.25; to: 1.0; duration: 500; easing.type: Easing.InOutSine }
                }
              }

              NText {
                text: root.isLive
                  ? root.t("panel.liveOn", "LIVE")
                  : root.t("panel.liveStart", "Start Live")
                color: root.isLive ? Color.mOnPrimary : Color.mError
                pointSize: Style.fontSizeXS
                font.weight: Style.fontWeightBold
              }
            }

            MouseArea {
              id: liveBtnMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (mainInstance) mainInstance.toggleLive();
              }
            }

            ToolTip.visible: liveBtnMouse.containsMouse
            ToolTip.text: root.isLive
              ? root.t("panel.liveStop", "Stop Live")
              : root.t("panel.liveStart", "Start Live")
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
      // Live status strip (what we last heard)
      // ==================
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: heardRow.implicitHeight + Style.marginS * 2
        visible: root.isLive && root.lastHeardText !== ""
        color: Qt.alpha(Color.mPrimary, 0.08)
        radius: Style.radiusS
        border.color: Qt.alpha(Color.mPrimary, 0.25)
        border.width: 1

        RowLayout {
          id: heardRow
          anchors.fill: parent
          anchors.margins: Style.marginS
          spacing: Style.marginS

          NText {
            text: root.t("panel.heardLabel", "Heard") + ":"
            color: Color.mPrimary
            pointSize: Style.fontSizeXS
            font.weight: Style.fontWeightBold
          }

          NText {
            Layout.fillWidth: true
            text: root.lastHeardText
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeXS
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
          }
        }
      }

      // ==================
      // Status indicator (covers PTT + Live states)
      // ==================
      Rectangle {
        id: statusIndicator
        Layout.fillWidth: true
        Layout.preferredHeight: statusContent.implicitHeight + Style.marginL * 2
        visible: root.isRecording || root.isTranscribing || root.isLive
        color: {
          if (root.isRecording) return Qt.alpha(Color.mError, 0.1);
          if (root.isLive) return Qt.alpha(Color.mError, 0.07);
          return Qt.alpha(Color.mPrimary, 0.1);
        }
        radius: Style.radiusL
        border.color: {
          if (root.isRecording) return Qt.alpha(Color.mError, 0.3);
          if (root.isLive) return Qt.alpha(Color.mError, 0.25);
          return Qt.alpha(Color.mPrimary, 0.3);
        }
        border.width: 1

        ColumnLayout {
          id: statusContent
          anchors.centerIn: parent
          spacing: Style.marginM

          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.marginS

            Rectangle {
              width: 12
              height: 12
              radius: 6
              color: (root.isRecording || root.isLive) ? Color.mError : Color.mPrimary
              visible: root.isRecording || root.isLive

              SequentialAnimation on opacity {
                running: root.isRecording || root.isLive
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
                  return root.t("panel.recording", "Recording") + "  " +
                    (mins < 10 ? "0" : "") + mins + ":" + (secs < 10 ? "0" : "") + secs;
                }
                if (root.isTranscribing) {
                  return root.t("panel.transcribing", "Transcribing...");
                }
                if (root.isLive) {
                  return root.t("panel.listening", "Listening...");
                }
                return "";
              }
              color: (root.isRecording || root.isLive) ? Color.mError : Color.mPrimary
              pointSize: Style.fontSizeM
              font.weight: Style.fontWeightBold
            }
          }

          // Audio-level bars (visible while any mic-active state is true)
          Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 3
            visible: root.isRecording || root.isLive

            Repeater {
              model: 12
              Rectangle {
                width: 4
                height: 8 + Math.random() * 20
                radius: 2
                color: Color.mError
                opacity: 0.7

                Timer {
                  interval: 100 + Math.random() * 100
                  repeat: true
                  running: root.isRecording || root.isLive
                  onTriggered: parent.height = 8 + Math.random() * 20
                }

                Behavior on height {
                  NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                }
              }
            }
          }

          // PTT-only stop button (Live is controlled from the header)
          NButton {
            Layout.alignment: Qt.AlignHCenter
            visible: root.isRecording
            text: root.t("panel.stopRecording", "Stop & Send")
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
          visible: messages.length === 0 && !root.isGenerating && !root.isRecording && !root.isTranscribing && !root.isLive

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
              text: root.t("panel.emptyTitle", "Ready to listen")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeM
              applyUiScale: false
              font.weight: Font.Medium
            }

            NText {
              Layout.alignment: Qt.AlignHCenter
              text: root.t("panel.emptyHint", "Click Live, press your keybind, or type a message")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              applyUiScale: false
            }
          }
        }

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
                  ToastService.showNotice(root.t("toast.copied", "Copied!"));
                }
              }
            }

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

          // Primary mic button — Live toggle (or PTT stop when PTT is active)
          Rectangle {
            width: 40
            height: 40
            radius: 20
            color: {
              if (root.isRecording || root.isLive) return Color.mError;
              if (recordBtnMouse.containsMouse) return Qt.alpha(Color.mPrimary, 0.2);
              return Qt.alpha(Color.mPrimary, 0.1);
            }

            Behavior on color { ColorAnimation { duration: 150 } }

            NIcon {
              anchors.centerIn: parent
              icon: (root.isRecording || root.isLive) ? "player-stop" : "microphone"
              color: (root.isRecording || root.isLive) ? Color.mOnPrimary : Color.mPrimary
              pointSize: Style.fontSizeM
            }

            MouseArea {
              id: recordBtnMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: !root.isTranscribing
              onClicked: {
                if (!mainInstance) return;
                mainInstance.primaryToggle();
              }
            }

            ToolTip.visible: recordBtnMouse.containsMouse
            ToolTip.text: {
              if (root.isLive) return root.t("panel.liveStop", "Stop Live");
              if (root.isRecording) return root.t("panel.stopRecording", "Stop Recording");
              return root.t("panel.liveStart", "Start Live");
            }
          }

          // Text input
          ScrollView {
            Layout.fillWidth: true
            Layout.maximumHeight: 100

            TextArea {
              id: inputField
              text: mainInstance?.chatInputText || ""
              placeholderText: root.t("panel.placeholder", "Type a message, or press Live to start listening...")
              placeholderTextColor: Color.mOnSurfaceVariant
              color: Color.mOnSurface
              font.pointSize: Style.fontSizeM
              wrapMode: TextArea.Wrap
              background: null
              selectByMouse: true
              // Typing is still allowed while Live is running — user may want to type a follow-up.
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
              ? root.t("panel.stopGenerating", "Stop")
              : root.t("panel.send", "Send")
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
