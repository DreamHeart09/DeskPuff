import Foundation
import CoreGraphics

public enum ToyState: Equatable {
    case closed, open, unlit, burning, inhaling, extinguished
}
public enum ToyAction {
    case openBox, takeCigarette, light, beginInhale, endInhale, extinguish, reset, cancel
}
public struct ToyModel {
    public private(set) var state: ToyState = .closed
    public private(set) var puffCount = 0
    public init() {}
    @discardableResult public mutating func send(_ action: ToyAction) -> Bool {
        switch (state, action) {
        case (_, .reset): state = .closed; puffCount = 0
        case (.closed, .openBox): state = .open
        case (.open, .takeCigarette): state = .unlit
        case (.unlit, .light): state = .burning
        case (.burning, .beginInhale): state = .inhaling
        case (.inhaling, .endInhale): state = .burning; puffCount += 1
        case (.inhaling, .cancel): state = .burning
        case (.burning, .extinguish), (.inhaling, .extinguish): state = .extinguished
        default: return false
        }
        return true
    }
}

public struct MotionSample {
    public let velocityX: Double
    public let velocityY: Double
    public init(dx: Double, dy: Double, dt: Double, maximumSpeed: Double = 1800) {
        guard dt > 0, dt < 0.25 else { velocityX = 0; velocityY = 0; return }
        let x = dx / dt, y = dy / dt
        let factor = min(1, maximumSpeed / max(hypot(x, y), 0.001))
        velocityX = x * factor; velocityY = y * factor
    }
}

public enum SmokeAmount: String, CaseIterable {
    case light, standard, heavy
    public var multiplier: Float {
        switch self {
        case .light: return 0.45
        case .standard: return 1
        case .heavy: return 2.25
        }
    }
    public var title: String {
        switch self {
        case .light: return "轻量"
        case .standard: return "标准"
        case .heavy: return "大量"
        }
    }
}

public enum CigaretteSmokeColorMode: String, Codable, CaseIterable {
    case inheritGlobal
    case custom
}

public struct CigarettePaperProfile: Codable, Equatable {
    public var color: String
    public var highlight: String
    public var shade: String
    public init(color: String = "#F5F4EE", highlight: String = "#FFFFFF", shade: String = "#D7D8D3") {
        self.color = color; self.highlight = highlight; self.shade = shade
    }
}

public struct CigaretteFilterProfile: Codable, Equatable {
    public var color: String
    public var highlight: String
    public var shade: String
    public var band: String
    public init(color: String = "#BE955A", highlight: String = "#E5C98D", shade: String = "#8E6538", band: String = "#9B7446") {
        self.color = color; self.highlight = highlight; self.shade = shade; self.band = band
    }
}

public struct CigaretteSmokeProfile: Codable, Equatable {
    public var emissionMultiplier: Double
    public var colorMode: CigaretteSmokeColorMode
    public var color: String
    public init(emissionMultiplier: Double = 1, colorMode: CigaretteSmokeColorMode = .inheritGlobal, color: String = "#C7CDD2") {
        self.emissionMultiplier = emissionMultiplier; self.colorMode = colorMode; self.color = color
    }
}

public struct CigaretteStyleArtwork: Codable, Equatable {
    public var paper: String?
    public var filter: String?
    public var preview: String?
    public init(paper: String? = nil, filter: String? = nil, preview: String? = nil) {
        self.paper = paper; self.filter = filter; self.preview = preview
    }
}

/// Data-only appearance and smoke defaults for one cigarette profile.
public struct CigaretteStyleManifest: Codable, Equatable, Identifiable {
    public var schemaVersion: Int
    public var type: String
    public var id: String
    public var name: String
    public var author: String?
    public var license: String?
    public var diameterMM: Double
    public var paper: CigarettePaperProfile
    public var filter: CigaretteFilterProfile
    public var smoke: CigaretteSmokeProfile
    public var artwork: CigaretteStyleArtwork?

    public init(id: String, name: String, diameterMM: Double = 7.8,
                paper: CigarettePaperProfile = .init(), filter: CigaretteFilterProfile = .init(),
                smoke: CigaretteSmokeProfile = .init(), artwork: CigaretteStyleArtwork? = nil,
                author: String? = nil, license: String? = nil) {
        schemaVersion = 1; type = "cigarette"; self.id = id; self.name = name; self.author = author
        self.license = license; self.diameterMM = diameterMM; self.paper = paper; self.filter = filter
        self.smoke = smoke; self.artwork = artwork
    }

