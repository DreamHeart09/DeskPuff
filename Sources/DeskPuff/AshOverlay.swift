import AppKit
import CoreGraphics
import DeskPuffCore

@MainActor final class AshOverlay {
    private var particles: [AshParticle] = []
    private var windows: [NSPanel] = []
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var lastWindowScan: CFTimeInterval = 0
    private var surfaces: [AshSurface] = []
    private struct Emission {
        var remaining: Int
        let perTick: Int
        let origin: NSPoint
        let motion: NSPoint
        let scale: Double
        var recoveryMass: Int
        let batchID: UUID?
    }
    private var pendingEmissions: [Emission] = []
    private var shown = true
    private var hasFalling = true
    private var lastIdleUpdate: CFTimeInterval = 0
    var amount: AshAmount = .standard
    var cigaretteSurfaces: (() -> [AshSurface])?
    var ashtraySurfaces: (() -> [AshSurface])?
    var additionalWindowSurfaces: (() -> [AshSurface])?
    var storeInAshtray: ((AshParticle) -> Bool)?
    var recoveryOpening: (() -> RecoveryOpening?)?
    var collectAsh: (([(batch: AshRecoveryBatch, mass: Int)]) -> [AshRecoveryBatch: Int])?

    func sweepRecoveryOpening(from previous: RecoveryOpening?, to opening: RecoveryOpening) {
        _ = captureAsh(in: opening, previousOpening: previous)
    }

    private func captureAsh(in opening: RecoveryOpening, previousOpening: RecoveryOpening? = nil,
                            previousPositions: [CGPoint]? = nil) -> [Int] {
        var candidates: [Int] = []
        var offered: [AshRecoveryBatch: Int] = [:]
        var batches: [AshRecoveryBatch] = []
        for index in particles.indices {
            let particle = particles[index]
            guard particle.supportingSurfaceGroup != AshtrayView.surfaceGroupID else { continue }
            let end = CGPoint(x: particle.x, y: particle.y)
            guard opening.crosses(from: previousPositions?[index] ?? end, to: end, previous: previousOpening) else { continue }
            candidates.append(index)
            if let batch = particle.recoveryBatch {
                if offered[batch] == nil { batches.append(batch) }
                offered[batch, default: 0] += particle.recoveryMass
            }
        }
        guard !candidates.isEmpty else { return [] }
        var removed: [Int] = []
        var accepted = collectAsh?(batches.map { ($0, offered[$0, default: 0]) }) ?? [:]
        for index in candidates.reversed() {
            guard let batch = particles[index].recoveryBatch else {
                particles.remove(at: index)
                removed.append(index)
                continue
            }
            let taken = min(particles[index].recoveryMass, accepted[batch, default: 0])
            guard taken > 0 else { continue }
            accepted[batch, default: 0] -= taken
            particles[index].recoveryMass -= taken
            if particles[index].recoveryMass == 0 { particles.remove(at: index); removed.append(index) }
        }
        windows.forEach { $0.contentView?.needsDisplay = true }
        return removed
    }

