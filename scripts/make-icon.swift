// 生成 App 图标：蓝紫渐变的圆角方块上两个对话气泡，后面的写 “A”，前面的写“文”（英译中）。
//   swift scripts/make-icon.swift            生成 Resources/AppIcon.icns
// 只用 AppKit 画，不需要设计软件；改颜色、图案就改这个文件再运行一次。
import AppKit

let size: CGFloat = 1024

func drawIcon() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // macOS 图标网格：1024 画布里内容占 824，四周留白，圆角约为边长的 22.5%。
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    let blue = NSColor(srgbRed: 0.24, green: 0.52, blue: 0.98, alpha: 1)
    let violet = NSColor(srgbRed: 0.43, green: 0.24, blue: 0.86, alpha: 1)
    NSGradient(starting: blue, ending: violet)!.draw(in: tilePath, angle: -60)

    // 后面的气泡：半透明白，尾巴朝左下。
    // 先在透明图层里画不透明的气泡和尾巴，再整体调透明度，重叠处不会出现接缝。
    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    context.setAlpha(0.38)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    fillBubble(NSRect(x: 190, y: 430, width: 440, height: 330), tailLeft: true, color: .white)
    context.endTransparencyLayer()
    context.restoreGState()
    text("A", in: NSRect(x: 190, y: 455, width: 440, height: 300), size: 230, weight: .bold,
         color: NSColor.white)

    // 前面的气泡：白色，尾巴朝右下。
    NSGraphicsContext.saveGraphicsState()
    let bubbleShadow = NSShadow()
    bubbleShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    bubbleShadow.shadowBlurRadius = 18
    bubbleShadow.shadowOffset = NSSize(width: 0, height: -6)
    bubbleShadow.set()
    // 在透明图层里画，阴影按整个气泡算一次，不会在尾巴和气泡重叠处叠出深色。
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    fillBubble(NSRect(x: 400, y: 250, width: 440, height: 330), tailLeft: false, color: .white)
    context.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()
    text("文", in: NSRect(x: 400, y: 280, width: 440, height: 290), size: 220, weight: .bold, color: violet)
    return rep
}

/// 圆角矩形加一个小尾巴的对话气泡。两部分分开填充：合成一条路径时方向相反，重叠处会被抵消成空洞。
func fillBubble(_ rect: NSRect, tailLeft: Bool, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 90, yRadius: 90).fill()
    let tail = NSBezierPath()
    let x = tailLeft ? rect.minX + 90 : rect.maxX - 90
    let dir: CGFloat = tailLeft ? -1 : 1
    tail.move(to: NSPoint(x: x - 45 * dir, y: rect.minY + 70))
    tail.line(to: NSPoint(x: x + 55 * dir, y: rect.minY - 70))
    tail.line(to: NSPoint(x: x + 40 * dir, y: rect.minY + 70))
    tail.close()
    tail.fill()
}

func text(_ string: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style,
    ]
    let attributed = NSAttributedString(string: string, attributes: attributes)
    let height = attributed.boundingRect(with: rect.size, options: .usesLineFragmentOrigin).height
    attributed.draw(in: NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height))
}

// 画好 1024 的原图，再缩成 iconutil 需要的各种尺寸，打包成 icns。
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = drawIcon()

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        NSGraphicsContext.current?.imageInterpolation = .high
        master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! small.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! iconutil.run()
iconutil.waitUntilExit()
try? master.representation(using: .png, properties: [:])!.write(
    to: FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-1024.png"))
print(iconutil.terminationStatus == 0 ? "✅ 已生成 \(output.path)" : "❌ iconutil 失败")
