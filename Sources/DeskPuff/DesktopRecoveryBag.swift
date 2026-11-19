import AppKit
import Combine
import DeskPuffCore

@MainActor final class DesktopRecoveryBag: NSView {
    static let canvasSize = NSSize(width: 330, height: 330)
    var onOpen: (() -> Void)?
    var onHide: (() -> Void)?
    var onMoveOpening: ((RecoveryOpening?, RecoveryOpening) -> Void)?

    private var image: NSImage?
    private var asset: String?
    private var angle = 0.0
    private(set) var isDragging = false
    private var rotationStart: Double?
    private var pointerAngleStart: Double = 0
    private var intakeUnits = 0
    private var feedbackSuccess = false
    private var mouseStart = CGPoint.zero
    private var windowStart = CGPoint.zero
    private var subscriptions = Set<AnyCancellable>()
    private var feedback: String?
    private var feedbackTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let store = InventoryStore.shared
        refreshArtwork()
        store.$economy.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refreshArtwork()
        }.store(in: &subscriptions)
    }

    required init?(coder: NSCoder) { nil }

    private var artwork: CGRect {
        let size = image?.size ?? NSSize(width: 242, height: 178)
        let scale = min(248 / max(1, size.width), 215 / max(1, size.height))
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    }

    var opening: RecoveryOpening? {
        guard let window, window.isVisible else { return nil }
        return RecoveryOpening(center: CGPoint(x: window.frame.midX, y: window.frame.midY), angle: angle, opening: artwork)
    }

    private func refreshArtwork() {
        let currentAsset = InventoryStore.shared.currentBagAsset
        guard asset != currentAsset else { return }
        asset = currentAsset
        image = InventoryWindowView.loadBagImage(asset: currentAsset)
            .flatMap(ProductStylePreviewHost.trimmedArtwork)
        constrainToScreen()
        needsDisplay = true
    }

    func constrainToScreen(proposed: CGPoint? = nil) {
        guard let window else { return }
        let origin = proposed ?? window.frame.origin
        let center = CGPoint(x: origin.x + bounds.midX, y: origin.y + bounds.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
                ?? NSScreen.screens.min(by: { distance(center, $0.frame) < distance(center, $1.frame) }) else { return }
        let halfWidth = (artwork.width * abs(cos(angle)) + artwork.height * abs(sin(angle))) / 2
        let halfHeight = (artwork.width * abs(sin(angle)) + artwork.height * abs(cos(angle))) / 2
        let frame = screen.frame
        let x = min(frame.maxX - halfWidth, max(frame.minX + halfWidth, center.x))
        var y = min(frame.maxY - halfHeight, max(frame.minY + halfHeight, center.y))
        if cos(angle) < -0.99 && y - halfHeight - frame.minY < 12 { y = frame.minY + halfHeight }
        window.setFrameOrigin(CGPoint(x: x - bounds.midX, y: y - bounds.midY))
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        hypot(point.x - min(rect.maxX, max(rect.minX, point.x)),
              point.y - min(rect.maxY, max(rect.minY, point.y)))
    }

    func show(_ text: String, success: Bool = false) {
        intakeUnits = 0
        setFeedback(text, success: success)
    }

    func showAshIntake(units: Int) {
        intakeUnits += units
        setFeedback(intakeUnits > 0 ? tr("收进 {{0}} 份烟灰", intakeUnits) : tr("已收进少量烟灰"), success: true)
    }

    private func setFeedback(_ text: String, success: Bool) {
        feedback = text
        feedbackSuccess = success
        feedbackTimer?.invalidate()
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.feedback = nil
                self?.intakeUnits = 0
                self?.needsDisplay = true
            }
        }
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = RecoveryOpening(center: CGPoint(x: bounds.midX, y: bounds.midY), angle: angle, opening: artwork).localPoint(point)
        return artwork.insetBy(dx: -3, dy: -3).contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onOpen?(); return }
        guard let window else { return }
        isDragging = true
        mouseStart = NSEvent.mouseLocation
        windowStart = window.frame.origin
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let pose = RecoveryOpening(center: center, angle: angle, opening: artwork)
        let point = pose.localPoint(mouseStart)
        let corner = abs(point.x) >= artwork.width * 0.32 && abs(point.y) >= artwork.height * 0.22
        rotationStart = corner ? angle : nil
        pointerAngleStart = atan2(mouseStart.y - center.y, mouseStart.x - center.x)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let previous = opening
        let mouse = NSEvent.mouseLocation
        if let rotationStart {
            let center = CGPoint(x: windowStart.x + bounds.midX, y: windowStart.y + bounds.midY)
            let pointerAngle = atan2(mouse.y - center.y, mouse.x - center.x)
            let target = rotationStart + pointerAngle - pointerAngleStart
            let quarterTurn = (target / (.pi / 2)).rounded() * (.pi / 2)
            angle = abs(target - quarterTurn) < 0.12 ? quarterTurn : target
            constrainToScreen(proposed: windowStart)
            needsDisplay = true
        } else {
            constrainToScreen(proposed: CGPoint(x: windowStart.x + mouse.x - mouseStart.x,
                                                y: windowStart.y + mouse.y - mouseStart.y))
        }
        if let opening, opening != previous {
            onMoveOpening?(rotationStart == nil ? previous : nil, opening)
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        rotationStart = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: tr("打开背包"), action: #selector(openBag), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("收起桌面背包"), action: #selector(hideBag), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func openBag() { onOpen?() }
    @objc private func hideBag() { onHide?() }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: angle)
        if let image {
            image.draw(in: artwork, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            NSColor(calibratedRed: 0.26, green: 0.16, blue: 0.37, alpha: 1).setFill()
            NSBezierPath(roundedRect: artwork, xRadius: 18, yRadius: 18).fill()
        }
        context.restoreGState()
        if let feedback {
            let tint = feedbackSuccess
                ? NSColor(calibratedRed: 0.64, green: 0.96, blue: 0.87, alpha: 1)
                : NSColor(calibratedRed: 0.82, green: 0.88, blue: 1, alpha: 1)
            let label = NSAttributedString(string: feedback, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white
            ])
            let size = label.size()
            let frame = CGRect(x: bounds.midX - (size.width + 33) / 2, y: bounds.midY - 35,
                               width: size.width + 33, height: size.height + 10)
            let capsule = NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2)
            let top = tint.blended(withFraction: 0.62, of: .black)?.withAlphaComponent(0.86) ?? .darkGray
            let bottom = NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.17, alpha: 0.91)
            NSGradient(starting: bottom, ending: top)?.draw(in: capsule, angle: 90)
            tint.withAlphaComponent(0.70).setStroke()
            capsule.lineWidth = 0.8
            capsule.stroke()
            tint.setFill()
            NSBezierPath(ovalIn: CGRect(x: frame.minX + 10, y: frame.midY - 2.5, width: 5, height: 5)).fill()
            label.draw(at: CGPoint(x: frame.minX + 21, y: frame.minY + 5))
        }
    }
}
