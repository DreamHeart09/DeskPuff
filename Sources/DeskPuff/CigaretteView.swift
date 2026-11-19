import AppKit
import QuartzCore
import DeskPuffCore

final class CigaretteView: NSView {
    var onPuff: ((NSPoint) -> Void)?
    var onTapAsh: (() -> Void)?
    var onInhaleChanged: ((Bool) -> Void)?
    var onDrag: ((NSPoint, NSPoint, NSPoint, NSPoint) -> NSPoint)?
    var onDragFinished: (() -> Void)?
    var onRotate: ((Double, NSPoint, NSPoint) -> Void)?
    var rotationAngle: Double = 0 { didSet { needsDisplay = true } }
    var cigaretteStyle: CigaretteStyle? { didSet { needsDisplay = true } }
    var diameterScale: CGFloat { cigaretteStyle?.diameterScale ?? 1 }
    var isInteracting: Bool { pressed }
    var interactionStart: NSPoint { downScreen }
    var interactionStartTime: CFTimeInterval { downTime }
    var interactionAnchorX: CGFloat { interactionAnchor }
    var impactFoldHingePositions: [CGFloat] { impactBends.map(\.hingeX) }
    private struct ImpactBend {
        var hingeX: CGFloat
        var targetAngle: Double
        var displayedAngle: Double = 0
        var impactCount: Int = 1
    }
    private var damageAnchorX: CGFloat?
    private var impactBends: [ImpactBend] = []
    private let maximumAccumulatedBendAngle = 0.45
    private let maximumImpactMarks = 24
    private var interactionAnchor: CGFloat = 180
    private var targetTipPressure: CGFloat = 0
    private var displayedTipPressure: CGFloat = 0
    private var displayedCompression: CGFloat = 0
    var tipWorldAngle: Double {
        rotationAngle + impactBends.reduce(0) { $0 + (smokeTipX < $1.hingeX ? $1.displayedAngle : 0) }
    }
    private func axialOffset(at x: CGFloat) -> CGFloat {
        guard let anchor = damageAnchorX else { return 0 }
        return CGFloat(CigaretteImpact.axialOffset(position: Double(x), damageAt: Double(anchor), pressure: Double(min(1, displayedCompression + displayedTipPressure * 0.25))))
    }
    private func deformedPoint(_ point: NSPoint) -> NSPoint {
        let shifted = NSPoint(x: point.x + axialOffset(at: point.x), y: point.y)
        var result = shifted
        for bend in impactBends {
            result = CigaretteImpact.foldPoint(result, hingeX: Double(bend.hingeX), angle: bend.displayedAngle)
        }
        return result
    }
    func canvasPoint(_ point: NSPoint) -> NSPoint {
        var point = deformedPoint(point)
        point.y = 19 + (point.y - 19) * diameterScale
        return CigarettePose.canvasPoint(point, angle: rotationAngle)
    }
    func logicalPoint(_ point: NSPoint) -> NSPoint {
        var p = CigarettePose.logicalPoint(point, angle: rotationAngle)
        p.y = 19 + (p.y - 19) / max(0.5, diameterScale)
        var unfolded = p
        for bend in impactBends.reversed() {
            unfolded = CigaretteImpact.unfoldPoint(unfolded, hingeX: Double(bend.hingeX), angle: bend.displayedAngle)
        }
        var x = unfolded.x
        for _ in 0..<5 { x = unfolded.x - axialOffset(at: x) }
        return NSPoint(x: x, y: unfolded.y)
    }
    func applyImpact(at contactX: CGFloat, compression: CGFloat, direction: CGFloat = 1, speed: Double, pressure: Double,
                     obliqueness: Double, gripX: CGFloat) {
        if damageAnchorX == nil { damageAnchorX = contactX }
        let support = min(180, max(contactX + 14, gripX))
        let span = max(18, support - contactX)
        let folds = CigaretteImpact.impactFold(speed: speed, pressure: pressure, obliqueness: obliqueness,
                                               sample: Double.random(in: 0...1), direction: direction < 0 ? -1 : 1)
        let primaryHinge = contactX + span * CGFloat.random(in: 0.34...0.70)
        let primaryAngle = folds.primary == 0 ? (direction < 0 ? -1 : 1) * 0.055 : folds.primary
        addImpactBend(ImpactBend(hingeX: primaryHinge,
                                 targetAngle: primaryAngle))
        if folds.secondary != 0 {
            let secondaryHinge = contactX + span * CGFloat.random(in: 0.18...0.30)
            addImpactBend(ImpactBend(hingeX: secondaryHinge,
                                     targetAngle: folds.secondary))
        }
        tipCompression = max(tipCompression, min(1, max(0, compression)))
    }
    private func addImpactBend(_ candidate: ImpactBend) {
        let nearest = impactBends.indices.min { abs(impactBends[$0].hingeX - candidate.hingeX) < abs(impactBends[$1].hingeX - candidate.hingeX) }
        if let nearest, abs(impactBends[nearest].hingeX - candidate.hingeX) < 8 {
            let old = impactBends[nearest]
            let remainingAngle = max(0, maximumAccumulatedBendAngle - impactBends.enumerated().filter { $0.offset != nearest }.reduce(0) { $0 + abs($1.element.targetAngle) })
            let oldMagnitude = abs(old.targetAngle)
            let growth = oldMagnitude == 0 ? abs(candidate.targetAngle) : max(oldMagnitude, abs(candidate.targetAngle)) + min(0.045, abs(candidate.targetAngle) * 0.18)
            let sign = old.targetAngle == 0 ? (candidate.targetAngle < 0 ? -1.0 : 1.0) : (old.targetAngle < 0 ? -1.0 : 1.0)
            impactBends[nearest].impactCount += 1
            impactBends[nearest].targetAngle = sign * max(oldMagnitude, min(0.42, min(remainingAngle, growth)))
            return
        }
        if impactBends.count >= maximumImpactMarks {
            impactBends.removeFirst()
        }
        let existing = impactBends.reduce(0) { $0 + abs($1.targetAngle) }
        var bend = candidate
        let available = max(0, maximumAccumulatedBendAngle - existing)
        let requested = min(abs(bend.targetAngle), 0.42, available)
        bend.targetAngle = (bend.targetAngle < 0 ? -1 : 1) * requested
        impactBends.append(bend)
    }
    func setTipPressure(_ pressure: CGFloat) { targetTipPressure = min(1, max(0, pressure)) }
    func clearTipDamage() { tipCompression = 0; displayedCompression = 0; damageAnchorX = nil; impactBends.removeAll(); targetTipPressure = 0; displayedTipPressure = 0 }
    func containsCigarette(_ point: NSPoint) -> Bool {
        let p = logicalPoint(point)
        return p.x >= smokeTipX - 6 && p.x <= 182 && abs(p.y - 19) <= 11
    }
    var onExtinguish: (() -> Void)?
    var onAnimationTick: ((Double) -> Void)?
    var burnProgress: Double = 0 {
        didSet {
            if let anchor = damageAnchorX, CigaretteImpact.damageConsumed(tip: Double(smokeTipX), damageAt: Double(anchor)) {
                damageAnchorX = nil; tipCompression = 0; displayedCompression = 0
            }
            impactBends.removeAll { smokeTipX >= $0.hingeX }
            needsDisplay = true
        }
    }
    var ashLevel: Double = 0 { didSet { needsDisplay = true } }
    var finished = false { didSet { needsDisplay = true } }
    var canRecycleButt = false
    var lit = true { didSet { needsDisplay = true } }
    var preheat: CGFloat = 0 { didSet { needsDisplay = true } }
    var tipCompression: CGFloat = 0 { didSet { needsDisplay = true } }
    var filterCompression: CGFloat = 0 { didSet { needsDisplay = true } }
    var inhaleActive = false { didSet { needsDisplay = true } }
    private let ashInset: CGFloat = 20
    var smokeTipX: CGFloat { ashInset + CGFloat(13 + 100 * burnProgress) }
    private struct EmberSpark {
        var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
        var age: Double, lifetime: Double
    }
    private var sparks: [EmberSpark] = []
    private var sparkBudget: Double = 0
    private var lastAnimationTime = CACurrentMediaTime()
    private var hold: Timer?
    private var tappingUntil: CFTimeInterval = 0
    private var animation: Timer?
    private var gesture = FilterGesture()
    private var taps = TapSequence()
    private var doubleTapCandidate = false
    private var downScreen = NSPoint.zero
    private var previousDragScreen = NSPoint.zero
    private var lastDragTimestamp: TimeInterval = 0
    private var downTime: CFTimeInterval = 0
    private var downOrigin = NSPoint.zero
    private var rotationPivot: NSPoint?
    private var rotationAnchor = NSPoint.zero
    private var initialPointerAngle: Double = 0
    private var initialRotation: Double = 0
    private var pressed = false { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }

