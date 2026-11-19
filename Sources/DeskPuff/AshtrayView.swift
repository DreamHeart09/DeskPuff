import AppKit
import DeskPuffCore

struct AshtrayRimContact {
    let correction: NSPoint
    let point: NSPoint
}

final class AshtrayView: NSView {
    static let surfaceGroupID: UInt32 = 0x2F000000
    static let surfaceCount = 20
    static let canvasSize = NSSize(width: 500, height: 360)

    var onMove: ((NSPoint, NSPoint) -> Void)?
    var onMoveFinished: (() -> Void)?
    var onRotationChanged: ((Double) -> Void)?
    var onDumpAsh: (() -> Void)?
    var onRecoveryContentsChanged: (() -> Void)?
    var onClearAsh: (() -> Void)?
    var onStoreInInventory: (() -> Void)?
    var onAshSpilled: (([AshParticle]) -> Void)?
    var rotationAngle = 0.0 { didSet { needsDisplay = true; startAshMotion() } }
    var style: AshtrayStyle = .default {
        didSet {
            artworkSilhouette = nil
            needsDisplay = true
        }
    }
    var scale = 1.0 { didSet { needsDisplay = true } }
    private struct StoredAsh {
        var point: NSPoint
        var particle: AshParticle
        var velocity: CGFloat = 0
    }
    private struct StoredAshRecord: Codable {
        var x: Double
        var y: Double
        var size: Double
        var seed: UInt32
        var rotation: Double
        var material: RecoveryMaterial?
        var units: Int?
        var mass: Int?
        var batchID: UUID?
        var isClump: Bool?
        var widthScale: Double?
    }
    private struct InventoryState: Codable { var ashes: [StoredAshRecord]; var scale: Double; var rotation: Double }
    private var storedAsh: [StoredAsh] = []
    var inventoryState: Data? {
        let records = storedAsh.map { flake in
            StoredAshRecord(x: flake.point.x, y: flake.point.y, size: flake.particle.size,
                            seed: flake.particle.shapeSeed, rotation: flake.particle.rotation,
                            material: flake.particle.recoveryMaterial, units: nil,
                            mass: flake.particle.recoveryMass, batchID: flake.particle.recoveryBatchID,
                            isClump: flake.particle.isClump, widthScale: flake.particle.visualWidthScale)
        }
        return try? JSONEncoder().encode(InventoryState(ashes: records, scale: scale, rotation: rotationAngle))
    }

    func restoreInventoryState(_ data: Data?) {
        guard let data else { return }
        let state = try? JSONDecoder().decode(InventoryState.self, from: data)
        let records = state?.ashes ?? (try? JSONDecoder().decode([StoredAshRecord].self, from: data))
        guard let records else { return }
        if let state { scale = state.scale; rotationAngle = state.rotation }
        let legacyBatchID = UUID()
        storedAsh = records.map { record in
            var particle = AshParticle(x: 0, y: 0, vx: 0, vy: 0, size: record.size,
                                       shapeSeed: record.seed, rotation: record.rotation)
            particle.recoveryMaterial = record.material
            particle.recoveryMass = min(20_000, max(0, record.mass ?? min(20, max(0, record.units ?? 0)) * RecoveryMaterial.legacyMassPerUnit))
            particle.recoveryBatchID = record.batchID ?? legacyBatchID
            particle.isClump = record.isClump ?? false
            particle.visualWidthScale = record.widthScale ?? 1
            return StoredAsh(point: NSPoint(x: record.x, y: record.y), particle: particle)
        }
        needsDisplay = true
    }
    func resetInventoryState() {
        clearAsh(); scale = 1; rotationAngle = 0
    }
    private var artworkSilhouette: [NSPoint]?
    private var ashMotionTimer: Timer?
    private var lastAshMotion = CACurrentMediaTime()

