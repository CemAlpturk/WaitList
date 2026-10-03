// make-icon.swift: the WaitList app icon and menu bar glyph, drawn in code.
//
// This file is the source of truth for the brand artwork. Everything is vector
// (CoreGraphics paths and gradients, no bitmaps, no text), so every size is crisp.
//
// Usage, from the repo root:
//   make icon                                   export concept A (same as the next line)
//   swift Tools/make-icon.swift                 export concept A into Resources/ and Screenshots/
//   swift Tools/make-icon.swift --concept b     export concept B instead
//   swift Tools/make-icon.swift --previews      render comparison images into build/icon-previews/
//
// Tweaking colors: every concept below starts with a `palette` made of plain
// hex colors ("#RRGGBB"). Change them and re-run. Shapes are described in a
// 1024 x 1024 grid (the full icon canvas), y grows downward, (512, 512) is the center.
//
// Outputs of the default export:
//   Resources/AppIcon.icns          app icon, 16 to 1024 px (built from build/AppIcon.iconset by iconutil)
//   Resources/MenuBarIcon.png       18 x 18 menu bar template image (pure black + alpha)
//   Resources/MenuBarIcon@2x.png    36 x 36 retina version
//   Screenshots/icon.png            full-size 1024 px icon for the README (not shipped in the app bundle,
//                                   which copies everything in Resources/)

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Concept A: hourglass whose sand has settled into a shopping bag

struct HourglassBag: IconConcept {
    let palette = Palette(
        top: "#4FD0C3",          // soft teal
        bottom: "#2A78D4",       // calm blue
        symbolShade: "#DCEFFA"   // the white symbol fades to this at the bottom
    )

