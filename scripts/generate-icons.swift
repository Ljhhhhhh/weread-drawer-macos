import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let mark = CGMutablePath()
mark.move(to: CGPoint(x: 2.3, y: 14.3))
mark.addLine(to: CGPoint(x: 5.5, y: 3.7))
mark.addLine(to: CGPoint(x: 9, y: 11.2))
mark.addLine(to: CGPoint(x: 12.5, y: 3.7))
mark.addLine(to: CGPoint(x: 15.7, y: 14.3))

func drawMark(_ context: CGContext, color: CGColor) {
    context.setStrokeColor(color)
    context.setLineWidth(2.2)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(mark)
    context.strokePath()
}

var bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
let pdfURL = resources.appendingPathComponent("MenuBar-template.pdf")
guard let pdf = CGContext(pdfURL as CFURL, mediaBox: &bounds, nil) else {
    fatalError("Cannot create menu bar icon")
}
pdf.beginPDFPage(nil)
drawMark(pdf, color: NSColor.black.cgColor)
pdf.endPDFPage()
pdf.closePDF()
precondition(CGPDFDocument(pdfURL as CFURL)?.page(at: 1)?.getBoxRect(.mediaBox) == bounds)

func appIcon(pixels: Int) throws -> Data {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Cannot render app icon")
    }
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    context.addPath(CGPath(roundedRect: tile, cornerWidth: 184, cornerHeight: 184, transform: nil))
    context.clip()
    let colors = [NSColor(srgbRed: 0.04, green: 0.16, blue: 0.20, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.12, green: 0.36, blue: 0.39, alpha: 1).cgColor]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100),
                               end: CGPoint(x: 512, y: 924), options: [])
    context.translateBy(x: 242, y: 242)
    context.scaleBy(x: 30, y: 30)
    drawMark(context, color: NSColor(srgbRed: 0.95, green: 0.97, blue: 0.93, alpha: 1).cgColor)
    let image = context.makeImage()!
    precondition(image.width == pixels && image.height == pixels)
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let iconset = temporary.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try appIcon(pixels: size * scale).write(to: iconset.appendingPathComponent(name))
    }
}
try appIcon(pixels: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
precondition(process.terminationStatus == 0, "App icon packaging failed")
