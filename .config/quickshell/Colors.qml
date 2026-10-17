pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: colors

    readonly property FileView _view: FileView {
        path: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property color background: "#15130b"
            property color error: "#ffb4ab"
            property color error_container: "#93000a"
            property color inverse_on_surface: "#333027"
            property color inverse_primary: "#6e5e0e"
            property color inverse_surface: "#e9e2d4"
            property color on_background: "#e9e2d4"
            property color on_error: "#690005"
            property color on_error_container: "#ffdad6"
            property color on_primary: "#3a3000"
            property color on_primary_container: "#f9e287"
            property color on_primary_fixed: "#221b00"
            property color on_primary_fixed_variant: "#544600"
            property color on_secondary: "#373016"
            property color on_secondary_container: "#eee2bc"
            property color on_secondary_fixed: "#211b04"
            property color on_secondary_fixed_variant: "#4e472a"
            property color on_surface: "#e9e2d4"
            property color on_surface_variant: "#cdc6b4"
            property color on_tertiary: "#153722"
            property color on_tertiary_container: "#c5ecce"
            property color on_tertiary_fixed: "#00210f"
            property color on_tertiary_fixed_variant: "#2c4e38"
            property color outline: "#969080"
            property color outline_variant: "#4b4739"
            property color primary: "#dcc66e"
            property color primary_container: "#544600"
            property color primary_fixed: "#f9e287"
            property color primary_fixed_dim: "#dcc66e"
            property color scrim: "#000000"
            property color secondary: "#d2c6a1"
            property color secondary_container: "#4e472a"
            property color secondary_fixed: "#eee2bc"
            property color secondary_fixed_dim: "#d2c6a1"
            property color shadow: "#000000"
            property color source_color: "#fce89d"
            property color surface: "#15130b"
            property color surface_bright: "#3c3930"
            property color surface_container: "#221f17"
            property color surface_container_high: "#2d2a21"
            property color surface_container_highest: "#38352b"
            property color surface_container_low: "#1e1b13"
            property color surface_container_lowest: "#100e07"
            property color surface_dim: "#15130b"
            property color surface_tint: "#dcc66e"
            property color surface_variant: "#4b4739"
            property color tertiary: "#aad0b2"
            property color tertiary_container: "#2c4e38"
            property color tertiary_fixed: "#c5ecce"
            property color tertiary_fixed_dim: "#aad0b2"
        }
    }

    readonly property color background: adapter.background
    readonly property color error: adapter.error
    readonly property color error_container: adapter.error_container
    readonly property color inverse_on_surface: adapter.inverse_on_surface
    readonly property color inverse_primary: adapter.inverse_primary
    readonly property color inverse_surface: adapter.inverse_surface
    readonly property color on_background: adapter.on_background
    readonly property color on_error: adapter.on_error
    readonly property color on_error_container: adapter.on_error_container
    readonly property color on_primary: adapter.on_primary
    readonly property color on_primary_container: adapter.on_primary_container
    readonly property color on_primary_fixed: adapter.on_primary_fixed
    readonly property color on_primary_fixed_variant: adapter.on_primary_fixed_variant
    readonly property color on_secondary: adapter.on_secondary
    readonly property color on_secondary_container: adapter.on_secondary_container
    readonly property color on_secondary_fixed: adapter.on_secondary_fixed
    readonly property color on_secondary_fixed_variant: adapter.on_secondary_fixed_variant
    readonly property color on_surface: adapter.on_surface
    readonly property color on_surface_variant: adapter.on_surface_variant
    readonly property color on_tertiary: adapter.on_tertiary
    readonly property color on_tertiary_container: adapter.on_tertiary_container
    readonly property color on_tertiary_fixed: adapter.on_tertiary_fixed
    readonly property color on_tertiary_fixed_variant: adapter.on_tertiary_fixed_variant
    readonly property color outline: adapter.outline
    readonly property color outline_variant: adapter.outline_variant
    readonly property color primary: adapter.primary
    readonly property color primary_container: adapter.primary_container
    readonly property color primary_fixed: adapter.primary_fixed
    readonly property color primary_fixed_dim: adapter.primary_fixed_dim
    readonly property color scrim: adapter.scrim
    readonly property color secondary: adapter.secondary
    readonly property color secondary_container: adapter.secondary_container
    readonly property color secondary_fixed: adapter.secondary_fixed
    readonly property color secondary_fixed_dim: adapter.secondary_fixed_dim
    readonly property color shadow: adapter.shadow
    readonly property color source_color: adapter.source_color
    readonly property color surface: adapter.surface
    readonly property color surface_bright: adapter.surface_bright
    readonly property color surface_container: adapter.surface_container
    readonly property color surface_container_high: adapter.surface_container_high
    readonly property color surface_container_highest: adapter.surface_container_highest
    readonly property color surface_container_low: adapter.surface_container_low
    readonly property color surface_container_lowest: adapter.surface_container_lowest
    readonly property color surface_dim: adapter.surface_dim
    readonly property color surface_tint: adapter.surface_tint
    readonly property color surface_variant: adapter.surface_variant
    readonly property color tertiary: adapter.tertiary
    readonly property color tertiary_container: adapter.tertiary_container
    readonly property color tertiary_fixed: adapter.tertiary_fixed
    readonly property color tertiary_fixed_dim: adapter.tertiary_fixed_dim
}
