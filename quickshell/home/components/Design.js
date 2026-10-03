.pragma library

// Every spacing, radius, type, and motion value used anywhere in the home
// surface. Components read from here so no magic number is repeated per file.
//
// The active Omarchy theme on this host is deliberately monochrome, and this
// design does not fight that: hierarchy comes from translucency, weight,
// scale, and spacing rather than from hue. There are no brand colours here at
// all; every colour is derived from the live theme at runtime.

// The strip is a very wide, short band. Vertical space is the scarce resource,
// so the type scale and the spacing scale are tuned for a 288px logical
// height and only compact downward.
var metrics = ({
    // Horizontal rhythm.
    "gutter": 22,
    "gutterCompact": 14,
    "columnGap": 14,
    "columnGapCompact": 10,

    // The strip's own height budget. Both preview sizes are supported; the
    // 288px logical surface is the tighter of the two.
    "stripHeight": 288,
    "previewHeight": 360,

    // Edge-gesture safety. Nothing interactive or legible sits within 8% of
    // the top or bottom edge, so a swipe from either bezel never lands on
    // content. 8% of 288 is 23px; the strip reserves more than that.
    "edgeSafeFraction": 0.08,
    "edgeSafeMinimum": 24,

    // Status strip height, which the main band sits under.
    "statusHeight": 46,
    "statusHeightCompact": 40
})

// Continuous ("squircle") corner radii. The radius never exceeds half the
// smaller side, so a squircle stays a squircle at any card size.
var radius = ({
    "artwork": 12,
    "card": 22,
    "cardCompact": 18,
    "cluster": 20,
    "pill": 999,
    "chip": 9,
    "hairline": 0
})

// SF-Pro-like hierarchy. Titles are tightly tracked and large; labels are
// small and loosely tracked. `weight` maps to Qt's numeric font weights.
var type = ({
    "display": ({
        "size": 34,
        "weight": 600,
        "tracking": -0.9,
        "lineHeight": 38
    }),
    "title": ({
        "size": 19,
        "weight": 600,
        "tracking": -0.35,
        "lineHeight": 23
    }),
    "headline": ({
        "size": 15,
        "weight": 600,
        "tracking": -0.2,
        "lineHeight": 19
    }),
    "body": ({
        "size": 13,
        "weight": 400,
        "tracking": -0.05,
        "lineHeight": 17
    }),
    "callout": ({
        "size": 12,
        "weight": 500,
        "tracking": 0,
        "lineHeight": 15
    }),
    "subheadline": ({
        "size": 11,
        "weight": 500,
        "tracking": 0.1,
        "lineHeight": 14
    }),
    "caption": ({
        "size": 10,
        "weight": 500,
        "tracking": 0.3,
        "lineHeight": 13
    }),
    // Device headings and metric readouts. Tabular figures keep a number from
    // shifting the layout as it counts.
    "metric": ({
        "size": 22,
        "weight": 600,
        "tracking": -0.6,
        "lineHeight": 26
    }),
    "metricSmall": ({
        "size": 13,
        "weight": 600,
        "tracking": -0.15,
        "lineHeight": 17
    }),
    "mono": ({
        "size": 11,
        "weight": 500,
        "tracking": 0.2,
        "lineHeight": 14
    })
})

// SF Pro is not installed on this host. This is the same family Omarchy's own
// bar resolves to, and it is a humanist grotesque rather than a UI slab, so
// the hierarchy reads the same way the reference intends.
var fontFamily = "Noto Sans"
var monospaceFamily = "JetBrainsMono Nerd Font"

// Restrained spring motion. One set of constants, honoured by every animated
// property; reduced motion sets every duration to zero instead of swapping
// easing curves, so a disabled animation ends on exactly the same frame.
var motion = ({
    "springStiffness": 320,
    "springDamping": 30,
    "springDurationMs": 260,
    "pressScale": 0.94,
    "hoverScale": 1.05,
    "dockLift": 6,
    "crossfadeMs": 220,
    "scrubHandleDiameter": 11
})

// A squircle corner is a superellipse, not a circular arc. This walks the
// corner's exponent curve and returns an SVG path for one rounded rectangle,
// which is what gives the continuous curvature Apple's shapes have.
function squirclePath(width, height, cornerRadius, exponent) {
    var w = Math.max(0, Number(width) || 0)
    var h = Math.max(0, Number(height) || 0)
    var limit = Math.min(w, h) / 2
    var r = Math.max(0, Math.min(Number(cornerRadius) || 0, limit))
    if (w === 0 || h === 0)
        return ""
    if (r <= 0.5)
        return "M 0 0 L " + w + " 0 L " + w + " " + h + " L 0 " + h + " Z"

    // A superellipse corner, not a circular arc. On each corner the curve is
    // traced as |dx/r|^n + |dy/r|^n = 1, which is what gives the corner its
    // continuous curvature instead of four circular arcs meeting at a right
    // angle.
    var n = Math.max(2, Number(exponent) || 4)
    var exponentOf = 2 / n
    var steps = 16

    function point(cx, cy, sx, sy, t) {
        // t runs 0..1 across the quarter corner.
        var cos = Math.cos(t * Math.PI / 2)
        var sin = Math.sin(t * Math.PI / 2)
        return {
            "x": cx + sx * r * Math.pow(cos, exponentOf),
            "y": cy + sy * r * Math.pow(sin, exponentOf)
        }
    }

    var path = ""

    function lineTo(x, y) {
        path += " L " + x.toFixed(2) + " " + y.toFixed(2)
    }

    // One quarter corner, sampled from `from` to `to` in sixteenths of a
    // quarter turn. sx and sy are the directions away from the corner centre.
    function corner(cx, cy, sx, sy, from, to) {
        var direction = to > from ? 1 : -1
        for (var step = from; step !== to + direction; step += direction) {
            var sample = point(cx, cy, sx, sy, step / steps)
            lineTo(sample.x, sample.y)
        }
    }

    // Traced clockwise from where the top edge meets the top-left corner. Each
    // corner's final sample is where the next straight edge begins, so the
    // straight edges need no explicit segment of their own.
    var start = point(r, r, -1, -1, 0)
    path += "M " + start.x.toFixed(2) + " " + start.y.toFixed(2)

    corner(r, r, -1, -1, 0, steps)       // top-left, onto the top edge
    corner(w - r, r, 1, -1, steps, 0)    // top-right, onto the right edge
    corner(w - r, h - r, 1, 1, 0, steps) // bottom-right, onto the base
    corner(r, h - r, -1, 1, steps, 0)    // bottom-left, onto the left edge

    path += " Z"
    return path
}

function squirclePoints(width, height, cornerRadius, exponent) {
    return squirclePath(width, height, cornerRadius, exponent)
}

// Height-derived sizing, so one layout serves both the 1024x288 logical
// surface and the 1280x360 preview without a second code path.
function bandForHeight(height) {
    var safe = Math.max(
        metrics.edgeSafeMinimum,
        Math.round(height * metrics.edgeSafeFraction)
    )
    return {
        "edgeSafe": safe,
        "statusHeight": height < 320 ? metrics.statusHeightCompact : metrics.statusHeight,
        "gutter": height < 320 ? metrics.gutterCompact : metrics.gutter,
        "columnGap": height < 320 ? metrics.columnGapCompact : metrics.columnGap,
        "cardRadius": height < 320 ? radius.cardCompact : radius.card
    }
}

function compactHeight(height) {
    return height < 320
}