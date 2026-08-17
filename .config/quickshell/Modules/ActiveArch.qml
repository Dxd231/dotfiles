
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Scope {
    id: activearch_root
	Variants {
		// Create the panel once on each monitor.
		model: Quickshell.screens

		PanelWindow {
			id: w

			property var modelData
			screen: modelData

			anchors {
				right: true
				bottom: true
			}

			margins {
				right: 50
				bottom: 50
			}

			implicitWidth: content.width
			implicitHeight: content.height

			color: "transparent"

			// Give the window an empty click mask so all clicks pass through it.
			mask: Region {}

			// Use the wlroots specific layer property to ensure it displays over
			// fullscreen windows.
			WlrLayershell.layer: WlrLayer.Top

			ColumnLayout {
				id: content

				Text {
					text: "Activate Arch Linux"
					color: "#70ffffff"
					font.pointSize: 20
					font.family: "Segoe UI Variable Static Text"
					//renderType: Text.NativeRendering
					//font.hintingPreference: Font.PreferFullHinting
				}

				Text {
					text: "Go to Terminal to activate Arch Linux(BTW)"
					color: "#70ffffff"
					font.pointSize: 12
					font.family: "Segoe UI Variable Static Text"
					//renderType: Text.NativeRendering
					//font.hintingPreference: Font.PreferFullHinting
				}
			}
		}
	}
}