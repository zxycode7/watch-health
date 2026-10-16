import AppKit
import CoreImage

// Input is a locally generated, short-lived pairing URL on stdin, never a command-line argument.
let text = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
guard CommandLine.arguments.count == 2,
      let filter = CIFilter(name: "CIQRCodeGenerator"), !text.isEmpty else {
    fputs("Usage: swift PairingQR.swift output.png < pairing-url\n", stderr)
    exit(1)
}
filter.setValue(Data(text.utf8), forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
guard let output = filter.outputImage else { exit(1) }
let image = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
let context = CIContext()
guard let cg = context.createCGImage(image, from: image.extent) else { exit(1) }
let padding = 40
let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cg.width + padding * 2,
    pixelsHigh: cg.height + padding * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: canvas.pixelsWide, height: canvas.pixelsHigh).fill()
NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)).draw(
    in: NSRect(x: padding, y: padding, width: cg.width, height: cg.height))
NSGraphicsContext.restoreGraphicsState()
try canvas.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