    private enum DragMode { case move, rotate }
    private var dragMode: DragMode = .move
    private var downScreen = NSPoint.zero
    private var downOrigin = NSPoint.zero
    private var initialAngle = 0.0
    private var initialPointerAngle = 0.0
    private var artworkCenter: NSPoint {
        if let frame = style.artworkFrame { return NSPoint(x: frame.midX, y: frame.midY) }
        return style.id == "clear-glass" ? NSPoint(x: 160, y: 115) : NSPoint(x: 160, y: 100)
    }
    private var artworkOffset: NSPoint {
        NSPoint(x: Self.canvasSize.width / 2 - artworkCenter.x,
                y: Self.canvasSize.height / 2 - artworkCenter.y)
    }
    private var basin: NSRect { style.basinFrame ?? NSRect(x: 29, y: 53, width: 262, height: 78) }
    private var ashStorageLimit: Int {
        let bonus = max(1, UserDefaults.standard.object(forKey: "inventoryToolAshtrayCapacityMultiplierV1") as? Double ?? 1)
        return Int((1200 * bonus).rounded(.down))
    }
    private var bodyBounds: NSRect {
        if let frame = style.artworkFrame { return frame }
        return style.id == "clear-glass" ? NSRect(x: 10, y: 10, width: 300, height: 210)
                                   : NSRect(x: 16, y: 31, width: 288, height: 132)
    }
    private var visualScale: CGFloat { CGFloat(min(2, max(0.5, scale)) * 0.75) }

    override var isOpaque: Bool { false }

    private func artPoint(fromView point: NSPoint) -> NSPoint {
        let shifted = NSPoint(x: point.x - artworkOffset.x, y: point.y - artworkOffset.y)
        let dx = shifted.x - artworkCenter.x, dy = shifted.y - artworkCenter.y
        let c = cos(rotationAngle), s = sin(rotationAngle)
        return NSPoint(x: artworkCenter.x + (dx * c + dy * s) / visualScale,
                       y: artworkCenter.y + (-dx * s + dy * c) / visualScale)
    }

    private func viewPoint(fromArt point: NSPoint) -> NSPoint {
        let dx = point.x - artworkCenter.x, dy = point.y - artworkCenter.y
        let c = cos(rotationAngle), s = sin(rotationAngle)
        return NSPoint(x: artworkCenter.x + (dx * c - dy * s) * visualScale + artworkOffset.x,
                       y: artworkCenter.y + (dx * s + dy * c) * visualScale + artworkOffset.y)
    }