    public func validationError() -> String? {
        guard schemaVersion == 1, type == "cigarette" else { return "unsupported style package version or type" }
        guard id.range(of: "^[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil else { return "invalid style id" }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else { return "invalid style name" }
        guard diameterMM.isFinite, (5.0...11.0).contains(diameterMM) else { return "diameterMM must be between 5 and 11" }
        guard smoke.emissionMultiplier.isFinite, (0.25...3.0).contains(smoke.emissionMultiplier) else { return "smoke.emissionMultiplier must be between 0.25 and 3" }
        let colors = [paper.color, paper.highlight, paper.shade, filter.color, filter.highlight, filter.shade, filter.band, smoke.color]
        guard colors.allSatisfy({ $0.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }) else {
            return "colors must use #RRGGBB"
        }
        return nil
    }
}

/// Tracks a bounded inhalation in equivalent seconds of idle burn.
public struct InhaleReservoir {
    public static let capacity: Double = 60
    public private(set) var amount: Double = 0
    public init() {}
    public var isFull: Bool { amount >= Self.capacity - 0.000001 }
    public mutating func take(seconds: Double, multiplier: Double) -> Double {
        guard seconds > 0, multiplier > 0, !isFull else { return 0 }
        let active = min(seconds, (Self.capacity - amount) / multiplier)
        amount = min(Self.capacity, amount + active * multiplier)
        return active
    }
}

/// Exhale strength reflects actual tobacco consumed while inhaling, with a
/// bounded release so a very long hold cannot flood the simulator at once.
public struct PuffProfile {
    public let duration: Double
    public let intensity: Double
    public let size: Double
    public let densityIntensity: Double
    public init(consumedBurnSeconds: Double) {
        let charge = min(InhaleReservoir.capacity, max(0, consumedBurnSeconds))
        duration = 0.55 + charge / 150
        intensity = charge > 0 ? 18 + 2 * sqrt(charge) : 0
        size = 1.2 + 1.8 * sqrt(charge / InhaleReservoir.capacity)
        // More inhaled smoke spreads over a wider area instead of saturating
        // the same pixels; total deposited smoke still increases with charge.
        densityIntensity = intensity * pow(1.2 / size, 0.9)
    }
    public func envelope(at elapsed: Double) -> Double {
        guard elapsed >= 0, elapsed < duration else { return 0 }
        let attack = 1 - exp(-elapsed / 0.035)
        let decay = exp(-elapsed / (duration * 0.32))
        let tail = min(1, max(0, (duration - elapsed) / (duration * 0.18)))
        return attack * decay * tail * densityIntensity
    }
}

/// Converts cigarette-local coordinates to the square rotation canvas.
public enum CigarettePose {
    public static let canvasSize: Double = 220
    public static let center = CGPoint(x: 95, y: 19)
    public static func canvasPoint(_ point: CGPoint, angle: Double) -> CGPoint {
        let x = point.x - center.x, y = point.y - center.y
        return CGPoint(x: canvasSize / 2 + x * cos(angle) - y * sin(angle),
                       y: canvasSize / 2 + x * sin(angle) + y * cos(angle))
    }
    public static func logicalPoint(_ point: CGPoint, angle: Double) -> CGPoint {
        let x = point.x - canvasSize / 2, y = point.y - canvasSize / 2
        return CGPoint(x: center.x + x * cos(angle) + y * sin(angle),
                       y: center.y - x * sin(angle) + y * cos(angle))
    }
    public static func rotationPivot(forX x: Double, tip: Double, screenScale: Double = 1) -> Double? {
        let end = 180.0
        // Aim for a fixed screen-space target but leave a central drag area.
        let zone = min(12 / max(screenScale, 0.1), max(0, end - tip) * 0.30)
        if x >= tip - 6 && x <= tip + zone { return end }
        if x <= end + 2 && x >= end - zone { return tip }
        return nil
    }
}

/// A display's reachable area. The menu-bar inset keeps the cigarette draggable.
public struct CigaretteBoundary {
    public let frame: CGRect
    public let usableTop: Double
    public init(frame: CGRect, usableTop: Double) { self.frame = frame; self.usableTop = usableTop }
}
public struct CigaretteContactResult {
    public let correction: CGPoint
    public let tipContact: Bool
    public let filterContact: Bool
    public let pressure: Double
}
public enum CigaretteContact {
    private static func segmentIntersects(_ a: CGPoint, _ b: CGPoint, _ rect: CGRect) -> Bool {
        var lower = 0.0, upper = 1.0
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let pairs: [(Double, Double)] = [(-dx, Double(a.x - rect.minX)), (dx, Double(rect.maxX - a.x)),
                                        (-dy, Double(a.y - rect.minY)), (dy, Double(rect.maxY - a.y))]
        for (direction, distance) in pairs {
            if abs(direction) < 0.000001 { if distance < 0 { return false }; continue }
            let t = distance / direction
            if direction < 0 { lower = max(lower, t) } else { upper = min(upper, t) }
            if lower > upper { return false }
        }
        return true
    }
    public static func resolve(tip: CGPoint, filter: CGPoint, previousTip: CGPoint, previousFilter: CGPoint,
                               screens: [CigaretteBoundary], obstacles: [CGRect]) -> CigaretteContactResult {
        guard !screens.isEmpty else { return CigaretteContactResult(correction: .zero, tipContact: false, filterContact: false, pressure: 0) }
        func correction(for point: CGPoint, previous: CGPoint) -> CGPoint {
            let areas = screens.map { screen -> CGRect in
                let f = screen.frame
                // Do not create a wall between vertically adjacent displays.
                let above = screens.contains { other in
                    other.frame != f && abs(other.frame.minY - f.maxY) < 2 &&
                    point.x >= other.frame.minX && point.x <= other.frame.maxX
                }
                let top = above ? f.maxY : min(f.maxY, screen.usableTop)
                return CGRect(x: f.minX, y: f.minY, width: f.width, height: max(0, top - f.minY))
            }
            if !areas.contains(where: { $0.contains(point) }) {
                let candidates = areas.map { rect -> CGPoint in
                    CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
                }
                if let closest = candidates.min(by: { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) }) {
                    return CGPoint(x: closest.x - point.x, y: closest.y - point.y)
                }
            }
            return .zero
        }
        let a = correction(for: tip, previous: previousTip), b = correction(for: filter, previous: previousFilter)
        let da = hypot(a.x, a.y), db = hypot(b.x, b.y)
        let screenDelta = da >= db ? a : b
        let correctedTip = CGPoint(x: tip.x + screenDelta.x, y: tip.y + screenDelta.y)
        let correctedFilter = CGPoint(x: filter.x + screenDelta.x, y: filter.y + screenDelta.y)
        // A bottom Dock is a raised portion of the floor, not a permeable box.
        // Check the whole segment after screen clamping, including when an input
        // event jumped completely through it or started within its footprint.
        for rect in obstacles where rect.width > rect.height {
            let bottomDock = screens.contains { screen in
                rect.maxY > screen.frame.minY && rect.minY <= screen.frame.minY + 2 &&
                rect.maxX > screen.frame.minX && rect.minX < screen.frame.maxX
            }
            guard bottomDock else { continue }
            let dx = correctedFilter.x - correctedTip.x
            var t0: CGFloat = 0, t1: CGFloat = 1
            if abs(dx) < 0.0001 {
                guard correctedTip.x >= rect.minX && correctedTip.x <= rect.maxX else { continue }
            } else {
                let u = (rect.minX - correctedTip.x) / dx, v = (rect.maxX - correctedTip.x) / dx
                t0 = max(0, min(u, v)); t1 = min(1, max(u, v))
                guard t0 <= t1 else { continue }
            }
            let y0 = correctedTip.y + (correctedFilter.y - correctedTip.y) * t0
            let y1 = correctedTip.y + (correctedFilter.y - correctedTip.y) * t1
            let lowest = min(y0, y1)
            guard lowest < rect.maxY - 0.01 else { continue }
            let prevLow = min(previousTip.y, previousFilter.y)
            let extra: CGPoint
            if prevLow < rect.maxY && max(previousTip.x, previousFilter.x) <= rect.minX {
                extra = CGPoint(x: rect.minX - max(correctedTip.x, correctedFilter.x), y: 0)
            } else if prevLow < rect.maxY && min(previousTip.x, previousFilter.x) >= rect.maxX {
                extra = CGPoint(x: rect.maxX - min(correctedTip.x, correctedFilter.x), y: 0)
            } else if prevLow < rect.maxY {
                // Recover gracefully from an already-overlapping position by the
                // nearest exit, instead of pulling every sideways move upward.
                let choices = [CGPoint(x: rect.minX - max(correctedTip.x, correctedFilter.x), y: 0),
                               CGPoint(x: rect.maxX - min(correctedTip.x, correctedFilter.x), y: 0),
                               CGPoint(x: 0, y: rect.maxY - lowest)]
                extra = choices.min(by: { hypot($0.x, $0.y) < hypot($1.x, $1.y) }) ?? .zero
            } else { extra = CGPoint(x: 0, y: rect.maxY - lowest) }
            let tipOnDock = correctedTip.x >= rect.minX && correctedTip.x <= rect.maxX && correctedTip.y < rect.maxY
            let filterOnDock = correctedFilter.x >= rect.minX && correctedFilter.x <= rect.maxX && correctedFilter.y < rect.maxY
            let total = CGPoint(x: screenDelta.x + extra.x, y: screenDelta.y + extra.y)
            return CigaretteContactResult(correction: total, tipContact: da > 0.01 || tipOnDock,
                                          filterContact: db > 0.01 || filterOnDock,
                                          pressure: min(1, max(hypot(total.x, total.y), hypot(extra.x, extra.y)) / 12))
        }
        if da > 0.01 || db > 0.01 {
            return CigaretteContactResult(correction: screenDelta, tipContact: da > 0.01, filterContact: db > 0.01,
                                          pressure: min(1, max(da, db) / 12))
        }
        // The ends can both lie outside the Dock while the middle crosses it.
        // Treat the whole centerline as solid, without falsely extinguishing it.
        for rect in obstacles {
            let interior = rect.insetBy(dx: 0.01, dy: 0.01)
            let tipSweep = segmentIntersects(previousTip, tip, interior)
            let filterSweep = segmentIntersects(previousFilter, filter, interior)
            let bodySweep = (1..<4).contains { index in
                let t = Double(index) / 4
                let old = CGPoint(x: previousTip.x + (previousFilter.x - previousTip.x) * t,
                                  y: previousTip.y + (previousFilter.y - previousTip.y) * t)
                let new = CGPoint(x: tip.x + (filter.x - tip.x) * t, y: tip.y + (filter.y - tip.y) * t)
                return segmentIntersects(old, new, interior)
            }
            guard segmentIntersects(tip, filter, interior) || tipSweep || filterSweep || bodySweep else { continue }
            let oldMid = CGPoint(x: (previousTip.x + previousFilter.x) / 2, y: (previousTip.y + previousFilter.y) / 2)
            let options = [CGPoint(x: rect.minX - max(tip.x, filter.x), y: 0),
                           CGPoint(x: rect.maxX - min(tip.x, filter.x), y: 0),
                           CGPoint(x: 0, y: rect.minY - max(tip.y, filter.y)),
                           CGPoint(x: 0, y: rect.maxY - min(tip.y, filter.y))]
            let candidates = options.filter { delta in
                if delta.x < 0 { return oldMid.x <= rect.minX }
                if delta.x > 0 { return oldMid.x >= rect.maxX }
                if delta.y < 0 { return oldMid.y <= rect.minY }
                return oldMid.y >= rect.maxY
            }
            if let nearest = (candidates.isEmpty ? options : candidates).min(by: { hypot($0.x, $0.y) < hypot($1.x, $1.y) }) {
                return CigaretteContactResult(correction: nearest, tipContact: tipSweep, filterContact: filterSweep,
                                              pressure: min(1, hypot(nearest.x, nearest.y) / 12))
            }
        }
        return CigaretteContactResult(correction: .zero, tipContact: false, filterContact: false, pressure: 0)
    }
}

