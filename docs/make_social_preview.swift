// GitHub 社交预览图（分享仓库链接时显示的大图，1280×640）：深蓝黑底，左边 xrkit 图标 + 名字 + 介绍，右边三张截图。
// 生成后要在 GitHub 网页上传：仓库 Settings › General › Social preview（没有 API）。
//   swift docs/make_social_preview.swift docs/social-preview.png          英文版（GitHub 用）
//   swift docs/make_social_preview.swift docs/social-preview-zh.png zh    中文版（分享用；中间的「设置 › 控制中心」是系统页面，跟手机语言，手机是英文）
import AppKit

let out = CommandLine.arguments.count >= 2 ? CommandLine.arguments[1] : "docs/social-preview.png"
let zh = CommandLine.arguments.count >= 3 && CommandLine.arguments[2] == "zh"
let W = 1280, H = 640
let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)   // 左下角原点

// 背景：和 xrkit 图标一样的深蓝到黑渐变
let bg = NSGradient(colors: [rgb(0x18212D), rgb(0x0A0F16), rgb(0x040609)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
bg.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -45)

// 右边三张截图（圆角、带一点阴影），中间那张靠前
func shot(_ name: String, _ rect: NSRect) {
    guard let img = NSImage(contentsOfFile: "docs/screenshots/\(name).png") else { return }
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowBlurRadius = 24; sh.shadowColor = NSColor(white: 0, alpha: 0.55); sh.shadowOffset = NSSize(width: 0, height: -6)
    sh.set()
    let path = NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22)
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    img.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    rgb(0xE6E8EB, 0.18).setStroke(); path.lineWidth = 2; path.stroke()
}
// 三张并排、互不遮挡（之前叠在一起，右边那张的文字被盖住了），中间那张稍微抬高
let sw: CGFloat = 180, gap: CGFloat = 16, shh = sw * 2796 / 1290
let x0: CGFloat = CGFloat(W) - 36 - 3 * sw - 2 * gap, y0 = (CGFloat(H) - shh) / 2
shot(zh ? "settings-zh" : "settings", NSRect(x: x0, y: y0 - 14, width: sw, height: shh))
shot("control-center", NSRect(x: x0 + sw + gap, y: y0 + 14, width: sw, height: shh))
shot(zh ? "homescreen-zh" : "homescreen", NSRect(x: x0 + 2 * (sw + gap), y: y0 - 14, width: sw, height: shh))

// 左边：图标 + 名字 + 介绍
if let icon = NSImage(contentsOfFile: "docs/xrkit-icon.png") {
    let r = NSRect(x: 80, y: 448, width: 120, height: 120)
    icon.draw(in: r)
    // 图标和背景同色系，描一圈很淡的边
    let rim = NSBezierPath(roundedRect: r.insetBy(dx: 0.75, dy: 0.75), xRadius: 27, yRadius: 27)
    rgb(0xE6E8EB, 0.14).setStroke(); rim.lineWidth = 1.5; rim.stroke()
}
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, mono: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
}
text("xrkit", 76, 330, 92, .bold, rgb(0xE6E8EB))
text(zh ? "iOS 17 越狱综合优化插件" : "All-in-one tweak for jailbroken iOS 17", 80, 285, 30, .medium, rgb(0xE6E8EB, 0.85))
text(zh ? "主屏幕 · 锁屏 · 控制中心 · 多任务" : "Home Screen · Lock Screen · Control Center · App Switcher", 80, 245, 21, .regular, rgb(0xE6E8EB, 0.55))
// 底部小标签
var x: CGFloat = 80
for tag in ["roothide", "iOS 17", "Sileo"] {
    let font = NSFont.monospacedSystemFont(ofSize: 19, weight: .medium)
    let w = (tag as NSString).size(withAttributes: [.font: font]).width + 28
    let r = NSRect(x: x, y: 168, width: w, height: 38)
    rgb(0x3DF5A8, 0.12).setFill(); NSBezierPath(roundedRect: r, xRadius: 19, yRadius: 19).fill()
    (tag as NSString).draw(at: NSPoint(x: x + 14, y: 176), withAttributes: [.font: font, .foregroundColor: rgb(0x5EEBC0)])
    x += w + 12
}

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
print("写好 \(out)")
