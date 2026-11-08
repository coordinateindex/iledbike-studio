#if os(macOS)
import AppKit
#else
import UIKit
#endif
import ImageIO
import UniformTypeIdentifiers

struct Design: Codable {
    var version = 1
    var kind = "message"
    var text = "BOO!"
    var color = "#FF8A33"
    var scrolling = true
    var speed = 140
    var imagePixels: [UInt8]? = nil
    func validate() throws {
        guard version == 1, ["message", "image"].contains(kind), text.count <= 40,
              color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil,
              (1...255).contains(speed), imagePixels == nil || imagePixels?.count == 36 * 12 * 3 else {
            throw StudioError.invalid("This design file is invalid or uses an unsupported version.")
        }
        if kind == "image", imagePixels == nil { throw StudioError.invalid("The design has no image.") }
    }
    var rgb: [UInt8] {
        let value = UInt32(color.dropFirst(), radix: 16) ?? 0xffffff
        return [UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
    }
    func raster() throws -> Raster {
        try validate()
        if kind == "image", let imagePixels { return Raster(width: 36, height: 12, pixels: imagePixels) }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StudioError.invalid("Type a message first.") }
        return try Raster.text(text, rgb: rgb, scrolling: scrolling)
    }
    func program() throws -> [UInt8] {
        let image = try raster()
        if kind == "image" { return try BikeProtocol.imageProgram(pixels: image.pixels) }
        // One raster layer avoids this firmware’s broken native text/color composition.
        return try BikeProtocol.imageProgram(pixels: image.pixels, mode: scrolling ? 2 : 1, speed: UInt8(speed), imageWidth: image.width)
    }
}

struct Raster {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    static func text(_ text: String, rgb: [UInt8], scrolling: Bool) throws -> Raster {
        #if os(macOS)
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        #else
        let font = UIFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        #endif
        let label = NSAttributedString(string: text, attributes: attributes)
        let measured = label.size()
        let naturalWidth = Int(ceil(measured.width)) + 2
        guard naturalWidth <= 255 else { throw StudioError.invalid("Use a shorter message (up to about 40 characters).") }
        let width = scrolling ? max(36, naturalWidth) : 36
        if !scrolling && naturalWidth > 36 { throw StudioError.invalid("This message needs scrolling. Shorten it or turn on Scroll.") }
        let raster = try draw(width: width, height: 12) { context in
            context.setShouldAntialias(false)
            let x = naturalWidth < 36 ? CGFloat(36 - naturalWidth) / 2 + 1 : 1
            #if os(macOS)
            label.draw(at: NSPoint(x: x, y: (12 - measured.height) / 2))
            #else
            // UIKit text expects a top-left origin; raw bitmap contexts start bottom-left.
            context.translateBy(x: 0, y: 12)
            context.scaleBy(x: 1, y: -1)
            label.draw(at: CGPoint(x: x, y: (12 - measured.height) / 2))
            #endif
        }
        var pixels = raster.pixels
        for i in stride(from: 0, to: pixels.count, by: 3) {
            let lit = pixels[i] > 64 || pixels[i + 1] > 64 || pixels[i + 2] > 64
            for channel in 0..<3 { pixels[i + channel] = lit ? rgb[channel] : 0 }
        }
        return Raster(width: width, height: 12, pixels: pixels)
    }
    static func importImage(_ url: URL) throws -> Raster {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attrs[.size] as? NSNumber)?.intValue ?? Int.max <= 20_000_000,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw StudioError.invalid("Choose a supported image smaller than 20 MB.") }
        return try draw(width: 36, height: 12) { context in
            context.interpolationQuality = .high
            let ratio = min(36 / CGFloat(image.width), 12 / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
            context.draw(image, in: CGRect(x: (36 - size.width) / 2, y: (12 - size.height) / 2, width: size.width, height: size.height))
        }
    }
    static func draw(width: Int, height: Int, action: (CGContext) -> Void) throws -> Raster {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw StudioError.invalid("Cannot create preview.") }
        context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        #if os(macOS)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        action(context)
        NSGraphicsContext.restoreGraphicsState()
        #else
        UIGraphicsPushContext(context)
        action(context)
        UIGraphicsPopContext()
        #endif
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { throw StudioError.invalid("Cannot render image.") }
        var pixels = [UInt8](); pixels.reserveCapacity(width * height * 3)
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            pixels += [data[i], data[i + 1], data[i + 2]]
        }}
        return Raster(width: width, height: height, pixels: pixels)
    }
    func png() throws -> Data {
        #if os(macOS)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                      samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: width * 3, bitsPerPixel: 24)!
        pixels.withUnsafeBytes { bitmap.bitmapData!.update(from: $0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: pixels.count) }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw StudioError.invalid("Cannot export PNG.") }
        return data
        #else
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                                  bytesPerRow: width * 3, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let data = UIImage(cgImage: image).pngData() else { throw StudioError.invalid("Cannot export PNG.") }
        return data
        #endif
    }
}