    func updateDisplays() {
        windows.forEach { $0.orderOut(nil) }; windows.removeAll()
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true; panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false
            let view = AshView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.owner = self; panel.contentView = view
            windows.append(panel)
            if shown && !particles.isEmpty { panel.orderFrontRegardless() }
        }
    }
    func setVisible(_ value: Bool) {
        shown = value; lastTick = CACurrentMediaTime()
        if value && (!particles.isEmpty || !pendingEmissions.isEmpty) { windows.forEach { $0.orderFrontRegardless() }; start() }
        else { timer?.invalidate(); timer = nil; windows.forEach { $0.orderOut(nil) } }
    }
    func clear() { particles.removeAll(); pendingEmissions.removeAll(); timer?.invalidate(); timer = nil; windows.forEach { $0.orderOut(nil) } }
    enum FallStyle { case disturbed, natural, tapped }
    func shed(at point: NSPoint, amount: Double, motion: NSPoint, scale: Double, orientation: Double = 0, style: FallStyle = .disturbed, recoveryMass: Int = 0) {
        guard amount > 0 else { return }
        let count = AshGeometry.fragmentCount(level: amount, scale: scale, amount: self.amount)
        if style == .natural {
            appendNaturalFall(at: point, amount: amount, scale: scale, orientation: orientation,
                              recoveryMaterial: .ashClump, recoveryMass: recoveryMass)
        } else if style == .tapped {
            appendNaturalFall(at: point, amount: amount, scale: scale, orientation: orientation,
                              breakApartAfter: 0.16,
                              breakApartCount: AshGeometry.fragmentCount(level: amount, scale: scale, amount: self.amount),
                              recoveryMaterial: .fineAsh, recoveryMass: recoveryMass)
        } else if self.amount == .heavy {
            // Release the whole shed in at most six frames, without discarding ash.
            pendingEmissions.append(Emission(remaining: count, perTick: AshAmount.releaseBatchSize(for: count), origin: point, motion: motion, scale: scale,
                                             recoveryMass: recoveryMass, batchID: recoveryMass > 0 ? UUID() : nil))
        } else {
            appendParticles(count: count, at: point, motion: motion, scale: scale, spread: false,
                            recoveryMass: recoveryMass)
        }
        showDetachedAsh()
    }
    func crush(at point: NSPoint, ashAmount: Double, motion: NSPoint, scale: Double, orientation: Double = 0, recoveryMass: Int = 0) {
        // The small dark core represents charred material even when no loose ash
        // has accumulated; loose ash itself is consumed only once by the caller.
        let level = CigaretteImpact.fragmentLevel(ash: ashAmount)
        let baseCount = max(6, AshGeometry.fragmentCount(level: level, scale: scale, amount: self.amount))
        let impact = min(1, hypot(motion.x, motion.y) / 1600)
        let profile = AshCrushProfile(ash: ashAmount, baseCount: baseCount, impact: impact,
                                      charSample: Double.random(in: 0...1), sizeSample: Double.random(in: 0...1),
                                      countSample: Double.random(in: 0...1))
        appendNaturalFall(at: point, amount: profile.charLevel, scale: scale, motion: motion, sizeVariation: profile.sizeVariation, orientation: orientation)
        appendParticles(count: profile.fragmentCount, at: point, motion: motion, scale: scale, spread: false, impact: impact, recoveryMass: recoveryMass)
        showDetachedAsh()
    }
    func scatterFromAshtray(_ particlesToScatter: [AshParticle], impulse: NSPoint) {
        guard !particlesToScatter.isEmpty else { return }
        for var particle in particlesToScatter {
            let vx = Double(impulse.x) + Double.random(in: -12...12)
            let vy = Double(impulse.y) + Double.random(in: -6...10)
            if particle.supportingSurfaceGroup == AshtrayView.surfaceGroupID {
                particle.release(fromSurfaceGroup: AshtrayView.surfaceGroupID, impulseX: vx, impulseY: vy)
            } else {
                particle.vx += vx; particle.vy += vy; particle.beginLooseFall()
            }
            particles.append(particle)
        }
        showDetachedAsh()
        start()
    }
    private func showDetachedAsh() {
        hasFalling = true
        if shown {
            // Paint the detached cap in the same event that removes it from the
            // cigarette, rather than waiting for the first timer tick.
            windows.forEach { window in
                window.contentView?.needsDisplay = true
                window.orderFrontRegardless(); window.displayIfNeeded()
            }
            start()
        }
    }
    private func appendNaturalFall(at point: NSPoint, amount: Double, scale: Double, motion: NSPoint = .zero, sizeVariation: Double = 1, orientation: Double = 0,
                                   breakApartAfter: Double? = nil, breakApartCount: Int = 0,
                                   recoveryMaterial: RecoveryMaterial? = nil, recoveryMass: Int = 0) {
        let dimensions = AshGeometry.detachedSize(level: amount, scale: scale)
        let size = dimensions.height * sizeVariation / 0.62
        var clump = AshParticle(x: point.x, y: point.y,
                                vx: max(-12, min(12, motion.x * 0.025)) + Double.random(in: -3...3), vy: max(-12, min(5, motion.y * 0.015)) + Double.random(in: -5...0),
                                size: size, shapeSeed: UInt32.random(in: 1...100000),
                                rotation: orientation + Double.random(in: -0.12...0.12), spin: Double.random(in: -0.8...0.8))
        clump.isClump = true; clump.visualWidthScale = dimensions.width * sizeVariation / (size * 0.96)
        clump.emberRemaining = 2.0
        clump.pendingImpactCrumbs = breakApartAfter == nil
            ? max(1, AshGeometry.fragmentCount(level: amount, scale: scale, amount: self.amount) / 50) : 0
        clump.impactScale = scale
        clump.breakApartAfter = breakApartAfter
        clump.breakApartCount = breakApartCount
        clump.recoveryMaterial = recoveryMaterial
        clump.recoveryMass = recoveryMass
        clump.recoveryBatchID = recoveryMass > 0 ? UUID() : nil
        clump.pileSpread = 0.4; clump.beginLooseFall()
        particles.append(clump)
    }
    private func appendTapFragments(from clump: AshParticle, count: Int) {
        guard count > 0 else { return }
        if amount == .heavy {
            let motion = NSPoint(x: clump.vx, y: clump.vy)
            pendingEmissions.append(Emission(remaining: count,
                                             perTick: AshAmount.releaseBatchSize(for: count),
                                             origin: NSPoint(x: clump.x, y: clump.y),
                                             motion: motion,
                                             scale: clump.impactScale,
                                             recoveryMass: clump.recoveryMass, batchID: clump.recoveryBatchID))
            return
        }
        for index in 0..<count {
            var flake = AshParticle(
                x: clump.x + Double.random(in: -0.48...0.48) * clump.size * clump.visualWidthScale,
                y: clump.y + Double.random(in: -0.32...0.32) * clump.size,
                vx: clump.vx + Double.random(in: -38...38),
                vy: clump.vy + Double.random(in: -8...30),
                size: Double.random(in: 1.1...2.8) * clump.impactScale,
                shapeSeed: UInt32.random(in: 1...100000),
                rotation: clump.rotation + Double.random(in: -0.7...0.7),
                spin: Double.random(in: -4...4))
            flake.recoveryMaterial = clump.recoveryMaterial
            flake.recoveryBatchID = clump.recoveryBatchID
            flake.recoveryMass = clump.recoveryMass / count + (index < clump.recoveryMass % count ? 1 : 0)
            flake.pileSpread = 0.65
            flake.beginLooseFall()
            particles.append(flake)
        }
    }
    private func appendImpactCrumbs(from clump: AshParticle, count: Int) {
        for _ in 0..<count {
            let scale = clump.impactScale
            var crumb = AshParticle(x: clump.x + Double.random(in: -0.3...0.3) * clump.size * clump.visualWidthScale,
                                    y: clump.y - clump.size * 0.35,
                                    vx: Double.random(in: -22...22), vy: Double.random(in: 15...35),
                                    size: Double.random(in: 0.7...1.7) * scale, shapeSeed: UInt32.random(in: 1...100000),
                                    rotation: Double.random(in: 0...6.28), spin: Double.random(in: -3...3))
            crumb.pileSpread = 0.6; crumb.beginLooseFall(); particles.append(crumb)
        }
    }
    private func appendParticles(count: Int, at point: NSPoint, motion: NSPoint, scale: Double, spread: Bool, impact: Double = 0, recoveryMass: Int = 0, batchID: UUID? = nil) {
        guard count > 0 else { return }
        let releaseID = recoveryMass > 0 ? (batchID ?? UUID()) : nil
        for index in 0..<count {
            let spreadX: ClosedRange<Double> = spread ? -10...10 : -7...7
            let spreadY: ClosedRange<Double> = spread ? 0...4 : -1...2
            let velocityX: ClosedRange<Double> = spread ? -42...42 : -34...34
            var particle = AshParticle(x: point.x + Double.random(in: spreadX), y: point.y + Double.random(in: spreadY),
                                       vx: max(-22, min(22, motion.x * 0.035)) + Double.random(in: velocityX),
                                       vy: Double.random(in: spread ? -4...10 : -4...8) + impact * 8, size: Double.random(in: 1.2...3.8) * scale,
                                       shapeSeed: UInt32.random(in: 1...100000), rotation: Double.random(in: 0...6.28), spin: Double.random(in: -4...4))
            if Int.random(in: 0..<45) == 0 { particle.emberRemaining = Double.random(in: 0.35...1.1) }
            particle.beginLooseFall()
            particle.pileSpread = spread ? 1 : 0.65
            particle.recoveryMaterial = recoveryMass > 0 ? .fineAsh : nil
            particle.recoveryBatchID = releaseID
            particle.recoveryMass = recoveryMass / count + (index < recoveryMass % count ? 1 : 0)
            particles.append(particle)
        }
    }
    private func drainEmissions() {
        guard !pendingEmissions.isEmpty else { return }
        let emission = pendingEmissions[0]
        let count = min(emission.perTick, emission.remaining)
        let units = emission.recoveryMass * count / emission.remaining
        appendParticles(count: count, at: emission.origin, motion: emission.motion, scale: emission.scale, spread: true, recoveryMass: units, batchID: emission.batchID)
        pendingEmissions[0].remaining -= count
        pendingEmissions[0].recoveryMass -= units
        if pendingEmissions[0].remaining == 0 { pendingEmissions.removeFirst() }
    }
    fileprivate func render(in view: NSView) {
        guard let origin = view.window?.frame.origin else { return }
        for particle in particles {
            let x = particle.x - origin.x, y = particle.y - origin.y
            guard view.bounds.insetBy(dx: -18, dy: -18).contains(NSPoint(x: x, y: y)) else { continue }
            AshParticleRenderer.draw(particle, at: NSPoint(x: x, y: y))
        }
    }
    private func start() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let next = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(next, forMode: .common); timer = next
    }
    private func tick() {
        let now = CACurrentMediaTime()
        if !hasFalling && now - lastIdleUpdate < 0.2 { return }
        if !hasFalling { lastIdleUpdate = now }
        let dt = min(max(now - lastTick, 0), 1.0/15); lastTick = now
        if now - lastWindowScan >= 0.2 { surfaces = readWindowEdges(); lastWindowScan = now }
        drainEmissions()
        let traySurfaces = ashtraySurfaces?() ?? []
        let collisionSurfaces = surfaces + (additionalWindowSurfaces?() ?? [])
            + (cigaretteSurfaces?() ?? []) + traySurfaces
        let screens = NSScreen.screens
        func floorFor(_ p: AshParticle) -> Double {
            let screen = screens.first(where: { p.x >= $0.frame.minX && p.x < $0.frame.maxX && p.y >= $0.frame.minY - 20 && p.y <= $0.frame.maxY + 20 }) ?? NSScreen.main
            return Double(screen?.frame.minY ?? 0)
        }
        let opening = recoveryOpening?()
        let previousPositions = opening.map { _ in particles.map { CGPoint(x: $0.x, y: $0.y) } }
        var oldBottoms = particles.map { $0.y - $0.size / 2 }
        var previousBounces = particles.map { $0.bounces }
        for i in particles.indices { particles[i].step(dt: dt, surfaces: collisionSurfaces, floor: floorFor(particles[i])) }
        if let opening {
            for index in captureAsh(in: opening, previousPositions: previousPositions) {
                oldBottoms.remove(at: index)
                previousBounces.remove(at: index)
            }
        }
        let settled = particles.map { p in
            p.support != nil || p.restingOnPile || (p.vy == 0 && p.y - p.size / 2 <= floorFor(p) + 0.5)
        }
        AshPileSolver.resolve(&particles, oldBottoms: oldBottoms, settled: settled)
        var impacts: [(AshParticle, Int)] = []
        for i in particles.indices where particles[i].pendingImpactCrumbs > 0 {
            let floor = floorFor(particles[i])
            let count = particles[i].takeImpactCrumbs(previousBounces: previousBounces[i], floor: floor)
            if count > 0 { impacts.append((particles[i], count)) }
        }
        for (clump, count) in impacts { appendImpactCrumbs(from: clump, count: count) }
        let breaking = particles.indices.filter { index in
            guard let delay = particles[index].breakApartAfter else { return false }
            return particles[index].fallAge >= delay
        }
        for index in breaking.reversed() {
            let clump = particles.remove(at: index)
            appendTapFragments(from: clump, count: clump.breakApartCount)
        }
        let trayGroup = AshtrayView.surfaceGroupID
        let stored = particles.indices.reversed().filter { index in
            particles[index].breakApartAfter == nil && particles[index].supportingSurfaceGroup == trayGroup &&
                (particles[index].support != nil || particles[index].restingOnPile)
        }
        for index in stored where storeInAshtray?(particles[index]) == true { particles.remove(at: index) }
        hasFalling = !pendingEmissions.isEmpty || particles.contains { p in
            p.emberRemaining > 0 || (p.support == nil && !p.restingOnPile && (abs(p.vy) > 0.01 || p.y - p.size / 2 > floorFor(p) + 0.5))
        }
        windows.forEach { $0.contentView?.needsDisplay = true }
    }
    private func readWindowEdges() -> [AshSurface] {
        guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]], let main = NSScreen.screens.first else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let applicationEdges: [AshSurface] = rows.compactMap { row in
            guard let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
                  let layer = (row[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let raw = row[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary), bounds.width > 80, bounds.height > 50 else { return nil }
            return AshSurface(id: id, x: Double(bounds.minX), y: Double(main.frame.maxY - bounds.minY), width: Double(bounds.width))
        }
        let dockEdges = Self.dockRectangles().enumerated().map { index, rect in
            AshSurface(id: UInt32.max - UInt32(index), x: rect.minX, y: rect.maxY, width: rect.width)
        }
        return applicationEdges + dockEdges
    }
    /// Uses the visible-frame inset and the user's Dock footprint as an approximation.
    static func dockRectangles() -> [CGRect] {
        let dockDomain = "com.apple.dock" as CFString
        func preference(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, dockDomain) }
        let apps = (preference("persistent-apps") as? [Any])?.count ?? 6
        let others = (preference("persistent-others") as? [Any])?.count ?? 0
        let showRecents = (preference("show-recents") as? Bool) ?? true
        let recents = showRecents ? ((preference("recent-apps") as? [Any])?.count ?? 0) : 0
        let tile = (preference("tilesize") as? NSNumber)?.doubleValue ?? 48
        let pinning = (preference("pinning") as? String) ?? "middle"
        let count = apps + others + recents + 1
        return NSScreen.screens.compactMap { screen in
            let frame = screen.frame, visible = screen.visibleFrame
            let bottom = visible.minY - frame.minY
            if bottom > 8, let span = DockFootprint.horizontal(screenX: frame.minX, screenWidth: frame.width, tileSize: tile, itemCount: count, pinning: pinning) {
                return CGRect(x: span.x, y: frame.minY, width: span.width, height: bottom)
            }
            let left = visible.minX - frame.minX, right = frame.maxX - visible.maxX
            guard max(left, right) > 8,
                  let span = DockFootprint.horizontal(screenX: frame.minY, screenWidth: frame.height, tileSize: tile, itemCount: count, pinning: pinning) else { return nil }
            return CGRect(x: left > right ? frame.minX : visible.maxX, y: span.x, width: max(left, right), height: span.width)
        }
    }

}