    func setAnimating(_ enabled: Bool) {
        animation?.invalidate(); animation = nil
        if !enabled { sparks.removeAll(); sparkBudget = 0 }
        if enabled {
            lastAnimationTime = CACurrentMediaTime()
            let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                let now = CACurrentMediaTime(); let elapsed = max(now - self.lastAnimationTime, 0)
                self.lastAnimationTime = now
                self.displayedTipPressure = CGFloat(CigaretteImpact.pressureAfter(current: Double(self.displayedTipPressure), target: Double(self.targetTipPressure), elapsed: elapsed))
                let response = 1 - exp(-min(elapsed, 0.12) * 12)
                self.displayedCompression += (self.tipCompression - self.displayedCompression) * CGFloat(response)
                for index in self.impactBends.indices {
                    self.impactBends[index].displayedAngle += (self.impactBends[index].targetAngle - self.impactBends[index].displayedAngle) * response
                }
                self.onAnimationTick?(elapsed)
                self.updateSparks(elapsed: elapsed); self.needsDisplay = true
            }
            RunLoop.main.add(timer, forMode: .common); animation = timer
        }
    }
    private func updateSparks(elapsed: Double) {
        let dt = min(max(elapsed, 0), 0.12)
        for i in sparks.indices {
            sparks[i].age += dt
            sparks[i].vy -= CGFloat(22 * dt)
            sparks[i].vx *= CGFloat(exp(-1.8 * dt))
            sparks[i].x += sparks[i].vx * CGFloat(dt)
            sparks[i].y += sparks[i].vy * CGFloat(dt)
        }
        sparks.removeAll { $0.age >= $0.lifetime }
        guard !finished && lit else { sparkBudget = 0; return }
        let inhaling = inhaleActive
        sparkBudget += dt * (inhaling ? 9.0 : 1.0)
        if sparkBudget >= 1 && sparks.count < 15 {
            sparkBudget -= 1
            sparks.append(EmberSpark(x: smokeTipX - ashInset + CGFloat.random(in: -2...3), y: CGFloat.random(in: 15...24),
                                    vx: CGFloat.random(in: -7...3), vy: CGFloat.random(in: 5...13),
                                    age: 0, lifetime: Double.random(in: 0.25...0.55)))
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let time = CACurrentMediaTime()
        NSGraphicsContext.saveGraphicsState()
        let pose = NSAffineTransform(); pose.translateX(by: 110, yBy: 110)
        pose.rotate(byRadians: rotationAngle); pose.translateX(by: -95, yBy: -19); pose.concat()
        let insetTransform = NSAffineTransform(); insetTransform.translateX(by: ashInset, yBy: 2.85)
        insetTransform.scaleX(by: 1, yBy: 0.85); insetTransform.concat()
        let diameterTransform = NSAffineTransform(); diameterTransform.translateX(by: 0, yBy: 19)
        diameterTransform.scaleX(by: 1, yBy: diameterScale); diameterTransform.translateX(by: 0, yBy: -19)
        diameterTransform.concat()
        if time < tappingUntil {
            let phase = (tappingUntil - time) / 0.36
            let transform = NSAffineTransform(); transform.translateX(by: 140, yBy: 19)
            transform.rotate(byDegrees: sin(phase * .pi * 4) * phase * 4)
            transform.translateX(by: -140, yBy: -19); transform.concat()
        }
        defer { NSGraphicsContext.restoreGraphicsState() }
        let pulse = 0.5 + 0.5 * sin(time * 2.3) * sin(time * 0.71 + 1.0)
        let tip = smokeTipX - ashInset
        let unburnt = !lit && burnProgress <= 0.001 && ashLevel <= 0.001
        // Smooth per-height variation gives the burn edge an irregular contour
        // that evolves with the consumed paper and flickers gently over time.
        func burnEdge(_ y: CGFloat) -> CGFloat {
            let v = Double((y - 11) / 16)
            let sample = v * 7 + burnProgress * 17
            let cell = floor(sample), fraction = sample - cell
            func noise(_ n: Double) -> Double {
                let raw = sin(n * 127.1 + 31.7) * 43758.5453
                return (raw - floor(raw)) * 2 - 1
            }
            let smooth = fraction * fraction * (3 - 2 * fraction)
            let grain = noise(cell) * (1 - smooth) + noise(cell + 1) * smooth
            let drift = sin(time * 0.24 + v * 8 + burnProgress * 11) * 0.25
            return tip + CGFloat(2.0 + grain * 1.7 + drift)
        }
        let paper = NSBezierPath()
        // Keep the unlit paper's visible end aligned with the short ash cap
        // drawn at ignition. Starting the pristine wrapper at x=0 made the
        // cigarette appear to lose a long white segment as soon as it lit.
        let unlitTip = max(9, tip - 4)
        let bottomStart = unburnt ? unlitTip : burnEdge(11)
        let topStart = unburnt ? unlitTip : burnEdge(27)
        let anchor = damageAnchorX.map { $0 - ashInset }
        func wrinkle(_ x: CGFloat) -> CGFloat {
            guard let anchor else { return 0 }
            let visibleCompression = min(1, tipCompression + displayedTipPressure * 0.3)
            return CGFloat(CigaretteImpact.wrinkleOffset(distance: Double(x - anchor), compression: Double(visibleCompression)))
        }
        func artworkPoint(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            let p = deformedPoint(NSPoint(x: x + ashInset, y: 2.85 + 0.85 * y))
            return NSPoint(x: p.x - ashInset, y: (p.y - 2.85) / 0.85)
        }
        paper.move(to: artworkPoint(bottomStart, 11 + wrinkle(bottomStart)))
        if bottomStart < 154 {
            for x in stride(from: bottomStart + 1, through: 154, by: 1) {
                paper.line(to: artworkPoint(x, 11 + wrinkle(x)))
            }
        }
        paper.line(to: artworkPoint(158, 11))
        paper.curve(to: NSPoint(x: 160 - filterCompression * 0.8, y: 13), controlPoint1: NSPoint(x: 159, y: 11), controlPoint2: NSPoint(x: 160 - filterCompression * 0.8, y: 12))
        paper.line(to: NSPoint(x: 160 - filterCompression * 0.8, y: 25))
        paper.curve(to: NSPoint(x: 158, y: 27), controlPoint1: NSPoint(x: 160 - filterCompression * 0.8, y: 26), controlPoint2: NSPoint(x: 159, y: 27))
        paper.line(to: NSPoint(x: 154, y: 27))
        if topStart < 154 && !unburnt {
            for x in stride(from: CGFloat(153), through: topStart, by: -1) {
                paper.line(to: artworkPoint(x, 27 - wrinkle(x)))
            }
        }
        paper.line(to: artworkPoint(topStart, 27 - wrinkle(topStart)))
        if !unburnt { for y in stride(from: 26, through: 12, by: -1) {
            let x = burnEdge(CGFloat(y))
            paper.line(to: artworkPoint(x, CGFloat(y)))
        } }
        paper.close()
        let paperProfile = cigaretteStyle?.manifest.paper ?? CigarettePaperProfile()
        let filterProfile = cigaretteStyle?.manifest.filter ?? CigaretteFilterProfile()
        let paperBase = cigaretteNSColor(paperProfile.color)
        let paperHighlight = cigaretteNSColor(paperProfile.highlight)
        let paperShade = cigaretteNSColor(paperProfile.shade)
        let filterBase = cigaretteNSColor(filterProfile.color)
        let filterHighlight = cigaretteNSColor(filterProfile.highlight)
        let filterShade = cigaretteNSColor(filterProfile.shade)
        NSGradient(colors: [paperShade, paperBase, paperHighlight, paperBase])?.draw(in: paper, angle: 90)
        if let artwork = cigaretteStyle?.paperArtwork {
            NSGraphicsContext.saveGraphicsState(); paper.addClip()
            let artworkRect = NSRect(x: 0, y: 10, width: 123, height: 18)
            NSBezierPath(rect: artworkRect).addClip()
            artwork.draw(in: artworkRect, from: .zero, operation: .sourceOver, fraction: 1)
            // Legacy artwork is a texture layer. Recolor it with the current
            // numeric paper profile while preserving the texture's luminance.
            NSGraphicsContext.current?.cgContext.saveGState()
            NSGraphicsContext.current?.cgContext.setBlendMode(.color)
            paperBase.withAlphaComponent(0.88).setFill()
            artworkRect.fill()
            NSGraphicsContext.current?.cgContext.restoreGState()
            NSGraphicsContext.restoreGraphicsState()
        }
        // Fine fibres, subtle pores and a helical paper seam give the cylinder
        // texture at Retina scale without changing from frame to frame.
        NSGraphicsContext.saveGraphicsState(); paper.addClip()
        if preheat > 0.001 && !lit {
            let ember = artworkPoint(tip, 19)
            for (radius, opacity) in [(CGFloat(6.5), 0.07), (CGFloat(3.8), 0.13), (CGFloat(1.7), 0.32)] {
                NSColor(calibratedRed: 1, green: 0.19, blue: 0.025,
                        alpha: preheat * opacity).setFill()
                NSBezierPath(ovalIn: NSRect(x: ember.x-radius, y: ember.y-radius,
                                            width: radius*2, height: radius*2)).fill()
            }
            if preheat > 0.55 {
                NSColor(calibratedRed: 0.28, green: 0.11, blue: 0.035,
                        alpha: (preheat - 0.55) * 0.35).setStroke()
                let char = NSBezierPath(); char.move(to: artworkPoint(tip+1, 12)); char.line(to: artworkPoint(tip+1, 26))
                char.lineWidth = 1.1; char.stroke()
            }
        }
        let shadeStart = max(bottomStart, topStart)
        func materialTrack(_ y: CGFloat, color: NSColor, width: CGFloat) {
            guard shadeStart + 1 < 154 else { return }
            let track = NSBezierPath()
            track.move(to: artworkPoint(shadeStart, y))
            for x in stride(from: shadeStart + 2, through: CGFloat(154), by: 2) {
                track.line(to: artworkPoint(x, y))
            }
            color.setStroke(); track.lineWidth = width; track.lineCapStyle = .round; track.stroke()
        }
        // Draw cylinder lighting in material coordinates, then map every sample
        // through the same local folds as the paper silhouette. This keeps the
        // highlight and both edge shadows aligned with each bent section.
        materialTrack(12.2, color: paperShade.withAlphaComponent(0.52), width: 1.2)
        materialTrack(25.8, color: paperShade.withAlphaComponent(0.52), width: 1.2)
        materialTrack(13.8, color: paperShade.withAlphaComponent(0.30), width: 2.0)
        materialTrack(14.0, color: paperShade.withAlphaComponent(0.30), width: 2.2)
        materialTrack(16.2, color: paperShade.withAlphaComponent(0.22), width: 3.0)
        materialTrack(17.8, color: paperHighlight.withAlphaComponent(0.42), width: 3.0)
        materialTrack(24.0, color: paperShade.withAlphaComponent(0.30), width: 2.2)
        materialTrack(22.0, color: paperHighlight.withAlphaComponent(0.40), width: 3.0)
        materialTrack(23.4, color: paperShade.withAlphaComponent(0.20), width: 3.0)
        materialTrack(24.2, color: paperShade.withAlphaComponent(0.30), width: 2.0)
        materialTrack(19.6, color: paperHighlight.withAlphaComponent(0.34), width: 1.0)
        for i in 0..<420 {
            let x = CGFloat(14 + (i * 73 % 146)), y = CGFloat(11 + (i * 41 % 16))
            let shade = CGFloat(0.45 + Double((i * 17) % 35) / 100)
            NSColor(white: shade, alpha: 0.09).setFill()
            let p = artworkPoint(x, y)
            NSBezierPath(ovalIn: NSRect(x: p.x, y: p.y, width: 0.4 + CGFloat(i % 3) * 0.22, height: 0.35)).fill()
        }
        NSColor(white: 0.42, alpha: 0.10).setStroke()
        for x in stride(from: 26, through: 120, by: 25) {
            let seam = NSBezierPath(); seam.move(to: NSPoint(x: x, y: 11)); seam.line(to: NSPoint(x: x + 9, y: 27)); seam.lineWidth = 0.5; seam.stroke()
        }
        if let anchor, tipCompression > 0 {
            // The folds stay attached to the damaged paper as the burn front advances.
            for index in 0..<4 {
                let x = anchor + 2 + CGFloat(index) * 4.2
                let strength = min(1, tipCompression + displayedTipPressure * 0.3) * max(0, 1 - CGFloat(index) * 0.20)
                let offset: CGFloat = 0
                let crease = NSBezierPath(); crease.move(to: artworkPoint(x - 0.8, 12 + offset))
                crease.line(to: artworkPoint(x + 0.8, 15.5 + offset)); crease.line(to: artworkPoint(x - 0.7, 19.2 + offset))
                crease.line(to: artworkPoint(x + 0.9, 22.5 + offset)); crease.line(to: artworkPoint(x + 0.1, 26 + offset))
                NSColor(white: 0.25, alpha: 0.48 * strength).setStroke(); crease.lineWidth = 0.65; crease.stroke()
                NSGraphicsContext.saveGraphicsState()
                let highlight = NSAffineTransform(); highlight.translateX(by: 0.75, yBy: 0); highlight.concat()
                NSColor(white: 1, alpha: 0.40 * strength).setStroke(); crease.lineWidth = 0.55; crease.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        for bend in impactBends {
            let x = bend.hingeX - ashInset
            let strength = min(1, 0.35 + Double(bend.impactCount - 1) * 0.10 + abs(bend.targetAngle) * 0.35)
            let crease = NSBezierPath(); crease.move(to: artworkPoint(x - 0.45, 12.2))
            crease.line(to: artworkPoint(x + 0.35, 16.0)); crease.line(to: artworkPoint(x - 0.25, 19.1))
            crease.line(to: artworkPoint(x + 0.35, 22.2)); crease.line(to: artworkPoint(x, 25.8))
            NSColor(white: 0.24, alpha: 0.36 * strength).setStroke(); crease.lineWidth = 0.65; crease.stroke()
            let highlight = NSBezierPath(); highlight.move(to: artworkPoint(x + 0.85, 12.4))
            highlight.line(to: artworkPoint(x + 0.95, 19.0)); highlight.line(to: artworkPoint(x + 0.6, 25.5))
            NSColor(white: 1, alpha: 0.18 * strength).setStroke(); highlight.lineWidth = 0.55; highlight.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        // Fine, stable fibres follow the paper, rather than shimmering each frame.
        NSColor(white: 0.42, alpha: 0.13).setStroke()
        for i in 0..<48 {
            let x = 19 + (i * 37 % 101), y = 12 + (i * 19 % 13)
            guard CGFloat(x) > tip + 3 else { continue }
            let line = NSBezierPath(); line.move(to: NSPoint(x: x, y: y)); line.line(to: NSPoint(x: min(x + 5, 121), y: y)); line.lineWidth = 0.35; line.stroke()
        }
        NSGraphicsContext.saveGraphicsState(); paper.addClip()
        let filter = NSRect(x: 123, y: 11, width: 37, height: 16)
        NSGradient(colors: [filterShade, filterBase, filterHighlight, filterBase])?.draw(in: filter, angle: 90)
        if let artwork = cigaretteStyle?.filterArtwork {
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: filter).addClip()
            artwork.draw(in: filter, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.current?.cgContext.saveGState()
            NSGraphicsContext.current?.cgContext.setBlendMode(.color)
            filterBase.withAlphaComponent(0.88).setFill()
            filter.fill()
            NSGraphicsContext.current?.cgContext.restoreGState()
            NSGraphicsContext.restoreGraphicsState()
        }
        cigaretteNSColor(filterProfile.band).withAlphaComponent(0.40).setFill()
        NSBezierPath(rect: NSRect(x: 123.2, y: 11.2, width: 1.4, height: 15.6)).fill()
        filterShade.withAlphaComponent(0.35).setFill()
        for i in 0..<55 { let x = 125 + (i * 23 % 32), y = 12 + (i * 17 % 13); NSBezierPath(ovalIn: NSRect(x: CGFloat(x), y: CGFloat(y), width: 0.7, height: 0.7)).fill() }
        if filterCompression > 0 {
            NSColor(calibratedRed: 0.30, green: 0.18, blue: 0.09, alpha: 0.38 * filterCompression).setStroke()
            for index in 0..<3 {
                let x = CGFloat(150 + index * 3)
                let crease = NSBezierPath(); crease.move(to: NSPoint(x: x, y: 12.5))
                crease.line(to: NSPoint(x: x - 0.8, y: 18.5)); crease.line(to: NSPoint(x: x + 0.5, y: 25.5))
                crease.lineWidth = 0.55; crease.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 0.32, alpha: 0.34).setStroke()
        let seam = NSBezierPath(); seam.move(to: NSPoint(x: 122, y: 12)); seam.line(to: NSPoint(x: 122, y: 26)); seam.lineWidth = 0.6; seam.stroke()
        let inhaling = lit && !finished && inhaleActive
        if inhaling {
            NSColor(calibratedRed: 0.94, green: 0.68, blue: 0.35, alpha: 0.32).setStroke()
            for i in 0..<3 {
                let phase = (time * 24 + Double(i) * 13).truncatingRemainder(dividingBy: 35)
                let x = min(CGFloat(phase) + tip + 4, 117)
                let streak = NSBezierPath(); streak.move(to: NSPoint(x: x, y: CGFloat(15 + i * 4))); streak.line(to: NSPoint(x: min(x + 5, 121), y: CGFloat(15 + i * 4))); streak.lineWidth = 0.55; streak.stroke()
            }
        }
        let intensity = (finished || !lit) ? 0.0 : (inhaling ? 1.0 : 0.65 + 0.12 * pulse)
        NSGraphicsContext.saveGraphicsState()
        for bend in impactBends where smokeTipX < bend.hingeX {
            let h = bend.hingeX - ashInset, c = cos(bend.displayedAngle), sn = sin(bend.displayedAngle)
            let fold = CGAffineTransform(a: c, b: sn / 0.85, c: -sn * 0.85, d: c,
                                         tx: h - c * h + sn * 0.85 * 19,
                                         ty: 19 - sn / 0.85 * h - c * 19)
            NSGraphicsContext.current?.cgContext.concatenate(fold)
        }
        if !unburnt {
        let transform = NSAffineTransform(); transform.translateX(by: tip - 13 + axialOffset(at: smokeTipX), yBy: 0); transform.concat()
        let ash = NSBezierPath()
        ash.move(to: NSPoint(x: 9, y: 12))
        ash.line(to: NSPoint(x: burnEdge(11) - tip + 13, y: 11))
        for y in 12...27 { ash.line(to: NSPoint(x: burnEdge(CGFloat(y)) - tip + 13, y: CGFloat(y))) }
        ash.line(to: NSPoint(x: 10, y: 26.4)); ash.close()
        NSGradient(colors: [NSColor(white: 0.17, alpha: 1), NSColor(white: 0.37, alpha: 1), NSColor(white: 0.23, alpha: 1)])?.draw(in: ash, angle: 90)
        NSGraphicsContext.saveGraphicsState(); ash.addClip()
        // Irregular incandescent fissures glow through the cool ash.
        let cracks: [[NSPoint]] = [
            [NSPoint(x: 10, y: 14), NSPoint(x: 12, y: 15), NSPoint(x: 14, y: 14), NSPoint(x: 16, y: 16)],
            [NSPoint(x: 11, y: 20), NSPoint(x: 13, y: 19), NSPoint(x: 15, y: 21), NSPoint(x: 18, y: 20)],
            [NSPoint(x: 12, y: 24), NSPoint(x: 14, y: 23), NSPoint(x: 16, y: 25)]
        ]
        for (index, points) in cracks.enumerated() {
            let flicker = 0.65 + 0.35 * sin(time * (1.7 + Double(index) * 0.37) + Double(index) * 2.1)
            NSColor(calibratedRed: 0.95, green: 0.16 + 0.25 * intensity, blue: 0.025, alpha: intensity * flicker).setStroke()
            let line = NSBezierPath(); line.move(to: points[0]); for point in points.dropFirst() { line.line(to: point) }; line.lineWidth = inhaling ? 1.35 : 0.85; line.lineCapStyle = .round; line.stroke()
        }
        for index in 0..<(inhaling ? 10 : 6) {
            let x = CGFloat(10 + (index * 7 % 9))
            let y = CGFloat(12 + (index * 11 % 15))
            let flicker = 0.65 + 0.35 * sin(time * (2.3 + Double(index % 3)) + Double(index) * 1.7)
            NSColor(calibratedRed: 1, green: 0.32 + 0.26 * intensity, blue: 0.04, alpha: intensity * flicker * 0.8).setFill()
            let width: CGFloat = inhaling ? 1.2 : 0.9
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: width, height: width * 0.7)).fill()
        }
        if let anchor = damageAnchorX, smokeTipX - anchor < 5 {
            let charDamage = tipCompression * max(0, 1 - (smokeTipX - anchor) / 5)
            NSColor(white: 0.08, alpha: 0.65 * charDamage).setStroke()
            for index in 0..<3 {
                let x = CGFloat(11 + index * 2)
                let crease = NSBezierPath(); crease.move(to: NSPoint(x: x, y: 13 + CGFloat(index)))
                crease.line(to: NSPoint(x: x + 0.8, y: 18)); crease.line(to: NSPoint(x: x - 0.5, y: 24 - CGFloat(index)))
                crease.lineWidth = 0.8; crease.stroke()
            }
        }
        NSColor(white: 0.82, alpha: 0.35).setStroke()
        for (x,y) in [(10,17),(14,26),(17,22),(12,12)] {
            let grain = NSBezierPath(); grain.move(to: NSPoint(x: x, y: y)); grain.line(to: NSPoint(x: x + 2, y: y + 1)); grain.lineWidth = 0.55; grain.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        // The cool ash cap stays attached to the charred rim; texture is clipped
        // to one continuous silhouette so it cannot look like floating debris.
        let ashOpacity = min(1.0, max(0.0, ashLevel * 3.0))
        if ashOpacity > 0 {
            let length = CGFloat(AshGeometry.capLength(level: ashLevel))
            let left = 9 - length
            let cap = NSBezierPath()
            cap.move(to: NSPoint(x: left + 0.7, y: 13.5))
            cap.line(to: NSPoint(x: left + length * 0.35, y: 12.4))
            cap.line(to: NSPoint(x: 10.5, y: 11.7)); cap.line(to: NSPoint(x: 12, y: 13))
            cap.line(to: NSPoint(x: 12.5, y: 25)); cap.line(to: NSPoint(x: 10, y: 26))
            cap.line(to: NSPoint(x: left + length * 0.45, y: 25.4))
            cap.line(to: NSPoint(x: left, y: 23.5)); cap.close()
            NSGradient(colors: [NSColor(white: 0.18, alpha: ashOpacity), NSColor(white: 0.34, alpha: ashOpacity), NSColor(white: 0.23, alpha: ashOpacity)])?.draw(in: cap, angle: 90)
            NSGraphicsContext.saveGraphicsState(); cap.addClip()
            for index in 0..<35 {
                let fraction = CGFloat((index * 37) % 97) / 96
                let x = left + fraction * (length + 4)
                let y = 12 + CGFloat((index * 31) % 15)
                let radius = CGFloat(0.35 + Double((index * 17) % 9) / 10)
                let shade = AshAppearance.shade(seed: UInt32(index + 1))
                NSColor(white: shade, alpha: ashOpacity * (0.55 + Double(index % 3) * 0.15)).setFill()
                let flake = NSBezierPath(); flake.move(to: NSPoint(x: x-radius, y: y))
                flake.line(to: NSPoint(x: x-radius*0.2, y: y+radius*0.65)); flake.line(to: NSPoint(x: x+radius, y: y+radius*0.2))
                flake.line(to: NSPoint(x: x+radius*0.3, y: y-radius*0.45)); flake.close(); flake.fill()
            }
            if lit && !finished {
                for index in 0..<5 {
                    let x = left + length * CGFloat((index * 19 % 43) + 8) / 50
                    let y = CGFloat(13 + (index * 7 % 13))
                    let flicker = 0.5 + 0.5 * sin(time * (1.4 + Double(index) * 0.22) + Double(index) * 2.1)
                    NSColor(calibratedRed: 0.95, green: 0.22 + 0.22 * flicker, blue: 0.02, alpha: ashOpacity * flicker * 0.62).setFill()
                    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 0.8, height: 0.55)).fill()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        }
        NSGraphicsContext.restoreGraphicsState()
        for spark in sparks {
            let remaining = max(0, 1 - spark.age / spark.lifetime)
            NSColor(calibratedRed: 1, green: 0.28 + 0.24 * remaining, blue: 0.035, alpha: remaining * 0.95).setFill()
            let p = artworkPoint(spark.x, spark.y)
            NSBezierPath(ovalIn: NSRect(x: p.x, y: p.y, width: 1.2, height: 1.2)).fill()
        }
    }
    override func mouseDown(with event: NSEvent) {
        let point = logicalPoint(convert(event.locationInWindow, from: nil))
        guard point.x >= smokeTipX - 6, point.x <= 182, abs(point.y - 19) <= 11 else { return }
        interactionAnchor = point.x
        rotationPivot = CigarettePose.rotationPivot(forX: point.x, tip: smokeTipX, screenScale: Double(frame.width / 220)).map { NSPoint(x: $0, y: 19) }
        if let pivot = rotationPivot, let window {
            rotationAnchor = window.convertPoint(toScreen: convert(canvasPoint(pivot), to: nil))
            let cursor = NSEvent.mouseLocation
            initialPointerAngle = atan2(cursor.y - rotationAnchor.y, cursor.x - rotationAnchor.x)
            initialRotation = rotationAngle
        }
        doubleTapCandidate = taps.begin(clickCount: event.clickCount, time: event.timestamp, interval: NSEvent.doubleClickInterval)
        downScreen = NSEvent.mouseLocation; previousDragScreen = downScreen
        lastDragTimestamp = event.timestamp; downTime = CACurrentMediaTime(); downOrigin = window?.frame.origin ?? .zero
        gesture.begin(); pressed = true
        guard !finished && lit else { return }
        let timer = Timer(timeInterval: 0.38, repeats: false) { [weak self] _ in
            guard let self, self.gesture.hold() else { return }
            self.taps.reset(); self.needsDisplay = true; self.onInhaleChanged?(true)
        }
        hold = timer; RunLoop.main.add(timer, forMode: .common)
    }
    override func mouseDragged(with event: NSEvent) {
        guard pressed else { return }
        let point = NSEvent.mouseLocation
        let delta = NSPoint(x: point.x-downScreen.x, y: point.y-downScreen.y)
        if gesture.move(distance: hypot(delta.x, delta.y)) {
            hold?.invalidate(); taps.reset()
            let dragElapsed = max(1.0 / 240.0, event.timestamp - lastDragTimestamp)
            let dragDelta = NSPoint(x: point.x - previousDragScreen.x, y: point.y - previousDragScreen.y)
            let dragMotion = NSPoint(x: dragDelta.x / dragElapsed, y: dragDelta.y / dragElapsed)
            previousDragScreen = point
            lastDragTimestamp = event.timestamp
            if let pivot = rotationPivot {
                let pointerAngle = atan2(point.y - rotationAnchor.y, point.x - rotationAnchor.x)
                onRotate?(initialRotation + pointerAngle - initialPointerAngle, pivot, rotationAnchor)
            } else if let correction = onDrag?(downOrigin, delta, dragDelta, dragMotion) {
                downOrigin.x += correction.x; downOrigin.y += correction.y
            }
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard pressed else { return }
        hold?.invalidate(); pressed = false
        switch gesture.end() {
        case .tap:
            if doubleTapCandidate {
                tappingUntil = CACurrentMediaTime() + 0.36; needsDisplay = true; onTapAsh?()
            } else { taps.completedTap(time: event.timestamp) }
        case .dragFinished: onDragFinished?()
        case .puff: onInhaleChanged?(false); onPuff?(downScreen)
        case .none: break
        }
        doubleTapCandidate = false; rotationPivot = nil
    }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        if lit {
            let action = NSMenuItem(title: tr("掐灭香烟"), action: #selector(extinguish), keyEquivalent: "")
            action.isEnabled = !finished; action.target = self; menu.addItem(action)
        } else {
            let title = canRecycleButt ? tr("拖到桌面背包可回收烟头") : tr("请用打火机火焰靠近烟头点火")
            let hint = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            hint.isEnabled = false; menu.addItem(hint)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func extinguish() { onExtinguish?() }
    func cancel() { hold?.invalidate(); if gesture.state == .inhaling { onInhaleChanged?(false) }; gesture.cancel(); taps.reset(); doubleTapCandidate = false; rotationPivot = nil; pressed = false }
}