    private func basinPathInView() -> NSBezierPath {
        let path = NSBezierPath()
        let segments = 64
        for index in 0..<segments {
            let angle = Double(index) * 2 * .pi / Double(segments)
            let artPoint = NSPoint(x: basin.midX + CGFloat(cos(angle)) * basin.width * 0.5,
                                   y: basin.midY + CGFloat(sin(angle)) * basin.height * 0.5)
            let point = viewPoint(fromArt: artPoint)
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        return path
    }

    private func artPoint(fromScreen point: NSPoint) -> NSPoint? {
        guard let window else { return nil }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        return artPoint(fromView: local)
    }

    private func screenPoint(fromArt point: NSPoint) -> NSPoint? {
        guard let window else { return nil }
        return window.convertPoint(toScreen: convert(viewPoint(fromArt: point), to: nil))
    }

    func containsBasin(screenPoint point: NSPoint) -> Bool {
        guard let art = artPoint(fromScreen: point) else { return false }
        return insideBasin(art)
    }

    func trayLocalPoint(fromScreenPoint point: NSPoint) -> NSPoint? {
        artPoint(fromScreen: point)
    }

    func screenPoint(fromTrayLocalPoint point: NSPoint) -> NSPoint? {
        screenPoint(fromArt: point)
    }

    func visibleArtworkBounds() -> NSRect {
        if artworkSilhouette == nil {
            artworkSilhouette = style.artwork.flatMap { Self.silhouette(of: $0, in: bodyBounds) }
                ?? (0..<128).map { index in
                    let angle = Double(index) * 2 * .pi / 128
                    return NSPoint(x: 160 + cos(angle) * 142, y: 95 + sin(angle) * 58)
                }
        }
        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity
        let points = artworkSilhouette ?? []
        let cosine = cos(rotationAngle) * visualScale
        let sine = sin(rotationAngle) * visualScale
        let center = artworkCenter
        let offset = artworkOffset
        for point in points {
            let dx = point.x - center.x
            let dy = point.y - center.y
            let x = center.x + offset.x + dx * cosine - dy * sine
            let y = center.y + offset.y + dx * sine + dy * cosine
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func silhouette(of image: NSImage, in frame: NSRect) -> [NSPoint]? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = min(source.width, 480)
        let height = min(source.height, 480)
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let alpha = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let dx = frame.width / CGFloat(width)
        let dy = frame.height / CGFloat(height)
        var points: [NSPoint] = []
        // A rotated extent can only occur at one of the two alpha edges of a row.
        for row in 0..<height {
            let pixels = alpha + row * context.bytesPerRow
            let columns = 0..<width
            guard let first = columns.first(where: { pixels[$0 * 4 + 3] >= 48 }),
                  let last = columns.last(where: { pixels[$0 * 4 + 3] >= 48 }) else { continue }
            let bottom = frame.maxY - CGFloat(row + 1) * dy
            let left = frame.minX + CGFloat(first) * dx
            let right = frame.minX + CGFloat(last + 1) * dx
            points.append(NSPoint(x: left, y: bottom))
            points.append(NSPoint(x: right, y: bottom))
            points.append(NSPoint(x: left, y: bottom + dy))
            points.append(NSPoint(x: right, y: bottom + dy))
        }
        return points.isEmpty ? nil : points
    }

    @discardableResult
    func storeAsh(_ particle: AshParticle) -> Bool {
        guard storedAsh.count < ashStorageLimit,
              let point = artPoint(fromScreen: NSPoint(x: particle.x, y: particle.y)),
              insideBasin(point) else { return false }
        storedAsh.append(StoredAsh(point: point, particle: particle))
        if particle.recoveryMass > 0 { onRecoveryContentsChanged?() }
        startAshMotion()
        needsDisplay = true
        return true
    }

    func depositCrushedAsh(at screenPoint: NSPoint, amount: Double, scale: CGFloat, recoveryMass: Int) {
        guard let center = artPoint(fromScreen: screenPoint) else { return }
        let count = max(6, AshGeometry.fragmentCount(level: CigaretteImpact.fragmentLevel(ash: amount), scale: scale, amount: .standard))
        let before = storedAsh.count
        for _ in 0..<count where storedAsh.count < ashStorageLimit {
            let point = NSPoint(x: center.x + CGFloat.random(in: -10...10),
                                y: center.y + CGFloat.random(in: 1...8))
            guard insideBasin(point) else { continue }
            let particle = AshParticle(x: 0, y: 0, vx: 0, vy: 0,
                                       size: Double.random(in: 1.5...4.0) * Double(scale),
                                       shapeSeed: UInt32.random(in: 1...UInt32.max),
                                       rotation: Double.random(in: 0...(.pi * 2)))
            storedAsh.append(StoredAsh(point: point, particle: particle))
        }
        let added = storedAsh.count - before
        if added > 0 && recoveryMass > 0 {
            let batchID = UUID()
            for index in 0..<added {
                storedAsh[before + index].particle.recoveryMaterial = .fineAsh
                storedAsh[before + index].particle.recoveryBatchID = batchID
                storedAsh[before + index].particle.recoveryMass = recoveryMass / added + (index < recoveryMass % added ? 1 : 0)
            }
            onRecoveryContentsChanged?()
        }
        startAshMotion()
        needsDisplay = true
    }

    private func startAshMotion() {
        guard !storedAsh.isEmpty, ashMotionTimer == nil, abs(sin(rotationAngle)) > 0.12 else { return }
        lastAshMotion = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.advanceStoredAsh()
        }
        ashMotionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceStoredAsh() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(0.05, max(0, now - lastAshMotion)))
        lastAshMotion = now
        let slope = CGFloat(-sin(rotationAngle))
        var remaining: [StoredAsh] = []
        var spilled: [AshParticle] = []
        for var flake in storedAsh {
            flake.velocity = (flake.velocity + slope * 180 * dt) * pow(0.23, dt)
            flake.point.x += flake.velocity * dt
            let y = min(0.96, abs((flake.point.y - basin.midY) / (basin.height * 0.5)))
            let radius = basin.width * 0.5 * sqrt(1 - y * y)
            let edge = basin.midX + (slope < 0 ? -radius : radius)
            let beyond = slope < 0 ? flake.point.x <= edge : flake.point.x >= edge
            if beyond && abs(slope) > 0.55, let screen = screenPoint(fromArt: NSPoint(x: edge, y: flake.point.y)) {
                var particle = flake.particle
                particle.x = screen.x; particle.y = screen.y
                particle.vx = 0; particle.vy = 0
                spilled.append(particle)
            } else {
                flake.point.x = min(basin.midX + radius - 0.5, max(basin.midX - radius + 0.5, flake.point.x))
                if beyond { flake.velocity = 0 }
                remaining.append(flake)
            }
        }
        storedAsh = remaining
        if !spilled.isEmpty {
            if spilled.contains(where: { $0.recoveryMass > 0 }) { onRecoveryContentsChanged?() }
            onAshSpilled?(spilled)
        }
        needsDisplay = true
        if storedAsh.isEmpty || (abs(slope) < 0.12 && storedAsh.allSatisfy({ abs($0.velocity) < 1 })) {
            ashMotionTimer?.invalidate(); ashMotionTimer = nil
        }
    }

