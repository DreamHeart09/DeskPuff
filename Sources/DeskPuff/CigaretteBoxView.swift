import AppKit
import DeskPuffCore

enum CigaretteExtractionMode: String, CaseIterable {
    case scaled = "scaled"
    case oneToOne = "oneToOne"

    var title: String {
        switch self {
        case .scaled: return tr("缩放取放（当前模式）")
        case .oneToOne: return tr("一比一直接抽取")
        }
    }
}

/// A hand-drawn 2D hard-pack. The box, lid, foil, and cigarettes share one
/// screen-plane transform; local hit testing uses the inverse transform.
final class CigaretteBoxView: NSView {
    static let canvasSize = 560.0
    static let defaultStock = 20

    var onMove: ((NSPoint, NSPoint) -> NSPoint)?
    var onMoveFinished: (() -> Void)?
    var onRotationChanged: ((Double) -> Void)?
    var onCigaretteScale: ((NSPoint) -> CGFloat)?
    var onInventoryChanged: ((Int, [Int]) -> Void)?
    var onTakeCigarette: ((NSPoint, Double, CGFloat, Bool, Bool) -> Bool)?
    var onExtractionBecameFree: ((NSPoint) -> Void)?
    var onFreeCigaretteDrag: ((NSPoint) -> Void)?
    var onFreeCigaretteDragFinished: (() -> Void)?
    var onStoreInInventory: (() -> Void)?
    var onOpenChanged: ((Bool) -> Void)?
    var onVisualBoundsChanged: (() -> Void)?
    var onInteractionFinished: (() -> Void)?
    var onExtractionModeChanged: ((CigaretteExtractionMode) -> Void)?

    private(set) var remaining = CigaretteBoxView.defaultStock { didSet { needsDisplay = true } }
    private var occupiedSlots = Array(0..<CigaretteBoxView.defaultStock)
    private struct InventoryState: Codable { var remaining: Int; var slots: [Int]; var rotation: Double?; var extractionMode: String? }
    static func inventoryStock(from data: Data?) -> Int {
        guard let data, let state = try? JSONDecoder().decode(InventoryState.self, from: data) else {
            return defaultStock
        }
        return min(defaultStock, max(0, state.remaining))
    }

    static func inventoryState(withStock count: Int, from data: Data?) -> Data? {
        guard (0...defaultStock).contains(count) else { return nil }
        let previous = data.flatMap { try? JSONDecoder().decode(InventoryState.self, from: $0) }
        var used = Set<Int>()
        let slots = ((previous?.slots ?? []) + Array(0..<defaultStock))
            .filter { (0..<defaultStock).contains($0) && used.insert($0).inserted }
        let state = InventoryState(remaining: count, slots: Array(slots.prefix(count)),
                                   rotation: previous?.rotation, extractionMode: previous?.extractionMode)
        return try? JSONEncoder().encode(state)
    }

    var inventoryState: Data? {
        try? JSONEncoder().encode(InventoryState(remaining: remaining, slots: occupiedSlots,
                                                 rotation: rotationAngle, extractionMode: extractionMode.rawValue))
    }

    func inventoryPreviewBounds() -> NSRect {
        bodyRect.union(lidBounds(progress: openProgress)).insetBy(dx: -8, dy: -8)
    }
    func restoreInventoryState(_ data: Data?) {
        guard let data, let state = try? JSONDecoder().decode(InventoryState.self, from: data) else { return }
        setStock(state.remaining, slots: state.slots)
        if let rotation = state.rotation { rotationAngle = rotation }
        if let raw = state.extractionMode, let mode = CigaretteExtractionMode(rawValue: raw) { extractionMode = mode }
    }
    func resetInventoryState() {
        setStock(CigaretteBoxView.defaultStock, slots: Array(0..<CigaretteBoxView.defaultStock))
        let rawMode = UserDefaults.standard.string(forKey: "cigaretteExtractionMode") ?? ""
        rotationAngle = 0
        extractionMode = CigaretteExtractionMode(rawValue: rawMode) ?? .oneToOne
    }
    private(set) var isOpen = false
    private(set) var isInteracting = false
    var rotationAngle = 0.0 { didSet { needsDisplay = true } }
    var style: CigaretteBoxStyle = .default {
        didSet {
            cigaretteArtworkCache.removeAll()
            projectedCGImageCache.removeAll(keepingCapacity: true)
            needsDisplay = true
        }
    }
    var cigaretteStyleResolver: ((CigaretteBoxStyle) -> CigaretteStyle?)?
    var cigaretteScale: CGFloat = 1.35 { didSet { needsDisplay = true } }
    var extractionMode: CigaretteExtractionMode = .oneToOne {
        didSet {
            if extractionMode == .oneToOne { refreshCigaretteScale() }
            needsDisplay = true; onVisualBoundsChanged?(); onExtractionModeChanged?(extractionMode)
        }
    }

    private enum Gesture { case pending, move, rotate, extract }
    private var gesture: Gesture = .pending
    private var downScreen = NSPoint.zero
    private var downOrigin = NSPoint.zero
    private var downLocal = NSPoint.zero
    private var initialAngle = 0.0
    private var initialPointerAngle = 0.0
    private var openProgress = 0.0
    private var targetOpenProgress = 0.0
    private var isLidDebugProgressEnabled = false
    private var animation: Timer?
    private var extractionAnimation: Timer?
    private var insertionAnimation: Timer?
    private struct InsertionMotion {
        let slot: Int
        let startCenter: NSPoint
        let startScale: CGFloat
        let angle: CGFloat
        var progress: CGFloat
    }
    private var insertionMotion: InsertionMotion?
    private var delayedTakeWorkItem: DispatchWorkItem?
    private var selectedSlot: Int?
    private var draggedCenter: NSPoint?
    private var poppedSlot: Int?
    private var pendingShakenSlot: Int?
    private var lastShakeX: CGFloat = 0
    private var shakeDirection = 0
    private var shakeReversals = 0
    private var pullProgress = 0.0
    private var isPulling = false
    private var hasClearedMouth = false
    private var extractionLit = false
    private var forwardingExtraction = false
    private var delayedTake = false
    private var dragStartScreen: NSPoint = .zero
    private var dragStartCenter: NSPoint = .zero
    private var dragTopOffset: CGFloat = 0
    private var dragStartScale: CGFloat = 1
    private var activeExtractionScale: CGFloat = 1.35
    private let center = NSPoint(x: 280, y: 280)
    private let cigaretteModelDiameter: CGFloat = 16 * 0.85
    private var cigaretteDiameterScale: CGFloat { cigaretteStyleResolver?(style)?.diameterScale ?? 1 }
    private var effectiveCigaretteDiameterScale: CGFloat {
        style.geometry.cigaretteDiameterMM.map { CGFloat($0 / 7.8) } ?? cigaretteDiameterScale
    }
    private var cigaretteArtworkCache: [String: NSImage] = [:]
    private var projectedCGImageCache: [ObjectIdentifier: CGImage] = [:]
    private static var paperTextureCache: [String: NSImage] = [:]
    private static let sharedLinerArtwork: NSImage? = {
        guard let root = Bundle.module.resourceURL else { return nil }
        let url = root.appendingPathComponent("Resources/StylePackages/cigarette-boxes/zhonghua-classic/artwork/body-photo-v1.png")
        return NSImage(contentsOf: url)
    }()
    private var packedCigaretteScale: CGFloat { extractionMode == .oneToOne ? cigaretteScale : 1 }
    private var isSlimHardPack: Bool { style.geometry.isSlimHard }
    private var isGenericTwoRowPack: Bool { style.geometry.isTwoRow && !style.geometry.isSlimHard }
    private var hasExteriorArtwork: Bool {
        style.frontArtwork != nil || style.bodyArtwork != nil || style.scaledBodyArtwork != nil
            || style.lidOutsideArtwork != nil || style.lidOutsideOpenArtwork != nil
    }
    private var bodyRect: NSRect {
        if isSlimHardPack {
            // Slim hard packs use the face ratio stored in their reusable
            // geometry profile; the number of cigarettes across comes from
            // the configured row arrangement.
            let columns = CGFloat(style.geometry.rowCounts.max() ?? 10)
            let width = columns * cigaretteModelDiameter * effectiveCigaretteDiameterScale * packedCigaretteScale + 14
            let height = width / (style.geometry.frontAspectRatio ?? (54.5 / 99))
            return NSRect(x: center.x - width / 2, y: 158, width: width, height: height)
        }
        if isGenericTwoRowPack {
            // Ten full-width cigarettes per row; grow the pack, never squeeze them.
            let width = 10 * cigaretteModelDiameter * effectiveCigaretteDiameterScale * packedCigaretteScale + 14
            let height = max(224, 160 * packedCigaretteScale + 12)
            return NSRect(x: center.x - width / 2, y: 158, width: width, height: height)
        }
        let height = 224.0
        let standardWidth = height * (style.geometry.frontAspectRatio ?? (55.0 / 86.0))
        let sevenCigaretteWidth = 7 * cigaretteModelDiameter * effectiveCigaretteDiameterScale * packedCigaretteScale + 14
        let width = extractionMode == .oneToOne ? max(standardWidth, sevenCigaretteWidth) : standardWidth
        return NSRect(x: center.x - width / 2, y: 158, width: width, height: height)
    }
    private var contentsRect: NSRect {
        let depth = bodyRect.height * 22.0 / 86.0
        let notchDepth = mouthNotchDepth
        // Preserve the original cavity's lower edge (also used by generic
        // style liners) while extending its upper bounds for packed tips.
        return NSRect(x: bodyRect.minX + 7, y: bodyRect.maxY - 5 - notchDepth,
                      width: bodyRect.width - 14, height: depth * 2 + 5 + notchDepth)
    }

    /// Fixed seated position for every packed stick. Tips sit just inside the
    /// carton rim; the space above them is exposed by the lid as it opens.
    private var packedCigaretteAnchorY: CGFloat {
        let diameter = cigaretteModelDiameter * effectiveCigaretteDiameterScale * packedCigaretteScale
        return bodyRect.maxY + diameter / 2 - 2
    }

