import Foundation
import CoreGraphics

/// A small, bounded airflow model. Airflow and gravity are in screen coordinates.
public struct FlameDynamics {
    public private(set) var wind = CGPoint.zero
    public private(set) var bend: Double = 0
    public private(set) var verticalFlow: Double = 0
    public private(set) var mousePressure: Double = 0
    public private(set) var time: Double = 0
    private var bendVelocity: Double = 0

    public init() {}

    public mutating func advance(dt rawDT: Double, air: CGPoint, acceleration: CGPoint = .zero,
                                 mouseAvoidance: Double = 0, mousePressure rawPressure: Double = 0,
                                 level: Double) {
        guard rawDT > 0, rawDT.isFinite else { return }
        let dt = min(rawDT, 1.0 / 20.0)
        time += dt
        let smoothing = 1 - exp(-dt * 9)
        let ax = air.x.isFinite ? min(1_800, max(-1_800, air.x)) : 0
        let ay = air.y.isFinite ? min(1_800, max(-1_800, air.y)) : 0
        wind.x += (ax - wind.x) * smoothing
        wind.y += (ay - wind.y) * smoothing
        let strength = 0.72 + min(1, max(0, level)) * 0.48
        // Approximate aerodynamic drag: small air speeds barely bend the flame,
        // while stronger sweeps build displacement nonlinearly.
        let normalizedSpeed = min(1, abs(Double(wind.x)) / 900)
        let velocityBend = (wind.x < 0 ? -1 : 1) * 112 * pow(normalizedSpeed, 1.25) * strength
        let accelerationX = acceleration.x.isFinite ? min(18_000, max(-18_000, acceleration.x)) : 0
        let accelerationBend = min(1, max(-1, accelerationX / 12_000)) * 38
        // Mouse pressure is supplied only while moving; a stationary pointer
        // therefore cannot hold the plume compressed or pull it sideways.
        let pressure = min(1, max(0, rawPressure.isFinite ? rawPressure : 0))
        let avoidanceBend = min(1, max(-1, mouseAvoidance.isFinite ? mouseAvoidance : 0)) * pressure * 52
        let target = min(140, max(-140, velocityBend + accelerationBend + avoidanceBend))
        mousePressure += (pressure - mousePressure) * (1 - exp(-dt * 8))
        // Slightly underdamped response gives a visible, short sway after strong gusts.
        let omega = 5.0
        let dampingRatio = 0.82
        bendVelocity += ((target - bend) * omega * omega - 2 * dampingRatio * omega * bendVelocity) * dt
        bend += bendVelocity * dt
        bend = min(140, max(-140, bend))
        let accelerationY = acceleration.y.isFinite ? min(18_000, max(-18_000, acceleration.y)) : 0
        let verticalTarget = min(1, max(-1, Double(wind.y) / 700 + accelerationY / 45_000))
        verticalFlow += (verticalTarget - verticalFlow) * (1 - exp(-dt * 5))
    }

    /// Distance from a point to the mouse's swept path, in screen points.
    public static func distanceToSegment(_ point: CGPoint, from a: CGPoint, to b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0001 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    /// Minimum separation between the cursor's swept path and the flame column.
    public static func distanceBetweenSegments(_ a0: CGPoint, _ a1: CGPoint, _ b0: CGPoint, _ b1: CGPoint) -> Double {
        func cross(_ a: CGPoint, _ b: CGPoint) -> Double { a.x * b.y - a.y * b.x }
        let r = CGPoint(x: a1.x - a0.x, y: a1.y - a0.y)
        let s = CGPoint(x: b1.x - b0.x, y: b1.y - b0.y)
        let denominator = cross(r, s)
        let q = CGPoint(x: b0.x - a0.x, y: b0.y - a0.y)
        if abs(denominator) > 0.0001 {
            let t = cross(q, s) / denominator, u = cross(q, r) / denominator
            if (0...1).contains(t), (0...1).contains(u) { return 0 }
        }
        return min(distanceToSegment(a0, from: b0, to: b1), distanceToSegment(a1, from: b0, to: b1),
                   distanceToSegment(b0, from: a0, to: a1), distanceToSegment(b1, from: a0, to: a1))
    }

    public static func closestPoint(_ point: CGPoint, onSegmentFrom a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0001 else { return a }
        let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return CGPoint(x: a.x + t * dx, y: a.y + t * dy)
    }

    /// Smooth deterministic noise avoids a recognisable repeated flicker cycle.
    public static func noise(_ x: Double, seed: Double) -> Double {
        let cell = floor(x), fraction = x - cell
        func value(_ n: Double) -> Double {
            let v = sin(n * 127.1 + seed * 311.7) * 43758.5453123
            return (v - floor(v)) * 2 - 1
        }
        let t = fraction * fraction * (3 - 2 * fraction)
        return value(cell) * (1 - t) + value(cell + 1) * t
    }
}

/// Continuously sampled emission field in lighter-local coordinates.
public enum FlameField {
    public static func height(level: Double) -> Double {
        let level = min(1, max(0, level))
        return 25 + 22 * level + 37 * level * level
    }

    public static func center(height h: Double, time: Double, bend: Double, level: Double) -> Double {
        let h = min(1, max(0, h))
        let activity = 0.7 + 2.6 * level
        let slow = FlameDynamics.noise(time * 0.9 - h * 1.5, seed: 2.1)
        let detail = FlameDynamics.noise(time * (1.3 + level) - h * 3.5, seed: 8.3)
        return bend * h * h + activity * h * h * (slow + 0.35 * detail)
    }