    func drawIcon(in ctx: CGContext, size: CGFloat) {
        ctx.useGrid(1024, canvas: size)
        let boost = opticalBoost(size)
        let detailed = size >= 64
        let white = color("#FFFFFF")

        let wall = 40 * boost                 // glass outline thickness
        let capSize = CGSize(width: 456, height: 60 * boost)
        let topCap = CGRect(x: 512 - capSize.width / 2, y: 232, width: capSize.width, height: capSize.height)
        let bottomCap = CGRect(x: 512 - capSize.width / 2, y: 792 - capSize.height, width: capSize.width, height: capSize.height)
        let glass = hourglassGlass(cx: 512, top: topCap.midY, bottom: bottomCap.midY,
                                   half: 174, neck: 34, shoulder: 58, waist: 62)

        // 1. Frosted glass.
        ctx.addPath(glass)
        ctx.setFillColor(white.copy(alpha: 0.22)!)
        ctx.fillPath()

        // 2. Sand still waiting in the top bulb, with a hairline gap to the glass.
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.saveGState()
        ctx.addPath(glass)
        ctx.clip()
        ctx.clip(to: CGRect(x: 0, y: 0, width: 1024, height: 512))
        let sand = CGMutablePath()
        sand.move(to: P(338, 366))
        sand.addQuadCurve(to: P(686, 366), control: P(512, 426))   // dips where it drains
        sand.addLine(to: P(686, 600))
        sand.addLine(to: P(338, 600))
        sand.closeSubpath()
        ctx.addPath(sand)
        ctx.setFillColor(white)
        ctx.fillPath()
        ctx.restoreGState()
        if detailed {
            ctx.setBlendMode(.destinationOut)
            ctx.addPath(glass)
            ctx.setLineWidth(wall + 2 * 14)
            ctx.setStrokeColor(white)
            ctx.strokePath()
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        // 3. A thin stream falling through the neck.
        if detailed {
            ctx.setStrokeColor(white)
            ctx.setLineWidth(14)
            ctx.setLineCap(.round)
            ctx.move(to: P(512, 500))
            ctx.addLine(to: P(512, 526))
            ctx.strokePath()
        }

        // 4. The bag the sand has become.
        let bag = roundedTrapezoid(cx: 512, top: 610, bottom: 716, topHalf: 96, bottomHalf: 114,
                                   topRadius: 12, bottomRadius: 22)
        ctx.addPath(bag)
        ctx.setFillColor(white)
        ctx.fillPath()
        let handle = CGMutablePath()
        handle.move(to: P(478, 614))
        handle.addLine(to: P(478, 596))
        handle.addArc(center: P(512, 596), radius: 34, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        handle.addLine(to: P(546, 614))
        ctx.addPath(handle)
        ctx.setStrokeColor(white)
        ctx.setLineWidth(18 * boost)
        ctx.setLineCap(.round)
        ctx.strokePath()

        // 5. Glass outline and the two caps.
        ctx.addPath(glass)
        ctx.setLineWidth(wall)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        for cap in [topCap, bottomCap] {
            ctx.addPath(CGPath(roundedRect: cap, cornerWidth: cap.height / 2, cornerHeight: cap.height / 2, transform: nil))
        }
        ctx.setFillColor(white)
        ctx.fillPath()
    }

    func drawMenuBarGlyph(in ctx: CGContext, size: CGFloat) {
        ctx.useGrid(18, canvas: size)
        let glass = hourglassGlass(cx: 9, top: 2, bottom: 16, half: 4.1, neck: 1.0, shoulder: 1.4, waist: 1.9)

        // Settled sand: a small mound in the bottom bulb.
        ctx.saveGState()
        ctx.addPath(glass)
        ctx.clip()
        let mound = CGMutablePath()
        mound.move(to: P(0, 13.6))
        mound.addQuadCurve(to: P(18, 13.6), control: P(9, 10.8))
        mound.addLine(to: P(18, 18))
        mound.addLine(to: P(0, 18))
        mound.closeSubpath()
        ctx.addPath(mound)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.addPath(glass)
        ctx.setLineWidth(1.35)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        for y in [2.0, 16.0] {
            ctx.move(to: P(3.75, y))
            ctx.addLine(to: P(14.25, y))
        }
        ctx.strokePath()
    }
}

// MARK: - Concept B: a shopping bag on pause

struct PausedBag: IconConcept {
    let palette = Palette(
        top: "#FFC65C",          // amber
        bottom: "#F2731D",       // orange
        symbolShade: "#FFF0DE"
    )

    func drawIcon(in ctx: CGContext, size: CGFloat) {
        ctx.useGrid(1024, canvas: size)
        let boost = opticalBoost(size)
        let white = color("#FFFFFF")
        ctx.translateBy(x: 0, y: -18)          // the bag is bottom-heavy; lift it to the optical center
        let top: CGFloat = 392, bottom: CGFloat = 800

        // Handle: a slim, narrow loop (a thick, wide one reads as a padlock).
        let handle = CGMutablePath()
        handle.move(to: P(428, top + 46))
        handle.addLine(to: P(428, 360))
        handle.addArc(center: P(512, 360), radius: 84, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        handle.addLine(to: P(596, top + 46))
        ctx.addPath(handle)
        ctx.setStrokeColor(white)
        ctx.setLineWidth(34 * boost)
        ctx.setLineCap(.round)
        ctx.strokePath()

        // Body: taller than wide and a little wider at the bottom, like a paper bag.
        ctx.addPath(roundedTrapezoid(cx: 512, top: top, bottom: bottom, topHalf: 168, bottomHalf: 204,
                                     topRadius: 30, bottomRadius: 64))
        ctx.setFillColor(white)
        ctx.fillPath()

        ctx.setBlendMode(.destinationOut)
        // Rope-handle holes: the detail that says "shopping bag" rather than "padlock".
        if size >= 64 {
            for x in [428.0, 596.0] { ctx.fillEllipse(in: circle(P(x, top + 46), 17)) }
        }
        // Pause bars, cut out so the background shows through.
        let barWidth = 64 * boost, barHeight: CGFloat = 176, gap = 60 * boost
        let cy: CGFloat = 620
        for x in [512 - gap / 2 - barWidth, 512 + gap / 2] {
            let bar = CGRect(x: x, y: cy - barHeight / 2, width: barWidth, height: barHeight)
            ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        }
        ctx.fillPath()
        ctx.setBlendMode(.normal)
    }

    func drawMenuBarGlyph(in ctx: CGContext, size: CGFloat) {
        ctx.useGrid(18, canvas: size)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let top: CGFloat = 6.2
        let handle = CGMutablePath()
        handle.move(to: P(7.0, top))
        handle.addLine(to: P(7.0, 4.6))
        handle.addArc(center: P(9, 4.6), radius: 2.0, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        handle.addLine(to: P(11.0, top))
        ctx.addPath(handle)
        ctx.addPath(roundedTrapezoid(cx: 9, top: top, bottom: 16.4, topHalf: 4.7, bottomHalf: 5.5,
                                     topRadius: 1.0, bottomRadius: 2.0))
        ctx.strokePath()

        for x in [6.85, 9.65] {
            let bar = CGRect(x: x, y: 9.1, width: 1.5, height: 4.6)
            ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 0.75, cornerHeight: 0.75, transform: nil))
        }
        ctx.fillPath()
    }
}

// MARK: - Concept C: a price tag with a clock face

struct TagClock: IconConcept {
    let palette = Palette(
        top: "#7B7EF4",          // indigo
        bottom: "#6B3FCF",       // violet
        symbolShade: "#ECE6FF"
    )

    func drawIcon(in ctx: CGContext, size: CGFloat) {
        ctx.useGrid(1024, canvas: size)
        let boost = opticalBoost(size)
        let white = color("#FFFFFF")

        // The tag, tilted 45 degrees so its tip points to the top-left.
        ctx.saveGState()
        ctx.translateBy(x: 448, y: 448)
        ctx.rotate(by: .pi / 4)
        ctx.addPath(tagPath(length: 560, height: 360, cornerRadius: 64, tipRadius: 56))
        ctx.setFillColor(white)
        ctx.fillPath()
        ctx.setBlendMode(.destinationOut)
        ctx.fillEllipse(in: circle(P(-164, 0), 34 * boost))       // string hole
        ctx.restoreGState()

        // Clock face (kept upright), cut out of the tag. At 16 px a plain round window reads better.
        ctx.setBlendMode(.destinationOut)
        if size < 24 {
            ctx.fillEllipse(in: circle(P(512, 512), 116))
            ctx.setBlendMode(.normal)
            return
        }
        ctx.setStrokeColor(white)
        ctx.setLineWidth(32 * boost)
        ctx.strokeEllipse(in: circle(P(512, 512), 118))
        ctx.setLineWidth(30 * boost)
        ctx.setLineCap(.round)
        ctx.move(to: P(512, 444)); ctx.addLine(to: P(512, 512)); ctx.addLine(to: P(562, 512))
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.setBlendMode(.normal)
    }

    func drawMenuBarGlyph(in ctx: CGContext, size: CGFloat) {
        ctx.useGrid(18, canvas: size)
        ctx.saveGState()
        ctx.translateBy(x: 7.9, y: 7.9)
        ctx.rotate(by: .pi / 4)
        ctx.addPath(tagPath(length: 16.2, height: 10.4, cornerRadius: 1.6, tipRadius: 1.4))
        ctx.setLineWidth(1.5)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.fillEllipse(in: circle(P(-4.9, 0), 1.0))
        ctx.restoreGState()

        let c = P(9.75, 9.75)
        ctx.setLineWidth(1.2)
        ctx.strokeEllipse(in: circle(c, 2.9))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: P(c.x, c.y - 1.7)); ctx.addLine(to: c); ctx.addLine(to: P(c.x + 1.3, c.y))
        ctx.strokePath()
    }
}

// MARK: - The concept contract

/// Background and symbol colors of one concept. Hex strings, "#RRGGBB".
struct Palette {
    /// Background gradient, top to bottom. Keep the top a little lighter.
    var top: String
    var bottom: String
    /// The symbol is drawn white and shaded towards `symbolShade` at the bottom.
    var symbolShade: String
}

protocol IconConcept {
    var palette: Palette { get }

