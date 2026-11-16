// xrkit 自己的图标（设置列表、关于页、Sileo、调试版桌面图标）。
// 定稿（2026-11-16，替换 11-13 那版）：xrsh 那种深蓝黑底；一个 X——一笔是白线，另一笔是控制中心的开关轨道，
// 轨道一头的圆点发光（薄荷→青）。两笔一样粗，白线穿进轨道里，只在轨道边框处断开一道缝（编织感）。
//
//   swift Prefs/make_logo.swift export Prefs/Resources Launcher/Resources
//   导出设置列表 icon*.png、关于页 About*.png、调试版桌面图标 AppIcon60x60@*.png，以及 docs/xrkit-icon.png（1024 原图）

import AppKit

let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
func rr(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }
func seg(_ a: CGPoint, _ b: CGPoint) -> CGPath { let p = CGMutablePath(); p.move(to: a); p.addLine(to: b); return p }

func strokePath(_ ctx: CGContext, _ p: CGPath, _ w: CGFloat, _ c: CGColor) {
    ctx.saveGState(); ctx.addPath(p); ctx.setLineWidth(w); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setStrokeColor(c); ctx.strokePath(); ctx.restoreGState()
}

let mint: UInt32 = 0x3DF5A8, cyan: UInt32 = 0x1AB8FF
let line = rgb(0xE8ECF0, 0.9)

// 发光填充：先带辉光填一次，再盖 薄荷→青 渐变
func fillGlow(_ ctx: CGContext, _ shape: CGPath, blur: CGFloat) {
    let b = shape.boundingBoxOfPath
    let g = CGGradient(colorsSpace: space, colors: [rgb(mint), rgb(cyan)] as CFArray, locations: [0, 1])!
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: blur, color: rgb(0x2EE6C0, 0.55))
    ctx.addPath(shape); ctx.setFillColor(rgb(mint)); ctx.fillPath(); ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(shape); ctx.clip()
    ctx.drawLinearGradient(g, start: P(b.minX, b.minY), end: P(b.maxX, b.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// 背景：深蓝到黑的斜向渐变 + 圆点附近一点柔光
func coldBG(_ ctx: CGContext) {
    let bg = CGGradient(colorsSpace: space, colors: [rgb(0x18212D), rgb(0x0A0F16), rgb(0x040609)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: .zero, end: P(1024, 1024), options: [])
    let c = P(660, 360)
    let glow = CGGradient(colorsSpace: space, colors: [rgb(mint, 0.08), rgb(mint, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: 480, options: [])
}

// 整个图标，画在 1024 画布上（左上角原点）。在转了 -45° 的坐标里画：轨道横着，白线竖着
func drawLogo(_ ctx: CGContext) {
    coldBG(ctx)
    let L: CGFloat = 620, H: CGFloat = 150, t: CGFloat = 24, gap: CGFloat = 18
    ctx.saveGState(); ctx.translateBy(x: 512, y: 512); ctx.rotate(by: -.pi / 4)
    let track = CGRect(x: -L / 2, y: -H / 2, width: L, height: H)
    // 白线：透明层里画，再把轨道边框经过的地方擦出一道缝
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    strokePath(ctx, seg(P(0, -L / 2), P(0, L / 2)), t, line)
    ctx.setBlendMode(.clear)
    strokePath(ctx, rr(track, H / 2), t + gap * 2, rgb(0))
    ctx.endTransparencyLayer()
    strokePath(ctx, rr(track, H / 2), t, line)
    let k = H / 2 - t / 2 - H * 0.16
    fillGlow(ctx, CGPath(ellipseIn: CGRect(x: L / 2 - H / 2 - k, y: -k, width: k * 2, height: k * 2), transform: nil), blur: 34)
    ctx.restoreGState()
}

func drawIcon(_ ctx: CGContext, side: CGFloat, rounded: Bool) {
    ctx.saveGState()
    if rounded { ctx.addPath(rr(CGRect(x: 0, y: 0, width: side, height: side), side * 0.225)); ctx.clip() }
    ctx.scaleBy(x: side / 1024, y: side / 1024)
    drawLogo(ctx)
    ctx.restoreGState()
}

func bitmap(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    return ctx.makeImage()!
}

func save(_ img: CGImage, _ path: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}

let args = CommandLine.arguments
guard args.count >= 3 && args[1] == "export" else { print("用法见文件开头"); exit(1) }
// 原图（1024，带圆角）留一份在 docs，以后 Sileo / 软件源用
save(bitmap(1024, 1024) { drawIcon($0, side: 1024, rounded: true) }, "docs/xrkit-icon.png")
for scale in [1, 2, 3] {
    let side = 29 * scale, suffix = scale == 1 ? "" : "@\(scale)x"
    let img = bitmap(side, side) { drawIcon($0, side: CGFloat(side), rounded: true) }
    for name in ["icon", "About"] { save(img, "\(args[2])/\(name)\(suffix).png") }
}
if args.count >= 4 {   // 调试版桌面图标：不切圆角（系统自己切）
    for scale in [2, 3] {
        let side = 60 * scale
        save(bitmap(side, side) { drawIcon($0, side: CGFloat(side), rounded: false) }, "\(args[3])/AppIcon60x60@\(scale)x.png")
    }
}
print("导出完成")