    func ejectStoredAsh() -> [AshParticle] {
        let direction: CGFloat = sin(rotationAngle) > 0 ? -1 : 1
        let released = storedAsh.compactMap { flake -> AshParticle? in
            let edge = NSPoint(x: basin.midX + direction * basin.width * 0.48, y: basin.midY)
            guard let screen = screenPoint(fromArt: edge) else { return nil }
            var particle = flake.particle
            particle.x = Double(screen.x); particle.y = Double(screen.y)
            return particle
        }
        storedAsh.removeAll(keepingCapacity: true)
        ashMotionTimer?.invalidate(); ashMotionTimer = nil
        needsDisplay = true
        onRecoveryContentsChanged?()
        return released
    }

    func clearAsh() {
        let hadContents = !storedAsh.isEmpty
        storedAsh.removeAll(keepingCapacity: true)
        ashMotionTimer?.invalidate()
        ashMotionTimer = nil
        needsDisplay = true
        if hadContents { onRecoveryContentsChanged?() }
    }

    private func insideBasin(_ point: NSPoint) -> Bool {
        let dx = (point.x - basin.midX) / (basin.width * 0.5)
        let dy = (point.y - basin.midY) / (basin.height * 0.5)
        return dx * dx + dy * dy <= 1
    }

    func basinFloorContact(from previousScreenPoint: NSPoint, to currentScreenPoint: NSPoint) -> AshtrayRimContact? {
        guard let previous = artPoint(fromScreen: previousScreenPoint),
              let current = artPoint(fromScreen: currentScreenPoint) else { return nil }
        let halfWidth = basin.width * 0.5
        func floorY(_ x: CGFloat) -> CGFloat {
            let normalized = (x - basin.midX) / halfWidth
            // Raise the contact surface into the visible basin so cigarette tips
            // and loose ash stop above the illustrated outer underside.
            return basin.minY + basin.height * 0.47 + 10 * normalized * normalized
        }
        func heightAboveFloor(_ point: NSPoint) -> CGFloat { point.y - floorY(point.x) }
        guard previous.x >= basin.minX + 3, previous.x <= basin.maxX - 3,
              current.x >= basin.minX + 3, current.x <= basin.maxX - 3,
              heightAboveFloor(previous) >= 0, heightAboveFloor(current) < 0 else { return nil }
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<18 {
            let mid = (low + high) * 0.5
            let point = NSPoint(x: previous.x + (current.x - previous.x) * mid,
                                y: previous.y + (current.y - previous.y) * mid)
            if heightAboveFloor(point) >= 0 { low = mid } else { high = mid }
        }
        let t = (low + high) * 0.5
        let hit = NSPoint(x: previous.x + (current.x - previous.x) * t,
                          y: previous.y + (current.y - previous.y) * t)
        let slope = 20 * ((hit.x - basin.midX) / halfWidth) / halfWidth
        let normalLength = max(0.001, hypot(slope, 1))
        let safe = NSPoint(x: hit.x - slope * 2 / normalLength, y: hit.y + 2 / normalLength)
        guard let hitScreen = screenPoint(fromArt: hit),
              let safeScreen = screenPoint(fromArt: safe) else { return nil }
        return AshtrayRimContact(correction: NSPoint(x: safeScreen.x - currentScreenPoint.x,
                                                     y: safeScreen.y - currentScreenPoint.y), point: hitScreen)
    }

