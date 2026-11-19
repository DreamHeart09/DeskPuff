import AppKit
import DeskPuffCore

/// A fully interactive 2D lighter. Its flame is animated locally; the app
/// decides when that flame physically contacts the cigarette tip.
final class LighterView: NSView {
    // Keep the burner centered while giving the enlarged flame room to rotate.
    static let canvasSize = NSSize(width: 1600, height: 1600)
    static let canvasPadding: CGFloat = 665

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setBoundsOrigin(NSPoint(x: -Self.canvasPadding, y: -Self.canvasPadding))
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    var style: LighterStyle = .default { didSet { needsDisplay = true } }
    var rotationAngle = 0.0 { didSet { needsDisplay = true } }
    private(set) var isIgnited = false {
        didSet {
            if isIgnited {
                carriedFuelRuntimeMultiplier = max(1, UserDefaults.standard.object(forKey: "inventoryToolLighterRuntimeMultiplierV1") as? Double ?? 1)
            }
            startAnimation()
            needsDisplay = true
        }
    }
    var onMove: ((NSPoint, NSPoint) -> NSPoint)?
    var onMoveFinished: (() -> Void)?
    var onRotationChanged: ((Double) -> Void)?
    var onIgnitionChanged: ((Bool) -> Void)?
    var onStoreInInventory: (() -> Void)?
    var onInventoryStateChanged: (() -> Void)?
    var flameObstructionScreenSegment: (NSPoint, NSPoint)?
    var flameObstructionScreenSegments: [(NSPoint, NSPoint)] = []