/// One restrained local deformation profile for a single impact.
public enum CigaretteImpact {
    public static func compression(current: Double, speed: Double, pressure: Double) -> Double {
        let speedFactor = min(1, max(0, speed) / 1200)
        let depthFactor = min(1, max(0, pressure))
        return min(0.78, max(0, 0.08 + 0.38 * speedFactor + 0.16 * depthFactor))
    }
    /// Local accordion-like folds decay into the undamaged cylinder.
    public static func wrinkleOffset(distance: Double, compression: Double) -> Double {
        let d = distance
        guard d >= 0 && d < 24 else { return 0 }
        let fade = 1 - d / 24
        return min(1, max(0, compression)) * 0.38 * sin((d + 2) * 0.75) * fade * fade
    }
    /// Smooth pressure changes, including a small elastic recovery on release.
    public static func pressureAfter(current: Double, target: Double, elapsed: Double) -> Double {
        let start = min(1, max(0, current)), goal = min(1, max(0, target))
        let response = 1 - exp(-min(0.12, max(0, elapsed)) * 14)
        return start + (goal - start) * response
    }
    /// Temporary axial compression near the impact point; the filter stays fixed.
    public static func axialOffset(position: Double, damageAt: Double, pressure: Double) -> Double {
        let d = max(0, position - damageAt)
        guard d < 24 else { return 0 }
        let fade = 1 - d / 24
        return min(1, max(0, pressure)) * 3 * fade * fade
    }
    /// The damaged end rotates at a fixed material hinge, leaving the rest straight.
    public static func foldAngle(compression: Double, pressure: Double, direction: Double) -> Double {
        let amount = min(1, max(0, compression))
        guard amount > 0 else { return 0 }
        let strength = min(1, max(0, pressure))
        return (direction < 0 ? -1 : 1) * min(0.40, 0.06 + 0.22 * amount + 0.10 * strength)
    }
    /// Fold probability and angle are bounded by impact speed and obliqueness.
    public static func impactFold(speed: Double, pressure: Double, obliqueness: Double, sample: Double, direction: Double) -> (primary: Double, secondary: Double) {
        let speedFactor = min(1, max(0, speed) / 1200)
        let force = min(1, max(0, pressure)) * 0.45 + speedFactor * 0.55
        let oblique = min(1, max(0, obliqueness))
        let chance = 0.12 + 0.48 * oblique + 0.22 * force
        guard min(1, max(0, sample)) < chance else { return (0, 0) }
        let sign = direction < 0 ? -1.0 : 1.0
        let angle = min(0.34, 0.07 + 0.18 * force + 0.10 * oblique)
        let secondChance = force > 0.68 && oblique > 0.55 ? 0.10 : 0
        let secondary = min(1, max(0, sample * 7 - floor(sample * 7))) < secondChance
            ? -sign * min(0.06, angle * 0.22) : 0
        return (sign * angle, secondary)
    }
    public static func foldPoint(_ point: CGPoint, hingeX: Double, angle: Double) -> CGPoint {
        guard point.x < hingeX else { return point }
        let x = point.x - hingeX, y = point.y - 19
        return CGPoint(x: hingeX + x * cos(angle) - y * sin(angle),
                       y: 19 + x * sin(angle) + y * cos(angle))
    }
    public static func unfoldPoint(_ point: CGPoint, hingeX: Double, angle: Double) -> CGPoint {
        let x = point.x - hingeX, y = point.y - 19
        let unfolded = CGPoint(x: hingeX + x * cos(angle) + y * sin(angle),
                               y: 19 - x * sin(angle) + y * cos(angle))
        return unfolded.x < hingeX && point.x < hingeX + 8 ? unfolded : point
    }
    public static func damageConsumed(tip: Double, damageAt: Double) -> Bool { tip >= damageAt + 24 }
    public static func charLevel(ash: Double) -> Double { min(0.38, 0.12 + max(0, ash) * 0.26) }
    public static func fragmentLevel(ash: Double) -> Double { min(1, max(0, ash) + 0.18) }
}

