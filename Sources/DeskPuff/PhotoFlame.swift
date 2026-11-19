import AppKit
import DeskPuffCore
import ImageIO

/// Prepares the licensed flame footage once; frames are premultiplied for compositing.
final class PhotoFlame {
    // One source row per deformation band keeps the silhouette smooth at steep bends.
    private let columns = 4, rows = 4, width = 120, height = 276, stripCount = 276
    private var normal: [[CGImage]] = []
    private var normalCenters: [CGFloat] = []
    private var visibleHeightRatios: [CGFloat] = []
    var available: Bool { normal.count == 16 }

    init?() {
        guard let url = Bundle.module.url(forResource: "LighterFootage", withExtension: "png", subdirectory: "Resources"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil), atlas.width == 480, atlas.height == 1104 else { return nil }
        var frames: [[UInt8]] = []
        for index in 0..<columns * rows {
            let x = (index % columns) * width, y = (index / columns) * height
            guard let tile = atlas.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else { return nil }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(tile, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard ok else { return nil }
            for pixel in stride(from: 0, to: pixels.count, by: 4) {
                let peak = Double(max(pixels[pixel], pixels[pixel + 1], pixels[pixel + 2])) / 255
                let x = min(1, max(0, (peak - 0.025) / 0.175))
                let matte = x * x * (3 - 2 * x)
                let alpha = peak * matte
                for channel in 0..<3 { pixels[pixel + channel] = UInt8((Double(pixels[pixel + channel]) * matte).rounded()) }
                pixels[pixel + 3] = UInt8((alpha * 255).rounded())
            }
            frames.append(pixels)
        }
        for pixels in frames {
            guard let result = makeStrips(pixels) else { return nil }
            normal.append(result.0); normalCenters.append(result.1); visibleHeightRatios.append(result.2)
        }
    }

    private func makeStrips(_ pixels: [UInt8]) -> ([CGImage], CGFloat, CGFloat)? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        var weight: Double = 0, weightedX: Double = 0
        // The visible center of the stable middle section is used to cancel camera drift.
        for y in (height / 3)..<(height * 2 / 3) {
            for x in 0..<width {
                let a = Double(pixels[(y * width + x) * 4 + 3])
                weightedX += Double(x) * a; weight += a
            }
        }
        var firstVisibleRow = height, lastVisibleRow = 0
        for y in 0..<height {
            var visiblePixels = 0
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 12 { visiblePixels += 1 }
            if visiblePixels >= 2 { firstVisibleRow = min(firstVisibleRow, y); lastVisibleRow = max(lastVisibleRow, y) }
        }
        var strips: [CGImage] = []
        for index in 0..<stripCount {
            guard let strip = image.cropping(to: CGRect(x: 0, y: index * (height / stripCount), width: width, height: height / stripCount)) else { return nil }
            strips.append(strip)
        }
        let visibleHeight = CGFloat(max(1, lastVisibleRow - firstVisibleRow + 1)) / CGFloat(height)
        return (strips, weight > 0 ? CGFloat(weightedX / weight) : CGFloat(width) / 2, visibleHeight)
    }

