// 设置主页入口的小图标（29pt，SF Symbols 画的）。
//   swift Prefs/make_icons.swift candidates docs/root-icon-candidates.png   画候选对比图
//   swift Prefs/make_icons.swift export <A|B|C> Prefs/Resources            导出某一种风格的 png（@1x/@2x/@3x）
// 导出后再运行 python3 Prefs/make_plists.py，Root.plist 才会写上 icon。
import AppKit

struct Entry { let file: String; let label: String; let symbol: String; let color: NSColor }

let entries = [
    Entry(file: "SpringBoard",   label: "主屏幕",   symbol: "apps.iphone",             color: NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 1)),
    Entry(file: "LockScreen",    label: "锁屏",     symbol: "lock.fill",               color: NSColor(srgbRed: 0.35, green: 0.34, blue: 0.84, alpha: 1)),
    Entry(file: "ControlCenter", label: "控制中心", symbol: "switch.2",                color: NSColor(srgbRed: 0.56, green: 0.56, blue: 0.58, alpha: 1)),
    Entry(file: "Switcher",      label: "多任务",   symbol: "square.stack.3d.up.fill", color: NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1)),
    Entry(file: "Beta",          label: "Beta",     symbol: "flask.fill",              color: NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1)),
]

// xrkit 自己图标的蓝紫渐变（Prefs/Resources/icon.png）
let brandTop = NSColor(srgbRed: 0.40, green: 0.40, blue: 0.95, alpha: 1)
let brandBottom = NSColor(srgbRed: 0.20, green: 0.75, blue: 0.95, alpha: 1)

// style A：各自彩色底 + 白符号（系统设置风格）；B：统一 xrkit 渐变底 + 白符号；C：无底，彩色符号
func drawIcon(_ e: Entry, style: String, in rect: NSRect) {
    let radius = rect.width * 0.225
    let glyphColor: NSColor
    if style == "C" {
        glyphColor = e.color
    } else {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if style == "A" {
            e.color.setFill(); path.fill()
        } else {
            NSGradient(starting: brandTop, ending: brandBottom)!.draw(in: path, angle: -60)
        }
        glyphColor = .white
    }
    let pt = rect.width * (style == "C" ? 0.72 : 0.56)
    let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [glyphColor]))
    guard let img = NSImage(systemSymbolName: e.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
    // 按比例放进方块中间（宽高都不超过 70% / C 风格 86%）
    let limit = rect.width * (style == "C" ? 0.86 : 0.70)
    let s = min(limit / img.size.width, limit / img.size.height, 1)
    let size = NSSize(width: img.size.width * s, height: img.size.height * s)
    img.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
}

func png(_ size: NSSize, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
if args.count >= 3 && args[1] == "candidates" {
    // 三列，每列一个仿「设置」列表（@3x 尺寸）
    let s: CGFloat = 3, colW: CGFloat = 300 * s, rowH: CGFloat = 44 * s, top: CGFloat = 40 * s, pad: CGFloat = 16 * s
    let styles = [("A", "A  彩色底（系统设置风格）"), ("B", "B  统一 xrkit 渐变底"), ("C", "C  不加底色")]
    let size = NSSize(width: colW * 3 + pad * 4, height: top + rowH * CGFloat(entries.count) + pad * 2)
    let data = png(size) {
        NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (ci, (style, title)) in styles.enumerated() {
            let x0 = pad + CGFloat(ci) * (colW + pad)
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13 * s, weight: .medium), .foregroundColor: NSColor.darkGray]
            (title as NSString).draw(at: NSPoint(x: x0 + 4 * s, y: size.height - top + 10 * s), withAttributes: titleAttrs)
            let card = NSRect(x: x0, y: pad, width: colW, height: rowH * CGFloat(entries.count))
            NSColor.white.setFill()
            NSBezierPath(roundedRect: card, xRadius: 10 * s, yRadius: 10 * s).fill()
            for (ri, e) in entries.enumerated() {
                let y = card.maxY - rowH * CGFloat(ri + 1)
                drawIcon(e, style: style, in: NSRect(x: x0 + 16 * s, y: y + (rowH - 29 * s) / 2, width: 29 * s, height: 29 * s))
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17 * s), .foregroundColor: NSColor.black]
                let str = e.label as NSString
                str.draw(at: NSPoint(x: x0 + 60 * s, y: y + (rowH - str.size(withAttributes: attrs).height) / 2), withAttributes: attrs)
                let chev: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17 * s, weight: .semibold), .foregroundColor: NSColor.lightGray]
                ("›" as NSString).draw(at: NSPoint(x: card.maxX - 26 * s, y: y + (rowH - 22 * s) / 2), withAttributes: chev)
                if ri > 0 {
                    NSColor(white: 0.85, alpha: 1).setFill()
                    NSRect(x: x0 + 60 * s, y: y + rowH - 0.5 * s, width: colW - 60 * s, height: 0.5 * s).fill()
                }
            }
        }
    }
    try! data.write(to: URL(fileURLWithPath: args[2]))
    print("写好 \(args[2])")
} else if args.count >= 4 && args[1] == "export" {
    for e in entries {
        for scale in [1, 2, 3] {
            let side = CGFloat(29 * scale)
            let data = png(NSSize(width: side, height: side)) { drawIcon(e, style: args[2], in: NSRect(x: 0, y: 0, width: side, height: side)) }
            let name = scale == 1 ? "\(e.file).png" : "\(e.file)@\(scale)x.png"
            try! data.write(to: URL(fileURLWithPath: args[3]).appendingPathComponent(name))
        }
    }
    print("导出风格 \(args[2]) 到 \(args[3])")
} else {
    print("用法见文件开头")
}
