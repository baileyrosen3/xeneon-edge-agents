pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "Design.js" as Design

// A rounded rectangle with continuous corner curvature.
//
// A `Rectangle` can only draw circular corners, and four circular arcs meeting
// at a right angle produce a visible tension that reads as "Linux settings
// panel". Apple's shapes use a superellipse corner whose curvature flows into
// the edges, and that difference is most of what makes a surface read as system
// UI. This draws the real superellipse outline as one closed path.
//
// The optional sheen gradient is folded in here so the glass material does not
// have to reach for a second shape type just to get a top-edge light.
Item {
    id: root

    // Corner radius in logical pixels, clamped to half the smaller side.
    property real corner: Design.radius.card

    // 4 is the Apple-like continuous corner; higher values square the corner
    // off further, lower values round it toward a circle.
    property real exponent: 4

    property color fillColor: "transparent"
    property color strokeColor: "transparent"
    property real strokeWidth: 0

    // An optional gradient fill. When set it replaces the flat colour, which
    // is how the glass material gets its top-edge light without a second
    // shape type or a second pass.
    // A ShapeGradient, not a QtQuick Gradient: ShapePath.fillGradient is a
    // different type. Null means "use fillColor".
    property var fillGradient: null

    implicitWidth: 0
    implicitHeight: 0

    Shape {
        id: shape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        // Rebuilt only when the geometry or the radius actually changes, never
        // per frame: the path is a binding on those values alone.
        readonly property string outline: Design.squirclePath(
            shape.width,
            shape.height,
            root.corner,
            root.exponent
        )

        ShapePath {
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            fillColor: root.fillGradient === null ? root.fillColor : "transparent"
            fillGradient: root.fillGradient === null ? undefined : root.fillGradient
            fillRule: ShapePath.WindingFill
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: shape.outline
            }
        }
    }
}