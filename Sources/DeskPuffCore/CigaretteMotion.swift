import Foundation
import CoreGraphics

public enum CigaretteMotionMode: String, CaseIterable, Identifiable {
    case free
    case gravity

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .free: "自由模式"
        case .gravity: "重力模式"
        }
    }
}

/// A light-weight rigid-body approximation for a cigarette in screen points.
/// Horizontal AshSurface segments are shared with the ash collision system.
public struct CigaretteRigidBody {
    public private(set) var center = CGPoint.zero
    public private(set) var velocity = CGPoint.zero
    public private(set) var angle = 0.0
    public private(set) var angularVelocity = 0.0
    public private(set) var isSleeping = true

    public init() {}

    public mutating func reset(center: CGPoint, angle: Double, velocity: CGPoint = .zero) {
        self.center = center
        self.angle = angle
        self.velocity = velocity
        angularVelocity = 0
        isSleeping = velocity == .zero
    }

    public mutating func release(with velocity: CGPoint, angularVelocity: Double = 0) {
        self.velocity = CGPoint(x: min(1000, max(-1000, velocity.x)),
                                y: min(1200, max(-1200, velocity.y)))
        self.angularVelocity = min(5, max(-5, angularVelocity))
        isSleeping = false
    }

    public mutating func setAngle(_ newAngle: Double, angularVelocity: Double) {
        angle = newAngle
        self.angularVelocity = min(5, max(-5, angularVelocity))
        isSleeping = false
    }

    public mutating func moveWhileHeld(to center: CGPoint, angle: Double) {
        self.center = center
        self.angle = angle
        velocity = .zero
        isSleeping = false
    }

    @discardableResult
    public mutating func advance(dt rawDT: Double, halfLength: Double, radius: Double,
                                 surfaces: [AshSurface], screenFloor: AshSurface,
                                 screenBounds: CGRect?) -> Bool {
        guard rawDT > 0, rawDT.isFinite else { return false }
        let dt = min(1.0 / 30.0, rawDT)
        let safeHalfLength = max(1, halfLength)
        let safeRadius = max(1, radius)
        let extentX = abs(cos(angle)) * safeHalfLength + abs(sin(angle)) * safeRadius
        let extentY = abs(sin(angle)) * safeHalfLength + abs(cos(angle)) * safeRadius
        let bottom = center.y - extentY
        if isSleeping {
            let restingOnSurface = ([screenFloor] + surfaces).contains { surface in
                let overlaps = center.x + extentX >= surface.x && center.x - extentX <= surface.x + surface.width
                return overlaps && abs(bottom - surface.y) <= 2.5
            }
            guard !restingOnSurface else { return false }
            isSleeping = false
        }

        let previousBottom = bottom
        velocity.y -= 1_450 * dt
        velocity.x *= exp(-0.10 * dt)
        angularVelocity *= exp(-0.48 * dt)
        center.x += velocity.x * dt
        center.y += velocity.y * dt
        angle += angularVelocity * dt

        if let screenBounds {
            let xRadius = abs(cos(angle)) * safeHalfLength + abs(sin(angle)) * safeRadius
            let minX = screenBounds.minX + xRadius, maxX = screenBounds.maxX - xRadius
            if center.x < minX { center.x = minX; velocity.x = abs(velocity.x) * 0.24; angularVelocity += 0.15 }
            if center.x > maxX { center.x = maxX; velocity.x = -abs(velocity.x) * 0.24; angularVelocity -= 0.15 }
        }

        let nextExtentY = abs(sin(angle)) * safeHalfLength + abs(cos(angle)) * safeRadius
        let nextBottom = center.y - nextExtentY
        let candidates = [screenFloor] + surfaces
        guard let support = candidates
            .filter({ center.x + extentX >= $0.x && center.x - extentX <= $0.x + $0.width })
            .filter({ previousBottom >= $0.y - 0.5 && nextBottom <= $0.y })
            .max(by: { $0.y < $1.y }) else { return false }

        let impactSpeed = max(0, -velocity.y)
        let impactX = min(support.x + support.width, max(support.x, center.x))
        let lever = impactX - center.x
        center.y += support.y - nextBottom
        if impactSpeed > 42 {
            velocity.y = impactSpeed * 0.10
            velocity.x *= 0.72
            angularVelocity += min(1.0, max(-1.0, -velocity.x * lever / (safeHalfLength * safeHalfLength) * 5))
        } else {
            velocity.y = 0
            velocity.x *= 0.48
            angularVelocity *= 0.62
        }
        if abs(cos(angle)) < 0.34 {
            let direction = angle >= 0 ? -1.0 : 1.0
            angularVelocity += direction * (impactSpeed > 42 ? 0.72 : 0.42)
            isSleeping = false
        }
        if abs(velocity.y) < 30 { velocity.y = 0 }
        if abs(velocity.x) < 5 { velocity.x = 0 }
        if abs(angularVelocity) < 0.06 { angularVelocity = 0 }
        if velocity == .zero && angularVelocity == 0 { isSleeping = true }
        return true
    }
}
