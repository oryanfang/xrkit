// xyrith 软件源图标（Sileo 里显示的 CydiaIcon.png）：米色底 + 珊瑚红→琥珀黄渐变的 XR。
// X 是 λ 形（一条长斜笔 + 左下短笔），R 没有竖笔（顶横 + 圆肚子 + 和 X 长笔平行的腿）。
//   swift docs/make_source_icon.swift <输出.png> [边长，默认 1024]
import AppKit

let args = CommandLine.arguments
let out = args.count >= 2 ? args[1] : "docs/xyrith-source-icon.png"
let side = args.count >= 3 ? Int(args[2]) ?? 1024 : 1024
let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(side)); ctx.scaleBy(x: 1, y: -1)   // 左上角原点
ctx.scaleBy(x: CGFloat(side) / 1024, y: CGFloat(side) / 1024)

// 米色底
ctx.setFillColor(rgb(0xF6EFE1)); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))

// 坐标照参考图（字母组在 165…630 × 372…795），放大 1.3 倍后居中
let s: CGFloat = 1.3, cx: CGFloat = 397, cy: CGFloat = 584
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 512 + (x - cx) * s, y: 512 + (y - cy) * s) }
let w: CGFloat = 86          // 笔画粗细（垂直于笔画方向）
let corner: CGFloat = 14     // 斜笔水平切口的小圆角

// 斜笔：从 (topX, topY) 到 (botX, botY)，上下两端水平切开，四个角带小圆角
func slab(_ topX: CGFloat, _ topY: CGFloat, _ botX: CGFloat, _ botY: CGFloat) -> CGPath {
    let k = (botX - topX) / (botY - topY)
    let half = w * sqrt(1 + k * k) / 2      // 水平方向的半宽
    let pts = [P(topX - half, topY), P(topX + half, topY), P(botX + half, botY), P(botX - half, botY)]
    let p = CGMutablePath()
    let r = corner * s
    p.move(to: CGPoint(x: (pts[0].x + pts[1].x) / 2, y: pts[0].y))
    for i in 1...4 { p.addArc(tangent1End: pts[i % 4], tangent2End: pts[(i + 1) % 4], radius: r) }
    p.closeSubpath()
    return p
}

var pieces: [CGPath] = []
// X：长斜笔（左上 → 右下）+ 左下短笔（顶端藏进长笔里，左边留出参考图那个小缺口）
pieces.append(slab(232, 372, 482, 795))
pieces.append(slab(335, 570, 207, 795))
// R：顶横（左端圆头）→ 圆肚子 → 回到左边；腿和 X 长笔平行，中间留一道窄缝，顶端藏进圆肚子里
let top: CGFloat = 372 + w / 2, bottom: CGFloat = 585, r = (bottom - top) / 2
let bowl = CGMutablePath()
bowl.move(to: P(400, top)); bowl.addLine(to: P(488, top))
bowl.addArc(center: P(488, top + r), radius: r * s, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
bowl.addLine(to: P(470, bottom))
pieces.append(bowl.copy(strokingWithWidth: w * s, lineCap: .round, lineJoin: .round, miterLimit: 10))
let slope = (482 - 232) / (795 - 372) as CGFloat
pieces.append(slab(610 - slope * (795 - 600), 600, 610, 795))

// 每块单独填同一个渐变（合在一条路径里填，重叠处会因为方向相反被抠出缝）
let g = CGGradient(colorsSpace: space, colors: [rgb(0xF4614A), rgb(0xF88B3F), rgb(0xFAC03B)] as CFArray, locations: [0, 0.5, 1])!
for piece in pieces {
    ctx.saveGState()
    ctx.addPath(piece); ctx.clip()
    ctx.drawLinearGradient(g, start: P(190, 380), end: P(630, 800), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
print("写好 \(out)")