    func draw(in context: CGContext, height: CGFloat, width displayWidth: CGFloat, bend: CGFloat, time: Double,
              nozzleAngle: CGFloat, nozzleOrigin: CGPoint, gentleMode: Bool,
              optimized: Bool = false, obstructions: [(CGPoint, CGPoint)] = []) {
        guard !normal.isEmpty else { return }
        // Keep the footage's full brightness variation. The smooth mode only
        // blends adjacent frames more frequently; it never averages brightness.
        let allFrames = normal, centers = normalCenters
        let count = allFrames.count, speed = gentleMode ? 24.0 : 10.0
        // Move forward through the captured motion instead of ping-ponging it,
        // which made the flame's sideways motion look like a regular sway.
        let phase = time * speed + FlameDynamics.noise(time * 0.22, seed: 41.7) * 0.55
        let position = phase.truncatingRemainder(dividingBy: Double(count))
        let first = Int(position), second = (first + 1) % count, mix = CGFloat(position - Double(first))
        let imageWidth = displayWidth
        let reference = centers.reduce(0, +) / CGFloat(centers.count)
        let referenceHeight = visibleHeightRatios.reduce(0, +) / CGFloat(visibleHeightRatios.count)
        let centerline = (0...stripCount).map {
            FlameField.plumePoint(fraction: Double($0) / Double(stripCount), height: Double(height),
                                  nozzleAngle: Double(nozzleAngle), bend: Double(bend))
        }
        func plume(_ h: CGFloat) -> CGPoint {
            let position = min(CGFloat(stripCount), max(0, h * CGFloat(stripCount)))
            let lower = min(stripCount, Int(position)), upper = min(stripCount, lower + 1)
            let mix = position - CGFloat(lower)
            let a = centerline[lower], b = centerline[upper]
            return CGPoint(x: a.x + (b.x-a.x)*mix, y: a.y + (b.y-a.y)*mix)
        }
        func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> (CGFloat, CGPoint) {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let t = length > 0.001 ? min(1, max(0, ((p.x-a.x)*dx + (p.y-a.y)*dy)/length)) : 0
            let closest = CGPoint(x: a.x + dx*t, y: a.y + dy*t)
            return (hypot(p.x-closest.x, p.y-closest.y), closest)
        }
        func capsule(_ a: CGPoint, _ b: CGPoint, radius: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let angle = atan2(b.y-a.y, b.x-a.x)
            let normal = CGPoint(x: -sin(angle)*radius, y: cos(angle)*radius)
            path.move(to: CGPoint(x: a.x+normal.x, y: a.y+normal.y))
            path.addLine(to: CGPoint(x: b.x+normal.x, y: b.y+normal.y))
            path.addArc(center: b, radius: radius, startAngle: angle + .pi/2, endAngle: angle - .pi/2, clockwise: true)
            path.addLine(to: CGPoint(x: a.x-normal.x, y: a.y-normal.y))
            path.addArc(center: a, radius: radius, startAngle: angle - .pi/2, endAngle: angle - 3 * .pi/2, clockwise: true)
            path.closeSubpath()
            return path
        }
        var bandGeometry: [(CGPoint, CGFloat, CGFloat)] = []
        func drawFrame(_ index: Int, alpha: CGFloat) {
            guard alpha > 0.001 else { return }
            context.saveGState(); context.setAlpha(alpha)
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            let drift = (reference - centers[index]) * imageWidth / CGFloat(self.width)
            let frameHeight = max(0.88, min(1.12, referenceHeight / visibleHeightRatios[index]))
            let frameRenderHeight = height * frameHeight
            let naturalPulse = CGFloat(FlameDynamics.noise(time * 0.72, seed: 18.2)) * 0.045
            let smoothHeight = frameRenderHeight * (1 + naturalPulse)
            if !obstructions.isEmpty {
                // Remove the cigarette's solid silhouette from the flame layer;
                // the nearby gas bends around it instead of rendering through it.
                let bounds = CGRect(x: nozzleOrigin.x - max(imageWidth, smoothHeight), y: nozzleOrigin.y - smoothHeight * 1.5,
                                    width: max(imageWidth, smoothHeight) * 2, height: smoothHeight * 3)
                let clipPath = CGMutablePath(); clipPath.addRect(bounds)
                let shift = CGAffineTransform(translationX: nozzleOrigin.x, y: nozzleOrigin.y)
                for obstruction in obstructions {
                    clipPath.addPath(capsule(obstruction.0, obstruction.1, radius: 7.5), transform: shift)
                }
                context.addPath(clipPath); context.clip(using: .evenOdd)
            }
            for strip in 0..<stripCount {
                let center: CGPoint, angle: CGFloat, contact: CGFloat
                if optimized && bandGeometry.count > strip {
                    (center, angle, contact) = bandGeometry[strip]
                } else {
                    let h = 1 - (CGFloat(strip) + 0.5) / CGFloat(stripCount)
                    let base = plume(h)
                    let p0 = plume(max(0, h - 0.006)), p1 = plume(min(1, h + 0.006))
                    var calculatedCenter = CGPoint(x: base.x, y: base.y)
                    var calculatedContact = CGFloat.zero
                    var pushX = CGFloat.zero, pushY = CGFloat.zero
                    for obstruction in obstructions {
                        let (distance, nearest) = segmentDistance(calculatedCenter, obstruction.0, obstruction.1)
                        let radius = imageWidth * 0.56 + 7.5
                        let coverage = min(1, max(0, 1 - distance / radius))
                        let influence = coverage * coverage * (3 - 2 * coverage)
                        calculatedContact = max(calculatedContact, influence)
                        if influence > 0.001 {
                            var nx = calculatedCenter.x - nearest.x, ny = calculatedCenter.y - nearest.y
                            let magnitude = hypot(nx, ny)
                            if magnitude < 0.01 {
                                let dx = obstruction.1.x - obstruction.0.x, dy = obstruction.1.y - obstruction.0.y
                                nx = abs(dx) > abs(dy) ? 0 : (bend < 0 ? -1 : 1)
                                ny = abs(dx) > abs(dy) ? (bend < 0 ? 1 : -1) : 0
                            } else { nx /= magnitude; ny /= magnitude }
                            pushX += nx * 7.5 * influence
                            pushY += ny * 7.5 * influence
                        }
                    }
                    let pushLength = hypot(pushX, pushY)
                    if pushLength > 8 { pushX *= 8 / pushLength; pushY *= 8 / pushLength }
                    calculatedCenter.x += pushX; calculatedCenter.y += pushY
                    let tangentX = p1.x - p0.x, tangentY = p1.y - p0.y
                    center = calculatedCenter; contact = calculatedContact
                    angle = atan2(-tangentX, tangentY)
                    if optimized { bandGeometry.append((center, angle, contact)) }
                }
                let bandHeight = smoothHeight / CGFloat(stripCount)
                context.saveGState()
                context.translateBy(x: nozzleOrigin.x + center.x, y: nozzleOrigin.y + center.y)
                context.rotate(by: angle)
                let stripWidth = imageWidth * (1 - contact * 0.10)
                // Adjacent deformed rows can expose hairline gaps when the
                // centerline bends. Slightly overlap them and composite each
                // frame source-over so the overlap closes seams without
                // accumulating brightness at every band boundary.
                let rect = CGRect(x: -stripWidth / 2 + drift, y: -bandHeight / 2,
                                  width: stripWidth, height: bandHeight + 0.8)
                context.setBlendMode(.normal)
                context.draw(allFrames[index][strip], in: rect)
                context.restoreGState()
            }
            context.restoreGState()
        }
        // Premultiplied additive interpolation inside an isolated layer avoids
        // the brightness dip produced by stacking two source-over frames.
        context.saveGState()
        if optimized {
            // Restrict the temporary compositing surface to the deformed plume.
            // Include the full strip width, drift and obstacle displacement.
            let margin = imageWidth * 1.5 + 24
            let minX = centerline.map(\.x).min() ?? 0
            let maxX = centerline.map(\.x).max() ?? 0
            let minY = centerline.map(\.y).min() ?? 0
            let maxY = centerline.map(\.y).max() ?? 0
            context.clip(to: CGRect(x: nozzleOrigin.x + minX - margin, y: nozzleOrigin.y + minY - margin,
                                    width: maxX - minX + 2 * margin, height: maxY - minY + 2 * margin))
        }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setBlendMode(.plusLighter)
        drawFrame(first, alpha: 1 - mix); drawFrame(second, alpha: mix)
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
