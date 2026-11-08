import SwiftUI

struct PixelPreview: View {
    let raster: Raster?
    let offset: Int
    var body: some View {
        Canvas { context, size in
            let step = min(size.width / 36, size.height / 12)
            for y in 0..<12 { for x in 0..<36 {
                var color = Color.white.opacity(0.055)
                let sourceX = x + offset
                if let raster, sourceX >= 0, sourceX < raster.width {
                    let i = (y * raster.width + sourceX) * 3
                    let channels = (0..<3).map { Double(BikeProtocol.quantize(raster.pixels[i + $0])) / 15 }
                    if channels.contains(where: { $0 > 0 }) { color = Color(red: channels[0], green: channels[1], blue: channels[2]) }
                }
                let rect = CGRect(x: CGFloat(x) * step + step * 0.13, y: CGFloat(y) * step + step * 0.13, width: step * 0.74, height: step * 0.74)
                context.fill(Path(roundedRect: rect, cornerRadius: step * 0.2), with: .color(color))
            }}
        }.accessibilityLabel("36 by 12 LED pixel preview")
    }
}
