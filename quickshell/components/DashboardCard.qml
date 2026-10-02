pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
    required property var theme
    radius: 20
    color: theme.surface
    border.width: 1
    border.color: theme.border
    clip: true
}
