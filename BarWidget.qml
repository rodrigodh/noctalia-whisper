import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import "WhisperLogic.js" as Logic

Item {
  id: root

  property var pluginApi: null

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property bool isRecording: mainInstance?.isRecording || false
  readonly property bool isLive: mainInstance?.isLive || false
  readonly property bool isTranscribing: mainInstance?.isTranscribing || false
  readonly property bool isGenerating: mainInstance?.isGenerating || false

  function t(key, fallback) {
    if (mainInstance && mainInstance.t) return mainInstance.t(key, fallback);
    return Logic.cleanTr(pluginApi ? pluginApi.tr(key) : null, fallback);
  }

  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

  readonly property real contentWidth: capsuleHeight
  readonly property real contentHeight: capsuleHeight

  implicitWidth: contentWidth
  implicitHeight: contentHeight

  // Recording pulse animation
  SequentialAnimation {
    id: pulseAnimation
    running: root.isRecording || root.isLive
    loops: Animation.Infinite

    NumberAnimation {
      target: iconWidget
      property: "opacity"
      from: 1.0
      to: 0.3
      duration: 600
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: iconWidget
      property: "opacity"
      from: 0.3
      to: 1.0
      duration: 600
      easing.type: Easing.InOutSine
    }
  }

  // Reset opacity when not recording/live
  Binding {
    target: iconWidget
    property: "opacity"
    value: 1.0
    when: !root.isRecording && !root.isLive
  }

  Rectangle {
    id: visualCapsule
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    width: root.contentWidth
    height: root.contentHeight
    color: {
      if (root.isRecording || root.isLive) return Qt.alpha(Color.mError, 0.2);
      if (mouseArea.containsMouse) return Color.mHover;
      return Style.capsuleColor;
    }
    radius: Style.radiusL
    border.color: (root.isRecording || root.isLive) ? Color.mError : Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    NIcon {
      id: iconWidget
      anchors.centerIn: parent
      icon: {
        if (root.isRecording || root.isLive) return "microphone";
        if (root.isTranscribing) return "loader-2";
        if (root.isGenerating) return "loader-2";
        return "microphone";
      }
      color: {
        if (root.isRecording || root.isLive) return Color.mError;
        if (root.isTranscribing || root.isGenerating) return Color.mPrimary;
        return Color.mOnSurface;
      }
      applyUiScale: false

      RotationAnimation on rotation {
        running: root.isTranscribing || root.isGenerating
        from: 0
        to: 360
        duration: 1000
        loops: Animation.Infinite
      }

      Binding {
        target: iconWidget
        property: "rotation"
        value: 0
        when: !root.isTranscribing && !root.isGenerating
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onEntered: {
      var tooltip = root.t("widget.title", "Whisper");
      if (root.isLive) {
        tooltip += "\n" + root.t("widget.live", "Live (listening)");
      } else if (root.isRecording) {
        tooltip += "\n" + root.t("widget.recording", "Recording...");
      } else if (root.isTranscribing) {
        tooltip += "\n" + root.t("widget.transcribing", "Transcribing...");
      } else if (root.isGenerating) {
        tooltip += "\n" + root.t("widget.generating", "Generating...");
      }
      tooltip += "\n\n" + root.t("widget.clickHint", "Click to open");
      TooltipService.show(root, tooltip, BarService.getTooltipDirection());
    }

    onExited: TooltipService.hide()

    onClicked: function (mouse) {
      if (mouse.button === Qt.LeftButton) {
        if (pluginApi) {
          pluginApi.openPanel(root.screen, root);
        }
      } else if (mouse.button === Qt.RightButton) {
        PanelService.showContextMenu(contextMenu, root, screen);
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": root.t("menu.openPanel", "Open Panel"),
        "action": "open",
        "icon": "external-link"
      },
      {
        "label": root.isLive ? root.t("menu.stopLive", "Stop Live") : root.t("menu.startLive", "Start Live"),
        "action": "live",
        "icon": "microphone"
      },
      {
        "label": root.t("menu.record", "Start Recording"),
        "action": "record",
        "icon": "microphone"
      },
      {
        "label": root.t("menu.clearHistory", "Clear History"),
        "action": "clear",
        "icon": "trash"
      },
      {
        "label": root.t("menu.settings", "Settings"),
        "action": "settings",
        "icon": "settings"
      }
    ]

    onTriggered: function (action) {
      contextMenu.close();
      PanelService.closeContextMenu(screen);

      if (action === "open") {
        pluginApi?.openPanel(root.screen, root);
      } else if (action === "live") {
        pluginApi?.openPanel(root.screen, root);
        if (mainInstance) {
          Qt.callLater(function() { mainInstance.toggleLive(); });
        }
      } else if (action === "record") {
        pluginApi?.openPanel(root.screen, root);
        if (mainInstance && !mainInstance.isRecording && !mainInstance.isLive) {
          Qt.callLater(function() { mainInstance.startRecording(); });
        }
      } else if (action === "clear") {
        if (mainInstance) {
          mainInstance.clearMessages();
          ToastService.showNotice(root.t("toast.historyCleared", "History cleared"));
        }
      } else if (action === "settings") {
        BarService.openPluginSettings(screen, pluginApi.manifest);
      }
    }
  }
}