/// Bounded variations for each crush, with injectable samples for verification.
public struct AshCrushProfile {
    public let charLevel: Double
    public let sizeVariation: Double
    public let fragmentCount: Int
    public init(ash: Double, baseCount: Int, impact: Double, charSample: Double, sizeSample: Double, countSample: Double) {
        func unit(_ value: Double) -> Double { min(1, max(0, value)) }
        charLevel = CigaretteImpact.charLevel(ash: ash) * (0.8 + 0.4 * unit(charSample))
        sizeVariation = 0.8 + 0.4 * unit(sizeSample)
        let countFactor = (1 + 0.3 * unit(impact)) * (0.7 + 0.6 * unit(countSample))
        fragmentCount = max(1, Int((Double(max(1, baseCount)) * countFactor).rounded()))
    }
}

/// Resolves a filter press into a tap, drag, or sustained inhale.
public struct FilterGesture {
    public enum State { case idle, pending, dragging, inhaling }
    public enum Result { case none, tap, dragFinished, puff }
    public private(set) var state: State = .idle
    public init() {}
    public mutating func begin() { state = .pending }
    public mutating func move(distance: Double) -> Bool {
        if state == .pending && distance >= 6 { state = .dragging }
        return state == .dragging
    }
    public mutating func hold() -> Bool {
        guard state == .pending else { return false }
        state = .inhaling
        return true
    }
    public mutating func end() -> Result {
        let result: Result
        switch state {
        case .idle: result = .none
        case .pending: result = .tap
        case .dragging: result = .dragFinished
        case .inhaling: result = .puff
        }
        state = .idle
        return result
    }
    public mutating func cancel() { state = .idle }
}