enum AshParticleRenderer {
    static func draw(_ particle: AshParticle, at point: NSPoint) {
        let size = particle.size
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: point.x, yBy: point.y); transform.rotate(byRadians: particle.rotation); transform.concat()
        let path = NSBezierPath()
        let seed = particle.shapeSeed
        if particle.isClump {
            let halfWidth = size * particle.visualWidthScale * 0.48
            let halfHeight = size * 0.31
            path.move(to: NSPoint(x: -halfWidth, y: -halfHeight * 0.65))
            for index in 0...8 {
                let t = Double(index) / 8
                let jag = (Double((seed &+ UInt32(index * 67)) % 13) / 13 - 0.5) * 0.18
                path.line(to: NSPoint(x: -halfWidth + t * halfWidth * 2, y: -halfHeight * (0.92 + jag)))
            }
            path.line(to: NSPoint(x: halfWidth, y: halfHeight * 0.70))
            for index in (0...8).reversed() {
                let t = Double(index) / 8
                let jag = (Double((seed &+ UInt32(index * 97 + 11)) % 17) / 17 - 0.5) * 0.20
                path.line(to: NSPoint(x: -halfWidth + t * halfWidth * 2, y: halfHeight * (0.92 + jag)))
            }
            path.close()
            NSGradient(colors: [NSColor(white: 0.18, alpha: 0.98), NSColor(white: 0.34, alpha: 0.98), NSColor(white: 0.23, alpha: 0.98)])?.draw(in: path, angle: 90)
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            for index in 0..<48 {
                let x = (Double((seed &+ UInt32(index * 37)) % 100) / 100 - 0.5) * halfWidth * 2
                let y = (Double((seed &+ UInt32(index * 53)) % 100) / 100 - 0.5) * halfHeight * 2
                let radius = 0.35 + Double((index * 17) % 9) / 10
                NSColor(white: AshAppearance.shade(seed: seed &+ UInt32(index * 11)), alpha: 0.75).setFill()
                let flake = NSBezierPath(); flake.move(to: NSPoint(x: x - radius, y: y))
                flake.line(to: NSPoint(x: x - radius * 0.2, y: y + radius * 0.65))
                flake.line(to: NSPoint(x: x + radius, y: y + radius * 0.2))
                flake.line(to: NSPoint(x: x + radius * 0.3, y: y - radius * 0.45)); flake.close(); flake.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        } else {
            for vertex in 0..<7 {
                let angle = Double(vertex) * 2 * Double.pi / 7
                let variation = 0.63 + Double((seed &+ UInt32(vertex * 67)) % 31) / 100
                let vertexPoint = NSPoint(x: cos(angle) * size * variation * 0.6,
                                          y: sin(angle) * size * variation * 0.38)
                if vertex == 0 { path.move(to: vertexPoint) } else { path.line(to: vertexPoint) }
            }
            path.close()
            let shade = AshAppearance.shade(seed: seed)
            NSColor(white: shade, alpha: 0.92).setFill(); path.fill()
            NSColor(white: min(shade + 0.12, 0.48), alpha: 0.9).setStroke(); path.lineWidth = 0.45; path.stroke()
            NSColor(white: min(shade + 0.20, 0.54), alpha: 0.50).setFill()
            NSBezierPath(ovalIn: NSRect(x: -size * 0.18, y: 0, width: max(0.5, size * 0.28), height: max(0.4, size * 0.12))).fill()
        }
        if particle.emberRemaining > 0 && particle.isClump {
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            let remaining = min(1, particle.emberRemaining / 10.0)
            for index in 0..<4 {
                let x = (Double((seed &+ UInt32(index * 37)) % 80) / 80 - 0.5) * size * particle.visualWidthScale * 0.72
                let y = (Double((seed &+ UInt32(index * 19)) % 80) / 80 - 0.5) * size * 0.38
                let flicker = 0.55 + 0.45 * sin(CACurrentMediaTime() * (2.0 + Double(index) * 0.3) + Double(index * 2))
                let crack = NSBezierPath(); crack.move(to: NSPoint(x: x - 1.2, y: y - 0.4))
                crack.line(to: NSPoint(x: x - 0.3, y: y + 0.2)); crack.line(to: NSPoint(x: x + 0.4, y: y - 0.2))
                crack.line(to: NSPoint(x: x + 1.3, y: y + 0.35)); crack.lineCapStyle = .round
                NSColor(calibratedRed: 0.8, green: 0.12, blue: 0.015, alpha: remaining * flicker * 0.45).setStroke()
                crack.lineWidth = 1.4; crack.stroke()
                NSColor(calibratedRed: 1, green: 0.28 + 0.25 * flicker, blue: 0.035, alpha: remaining * flicker * 0.95).setStroke()
                crack.lineWidth = 0.55; crack.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
        } else if particle.emberRemaining > 0 {
            let glow = min(1, particle.emberRemaining * 1.4)
            NSColor(calibratedRed: 1, green: 0.25 + 0.25 * glow, blue: 0.025, alpha: glow * 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: -0.6, y: -0.4, width: 1.3, height: 1.0)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class AshView: NSView {
    weak var owner: AshOverlay?
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        // Clear the transparent backing store before drawing the current particles;
        // otherwise old positions can remain as apparent extra ash.
        NSGraphicsContext.current?.cgContext.clear(dirtyRect)
        owner?.render(in: self)
    }
}
