import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root
  property var message
  property var pluginApi

  signal copyRequested(string text)

  height: mainLayout.implicitHeight
  width: parent ? parent.width : 400

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    z: 0
  }

  RowLayout {
    id: mainLayout
    z: 1
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.marginS

    // Assistant avatar
    NIcon {
      Layout.alignment: Qt.AlignTop
      visible: message.role === "assistant"
      icon: "sparkles"
      color: Color.mPrimary
      pointSize: Style.fontSizeL
      applyUiScale: false
    }

    // Spacer for user messages (push to right)
    Item {
      visible: message.role === "user"
      Layout.fillWidth: true
    }

    // Message bubble
    Rectangle {
      id: bubbleRect

      Layout.maximumWidth: parent.width * 0.85
      Layout.preferredWidth: contentCol.implicitWidth + (Style.marginM * 2)
      Layout.preferredHeight: contentCol.implicitHeight + (Style.marginM * 2)

      color: message.role === "user" ? Color.mSurfaceVariant : Color.mSurface
      radius: Style.radiusM

      // Sharp corner for user messages (top-right)
      Rectangle {
        visible: message.role === "user"
        anchors.top: parent.top
        anchors.right: parent.right
        width: parent.radius
        height: parent.radius
        color: parent.color
      }

      ColumnLayout {
        id: contentCol
        z: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.marginM
        spacing: Style.marginS

        TextEdit {
          Layout.maximumWidth: bubbleRect.Layout.maximumWidth - (Style.marginM * 2)
          Layout.fillWidth: true
          wrapMode: TextEdit.Wrap
          text: message.content
          textFormat: message.role === "assistant" ? Text.MarkdownText : Text.PlainText
          readOnly: true
          selectByMouse: true
          color: Color.mOnSurface
          font.family: Settings.data.ui.fontDefault
          font.pointSize: Math.max(1, Style.fontSizeM * Settings.data.ui.fontDefaultScale * Style.uiScaleRatio)
          font.weight: Style.fontWeightMedium
          selectionColor: Color.mPrimary
          selectedTextColor: Color.mOnPrimary
          onLinkActivated: link => Qt.openUrlExternally(link)
        }

        // Action buttons for assistant messages
        RowLayout {
          visible: message.role === "assistant" && !message.isStreaming
          spacing: Style.marginS
          Layout.alignment: Qt.AlignLeft

          Rectangle {
            width: 28
            height: 28
            radius: 4
            color: copyMouse.containsMouse ? Color.mSurfaceVariant : "transparent"

            NIcon {
              anchors.centerIn: parent
              icon: "copy"
              pointSize: Style.fontSizeM
              applyUiScale: false
              color: copyMouse.containsMouse ? Color.mPrimary : Color.mOnSurfaceVariant
            }

            MouseArea {
              id: copyMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyRequested(message.content)
              ToolTip.visible: containsMouse
              ToolTip.text: pluginApi?.tr("chat.copy") || "Copy"
            }
          }
        }
      }
    }

    // Spacer for assistant messages
    Item {
      visible: message.role === "assistant"
      Layout.fillWidth: true
    }

    // User avatar
    NIcon {
      Layout.alignment: Qt.AlignTop
      visible: message.role === "user"
      icon: "user"
      color: Color.mOnSurfaceVariant
      pointSize: Style.fontSizeL
      applyUiScale: false
    }
  }
}