/// A deliberately approximate eight-minute idle burn; active inhaling burns faster.
public struct CigaretteBurn {
    public static let idleDuration: Double = 8 * 60
    public private(set) var progress: Double = 0
    public private(set) var ash: Double = 0
    public init() {}
    public var isFinished: Bool { progress >= 1 }
    public mutating func advance(seconds: Double, inhaling: Bool, inhaleMultiplier: Double = 10) {
        guard seconds > 0, !isFinished else { return }
        let burned = min(1 - progress, seconds * (inhaling ? inhaleMultiplier : 1) / Self.idleDuration)
        progress += burned
        ash = min(1, ash + burned * 3)
    }
    public mutating func shedAshForCrush() -> Double {
        let detached = ash; ash = 0; return detached
    }
    public mutating func shedAshIfFull() -> Double {
        guard ash >= 1 else { return 0 }
        return shedAsh(all: true)
    }
    public mutating func shedAsh(all: Bool = false, fraction: Double = 0.75) -> Double {
        guard ash >= 0.08 else { return 0 }
        let shed = all ? ash : ash * min(1, max(0, fraction))
        ash -= shed
        return shed
    }
}

public enum AshAmount: Int, CaseIterable {
    case light = 1, standard, heavy
    public var multiplier: Double { [3.0, 6.0, 30.0][rawValue - 1] }
    public var title: String { ["较少", "标准", "大量"][rawValue - 1] }
    public static func releaseBatchSize(for count: Int) -> Int {
        max(24, (max(0, count) + 5) / 6)
    }
    public func naturalCrumbCount(for ash: Double) -> Int {
        let count = particleCount(for: ash)
        return count == 0 ? 0 : max(1, Int(Double(count) * 0.012))
    }
    public func particleCount(for ash: Double) -> Int {
        guard ash > 0 else { return 0 }
        return max(1, Int(ash * 60 * multiplier))
    }
}