    private func isRotationEdge(_ point: NSPoint) -> Bool {
        let dx = (point.x - bodyBounds.midX) / (bodyBounds.width * 0.5)
        let dy = (point.y - bodyBounds.midY) / (bodyBounds.height * 0.5)
        let radius = dx * dx + dy * dy
        return radius >= 0.78 && radius <= 1
    }

    func ashSurfaces() -> [AshSurface] {
        guard let window else { return [] }
        // The basin is shallow and concave: many short, stable segments give
        // falling ash a gently cupped floor while retaining the existing solver.
        let floor = (0..<Self.surfaceCount).compactMap { index -> AshSurface? in
            let usableWidth = basin.width - 24
            let x0 = basin.minX + 12 + CGFloat(index) * usableWidth / CGFloat(Self.surfaceCount)
            let x1 = basin.minX + 12 + CGFloat(index + 1) * usableWidth / CGFloat(Self.surfaceCount)
            func floorY(_ x: CGFloat) -> CGFloat {
                let normalized = (x - basin.midX) / (basin.width * 0.5)
                return basin.minY + basin.height * 0.47 + 10 * normalized * normalized
            }
            guard let a = screenPoint(fromArt: NSPoint(x: x0, y: floorY(x0))),
                  let b = screenPoint(fromArt: NSPoint(x: x1, y: floorY(x1))) else { return nil }
            let id = Self.surfaceGroupID &+ UInt32(index)
            return AshSurface(id: id, x: min(a.x, b.x) - 0.5, y: max(a.y, b.y),
                              width: max(1, abs(b.x - a.x) + 1), groupID: Self.surfaceGroupID)
        }
        // Keep the basin open while exposing the outer lower rim and its
        // short shoulders as landing surfaces when the tray is rotated.
        let baseID = UInt32(0x30000000) | ((UInt32(truncatingIfNeeded: window.windowNumber) & 0x000fffff) << 8)
        let bounds = bodyBounds
        let count = 48
        let outline = (0..<count).flatMap { index -> [AshSurface] in
            let a0 = 2 * .pi * CGFloat(index) / CGFloat(count)
            let a1 = 2 * .pi * CGFloat(index + 1) / CGFloat(count)
            let mid = (a0 + a1) / 2
            let upper = sin(mid) > 0
            let x = bounds.midX + cos(mid) * bounds.width / 2
            guard !upper || x < basin.minX || x > basin.maxX else { return [] }
            func point(_ angle: CGFloat) -> NSPoint {
                NSPoint(x: bounds.midX + cos(angle) * bounds.width / 2,
                        y: bounds.midY + sin(angle) * bounds.height / 2)
            }
            guard let start = screenPoint(fromArt: point(a0)), let end = screenPoint(fromArt: point(a1)) else { return [] }
            return CigaretteAshSurface.segments(from: start, to: end, idBase: baseID &+ UInt32(index * 2), count: 2)
        }
        return floor + outline
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let art = artPoint(fromView: point)
        let body = NSBezierPath(ovalIn: bodyBounds)
        return body.contains(art) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        downScreen = NSEvent.mouseLocation
        downOrigin = window?.frame.origin ?? .zero
        let local = convert(event.locationInWindow, from: nil)
        let art = artPoint(fromView: local)
        if isRotationEdge(art) {
            dragMode = .rotate
            initialAngle = rotationAngle
            initialPointerAngle = atan2(downScreen.y - (window?.frame.minY ?? 0) - artworkCenter.y - artworkOffset.y,
                                        downScreen.x - (window?.frame.minX ?? 0) - artworkCenter.x - artworkOffset.x)
        } else { dragMode = .move }
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        switch dragMode {
        case .move:
            onMove?(downOrigin, NSPoint(x: current.x - downScreen.x, y: current.y - downScreen.y))
        case .rotate:
            let center = NSPoint(x: (window?.frame.minX ?? 0) + artworkCenter.x + artworkOffset.x,
                                 y: (window?.frame.minY ?? 0) + artworkCenter.y + artworkOffset.y)
            let angle = atan2(current.y - center.y, current.x - center.x)
            rotationAngle = initialAngle + angle - initialPointerAngle
            onRotationChanged?(rotationAngle)
        }
    }

