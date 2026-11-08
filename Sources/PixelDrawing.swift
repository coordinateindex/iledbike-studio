import SwiftUI

enum PixelDrawing {
    static var blank: [UInt8] { [UInt8](repeating: 0, count: 36 * 12 * 3) }

    // Fill skipped cells between drag events so a fast stroke stays continuous.
    static func line(_ pixels: inout [UInt8], from start: (Int, Int), to end: (Int, Int), rgb: [UInt8]) {
        guard pixels.count == 36 * 12 * 3, rgb.count == 3,
              (0..<36).contains(start.0), (0..<12).contains(start.1),
              (0..<36).contains(end.0), (0..<12).contains(end.1) else { return }
        var (x, y) = start
        let dx = abs(end.0 - x), dy = -abs(end.1 - y)
        let sx = x < end.0 ? 1 : -1, sy = y < end.1 ? 1 : -1
        var error = dx + dy
        while true {
            let i = (y * 36 + x) * 3
            pixels.replaceSubrange(i..<i + 3, with: rgb)
            if x == end.0 && y == end.1 { break }
            let twice = error * 2
            if twice >= dy { error += dy; x += sx }
            if twice <= dx { error += dx; y += sy }
        }
    }
}

struct PixelDrawingCanvas: View {
    @Binding var pixels: [UInt8]?
    let color: String
    let beginStroke: () -> Void
    @State private var lastCell: (Int, Int)?
    @State private var drawing = false

    var body: some View {
        GeometryReader { geometry in
            PixelPreview(raster: Raster(width: 36, height: 12, pixels: pixels ?? PixelDrawing.blank), offset: 0)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let step = min(geometry.size.width / 36, geometry.size.height / 12)
                        guard step > 0 else { return }
                        let x = Int(floor(value.location.x / step)), y = Int(floor(value.location.y / step))
                        guard (0..<36).contains(x), (0..<12).contains(y) else { lastCell = nil; return }
                        if !drawing { beginStroke(); drawing = true }
                        let n = UInt32(color.dropFirst(), radix: 16) ?? 0
                        let rgb = [UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)]
                        var next = pixels ?? PixelDrawing.blank
                        PixelDrawing.line(&next, from: lastCell ?? (x, y), to: (x, y), rgb: rgb)
                        pixels = next; lastCell = (x, y)
                    }
                    .onEnded { _ in lastCell = nil; drawing = false })
                .accessibilityLabel("36 by 12 pixel drawing canvas")
                .accessibilityHint("Click or drag to paint. Select Eraser to remove pixels.")
        }
    }
}