public enum SmokeDissipation: String, CaseIterable {
    case slow, normal, fast, never, noAccumulation
    public var title: String {
        switch self {
        case .slow: return "慢（6 分钟）"
        case .normal: return "正常（3 分钟）"
        case .fast: return "快（1 分钟）"
        case .never: return "永不消失"
        case .noAccumulation: return "不积累烟雾"
        }
    }
    public var duration: Double? {
        switch self {
        case .slow: return 360
        case .normal: return 180
        case .fast: return 60
        case .never: return nil
        case .noAccumulation: return 30
        }
    }
    public func opacity(after elapsed: Double) -> Double {
        guard let duration else { return 1 }
        return max(0, min(1, 1 - max(0, elapsed) / duration))
    }
}

public enum AshGeometry {
    public static func capLength(level: Double) -> Double { min(1, max(0, level)) * 24 }
    public static func detachedSize(level: Double, scale: Double) -> (width: Double, height: Double) {
        let scale = max(0.01, scale)
        // Match the attached cap's material footprint after its 0.85 vertical
        // paper transform: x spans capLength + 3.5, y spans 11.7...26.
        return ((capLength(level: level) + 3.5) * scale, (26 - 11.7) * 0.85 * scale)
    }
    public static func fragmentCount(level: Double, scale: Double, amount: AshAmount) -> Int {
        guard level > 0 else { return 0 }
        let size = detachedSize(level: level, scale: scale)
        let standard = max(1, Int((size.width * size.height / 3.5).rounded()))
        switch amount {
        case .light: return max(1, standard / 2)
        case .standard: return standard
        case .heavy: return standard * 5
        }
    }
}

public enum AshAppearance {
    public static func shade(seed: UInt32) -> Double { 0.20 + Double((seed &* 37) % 17) / 100 }
}

public struct AshSurface: Equatable {
    public let id: UInt32
    public let x: Double
    public let y: Double
    public let width: Double
    public let groupID: UInt32
    public init(id: UInt32, x: Double, y: Double, width: Double, groupID: UInt32? = nil) {
        self.id = id; self.x = x; self.y = y; self.width = width; self.groupID = groupID ?? id
    }
}

/// Approximate the upper edge of a rotated cigarette with stable short surfaces.
public enum CigaretteAshSurface {
    public static func segments(from start: CGPoint, to end: CGPoint, idBase: UInt32, count: Int = 12) -> [AshSurface] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let t0 = Double(index) / Double(count), t1 = Double(index + 1) / Double(count)
            let x0 = start.x + (end.x - start.x) * t0, x1 = start.x + (end.x - start.x) * t1
            let y0 = start.y + (end.y - start.y) * t0, y1 = start.y + (end.y - start.y) * t1
            return AshSurface(id: idBase &+ UInt32(index), x: min(x0, x1) - 0.5,
                              y: max(y0, y1), width: max(1, abs(x1 - x0) + 1), groupID: idBase)
        }
    }
}