    private enum Gesture { case move, rotate, adjust }
    private var gesture: Gesture?
    private var downScreen = NSPoint.zero
    private var downOrigin = NSPoint.zero
    private var rotationPivot = NSPoint.zero
    private var initialPointerAngle = 0.0
    private var initialRotation = 0.0
    private var animationTimer: Timer?
    private var debugIgnitionTimer: Timer?
    private var pressIgnitionTimer: Timer?
    private var pressStartedAt = NSPoint.zero
    private var ignitionStartedByPress = false
    private var dynamics = FlameDynamics()
    private lazy var photoFlame = PhotoFlame()
    var gentleFlame: Bool = UserDefaults.standard.object(forKey: "gentleLighterFlameV1") as? Bool ?? true {
        didSet { UserDefaults.standard.set(gentleFlame, forKey: "gentleLighterFlameV1"); needsDisplay = true }
    }
    var optimizedFlame = UserDefaults.standard.object(forKey: "optimizedLighterFlameV1") as? Bool ?? true {
        didSet { UserDefaults.standard.set(optimizedFlame, forKey: "optimizedLighterFlameV1"); needsDisplay = true }
    }
    private var lastTick: CFTimeInterval = 0
    private var previousMouse: NSPoint?
    private var previousNozzle: NSPoint?
    private var previousCursorVelocity = CGPoint.zero
    private var previousLighterVelocity = CGPoint.zero
    private var fuelStoreInterval = 0.0
    private var carriedFuelRuntimeMultiplier: Double = {
        max(1, UserDefaults.standard.object(forKey: "inventoryToolLighterRuntimeMultiplierV1") as? Double ?? 1)
    }()
    private var fuelSurfaceAngle = 0.0
    private var fuelSurfaceVelocity = 0.0
    private var fuelLevel: CGFloat = {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "lighterFuelLevelV1") != nil else { return 0.9 }
        return CGFloat(min(1, max(0, defaults.double(forKey: "lighterFuelLevelV1"))))
    }()
    private var flameLevel: CGFloat = {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "lighterFlameLevelV1") != nil else { return 0.6 }
        return CGFloat(min(1, max(0, defaults.double(forKey: "lighterFlameLevelV1"))))
    }()
    private struct InventoryState: Codable { var fuel: Double; var flame: Double; var rotation: Double? }
    var inventoryState: Data? { try? JSONEncoder().encode(InventoryState(fuel: Double(fuelLevel), flame: Double(flameLevel), rotation: rotationAngle)) }
    func restoreInventoryState(_ data: Data?) {
        guard let data, let state = try? JSONDecoder().decode(InventoryState.self, from: data) else { return }
        fuelLevel = CGFloat(min(1, max(0, state.fuel)))
        flameLevel = CGFloat(min(1, max(0, state.flame)))
        if let rotation = state.rotation { rotationAngle = rotation }
        UserDefaults.standard.set(Double(fuelLevel), forKey: "lighterFuelLevelV1")
        UserDefaults.standard.set(Double(flameLevel), forKey: "lighterFlameLevelV1")
        needsDisplay = true
    }
    func resetInventoryState() {
        isIgnited = false; fuelLevel = 0.9; flameLevel = 0.6; rotationAngle = 0
        UserDefaults.standard.set(Double(fuelLevel), forKey: "lighterFuelLevelV1")
        UserDefaults.standard.set(Double(flameLevel), forKey: "lighterFlameLevelV1")
        needsDisplay = true
    }
    var isInteracting: Bool { gesture != nil }

    private var flameNozzleAnchor: NSPoint {
        style.artworkFrame == nil ? NSPoint(x: 116, y: 197) : NSPoint(x: 84, y: 228)
    }

    override var isFlipped: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isIgnited { startAnimation() }
    }
    private func startAnimation() {
        animationTimer?.invalidate(); animationTimer = nil
        let fuelIsMoving = abs(fuelSurfaceAngle) > 0.002 || abs(fuelSurfaceVelocity) > 0.008
        guard window != nil, isIgnited || gesture != nil || fuelIsMoving else {
            previousMouse = nil; previousNozzle = nil; return
        }
        lastTick = CACurrentMediaTime()
        previousMouse = NSEvent.mouseLocation
        previousNozzle = screenPoint(local: flameNozzleAnchor)
        previousCursorVelocity = .zero
        previousLighterVelocity = .zero
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.advanceFlame()
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func screenPoint(local point: NSPoint) -> NSPoint? {
        guard let window else { return nil }
        let x = point.x + 25 - bounds.midX, y = point.y + 10 - bounds.midY
        let c = cos(rotationAngle), s = sin(rotationAngle)
        let transformed = NSPoint(x: bounds.midX + x * c - y * s, y: bounds.midY + x * s + y * c)
        return window.convertPoint(toScreen: convert(transformed, to: nil))
    }

    private func advanceFlame() {
        guard let nozzle = screenPoint(local: flameNozzleAnchor) else { return }
        let now = CACurrentMediaTime()
        let dt = min(0.05, max(1.0 / 240, now - lastTick)); lastTick = now
        let mouse = NSEvent.mouseLocation
        let oldMouse = previousMouse ?? mouse
        let oldNozzle = previousNozzle ?? nozzle
        let source = MotionSample(dx: nozzle.x - oldNozzle.x, dy: nozzle.y - oldNozzle.y, dt: dt, maximumSpeed: 900)
        let cursor = MotionSample(dx: mouse.x - oldMouse.x, dy: mouse.y - oldMouse.y, dt: dt, maximumSpeed: 1800)
        previousMouse = mouse; previousNozzle = nozzle
        let cursorAcceleration = CGPoint(x: (cursor.velocityX - previousCursorVelocity.x) / dt,
                                         y: (cursor.velocityY - previousCursorVelocity.y) / dt)
        let lighterAcceleration = CGPoint(x: (source.velocityX - previousLighterVelocity.x) / dt,
                                          y: (source.velocityY - previousLighterVelocity.y) / dt)
        previousCursorVelocity = CGPoint(x: cursor.velocityX, y: cursor.velocityY)
        previousLighterVelocity = CGPoint(x: source.velocityX, y: source.velocityY)
        // Treat the flame as a narrow vertical air column, not a single point;
        // this makes a mouse sweep across any visible part register as a gust.
        var distance = CGFloat.greatestFiniteMagnitude
        var previousPoint = nozzle
        for sample in 1...20 {
            let fraction = Double(sample) / 20
            let offset = FlameField.plumePoint(fraction: fraction, height: Double(flameHeight),
                                               nozzleAngle: rotationAngle, bend: dynamics.bend)
            let nextPoint = NSPoint(x: nozzle.x + offset.x, y: nozzle.y + offset.y)
            distance = min(distance, FlameDynamics.distanceBetweenSegments(oldMouse, mouse, previousPoint, nextPoint))
            previousPoint = nextPoint
        }
        let proximity = max(0, 1 - distance / 128)
        let cursorSpeed = hypot(cursor.velocityX, cursor.velocityY)
        let pressure = proximity * proximity * min(1, cursorSpeed / 620)
        let avoidance = nozzle.x >= mouse.x ? 1.0 : -1.0
        // Moving the lighter creates relative airflow. Cursor wind is a separate
        // local disturbance and is suppressed while gripping the lighter.
        let mouseWeight = gesture == nil ? proximity * proximity : 0
        let worldX = -source.velocityX + cursor.velocityX * mouseWeight
        let worldY = -source.velocityY + cursor.velocityY * mouseWeight
        let worldAccelerationX = -lighterAcceleration.x + cursorAcceleration.x * mouseWeight
        let worldAccelerationY = -lighterAcceleration.y + cursorAcceleration.y * mouseWeight
        let c = cos(rotationAngle), s = sin(rotationAngle)
        let localFuelAcceleration = CGPoint(x: lighterAcceleration.x * c + lighterAcceleration.y * s,
                                            y: -lighterAcceleration.x * s + lighterAcceleration.y * c)
        advanceFuelSurface(dt: dt, acceleration: localFuelAcceleration)
        if isIgnited {
            let level = Double(flameLevel)
            let burnMinutes = level <= 0.5 ? 5 - level * 4 : 3 - (level - 0.5) * 4
            fuelLevel = max(0, fuelLevel - CGFloat(dt * 0.9 / (burnMinutes * 60 * carriedFuelRuntimeMultiplier)))
            fuelStoreInterval += dt
            if fuelStoreInterval >= 0.5 {
                carriedFuelRuntimeMultiplier = max(1, UserDefaults.standard.object(forKey: "inventoryToolLighterRuntimeMultiplierV1") as? Double ?? 1)
                saveFuelLevel(); fuelStoreInterval = 0
            }
            if fuelLevel <= 0 {
                fuelLevel = 0
                saveFuelLevel()
                isIgnited = false
                onIgnitionChanged?(false)
            }
        }
        if isIgnited {
            dynamics.advance(dt: dt, air: CGPoint(x: worldX, y: worldY),
                             acceleration: CGPoint(x: worldAccelerationX, y: worldAccelerationY),
                             mouseAvoidance: gesture == nil ? avoidance : 0,
                             mousePressure: gesture == nil ? pressure : 0,
                             level: Double(flameLevel))
        }
        needsDisplay = true
        if !isIgnited, gesture == nil, abs(fuelSurfaceAngle) < 0.002, abs(fuelSurfaceVelocity) < 0.008 {
            animationTimer?.invalidate(); animationTimer = nil
            previousMouse = nil; previousNozzle = nil
        }
    }

    private func advanceFuelSurface(dt: Double, acceleration: CGPoint) {
        let gravity = 5_000.0
        let accelerationX = acceleration.x.isFinite ? Double(acceleration.x) : 0
        let accelerationY = acceleration.y.isFinite ? Double(acceleration.y) : 0
        let target = min(0.46, max(-0.46, atan2(-accelerationX, gravity + accelerationY)))
        let frequency = 4.4, damping = 0.52
        fuelSurfaceVelocity += ((target - fuelSurfaceAngle) * frequency * frequency
                                - 2 * damping * frequency * fuelSurfaceVelocity) * dt
        fuelSurfaceAngle = min(0.48, max(-0.48, fuelSurfaceAngle + fuelSurfaceVelocity * dt))
    }

    private func saveFuelLevel() {
        UserDefaults.standard.set(Double(fuelLevel), forKey: "lighterFuelLevelV1")
        onInventoryStateChanged?()
    }

    func resetFuelForTesting() {
        isIgnited = false
        fuelLevel = 0.9
        fuelSurfaceAngle = 0; fuelSurfaceVelocity = 0
        saveFuelLevel()
        onIgnitionChanged?(false)
        needsDisplay = true
    }

    var fuelFraction: Double { Double(fuelLevel) }

    private var flameHeight: CGFloat {
        let flow = CGFloat(dynamics.verticalFlow)
        let mouseCompression = 1 - CGFloat(dynamics.mousePressure) * 0.32
        let previousMaximum = CGFloat(FlameField.height(level: 1)) * 1.6
        let minimum = previousMaximum * 0.21
        let medium = previousMaximum * 0.5
        let maximum = previousMaximum * 3
        let baseHeight = flameLevel <= 0.5
            ? minimum + (medium - minimum) * flameLevel / 0.5
            : medium + (maximum - medium) * (flameLevel - 0.5) / 0.5
        return baseHeight * mouseCompression
            * (1 + max(-0.18, min(0.12, flow * 0.12)))
    }

    private var flameWidth: CGFloat {
        let mediumHeight = CGFloat(FlameField.height(level: 1)) * 1.6 * 0.5
        let mediumWidth = mediumHeight * 120 / 276 * 2
        if flameLevel <= 0.5 {
            let progress = flameLevel / 0.5
            return mediumWidth * (0.95 + progress * 0.05)
        }
        let progress = (flameLevel - 0.5) / 0.5
        return mediumWidth * (1 + progress * 0.08)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: rotationAngle)
        context.translateBy(x: -bounds.midX, y: -bounds.midY)
        context.translateBy(x: 25, y: 10)
        drawBody()
        if isIgnited {
            // The nozzle remains fixed to the lighter, while the flame rises
            // against screen gravity instead of rotating rigidly with the body.
            context.saveGState()
            let nozzle = flameNozzleAnchor
            context.translateBy(x: nozzle.x, y: nozzle.y)
            context.rotate(by: -rotationAngle)
            context.translateBy(x: -nozzle.x, y: -nozzle.y)
            drawFlame(in: context)
            context.restoreGState()
        }
        context.restoreGState()
    }

    private func drawBody() {
        if let artwork = style.artwork {
            // The photo is an empty transparent shell. Keep the original
            // physical tank rendering behind it so fuel remains animated.
            drawTransparentShell(photoFit: style.artworkFrame != nil, internalOnly: style.artworkFrame != nil)
            let target = style.artworkFrame ?? NSRect(x: 22, y: 13, width: 176, height: 222)
            let source = style.artworkSourceRect.map { normalized in
                NSRect(x: normalized.minX * artwork.size.width,
                       y: normalized.minY * artwork.size.height,
                       width: normalized.width * artwork.size.width,
                       height: normalized.height * artwork.size.height)
            } ?? .zero
            NSGraphicsContext.current?.cgContext.interpolationQuality = .high
            artwork.draw(in: target, from: source, operation: .sourceOver, fraction: 1)
            if style.artworkFrame == nil { drawFlameAdjuster() }
            else { drawPhotoFlameSlider() }
            return
        }
        drawTransparentShell()
        drawStampedIgnitionHead()
        drawFlameAdjuster()
    }

    private var shellPath: NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 68, y: 43))
        path.curve(to: NSPoint(x: 78, y: 33), controlPoint1: NSPoint(x: 68, y: 36), controlPoint2: NSPoint(x: 72, y: 33))
        path.line(to: NSPoint(x: 142, y: 33))
        path.curve(to: NSPoint(x: 153, y: 44), controlPoint1: NSPoint(x: 150, y: 33), controlPoint2: NSPoint(x: 153, y: 37))
        path.line(to: NSPoint(x: 153, y: 166))
        path.curve(to: NSPoint(x: 143, y: 177), controlPoint1: NSPoint(x: 153, y: 173), controlPoint2: NSPoint(x: 149, y: 177))
        path.line(to: NSPoint(x: 78, y: 177))
        path.curve(to: NSPoint(x: 68, y: 166), controlPoint1: NSPoint(x: 72, y: 177), controlPoint2: NSPoint(x: 68, y: 173))
        path.close()
        return path
    }

    private func drawTransparentShell(photoFit: Bool = false, internalOnly: Bool = false) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: 110, y: 164)
        context.scaleBy(x: photoFit ? 0.69 : 0.76, y: 1.16)
        context.translateBy(x: -110, y: -164)
        if photoFit { context.translateBy(x: -7.5, y: 0) }

        let shell = shellPath
        let reservoir = NSBezierPath(roundedRect: NSRect(x: 72, y: 37, width: 77, height: 132), xRadius: 6, yRadius: 6)
        let bodyColors = style.body
        let resin = bodyColors.first ?? NSColor(calibratedRed: 0.67, green: 0.045, blue: 0.055, alpha: 1)
        let shade = bodyColors.dropFirst().first ?? resin.blended(withFraction: 0.72, of: .black) ?? resin
        let glow = bodyColors.dropFirst(2).first ?? resin.blended(withFraction: 0.30, of: .white) ?? resin

        let isAmberResin = style.id == "silver-flint"
        if !internalOnly {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowOffset = NSSize(width: 1.2, height: -2); shadow.shadowBlurRadius = 5
            shadow.set(); NSColor.black.withAlphaComponent(0.32).setFill(); shell.fill()
            NSGraphicsContext.restoreGraphicsState()

            let glassShadow = isAmberResin
                ? NSColor(calibratedRed: 0.38, green: 0.11, blue: 0.015, alpha: 0.18)
                : shade.withAlphaComponent(0.35)
            let glassHighlight = isAmberResin
                ? NSColor(calibratedRed: 1, green: 0.87, blue: 0.62, alpha: 0.30)
                : glow.withAlphaComponent(0.34)
            NSGradient(colors: [glassShadow, glassHighlight, glassShadow.withAlphaComponent(0.72)])?.draw(in: reservoir, angle: 0)
        }
        NSGraphicsContext.saveGraphicsState()
        reservoir.addClip()
        let tank = [CGPoint(x: 74, y: 38), CGPoint(x: 147, y: 38), CGPoint(x: 147, y: 163), CGPoint(x: 74, y: 163)]
        let surfaceAngle = -rotationAngle + fuelSurfaceAngle
        let upX = -sin(surfaceAngle), upY = cos(surfaceAngle)
        func projection(_ point: CGPoint) -> Double { point.x * upX + point.y * upY }
        func clippedTank(_ threshold: Double) -> [CGPoint] {
            var output: [CGPoint] = []
            for index in tank.indices {
                let start = tank[index], end = tank[(index + 1) % tank.count]
                let startDistance = projection(start) - threshold, endDistance = projection(end) - threshold
                let startInside = startDistance <= 0, endInside = endDistance <= 0
                if startInside != endInside {
                    let fraction = startDistance / (startDistance - endDistance)
                    output.append(CGPoint(x: start.x + (end.x - start.x) * fraction,
                                          y: start.y + (end.y - start.y) * fraction))
                }
                if endInside { output.append(end) }
            }
            return output
        }
        func polygonArea(_ points: [CGPoint]) -> Double {
            guard points.count > 2 else { return 0 }
            return abs(points.indices.reduce(0.0) { sum, index in
                let a = points[index], b = points[(index + 1) % points.count]
                return sum + a.x * b.y - b.x * a.y
            }) * 0.5
        }
        let projections = tank.map(projection)
        var low = projections.min() ?? 0, high = projections.max() ?? 0
        let tankArea = polygonArea(tank)
        for _ in 0..<20 {
            let middle = (low + high) * 0.5
            if polygonArea(clippedTank(middle)) / tankArea < Double(fuelLevel) { low = middle }
            else { high = middle }
        }
        let threshold = (low + high) * 0.5
        let liquidVertices = clippedTank(threshold)
        if liquidVertices.count > 2 {
            let fuel = NSBezierPath(); fuel.move(to: liquidVertices[0])
            for vertex in liquidVertices.dropFirst() { fuel.line(to: vertex) }
            fuel.close()
            NSGradient(colors: [shade.withAlphaComponent(0.48), resin.withAlphaComponent(0.46), glow.withAlphaComponent(0.34)])?.draw(in: fuel, angle: 0)
            var surfacePoints: [CGPoint] = []
            for index in tank.indices {
                let start = tank[index], end = tank[(index + 1) % tank.count]
                let startDistance = projection(start) - threshold, endDistance = projection(end) - threshold
                if startDistance * endDistance < 0 {
                    let fraction = startDistance / (startDistance - endDistance)
                    surfacePoints.append(CGPoint(x: start.x + (end.x - start.x) * fraction,
                                                 y: start.y + (end.y - start.y) * fraction))
                }
            }
            if surfacePoints.count >= 2 {
                let fluidLine = NSBezierPath(); fluidLine.move(to: surfacePoints[0]); fluidLine.line(to: surfacePoints[1])
                NSColor(calibratedRed: 1, green: 0.48, blue: 0.37, alpha: 0.48).setStroke()
                fluidLine.lineWidth = 1.05; fluidLine.stroke()
                let meniscus = NSBezierPath()
                meniscus.move(to: NSPoint(x: surfacePoints[0].x + upX * 0.8, y: surfacePoints[0].y + upY * 0.8))
                meniscus.line(to: NSPoint(x: surfacePoints[1].x + upX * 0.8, y: surfacePoints[1].y + upY * 0.8))
                NSColor.white.withAlphaComponent(0.24).setStroke(); meniscus.lineWidth = 0.45; meniscus.stroke()
            }
        }

        let feedTube = NSBezierPath()
        feedTube.move(to: NSPoint(x: 117, y: 46)); feedTube.curve(to: NSPoint(x: 116, y: 159), controlPoint1: NSPoint(x: 115, y: 82), controlPoint2: NSPoint(x: 118, y: 127))
        NSColor(calibratedRed: 0.48, green: 0.20, blue: 0.035, alpha: 0.42).setStroke(); feedTube.lineWidth = 2.2; feedTube.stroke()
        let tubeHighlight = NSBezierPath(); tubeHighlight.move(to: NSPoint(x: 116.3, y: 48)); tubeHighlight.line(to: NSPoint(x: 115.7, y: 151))
        NSColor.white.withAlphaComponent(0.28).setStroke(); tubeHighlight.lineWidth = 0.55; tubeHighlight.stroke()
        let valve = NSBezierPath(roundedRect: NSRect(x: 111.5, y: 154, width: 9, height: 10), xRadius: 2, yRadius: 2)
        NSGradient(colors: [glow.withAlphaComponent(0.55), resin.withAlphaComponent(0.55), shade.withAlphaComponent(0.62)])?.draw(in: valve, angle: 0)
        NSGraphicsContext.restoreGraphicsState()

        if !internalOnly {
            if isAmberResin {
                NSGradient(colors: [NSColor(calibratedRed: 1, green: 0.79, blue: 0.42, alpha: 0.26),
                                    NSColor(calibratedRed: 0.97, green: 0.47, blue: 0.055, alpha: 0.18),
                                    NSColor(calibratedRed: 0.48, green: 0.15, blue: 0.012, alpha: 0.30)])?.draw(in: shell, angle: 0)
            } else {
                NSGradient(colors: [glow.withAlphaComponent(0.28), resin.withAlphaComponent(0.20), shade.withAlphaComponent(0.31)])?.draw(in: shell, angle: 0)
            }
            shell.lineWidth = 0.85
            (isAmberResin ? NSColor(calibratedRed: 1, green: 0.82, blue: 0.48, alpha: 0.70)
                          : NSColor(calibratedRed: 1, green: 0.54, blue: 0.49, alpha: 0.55)).setStroke(); shell.stroke()

            let sideShade = NSBezierPath(roundedRect: NSRect(x: 69, y: 44, width: 4, height: 116), xRadius: 2, yRadius: 2)
            (isAmberResin ? NSColor(calibratedRed: 0.34, green: 0.085, blue: 0.008, alpha: 0.22)
                          : shade.withAlphaComponent(0.38)).setFill(); sideShade.fill()
            let edgeGlint = NSBezierPath(); edgeGlint.move(to: NSPoint(x: 76, y: 53)); edgeGlint.line(to: NSPoint(x: 76, y: 154))
            NSColor(calibratedRed: 1, green: 0.91, blue: 0.70, alpha: isAmberResin ? 0.42 : 0.28).setStroke(); edgeGlint.lineWidth = 1.15; edgeGlint.stroke()
            let oppositeRefraction = NSBezierPath()
            oppositeRefraction.move(to: NSPoint(x: 144, y: 52)); oppositeRefraction.curve(to: NSPoint(x: 143, y: 154), controlPoint1: NSPoint(x: 147, y: 86), controlPoint2: NSPoint(x: 141, y: 125))
            NSColor(calibratedRed: 0.30, green: 0.085, blue: 0.008, alpha: isAmberResin ? 0.24 : 0.18).setStroke()
            oppositeRefraction.lineWidth = 2.1; oppositeRefraction.stroke()
            let moldedRib = NSBezierPath()
            moldedRib.move(to: NSPoint(x: 82, y: 49)); moldedRib.curve(to: NSPoint(x: 82, y: 158), controlPoint1: NSPoint(x: 80, y: 88), controlPoint2: NSPoint(x: 84, y: 126))
            NSColor.white.withAlphaComponent(isAmberResin ? 0.19 : 0.13).setStroke(); moldedRib.lineWidth = 0.65; moldedRib.stroke()
            let moldedSeam = NSBezierPath(); moldedSeam.move(to: NSPoint(x: 71, y: 44)); moldedSeam.curve(to: NSPoint(x: 150, y: 44), controlPoint1: NSPoint(x: 94, y: 42), controlPoint2: NSPoint(x: 127, y: 46))
            (isAmberResin ? NSColor(calibratedRed: 1, green: 0.78, blue: 0.37, alpha: 0.46)
                          : shade.withAlphaComponent(0.42)).setStroke(); moldedSeam.lineWidth = 0.8; moldedSeam.stroke()
            let baseFoot = NSBezierPath(); baseFoot.move(to: NSPoint(x: 77, y: 36.5)); baseFoot.curve(to: NSPoint(x: 143, y: 36.5), controlPoint1: NSPoint(x: 95, y: 35), controlPoint2: NSPoint(x: 125, y: 35))
            glow.withAlphaComponent(0.42).setStroke(); baseFoot.lineWidth = 1.1; baseFoot.stroke()
        }
        context.restoreGState()
    }

    private func drawStampedIgnitionHead() {
        let metal = style.metal
        let brightMetal = metal.first ?? NSColor(calibratedWhite: 0.82, alpha: 1)
        let darkMetal = metal.dropFirst().first ?? NSColor(calibratedWhite: 0.27, alpha: 1)
        let collar = NSBezierPath(roundedRect: NSRect(x: 68, y: 158, width: 83, height: 17), xRadius: 4.5, yRadius: 4.5)
        NSGradient(colors: [NSColor(calibratedWhite: 0.055, alpha: 1), NSColor(calibratedWhite: 0.16, alpha: 1), NSColor(calibratedWhite: 0.035, alpha: 1)])?.draw(in: collar, angle: 90)
        NSColor.black.withAlphaComponent(0.68).setStroke(); collar.lineWidth = 0.75; collar.stroke()
        let collarGlint = NSBezierPath(); collarGlint.move(to: NSPoint(x: 74, y: 171.5)); collarGlint.curve(to: NSPoint(x: 145, y: 171.5), controlPoint1: NSPoint(x: 95, y: 173), controlPoint2: NSPoint(x: 125, y: 170.5))
        NSColor.white.withAlphaComponent(0.16).setStroke(); collarGlint.lineWidth = 0.55; collarGlint.stroke()
        let hood = NSBezierPath()
        hood.move(to: NSPoint(x: 101, y: 169)); hood.line(to: NSPoint(x: 151, y: 169))
        hood.line(to: NSPoint(x: 151, y: 184)); hood.curve(to: NSPoint(x: 141, y: 199), controlPoint1: NSPoint(x: 150, y: 193), controlPoint2: NSPoint(x: 147, y: 198))
        hood.line(to: NSPoint(x: 109, y: 199)); hood.curve(to: NSPoint(x: 101, y: 190), controlPoint1: NSPoint(x: 103, y: 197), controlPoint2: NSPoint(x: 101, y: 194))
        hood.close()
        NSGradient(colors: [darkMetal, brightMetal, darkMetal.blended(withFraction: 0.25, of: .white) ?? darkMetal])?.draw(in: hood, angle: 0)
        NSColor.black.withAlphaComponent(0.48).setStroke(); hood.lineWidth = 0.75; hood.stroke()

        let foldedRim = NSBezierPath()
        foldedRim.move(to: NSPoint(x: 103, y: 170)); foldedRim.curve(to: NSPoint(x: 149, y: 170), controlPoint1: NSPoint(x: 118, y: 168.5), controlPoint2: NSPoint(x: 137, y: 169))
        brightMetal.withAlphaComponent(0.92).setStroke(); foldedRim.lineWidth = 1.4; foldedRim.stroke()
        let hoodFace = NSBezierPath()
        hoodFace.move(to: NSPoint(x: 105, y: 172)); hoodFace.curve(to: NSPoint(x: 145, y: 180), controlPoint1: NSPoint(x: 135, y: 170), controlPoint2: NSPoint(x: 148, y: 174))
        hoodFace.line(to: NSPoint(x: 139, y: 193)); hoodFace.line(to: NSPoint(x: 110, y: 193)); hoodFace.close()
        NSGradient(colors: [darkMetal.withAlphaComponent(0.54), brightMetal.withAlphaComponent(0.38), darkMetal.withAlphaComponent(0.76)])?.draw(in: hoodFace, angle: 0)
        let brush = NSBezierPath(); brush.move(to: NSPoint(x: 109, y: 173)); brush.line(to: NSPoint(x: 132, y: 173))
        NSColor.white.withAlphaComponent(0.46).setStroke(); brush.lineWidth = 0.55; brush.stroke()

        let vents: [(CGFloat, CGFloat)] = [(140, 178), (145, 176), (148, 174.5)]
        for (x, y) in vents {
            let vent = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 1.2, height: 6.0), xRadius: 0.6, yRadius: 0.6)
            darkMetal.withAlphaComponent(0.92).setFill(); vent.fill()
            let ventGlint = NSBezierPath(); ventGlint.move(to: NSPoint(x: x + 0.3, y: y + 1)); ventGlint.line(to: NSPoint(x: x + 0.3, y: y + 5))
            brightMetal.withAlphaComponent(0.58).setStroke(); ventGlint.lineWidth = 0.35; ventGlint.stroke()
        }

        drawFlintWheel(brightMetal: brightMetal, darkMetal: darkMetal)

        let lever = NSBezierPath()
        lever.move(to: NSPoint(x: 96, y: 171)); lever.curve(to: NSPoint(x: 108, y: 174), controlPoint1: NSPoint(x: 101, y: 169), controlPoint2: NSPoint(x: 106, y: 170))
        lever.line(to: NSPoint(x: 112, y: 188)); lever.line(to: NSPoint(x: 106, y: 191)); lever.line(to: NSPoint(x: 100, y: 181)); lever.close()
        NSGradient(colors: [NSColor(calibratedWhite: 0.13, alpha: 1), NSColor(calibratedWhite: 0.035, alpha: 1)])?.draw(in: lever, angle: 90)
        NSColor.black.withAlphaComponent(0.75).setStroke(); lever.lineWidth = 0.55; lever.stroke()

        let nozzleShoulder = NSBezierPath(roundedRect: NSRect(x: 111.5, y: 187.5, width: 9, height: 8.5), xRadius: 2, yRadius: 2)
        NSGradient(colors: [brightMetal, darkMetal, brightMetal.withAlphaComponent(0.92)])?.draw(in: nozzleShoulder, angle: 0)
        let nozzleOpening = NSBezierPath(ovalIn: NSRect(x: 113.5, y: 195, width: 5, height: 2.2))
        NSColor(calibratedWhite: 0.055, alpha: 1).setFill(); nozzleOpening.fill()
        let nozzleLip = NSBezierPath(ovalIn: NSRect(x: 112.5, y: 195.8, width: 7, height: 1.6))
        brightMetal.withAlphaComponent(0.94).setStroke(); nozzleLip.lineWidth = 0.7; nozzleLip.stroke()
    }

    private func drawFlintWheel(brightMetal: NSColor, darkMetal: NSColor) {
        let axle = NSBezierPath(ovalIn: NSRect(x: 72, y: 177, width: 25, height: 17))
        NSGradient(colors: [darkMetal, brightMetal, darkMetal])?.draw(in: axle, angle: 0)
        NSColor.black.withAlphaComponent(0.70).setStroke(); axle.lineWidth = 0.8; axle.stroke()
        let drum = NSBezierPath(roundedRect: NSRect(x: 77, y: 178.5, width: 16.5, height: 15), xRadius: 5, yRadius: 5)
        NSGradient(colors: [NSColor(calibratedWhite: 0.19, alpha: 1), brightMetal, NSColor(calibratedWhite: 0.22, alpha: 1)])?.draw(in: drum, angle: 0)
        for index in 0..<13 {
            let x = 78.5 + CGFloat(index) * 1.12
            let darkGroove = NSBezierPath(); darkGroove.move(to: NSPoint(x: x, y: 180)); darkGroove.line(to: NSPoint(x: x + 0.75, y: 192))
            NSColor.black.withAlphaComponent(0.58).setStroke(); darkGroove.lineWidth = 0.65; darkGroove.stroke()
            let toothHighlight = NSBezierPath(); toothHighlight.move(to: NSPoint(x: x + 0.5, y: 180.5)); toothHighlight.line(to: NSPoint(x: x + 1.1, y: 191))
            brightMetal.withAlphaComponent(0.62).setStroke(); toothHighlight.lineWidth = 0.4; toothHighlight.stroke()
        }
        let cap = NSBezierPath(ovalIn: NSRect(x: 75, y: 182, width: 3, height: 7))
        brightMetal.withAlphaComponent(0.75).setFill(); cap.fill()
    }

    private func drawFlameAdjuster() {
        let metal = style.metal.first ?? NSColor(calibratedWhite: 0.78, alpha: 1)
        let darkMetal = style.metal.dropFirst().first ?? NSColor(calibratedWhite: 0.26, alpha: 1)
        let bezel = NSBezierPath(roundedRect: NSRect(x: 99, y: 157, width: 43, height: 10), xRadius: 3, yRadius: 3)
        NSGradient(colors: [darkMetal, metal, darkMetal])?.draw(in: bezel, angle: 90)
        let track = NSBezierPath(roundedRect: NSRect(x: 103, y: 160.3, width: 35, height: 2.4), xRadius: 1.2, yRadius: 1.2)
        NSColor(calibratedWhite: 0.075, alpha: 0.92).setFill(); track.fill()
        let knobX = 100 + flameLevel * 35
        let knob = NSBezierPath(roundedRect: NSRect(x: knobX, y: 157.6, width: 7, height: 8.5), xRadius: 2, yRadius: 2)
        NSGradient(colors: [NSColor(calibratedWhite: 0.91, alpha: 1), metal, darkMetal])?.draw(in: knob, angle: 0)
        NSColor.black.withAlphaComponent(0.52).setStroke(); knob.lineWidth = 0.55; knob.stroke()
        for offset in [2.0, 3.7, 5.4] {
            let grip = NSBezierPath(); grip.move(to: NSPoint(x: knobX + offset, y: 159)); grip.line(to: NSPoint(x: knobX + offset, y: 164.5))
            NSColor.white.withAlphaComponent(0.46).setStroke(); grip.lineWidth = 0.35; grip.stroke()
        }
    }

    private func drawPhotoFlameSlider() {
        // A compact chrome control sits directly on the lighter's black collar.
        let track = NSBezierPath(roundedRect: NSRect(x: 88.5, y: 185.7, width: 34, height: 4.5), xRadius: 2.2, yRadius: 2.2)
        NSGradient(colors: [NSColor(calibratedWhite: 0.025, alpha: 0.98),
                            NSColor(calibratedWhite: 0.12, alpha: 0.96),
                            NSColor(calibratedWhite: 0.035, alpha: 0.98)])?.draw(in: track, angle: 90)
        NSColor.black.withAlphaComponent(0.88).setStroke(); track.lineWidth = 0.45; track.stroke()
        let rail = NSBezierPath(); rail.move(to: NSPoint(x: 91, y: 187.9)); rail.line(to: NSPoint(x: 120, y: 187.9))
        NSColor(calibratedWhite: 0.40, alpha: 0.58).setStroke(); rail.lineWidth = 0.65; rail.stroke()
        for x in stride(from: CGFloat(92), through: 119, by: 6.75) {
            let mark = NSBezierPath(); mark.move(to: NSPoint(x: x, y: 186.6)); mark.line(to: NSPoint(x: x, y: 189.3))
            NSColor(calibratedWhite: 0.52, alpha: 0.28).setStroke(); mark.lineWidth = 0.35; mark.stroke()
        }
        let knobX = 89 + flameLevel * 27.5
        let knob = NSBezierPath(roundedRect: NSRect(x: knobX, y: 184.1, width: 5.5, height: 8), xRadius: 1.8, yRadius: 1.8)
        NSGradient(colors: [NSColor(calibratedWhite: 0.36, alpha: 1),
                            NSColor(calibratedWhite: 0.12, alpha: 1),
                            NSColor(calibratedWhite: 0.035, alpha: 1)])?.draw(in: knob, angle: 0)
        NSColor(calibratedWhite: 0.50, alpha: 0.62).setStroke(); knob.lineWidth = 0.5; knob.stroke()
        let grip = NSBezierPath()
        grip.move(to: NSPoint(x: knobX + 2.75, y: 185.6)); grip.line(to: NSPoint(x: knobX + 2.75, y: 190.8))
        NSColor(calibratedWhite: 0.56, alpha: 0.5).setStroke(); grip.lineWidth = 0.4; grip.stroke()
    }

    private func drawFlame(in context: CGContext) {
        guard let photoFlame else { return }
        let nozzle = screenPoint(local: flameNozzleAnchor) ?? .zero
        let nozzleOrigin = CGPoint(x: flameNozzleAnchor.x, y: flameNozzleAnchor.y)
        let screenObstacles = flameObstructionScreenSegments + (flameObstructionScreenSegment.map { [$0] } ?? [])
        let obstacles = screenObstacles.map { segment -> (CGPoint, CGPoint) in
            func localDelta(_ screenPoint: NSPoint) -> CGPoint {
                guard let window else { return .zero }
                let viewPoint = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
                let rootViewPoint = convert(window.convertPoint(fromScreen: nozzle), from: nil)
                return CGPoint(x: viewPoint.x - rootViewPoint.x, y: viewPoint.y - rootViewPoint.y)
            }
            return (localDelta(segment.0), localDelta(segment.1))
        }
        context.saveGState()
        context.interpolationQuality = .high
        photoFlame.draw(in: context, height: flameHeight, width: flameWidth, bend: CGFloat(dynamics.bend),
                        time: dynamics.time, nozzleAngle: CGFloat(rotationAngle),
                        nozzleOrigin: nozzleOrigin, gentleMode: gentleFlame,
                        optimized: optimizedFlame, obstructions: obstacles)
        context.restoreGState()
    }

    func visibleBodyBounds() -> NSRect {
        let body = style.artwork == nil
            ? NSRect(x: 67, y: 13, width: 86, height: 188)
            : (style.artworkFrame ?? NSRect(x: 22, y: 13, width: 176, height: 222))
        let c = cos(rotationAngle), s = sin(rotationAngle)
        let corners = [NSPoint(x: body.minX, y: body.minY), NSPoint(x: body.maxX, y: body.minY),
                       NSPoint(x: body.minX, y: body.maxY), NSPoint(x: body.maxX, y: body.maxY)].map { point in
            let x = point.x + 25 - bounds.midX, y = point.y + 10 - bounds.midY
            return NSPoint(x: bounds.midX + x * c - y * s, y: bounds.midY + x * s + y * c)
        }
        let minX = corners.map(\.x).min() ?? 0, maxX = corners.map(\.x).max() ?? 0
        let minY = corners.map(\.y).min() ?? 0, maxY = corners.map(\.y).max() ?? 0
        return NSRect(x: minX - bounds.minX, y: minY - bounds.minY, width: maxX - minX, height: maxY - minY)
    }

    private func localPoint(_ point: NSPoint) -> NSPoint {
        let dx = point.x - bounds.midX, dy = point.y - bounds.midY
        let c = cos(-rotationAngle), s = sin(-rotationAngle)
        return NSPoint(x: bounds.midX + dx * c - dy * s - 25, y: bounds.midY + dx * s + dy * c - 10)
    }
    private func ignitionZone(_ point: NSPoint) -> Bool {
        NSRect(x: 68, y: 166, width: 78, height: 40).contains(point)
    }
    private func rotationZone(_ point: NSPoint) -> Bool {
        let body = style.artwork == nil
            ? NSRect(x: 68, y: 13, width: 85, height: 183)
            : (style.artworkFrame ?? NSRect(x: 22, y: 13, width: 176, height: 222))
        return body.insetBy(dx: -12, dy: -12).contains(point)
            && !body.insetBy(dx: 6, dy: 6).contains(point)
    }
    func containsLighter(_ point: NSPoint) -> Bool {
        let local = localPoint(point)
        let body = style.artwork == nil
            ? NSRect(x: 66, y: 12, width: 88, height: 190)
            : (style.artworkFrame ?? NSRect(x: 22, y: 13, width: 176, height: 222))
        return body.contains(local) || rotationZone(local)
    }
    func landingSurfaces() -> [AshSurface] {
        guard let window, window.isVisible else { return [] }
        let baseID = UInt32(0x50000000) | ((UInt32(truncatingIfNeeded: window.windowNumber) & 0x000fffff) << 8)
        var edges: [(NSPoint, NSPoint)] = style.artworkFrame != nil
            ? [(NSPoint(x: 78, y: 230), NSPoint(x: 113, y: 230)),
               (NSPoint(x: 108, y: 234), NSPoint(x: 121, y: 234))]
            : (style.artwork == nil
                ? [(NSPoint(x: 109, y: 199), NSPoint(x: 141, y: 199)),
                   (NSPoint(x: 77, y: 194), NSPoint(x: 94, y: 194))]
                : [(NSPoint(x: 44, y: 235), NSPoint(x: 177, y: 235))])
        let body = style.artwork == nil
            ? NSRect(x: 67, y: 13, width: 86, height: 188)
            : (style.artworkFrame ?? NSRect(x: 22, y: 13, width: 176, height: 222))
        edges += [
            (NSPoint(x: body.minX, y: body.minY), NSPoint(x: body.maxX, y: body.minY)),
            (NSPoint(x: body.minX, y: body.minY), NSPoint(x: body.minX, y: body.maxY)),
            (NSPoint(x: body.maxX, y: body.minY), NSPoint(x: body.maxX, y: body.maxY))
        ]
        var surfaces: [AshSurface] = []
        for (index, edge) in edges.enumerated() {
            guard let start = screenPoint(local: edge.0), let end = screenPoint(local: edge.1) else { continue }
            surfaces += CigaretteAshSurface.segments(from: start, to: end,
                                                       idBase: baseID &+ UInt32(index * 16), count: 16)
        }
        return surfaces
    }
    func flameContainsScreenPoint(_ point: NSPoint) -> Bool {
        guard isIgnited, let nozzle = screenPoint(local: flameNozzleAnchor) else { return false }
        let height = flameHeight
        if optimizedFlame && !flameSearchBounds(nozzle: nozzle, height: height).contains(point) { return false }
        // Sample the world-space plume, including nozzle momentum and buoyancy.
        for sample in 1...32 {
            let h = Double(sample) / 32
            let offset = FlameField.plumePoint(fraction: h, height: Double(height),
                                               nozzleAngle: rotationAngle, bend: dynamics.bend)
            let center = NSPoint(x: nozzle.x + offset.x, y: nozzle.y + offset.y)
            let taper = min(1, max(0.28, 0.42 + (1 - CGFloat(h)) * 0.58))
            if hypot(point.x - center.x, point.y - center.y) <= flameWidth * taper * 0.52 + 3 { return true }
        }
        return false
    }

    func flameHeat(atScreenPoint point: NSPoint) -> Double {
        guard isIgnited, let nozzle = screenPoint(local: flameNozzleAnchor) else { return 0 }
        let height = flameHeight
        var nearest = CGFloat.greatestFiniteMagnitude
        var nearestFraction: CGFloat = 0
        for sample in 1...48 {
            let h = Double(sample) / 48
            let offset = FlameField.plumePoint(fraction: h, height: Double(height),
                                               nozzleAngle: rotationAngle, bend: dynamics.bend)
            let center = NSPoint(x: nozzle.x + offset.x, y: nozzle.y + offset.y)
            let distance = hypot(point.x - center.x, point.y - center.y)
            if distance < nearest { nearest = distance; nearestFraction = CGFloat(h) }
        }
        let width = flameWidth * (0.42 + (1 - nearestFraction) * 0.58)
        let coverage = max(0, min(1, 1 - nearest / max(1, width * 0.52 + 2)))
        return coverage * coverage * (3 - 2 * coverage)
    }

    private func flameSearchBounds(nozzle: NSPoint, height: CGFloat) -> NSRect {
        // Each integrated plume point lies within height of the nozzle, plus
        // the clamped 140-point bend and the hit-test radius.
        let radius = height + 140 + flameWidth + 4
        return NSRect(x: nozzle.x - radius, y: nozzle.y - radius, width: radius * 2, height: radius * 2)
    }

    func flameIntersectsScreenSegment(_ start: NSPoint, _ end: NSPoint) -> Bool {
        if optimizedFlame {
            guard isIgnited, let nozzle = screenPoint(local: flameNozzleAnchor) else { return false }
            let height = flameHeight
            let segmentBounds = NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                       width: abs(end.x - start.x), height: abs(end.y - start.y)).insetBy(dx: -0.01, dy: -0.01)
            guard flameSearchBounds(nozzle: nozzle, height: height).intersects(segmentBounds) else { return false }
            // The same 32 centers were previously recomputed for each of the
            // 21 points on the cigarette. Compute them once per check.
            let samples: [(NSPoint, CGFloat)] = (1...32).map { sample in
                let h = Double(sample) / 32
                let offset = FlameField.plumePoint(fraction: h, height: Double(height),
                                                   nozzleAngle: rotationAngle, bend: dynamics.bend)
                let taper = min(1, max(0.28, 0.42 + (1 - CGFloat(h)) * 0.58))
                return (NSPoint(x: nozzle.x + offset.x, y: nozzle.y + offset.y), flameWidth * taper * 0.52 + 3)
            }
            for sample in 0...20 {
                let t = CGFloat(sample) / 20
                let point = NSPoint(x: start.x + (end.x - start.x) * t,
                                    y: start.y + (end.y - start.y) * t)
                if samples.contains(where: { hypot(point.x - $0.0.x, point.y - $0.0.y) <= $0.1 }) { return true }
            }
            return false
        }
        for sample in 0...20 {
            let t = CGFloat(sample) / 20
            let point = NSPoint(x: start.x + (end.x - start.x) * t,
                                y: start.y + (end.y - start.y) * t)
            if flameContainsScreenPoint(point) { return true }
        }
        return false
    }

    override func mouseDown(with event: NSEvent) {
        let point = localPoint(convert(event.locationInWindow, from: nil))
        downScreen = NSEvent.mouseLocation; downOrigin = window?.frame.origin ?? .zero
        pressStartedAt = downScreen; ignitionStartedByPress = false
        let adjusterHit = style.artworkFrame == nil
            ? NSRect(x: 98, y: 155, width: 46, height: 14).contains(point)
            : NSRect(x: 83, y: 182, width: 46, height: 13).contains(point)
        let bodyBounds = style.artwork == nil
            ? NSRect(x: 66, y: 12, width: 88, height: 190)
            : (style.artworkFrame ?? NSRect(x: 22, y: 13, width: 176, height: 222))
        if event.clickCount == 2, bodyBounds.contains(point), !adjusterHit, fuelLevel > 0 {
            pressIgnitionTimer?.invalidate(); pressIgnitionTimer = nil
            gesture = nil
            isIgnited.toggle()
            onIgnitionChanged?(isIgnited)
            return
        }
        if adjusterHit {
            gesture = .adjust
            adjustFlame(at: point)
        } else if rotationZone(point) {
            gesture = .rotate; rotationPivot = NSPoint(x: bounds.midX, y: bounds.midY)
            let pointer = NSEvent.mouseLocation
            let center = window?.convertPoint(toScreen: convert(rotationPivot, to: nil)) ?? .zero
            initialPointerAngle = atan2(pointer.y - center.y, pointer.x - center.x); initialRotation = rotationAngle
        } else {
            gesture = .move
            let timer = Timer(timeInterval: 0.42, repeats: false) { [weak self] _ in
                guard let self, self.gesture == .move,
                      hypot(NSEvent.mouseLocation.x - self.pressStartedAt.x,
                            NSEvent.mouseLocation.y - self.pressStartedAt.y) < 4,
                      self.fuelLevel > 0 else { return }
                self.ignitionStartedByPress = true
                self.isIgnited = true
                self.onIgnitionChanged?(true)
            }
            pressIgnitionTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        startAnimation()
    }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let store = NSMenuItem(title: tr("放回背包"), action: #selector(storeInInventory), keyEquivalent: "")
        store.target = self; menu.addItem(store)
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }
    @objc private func storeInInventory() { onStoreInInventory?() }
    override func mouseDragged(with event: NSEvent) {
        guard let gesture else { return }
        let pointer = NSEvent.mouseLocation
        if hypot(pointer.x - pressStartedAt.x, pointer.y - pressStartedAt.y) >= 4 {
            pressIgnitionTimer?.invalidate(); pressIgnitionTimer = nil
        }
        switch gesture {
        case .move:
            let delta = NSPoint(x: pointer.x - downScreen.x, y: pointer.y - downScreen.y)
            if let correction = onMove?(downOrigin, delta) {
                downOrigin.x += correction.x; downOrigin.y += correction.y
            }
        case .adjust:
            adjustFlame(at: localPoint(convert(event.locationInWindow, from: nil)))
        case .rotate:
            let center = window?.convertPoint(toScreen: convert(rotationPivot, to: nil)) ?? .zero
            let pointerAngle = atan2(pointer.y - center.y, pointer.x - center.x)
            rotationAngle = initialRotation + pointerAngle - initialPointerAngle
            onRotationChanged?(rotationAngle)
        }
    }
    private func adjustFlame(at point: NSPoint) {
        if style.artworkFrame != nil {
            flameLevel = min(1, max(0, (point.x - 91.75) / 27.5))
            UserDefaults.standard.set(Double(flameLevel), forKey: "lighterFlameLevelV1")
            needsDisplay = true
            return
        }
        let range = style.artworkFrame == nil ? 40.0 : 35.0
        let origin = style.artworkFrame == nil ? 100.0 : 84.0
        flameLevel = min(1, max(0, (point.x - origin) / range))
        UserDefaults.standard.set(Double(flameLevel), forKey: "lighterFlameLevelV1")
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let gesture else { return }
        pressIgnitionTimer?.invalidate(); pressIgnitionTimer = nil
        if gesture == .move { onMoveFinished?() }
        if ignitionStartedByPress {
            ignitionStartedByPress = false
            isIgnited = false; onIgnitionChanged?(false)
        }
        self.gesture = nil
    }
    func cancelInteraction() {
        pressIgnitionTimer?.invalidate(); pressIgnitionTimer = nil
        if ignitionStartedByPress { ignitionStartedByPress = false; isIgnited = false; onIgnitionChanged?(false) }
        debugIgnitionTimer?.invalidate(); debugIgnitionTimer = nil
        if isIgnited { isIgnited = false; onIgnitionChanged?(false) }
        gesture = nil
    }
    func testIgnition(for duration: TimeInterval = 2) {
        guard fuelLevel > 0 else { return }
        isIgnited = true; onIgnitionChanged?(true)
        debugIgnitionTimer?.invalidate()
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.isIgnited = false; self.onIgnitionChanged?(false); self.debugIgnitionTimer = nil
        }
        debugIgnitionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
