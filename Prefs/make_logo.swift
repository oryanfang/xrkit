// xrkit 自己的图标（设置列表、关于页、Sileo、调试版桌面图标）。
// 定稿（2026-11-13）：石墨黑底；上面一个淡薄荷绿的控制中心长条，里面是 XR（X 往右上那笔是扳手、
// R 的圆肚子是开关，直腿、圆头）+ 等宽小写 kit；下面两个暗方块：软件里的多任务图标
// square.stack.3d.up.fill、叠着的卡片。
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

func strokePath(_ ctx: CGContext, _ p: CGPath, _ width: CGFloat, _ color: CGColor, cap: CGLineCap = .square) {
    ctx.saveGState()
    ctx.addPath(p); ctx.setLineWidth(width); ctx.setLineCap(cap); ctx.setLineJoin(.miter)
    ctx.setStrokeColor(color); ctx.strokePath()
    ctx.restoreGState()
}

// 低饱和配色
let graphiteTop: UInt32 = 0x1C1F24, graphiteBot: UInt32 = 0x0D0F12
let sage: UInt32 = 0x9CCFB4       // 淡薄荷绿
let ink: UInt32 = 0xE6E8EB        // 线条白（略灰）

func graphiteBG(_ ctx: CGContext) {
    let g = CGGradient(colorsSpace: space, colors: [rgb(graphiteTop), rgb(graphiteBot)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 1024, y: 1024), options: [])
}

// 控制中心格子：打开 = 薄荷绿，关着 = 很淡的白
func ccTile(_ ctx: CGContext, _ r: CGRect, on: Bool) {
    ctx.addPath(rr(r, min(r.width, r.height) * 0.28))
    ctx.setFillColor(on ? rgb(sage, 0.92) : rgb(ink, 0.08)); ctx.fillPath()
}

// 等宽字体（SF Mono）
func mono(_ ctx: CGContext, _ text: String, at p: CGPoint, size: CGFloat, color: CGColor) {
    let font = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    (text as NSString).draw(at: NSPoint(x: p.x, y: p.y), withAttributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!])
    NSGraphicsContext.restoreGraphicsState()
}

// SF Symbol 画在 rect 中央（左上角原点的 CGContext）
func symbolGlyph(_ ctx: CGContext, _ name: String, _ r: CGRect, size: CGFloat, color: NSColor) {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold).applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    let s = img.size
    img.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height),
             from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
}

// 扳手：把手 a→b，b 外面是实心扳手头，开口沿把手方向
func wrench(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, width: CGFloat, head: CGFloat, color: CGColor) {
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    strokePath(ctx, seg(a, b), width, color, cap: .round)
    let dir = atan2(b.y - a.y, b.x - a.x), ux = cos(dir), uy = sin(dir)
    let c = CGPoint(x: b.x + ux * head * 0.5, y: b.y + uy * head * 0.5)
    ctx.addEllipse(in: CGRect(x: c.x - head, y: c.y - head, width: head * 2, height: head * 2)); ctx.setFillColor(color); ctx.fillPath()
    // 开口：从扳手头中心往外的一条圆头槽
    ctx.saveGState(); ctx.setBlendMode(.clear)
    ctx.addPath(seg(c, CGPoint(x: c.x + ux * head * 2, y: c.y + uy * head * 2)))
    ctx.setLineWidth(head * 0.82); ctx.setLineCap(.round); ctx.setStrokeColor(rgb(0)); ctx.strokePath()
    ctx.restoreGState()
    ctx.endTransparencyLayer()
}

