import QtQuick

QtObject {
    // METHOD 1: Hex Formatting (#AARRGGBB)
    // Matugen's .hex property outputs a raw 6-character string (like "1a1b26") without a '#'.
    // We prepend the '#' and an alpha hex pair (e.g., '80' for 50% opacity).
    property color bg_color: "#10140f"
}