    /// Draws the white symbol on top of the background tile.
    /// The canvas is `size` x `size` pixels, origin top-left, y downward. The symbol is
    /// drawn into an empty layer, so blend mode `.destinationOut` cuts holes that reveal
    /// the background. `size` is the real pixel size (16...1024), handy for thickening
    /// strokes at tiny sizes.
    func drawIcon(in ctx: CGContext, size: CGFloat)

    /// Draws the menu bar glyph in black only (it is exported as a template image).
    /// The canvas is `size` x `size` points (18), origin top-left, y downward.
    func drawMenuBarGlyph(in ctx: CGContext, size: CGFloat)
}

let concepts: [String: any IconConcept] = ["a": HourglassBag(), "b": PausedBag(), "c": TagClock()]

// MARK: - Shared shapes

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }

/// Strokes get a little heavier at tiny sizes so they don't vanish at 16 px.
func opticalBoost(_ pixels: CGFloat) -> CGFloat {
    switch pixels {
    case ..<24: return 1.5
    case ..<48: return 1.25
    default: return 1
    }
}

/// Hourglass glass: straight under each cap, then an S-curve pinching into the neck.
/// `half` is the half-width at top and bottom, `neck` the half-width at the waist,
/// `waist` how far the curves' handles reach from the middle (smaller = sharper pinch).
func hourglassGlass(cx: CGFloat, top: CGFloat, bottom: CGFloat, half: CGFloat, neck: CGFloat,
                    shoulder: CGFloat, waist: CGFloat) -> CGPath {
    let mid = (top + bottom) / 2
    let r = cx + half, l = cx - half, nr = cx + neck, nl = cx - neck
    let p = CGMutablePath()
    p.move(to: P(r, top))
    p.addLine(to: P(r, top + shoulder))
    p.addCurve(to: P(nr, mid), control1: P(r, mid - waist), control2: P(nr, mid - waist))
    p.addCurve(to: P(r, bottom - shoulder), control1: P(nr, mid + waist), control2: P(r, mid + waist))
    p.addLine(to: P(r, bottom))
    p.addLine(to: P(l, bottom))
    p.addLine(to: P(l, bottom - shoulder))
    p.addCurve(to: P(nl, mid), control1: P(l, mid + waist), control2: P(nl, mid + waist))
    p.addCurve(to: P(l, top + shoulder), control1: P(nl, mid - waist), control2: P(l, mid - waist))
    p.addLine(to: P(l, top))
    p.closeSubpath()
    return p
}