public struct AshParticle {
    public var x: Double, y: Double, vx: Double, vy: Double
    public var size: Double
    public var support: UInt32?
    public var offset: Double = 0
    public var bounces: Int = 0
    public private(set) var restingOnPile = false
    public var shapeSeed: UInt32
    public var rotation: Double
    public var spin: Double
    public var pileSpread: Double = 0
    public var emberRemaining: Double = 0
    public var isClump = false
    public var visualWidthScale: Double = 1
    public var pendingImpactCrumbs: Int = 0
    public var impactScale: Double = 1
    public var breakApartAfter: Double?
    public var breakApartCount: Int = 0
    public var recoveryMaterial: RecoveryMaterial?
    public var recoveryMass = 0
    public var recoveryBatchID: UUID?
    public var recoveryBatch: AshRecoveryBatch? {
        guard recoveryMass > 0, let recoveryMaterial else { return nil }
        return AshRecoveryBatch(material: recoveryMaterial, id: recoveryBatchID)
    }
    public var fallAge: Double { fallTime }
    private var supportX: Double = 0
    private var supportY: Double = 0
    private var supportWidth: Double = 0
    private var supportGroup: UInt32?
    public var supportingSurfaceGroup: UInt32? { supportGroup }
    private var excludedGroup: UInt32?
    private var disturbedByWindow = false
    private var fallTime: Double = 0
    public init(x: Double, y: Double, vx: Double, vy: Double, size: Double, shapeSeed: UInt32 = 1, rotation: Double = 0, spin: Double = 0) {
        self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.size = size
        self.shapeSeed = shapeSeed; self.rotation = rotation; self.spin = spin
    }
    /// Release reserved crumbs once, when the intact clump first contacts a surface or pile.
    public mutating func takeImpactCrumbs(previousBounces: Int, floor: Double) -> Int {
        guard isClump, pendingImpactCrumbs > 0 else { return 0 }
        let onFloor = y - size / 2 <= floor + 0.05 && vy <= 0
        guard bounces > previousBounces || support != nil || restingOnPile || onFloor else { return 0 }
        let count = pendingImpactCrumbs
        pendingImpactCrumbs = 0
        emberRemaining = max(emberRemaining, 60.0)
        return count
    }
    /// Newly detached ash uses the same flutter and gravity as ash released by a moving window.
    public mutating func beginLooseFall() { disturbedByWindow = true; fallTime = 0 }
    public mutating func release(fromSurfaceGroup groupID: UInt32, impulseX: Double, impulseY: Double) {
        guard supportGroup == groupID, support != nil || restingOnPile else { return }
        support = nil; supportGroup = nil; restingOnPile = false
        excludedGroup = groupID
        vx += impulseX; vy += impulseY
        bounces = 0; disturbedByWindow = true; fallTime = 0
        spin = (shapeSeed % 2 == 0 ? 1 : -1) * 1.4
    }
    public mutating func rest(on other: AshParticle) {
        if pileSpread > 0 {
            let delta = x - other.x
            let direction = abs(delta) > 0.15 ? (delta < 0 ? -1.0 : 1.0) : (shapeSeed % 2 == 0 ? 1.0 : -1.0)
            let roll = (other.size + size) * min(pileSpread, 1) * 0.22
            x = other.x + direction * max(abs(delta), roll)
            if other.support != nil { x = min(max(x, other.supportX), other.supportX + other.supportWidth) }
            // Ash flakes are thin and irregular: allow partial, seed-varying
            // overlap, while keeping the flake above the underlying surface.
            let baseShare = 0.16 + Double(shapeSeed % 10) * 0.01
            let flakeShare = 0.28 + Double((shapeSeed / 10) % 9) * 0.01
            let layeredY = other.y + other.size * baseShare + size * flakeShare
            y = max(layeredY, other.y - other.size / 2 + size / 2)
        } else {
            y = other.y + (other.size + size) * 0.34
        }
        vx = 0; vy = 0; spin = 0; bounces = 1
        support = other.support; supportGroup = other.supportGroup; supportX = other.supportX; supportY = other.supportY; supportWidth = other.supportWidth
        offset = x - supportX; excludedGroup = nil
        restingOnPile = other.support == nil; disturbedByWindow = false; fallTime = 0
    }
    public mutating func step(dt: Double, surfaces: [AshSurface], floor: Double) {
        guard dt > 0 else { return }
        emberRemaining = max(0, emberRemaining - dt)
        if restingOnPile && support == nil { return }
        if let support {
            if let edge = surfaces.first(where: { $0.id == support }),
               abs(edge.x - supportX) < 0.75, abs(edge.y - supportY) < 0.75,
               abs(edge.width - supportWidth) < 0.75, offset >= 0, offset <= edge.width {
                return
            }
            let edge = surfaces.first(where: { $0.id == support })
            let dx = (edge?.x ?? supportX) - supportX
            let dy = (edge?.y ?? supportY) - supportY
            excludedGroup = supportGroup ?? support; self.support = nil; restingOnPile = false
            // Each flake separates immediately, while the window transfers only
            // a modest impulse instead of throwing the entire pile sideways.
            let jitter = (Double(shapeSeed % 101) / 100 - 0.5) * 48
            let windowImpulse = max(-16, min(16, dx * 0.4))
            vx = windowImpulse + jitter
            vy = max(-30, min(35, dy * 1.2))
            bounces = 0; disturbedByWindow = true; fallTime = 0
            spin = (shapeSeed % 2 == 0 ? 1 : -1) * (1.0 + min(abs(dx), 40) / 30)
        }
        let oldY = y
        if disturbedByWindow {
            fallTime += dt
            let lightness = min(1.5, max(0.55, 3.5 / size))
            let flutter = sin(fallTime * (3.2 + Double(shapeSeed % 5) * 0.3) + Double(shapeSeed % 13)) * 7 * lightness
            vx += flutter * dt; vx *= exp(-0.7 * dt)
            vy = max(vy - 500 * dt, -370 - size * 15)
        } else {
            vy -= 550 * dt; vx *= exp(-0.7 * dt)
        }
        x += vx * dt; y += vy * dt; rotation += spin * dt; spin *= exp(-0.45 * dt)
        let hits = surfaces.filter { $0.groupID != excludedGroup && x >= $0.x && x <= $0.x + $0.width && oldY - size/2 >= $0.y && y - size/2 <= $0.y }
        if let edge = hits.max(by: { $0.y < $1.y }) {
            y = edge.y + size/2
            if bounces == 0 && vy < -55 {
                vy = -vy * 0.12; vx *= 0.55; bounces += 1
            } else {
                support = edge.id; supportGroup = edge.groupID; offset = x - edge.x; supportX = edge.x; supportY = edge.y; supportWidth = edge.width
                excludedGroup = nil; vx = 0; vy = 0; spin = 0; disturbedByWindow = false
            }
        } else if y - size/2 <= floor {
            y = floor + size/2
            if bounces == 0 && vy < -55 { vy = -vy * 0.12; vx *= 0.55; bounces += 1 }
            else { vx = 0; vy = 0; spin = 0; excludedGroup = nil; disturbedByWindow = false }
        }
    }
}