    /// World-space plume centerline. The gas leaves along the lighter's nozzle
    /// axis, then turns smoothly toward screen-up as buoyancy takes over.
    /// `nozzleAngle` uses screen coordinates (positive y is up).
    public static func plumePoint(fraction rawFraction: Double, height: Double,
                                  nozzleAngle: Double, bend: Double = 0) -> CGPoint {
        let fraction = min(1, max(0, rawFraction))
        let rawAngle = nozzleAngle.isFinite ? nozzleAngle : 0
        // Rotation state can accumulate multiple full turns. Reduce it to the
        // shortest equivalent heading before blending toward world-up, or the
        // plume curls around the nozzle while trying to unwind those turns.
        var angle = atan2(sin(rawAngle), cos(rawAngle))
        if abs(abs(angle) - .pi) < 0.08 { angle = .pi }
        let bend = bend.isFinite ? min(140, max(-140, bend)) : 0
        guard fraction > 0 else { return .zero }
        // Keep integration sample count fixed across adjacent scan bands.
        // Variable counts introduced tiny positional discontinuities that read
        // as horizontal ripples when the plume was steeply bent.
        let steps = 32
        let step = fraction / Double(steps)
        var x = 0.0, y = 0.0
        for index in 0..<steps {
            let h = (Double(index) + 0.5) * step
            let t = min(1, max(0, (h - 0.035) / 0.42))
            let buoyancy = t * t * (3 - 2 * t)
            var heading = angle * (1 - buoyancy)
            // An inverted nozzle has two equivalent ways to turn upward. A
            // slight stable bias prevents frame-to-frame side switching.
            if abs(abs(angle) - .pi) < 0.08 { heading += 0.025 * (1 - buoyancy) }
            x += -sin(heading) * step * height
            y += cos(heading) * step * height
        }
        let eased = fraction * fraction
        return CGPoint(x: CGFloat(x + bend * eased), y: CGFloat(y))
    }

    /// Returns a premultiplied RGBA bitmap, top row first. The flame's root is at y = 0.
    public static func bitmap(width: Int, height: Int, level rawLevel: Double, time: Double, bend: Double) -> [UInt8] {
        guard width > 0, height > 0 else { return [] }
        let level = min(1, max(0, rawLevel))
        let safeTime = time.isFinite ? time : 0
        let wind = bend.isFinite ? min(25, max(-25, bend)) : 0
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let activity = 1.0 + level * 1.5
        let speed = 1.1 + level * 1.1
        func smooth(_ x: Double) -> Double {
            let t = min(1, max(0, x)); return t * t * (3 - 2 * t)
        }
        for row in 0..<height {
            let h = 1 - (Double(row) + 0.5) / Double(height)
            let rise = 1 - exp(-h * 22)
            let taper = pow(max(0, 1 - h), 0.52)
            let center = center(height: h, time: safeTime, bend: wind, level: level)
            let flow = FlameDynamics.noise(safeTime * speed - h * 4.5, seed: 4.8)
            let fine = FlameDynamics.noise(safeTime * speed * 0.65 - h * 7.0, seed: 13.1)
            let left = FlameDynamics.noise(safeTime * 1.2 - h * 5.5, seed: 5.7)
            let right = FlameDynamics.noise(safeTime * 0.95 - h * 6.2, seed: 19.2)
            let baseWidth = (5.6 + level * 3.2) * rise * taper * (0.94 + 0.12 * flow * h)
            let windNarrow = 1 - min(0.2, abs(wind) * 0.007)
            for col in 0..<width {
                // Draw region spans -48...48 points around the nozzle.
                let x = (Double(col) + 0.5) / Double(width) * 96 - 48
                let dx = x - center
                let sideNoise = dx < 0 ? left : right
                let halfWidth = max(0.1, baseWidth * windNarrow * (1 + 0.17 * sideNoise * h * activity))
                let q = abs(dx) / halfWidth
                let edge = 1 - smooth((q - 0.70) / 0.72)
                let rootFade = smooth(h / 0.025)
                let topFade = smooth((1 - h) / 0.09)
                let intensity = max(0, min(1, 0.78 + 0.12 * flow + 0.06 * fine + 0.07 * (dx / halfWidth)))
                let core = (1 - smooth((q - 0.10) / 0.90)) * (0.75 + 0.20 * flow)
                let blue = (1 - smooth((h - 0.025) / 0.09)) * (1 - smooth((q - 0.15) / 1.0))
                let alpha = min(0.92, max(0, edge * rootFade * topFade * intensity * (0.72 + core * 0.20)))
                let r = max(0, min(1, 1 - blue * 0.58))
                let g = max(0, min(1, 0.59 + 0.34 * core + 0.04 * fine + blue * 0.04))
                let b = max(0, min(1, 0.10 + 0.62 * core + blue * 0.55))
                let i = (row * width + col) * 4
                pixels[i] = UInt8((r * alpha * 255).rounded())
                pixels[i + 1] = UInt8((g * alpha * 255).rounded())
                pixels[i + 2] = UInt8((b * alpha * 255).rounded())
                pixels[i + 3] = UInt8((alpha * 255).rounded())
            }
        }
        return pixels
    }
}