    override func mouseUp(with event: NSEvent) { onMoveFinished?() }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: tr("放回背包"), action: #selector(storeInInventory), keyEquivalent: ""))
        for item in menu.items where item.action != nil { item.target = self }
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }

    @objc private func rotateClockwise() { setRotation(rotationAngle - .pi / 12) }
    @objc private func rotateCounterclockwise() { setRotation(rotationAngle + .pi / 12) }
    @objc private func rotateQuarterTurn() { setRotation(rotationAngle + .pi / 2) }
    @objc private func dumpAsh() { onDumpAsh?() }
    @objc private func clearContents() { onClearAsh?() }
    @objc private func storeInInventory() { onStoreInInventory?() }
    private func setRotation(_ angle: Double) { rotationAngle = angle; onRotationChanged?(angle) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        context.translateBy(x: artworkOffset.x, y: artworkOffset.y)
        context.translateBy(x: artworkCenter.x, y: artworkCenter.y)
        context.rotate(by: rotationAngle)
        context.scaleBy(x: visualScale, y: visualScale)
        context.translateBy(x: -artworkCenter.x, y: -artworkCenter.y)

        if style.artwork == nil {
            let shadow = NSBezierPath(ovalIn: NSRect(x: 22, y: 25, width: 276, height: 118))
            NSColor(calibratedWhite: 0.08, alpha: 0.16).setFill(); shadow.fill()
        }

        let body = NSBezierPath(ovalIn: NSRect(x: 18, y: 37, width: 284, height: 116))
        let rim = NSBezierPath(ovalIn: NSRect(x: 26, y: 53, width: 268, height: 82))
        let inner = NSBezierPath(ovalIn: basin)
        if let artwork = style.artwork {
            artwork.draw(in: bodyBounds, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            NSGradient(colors: style.body)?.draw(in: body, angle: 90)
            style.bodyStroke.withAlphaComponent(0.70).setStroke(); body.lineWidth = 0.8; body.stroke()
            NSGradient(colors: style.rim)?.draw(in: rim, angle: 90)
            NSGradient(colors: style.basin)?.draw(in: inner, angle: 90)
            style.trim.withAlphaComponent(0.78).setStroke(); inner.lineWidth = 0.7; inner.stroke()
        }

        NSGraphicsContext.saveGraphicsState(); inner.addClip()
        if style.artwork == nil {
            let depression = NSBezierPath(ovalIn: NSRect(x: 62, y: 62, width: 196, height: 43))
            NSGradient(colors: [NSColor(calibratedWhite: 0.09, alpha: 0.60), NSColor(calibratedWhite: 0.36, alpha: 0.25)])?.draw(in: depression, angle: 90)
        }
        NSGraphicsContext.restoreGraphicsState()

        if style.artwork == nil {
            let frontGlaze = NSBezierPath()
            frontGlaze.move(to: NSPoint(x: 31, y: 72)); frontGlaze.curve(to: NSPoint(x: 289, y: 72), controlPoint1: NSPoint(x: 92, y: 40), controlPoint2: NSPoint(x: 228, y: 40))
            style.highlight.withAlphaComponent(0.52).setStroke(); frontGlaze.lineWidth = 1.3; frontGlaze.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()

        // Store particle positions in basin coordinates, but render their
        // sizes in view points so resizing the tray never scales the ash.
        NSGraphicsContext.saveGraphicsState()
        basinPathInView().addClip()
        for flake in storedAsh {
            AshParticleRenderer.draw(flake.particle, at: viewPoint(fromArt: flake.point))
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
