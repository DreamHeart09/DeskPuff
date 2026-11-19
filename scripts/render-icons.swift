import AppKit
import Foundation

func renderImage(_ source: URL, size: Int, destination: URL) throws {
    guard let image = NSImage(contentsOf: source) else {
        throw NSError(domain: "DeskPuffIconRenderer", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not load image at \(source.path)"])
    }
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                        pixelsWide: size,
                                        pixelsHigh: size,
                                        bitsPerSample: 8,
                                        samplesPerPixel: 4,
                                        hasAlpha: true,
                                        isPlanar: false,
                                        colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0,
                                        bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "DeskPuffIconRenderer", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Could not allocate \(size)x\(size) bitmap"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1,
               respectFlipped: true,
               hints: [.interpolation: NSImageInterpolation.high])
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DeskPuffIconRenderer", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try png.write(to: destination, options: .atomic)
}

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: render-icons.swift APP_IMAGE MENU_SVG OUTPUT_DIRECTORY\n", stderr)
    exit(2)
}

let appImage = URL(fileURLWithPath: CommandLine.arguments[1])
let menuSVG = URL(fileURLWithPath: CommandLine.arguments[2])
let output = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try renderImage(appImage, size: 1024, destination: output.appendingPathComponent("AppIcon.png"))
try renderImage(menuSVG, size: 72, destination: output.appendingPathComponent("MenuBarIcon-4x.png"))