/// A trapezoid with rounded corners (a bag body), centered on `cx`.
func roundedTrapezoid(cx: CGFloat, top: CGFloat, bottom: CGFloat, topHalf: CGFloat, bottomHalf: CGFloat,
                      topRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addRoundedPolygon([P(cx - topHalf, top), P(cx + topHalf, top), P(cx + bottomHalf, bottom), P(cx - bottomHalf, bottom)],
                        radii: [topRadius, topRadius, bottomRadius, bottomRadius])
    return p
}

/// A price tag lying on its side, tip pointing left, centered on (0, 0). The tip is a right angle.
func tagPath(length: CGFloat, height: CGFloat, cornerRadius: CGFloat, tipRadius: CGFloat) -> CGPath {
    let tip = -length / 2, shoulder = -length / 2 + height / 2, end = length / 2
    let p = CGMutablePath()
    p.addRoundedPolygon([P(tip, 0), P(shoulder, -height / 2), P(end, -height / 2), P(end, height / 2), P(shoulder, height / 2)],
                        radii: [tipRadius, cornerRadius * 0.6, cornerRadius, cornerRadius, cornerRadius * 0.6])
    return p
}

/// Apple-style rounded square with continuous ("squircle") corners: each corner is a short
/// circular arc eased into the straight edges by two Bezier curves, so curvature never jumps.
/// `smoothing` 0 gives a plain rounded rect; 0.6 matches the iOS/macOS icon shape.
func squircle(_ rect: CGRect, radius: CGFloat, smoothing: CGFloat = 0.6) -> CGPath {
    let deg = CGFloat.pi / 180
    let p = min((1 + smoothing) * radius, min(rect.width, rect.height) / 2)   // corner length along each edge
    let arcAngle = 90 * (1 - smoothing)
    let arcLength = sin(arcAngle / 2 * deg) * radius * sqrt(2)
    let alpha = (90 - arcAngle) / 2
    let p3ToP4 = radius * tan(alpha / 2 * deg)
    let beta = 45 * smoothing
    let c = p3ToP4 * cos(beta * deg)
    let d = c * tan(beta * deg)
    let b = (p - arcLength - c - d) / 3
    let a = 2 * b

    // Corners in drawing order with their incoming (ex) and outgoing (ey) edge directions.
    let corners: [(CGPoint, CGVector, CGVector)] = [
        (P(rect.maxX, rect.minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
        (P(rect.maxX, rect.maxY), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0)),
        (P(rect.minX, rect.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
        (P(rect.minX, rect.minY), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)),
    ]
    let path = CGMutablePath()
    path.move(to: P(rect.minX + p, rect.minY))
    for (corner, ex, ey) in corners {
        // Point at distance u before the corner (along ex) and v after it (along ey).
        func q(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            P(corner.x - u * ex.dx + v * ey.dx, corner.y - u * ex.dy + v * ey.dy)
        }
        path.addLine(to: q(p, 0))
        path.addCurve(to: q(arcLength + d, d), control1: q(p - a, 0), control2: q(p - a - b, 0))
        // Circular part: tangent lines at both ends meet on the corner's diagonal.
        let center = q(radius, radius)
        let reach = radius / cos(arcAngle / 2 * deg) / sqrt(2)
        let tangentsMeet = P(center.x + reach * (ex.dx - ey.dx), center.y + reach * (ex.dy - ey.dy))
        path.addArc(tangent1End: tangentsMeet, tangent2End: q(d, arcLength + d), radius: radius)
        path.addCurve(to: q(0, p), control1: q(0, p - a - b), control2: q(0, p - a))
    }
    path.closeSubpath()
    return path
}

extension CGMutablePath {
    /// A closed polygon whose corners are rounded with the matching radius.
    func addRoundedPolygon(_ points: [CGPoint], radii: [CGFloat]) {
        let first = points[0], last = points[points.count - 1]
        move(to: P((first.x + last.x) / 2, (first.y + last.y) / 2))
        for i in points.indices {
            addArc(tangent1End: points[i], tangent2End: points[(i + 1) % points.count], radius: radii[i])
        }
        closeSubpath()
    }
}

// MARK: - Colors and context helpers

/// "#RRGGBB" (or "#RRGGBBAA") to an sRGB color.
func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    guard let value = UInt64(digits, radix: 16), digits.count == 6 || digits.count == 8 else {
        fatalError("Bad color \"\(hex)\", expected #RRGGBB")
    }
    let rgb = digits.count == 8 ? value >> 8 : value
    let a = digits.count == 8 ? CGFloat(value & 0xFF) / 255 : 1
    return CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                   green: CGFloat((rgb >> 8) & 0xFF) / 255,
                   blue: CGFloat(rgb & 0xFF) / 255,
                   alpha: a * alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

extension CGContext {
    /// Scales the context so that a `grid` x `grid` design fills a `canvas`-sized canvas.
    func useGrid(_ grid: CGFloat, canvas: CGFloat) {
        scaleBy(x: canvas / grid, y: canvas / grid)
    }

    /// Device pixels per user-space unit (shadows ignore the transform, so we convert).
    var pixelsPerUnit: CGFloat { sqrt(ctm.a * ctm.a + ctm.b * ctm.b) }

    /// A soft shadow measured in the current units; positive `dy` falls downward.
    func setSoftShadow(dy: CGFloat, blur: CGFloat, color: CGColor) {
        let k = pixelsPerUnit
        setShadow(offset: CGSize(width: 0, height: -dy * k), blur: blur * k, color: color)
    }

    func verticalGradient(_ g: CGGradient, from y0: CGFloat, to y1: CGFloat) {
        drawLinearGradient(g, start: P(0, y0), end: P(0, y1),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Draws an image upright in a y-down context.
    func drawUpright(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: CGRect(origin: .zero, size: rect.size))
        restoreGState()
    }

    /// Draws a template image (black + alpha) tinted with `tint`, like the menu bar does.
    func drawTemplate(_ image: CGImage, in rect: CGRect, tint: CGColor) {
        saveGState()
        beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        drawUpright(image, in: rect)
        setBlendMode(.sourceIn)
        setFillColor(tint)
        fill(rect)
        endTransparencyLayer()
        restoreGState()
    }
}

/// A transparent sRGB canvas with a top-left origin and y growing downward.
func makeCanvas(width: Int, height: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    return ctx
}

// MARK: - Renderer: tile, shadow, background, symbol

enum Renderer {
    // macOS icon grid (Big Sur and later), in a 1024 canvas.
    static let grid: CGFloat = 1024
    static let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let tileCornerRadius: CGFloat = 185.4

    static func icon(_ concept: any IconConcept, pixels: Int) -> CGImage {
        let size = CGFloat(pixels)
        let ctx = makeCanvas(width: pixels, height: pixels)
        let palette = concept.palette
        let shape = squircle(tile, radius: tileCornerRadius)

        ctx.saveGState()
        ctx.useGrid(grid, canvas: size)

        // Drop shadow under the tile, as in Apple's template.
        ctx.setSoftShadow(dy: 12, blur: 24, color: color("#000000", alpha: 0.30))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(shape)
        ctx.clip()

        // Background: vertical gradient, lighter at the top, plus a faint sheen.
        ctx.verticalGradient(gradient([color(palette.top), color(palette.bottom)]), from: tile.minY, to: tile.maxY)
        ctx.drawRadialGradient(gradient([color("#FFFFFF", alpha: 0.14), color("#FFFFFF", alpha: 0)]),
                               startCenter: P(512, 100), startRadius: 0, endCenter: P(512, 100), endRadius: 620,
                               options: [])

        // Hairline highlight along the top inner edge.
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.setLineWidth(8)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.verticalGradient(gradient([color("#FFFFFF", alpha: 0.35), color("#FFFFFF", alpha: 0)]), from: tile.minY, to: 420)
        ctx.restoreGState()

        // Symbol: drawn by the concept into its own layer, softly shadowed and shaded.
        ctx.saveGState()
        ctx.setSoftShadow(dy: 8, blur: 20, color: color("#000000", alpha: 0.16))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.saveGState()
        ctx.scaleBy(x: grid / size, y: grid / size)   // back to a pixel-sized canvas for the concept
        ctx.setFillColor(color("#FFFFFF"))
        ctx.setStrokeColor(color("#FFFFFF"))
        concept.drawIcon(in: ctx, size: size)
        ctx.restoreGState()
        ctx.setBlendMode(.sourceAtop)
        ctx.verticalGradient(gradient([color("#FFFFFF"), color(palette.symbolShade)]), from: 200, to: 824)
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        ctx.endTransparencyLayer()
        ctx.restoreGState()
        return ctx.makeImage()!
    }

    /// Menu bar glyph as a template image: pure black, shape carried by alpha only.
    static func menuBarGlyph(_ concept: any IconConcept, scale: Int) -> CGImage {
        let points: CGFloat = 18
        let pixels = Int(points) * scale
        let ctx = makeCanvas(width: pixels, height: pixels)
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        ctx.setFillColor(color("#000000"))
        ctx.setStrokeColor(color("#000000"))
        concept.drawMenuBarGlyph(in: ctx, size: points)
        return forceBlack(ctx.makeImage()!)
    }

    /// Guarantees a template image: every pixel's color becomes black, alpha is kept.
    static func forceBlack(_ image: CGImage) -> CGImage {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for row in 0..<ctx.height {
            for col in 0..<ctx.width {
                let i = row * ctx.bytesPerRow + col * 4
                bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0
            }
        }
        return ctx.makeImage()!
    }
}

// MARK: - Previews

enum Previews {
    static let background = color("#8E8E93")
    static let lightBar = color("#ECECEE"), lightTint = color("#000000", alpha: 0.85)
    static let darkBar = color("#2A2A2D"), darkTint = color("#FFFFFF", alpha: 0.92)

    /// One row per concept: icon at 128 px, icon at 32 px, menu bar glyph (18 pt @2x)
    /// on a light and on a dark menu bar strip.
    static func sheet(_ list: [any IconConcept]) -> CGImage {
        let pad: CGFloat = 72, gap: CGFloat = 64, rowHeight: CGFloat = 128, rowGap: CGFloat = 72
        let strip = CGSize(width: 176, height: 48)      // 24 pt menu bar at 2x
        let width = pad + 128 + gap + 32 + gap + strip.width + 40 + strip.width + pad
        let height = pad * 2 + rowHeight * CGFloat(list.count) + rowGap * CGFloat(list.count - 1)
        let ctx = makeCanvas(width: Int(width), height: Int(height))
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for (row, concept) in list.enumerated() {
            let y = pad + CGFloat(row) * (rowHeight + rowGap)
            var x = pad
            ctx.drawUpright(Renderer.icon(concept, pixels: 128), in: CGRect(x: x, y: y, width: 128, height: 128))
            x += 128 + gap
            ctx.drawUpright(Renderer.icon(concept, pixels: 32), in: CGRect(x: x, y: y + 48, width: 32, height: 32))
            x += 32 + gap
            let glyph = Renderer.menuBarGlyph(concept, scale: 2)
            for (bar, tint) in [(lightBar, lightTint), (darkBar, darkTint)] {
                let rect = CGRect(x: x, y: y + (rowHeight - strip.height) / 2, width: strip.width, height: strip.height)
                ctx.setFillColor(bar)
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
                ctx.fillPath()
                ctx.drawTemplate(glyph, in: CGRect(x: rect.midX - 18, y: rect.minY + 6, width: 36, height: 36), tint: tint)
                x += strip.width + 40
            }
        }
        return ctx.makeImage()!
    }

    /// Pixel-level view: 16 px and 32 px icons and the 1x / 2x glyphs, enlarged without smoothing.
    static func pixelZoom(_ list: [any IconConcept]) -> CGImage {
        let pad: CGFloat = 48, gap: CGFloat = 32, cell: CGFloat = 144
        let columns = 6
        let width = pad * 2 + cell * CGFloat(2) + 240 * CGFloat(columns - 2) + gap * CGFloat(columns - 1)
        let height = pad * 2 + cell * CGFloat(list.count) + gap * CGFloat(list.count - 1)
        let ctx = makeCanvas(width: Int(width), height: Int(height))
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .none

        for (row, concept) in list.enumerated() {
            let y = pad + CGFloat(row) * (cell + gap)
            var x = pad
            ctx.drawUpright(Renderer.icon(concept, pixels: 16), in: CGRect(x: x, y: y + 8, width: 128, height: 128))
            x += cell + gap
            ctx.drawUpright(Renderer.icon(concept, pixels: 32), in: CGRect(x: x, y: y + 8, width: 128, height: 128))
            x += cell + gap
            for (bar, tint) in [(lightBar, lightTint), (darkBar, darkTint)] {
                for scale in [1, 2] {
                    let stripImage = miniStrip(Renderer.menuBarGlyph(concept, scale: scale), scale: scale, bar: bar, tint: tint)
                    ctx.drawUpright(stripImage, in: CGRect(x: x, y: y, width: 240, height: 144))
                    x += 240 + gap
                }
            }
        }
        return ctx.makeImage()!
    }

    /// A 40 x 24 pt slice of menu bar with the glyph in the middle, at the given scale.
    static func miniStrip(_ glyph: CGImage, scale: Int, bar: CGColor, tint: CGColor) -> CGImage {
        let s = CGFloat(scale)
        let ctx = makeCanvas(width: 40 * scale, height: 24 * scale)
        ctx.setFillColor(bar)
        ctx.fill(CGRect(x: 0, y: 0, width: 40 * s, height: 24 * s))
        ctx.drawTemplate(glyph, in: CGRect(x: 11 * s, y: 3 * s, width: 18 * s, height: 18 * s), tint: tint)
        return ctx.makeImage()!
    }
}

// MARK: - Export

func writePNG(_ image: CGImage, to url: URL, scale: Int = 1) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw ToolError("cannot write \(url.path)")
    }
    let dpi = 72 * scale
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw ToolError("cannot write \(url.path)") }
    print("  wrote \(relative(url)) (\(image.width)x\(image.height))")
}

