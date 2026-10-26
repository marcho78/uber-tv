import QtQuick

// An article page an app sent (api 4, lib/appblocks.py page): its title,
// then each section's heading and text, plain, its own lines kept. Up and
// down scroll it a step at a time (AppView.move sets pageY; this keeps it
// within its length and says that length back: pageMax). In tablet mode a
// finger scrolls it too; where it stops is where the keys go on from.
Flickable {
  id: pageView

  required property var guide
  required property var view
  property var value: null           // { title, sections }
  readonly property real u: guide.u

  contentWidth: width
  contentHeight: col.implicitHeight + u * 2
  contentY: Math.max(0, Math.min(view.pageY, Math.max(0, contentHeight - height)))
  interactive: guide.touchMode
  onMovementEnded: view.pageY = contentY
  clip: true
  Behavior on contentY { enabled: !pageView.guide.touchMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  onContentHeightChanged: view.pageMax = Math.max(0, contentHeight - height)
  onHeightChanged: view.pageMax = Math.max(0, contentHeight - height)
  onVisibleChanged: if (visible) view.pageMax = Math.max(0, contentHeight - height)

  Column {
    id: col
    x: pageView.u * 3
    width: Math.min(pageView.width - pageView.u * 6, pageView.u * 70)   // lines short enough to read across the room
    spacing: pageView.u * 0.8
    Label {
      objectName: "pageTitle"
      width: parent.width
      text: pageView.value ? pageView.value.title : ""
      s: pageView.guide.look.appPageTitle
      unit: pageView.u
      sizeFactor: 0.7
      wrapMode: Text.Wrap
    }
    Repeater {
      model: pageView.value ? pageView.value.sections : []
      delegate: Column {
        required property var modelData
        width: col.width
        spacing: pageView.u * 0.4
        Label {
          width: parent.width
          visible: text !== ""
          topPadding: pageView.u * 0.6
          text: parent.modelData.heading
          s: pageView.guide.look.appPageHeading
          unit: pageView.u
          wrapMode: Text.Wrap
        }
        Label {
          width: parent.width
          visible: text !== ""
          text: parent.modelData.text
          s: pageView.guide.look.appPageText
          unit: pageView.u
          sizeFactor: 1.15
          wrapMode: Text.Wrap
          lineHeight: 1.25
        }
      }
    }
  }
}