/// Finds swept contacts against settled flakes using local spatial buckets.
public enum AshPileSolver {
    private struct Cell: Hashable { let x: Int; let y: Int }
    private static let cellSize = 12.0
    private static func cell(x: Double, y: Double) -> Cell { Cell(x: Int(floor(x / cellSize)), y: Int(floor(y / cellSize))) }
    public static func resolve(_ particles: inout [AshParticle], oldBottoms: [Double], settled: [Bool]) {
        guard particles.count == oldBottoms.count, particles.count == settled.count else { return }
        var buckets: [Cell: [Int]] = [:]
        // Seed only previously stationary flakes. Flakes that land this frame
        // are added as they are resolved, so a simultaneous drop forms a pile.
        for i in particles.indices where settled[i] {
            let bottom = particles[i].y - particles[i].size / 2
            if abs(bottom - oldBottoms[i]) <= 0.001 {
                buckets[cell(x: particles[i].x, y: particles[i].y), default: []].append(i)
            }
        }
        for i in particles.indices {
            let p = particles[i]
            let bottom = p.y - p.size / 2
            let moved = abs(bottom - oldBottoms[i]) > 0.001
            guard moved else { continue }
            if bottom < oldBottoms[i] || settled[i] {
                let key = cell(x: p.x, y: p.y)
                var contact: Int?; var highest = -Double.infinity
                let upperCell = max(key.y + 1, Int(floor(oldBottoms[i] / cellSize)) + 1)
                for dx in -2...2 { for cellY in (key.y - 1)...upperCell {
                    for j in buckets[Cell(x: key.x + dx, y: cellY)] ?? [] {
                        let base = particles[j]
                        let top = base.y + base.size * 0.34
                        let swept = oldBottoms[i] >= top && bottom <= top
                        // Resolve only shallow penetration. Deep overlaps must not
                        // teleport flakes upward and suddenly reveal hidden layers.
                        let overlap = p.pileSpread > 0 && settled[i] && bottom <= top &&
                            p.support == base.support && top <= oldBottoms[i] + p.size * 0.5 &&
                            oldBottoms[i] >= top - (base.size + p.size)
                        let collisionWidth = (base.size * max(1, base.visualWidthScale) + p.size * max(1, p.visualWidthScale)) * 0.36
                        if abs(base.x - p.x) < collisionWidth && (swept || overlap) && top > highest {
                            highest = top; contact = j
                        }
                    }
                } }
                if let contact { particles[i].rest(on: particles[contact]) }
            }
            if settled[i] || particles[i].restingOnPile || particles[i].support != nil {
                buckets[cell(x: particles[i].x, y: particles[i].y), default: []].append(i)
            }
        }
    }
}

/// Approximate Dock footprint when the window server does not expose its bounds.
public enum DockFootprint {
    public static func horizontal(screenX: Double, screenWidth: Double, tileSize: Double, itemCount: Int, pinning: String) -> (x: Double, width: Double)? {
        guard screenWidth > 0, tileSize >= 16, tileSize <= 128, itemCount > 0 else { return nil }
        let width = min(screenWidth, Double(itemCount) * tileSize + 30)
        let x: Double
        switch pinning {
        case "start": x = screenX
        case "end": x = screenX + screenWidth - width
        default: x = screenX + (screenWidth - width) / 2
        }
        return (x, width)
    }
}

/// A double tap must follow a completed tap, never a drag or an inhale.
public struct TapSequence {
    private var lastTap: Double?
    public init() {}
    public mutating func begin(clickCount: Int, time: Double, interval: Double) -> Bool {
        guard clickCount >= 2, let lastTap, time >= lastTap, time - lastTap <= interval else { return false }
        self.lastTap = nil
        return true
    }
    public mutating func completedTap(time: Double) { lastTap = time }
    public mutating func reset() { lastTap = nil }
}