func export(_ concept: any IconConcept, root: URL) throws {
    let build = root.appendingPathComponent("build")
    let resources = root.appendingPathComponent("Resources")
    let iconset = build.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)

    // name in the iconset, point size, scale
    let entries: [(String, Int, Int)] = [
        ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2),
        ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
        ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2),
        ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
        ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2),
    ]
    for (name, points, scale) in entries {
        try writePNG(Renderer.icon(concept, pixels: points * scale),
                     to: iconset.appendingPathComponent("\(name).png"), scale: scale)
    }

    let icns = resources.appendingPathComponent("AppIcon.icns")
    try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", icns.path])
    print("  wrote \(relative(icns))")

    let screenshots = root.appendingPathComponent("Screenshots")
    try writePNG(Renderer.icon(concept, pixels: 1024), to: screenshots.appendingPathComponent("icon.png"))
    try writePNG(Renderer.menuBarGlyph(concept, scale: 1), to: resources.appendingPathComponent("MenuBarIcon.png"))
    try writePNG(Renderer.menuBarGlyph(concept, scale: 2), to: resources.appendingPathComponent("MenuBarIcon@2x.png"), scale: 2)
}

func renderPreviews(root: URL) throws {
    let dir = root.appendingPathComponent("build/icon-previews")
    let ordered = ["a", "b", "c"].map { concepts[$0]! }
    for key in ["a", "b", "c"] {
        try writePNG(Renderer.icon(concepts[key]!, pixels: 512), to: dir.appendingPathComponent("concept-\(key).png"))
    }
    try writePNG(Previews.sheet(ordered), to: dir.appendingPathComponent("sheet.png"))
    try writePNG(Previews.pixelZoom(ordered), to: dir.appendingPathComponent("pixels.png"))
}