// XR：X 左下→右上那笔是扳手；R 的圆肚子是开关（宽 0.7H、高 0.36H），竖线 + 直腿。字母高 H，笔画 = H × tr
func toolXR(_ ctx: CGContext, center c: CGPoint, H: CGFloat, tr: CGFloat, letterGap: CGFloat, color: CGColor) {
    let t = H * tr, wX = H * 0.56, gapL = H * letterGap, pillW = H * 0.7
    let left = c.x - (wX + gapL + pillW) / 2, top = c.y - H / 2, bot = c.y + H / 2
    strokePath(ctx, seg(P(left, top), P(left + wX, bot)), t, color, cap: .round)
    wrench(ctx, from: P(left, bot), to: P(left + wX - t * 0.7, top + t * 0.7), width: t, head: t * 1.15, color: color)
    let rx = left + wX + gapL, pillH = H * 0.36
    let pill = CGRect(x: rx - t * 0.5, y: top, width: pillW, height: pillH)
    strokePath(ctx, seg(P(rx, bot), P(rx, pill.maxY - t * 0.35)), t, color, cap: .round)
    strokePath(ctx, seg(P(rx + pillW * 0.32, pill.maxY + t * 0.2), P(rx + pillW * 0.7, bot)), t, color, cap: .round)
    let line = t * 0.7, r = pillH / 2
    strokePath(ctx, rr(pill, r), line, color, cap: .round)
    let k = r - line * 0.5 - H * 0.04
    ctx.addEllipse(in: CGRect(x: pill.maxX - r - k, y: pill.midY - k, width: k * 2, height: k * 2)); ctx.setFillColor(color); ctx.fillPath()
}

// 叠着的卡片（关着的格子里，淡色）：后面一张描边，前面一张实心描边，错开
func stackedCards(_ ctx: CGContext, _ r: CGRect) {
    let c = P(r.midX, r.midY), col = rgb(ink, 0.4), fillCol = rgb(0x262A30)
    let cw = r.width * 0.3, ch = cw * 1.9, t = cw * 0.11, rad = cw * 0.2
    let back = CGRect(x: c.x - cw * 0.35, y: c.y - ch * 0.62, width: cw * 1.1, height: ch)
    strokePath(ctx, rr(back, rad), t, col, cap: .round)
    let front = back.offsetBy(dx: -cw * 0.32, dy: ch * 0.24)
    ctx.addPath(rr(front, rad)); ctx.setFillColor(fillCol); ctx.fillPath()
    strokePath(ctx, rr(front, rad), t, col, cap: .round)
}

// 整个图标，画在 1024 画布上
func drawLogo(_ ctx: CGContext) {
    graphiteBG(ctx)
    let cell: CGFloat = 336, gap: CGFloat = 44, x0 = (1024 - cell * 2 - gap) / 2
    let wideH = cell * 0.9, totalH = wideH + gap + cell, y0 = (1024 - totalH) / 2
    let wide = CGRect(x: x0, y: y0, width: cell * 2 + gap, height: wideH)
    ccTile(ctx, wide, on: true)
    // 长条里：XR + 小写 kit，整组居中后往左挪长条宽度的 5%
    let H = wideH * 0.46, dark = rgb(graphiteBot), shiftLeft: CGFloat = 0.05, kitScale: CGFloat = 0.6
    let xrW = H * (0.56 + 0.4 + 0.7), kitW = H * 0.62, between = H * 0.42
    let groupL = wide.midX - (xrW + between + kitW) / 2 - wide.width * shiftLeft
    toolXR(ctx, center: P(groupL + xrW / 2, wide.midY), H: H, tr: 0.13, letterGap: 0.4, color: dark)
    let kit = CGRect(x: groupL + xrW + between, y: wide.midY - H / 2, width: kitW, height: H)
    mono(ctx, "kit", at: P(kit.minX - H * 0.05, kit.maxY - H * (0.12 + kitScale)), size: H * kitScale, color: dark)
    // 下面两格：多任务 SF Symbol、叠着的卡片
    let left = CGRect(x: x0, y: y0 + wideH + gap, width: cell, height: cell), right = left.offsetBy(dx: cell + gap, dy: 0)
    ccTile(ctx, left, on: false); ccTile(ctx, right, on: false)
    symbolGlyph(ctx, "square.stack.3d.up.fill", left, size: cell * 0.46, color: NSColor(white: 0.9, alpha: 0.42))
    stackedCards(ctx, right.insetBy(dx: cell * 0.12, dy: cell * 0.12))
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
