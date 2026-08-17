// Workspaces.qml
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

Item {
  id: root
  
  // our kanji list
  property var kanjiNumbers: ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
  
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight
  
  RowLayout {
    id: row
    anchors.centerIn: parent
    spacing: 4
    
    Repeater {
      model: 9  // workspaces 1 through 9
      
      delegate: Item {
        id: wsItem
        required property int index
        
        // workspace number, index is 0-based so add 1
        property int wsId: index + 1
        
        // is this the currently active workspace?
        property bool active: Hyprland.focusedMonitor?.activeWorkspace?.id === wsId
        
        // does this workspace have any windows in it?
        property bool occupied: Hyprland.workspaces.values.some(ws => ws.id === wsId)
        
        implicitWidth: 28
        implicitHeight: 28
        
        Rectangle {
          anchors.fill: parent
          radius: 6
          
          // active = bright background
          // occupied = dim background  
          // empty = transparent
          color: wsItem.active ? "#cba6f7"
               : wsItem.occupied ? "#313244"
               : "transparent"
          
          Behavior on color {
            ColorAnimation { duration: 150 }
          }
          
          Text {
            anchors.centerIn: parent
            
            // get the kanji for this workspace
            // index 0 = 一, index 1 = 二, etc
            text: root.kanjiNumbers[index]
            
            // active = dark text on bright bg
            // occupied = white
            // empty = dim
            color: wsItem.active ? "#1e1e2e"
                 : wsItem.occupied ? "#cdd6f4"
                 : "#585b70"
            
            font.pixelSize: 14
            font.family: "Noto Sans JP"  // japanese font, change to whatever you have
            
            Behavior on color {
              ColorAnimation { duration: 150 }
            }
          }
          
          MouseArea {
            anchors.fill: parent
            onClicked: Hyprland.dispatch("workspace " + wsItem.wsId)
            
            // change cursor to a pointer hand on hover
            cursorShape: Qt.PointingHandCursor
          }
        }
      }
    }
  }
}