    func setLidDebugProgress(_ progress: Double?) {
        animation?.invalidate(); animation = nil
        guard let progress else {
            isLidDebugProgressEnabled = false
            targetOpenProgress = isOpen ? 1 : 0
            startAnimation()
            return
        }
        isLidDebugProgressEnabled = true
        openProgress = min(1, max(0, progress))
        targetOpenProgress = openProgress
        isOpen = openProgress >= 0.5
        needsDisplay = true
        onVisualBoundsChanged?()
    }

    // The finger cutout is part of the carton shell, so its geometry stays
    // fixed while the lid moves. The lid itself covers it when closed.
    private var mouthNotchDepth: CGFloat {
        min(isSlimHardPack ? 26 : 34, bodyRect.height * (isSlimHardPack ? 0.11 : 0.15))
    }

    private func frontPath() -> NSBezierPath {
        let rect = bodyRect
        let depth = mouthNotchDepth
        guard depth > 0.01 else { return NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3) }
        let halfWidth = min(rect.width * (isSlimHardPack ? 0.29 : 0.36), isSlimHardPack ? 48 : 58)
        let corner = min(isSlimHardPack ? 3 : 8, depth * 0.45)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY - 3))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + 3))
        path.curve(to: NSPoint(x: rect.minX + 3, y: rect.minY), controlPoint1: NSPoint(x: rect.minX, y: rect.minY), controlPoint2: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - 3, y: rect.minY))
        path.curve(to: NSPoint(x: rect.maxX, y: rect.minY + 3), controlPoint1: NSPoint(x: rect.maxX, y: rect.minY), controlPoint2: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - 3))
        path.curve(to: NSPoint(x: rect.maxX - 3, y: rect.maxY), controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY), controlPoint2: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: center.x + halfWidth, y: rect.maxY))
        path.line(to: NSPoint(x: center.x + halfWidth, y: rect.maxY - depth + corner))
        path.curve(to: NSPoint(x: center.x + halfWidth - corner, y: rect.maxY - depth),
                   controlPoint1: NSPoint(x: center.x + halfWidth, y: rect.maxY - depth),
                   controlPoint2: NSPoint(x: center.x + halfWidth, y: rect.maxY - depth))
        path.line(to: NSPoint(x: center.x - halfWidth + corner, y: rect.maxY - depth))
        path.curve(to: NSPoint(x: center.x - halfWidth, y: rect.maxY - depth + corner),
                   controlPoint1: NSPoint(x: center.x - halfWidth, y: rect.maxY - depth),
                   controlPoint2: NSPoint(x: center.x - halfWidth, y: rect.maxY - depth))
        path.line(to: NSPoint(x: center.x - halfWidth, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + 3, y: rect.maxY))
        path.curve(to: NSPoint(x: rect.minX, y: rect.maxY - 3), controlPoint1: NSPoint(x: rect.minX, y: rect.maxY), controlPoint2: NSPoint(x: rect.minX, y: rect.maxY))
        path.close()
        return path
    }

    private func cigaretteArtwork(for style: CigaretteStyle?, lit: Bool) -> NSImage? {
        let key = style.map { "\($0.id)|\($0.manifest.diameterMM)|\($0.manifest.paper.color)|\($0.manifest.paper.highlight)|\($0.manifest.filter.color)|\($0.manifest.filter.band)" } ?? "standard"
        let cacheKey = key + (lit ? "|lit" : "|unlit")
        if let cached = cigaretteArtworkCache[cacheKey] { return cached }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 440, pixelsHigh: 440,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        let model = CigaretteView(frame: NSRect(x: 0, y: 0, width: 220, height: 220))
        model.cigaretteStyle = style
        model.lit = lit; model.burnProgress = 0; model.ashLevel = 0; model.finished = !lit
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        model.draw(model.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 220, height: 220))
        image.addRepresentation(bitmap)
        cigaretteArtworkCache[cacheKey] = image
        return image
    }

    override var isOpaque: Bool { false }

    func setStock(_ value: Int, slots: [Int]? = nil) {
        let count = min(Self.defaultStock, max(0, value))
        let restored = slots?.filter { (0..<Self.defaultStock).contains($0) }
        let restoredSlots = restored ?? []
        occupiedSlots = (restoredSlots.isEmpty && count > 0 ? Array(0..<count) : Array(restoredSlots.prefix(count))).sorted()
        remaining = occupiedSlots.count
        needsDisplay = true
    }

    func containsBox(_ point: NSPoint) -> Bool {
        let local = unrotated(point)
        return bodyRect.insetBy(dx: -18, dy: -16).contains(local) ||
            (openProgress > Self.normalizedProgress(forLegacyProgress: 0.12) &&
             lidBounds(progress: openProgress).contains(local)) ||
            (poppedSlot != nil && poppedFilterBounds.contains(local))
    }

    func visibleArtworkBounds() -> NSRect {
        var artwork = bodyRect
        if openProgress > Self.normalizedProgress(forLegacyProgress: 0.02) {
            artwork = artwork.union(lidBounds(progress: openProgress))
        }
        if poppedSlot != nil { artwork = artwork.union(extractedBounds(at: poppedCigaretteCenter, scale: poppedCigaretteScale)) }
        if let draggedCenter, isPulling { artwork = artwork.union(extractedBounds(at: draggedCenter, scale: activeExtractionScale)) }
        let points = [NSPoint(x: artwork.minX, y: artwork.minY), NSPoint(x: artwork.minX, y: artwork.maxY),
                      NSPoint(x: artwork.maxX, y: artwork.minY), NSPoint(x: artwork.maxX, y: artwork.maxY)].map(rotated)
        let minX = points.map(\.x).min() ?? artwork.minX
        let maxX = points.map(\.x).max() ?? artwork.maxX
        let minY = points.map(\.y).min() ?? artwork.minY
        let maxY = points.map(\.y).max() ?? artwork.maxY
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -2, dy: -2)
    }

    func ashSurfaces() -> [AshSurface] {
        guard let window, window.isVisible else { return [] }
        let windowID = UInt32(truncatingIfNeeded: window.windowNumber) & 0x000fffff
        let baseID: UInt32 = 0x60000000 | (windowID << 5)
        func edge(from localStart: NSPoint, to localEnd: NSPoint, id: UInt32) -> [AshSurface] {
            let start = screenPoint(for: localStart), end = screenPoint(for: localEnd)
            return CigaretteAshSurface.segments(from: start, to: end, idBase: id, count: 24)
        }
        var surfaces = edge(from: NSPoint(x: bodyRect.minX, y: bodyRect.maxY),
                            to: NSPoint(x: bodyRect.maxX, y: bodyRect.maxY), id: baseID)
        if openProgress > Self.normalizedProgress(forLegacyProgress: 0.08) {
            let lid = lidPoints(progress: CGFloat(openProgress))
            surfaces += edge(from: lid[2], to: lid[3], id: baseID &+ 24)
        }
        return surfaces
    }

    func refreshCigaretteArtwork() {
        cigaretteArtworkCache.removeAll()
        needsDisplay = true
    }

    func refreshCigaretteScale() {
        guard extractionMode == .oneToOne else { return }
        cigaretteScale = onCigaretteScale?(screenPoint(for: center)) ?? cigaretteScale
    }

    private var poppedCigaretteCenter: NSPoint {
        let slotX = poppedSlot.map { slotCenter($0).x } ?? center.x
        // The filter barely clears the rim; the cigarette stays anchored to
        // the selected slot instead of jumping to the middle of the pack.
        return NSPoint(x: slotX, y: bodyRect.maxY - 62 * packedCigaretteScale)
    }
    private var poppedCigaretteScale: CGFloat { packedCigaretteScale }
    private var poppedFilterBounds: NSRect {
        let scale = poppedCigaretteScale
        let length = 160 * scale, diameter = cigaretteModelDiameter * effectiveCigaretteDiameterScale * scale, filterHeight = 36 * scale
        return NSRect(x: poppedCigaretteCenter.x - diameter / 2 - 5,
                      y: poppedCigaretteCenter.y + length / 2 - filterHeight - 5,
                      width: diameter + 10, height: filterHeight + 10)
    }
    private func extractedBounds(at point: NSPoint, scale: CGFloat? = nil) -> NSRect {
        let scale = scale ?? cigaretteScale
        let length = 160 * scale, diameter = cigaretteModelDiameter * effectiveCigaretteDiameterScale * scale
        return NSRect(x: point.x - diameter / 2, y: point.y - length / 2,
                      width: diameter, height: length)
    }

    func openAndTakeNext() {
        guard remaining > 0, !delayedTake else { return }
        if !isOpen {
            setOpen(true)
            delayedTake = true
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.delayedTakeWorkItem = nil
                guard self.delayedTake else { return }
                self.delayedTake = false
                self.takeFromMenu()
            }
            delayedTakeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: work)
        } else {
            takeFromMenu()
        }
    }

    func shakeOutOne() {
        guard remaining > 0, !delayedTake, poppedSlot == nil,
              pendingShakenSlot == nil, let selected = occupiedSlots.randomElement() else { return }
        pendingShakenSlot = selected
        setOpen(true)
        showPendingShakenCigarette()
    }

    func cancelPendingExtraction() {
        delayedTakeWorkItem?.cancel(); delayedTakeWorkItem = nil
        extractionAnimation?.invalidate(); extractionAnimation = nil
        insertionAnimation?.invalidate(); insertionAnimation = nil; insertionMotion = nil
        delayedTake = false; isPulling = false; selectedSlot = nil
        draggedCenter = nil; poppedSlot = nil; pullProgress = 0
        restoreCanvasSize()
        needsDisplay = true
    }

    func insertCigarette(at screenPoint: NSPoint, angle: Double, scale: CGFloat) -> Bool {
        guard isOpen,
              openProgress >= Self.normalizedProgress(forLegacyProgress: 0.70),
              remaining < Self.defaultStock, let window else { return false }
        let inWindow = window.convertPoint(fromScreen: screenPoint)
        let local = unrotated(convert(inWindow, from: nil))
        let difference = atan2(sin(angle - rotationAngle - .pi / 2), cos(angle - rotationAngle - .pi / 2))
        guard abs(difference) < 0.45 else { return false }
        let cigaretteAxis = NSPoint(x: sin(difference), y: cos(difference))
        let modelCenter = NSPoint(x: local.x - cigaretteAxis.x * 15 * scale,
                                  y: local.y - cigaretteAxis.y * 15 * scale)
        guard cigaretteOverlapFraction(center: modelCenter, scale: scale, angle: CGFloat(difference), box: bodyRect) >= 0.5 else { return false }
        let vacant = (0..<Self.defaultStock).filter { !occupiedSlots.contains($0) }
        guard let backRow = vacant.map(rowIndex).max() else { return false }
        guard let slot = vacant.filter({ rowIndex($0) == backRow }).min(by: {
            let firstCenter = NSPoint(x: slotCenter($0).x, y: slotCenter($0).y - 80 * packedCigaretteScale)
            let secondCenter = NSPoint(x: slotCenter($1).x, y: slotCenter($1).y - 80 * packedCigaretteScale)
            return hypot(firstCenter.x - modelCenter.x, firstCenter.y - modelCenter.y) <
                hypot(secondCenter.x - modelCenter.x, secondCenter.y - modelCenter.y)
        }) else { return false }
        occupiedSlots.append(slot)
        occupiedSlots.sort()
        remaining = occupiedSlots.count
        poppedSlot = nil
        insertionMotion = InsertionMotion(slot: slot, startCenter: modelCenter, startScale: scale,
                                          angle: CGFloat(difference), progress: 0)
        insertionAnimation?.invalidate()
        let startedAt = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, let motion = self.insertionMotion else { timer.invalidate(); return }
            let progress = min(1, (CACurrentMediaTime() - startedAt) / 0.22)
            self.insertionMotion = InsertionMotion(slot: motion.slot, startCenter: motion.startCenter,
                                                   startScale: motion.startScale, angle: motion.angle,
                                                   progress: CGFloat(progress))
            self.needsDisplay = true
            if progress >= 1 { timer.invalidate(); self.insertionAnimation = nil; self.insertionMotion = nil }
        }
        RunLoop.main.add(timer, forMode: .common); insertionAnimation = timer
        onInventoryChanged?(remaining, occupiedSlots)
        needsDisplay = true
        return true
    }

    private func animateCigaretteBackToSlot(slot: Int, from startCenter: NSPoint, scale: CGFloat) {
        insertionAnimation?.invalidate()
        insertionMotion = InsertionMotion(slot: slot, startCenter: startCenter,
                                          startScale: scale, angle: 0, progress: 0)
        let startedAt = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, self.insertionMotion != nil else { timer.invalidate(); return }
            let progress = min(1, (CACurrentMediaTime() - startedAt) / 0.20)
            self.insertionMotion = InsertionMotion(slot: slot, startCenter: startCenter,
                                                   startScale: scale, angle: 0, progress: CGFloat(progress))
            self.needsDisplay = true
            if progress >= 1 {
                timer.invalidate()
                self.insertionAnimation = nil
                self.insertionMotion = nil
                self.restoreCanvasSize()
                self.needsDisplay = true
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        insertionAnimation = timer
    }

    private func cigaretteOverlapFraction(center: NSPoint, scale: CGFloat, angle: CGFloat, box: NSRect) -> CGFloat {
        let halfLength = 80 * scale, halfWidth = cigaretteModelDiameter * effectiveCigaretteDiameterScale * scale / 2
        let axis = NSPoint(x: sin(angle), y: cos(angle))
        let cross = NSPoint(x: cos(angle), y: -sin(angle))
        var polygon = [
            NSPoint(x: center.x - axis.x * halfLength - cross.x * halfWidth, y: center.y - axis.y * halfLength - cross.y * halfWidth),
            NSPoint(x: center.x + axis.x * halfLength - cross.x * halfWidth, y: center.y + axis.y * halfLength - cross.y * halfWidth),
            NSPoint(x: center.x + axis.x * halfLength + cross.x * halfWidth, y: center.y + axis.y * halfLength + cross.y * halfWidth),
            NSPoint(x: center.x - axis.x * halfLength + cross.x * halfWidth, y: center.y - axis.y * halfLength + cross.y * halfWidth)
        ]
        enum Edge { case minX, maxX, minY, maxY }
        func clip(_ input: [NSPoint], edge: Edge) -> [NSPoint] {
            guard !input.isEmpty else { return [] }
            func inside(_ point: NSPoint) -> Bool {
                switch edge {
                case .minX: return point.x >= box.minX
                case .maxX: return point.x <= box.maxX
                case .minY: return point.y >= box.minY
                case .maxY: return point.y <= box.maxY
                }
            }
            func intersection(_ start: NSPoint, _ end: NSPoint) -> NSPoint {
                switch edge {
                case .minX, .maxX:
                    let x = edge == .minX ? box.minX : box.maxX
                    let t = (x - start.x) / (end.x - start.x)
                    return NSPoint(x: x, y: start.y + (end.y - start.y) * t)
                case .minY, .maxY:
                    let y = edge == .minY ? box.minY : box.maxY
                    let t = (y - start.y) / (end.y - start.y)
                    return NSPoint(x: start.x + (end.x - start.x) * t, y: y)
                }
            }
            var output: [NSPoint] = []
            var previous = input[input.count - 1]
            for current in input {
                let previousInside = inside(previous), currentInside = inside(current)
                if currentInside {
                    if !previousInside { output.append(intersection(previous, current)) }
                    output.append(current)
                } else if previousInside {
                    output.append(intersection(previous, current))
                }
                previous = current
            }
            return output
        }
        for edge in [Edge.minX, .maxX, .minY, .maxY] { polygon = clip(polygon, edge: edge) }
        guard polygon.count >= 3 else { return 0 }
        var twiceArea: CGFloat = 0
        for index in polygon.indices {
            let next = polygon[(index + 1) % polygon.count]
            twiceArea += polygon[index].x * next.y - next.x * polygon[index].y
        }
        return abs(twiceArea) / (2 * halfLength * 2 * halfWidth)
    }

    private func setOpen(_ value: Bool) {
        guard isOpen != value else { return }
        if !value {
            pendingShakenSlot = nil
            poppedSlot = nil
            insertionAnimation?.invalidate(); insertionAnimation = nil; insertionMotion = nil
        }
        isOpen = value
        targetOpenProgress = value ? 1 : 0
        onOpenChanged?(value)
        startAnimation()
    }

    private func showPendingShakenCigarette() {
        guard isOpen, openProgress >= 1, let slot = pendingShakenSlot else { return }
        pendingShakenSlot = nil
        guard occupiedSlots.contains(slot), poppedSlot == nil else { return }
        poppedSlot = slot
        activeExtractionScale = packedCigaretteScale
        cigaretteScale = onCigaretteScale?(screenPoint(for: poppedCigaretteCenter)) ?? cigaretteScale
        needsDisplay = true
    }

    private func startAnimation() {
        guard animation == nil, !isLidDebugProgressEnabled else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let difference = self.targetOpenProgress - self.openProgress
            self.openProgress += difference * 0.22
            if abs(difference) < 0.003 {
                self.openProgress = self.targetOpenProgress
                self.animation?.invalidate(); self.animation = nil
                self.showPendingShakenCigarette()
            }
            self.needsDisplay = true
            self.onVisualBoundsChanged?()
        }
        RunLoop.main.add(timer, forMode: .common)
        animation = timer
    }

    private func unrotated(_ point: NSPoint) -> NSPoint {
        let dx = point.x - center.x, dy = point.y - center.y
        let c = CGFloat(cos(rotationAngle)), s = CGFloat(sin(rotationAngle))
        return NSPoint(x: center.x + dx * c + dy * s,
                       y: center.y - dx * s + dy * c)
    }

    private func rotated(_ point: NSPoint) -> NSPoint {
        let dx = point.x - center.x, dy = point.y - center.y
        let c = CGFloat(cos(rotationAngle)), s = CGFloat(sin(rotationAngle))
        return NSPoint(x: center.x + dx * c - dy * s,
                       y: center.y + dx * s + dy * c)
    }

    private func screenPoint(for local: NSPoint) -> NSPoint {
        guard let window else { return rotated(local) }
        return window.convertPoint(toScreen: convert(rotated(local), to: nil))
    }

    private func extendCanvasAbove(_ point: NSPoint, scale: CGFloat) {
        guard let window else { return }
        // `point` is the pull anchor, while drawing places the cigarette model
        // another 80pt above it and the model itself extends 80pt further.
        // Reserve the full silhouette so its tip is not clipped mid-drag.
        let inset = 165 * scale + 24
        let corners = [NSPoint(x: point.x - inset, y: point.y - inset),
                       NSPoint(x: point.x + inset, y: point.y - inset),
                       NSPoint(x: point.x - inset, y: point.y + inset),
                       NSPoint(x: point.x + inset, y: point.y + inset)].map(rotated)
        let minX = min(bounds.minX, floor(corners.map(\.x).min() ?? 0))
        let minY = min(bounds.minY, floor(corners.map(\.y).min() ?? 0))
        let maxX = max(bounds.maxX, ceil(corners.map(\.x).max() ?? 0))
        let maxY = max(bounds.maxY, ceil(corners.map(\.y).max() ?? 0))
        guard minX < bounds.minX || minY < bounds.minY || maxX > bounds.maxX || maxY > bounds.maxY else { return }
        let frame = window.frame
        let newBounds = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        window.setFrame(NSRect(x: frame.minX + minX - bounds.minX, y: frame.minY + minY - bounds.minY,
                               width: newBounds.width, height: newBounds.height), display: true)
        setFrameSize(newBounds.size)
        setBoundsOrigin(newBounds.origin)
        setBoundsSize(newBounds.size)
    }

    private func restoreCanvasSize() {
        guard let window, bounds != NSRect(x: 0, y: 0, width: Self.canvasSize, height: Self.canvasSize) else { return }
        let frame = window.frame
        let size = NSSize(width: Self.canvasSize, height: Self.canvasSize)
        window.setFrame(NSRect(x: frame.minX - bounds.minX, y: frame.minY - bounds.minY,
                               width: size.width, height: size.height), display: true)
        setFrameSize(size)
        setBoundsOrigin(.zero)
        setBoundsSize(size)
    }

    private func slotCenter(_ index: Int) -> NSPoint {
        let row: Int
        let column: Int
        let count: Int
        (row, column, count) = rowPosition(for: index)
        let diameter = cigaretteModelDiameter * effectiveCigaretteDiameterScale * packedCigaretteScale
        let sideMargin = (contentsRect.width - CGFloat(count) * diameter) / 2
        // Centering the six-wide middle row naturally offsets it by half a
        // cigarette diameter, nesting each stick between the outer rows.
        let x = contentsRect.minX + sideMargin + diameter / 2 + CGFloat(column) * diameter
        // Rows share the same seated height; depth only controls drawing order.
        let y = packedCigaretteAnchorY - diameter / 2 - 2
        _ = row
        return NSPoint(x: x, y: y)
    }

    private func hitSlot(_ point: NSPoint) -> Int? {
        guard openProgress > Self.normalizedProgress(forLegacyProgress: 0.52),
              !occupiedSlots.isEmpty, contentsRect.contains(point) else { return nil }
        return occupiedSlots.min {
            let first = slotCenter($0), second = slotCenter($1)
            let firstDistance = hypot(first.x - point.x, first.y - point.y)
            let secondDistance = hypot(second.x - point.x, second.y - point.y)
            return firstDistance == secondDistance ? $0 < $1 : firstDistance < secondDistance
        }
    }

    private func lidBounds(progress: Double) -> NSRect {
        let points = lidShellGeometry(progress: CGFloat(progress)).allPoints
        let minX = (points.map(\.x).min() ?? bodyRect.minX) - 5
        let maxX = (points.map(\.x).max() ?? bodyRect.maxX) + 5
        let minY = (points.map(\.y).min() ?? bodyRect.maxY) - 5
        let maxY = (points.map(\.y).max() ?? bodyRect.maxY) + 5
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func drawGradient(_ colors: [NSColor], in rect: NSRect, angle: CGFloat = 90) {
        NSGradient(colors: colors)?.draw(in: rect, angle: angle)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byRadians: rotationAngle)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()

        if openProgress <= Self.normalizedProgress(forLegacyProgress: 0.02) {
            drawBoxBody()
            drawLid(progress: openProgress)
        } else {
            let lidIsBehindThePack = flipAngle(progress: CGFloat(openProgress)) >= .pi / 2
            if lidIsBehindThePack { drawLid(progress: openProgress) }
            if Self.sharedLinerArtwork == nil { drawOpenInterior() }
            drawBoxBody()
            drawPackedCigarettes()
            if !lidIsBehindThePack { drawLid(progress: openProgress) }
        }
        if let draggedCenter, isPulling, pullProgress > 0.001 {
            drawExtractedCigarette(at: draggedCenter, progress: pullProgress)
        } else if poppedSlot != nil {
            drawExtractedCigarette(at: poppedCigaretteCenter, progress: 1, insideBox: true)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBoxBody() {
        let front = frontPath()
        let bodyArtwork = extractionMode == .scaled
            ? (style.scaledBodyArtwork ?? style.bodyArtwork ?? style.frontArtwork)
            : (style.bodyArtwork ?? style.frontArtwork)
        // Photo artwork already contains its printed edge and paper folds.
        // Synthetic side panels and strokes would add a second colored frame.
        if !hasExteriorArtwork { drawBodySidePanels() }
        NSGraphicsContext.saveGraphicsState()
        front.addClip()
        if style.frontArtwork != nil,
           openProgress > Self.normalizedProgress(forLegacyProgress: 0.02) {
            // Only a single combined front image needs a backing layer after
            // its moving lid band is clipped away. Separate photo layers must
            // keep their transparent edges clear, or this palette fill leaks
            // out as a colored rectangle as soon as the lid starts to move.
            drawGradient(style.body, in: bodyRect, angle: 0)
        }
        if let artwork = bodyArtwork {
            if style.frontArtwork != nil,
               openProgress > Self.normalizedProgress(forLegacyProgress: 0.02) {
                // A single closed-front texture contains both the lid print
                // and the body print. Once open, keep the lid's print on the
                // moving flap and reveal the shared unprinted paperboard
                // shoulder beneath it instead of duplicating the lid artwork.
                let lidBand = bodyRect.height * style.geometry.lidBandFraction
                let bodyPrint = NSRect(x: bodyRect.minX, y: bodyRect.minY,
                                       width: bodyRect.width, height: bodyRect.height - lidBand)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: bodyPrint).addClip()
                artwork.draw(in: bodyRect, from: artworkSourceRect(for: artwork), operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                artwork.draw(in: bodyRect, from: artworkSourceRect(for: artwork), operation: .sourceOver, fraction: 1)
            }
        } else {
            drawGradient(style.body, in: bodyRect, angle: 0)
            drawGoldText(style.brand, at: NSPoint(x: center.x, y: 245), size: 26)
            drawGoldText(style.subtitle, at: NSPoint(x: center.x, y: 220), size: 7)
        }
        if !hasExteriorArtwork {
            drawPaperGrain(in: bodyRect)
            drawPrintedFinish(in: bodyRect)
        }
        // Folded paperboard reads through compressed seams and fine foil
        // registration, not through a large bevel or a floating card shadow.
        if !hasExteriorArtwork {
            let fold = NSBezierPath(); fold.move(to: NSPoint(x: bodyRect.minX + 1, y: bodyRect.maxY - 1))
            fold.line(to: NSPoint(x: bodyRect.maxX - 1, y: bodyRect.maxY - 1))
            style.fold.setStroke(); fold.lineWidth = 0.7; fold.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        if openProgress > Self.normalizedProgress(forLegacyProgress: 0.02),
           let artwork = Self.sharedLinerArtwork {
            // One shared photo supplies the foil and folded paper collar for
            // every hard-pack exterior, so package authors only provide outer art.
            let halfWidth = min(bodyRect.width * 0.36, 58)
            let notch = NSRect(x: center.x - halfWidth, y: bodyRect.maxY - mouthNotchDepth,
                               width: halfWidth * 2, height: mouthNotchDepth)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: notch).addClip()
            let source = Self.zhonghuaPhotoContentRect(for: artwork)
            artwork.draw(in: bodyRect, from: source, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        drawNotchCutEdges()
        if !hasExteriorArtwork {
            style.edge.withAlphaComponent(0.72).setStroke()
            front.lineWidth = 0.8; front.stroke()
        }
    }

    private func artworkSourceRect(for artwork: NSImage) -> NSRect {
        guard style.id == "user:zhonghua-classic" else { return NSRect(origin: .zero, size: artwork.size) }
        return Self.zhonghuaPhotoContentRect(for: artwork)
    }

    private static func zhonghuaPhotoContentRect(for artwork: NSImage) -> NSRect {
        // These source bounds exclude the low-alpha red extraction fringe and
        // align the photographed carton edges with the shared shell. The body
        // and lid photos have different, asymmetric transparent margins.
        let size = artwork.size
        if abs(size.width - 749) < 1, abs(size.height - 1200) < 1 {
            return NSRect(x: 9, y: 11, width: 715, height: 1179)
        }
        if abs(size.width - 1730) < 1, abs(size.height - 728) < 1 {
            return NSRect(x: 12, y: 58, width: 1699, height: 656)
        }
        return NSRect(origin: .zero, size: size)
    }

    /// A low-contrast, deterministic fibre texture. It is cached per package
    /// and clipped to the printed face so every preset can share the same shell.
    private func paperGrain(for key: String) -> NSImage? {
        let texture: NSImage
        if let cached = Self.paperTextureCache[key] {
            texture = cached
        } else {
            let width = 192, height = 320
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            var seed: UInt32 = 2_166_136_261
            for byte in key.utf8 { seed = (seed ^ UInt32(byte)) &* 16_777_619 }
            seed |= 1
            for pixel in 0..<(width * height) {
                seed = 1_664_525 &* seed &+ 1_013_904_223
                let alpha = UInt8(3 + ((seed >> 25) & 0x0b))
                let offset = pixel * 4
                // Premultiplied charcoal flecks at only a few percent opacity.
                bytes[offset] = alpha / 2
                bytes[offset + 1] = alpha / 2
                bytes[offset + 2] = alpha / 2
                bytes[offset + 3] = alpha
            }
            let generated = bytes.withUnsafeMutableBytes { storage -> NSImage? in
                guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                      let image = context.makeImage() else { return nil }
                return NSImage(cgImage: image, size: NSSize(width: width, height: height))
            }
            guard let generated else { return nil }
            texture = generated
            Self.paperTextureCache[key] = generated
        }
        return texture
    }

    private func drawPaperGrain(in rect: NSRect) {
        paperGrain(for: style.id)?.draw(in: rect, from: .zero, operation: .multiply, fraction: 0.42)
        // A soft, broad surface sheen helps distinguish coated carton from ink.
        let sheen = NSBezierPath(rect: rect)
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.075),
                            NSColor.white.withAlphaComponent(0.012),
                            NSColor.black.withAlphaComponent(0.035)])?.draw(in: sheen, angle: 0)
    }

    private func drawPrintedFinish(in rect: NSRect) {
        let inset = rect.insetBy(dx: 8, dy: 8)
        let border = NSBezierPath(roundedRect: inset, xRadius: 1.5, yRadius: 1.5)
        style.edge.withAlphaComponent(0.36).setStroke()
        border.lineWidth = 1.1
        border.stroke()
        let inner = NSBezierPath(roundedRect: inset.insetBy(dx: 1.4, dy: 1.4), xRadius: 1, yRadius: 1)
        NSColor.white.withAlphaComponent(0.12).setStroke()
        inner.lineWidth = 0.45
        inner.stroke()
        // Fine corner registration marks mimic a restrained metallic foil stamp.
        let markY = rect.minY + 35
        for x in [rect.minX + 19, rect.maxX - 19] {
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: x - 3, y: markY)); mark.line(to: NSPoint(x: x + 3, y: markY))
            mark.move(to: NSPoint(x: x, y: markY - 3)); mark.line(to: NSPoint(x: x, y: markY + 3))
            style.foil.withAlphaComponent(0.42).setStroke(); mark.lineWidth = 0.55; mark.stroke()
        }
    }

    /// The unprinted paperboard shell is rendered first; brand art is only a
    /// surface layer, so every preset shares the same folded hard-pack body.
    private func drawBodySidePanels() {
        let rect = bodyRect
        let sideDepth: CGFloat = min(4.5, rect.width * 0.055)
        let bottomDepth: CGFloat = 3
        let left = NSBezierPath()
        left.move(to: NSPoint(x: rect.minX - sideDepth, y: rect.minY - bottomDepth))
        left.line(to: NSPoint(x: rect.minX, y: rect.minY))
        left.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        left.line(to: NSPoint(x: rect.minX - sideDepth, y: rect.maxY - 3))
        left.close()
        NSGradient(colors: [style.body.last ?? .darkGray, style.body.first ?? .gray])?.draw(in: left, angle: 0)

        let right = NSBezierPath()
        right.move(to: NSPoint(x: rect.maxX + sideDepth, y: rect.minY - bottomDepth))
        right.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        right.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        right.line(to: NSPoint(x: rect.maxX + sideDepth, y: rect.maxY - 3))
        right.close()
        NSGradient(colors: [style.body.first ?? .gray, style.body.last ?? .darkGray])?.draw(in: right, angle: 0)

        let base = NSBezierPath()
        base.move(to: NSPoint(x: rect.minX - sideDepth, y: rect.minY - bottomDepth))
        base.line(to: NSPoint(x: rect.minX, y: rect.minY))
        base.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        base.line(to: NSPoint(x: rect.maxX + sideDepth, y: rect.minY - bottomDepth))
        base.close()
        (style.body.last ?? .darkGray).withAlphaComponent(0.9).setFill()
        base.fill()
        style.edge.withAlphaComponent(0.42).setStroke()
        let seam = NSBezierPath(); seam.move(to: NSPoint(x: rect.minX + 1, y: rect.minY - bottomDepth + 0.7))
        seam.line(to: NSPoint(x: rect.maxX - 1, y: rect.minY - bottomDepth + 0.7))
        seam.lineWidth = 0.65; seam.stroke()
    }

    private func drawNotchCutEdges() {
        guard mouthNotchDepth > 1 else { return }
        let rect = bodyRect
        let halfWidth = min(rect.width * (isSlimHardPack ? 0.29 : 0.36), isSlimHardPack ? 48 : 58)
        let y = rect.maxY - mouthNotchDepth
        Self.cartonPaper(0.82).withAlphaComponent(0.55).setStroke()
        let cut = NSBezierPath()
        cut.move(to: NSPoint(x: center.x - halfWidth, y: rect.maxY - 1))
        cut.line(to: NSPoint(x: center.x - halfWidth, y: y + 2))
        cut.curve(to: NSPoint(x: center.x - halfWidth + 3, y: y),
                  controlPoint1: NSPoint(x: center.x - halfWidth, y: y),
                  controlPoint2: NSPoint(x: center.x - halfWidth + 1, y: y))
        cut.line(to: NSPoint(x: center.x + halfWidth - 3, y: y))
        cut.curve(to: NSPoint(x: center.x + halfWidth, y: y + 2),
                  controlPoint1: NSPoint(x: center.x + halfWidth - 1, y: y),
                  controlPoint2: NSPoint(x: center.x + halfWidth, y: y))
        cut.line(to: NSPoint(x: center.x + halfWidth, y: rect.maxY - 1))
        cut.lineWidth = 1.1; cut.stroke()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let cutHighlight = NSBezierPath(); cutHighlight.move(to: NSPoint(x: center.x - halfWidth + 1.5, y: rect.maxY - 2))
        cutHighlight.line(to: NSPoint(x: center.x - halfWidth + 1.5, y: y + 3))
        cutHighlight.line(to: NSPoint(x: center.x + halfWidth - 1.5, y: y + 3))
        cutHighlight.line(to: NSPoint(x: center.x + halfWidth - 1.5, y: rect.maxY - 2))
        cutHighlight.lineWidth = 0.55; cutHighlight.stroke()
    }

    private func drawGoldText(_ text: String, at point: NSPoint, size: CGFloat) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Songti SC", size: size) ?? NSFont.systemFont(ofSize: size, weight: .regular),
            .foregroundColor: style.foil.withAlphaComponent(0.98),
            .paragraphStyle: paragraph,
            .kern: size > 20 ? 3.2 : 1.0
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let width = max(bodyRect.width - 24, string.size().width + 24)
        string.draw(in: NSRect(x: point.x - width / 2, y: point.y - size / 2, width: width, height: size + 5))
    }

    private func drawOpenInterior() {
        let rect = bodyRect
        let baseY = rect.maxY - max(mouthNotchDepth + 2, rect.height * 0.26)
        let rimY = rect.maxY
        let inset = rect.width * 0.09
        let collar = [
            NSPoint(x: rect.minX + 1, y: baseY),
            NSPoint(x: rect.maxX - 1, y: baseY),
            NSPoint(x: rect.maxX - 2, y: rimY),
            NSPoint(x: rect.minX + 2, y: rimY)
        ]
        let foil = [
            NSPoint(x: rect.minX + inset + 3, y: baseY + 5),
            NSPoint(x: rect.maxX - inset - 3, y: baseY + 5),
            NSPoint(x: rect.maxX - inset, y: rimY - 2),
            NSPoint(x: rect.minX + inset, y: rimY - 2)
        ]
        drawLidSurface(collar, colors: [Self.cartonPaper(0.69), Self.cartonPaper(0.88)], angle: 94)
        drawLidSurface([collar[0], foil[0], foil[3], collar[3]],
                       colors: [Self.cartonPaper(0.91), Self.cartonPaper(0.64)], angle: 5)
        drawLidSurface([foil[1], collar[1], collar[2], foil[2]],
                       colors: [Self.cartonPaper(0.57), Self.cartonPaper(0.83)], angle: -8)

        // The foil wrapping catches light independently of the paper collar.
        drawLidSurface(foil, colors: [
            NSColor(calibratedWhite: 0.78, alpha: 1), NSColor(calibratedWhite: 0.57, alpha: 1),
            NSColor(calibratedWhite: 0.66, alpha: 1), NSColor(calibratedWhite: 0.41, alpha: 1)
        ], angle: 85)
        for (corner, back, offset) in [(0, 3, 7.0), (1, 2, -7.0)] {
            let fold = interpolate(foil[corner], foil[back], 0.35)
            let tip = NSPoint(x: foil[corner].x + offset, y: foil[corner].y + 1)
            drawLidSurface([foil[corner], tip, fold],
                           colors: [NSColor(calibratedWhite: 0.76, alpha: 1),
                                    NSColor(calibratedWhite: 0.50, alpha: 1)], angle: 105)
            drawCartonLine(from: fold, to: tip, color: NSColor.white.withAlphaComponent(0.43), width: 0.55)
        }
    }

    /// Live cigarettes remain in fixed box-local positions. The opening mask
    /// reveals them from their tips as the lid clears the mouth; it never moves
    /// the cigarettes or fades them in.
    private func drawPackedCigarettes() {
        guard mouthNotchDepth > 1, !occupiedSlots.isEmpty else { return }
        let rect = bodyRect
        let halfWidth = min(rect.width * (isSlimHardPack ? 0.29 : 0.36), isSlimHardPack ? 48 : 58)
        let openingMinY = rect.maxY - mouthNotchDepth
        let angle = flipAngle(progress: CGFloat(openProgress))
        // Opening the lid uncovers the cigarette tips progressively. Using
        // 1-cos follows the hinge angle: almost nothing is exposed at 10–20%,
        // then the sticks emerge naturally as the lid passes the pack rim.
        let reveal = min(1, max(0, (1 - cos(angle)) * 0.5))
        let exposedTipHeight = min(max(0, contentsRect.maxY - rect.maxY), bodyRect.height * 0.80 * reveal)
        let opening = NSBezierPath(rect: NSRect(x: center.x - halfWidth, y: openingMinY,
                                               width: halfWidth * 2,
                                               height: mouthNotchDepth + exposedTipHeight))
        NSGraphicsContext.saveGraphicsState()
        opening.addClip()
        let ordered = occupiedSlots.sorted {
            let firstRow = rowIndex($0), secondRow = rowIndex($1)
            return firstRow == secondRow ? $0 < $1 : firstRow > secondRow
        }
        for index in ordered where index != poppedSlot && index != insertionMotion?.slot &&
            !(isPulling && pullProgress > 0.001 && index == selectedSlot) {
            drawCigaretteModel(at: slotCenter(index), scale: packedCigaretteScale, alpha: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        if let motion = insertionMotion {
            let p = motion.progress
            let eased = p * p * (3 - 2 * p)
            let target = slotCenter(motion.slot)
            let targetCenter = NSPoint(x: target.x, y: target.y - 80 * packedCigaretteScale)
            let currentCenter = NSPoint(x: motion.startCenter.x + (targetCenter.x - motion.startCenter.x) * eased,
                                        y: motion.startCenter.y + (targetCenter.y - motion.startCenter.y) * eased)
            let scale = motion.startScale + (packedCigaretteScale - motion.startScale) * eased
            NSGraphicsContext.saveGraphicsState()
            addMouthOcclusionClip()
            drawCigaretteModel(at: NSPoint(x: currentCenter.x, y: currentCenter.y + 80 * scale),
                               scale: scale, alpha: 1, angle: motion.angle * (1 - eased))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func rowIndex(_ index: Int) -> Int {
        rowPosition(for: index).row
    }

    private func rowPosition(for index: Int) -> (row: Int, column: Int, count: Int) {
        var firstSlot = 0
        for (row, count) in style.geometry.rowCounts.enumerated() {
            if index < firstSlot + count { return (row, index - firstSlot, count) }
            firstSlot += count
        }
        let count = style.geometry.rowCounts.last ?? 1
        return (max(0, style.geometry.rowCounts.count - 1), max(0, index - firstSlot), count)
    }

    private func drawCigaretteModel(at filterTop: NSPoint, scale: CGFloat, alpha: CGFloat, angle: CGFloat = 0, lit: Bool = false) {
        guard let image = cigaretteArtwork(for: cigaretteStyleResolver?(style), lit: lit),
              let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: filterTop.x, y: filterTop.y - 85 * scale)
        context.rotate(by: .pi / 2 + angle)
        context.scaleBy(x: scale, y: scale)
        image.draw(in: NSRect(x: -110, y: -110, width: 220, height: 220),
                   from: .zero, operation: .sourceOver, fraction: alpha)
        context.restoreGState()
    }

    private struct FlipPose {
        let progress: CGFloat
        let angle: CGFloat
    }

    private struct LidShellGeometry {
        let outerFront: [NSPoint]
        let innerFront: [NSPoint]
        let innerRoof: [NSPoint]
        let leftWall: [NSPoint]
        let rightWall: [NSPoint]
        let frontCut: [NSPoint]
        let hingeFold: [NSPoint]

        var allPoints: [NSPoint] {
            [outerFront, innerFront, innerRoof, leftWall, rightWall, frontCut, hingeFold].flatMap { $0 }
        }
    }

    /// Shared hard-pack lid poses. These describe the angle of one rigid flap
    /// around its rear hinge, rather than independent artwork frames.
    private static let hardPackFlipPoses: [FlipPose] = [
        .init(progress: 0.00, angle: 0.00),
        .init(progress: 0.20, angle: 0.25),
        .init(progress: 0.50, angle: 1.05),
        .init(progress: 0.80, angle: 2.15),
        .init(progress: 1.00, angle: .pi)
    ]

    /// The former 75% pose is now the fully-open endpoint.
    private static let fullyOpenPoseProgress: CGFloat = 0.75

    private static func normalizedProgress(forLegacyProgress progress: Double) -> Double {
        min(1, max(0, progress / Double(fullyOpenPoseProgress)))
    }

    private func flipAngle(progress: CGFloat) -> CGFloat {
        // The old 75% pose is the new fully-open endpoint. Scale normalized
        // progress into the old pose range so every consumer (drawing, hit
        // testing and extraction geometry) uses the same remapped motion.
        let t = min(Self.fullyOpenPoseProgress, max(0, progress) * Self.fullyOpenPoseProgress)
        let poses = Self.hardPackFlipPoses
        guard let upper = poses.firstIndex(where: { $0.progress >= t }) else { return .pi }
        guard upper > 0 else { return poses[0].angle }
        let lowerPose = poses[upper - 1], upperPose = poses[upper]
        let segment = (t - lowerPose.progress) / (upperPose.progress - lowerPose.progress)
        return lowerPose.angle + (upperPose.angle - lowerPose.angle) * segment
    }

    private func lidShellGeometry(progress: CGFloat) -> LidShellGeometry {
        let rect = bodyRect
        let hingeY = rect.maxY + 1
        let lidLength = rect.height * style.geometry.lidBandFraction
        // Standard pack depth (front to back), rather than paper thickness.
        let packDepth = rect.height * 23.0 / 86.0
        let wallThickness = min(2.2, max(1.4, rect.width * 0.012))
        let lidHalfWidth = rect.width / 2
        let lidCenterOffset: CGFloat = 0
        let angle = flipAngle(progress: progress)
        let cameraDistance = max(300, rect.height * 2.1)

        func project(x: CGFloat, alongLid: CGFloat, fromHinge: CGFloat) -> NSPoint {
            // Coordinates describe a real open-ended carton shell: a long lid
            // axis, and a separate front-to-back pack-depth axis. Both rotate
            // around the same rear hinge; there is no progress-based scaling.
            let localY = -alongLid * cos(angle) + fromHinge * sin(angle)
            let depthAway = alongLid * sin(angle) + (packDepth - fromHinge) * cos(angle)
            let perspective = cameraDistance / (cameraDistance + depthAway)
            // Keep every hard-pack lid's left and right edges parallel while
            // retaining depth foreshortening vertically.
            let horizontalPerspective: CGFloat = 1
            return NSPoint(x: center.x + lidCenterOffset + x * horizontalPerspective,
                           y: hingeY + localY * perspective)
        }

        let outerFront = [
            project(x: -lidHalfWidth, alongLid: lidLength, fromHinge: packDepth),
            project(x: lidHalfWidth, alongLid: lidLength, fromHinge: packDepth),
            project(x: lidHalfWidth, alongLid: 0, fromHinge: packDepth),
            project(x: -lidHalfWidth, alongLid: 0, fromHinge: packDepth)
        ]

        let openingWidth = lidHalfWidth - wallThickness
        // Give the recessed ceiling its own vanishing width while keeping the
        // printed front's straight-on silhouette. The open lip stays wider.
        let recess = min(rect.width * 0.048, 9) * sin(angle)
        let ceilingWidth = openingWidth - recess
        let nearDepth = packDepth - wallThickness
        let nearLeft = project(x: -openingWidth, alongLid: lidLength, fromHinge: nearDepth)
        let nearRight = project(x: openingWidth, alongLid: lidLength, fromHinge: nearDepth)
        let roofFrontLeft = project(x: -ceilingWidth, alongLid: wallThickness, fromHinge: nearDepth)
        let roofFrontRight = project(x: ceilingWidth, alongLid: wallThickness, fromHinge: nearDepth)
        let roofBackLeft = project(x: -ceilingWidth, alongLid: wallThickness, fromHinge: wallThickness)
        let roofBackRight = project(x: ceilingWidth, alongLid: wallThickness, fromHinge: wallThickness)
        let hingeLeft = project(x: -openingWidth, alongLid: 0, fromHinge: 0)
        let hingeRight = project(x: openingWidth, alongLid: 0, fromHinge: 0)

        return LidShellGeometry(
            outerFront: outerFront,
            innerFront: [nearLeft, nearRight, roofFrontRight, roofFrontLeft],
            innerRoof: [roofBackLeft, roofBackRight, roofFrontRight, roofFrontLeft],
            leftWall: [nearLeft, roofFrontLeft, roofBackLeft, hingeLeft],
            rightWall: [nearRight, hingeRight, roofBackRight, roofFrontRight],
            frontCut: [outerFront[0], outerFront[1], nearRight, nearLeft],
            hingeFold: [NSPoint(x: hingeLeft.x, y: rect.maxY - 4),
                        NSPoint(x: hingeRight.x, y: rect.maxY - 4),
                        roofBackRight, roofBackLeft]
        )
    }

    private func lidPoints(progress: CGFloat) -> [NSPoint] {
        lidShellGeometry(progress: progress).outerFront
    }

    private func drawProjectedArtwork(_ artwork: NSImage, sourceRect: NSRect, on points: [NSPoint], fraction: CGFloat = 1) {
        guard points.count == 4, sourceRect.width > 0, sourceRect.height > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }

        // A closed hard-pack lid is a flat rectangle. Drawing it through the
        // perspective mesh needlessly clips the artwork into many horizontal
        // slices; antialiased slice boundaries can show up as extra stripes.
        // Draw the unprojected face in one pass while it is flat, and reserve
        // the mesh for poses that actually need perspective projection.
        let bounds = NSRect(x: points.map(\.x).min() ?? 0,
                            y: points.map(\.y).min() ?? 0,
                            width: (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0),
                            height: (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0))
        let isFlatRectangle = abs(points[0].y - points[1].y) < 0.01
            && abs(points[2].y - points[3].y) < 0.01
            && abs(points[0].x - points[3].x) < 0.01
            && abs(points[1].x - points[2].x) < 0.01
        if isFlatRectangle {
            context.saveGState()
            context.interpolationQuality = .high
            artwork.draw(in: bounds, from: sourceRect, operation: .sourceOver, fraction: fraction)
            context.restoreGState()
            return
        }

        let imageKey = ObjectIdentifier(artwork)
        let cgImage: CGImage
        if let cached = projectedCGImageCache[imageKey] {
            cgImage = cached
        } else if let converted = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            cgImage = converted
            projectedCGImageCache[imageKey] = converted
        } else {
            return
        }

        // Thin horizontal mesh strips approximate a perspective projection
        // without a 3D runtime. The same mapping works for built-in and
        // community artwork and keeps motion deterministic at every frame.
        let strips = 12
        let farLeft = points[0], farRight = points[1]
        let hingeRight = points[2], hingeLeft = points[3]
        let imageSize = artwork.size
        context.saveGState()
        context.interpolationQuality = .high
        let silhouette = CGMutablePath()
        silhouette.addLines(between: points)
        silhouette.closeSubpath()
        context.addPath(silhouette)
        context.clip()
        context.setShouldAntialias(false)
        for strip in 0..<strips {
            let u0 = CGFloat(strip) / CGFloat(strips)
            let u1 = CGFloat(strip + 1) / CGFloat(strips)
            let y0 = sourceRect.minY + sourceRect.height * u0
            let y1 = sourceRect.minY + sourceRect.height * u1
            let q0 = interpolate(farLeft, hingeLeft, u0)
            let q1 = interpolate(farRight, hingeRight, u0)
            let q2 = interpolate(farLeft, hingeLeft, u1)
            let q3 = interpolate(farRight, hingeRight, u1)
            let p0 = NSPoint(x: sourceRect.minX, y: y0)
            let p1 = NSPoint(x: sourceRect.maxX, y: y0)
            let p2 = NSPoint(x: sourceRect.minX, y: y1)
            guard let transform = affineTransform(from: (p0, p1, p2), to: (q0, q1, q2)) else { continue }

            let clip = CGMutablePath()
            clip.move(to: q0); clip.addLine(to: q1); clip.addLine(to: q3); clip.addLine(to: q2); clip.closeSubpath()
            context.saveGState()
            context.addPath(clip); context.clip()
            context.concatenate(transform)
            context.setAlpha(fraction)
            context.draw(cgImage, in: NSRect(origin: .zero, size: imageSize))
            context.restoreGState()
        }
        context.restoreGState()
    }

    private func interpolate(_ a: NSPoint, _ b: NSPoint, _ t: CGFloat) -> NSPoint {
        NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func affineTransform(from source: (NSPoint, NSPoint, NSPoint), to target: (NSPoint, NSPoint, NSPoint)) -> CGAffineTransform? {
        let u = NSPoint(x: source.1.x - source.0.x, y: source.1.y - source.0.y)
        let v = NSPoint(x: source.2.x - source.0.x, y: source.2.y - source.0.y)
        let U = NSPoint(x: target.1.x - target.0.x, y: target.1.y - target.0.y)
        let V = NSPoint(x: target.2.x - target.0.x, y: target.2.y - target.0.y)
        let determinant = u.x * v.y - v.x * u.y
        guard abs(determinant) > 0.0001 else { return nil }
        let a = (U.x * v.y - V.x * u.y) / determinant
        let c = (-U.x * v.x + V.x * u.x) / determinant
        let b = (U.y * v.y - V.y * u.y) / determinant
        let d = (-U.y * v.x + V.y * u.x) / determinant
        let tx = target.0.x - a * source.0.x - c * source.0.y
        let ty = target.0.y - b * source.0.x - d * source.0.y
        return CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    private static func cartonPaper(_ lightness: CGFloat) -> NSColor {
        NSColor(calibratedRed: lightness, green: lightness * 0.973,
                blue: lightness * 0.923, alpha: 1)
    }

    private func drawLid(progress: Double) {
        let t = CGFloat(progress)
        let shell = lidShellGeometry(progress: t)
        let angle = flipAngle(progress: t)

        if angle > 0.025 {
            // The rear fold crosses the hinge line and tucks behind the box liner.
            // Keep its bottom on the body while the upper edge follows the lid.
            if angle >= .pi / 2 {
                drawLidSurface(shell.hingeFold, colors: [Self.cartonPaper(0.53), Self.cartonPaper(0.76)], angle: 90)
            }
            let roofLight = 0.70 + 0.20 * sin(angle)
            let frontLight = 0.80 - 0.13 * cos(angle)
            drawCartonFace(shell.innerRoof, light: roofLight, seams: [1, 2, 3])
            drawLidCornerTabs(on: shell.innerRoof, light: roofLight)
            drawCartonFace(shell.leftWall, light: 0.68 + 0.10 * sin(angle), seams: [1])
            drawCartonFace(shell.rightWall, light: 0.59 + 0.11 * sin(angle), seams: [2])
            if angle >= .pi / 2 {
                drawCartonFace(shell.innerFront, light: frontLight, seams: [2])
            }
            drawLidSurface(shell.frontCut, colors: [Self.cartonPaper(0.79), Self.cartonPaper(0.93)], angle: 90)
            let hinge = shell.innerRoof
            drawCartonLine(from: hinge[0], to: hinge[1],
                           color: Self.cartonPaper(0.45).withAlphaComponent(0.42 * sin(angle)), width: 0.65)
        }

        guard angle < .pi / 2 else { return }
        let face = shell.outerFront
        let frontTexture = style.lidOutsideArtwork ?? style.lidOutsideOpenArtwork
        if let frontTexture {
            drawProjectedArtwork(frontTexture, sourceRect: artworkSourceRect(for: frontTexture), on: face)
        } else if let frontArtwork = style.frontArtwork {
            let lidFraction = style.geometry.lidBandFraction
            let source = NSRect(x: 0, y: frontArtwork.size.height * (1 - lidFraction),
                                width: frontArtwork.size.width, height: frontArtwork.size.height * lidFraction)
            drawProjectedArtwork(frontArtwork, sourceRect: source, on: face)
        } else {
            drawLidSurface(face, colors: style.lid, angle: 90)
        }
    }

    private func drawLidCornerTabs(on roof: [NSPoint], light: CGFloat) {
        for (corner, side, across) in [(3, 0, 2), (2, 1, 3)] {
            let alongFold = interpolate(roof[corner], roof[side], 0.23)
            let acrossFold = interpolate(roof[corner], roof[across], 0.085)
            drawLidSurface([roof[corner], alongFold, acrossFold],
                           colors: [Self.cartonPaper(light - 0.09), Self.cartonPaper(light - 0.02)], angle: 112)
            drawCartonLine(from: alongFold, to: acrossFold,
                           color: Self.cartonPaper(0.48).withAlphaComponent(0.40), width: 0.5)
        }
    }

    private func drawCartonFace(_ points: [NSPoint], light: CGFloat, seams: [Int]) {
        let face = NSBezierPath()
        face.move(to: points[0])
        points.dropFirst().forEach { face.line(to: $0) }
        face.close()
        NSGraphicsContext.saveGraphicsState()
        face.addClip()
        NSGradient(colors: [Self.cartonPaper(light - 0.045), Self.cartonPaper(light)])?
            .draw(in: face.bounds, angle: 112)

        if let grain = paperGrain(for: "shared-carton"), let context = NSGraphicsContext.current?.cgContext,
           let projection = affineTransform(from: (.zero, NSPoint(x: 1, y: 0), NSPoint(x: 0, y: 1)),
                                            to: (points[0], points[1], points[3])) {
            context.saveGState()
            context.concatenate(projection)
            grain.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1),
                       from: .zero, operation: .sourceOver, fraction: 0.55)
            context.restoreGState()
        }

        for seam in seams {
            let a = points[seam], b = points[(seam + 1) % 4]
            let edge = interpolate(a, b, 0.5)
            let direction = NSPoint(x: b.y - a.y, y: a.x - b.x)
            let length = hypot(direction.x, direction.y)
            guard length > 0.5 else { continue }
            let opposite = interpolate(points[(seam + 2) % 4], points[(seam + 3) % 4], 0.5)
            let depth = ((opposite.x - edge.x) * direction.x + (opposite.y - edge.y) * direction.y) / length
            guard abs(depth) > 0.5 else { continue }
            let distance = min(seam == 2 ? 8 : 4, abs(depth) * 0.58)
            let scale = (depth > 0 ? distance : -distance) / length
            let fade = NSPoint(x: edge.x + direction.x * scale, y: edge.y + direction.y * scale)
            let shade = Self.cartonPaper(0.29)
            NSGradient(colors: [shade.withAlphaComponent(seam == 2 ? 0.41 : 0.23),
                                shade.withAlphaComponent(0.08), shade.withAlphaComponent(0)])?
                .draw(from: edge, to: fade, options: [.drawsBeforeStartingLocation])
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCartonLine(from start: NSPoint, to end: NSPoint, color: NSColor, width: CGFloat) {
        let line = NSBezierPath()
        line.move(to: start)
        line.line(to: end)
        color.setStroke()
        line.lineWidth = width
        line.stroke()
    }

    private func drawLidSurface(_ points: [NSPoint], colors: [NSColor], angle: CGFloat) {
        guard points.count >= 3 else { return }
        let path = NSBezierPath(); path.move(to: points[0]); points.dropFirst().forEach { path.line(to: $0) }; path.close()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colors: colors)?.draw(in: path.bounds, angle: angle)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawExtractedCigarette(at center: NSPoint, progress: CGFloat, insideBox: Bool? = nil) {
        let t = min(1, max(0, progress))
        let scale = extractionMode == .oneToOne
            ? activeExtractionScale
            : packedCigaretteScale + (activeExtractionScale - packedCigaretteScale) * t
        NSGraphicsContext.saveGraphicsState()
        // Hide the part inside the front wall without repainting over the lid.
        if insideBox ?? !hasClearedMouth { addMouthOcclusionClip() }
        drawCigaretteModel(at: NSPoint(x: center.x, y: center.y + 80 * scale), scale: scale, alpha: 1, lit: extractionLit)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Keep partially extracted or inserting cigarettes behind the carton
    /// front, visible only through the real mouth cutout and the space above it.
    private func addMouthOcclusionClip() {
        let visible = NSBezierPath(rect: bounds)
        visible.append(frontPath())
        visible.windingRule = .evenOdd
        visible.addClip()

        let halfWidth = min(bodyRect.width * (isSlimHardPack ? 0.29 : 0.36), isSlimHardPack ? 48 : 58)
        let opening = NSBezierPath(rect: NSRect(x: center.x - halfWidth,
                                                y: bodyRect.maxY - mouthNotchDepth,
                                                width: halfWidth * 2,
                                                height: max(0, bounds.maxY - bodyRect.maxY + mouthNotchDepth)))
        // Above the rim the entire cigarette is visible, including at the
        // outermost slots. Only the part inside the carton is mouth-clipped.
        opening.appendRect(NSRect(x: bounds.minX, y: bodyRect.maxY,
                                  width: bounds.width, height: max(0, bounds.maxY - bodyRect.maxY)))
        opening.addClip()
    }

    private func takeFromMenu() {
        guard remaining > 0 else { return }
        guard let index = poppedSlot ?? occupiedSlots.first else { return }
        let slot = slotCenter(index)
        let start = index == poppedSlot ? poppedCigaretteCenter : NSPoint(x: slot.x, y: slot.y - 80 * packedCigaretteScale)
        let destination = screenPoint(for: NSPoint(x: center.x, y: 460))
        animateTake(from: start, toScreen: destination, removing: index)
    }

    private func animateTake(from start: NSPoint, toScreen destination: NSPoint, removing slot: Int) {
        guard !delayedTake else { return }
        let target: NSPoint
        if let window {
            let viewPoint = convert(window.convertPoint(fromScreen: destination), from: nil)
            target = unrotated(viewPoint)
        } else {
            target = NSPoint(x: center.x, y: 460)
        }
        cigaretteScale = onCigaretteScale?(destination) ?? cigaretteScale
        activeExtractionScale = cigaretteScale
        delayedTake = true
        isPulling = true
        hasClearedMouth = false; extractionLit = false
        draggedCenter = start
        pullProgress = 0
        let began = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = min(1, (CACurrentMediaTime() - began) / 0.34)
            let eased = CGFloat(t * t * (3 - 2 * t))
            self.draggedCenter = NSPoint(x: start.x + (target.x - start.x) * eased,
                                         y: start.y + (target.y - start.y) * eased)
            self.pullProgress = eased
            self.needsDisplay = true
            guard t >= 1 else { return }
            timer.invalidate()
            self.extractionAnimation = nil
            self.delayedTake = false
            self.finishTake(at: destination, removing: slot)
        }
        RunLoop.main.add(timer, forMode: .common)
        extractionAnimation = timer
    }

    @discardableResult
    private func finishTake(at screenCenter: NSPoint, removing slot: Int? = nil, duringDrag: Bool = false) -> Bool {
        guard remaining > 0 else { return false }
        guard onTakeCigarette?(screenCenter, rotationAngle + .pi / 2, activeExtractionScale, extractionLit, duringDrag) == true else {
            selectedSlot = nil; draggedCenter = nil; isPulling = false; pullProgress = 0; delayedTake = false
            restoreCanvasSize(); needsDisplay = true
            return false
        }
        if let slot, let index = occupiedSlots.firstIndex(of: slot) { occupiedSlots.remove(at: index) }
        else if !occupiedSlots.isEmpty { occupiedSlots.removeLast() }
        remaining = occupiedSlots.count
        onInventoryChanged?(remaining, occupiedSlots)
        poppedSlot = nil
        selectedSlot = nil; draggedCenter = nil; isPulling = false; pullProgress = 0
        if !duringDrag { restoreCanvasSize() }
        needsDisplay = true
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard !delayedTake else { return }
        isInteracting = true
        downScreen = NSEvent.mouseLocation
        lastShakeX = downScreen.x; shakeDirection = 0; shakeReversals = 0
        dragStartScreen = downScreen
        downOrigin = window?.frame.origin ?? .zero
        downLocal = unrotated(convert(event.locationInWindow, from: nil))
        let popRect = poppedFilterBounds
        selectedSlot = poppedSlot != nil && popRect.contains(downLocal) ? poppedSlot : hitSlot(downLocal)
        if let selectedSlot {
            gesture = .extract
            let slot = slotCenter(selectedSlot)
            draggedCenter = selectedSlot == poppedSlot
                ? poppedCigaretteCenter
                : NSPoint(x: slot.x, y: slot.y - 80 * packedCigaretteScale)
            dragStartCenter = draggedCenter ?? slot
            dragStartScale = packedCigaretteScale
            let filterAnchorY = dragStartCenter.y + 80 * dragStartScale
            dragTopOffset = selectedSlot == poppedSlot ? filterAnchorY - downLocal.y : slot.y - downLocal.y
            activeExtractionScale = packedCigaretteScale
            pullProgress = 0
            isPulling = true; hasClearedMouth = false; extractionLit = false; forwardingExtraction = false
        } else if NSRect(x: bodyRect.maxX - 25, y: bodyRect.minY - 7, width: 32, height: 32).contains(downLocal) {
            gesture = .rotate
            initialAngle = rotationAngle
            let localCenter = rotated(center)
            let screenCenter = window?.convertPoint(toScreen: convert(localCenter, to: nil)) ?? .zero
            let pointer = NSEvent.mouseLocation
            initialPointerAngle = atan2(pointer.y - screenCenter.y, pointer.x - screenCenter.x)
        } else {
            gesture = .pending
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        let distance = hypot(pointer.x - downScreen.x, pointer.y - downScreen.y)
        if gesture == .pending || gesture == .move {
            let dx = pointer.x - lastShakeX
            if abs(dx) >= 8 {
                let direction = dx > 0 ? 1 : -1
                if shakeDirection != 0 && direction != shakeDirection { shakeReversals += 1 }
                shakeDirection = direction; lastShakeX = pointer.x
                if shakeReversals >= 2 { shakeOutOne() }
            }
        }
        switch gesture {
        case .pending:
            guard distance >= 6, let onMove else { return }
            gesture = .move
            let correction = onMove(downOrigin, NSPoint(x: pointer.x - downScreen.x, y: pointer.y - downScreen.y))
            downOrigin.x += correction.x; downOrigin.y += correction.y
        case .move:
            guard let onMove else { return }
            let correction = onMove(downOrigin, NSPoint(x: pointer.x - downScreen.x, y: pointer.y - downScreen.y))
            downOrigin.x += correction.x; downOrigin.y += correction.y
        case .rotate:
            let viewPoint = unrotated(convert(event.locationInWindow, from: nil))
            let currentCenter = window?.convertPoint(toScreen: convert(rotated(center), to: nil)) ?? .zero
            let pointerAngle = atan2(pointer.y - currentCenter.y, pointer.x - currentCenter.x)
            rotationAngle = initialAngle + pointerAngle - initialPointerAngle
            onRotationChanged?(rotationAngle)
            _ = viewPoint
        case .extract:
            if forwardingExtraction { onFreeCigaretteDrag?(pointer); return }
            guard let window else { return }
            let viewPoint = convert(window.convertPoint(fromScreen: pointer), from: nil)
            let pointerCenter = unrotated(viewPoint)
            let upwardTravel = pointerCenter.y - downLocal.y
            pullProgress = min(1, max(0, upwardTravel / 55))
            activeExtractionScale = onCigaretteScale?(screenPoint(for: pointerCenter)) ?? activeExtractionScale
            let currentScale = extractionMode == .oneToOne
                ? activeExtractionScale
                : packedCigaretteScale + (activeExtractionScale - packedCigaretteScale) * CGFloat(pullProgress)
            let grabOffset = dragTopOffset * currentScale / max(0.01, dragStartScale)
            let pointerY = pointerCenter.y + grabOffset - 80 * currentScale
            let wasShakenOut = poppedSlot != nil && selectedSlot == poppedSlot
            let proposedY = hasClearedMouth || wasShakenOut ? pointerY : max(dragStartCenter.y, pointerY)
            if proposedY - 80 * currentScale >= bodyRect.maxY { hasClearedMouth = true }
            // The cigarette stays in its slot until the handoff; the current
            // pointer offset is captured at that point for all subsequent moves.
            let centerX = dragStartCenter.x
            draggedCenter = NSPoint(x: centerX,
                                    y: proposedY)
            if hasClearedMouth, let draggedCenter {
                let screenCenter = screenPoint(for: draggedCenter)
                if finishTake(at: screenCenter, removing: selectedSlot, duringDrag: true) {
                    forwardingExtraction = true
                    onExtractionBecameFree?(pointer)
                    return
                }
            }
            extendCanvasAbove(draggedCenter ?? pointerCenter, scale: currentScale)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let distance = hypot(NSEvent.mouseLocation.x - downScreen.x, NSEvent.mouseLocation.y - downScreen.y)
        switch gesture {
        case .pending:
            setOpen(!isOpen)
        case .move:
            onMoveFinished?()
        case .rotate:
            onRotationChanged?(rotationAngle)
        case .extract:
            if forwardingExtraction {
                forwardingExtraction = false
                onFreeCigaretteDragFinished?()
                restoreCanvasSize()
                break
            }
            let local = distance < 7 ? (selectedSlot.map { NSPoint(x: slotCenter($0).x, y: slotCenter($0).y + 22) } ?? center) : (draggedCenter ?? center)
            let target = screenPoint(for: local)
            if !hasClearedMouth {
                let isReturning = distance >= 6
                if isReturning, let selectedSlot, let draggedCenter {
                    animateCigaretteBackToSlot(slot: selectedSlot, from: draggedCenter,
                                               scale: activeExtractionScale)
                }
                // A cigarette that has not fully cleared the mouth remains in
                // its original fixed slot. A partial pull glides back there,
                // so the tip is not clipped and the row stays aligned.
                poppedSlot = nil
                draggedCenter = nil; isPulling = false; pullProgress = 0
                selectedSlot = nil
                if !isReturning { restoreCanvasSize() }
            } else {
                finishTake(at: target, removing: selectedSlot)
            }
        }
        isInteracting = false
        needsDisplay = true
        onInteractionFinished?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let stockItem = NSMenuItem(title: tr("剩余 {{0}} 支", remaining), action: nil, keyEquivalent: "")
        stockItem.isEnabled = false
        let lidAction = NSMenuItem(title: isOpen ? tr("合上烟盒") : tr("打开烟盒"), action: #selector(toggleLid), keyEquivalent: "")
        let takeAction = NSMenuItem(title: tr("取一支烟"), action: #selector(takeOne), keyEquivalent: "")
        takeAction.isEnabled = remaining > 0
        let storeAction = NSMenuItem(title: tr("放回背包"), action: #selector(storeInInventory), keyEquivalent: "")
        [stockItem, NSMenuItem.separator(), lidAction, takeAction,
         NSMenuItem.separator(), storeAction].forEach { $0.target = self; menu.addItem($0) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func toggleLid() { setOpen(!isOpen) }
    @objc private func takeOne() { shakeOutOne() }
    @objc private func selectExtractionMode(_ sender: NSMenuItem) {
        guard CigaretteExtractionMode.allCases.indices.contains(sender.tag) else { return }
        extractionMode = CigaretteExtractionMode.allCases[sender.tag]
    }
    @objc private func rotateQuarterTurn() { rotationAngle += .pi / 2; onRotationChanged?(rotationAngle); onVisualBoundsChanged?() }
    @objc private func storeInInventory() { onStoreInInventory?() }
}