// MARK: - Plumbing

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

func run(_ tool: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ToolError("\(tool) failed with status \(process.terminationStatus)")
    }
}

/// The repository root: the current directory if it holds Tools/make-icon.swift,
/// otherwise the folder above this script.
func repoRoot() -> URL {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("Tools/make-icon.swift").path) { return cwd }
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}

func relative(_ url: URL) -> String {
    let root = repoRoot().standardizedFileURL.path + "/"
    let path = url.standardizedFileURL.path
    return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
}

let usage = """
usage: swift Tools/make-icon.swift [--concept a|b|c] [--previews]
  (default)       export the selected concept (a) into Resources/ and Screenshots/icon.png
  --concept X     a = hourglass + bag, b = paused bag, c = tag + clock
  --previews      render build/icon-previews/{concept-a,concept-b,concept-c,sheet,pixels}.png
"""

var conceptKey = "a"
var wantsPreviews = false
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--concept":
        guard let key = args.popFirst()?.lowercased(), concepts[key] != nil else {
            FileHandle.standardError.write("error: --concept needs a, b or c\n\(usage)\n".data(using: .utf8)!)
            exit(2)
        }
        conceptKey = key
    case "--previews":
        wantsPreviews = true
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        FileHandle.standardError.write("error: unknown argument \(arg)\n\(usage)\n".data(using: .utf8)!)
        exit(2)
    }
}

do {
    let root = repoRoot()
    if wantsPreviews {
        print("Rendering previews…")
        try renderPreviews(root: root)
    } else {
        print("Exporting concept \(conceptKey.uppercased())…")
        try export(concepts[conceptKey]!, root: root)
    }
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
