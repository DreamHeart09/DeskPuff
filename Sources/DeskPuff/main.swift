import AppKit
import DeskPuffCore
import SwiftUI

final class EdgeToEdgeDesktopPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private final class AdditionalDesktopObject {
    let id: UUID
    let kind: InventoryKind
    let window: NSPanel
    var boxView: CigaretteBoxView?
    var lighterView: LighterView?
    var ashtrayView: AshtrayView?
    init(id: UUID, kind: InventoryKind, window: NSPanel) { self.id = id; self.kind = kind; self.window = window }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "deskpuff" && $0.host == "profile" }) else { return }
        openPlayerHub(.rank)
    }

    private struct AshtrayAttachment {
        let inventoryID: UUID?
        let localCenter: NSPoint
        let relativeAngle: Double
    }
    private weak var parentSession: AppDelegate?
    private weak var sourceBoxView: CigaretteBoxView?
    private var status: NSStatusItem!
    private var statusPopover: NSPopover?
    private let isChild: Bool
    private let styleRegistry = StylePackageRegistry.shared
    private let cigaretteStyleStore = CigaretteStyleStore.shared
    private var cigaretteStyle: CigaretteStyle?
    private var ashtrayAttachment: AshtrayAttachment?
    private var controlPanelWindow: NSWindow?
    private var supportDeveloperWindow: NSWindow?
    private var gameSettingsWindow: NSWindow?
    private var recoveryBagWindow: NSPanel?
    private var recoveryBag: DesktopRecoveryBag? { recoveryBagWindow?.contentView as? DesktopRecoveryBag }
    private var detachedAshMass = 0.0
    private var lastAshInteraction: CFTimeInterval = 0
    private var hasLitCigarette = false
    private var inventoryWindow: NSWindow?
    private let playerHubNavigation = PlayerHubNavigation()
    private var lighterWindow: NSPanel?
    private var lighterView: LighterView?
    private var lighterIgnitionLatched = false
    private var lighterTipHeat = 0.0
    private var lighterHeatTick = CACurrentMediaTime()
    private weak var lastTakenSession: AppDelegate?
    private weak var extractionSession: AppDelegate?
    private var extractionPointer = NSPoint.zero
    private var extractionPointerTime: CFTimeInterval = 0
    private var extractionOffset = NSPoint.zero
    private var externallyDragging = false
    private var additionalSessions: [AppDelegate] = []
    private var activeInventoryIDs: [InventoryKind: [UUID]] = [:]
    private var primaryInventoryIDs: [InventoryKind: UUID] = [:]
    private var additionalDesktopObjects: [UUID: AdditionalDesktopObject] = [:]
    private var cigaretteExists: Bool
    private var cigaretteMotionMode = CigaretteMotionMode(rawValue: UserDefaults.standard.string(forKey: "cigaretteMotionModeV1") ?? "") ?? .free
    private var cigaretteBody = CigaretteRigidBody()
    private var cigarettePhysicsTimer: Timer?
    private var cigarettePhysicsLastTick: CFTimeInterval = 0
    private var lastCigaretteDragVelocity = NSPoint.zero
    private var lastCigaretteAngle = 0.0
    private var lastCigaretteAngleTime: CFTimeInterval = 0
    private var cachedWindowSurfaces: [AshSurface] = []
    private var windowSurfacesRefreshTime: CFTimeInterval = 0
    private let sharedBoxView: CigaretteBoxView?
    init(isChild: Bool = false, sharedAsh: AshOverlay? = nil, sharedBoxView: CigaretteBoxView? = nil,
         sharedAshtrayView: AshtrayView? = nil) {
        self.isChild = isChild; self.cigaretteExists = isChild; self.ash = sharedAsh ?? AshOverlay()
        self.sharedBoxView = sharedBoxView; self.ashtrayView = sharedAshtrayView; super.init()
    }
    private var smokeWindow: NSPanel!
    private var cigaretteWindow: NSPanel!
    private var boxWindow: NSPanel?
    private var boxView: CigaretteBoxView?
    private var ashtrayWindow: NSPanel?
    private var ashtrayView: AshtrayView?
    private var cigaretteBoxStyleMenu: NSMenu?
    private var ashtrayStyleMenu: NSMenu?
    private var smokeDisplays: [UInt32: (window: NSPanel, view: SmokeView)] = [:]
    private var lit = false
    private var cigarette: CigaretteView!
    private var smoke: SmokeView!
    private let ash: AshOverlay
    private var burn = CigaretteBurn()
    private var countsTowardRank = false
    private var inhaleMultiplier: Double = 10
    private var inhaledBurnSeconds: Double = 0
    private var inhaleReservoir = InhaleReservoir()
    private var lastAshFall: CFTimeInterval = 0
    private var ashDragDistance: CGFloat = 0
    private var ashShedDuringDrag = false
    private var tipContactActive = false
    private var filterContactActive = false
    private var ashtrayFloorContactActive = false
    private var contactPointer: NSPoint?
    private var contactPointerTime: CFTimeInterval = 0
    private var visible = true
    private var hitTestTimer: Timer?
    private var displayObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        migrateAshtrayScalePreference()
        if cigaretteStyle == nil {
            cigaretteStyle = cigaretteStyleStore.resolve(cigaretteStyleStore.defaultStyleID) ?? cigaretteStyleStore.defaultStyle
        }
        guard setupWindows() else { if !isChild { NSApp.terminate(nil) }; return }
        if !isChild { setupMenu() }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.syncSmokeDisplays(); self?.ensureVisible(); self?.keepCigaretteInsideScreen(); self?.positionSmoke(); self?.ash.updateDisplays() } }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cigarette.cancel(); self?.cigarette.setAnimating(false); self?.smokeDisplays.values.forEach { $0.view.pauseAndClear() }; self?.ash.setVisible(false) } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { guard let self else { return }; if self.visible { if self.cigaretteExists && !self.burn.isFinished && self.lit { self.smokeDisplays.values.forEach { $0.view.resume() } }; if self.cigaretteExists { self.cigarette.setAnimating(true) }; self.ash.setVisible(true) } } }
        let defaults = UserDefaults.standard
        let shouldOpenControlPanel = !isChild && defaults.bool(forKey: "openControlPanelAtLaunch")
        let shouldOpenInventory = !isChild && defaults.bool(forKey: "openInventoryAtLaunch")
        if shouldOpenControlPanel {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.openControlPanel() }
        }
        if shouldOpenInventory {
            let delay = shouldOpenControlPanel ? 0.85 : 0.35
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.openInventory()
                if shouldOpenControlPanel {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        guard let self else { return }
                        NSApp.activate(ignoringOtherApps: true)
                        self.inventoryWindow?.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
        if !isChild && defaults.bool(forKey: "openStoreAtLaunch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + (shouldOpenInventory ? 1.2 : 0.6)) { [weak self] in self?.openStore() }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        let store = InventoryStore.shared
        for (kind, ids) in activeInventoryIDs {
            for id in ids {
                if let extra = additionalDesktopObjects[id] {
                    switch kind {
                    case .cigaretteBox: store.updateState(id, state: extra.boxView?.inventoryState); if let view = extra.boxView { store.updateStyle(id, styleID: view.style.id) }
                    case .lighter: store.updateState(id, state: extra.lighterView?.inventoryState); if let view = extra.lighterView { store.updateStyle(id, styleID: view.style.id) }
                    case .ashtray: store.updateState(id, state: extra.ashtrayView?.inventoryState); if let view = extra.ashtrayView { store.updateStyle(id, styleID: view.style.id) }
                    default: break
                    }
                    continue
                }
                switch kind {
                case .cigaretteBox: if let view = boxView { store.updateState(id, state: view.inventoryState); store.updateStyle(id, styleID: view.style.id) }
                case .lighter: if let view = lighterView { store.updateState(id, state: view.inventoryState); store.updateStyle(id, styleID: view.style.id) }
                case .ashtray: if let view = ashtrayView { store.updateState(id, state: view.inventoryState); store.updateStyle(id, styleID: view.style.id) }
                default: break
                }
            }
        }
        store.settleIncome()
    }
    private func setupWindows() -> Bool {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        guard let initialScreen = NSScreen.main ?? NSScreen.screens.first,
              let entry = makeSmokeDisplay(for: initialScreen) else {
            let alert = NSAlert(); alert.messageText = tr("DeskPuff 无法启动 Metal 烟雾"); alert.informativeText = tr("请确认这台 Mac 支持 Metal，然后重新打开应用。"); alert.runModal(); return false
        }
        smokeDisplays[displayID(initialScreen)] = entry
        smokeWindow = entry.window; smoke = entry.view
        syncSmokeDisplays()
        let savedSpeed = UserDefaults.standard.integer(forKey: "inhaleMultiplier")
        inhaleMultiplier = [5, 10, 20].contains(savedSpeed) ? Double(savedSpeed) : 10
        ash.amount = AshAmount(rawValue: UserDefaults.standard.integer(forKey: "ashAmountV2")) ?? .light
        let savedV3 = UserDefaults.standard.dictionary(forKey: "cigarettePositionV3")
        let savedV2 = UserDefaults.standard.dictionary(forKey: "cigarettePositionV2")
        let old = UserDefaults.standard.dictionary(forKey: "cigarettePosition")
        let origin = NSPoint(x: savedV3?["x"] as? CGFloat ?? savedV2?["x"] as? CGFloat ?? (old?["x"] as? CGFloat).map { $0 - 20 } ?? visibleFrame.maxX-240,
                             y: savedV3?["y"] as? CGFloat ?? savedV2?["y"] as? CGFloat ?? old?["y"] as? CGFloat ?? visibleFrame.minY+90)
        cigaretteWindow = panel(NSRect(origin: origin, size: NSSize(width: 220, height: 220)), free: true)
        cigarette = CigaretteView(frame: NSRect(x: 0, y: 0, width: 220, height: 220)); cigaretteWindow.contentView = cigarette
        cigarette.cigaretteStyle = cigaretteStyle
        cigarette.lit = false
        cigaretteWindow.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        cigarette.rotationAngle = UserDefaults.standard.double(forKey: "cigaretteRotation")
        cigarette.onDrag = { [weak self] origin, delta, dragDelta, motion in
            guard let self else { return .zero }
            self.lastCigaretteDragVelocity = motion
            let previousTip = self.cigaretteScreenPoint(x: self.cigarette.smokeTipX, y: 19)
            let previousFilter = self.cigaretteScreenPoint(x: 180, y: 19)
            self.cigaretteWindow.setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
            let proposed = self.cigaretteWindow.frame.origin
            self.applyContact(previousTip: previousTip, previousFilter: previousFilter)
            self.keepCigaretteInsideScreen()
            let corrected = self.cigaretteWindow.frame.origin
            self.positionSmoke()
            if self.cigaretteMotionMode == .gravity {
                self.cigaretteBody.moveWhileHeld(to: self.cigaretteScreenPoint(x: 95, y: 19), angle: self.cigarette.rotationAngle)
            }
            self.handleAshDrag(distance: hypot(dragDelta.x, dragDelta.y), motion: motion)
            return NSPoint(x: corrected.x - proposed.x, y: corrected.y - proposed.y)
        }
        cigarette.onDragFinished = { [weak self] in
            guard let self else { return }
            self.ashShedDuringDrag = false; self.ashDragDistance = 0
            let modelCenter = self.cigaretteWindow.convertPoint(toScreen: self.cigarette.convert(self.cigarette.canvasPoint(NSPoint(x: 95, y: 19)), to: nil))
            let modelScale = self.cigaretteWindow.frame.width / 220
            let pack = self.sourceBoxView ?? (self.isChild ? self.sharedBoxView : self.boxView)
            let owner = self.parentSession ?? self
            let buttCenter = self.cigaretteScreenPoint(x: (self.cigarette.smokeTipX + 180) / 2, y: 19)
            if self.cigarette.canRecycleButt,
               owner.recoveryBag?.opening?.crosses(from: buttCenter, to: buttCenter) == true {
                self.recycleCigaretteButt()
                if !self.cigaretteExists { return }
            }
            let pristine = !self.hasLitCigarette && self.burn.progress <= 0.001 && self.burn.ash <= 0.001 && self.cigarette.tipCompression <= 0.001
            if pristine, pack?.insertCigarette(at: modelCenter, angle: self.cigarette.rotationAngle, scale: modelScale) == true {
                self.deactivateCigarette()
                return
            }
            if self.cigaretteMotionMode == .gravity {
                self.ashtrayAttachment = nil
                self.releaseCigarettePhysics(with: self.lastCigaretteDragVelocity)
            } else {
                self.updateAshtrayAttachmentAfterDrag()
            }
            self.resetContactTracking(); self.keepCigaretteInsideScreen(); self.savePosition()
            self.lastCigaretteDragVelocity = .zero
        }
        cigarette.onRotate = { [weak self] angle, pivot, anchor in
            guard let self else { return }
            let previousTip = self.cigaretteScreenPoint(x: self.cigarette.smokeTipX, y: 19)
            let previousFilter = self.cigaretteScreenPoint(x: 180, y: 19)
            let now = CACurrentMediaTime()
            let angularVelocity = self.lastCigaretteAngleTime > 0
                ? (angle - self.lastCigaretteAngle) / max(1.0 / 240.0, now - self.lastCigaretteAngleTime) : 0
            self.lastAshInteraction = now
            self.lastCigaretteAngle = angle; self.lastCigaretteAngleTime = now
            self.cigarette.rotationAngle = angle
            if self.cigaretteMotionMode == .gravity {
                self.cigaretteBody.setAngle(angle, angularVelocity: angularVelocity)
            }
            let current = self.cigaretteScreenPoint(x: pivot.x, y: pivot.y)
            let origin = self.cigaretteWindow.frame.origin
            self.cigaretteWindow.setFrameOrigin(NSPoint(x: origin.x + anchor.x - current.x, y: origin.y + anchor.y - current.y))
            self.applyContact(previousTip: previousTip, previousFilter: previousFilter)
            self.keepCigaretteInsideScreen()
            self.positionSmoke()
        }
        cigarette.onPuff = { [weak self] point in
            guard let self else { return }
            self.smoke.puff(at: point, consumedBurnSeconds: self.inhaledBurnSeconds)
            self.inhaledBurnSeconds = 0
        }
        cigarette.onTapAsh = { [weak self] in self?.tapAsh() }
        cigarette.onAnimationTick = { [weak self] elapsed in self?.advanceBurn(elapsed) }
        cigarette.onInhaleChanged = { [weak self] inhaling in
            guard let self else { return }
            if inhaling { self.inhaledBurnSeconds = 0; self.inhaleReservoir = InhaleReservoir() }
            self.smoke.inhaling = inhaling
            self.cigarette.inhaleActive = inhaling
        }
        cigarette.onExtinguish = { [weak self] in self?.setLit(false) }
        if savedV3 == nil {
            // Migrate the old compact window origin to the rotation canvas.
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main {
                resizeCigarette(for: screen)
            }
            let scale = cigaretteWindow.frame.width / 220
            cigaretteWindow.setFrameOrigin(NSPoint(x: origin.x - 15 * scale, y: origin.y - 91 * scale))
        }
        if !isChild {
            ash.cigaretteSurfaces = { [weak self] in
                guard let self else { return [] }
                let cigaretteEdges = ([self] + self.additionalSessions).flatMap { $0.ashSurfacesOnCigarette() }
                let boxEdges = (self.boxWindow?.isVisible == true ? (self.boxView?.ashSurfaces() ?? []) : [])
                    + self.additionalDesktopObjects.values.filter { $0.kind == .cigaretteBox && $0.window.isVisible }.flatMap { $0.boxView?.ashSurfaces() ?? [] }
                let lighterEdges = (self.lighterWindow?.isVisible == true ? (self.lighterView?.landingSurfaces() ?? []) : [])
                    + self.additionalDesktopObjects.values.filter { $0.kind == .lighter && $0.window.isVisible }.flatMap { $0.lighterView?.landingSurfaces() ?? [] }
                return cigaretteEdges + boxEdges + lighterEdges
            }
            ash.ashtraySurfaces = { [weak self] in
                guard let self else { return [] }
                return (self.ashtrayWindow?.isVisible == true ? (self.ashtrayView?.ashSurfaces() ?? []) : [])
                    + self.additionalDesktopObjects.values.filter { $0.kind == .ashtray && $0.window.isVisible }.flatMap { $0.ashtrayView?.ashSurfaces() ?? [] }
            }
            ash.additionalWindowSurfaces = { [weak self] in
                guard let window = self?.inventoryWindow, window.isVisible else { return [] }
                let frame = window.frame
                let id = UInt32(truncatingIfNeeded: window.windowNumber)
                return [AshSurface(id: id, x: Double(frame.minX), y: Double(frame.maxY), width: Double(frame.width))]
            }
            ash.recoveryOpening = { [weak self] in self?.recoveryBag?.opening }
            ash.collectAsh = { [weak self] offered in self?.receiveRecoveryAsh(offered) ?? [:] }
            ash.storeInAshtray = { [weak self] particle in
                guard let self else { return false }
                if self.ashtrayWindow?.isVisible == true, self.ashtrayView?.storeAsh(particle) == true { return true }
                for object in self.additionalDesktopObjects.values where object.kind == .ashtray && object.window.isVisible {
                    if object.ashtrayView?.storeAsh(particle) == true { return true }
                }
                return false
            }
        }
        if !isChild { ash.updateDisplays() }
        ensureVisible(); keepCigaretteInsideScreen(); positionSmoke()
        if !isChild {
            let savedBox = UserDefaults.standard.dictionary(forKey: "cigaretteBoxPosition")
            let boxOrigin = NSPoint(x: savedBox?["x"] as? CGFloat ?? visibleFrame.maxX - 400,
                                    y: savedBox?["y"] as? CGFloat ?? visibleFrame.minY + 70)
            let window = panel(NSRect(origin: boxOrigin, size: NSSize(width: CigaretteBoxView.canvasSize, height: CigaretteBoxView.canvasSize)), free: true)
            let view = CigaretteBoxView(frame: NSRect(origin: .zero, size: NSSize(width: CigaretteBoxView.canvasSize, height: CigaretteBoxView.canvasSize)))
            let storedBoxStyleID = UserDefaults.standard.string(forKey: "cigaretteBoxStyleV1") ?? "user:zhonghua-classic"
            let migratedBoxStyleID = CigaretteBoxStyle.migratedPresetID(storedBoxStyleID)
            view.style = styleRegistry.cigaretteBoxes.first { $0.id == migratedBoxStyleID } ?? .default
            if storedBoxStyleID != migratedBoxStyleID {
                UserDefaults.standard.set(migratedBoxStyleID, forKey: "cigaretteBoxStyleV1")
            }
            view.cigaretteStyleResolver = { [weak self] box in
                self?.cigaretteStyleStore.style(for: box)
            }
            view.rotationAngle = UserDefaults.standard.double(forKey: "cigaretteBoxRotation")
            let modeWasChosen = UserDefaults.standard.bool(forKey: "cigaretteExtractionModeUserSelected")
            view.extractionMode = modeWasChosen
                ? (CigaretteExtractionMode(rawValue: UserDefaults.standard.string(forKey: "cigaretteExtractionMode") ?? "") ?? .oneToOne)
                : .oneToOne
            view.setStock(UserDefaults.standard.object(forKey: "cigaretteBoxRemaining") as? Int ?? CigaretteBoxView.defaultStock,
                          slots: UserDefaults.standard.array(forKey: "cigaretteBoxSlots") as? [Int])
            view.onMove = { [weak self, weak window] origin, delta in
                guard let self, let window else { return .zero }
                window.setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
                view.refreshCigaretteScale()
                let proposed = window.frame.origin
                self.keepBoxVisible(window)
                let actual = window.frame.origin
                return NSPoint(x: actual.x - proposed.x, y: actual.y - proposed.y)
            }
            view.onMoveFinished = { [weak self, weak window, weak view] in
                guard let self, let window, let view else { return }
                UserDefaults.standard.set(["x": window.frame.minX, "y": window.frame.minY], forKey: "cigaretteBoxPosition")
                if let id = self.primaryInventoryIDs[.cigaretteBox] {
                    InventoryStore.shared.updateTransform(id, transform: InventoryTransform(x: window.frame.minX, y: window.frame.minY, rotation: view.rotationAngle))
                }
            }
            view.onRotationChanged = { [weak self, weak window] angle in
                UserDefaults.standard.set(angle, forKey: "cigaretteBoxRotation")
                if let self, let window, let id = self.primaryInventoryIDs[.cigaretteBox] {
                    InventoryStore.shared.updateTransform(id, transform: InventoryTransform(x: window.frame.minX, y: window.frame.minY, rotation: angle))
                }
            }
            let keepArtworkVisible = { [weak self, weak window] in
                guard let self, let window else { return }
                self.keepBoxVisible(window)
            }
            view.onVisualBoundsChanged = keepArtworkVisible
            view.onInteractionFinished = keepArtworkVisible
            view.onCigaretteScale = { [weak self] point in self?.cigaretteScale(at: point) ?? 1 }
            view.refreshCigaretteScale()
            view.onExtractionModeChanged = { [weak self] mode in
                UserDefaults.standard.set(mode.rawValue, forKey: "cigaretteExtractionMode")
                UserDefaults.standard.set(true, forKey: "cigaretteExtractionModeUserSelected")
                self?.updateExtractionModeMenu(mode)
            }
            view.onInventoryChanged = { [weak self, weak view] count, slots in
                guard let self, let view else { return }
                UserDefaults.standard.set(count, forKey: "cigaretteBoxRemaining")
                UserDefaults.standard.set(slots, forKey: "cigaretteBoxSlots")
                if let id = self.primaryInventoryIDs[.cigaretteBox] {
                    InventoryStore.shared.updateState(id, state: view.inventoryState)
                }
            }
            view.onTakeCigarette = { [weak self] point, angle, scale, lit, duringDrag in
                self?.takeCigarette(at: point, angle: angle, scale: scale, lit: lit, duringDrag: duringDrag) ?? false
            }
            view.onExtractionBecameFree = { [weak self] pointer in
                guard let self, let session = self.lastTakenSession else { return }
                self.extractionSession = session
                session.beginExternalDrag(at: pointer)
            }
            view.onFreeCigaretteDrag = { [weak self] pointer in self?.extractionSession?.moveExternalDrag(to: pointer) }
            view.onFreeCigaretteDragFinished = { [weak self] in
                self?.extractionSession?.finishExternalDrag()
                self?.extractionSession = nil
            }
            view.onStoreInInventory = { [weak self] in self?.returnInventoryItem(.cigaretteBox) }
            window.contentView = view
            boxWindow = window; boxView = view
            keepBoxVisible(window)
            if cigaretteExists || !InventoryStore.shared.layout.items.contains(where: { $0.kind == .cigaretteBox && $0.location == .desktop }) { window.orderOut(nil) }
        }
        if !isChild {
            let saved = UserDefaults.standard.dictionary(forKey: "ashtrayPositionV1")
            let frame = NSRect(x: saved?["x"] as? CGFloat ?? visibleFrame.minX + 45,
                               y: saved?["y"] as? CGFloat ?? visibleFrame.minY + 55,
                               width: AshtrayView.canvasSize.width, height: AshtrayView.canvasSize.height)
            let window = panel(frame, free: true)
            // Keep the tray above the pack but below the cigarette, so a
            // cigarette can still be picked up when it visually overlaps it.
            window.level = .floating
            let view = AshtrayView(frame: NSRect(origin: .zero, size: AshtrayView.canvasSize))
            let savedAshtrayID = UserDefaults.standard.string(forKey: "ashtrayStyleV1")
            view.style = styleRegistry.ashtrays.first { $0.id == savedAshtrayID } ?? .default
            if !styleRegistry.ashtrays.contains(where: { $0.id == savedAshtrayID }) {
                UserDefaults.standard.set(view.style.id, forKey: "ashtrayStyleV1")
            }
            view.scale = UserDefaults.standard.object(forKey: "ashtrayScaleV1") as? Double ?? 1.0
            view.rotationAngle = UserDefaults.standard.double(forKey: "ashtrayRotationV1")
            window.contentView = view
            view.onMove = { [weak self, weak window] origin, delta in
                guard let self, let window else { return }
                window.setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
                self.keepAshtrayVisible(window)
                self.syncAshtrayAttachments()
            }
            view.onMoveFinished = { [weak self, weak window, weak view] in
                guard let self, let window, let view else { return }
                UserDefaults.standard.set(["x": window.frame.minX, "y": window.frame.minY], forKey: "ashtrayPositionV1")
                if let id = self.primaryInventoryIDs[.ashtray] {
                    InventoryStore.shared.updateTransform(id, transform: InventoryTransform(x: window.frame.minX, y: window.frame.minY, rotation: view.rotationAngle))
                }
            }
            view.onRotationChanged = { [weak self] angle in
                UserDefaults.standard.set(angle, forKey: "ashtrayRotationV1")
                guard let self else { return }
                if let window = self.ashtrayWindow {
                    self.keepAshtrayVisible(window)
                    if let id = self.primaryInventoryIDs[.ashtray] {
                        self.recordInventoryTransform(id, window: window, rotation: angle)
                    }
                }
                self.syncAshtrayAttachments()
            }
            configureRecoveryTray(view)
            view.onAshSpilled = { [weak self] particles in
                self?.ash.scatterFromAshtray(particles, impulse: .zero)
            }
            view.onDumpAsh = { [weak self, weak view] in
                guard let self, let view else { return }
                let angle = view.rotationAngle
                self.ash.scatterFromAshtray(view.ejectStoredAsh(), impulse: NSPoint(x: sin(angle) * 82, y: -cos(angle) * 82))
            }
            view.onClearAsh = { [weak view] in view?.clearAsh() }
            view.onStoreInInventory = { [weak self] in self?.returnInventoryItem(.ashtray) }
            ashtrayWindow = window; ashtrayView = view
            keepAshtrayVisible(window)
            if visible && InventoryStore.shared.layout.items.contains(where: { $0.kind == .ashtray && $0.location == .desktop }) { window.orderFrontRegardless() }
        }
        if !isChild {
            let saved = UserDefaults.standard.dictionary(forKey: "lighterPositionV1")
            let frame = NSRect(x: (saved?["x"] as? CGFloat ?? visibleFrame.midX - 135) - LighterView.canvasPadding,
                               y: (saved?["y"] as? CGFloat ?? visibleFrame.minY + 145) - LighterView.canvasPadding,
                               width: LighterView.canvasSize.width, height: LighterView.canvasSize.height)
            let window = panel(frame, free: true)
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
            let view = LighterView(frame: NSRect(origin: .zero, size: LighterView.canvasSize))
            let selectedID = UserDefaults.standard.string(forKey: "lighterStyleV1")
            view.style = styleRegistry.lighters.first { $0.id == selectedID } ?? .default
            view.rotationAngle = UserDefaults.standard.double(forKey: "lighterRotationV1")
            window.contentView = view
            view.onMove = { [weak self, weak window] origin, delta in
                guard let self, let window else { return .zero }
                window.setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
                let proposed = window.frame.origin
                self.keepLighterVisible(window)
                let actual = window.frame.origin
                return NSPoint(x: actual.x - proposed.x, y: actual.y - proposed.y)
            }
            view.onMoveFinished = { [weak self, weak window, weak view] in
                guard let self, let window, let view else { return }
                UserDefaults.standard.set(["x": window.frame.minX + LighterView.canvasPadding, "y": window.frame.minY + LighterView.canvasPadding], forKey: "lighterPositionV1")
                if let id = self.primaryInventoryIDs[.lighter] {
                    InventoryStore.shared.updateTransform(id, transform: InventoryTransform(x: window.frame.minX, y: window.frame.minY, rotation: view.rotationAngle))
                }
            }
            view.onRotationChanged = { [weak self, weak window] angle in
                UserDefaults.standard.set(angle, forKey: "lighterRotationV1")
                if let self, let window {
                    self.keepLighterVisible(window)
                    if let id = self.primaryInventoryIDs[.lighter] {
                        InventoryStore.shared.updateTransform(id, transform: InventoryTransform(x: window.frame.minX, y: window.frame.minY, rotation: angle))
                    }
                }
            }
            view.onIgnitionChanged = { [weak self] burning in
                if !burning { self?.lighterIgnitionLatched = false }
            }
            view.onInventoryStateChanged = { [weak self, weak view] in
                guard let self, let view, let id = self.primaryInventoryIDs[.lighter] else { return }
                InventoryStore.shared.updateState(id, state: view.inventoryState)
            }
            view.onStoreInInventory = { [weak self] in self?.returnInventoryItem(.lighter) }
            lighterWindow = window; lighterView = view
            keepLighterVisible(window)
            if visible && InventoryStore.shared.layout.items.contains(where: { $0.kind == .lighter && $0.location == .desktop }) { window.orderFrontRegardless() }
        }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateCigaretteHitTesting() }
        }
        RunLoop.main.add(timer, forMode: .common); hitTestTimer = timer
        updateCigaretteHitTesting()
        if cigaretteExists {
            smokeDisplays.values.forEach { $0.window.orderFrontRegardless(); $0.view.burning = lit }
            cigaretteWindow.orderFrontRegardless(); cigarette.setAnimating(true)
        } else {
            smokeDisplays.values.forEach { $0.window.orderOut(nil); $0.view.burning = false; $0.view.emits = false }
        }
        for item in InventoryStore.shared.layout.items where item.location == .desktop {
            deployInventoryItem(item, restoring: true)
        }
        return true
    }
    private func migrateAshtrayScalePreference() {
        let defaults = UserDefaults.standard
        let migrationKey = "ashtrayScaleRebasedV2"
        guard !defaults.bool(forKey: migrationKey) else { return }
        let previousScale = defaults.object(forKey: "ashtrayScaleV1") as? Double
        let rebasedScale = previousScale.map { min(2.0, max(0.5, $0 / 1.5)) } ?? 1.0
        defaults.set(rebasedScale, forKey: "ashtrayScaleV1")
        defaults.set(true, forKey: migrationKey)
    }
    private func advanceBurn(_ elapsed: Double) {
        guard visible && cigaretteExists else { return }
        let activeSeconds = smoke.inhaling ? inhaleReservoir.take(seconds: elapsed, multiplier: inhaleMultiplier) : 0
        if activeSeconds > 0 {
            lastAshInteraction = CACurrentMediaTime()
            let previousProgress = burn.progress
            burn.advance(seconds: activeSeconds, inhaling: true, inhaleMultiplier: inhaleMultiplier)
            inhaledBurnSeconds += (burn.progress - previousProgress) * CigaretteBurn.idleDuration
        }
        if lit { burn.advance(seconds: max(0, elapsed - activeSeconds), inhaling: false) }
        if burn.isFinished && countsTowardRank && InventoryStore.shared.completeCigarette(fromBoxStyleID: sourceBoxView?.style.id) { countsTowardRank = false }
        if inhaleReservoir.isFull || burn.isFinished {
            smoke.inhaling = false; cigarette.inhaleActive = false
        }
        cigarette.burnProgress = burn.progress; cigarette.finished = burn.isFinished
        let now = CACurrentMediaTime()
        // Holding the filter to inhale doesn't shake the cigarette.
        let canDropClump = activeSeconds > 0 || (!cigarette.isInteracting && now - lastAshInteraction >= 1.5)
        if canDropClump {
            let automaticAsh = burn.shedAshIfFull()
            if automaticAsh > 0 {
                shedAsh(amount: automaticAsh, motion: .zero, style: .natural)
                lastAshFall = now
            }
        }
        if burn.isFinished && lit {
            let remaining = burn.shedAsh(all: true)
            if remaining > 0 { shedAsh(amount: remaining, motion: .zero, style: .disturbed) }
            setLit(false)
        }
        cigarette.ashLevel = burn.ash
        positionSmoke()
    }
    private func handleAshDrag(distance: CGFloat, motion: NSPoint) {
        lastAshInteraction = CACurrentMediaTime()
        guard !ashShedDuringDrag else { return }
        guard burn.ash >= 0.08 else { ashDragDistance = 0; return }
        ashDragDistance += distance
        let speed = hypot(motion.x, motion.y)
        let now = CACurrentMediaTime()
        let threshold: CGFloat = speed >= 900 ? 7 : 15
        guard ashDragDistance >= threshold, now - lastAshFall > 0.12 else { return }
        let fastness = min(1, max(0, (speed - 220) / 1080))
        let amount = burn.shedAsh(all: burn.ash >= 1, fraction: 0.22 + fastness * 0.68)
        guard amount > 0 else { return }
        ashShedDuringDrag = true
        cigarette.ashLevel = burn.ash
        lastAshFall = now
        ashDragDistance = 0
        shedAsh(amount: amount, motion: motion)
    }
    private func shedAsh(amount: Double, motion: NSPoint, style: AshOverlay.FallStyle = .disturbed) {
        let remainingLength = AshGeometry.capLength(level: burn.ash)
        let detachedLength = AshGeometry.capLength(level: amount)
        let centerX = cigarette.smokeTipX - 4 - remainingLength - detachedLength / 2
        let center = cigaretteScreenPoint(x: centerX, y: 19)
        let scale = cigaretteWindow.frame.width / 220
        ash.shed(at: center, amount: amount, motion: motion, scale: scale, orientation: cigarette.tipWorldAngle,
                 style: style, recoveryMass: ashMass(for: amount))
    }

    private func ashMass(for amount: Double) -> Int {
        let before = Int(detachedAshMass)
        detachedAshMass += max(0, amount) * 3 * Double(RecoveryMaterial.legacyMassPerUnit)
        return Int(detachedAshMass) - before
    }

    private func tapAsh() {
        lastAshInteraction = CACurrentMediaTime()
        // Let the accumulated cap remain visibly attached for a beat before
        // it becomes a cohesive falling clump, then keep the existing fall.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            let amount = self.burn.shedAsh(all: true)
            guard amount > 0 else { return }
            self.cigarette.ashLevel = self.burn.ash
            self.shedAsh(amount: amount, motion: .zero, style: .tapped)
            self.lastAshFall = CACurrentMediaTime()
        }
    }
    private func newCigarette() {
        detachedAshMass = 0
        lastAshInteraction = CACurrentMediaTime()
        hasLitCigarette = false
        cigarette.canRecycleButt = false
        cigarette.cancel(); resetContactTracking(); burn = CigaretteBurn(); cigarette.burnProgress = 0; cigarette.ashLevel = 0; cigarette.finished = false
        lit = false; cigarette.lit = false; cigarette.clearTipDamage(); cigarette.filterCompression = 0
        // Keep the replacement tip on the existing smoke display near screen seams.
        let frame = smokeWindow.frame
        var origin = cigaretteWindow.frame.origin
        let tip = cigarette.convert(cigarette.canvasPoint(NSPoint(x: cigarette.smokeTipX, y: 19)), to: nil)
        origin.x = min(max(origin.x, frame.minX + 1 - tip.x), frame.maxX - 1 - tip.x)
        origin.y = min(max(origin.y, frame.minY + 1 - tip.y), frame.maxY - 1 - tip.y)
        cigaretteWindow.setFrameOrigin(origin)
        keepCigaretteInsideScreen()
        positionSmoke(); smokeDisplays.values.forEach { $0.view.burning = false }
    }
    private func panel(_ rect: NSRect, free: Bool = false) -> NSPanel {
        let panel = free ? EdgeToEdgeDesktopPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false) : NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false
        return panel
    }
    private func displayID(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    private func makeSmokeDisplay(for screen: NSScreen) -> (window: NSPanel, view: SmokeView)? {
        let window = panel(screen.frame); window.ignoresMouseEvents = true
        guard let view = SmokeView(smokeFrame: NSRect(origin: .zero, size: screen.frame.size)) else { return nil }
        window.contentView = view; view.emits = false
        view.energySaving = UserDefaults.standard.bool(forKey: "energySaving")
        view.cloudVariation = UserDefaults.standard.object(forKey: "smokeCloudVariation") as? Bool ?? false
        configureSmoke(view, for: cigaretteStyle)
        view.amount = SmokeAmount(rawValue: UserDefaults.standard.string(forKey: "smokeAmount") ?? "") ?? .standard
        view.dissipation = SmokeDissipation(rawValue: UserDefaults.standard.string(forKey: "smokeDissipation") ?? "") ?? .normal
        return (window, view)
    }
    private func syncSmokeDisplays() {
        let screens = NSScreen.screens
        let ids = Set(screens.map(displayID))
        for id in Array(smokeDisplays.keys) where !ids.contains(id) {
            smokeDisplays[id]?.view.pauseAndClear(); smokeDisplays[id]?.window.orderOut(nil); smokeDisplays.removeValue(forKey: id)
        }
        for screen in screens {
            let id = displayID(screen)
            if let entry = smokeDisplays[id] {
                if entry.window.frame != screen.frame { entry.window.setFrame(screen.frame, display: true) }
            } else if let entry = makeSmokeDisplay(for: screen) {
                smokeDisplays[id] = entry
                if lit && !burn.isFinished { entry.view.burning = true }
                if visible && cigaretteWindow != nil { entry.window.orderFrontRegardless() }
            }
        }
        updateSmokeWindowLevel()
    }
    private func updateSmokeWindowLevel() {
        let behind = UserDefaults.standard.bool(forKey: "smokeBehindWindows")
        let desktopIcons = Int(CGWindowLevelForKey(.desktopIconWindow))
        let foreground = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 4)
        for entry in smokeDisplays.values {
            // In foreground mode, sit above the cigarette, lighter, ashtray, inventory, and ash overlays.
            entry.window.level = behind ? NSWindow.Level(rawValue: desktopIcons - 1) : foreground
        }
    }
    private func setLit(_ value: Bool, cancelGesture: Bool = true) {
        guard !value || !burn.isFinished else { return }
        if cancelGesture { cigarette.cancel(); resetContactTracking() }
        lighterIgnitionLatched = false
        lighterTipHeat = 0
        cigarette.preheat = 0
        if value { hasLitCigarette = true }
        cigarette.canRecycleButt = hasLitCigarette && !value
        lit = value; cigarette.lit = value; cigarette.inhaleActive = false
        smokeDisplays.values.forEach { $0.view.inhaling = false; $0.view.burning = value }
    }

    private func configureSmoke(_ view: SmokeView, for style: CigaretteStyle?) {
        view.cigaretteEmissionMultiplier = Float(style?.manifest.smoke.emissionMultiplier ?? 1)
        view.cigaretteDiameterMultiplier = Float(style?.diameterScale ?? 1)
        if let rgb = UserDefaults.standard.array(forKey: "smokeTintRGB") as? [Double], rgb.count == 3 {
            view.colorTint = SIMD4(Float(rgb[0]), Float(rgb[1]), Float(rgb[2]), 1)
        } else if let style, style.manifest.smoke.colorMode == .custom {
            let raw = UInt32(style.manifest.smoke.color.dropFirst(), radix: 16) ?? 0xC7CDD2
            view.colorTint = SIMD4(Float((raw >> 16) & 0xff) / 255, Float((raw >> 8) & 0xff) / 255, Float(raw & 0xff) / 255, 1)
        } else {
            view.colorTint = SIMD4(1, 1, 1, 0)
        }
    }

    private func applyCigaretteStyle(_ style: CigaretteStyle) {
        cigaretteStyle = style
        cigarette?.cigaretteStyle = style
        smokeDisplays.values.forEach { configureSmoke($0.view, for: style) }
    }

    private func boxCigaretteStyleOverrides() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: "cigaretteStyleByBoxV1") as? [String: String] ?? [:]
    }

    private func styleForCurrentBox(_ sourceBox: CigaretteBoxView? = nil) -> CigaretteStyle {
        guard let box = sourceBox ?? boxView else { return cigaretteStyleStore.defaultStyle }
        return cigaretteStyleStore.style(for: box.style)
    }
    private func resetContactTracking() {
        tipContactActive = false; filterContactActive = false
        ashtrayFloorContactActive = false; contactPointer = nil
        cigarette?.setTipPressure(0)
    }
    private func boundaries() -> [CigaretteBoundary] {
        let radius = 8 * cigaretteWindow.frame.width / 220 + 3
        return NSScreen.screens.map { CigaretteBoundary(frame: $0.frame, usableTop: $0.visibleFrame.maxY - radius) }
    }
    private func applyContact(previousTip: NSPoint, previousFilter: NSPoint) {
        guard cigaretteExists else { return }
        let now = CACurrentMediaTime()
        let pointer = NSEvent.mouseLocation
        let previousPointer = contactPointer ?? cigarette.interactionStart
        let lastTime = contactPointer == nil ? cigarette.interactionStartTime : contactPointerTime
        let elapsed = min(0.15, max(1.0 / 120.0, now - lastTime))
        let motion = MotionSample(dx: pointer.x - previousPointer.x, dy: pointer.y - previousPointer.y, dt: elapsed, maximumSpeed: 1600)
        contactPointer = pointer; contactPointerTime = now
        let speed = hypot(motion.velocityX, motion.velocityY)
        let result = CigaretteContact.resolve(tip: cigaretteScreenPoint(x: cigarette.smokeTipX, y: 19),
            filter: cigaretteScreenPoint(x: 180, y: 19), previousTip: previousTip, previousFilter: previousFilter,
            screens: boundaries(), obstacles: [])
        if result.correction != .zero {
            let origin = cigaretteWindow.frame.origin
            cigaretteWindow.setFrameOrigin(NSPoint(x: origin.x + result.correction.x, y: origin.y + result.correction.y))
        }
        let currentTip = cigaretteScreenPoint(x: cigarette.smokeTipX, y: 19)
        let trayHit = activeAshtrayTargets().compactMap { target -> (UUID?, AshtrayView, AshtrayRimContact)? in
            guard let contact = target.1.basinFloorContact(from: previousTip, to: currentTip) else { return nil }
            return (target.0, target.1, contact)
        }.first
        let trayFloor = trayHit?.2
        if let trayFloor {
            let origin = cigaretteWindow.frame.origin
            cigaretteWindow.setFrameOrigin(NSPoint(x: origin.x + trayFloor.correction.x,
                                                   y: origin.y + trayFloor.correction.y))
        }
        let newImpact = result.tipContact && !tipContactActive
        let angle = cigarette.rotationAngle
        let localNormal = -sin(angle) * result.correction.x + cos(angle) * result.correction.y
        let localTangent = cos(angle) * result.correction.x + sin(angle) * result.correction.y
        let correctionLength = max(0.001, hypot(result.correction.x, result.correction.y))
        if newImpact {
            // Permanent crush folds model a lit cigarette being pinched out.
            // An unlit cigarette can still collide and be repositioned, but
            // must not acquire a charred/crushed shape that cannot burn away.
            if lit {
                let compression = CGFloat(CigaretteImpact.compression(current: Double(cigarette.tipCompression), speed: speed, pressure: result.pressure))
                let direction: CGFloat = localNormal > 0.01 ? -1 : 1
                cigarette.applyImpact(at: cigarette.smokeTipX, compression: compression, direction: direction, speed: speed,
                                      pressure: result.pressure, obliqueness: abs(localTangent) / correctionLength,
                                      gripX: cigarette.interactionAnchorX)
                // Keep the tip inside the reachable display area while its material compresses.
                let adjusted = CigaretteContact.resolve(tip: cigaretteScreenPoint(x: cigarette.smokeTipX, y: 19),
                    filter: cigaretteScreenPoint(x: 180, y: 19), previousTip: previousTip, previousFilter: previousFilter,
                    screens: boundaries(), obstacles: [])
                if adjusted.correction != .zero {
                    let origin = cigaretteWindow.frame.origin
                    cigaretteWindow.setFrameOrigin(NSPoint(x: origin.x + adjusted.correction.x, y: origin.y + adjusted.correction.y))
                }
            }
            if result.tipContact && lit {
                let fallen = burn.shedAshForCrush(); cigarette.ashLevel = burn.ash
                let centerX = cigarette.smokeTipX - 4 - AshGeometry.capLength(level: fallen) / 2
                let point = cigaretteScreenPoint(x: centerX, y: 19)
                let scale = cigaretteWindow.frame.width / 220
                ash.crush(at: point, ashAmount: fallen, motion: NSPoint(x: motion.velocityX, y: motion.velocityY), scale: scale, orientation: cigarette.tipWorldAngle, recoveryMass: ashMass(for: fallen))
                lastAshFall = now
                setLit(false, cancelGesture: false)
            }
        }
        if result.tipContact {
            let pressure = max(0.15, result.pressure)
            cigarette.setTipPressure(CGFloat(pressure))
        } else {
            cigarette.setTipPressure(0)
        }
        if lit && result.filterContact && !filterContactActive {
            cigarette.filterCompression = CGFloat(CigaretteImpact.compression(current: Double(cigarette.filterCompression), speed: speed, pressure: result.pressure))
        }
        tipContactActive = result.tipContact; filterContactActive = result.filterContact
        let tip = cigaretteScreenPoint(x: cigarette.smokeTipX, y: 19)
        let touchesAshtray = activeAshtrayTargets().contains { $0.1.containsBasin(screenPoint: tip) }
        if trayFloor != nil && !ashtrayFloorContactActive {
            let impactSpeed = hypot(motion.velocityX, motion.velocityY)
            if lit {
                let compression = CGFloat(CigaretteImpact.compression(current: Double(cigarette.tipCompression), speed: impactSpeed, pressure: 1))
                cigarette.applyImpact(at: cigarette.smokeTipX, compression: compression, speed: impactSpeed,
                                      pressure: 1, obliqueness: 0.25, gripX: cigarette.interactionAnchorX)
                let fallen = burn.shedAshForCrush(); cigarette.ashLevel = burn.ash
                trayHit?.1.depositCrushedAsh(at: trayFloor?.point ?? tip, amount: fallen,
                                             scale: cigaretteWindow.frame.width / 220,
                                             recoveryMass: ashMass(for: fallen))
                setLit(false, cancelGesture: false)
                lastAshFall = now
            }
        }
        if trayFloor != nil { ashtrayFloorContactActive = true }
        if !touchesAshtray { ashtrayFloorContactActive = false }
    }
    private func activeAshtrayTargets() -> [(UUID?, AshtrayView, NSPanel)] {
        let owner = parentSession ?? self
        var targets: [(UUID?, AshtrayView, NSPanel)] = []
        if let view = owner.ashtrayView, let window = owner.ashtrayWindow, window.isVisible {
            targets.append((owner.primaryInventoryIDs[.ashtray], view, window))
        }
        for object in owner.additionalDesktopObjects.values where object.kind == .ashtray && object.window.isVisible {
            if let view = object.ashtrayView { targets.append((object.id, view, object.window)) }
        }
        return targets
    }
    private func keepCigaretteInsideScreen() {
        guard !cigarette.isInteracting, !NSScreen.screens.isEmpty else { return }
        let center = cigaretteScreenPoint(x: 95, y: 19)
        if NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -12, dy: -12).contains(center) }) { return }
        let nearest = NSScreen.screens.map { screen -> NSPoint in
            NSPoint(x: min(max(center.x, screen.frame.minX + 12), screen.frame.maxX - 12),
                    y: min(max(center.y, screen.frame.minY + 12), screen.frame.maxY - 12))
        }.min { hypot($0.x - center.x, $0.y - center.y) < hypot($1.x - center.x, $1.y - center.y) }
        guard let nearest else { return }
        let correction = NSPoint(x: nearest.x - center.x, y: nearest.y - center.y)
        if correction != .zero {
            let origin = cigaretteWindow.frame.origin
            cigaretteWindow.setFrameOrigin(NSPoint(x: origin.x + correction.x, y: origin.y + correction.y))
        }
    }
    private func changeCigaretteMotionMode(_ mode: CigaretteMotionMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "cigaretteMotionModeV1")
        for session in [self] + additionalSessions { session.applyCigaretteMotionMode(mode) }
    }
    private func applyCigaretteMotionMode(_ mode: CigaretteMotionMode) {
        cigaretteMotionMode = mode
        cigarettePhysicsTimer?.invalidate(); cigarettePhysicsTimer = nil
        if mode == .gravity { ashtrayAttachment = nil }
        guard mode == .gravity, cigaretteExists else { return }
        cigaretteBody.reset(center: cigaretteScreenPoint(x: 95, y: 19), angle: cigarette.rotationAngle)
        startCigarettePhysics()
    }
    private func releaseCigarettePhysics(with velocity: NSPoint) {
        guard cigaretteMotionMode == .gravity, cigaretteExists else { return }
        cigaretteBody.moveWhileHeld(to: cigaretteScreenPoint(x: 95, y: 19), angle: cigarette.rotationAngle)
        cigaretteBody.release(with: velocity, angularVelocity: cigaretteBody.angularVelocity)
        lastCigaretteDragVelocity = .zero
        startCigarettePhysics()
    }
    private func startCigarettePhysics() {
        guard cigaretteMotionMode == .gravity, cigaretteExists, visible, cigarettePhysicsTimer == nil else { return }
        cigarettePhysicsLastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceCigarettePhysics() }
        }
        cigarettePhysicsTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func advanceCigarettePhysics() {
        guard cigaretteMotionMode == .gravity, cigaretteExists, visible,
              !cigarette.isInteracting, !externallyDragging else {
            cigarettePhysicsLastTick = CACurrentMediaTime()
            return
        }
        let now = CACurrentMediaTime()
        let dt = min(0.05, max(1.0 / 240.0, now - cigarettePhysicsLastTick))
        cigarettePhysicsLastTick = now
        let center = cigaretteScreenPoint(x: 95, y: 19)
        let tip = cigaretteScreenPoint(x: cigarette.smokeTipX, y: 19)
        let filter = cigaretteScreenPoint(x: 180, y: 19)
        let halfLength = hypot(filter.x - tip.x, filter.y - tip.y) * 0.5
        let radius = 4.5 * cigaretteWindow.frame.width / 220
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
        guard let screen else { return }
        let floor = AshSurface(id: 0x7f000001, x: screen.frame.minX, y: screen.frame.minY,
                               width: screen.frame.width, groupID: 0x7f000001)
        var surfaces = currentCigaretteLandingSurfaces()
        for (index, display) in NSScreen.screens.enumerated() where display != screen {
            surfaces.append(AshSurface(id: 0x7f100000 &+ UInt32(index), x: display.frame.minX,
                                       y: display.frame.minY, width: display.frame.width,
                                       groupID: 0x7f100000 &+ UInt32(index)))
        }
        var motionBounds = screen.frame
        for adjacent in NSScreen.screens where adjacent != screen {
            let verticalOverlap = center.y >= max(screen.frame.minY, adjacent.frame.minY)
                && center.y <= min(screen.frame.maxY, adjacent.frame.maxY)
            guard verticalOverlap else { continue }
            if abs(screen.frame.maxX - adjacent.frame.minX) < 2 {
                motionBounds.size.width = max(motionBounds.maxX, adjacent.frame.maxX) - motionBounds.minX
            } else if abs(adjacent.frame.maxX - screen.frame.minX) < 2 {
                let newMinX = min(motionBounds.minX, adjacent.frame.minX)
                motionBounds.size.width = motionBounds.maxX - newMinX
                motionBounds.origin.x = newMinX
            }
        }
        let landed = cigaretteBody.advance(dt: dt, halfLength: halfLength, radius: radius,
                                           surfaces: surfaces, screenFloor: floor,
                                           screenBounds: motionBounds)
        let targetCenter = cigaretteBody.center
        let targetAngle = cigaretteBody.angle
        if abs(targetAngle - cigarette.rotationAngle) > 0.0005 { cigarette.rotationAngle = targetAngle }
        lastCigaretteAngle = targetAngle; lastCigaretteAngleTime = now
        let delta = NSPoint(x: targetCenter.x - center.x, y: targetCenter.y - center.y)
        if hypot(delta.x, delta.y) > 0.01 {
            let origin = cigaretteWindow.frame.origin
            cigaretteWindow.setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
            positionSmoke()
        }
        if landed { savePosition() }
    }
    private func currentCigaretteLandingSurfaces() -> [AshSurface] {
        let owner = parentSession ?? self
        let ashtraySurfaces = owner.ashtrayWindow?.isVisible == true ? (owner.ashtrayView?.ashSurfaces() ?? []) : []
        let boxSurfaces = owner.boxWindow?.isVisible == true ? (owner.boxView?.ashSurfaces() ?? []) : []
        let lighterSurfaces = owner.lighterWindow?.isVisible == true ? (owner.lighterView?.landingSurfaces() ?? []) : []
        let extras = owner.additionalDesktopObjects.values.filter { $0.window.isVisible }
        var surfaces = ashtraySurfaces + boxSurfaces + lighterSurfaces
        surfaces += extras.flatMap { $0.boxView?.ashSurfaces() ?? [] }
        surfaces += extras.flatMap { $0.lighterView?.landingSurfaces() ?? [] }
        surfaces += extras.flatMap { $0.ashtrayView?.ashSurfaces() ?? [] }
        for session in [owner] + owner.additionalSessions where session !== self {
            surfaces += session.ashSurfacesOnCigarette()
        }
        surfaces += owner.currentWindowLandingSurfaces()
        return surfaces
    }
    private func currentWindowLandingSurfaces() -> [AshSurface] {
        let now = CACurrentMediaTime()
        guard now - windowSurfacesRefreshTime >= 0.12 else { return cachedWindowSurfaces }
        windowSurfacesRefreshTime = now
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            cachedWindowSurfaces = []
            return []
        }
        let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)
        let mainScreenTop = NSScreen.main?.frame.maxY ?? NSScreen.screens.map(\.frame.maxY).max() ?? 0
        var result: [AshSurface] = []
        for windowInfo in windows {
            let owner = windowInfo[kCGWindowOwnerName as String] as? String ?? ""
            let pid = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
            let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard pid != currentPID, let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary else { continue }
            var quartzBounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary as CFDictionary, &quartzBounds),
                  quartzBounds.width >= 100, quartzBounds.height >= 36 else { continue }
            guard owner == "Dock" || (layer == 0 && alpha >= 0.65) else { continue }
            let identifier = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            let appKitTop = mainScreenTop - quartzBounds.minY
            result.append(AshSurface(id: identifier, x: quartzBounds.minX, y: appKitTop,
                                     width: quartzBounds.width, groupID: identifier))
        }
        cachedWindowSurfaces = result
        return result
    }
    private func cigaretteArtworkBounds() -> NSRect {
        let left = cigarette.smokeTipX - 4 - CGFloat(AshGeometry.capLength(level: burn.ash)) - 1
        let right: CGFloat = 182
        let count = max(1, Int((right - left) / 1))
        var points: [NSPoint] = []
        var samples = (0...count).map { left + (right - left) * CGFloat($0) / CGFloat(count) }
        samples.append(contentsOf: cigarette.impactFoldHingePositions.filter { $0 >= left && $0 <= right })
        for x in samples {
            for y: CGFloat in [11, 19, 27] {
                points.append(cigaretteScreenPoint(x: x, y: y))
            }
        }
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    private func savePosition() {
        guard !isChild && cigaretteExists else { return }
        UserDefaults.standard.set(["x": cigaretteWindow.frame.minX, "y": cigaretteWindow.frame.minY], forKey: "cigarettePositionV3")
        UserDefaults.standard.set(cigarette.rotationAngle, forKey: "cigaretteRotation")
    }
    private func updateCigaretteHitTesting() {
        if visible, let window = recoveryBagWindow, let bag = recoveryBag {
            let local = bag.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            window.ignoresMouseEvents = !bag.isDragging && bag.hitTest(local) == nil
        }
        if visible, let boxWindow, let boxView {
            if boxView.isInteracting { boxWindow.ignoresMouseEvents = false }
            else {
                let inWindow = boxWindow.convertPoint(fromScreen: NSEvent.mouseLocation)
                let inView = boxView.convert(inWindow, from: nil)
                boxWindow.ignoresMouseEvents = !boxView.containsBox(inView)
            }
        }
        if visible, let lighterWindow, let lighterView {
            if lighterView.isInteracting { lighterWindow.ignoresMouseEvents = false }
            else {
                let inWindow = lighterWindow.convertPoint(fromScreen: NSEvent.mouseLocation)
                lighterWindow.ignoresMouseEvents = !lighterView.containsLighter(lighterView.convert(inWindow, from: nil))
            }
        }
        if visible {
            for object in additionalDesktopObjects.values {
                guard let view = object.lighterView else { continue }
                if view.isInteracting { object.window.ignoresMouseEvents = false }
                else {
                    let inWindow = object.window.convertPoint(fromScreen: NSEvent.mouseLocation)
                    object.window.ignoresMouseEvents = !view.containsLighter(view.convert(inWindow, from: nil))
                }
            }
            for object in additionalDesktopObjects.values where object.kind == .cigaretteBox {
                guard let view = object.boxView else { continue }
                if view.isInteracting { object.window.ignoresMouseEvents = false }
                else {
                    let inWindow = object.window.convertPoint(fromScreen: NSEvent.mouseLocation)
                    object.window.ignoresMouseEvents = !view.containsBox(view.convert(inWindow, from: nil))
                }
            }
        }
        if !isChild {
            let flames = ([lighterWindow?.isVisible == true ? lighterView : nil]
                          + additionalDesktopObjects.values.compactMap { $0.window.isVisible ? $0.lighterView : nil })
                .compactMap { $0 }
            for session in [self] + additionalSessions {
                let tip = session.cigaretteScreenPoint(x: session.cigarette.smokeTipX, y: 19)
                let body = session.cigaretteScreenPoint(x: min(182, session.cigarette.smokeTipX + 12), y: 19)
                let contacting = flames.first { $0.flameIntersectsScreenSegment(tip, body) || $0.flameContainsScreenPoint(tip) }
                session.updateLighterFlameContact(using: contacting)
            }
            for flame in flames { updateLighterObstructions(using: flame) }
        }
        guard visible && cigaretteExists, let cigarette, let cigaretteWindow else { return }
        if cigarette.isInteracting { cigaretteWindow.ignoresMouseEvents = false; return }
        let inWindow = cigaretteWindow.convertPoint(fromScreen: NSEvent.mouseLocation)
        let inView = cigarette.convert(inWindow, from: nil)
        cigaretteWindow.ignoresMouseEvents = !cigarette.containsCigarette(inView)
    }
    private func updateLighterFlameContact(using lighterView: LighterView?) {
        guard visible, cigaretteExists, let lighterView else {
            lighterIgnitionLatched = false
            setLighterSoot(source: nil, intensity: 0)
            let now = CACurrentMediaTime()
            let dt = min(0.08, max(0, now - lighterHeatTick)); lighterHeatTick = now
            lighterTipHeat = max(0, lighterTipHeat - dt * 0.62)
            cigarette?.preheat = CGFloat(lighterTipHeat)
            lighterHeatTick = CACurrentMediaTime()
            return
        }
        let now = CACurrentMediaTime()
        let dt = min(0.08, max(0, now - lighterHeatTick)); lighterHeatTick = now
        let tip = cigaretteScreenPoint(x: cigarette.smokeTipX, y: 19)
        let body = cigaretteScreenPoint(x: min(182, cigarette.smokeTipX + 12), y: 19)
        let bodyTouchesFlame = lighterView.flameIntersectsScreenSegment(tip, body)
        let heat = lighterView.flameContainsScreenPoint(tip) ? lighterView.flameHeat(atScreenPoint: tip) : 0
        let hotMaterial = bodyTouchesFlame && heat > 0.25 && (lit || lighterTipHeat > 0.28)
        let sootAmount = hotMaterial ? min(0.48, heat * (lit ? 0.48 : min(0.42, lighterTipHeat * 0.46))) : 0
        setLighterSoot(source: hotMaterial ? tip : nil, intensity: sootAmount)
        if !lit, heat > 0.25 {
            // Heat builds only at the exposed cigarette tip while it is inside
            // the bright part of the plume, then cools gradually when moved away.
            lighterTipHeat = min(1, lighterTipHeat + dt * (0.72 + heat * 0.48))
        } else {
            lighterTipHeat = max(0, lighterTipHeat - dt * (bodyTouchesFlame ? 0.12 : 0.62))
        }
        cigarette.preheat = CGFloat(lighterTipHeat)
        guard !lit, lighterTipHeat >= 0.92, !lighterIgnitionLatched else { return }
        lighterIgnitionLatched = true
        lighterTipHeat = 0
        cigarette.preheat = 0
        setLit(true, cancelGesture: false)
    }
    private func updateLighterObstructions(using flame: LighterView?) {
        guard let flame, flame.window?.isVisible == true, flame.isIgnited else {
            flame?.flameObstructionScreenSegments = []
            flame?.flameObstructionScreenSegment = nil
            return
        }
        let owner = parentSession ?? self
        var segments: [(NSPoint, NSPoint)] = []
        func add(_ start: NSPoint, _ end: NSPoint) {
            if flame.flameIntersectsScreenSegment(start, end) { segments.append((start, end)) }
        }
        func addRectEdges(_ rect: NSRect) {
            guard !rect.isEmpty else { return }
            let corners = [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
                           NSPoint(x: rect.maxX, y: rect.maxY), NSPoint(x: rect.minX, y: rect.maxY)]
            for index in corners.indices { add(corners[index], corners[(index + 1) % corners.count]) }
        }
        for session in [owner] + owner.additionalSessions where session.cigaretteExists && session.visible {
            let a = session.cigaretteScreenPoint(x: session.cigarette.smokeTipX, y: 19)
            let b = session.cigaretteScreenPoint(x: 182, y: 19)
            add(a, b)
        }
        if owner.boxWindow?.isVisible == true, let view = owner.boxView, let window = owner.boxWindow {
            addRectEdges(window.convertToScreen(view.convert(view.visibleArtworkBounds(), to: nil)))
        }
        if owner.ashtrayWindow?.isVisible == true, let view = owner.ashtrayView, let window = owner.ashtrayWindow {
            addRectEdges(window.convertToScreen(view.convert(view.visibleArtworkBounds(), to: nil)))
        }
        for object in owner.additionalDesktopObjects.values where object.window.isVisible {
            if let view = object.boxView { addRectEdges(object.window.convertToScreen(view.convert(view.visibleArtworkBounds(), to: nil))) }
            if let view = object.ashtrayView { addRectEdges(object.window.convertToScreen(view.convert(view.visibleArtworkBounds(), to: nil))) }
        }
        // The shared window-surface list includes on-screen app windows and
        // Dock tops, giving the plume a contact response at their edges.
        for surface in owner.currentWindowLandingSurfaces() {
            add(NSPoint(x: surface.x, y: surface.y), NSPoint(x: surface.x + surface.width, y: surface.y))
        }
        flame.flameObstructionScreenSegments = segments
        flame.flameObstructionScreenSegment = nil
    }
    private func setLighterSoot(source: NSPoint?, intensity: Double) {
        for entry in smokeDisplays.values {
            if let source {
                entry.view.sootSourceInWindow = NSPoint(x: source.x - entry.window.frame.minX,
                                                        y: source.y - entry.window.frame.minY)
            }
            entry.view.sootEmission = Float(min(0.5, max(0, intensity)))
        }
    }
    private func cigaretteScreenPoint(x: CGFloat, y: CGFloat) -> NSPoint {
        cigaretteWindow.convertPoint(toScreen: cigarette.convert(cigarette.canvasPoint(NSPoint(x: x, y: y)), to: nil))
    }
    private func resizeCigarette(for screen: NSScreen, scaleOverride: CGFloat? = nil) {
        let scale = scaleOverride ?? cigarettePointScale(for: screen)
        let desired = NSSize(width: 220 * scale, height: 220 * scale)
        guard abs(cigaretteWindow.frame.width - desired.width) > 0.5 else { return }
        let center = NSPoint(x: cigaretteWindow.frame.midX, y: cigaretteWindow.frame.midY)
        cigaretteWindow.setContentSize(desired)
        cigaretteWindow.setFrameOrigin(NSPoint(x: center.x - desired.width / 2, y: center.y - desired.height / 2))
        cigarette.setFrameSize(desired)
        cigarette.setBoundsSize(NSSize(width: 220, height: 220))
    }
    private func cigaretteScale(at point: NSPoint) -> CGFloat {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return 1 }
        return cigarettePointScale(for: screen)
    }
    private func cigarettePointScale(for screen: NSScreen) -> CGFloat {
        // Keep the cigarette at a consistent desktop size like the lighter
        // and pack. Virtual displays often report unreliable physical sizes.
        let preferredScale: CGFloat = 1.45
        let screenFitScale = min(screen.frame.width / 220, screen.frame.height / 220)
        return min(preferredScale, screenFitScale)
    }
    private func positionSmoke() {
        guard cigaretteExists, cigarette != nil, cigaretteWindow != nil else { return }
        var source = cigaretteScreenPoint(x: cigarette.smokeTipX, y: 19)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(source) }) ?? cigaretteWindow.screen ?? NSScreen.main else { return }
        if !cigarette.isInteracting && !externallyDragging {
            resizeCigarette(for: screen); keepCigaretteInsideScreen()
            source = cigaretteScreenPoint(x: cigarette.smokeTipX, y: 19)
        }
        guard let entry = smokeDisplays[displayID(screen)] else { return }
        if smoke !== entry.view {
            let wasInhaling = smoke?.inhaling ?? false
            smoke?.emits = false; smoke?.inhaling = false
            smokeWindow = entry.window; smoke = entry.view
            smoke.inhaling = wasInhaling
        }
        smoke.emits = true
        smoke.sourceInWindow = NSPoint(x: source.x - smokeWindow.frame.minX, y: source.y - smokeWindow.frame.minY)
    }
    private func ashSurfacesOnCigarette() -> [AshSurface] {
        guard visible && cigaretteExists, let cigarette, let cigaretteWindow else { return [] }
        let upperY: CGFloat = cos(cigarette.rotationAngle) >= 0 ? 26 : 12
        let tip = cigarette.smokeTipX - 4 - AshGeometry.capLength(level: burn.ash)
        let id = UInt32(truncatingIfNeeded: cigaretteWindow.windowNumber)
        let base = UInt32(0x40000000) | ((id & 0x00ffffff) << 4)
        return (0..<12).map { index in
            let x0 = tip + (180 - tip) * CGFloat(index) / 12
            let x1 = tip + (180 - tip) * CGFloat(index + 1) / 12
            let a = cigaretteScreenPoint(x: x0, y: upperY), b = cigaretteScreenPoint(x: x1, y: upperY)
            return AshSurface(id: base &+ UInt32(index), x: min(a.x, b.x) - 0.5,
                              y: max(a.y, b.y), width: max(1, abs(b.x - a.x) + 1), groupID: base)
        }
    }
    private func ensureVisible() {
        recoveryBag?.constrainToScreen()
        if let ashtrayWindow { keepAshtrayVisible(ashtrayWindow) }
        for object in additionalDesktopObjects.values where object.kind == .ashtray {
            keepAshtrayVisible(object.window)
        }
        guard let cigaretteWindow else { return }
        if !cigaretteExists, let boxWindow { keepBoxVisible(boxWindow); return }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(cigaretteWindow.frame) }) {
            let bounds = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
            cigaretteWindow.setFrameOrigin(NSPoint(x: bounds.maxX-cigaretteWindow.frame.width-40, y: bounds.minY+90))
        }
    }
    private func keepBoxVisible(_ window: NSWindow) {
        let artwork = boxView?.visibleArtworkBounds() ?? NSRect(origin: .zero, size: window.frame.size)
        let centerOnScreen = NSPoint(x: window.frame.minX + artwork.midX, y: window.frame.minY + artwork.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(centerOnScreen) }) ?? NSScreen.screens.min {
            let nearestA = NSPoint(x: min(max(centerOnScreen.x, $0.frame.minX), $0.frame.maxX),
                                   y: min(max(centerOnScreen.y, $0.frame.minY), $0.frame.maxY))
            let nearestB = NSPoint(x: min(max(centerOnScreen.x, $1.frame.minX), $1.frame.maxX),
                                   y: min(max(centerOnScreen.y, $1.frame.minY), $1.frame.maxY))
            return hypot(centerOnScreen.x - nearestA.x, centerOnScreen.y - nearestA.y) <
                hypot(centerOnScreen.x - nearestB.x, centerOnScreen.y - nearestB.y)
        }
        guard let bounds = screen?.frame else { return }
        var origin = window.frame.origin
        let minX = bounds.minX - artwork.minX
        let maxX = bounds.maxX - artwork.maxX
        let minY = bounds.minY - artwork.minY
        let maxY = bounds.maxY - artwork.maxY
        origin.x = minX <= maxX ? min(max(origin.x, minX), maxX) : bounds.midX - artwork.midX
        origin.y = minY <= maxY ? min(max(origin.y, minY), maxY) : bounds.midY - artwork.midY
        window.setFrameOrigin(origin)
    }
    private func keepAshtrayVisible(_ window: NSWindow) {
        guard let view = window.contentView as? AshtrayView else { return }
        let artwork = view.visibleArtworkBounds()
        let center = NSPoint(x: window.frame.minX + artwork.midX, y: window.frame.minY + artwork.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.screens.min {
            let left = NSPoint(x: min(max(center.x, $0.frame.minX), $0.frame.maxX), y: min(max(center.y, $0.frame.minY), $0.frame.maxY))
            let right = NSPoint(x: min(max(center.x, $1.frame.minX), $1.frame.maxX), y: min(max(center.y, $1.frame.minY), $1.frame.maxY))
            return hypot(center.x - left.x, center.y - left.y) < hypot(center.x - right.x, center.y - right.y)
        }
        guard let bounds = screen?.frame else { return }
        var origin = window.frame.origin
        let minX = bounds.minX - artwork.minX, maxX = bounds.maxX - artwork.maxX
        let minY = bounds.minY - artwork.minY, maxY = bounds.maxY - artwork.maxY
        origin.x = minX <= maxX ? min(max(origin.x, minX), maxX) : bounds.midX - artwork.midX
        origin.y = minY <= maxY ? min(max(origin.y, minY), maxY) : bounds.midY - artwork.midY
        window.setFrameOrigin(origin)
    }
    private func keepLighterVisible(_ window: NSWindow) {
        guard let view = lighterView, !NSScreen.screens.isEmpty else { return }
        let artwork = view.visibleBodyBounds()
        let center = NSPoint(x: window.frame.minX + artwork.midX, y: window.frame.minY + artwork.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.screens.min {
            let left = NSPoint(x: min(max(center.x, $0.frame.minX), $0.frame.maxX), y: min(max(center.y, $0.frame.minY), $0.frame.maxY))
            let right = NSPoint(x: min(max(center.x, $1.frame.minX), $1.frame.maxX), y: min(max(center.y, $1.frame.minY), $1.frame.maxY))
            return hypot(center.x - left.x, center.y - left.y) < hypot(center.x - right.x, center.y - right.y)
        }
        guard let bounds = screen?.frame else { return }
        let minX = bounds.minX - artwork.minX, maxX = bounds.maxX - artwork.maxX
        let minY = bounds.minY - artwork.minY, maxY = bounds.maxY - artwork.maxY
        var origin = window.frame.origin
        origin.x = minX <= maxX ? min(max(origin.x, minX), maxX) : bounds.midX - artwork.midX
        origin.y = minY <= maxY ? min(max(origin.y, minY), maxY) : bounds.midY - artwork.midY
        window.setFrameOrigin(origin)
    }
    private func setupMenu() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = ""
        if let iconURL = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png", subdirectory: "Resources"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true
            status.button?.image = icon
            status.button?.imagePosition = .imageOnly
        }
        status.button?.target = self
        status.button?.action = #selector(toggleStatusPopover)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func toggleStatusPopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusContextMenu()
            return
        }
        if statusPopover?.isShown == true {
            statusPopover?.performClose(nil)
            return
        }
        guard let button = status.button else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        let savedDissipation = UserDefaults.standard.string(forKey: "smokeDissipation").flatMap(SmokeDissipation.init(rawValue:)) ?? smoke.dissipation
        let hostingController = NSHostingController(rootView: MenuBarPopoverView(
            isVisible: visible,
            motionMode: cigaretteMotionMode,
            dissipation: savedDissipation,
            smokeBehindWindows: UserDefaults.standard.bool(forKey: "smokeBehindWindows"),
            onToggleVisibility: { [weak self] in self?.toggle() },
            onMotionMode: { [weak self] mode in self?.changeCigaretteMotionMode(mode) },
            onOpenControlPanel: { [weak self] in
                guard let self else { return }
                self.statusPopover?.performClose(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                    self?.openControlPanel()
                }
            },
            onOpenInventory: { [weak self] in
                guard let self else { return }
                self.statusPopover?.performClose(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in self?.openInventory() }
            },
            onOpenStore: { [weak self] in
                self?.statusPopover?.performClose(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in self?.openStore() }
            },
            onOpenSupportDeveloper: { [weak self] in
                self?.statusPopover?.performClose(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in self?.openSupportDeveloper() }
            },
            recoveryBagShown: recoveryBagWindow?.isVisible == true,
            onToggleRecoveryBag: { [weak self] in self?.toggleRecoveryBag() },
            onOpenSettings: { [weak self] in self?.openGameSettings() },
            onQuit: { NSApp.terminate(nil) },
            onDissipation: { [weak self] mode in
                guard let self, let index = SmokeDissipation.allCases.firstIndex(of: mode) else { return }
                let item = NSMenuItem(); item.tag = index; self.changeSmokeDissipation(item)
            },
            onSmokeBehind: { [weak self] enabled in self?.setSmokeBehindWindows(enabled) }
        ))
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hostingController
        statusPopover = popover
        NSApp.activate(ignoringOtherApps: true)
        let arrowAnchor = NSRect(x: button.bounds.midX - 1, y: button.bounds.minY,
                                 width: 2, height: button.bounds.height)
        popover.show(relativeTo: arrowAnchor, of: button, preferredEdge: .minY)
    }

    private func showStatusContextMenu() {
        guard let button = status.button else { return }
        let menu = NSMenu()
        let visibilityItem = menu.addItem(withTitle: visible ? tr("隐藏桌面物件") : tr("显示桌面物件"), action: #selector(toggle), keyEquivalent: "")
        visibilityItem.target = self
        let inventoryItem = menu.addItem(withTitle: tr("打开背包"), action: #selector(openInventoryFromStatusMenu), keyEquivalent: "")
        inventoryItem.target = self
        menu.addItem(withTitle: tr(recoveryBagWindow?.isVisible == true ? "收起桌面背包" : "把背包放到桌面"),
                     action: #selector(toggleRecoveryBag), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("支持开发者"), action: #selector(openSupportDeveloperFromStatusMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("设置与关于"), action: #selector(openGameSettings), keyEquivalent: ",").target = self
        let quitItem = menu.addItem(withTitle: tr("退出 DeskPuff"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func openGameSettings() { showGameSettings() }

    @objc private func openSupportDeveloperFromStatusMenu() { openSupportDeveloper() }

    private func openSupportDeveloper() {
        if let supportDeveloperWindow {
            NSApp.activate(ignoringOtherApps: true)
            supportDeveloperWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 450),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = tr("支持开发者")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.04, blue: 0.08, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: SupportDeveloperView())
        window.center()
        supportDeveloperWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func showGameSettings() {
        statusPopover?.performClose(nil)
        let window = gameSettingsWindow ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 820),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = tr("设置与关于")
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: GameSettingsView(onLanguageChanged: { [weak self] language in
            self?.applyGameLanguage(language)
        }, onQualityChanged: { [weak self] energySaving in
            if energySaving { self?.ecoQuality() } else { self?.highQuality() }
        }, onResetSave: { [weak self] in
            self?.resetGameForPlayer() ?? false
        }))
        if gameSettingsWindow == nil { window.center() }
        gameSettingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func applyGameLanguage(_ language: GameLanguage) {
        guard GameLanguage.current != language else { return }
        language.save()
        gameSettingsWindow?.title = tr("设置与关于")
        statusPopover?.performClose(nil)
        let showPlayerHub = inventoryWindow?.isVisible == true
        let showEditor = controlPanelWindow?.isVisible == true
        let hubFrame = inventoryWindow?.frame
        let editorFrame = controlPanelWindow?.frame
        inventoryWindow?.close()
        controlPanelWindow?.close()
        inventoryWindow = nil
        controlPanelWindow = nil
        if showPlayerHub {
            openPlayerHub(playerHubNavigation.selected)
            if let hubFrame { inventoryWindow?.setFrame(hubFrame, display: true) }
        }
        if showEditor {
            openControlPanel()
            if let editorFrame { controlPanelWindow?.setFrame(editorFrame, display: true) }
        }
        rebuildStyleMenus()
        gameSettingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openInventoryFromStatusMenu() {
        statusPopover?.performClose(nil)
        openInventory()
    }
    @objc private func toggle() {
        for child in additionalSessions { child.toggle() }
        visible.toggle()
        if visible {
            if cigaretteExists {
                positionSmoke()
                cigaretteWindow.orderFrontRegardless(); cigarette.setAnimating(true)
            }
            smokeDisplays.values.forEach { $0.window.orderFrontRegardless(); $0.view.resume() }
            if primaryInventoryIDs[.cigaretteBox] != nil { boxWindow?.orderFrontRegardless() }
            ash.setVisible(true)
            if let recoveryBagWindow {
                recoveryBagWindow.orderFrontRegardless()
                playerHubNavigation.recoveryBagShown = true
            }
            if primaryInventoryIDs[.ashtray] != nil { ashtrayWindow?.orderFrontRegardless() }
            if primaryInventoryIDs[.lighter] != nil { lighterWindow?.orderFrontRegardless() }
            additionalDesktopObjects.values.forEach { $0.window.orderFrontRegardless() }
        }
        else {
            cigarette.cancel(); lighterView?.cancelInteraction(); additionalDesktopObjects.values.forEach { $0.lighterView?.cancelInteraction() }
            resetContactTracking(); savePosition(); smokeDisplays.values.forEach { $0.view.pausePreservingSmoke(); $0.window.orderOut(nil) }
            cigarette.setAnimating(false); ash.setVisible(false); cigaretteWindow.orderOut(nil); boxWindow?.orderOut(nil)
            ashtrayWindow?.orderOut(nil); lighterWindow?.orderOut(nil); additionalDesktopObjects.values.forEach { $0.window.orderOut(nil) }
            recoveryBagWindow?.orderOut(nil)
            playerHubNavigation.recoveryBagShown = false
        }
    }
    @objc private func toggleSmokeBehindWindows(_ sender: NSMenuItem) {
        let behind = !UserDefaults.standard.bool(forKey: "smokeBehindWindows")
        setSmokeBehindWindows(behind)
        sender.state = behind ? .on : .off
    }
    private func setSmokeBehindWindows(_ behind: Bool) {
        guard UserDefaults.standard.bool(forKey: "smokeBehindWindows") != behind else { return }
        UserDefaults.standard.set(behind, forKey: "smokeBehindWindows")
        updateSmokeWindowLevel()
        for child in additionalSessions { child.updateSmokeWindowLevel() }
    }
    @objc private func toggleCloudVariation(_ sender: NSMenuItem) {
        let enabled = !smoke.cloudVariation
        smokeDisplays.values.forEach { $0.view.cloudVariation = enabled }
        for child in additionalSessions { child.smokeDisplays.values.forEach { $0.view.cloudVariation = enabled } }
        UserDefaults.standard.set(enabled, forKey: "smokeCloudVariation")
        sender.state = enabled ? .on : .off
    }
    @objc private func chooseSmokeColor() {
        let picker = NSColorPanel.shared
        picker.showsAlpha = false; picker.isContinuous = true
        let tint = smoke.colorTint
        picker.color = tint.w > 0 ? NSColor(srgbRed: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1) : NSColor(srgbRed: 0.75, green: 0.79, blue: 0.82, alpha: 1)
        picker.setTarget(self); picker.setAction(#selector(smokeColorChanged(_:)))
        picker.orderFront(nil)
    }
    @objc private func smokeColorChanged(_ picker: NSColorPanel) {
        guard let color = picker.color.usingColorSpace(.sRGB) else { return }
        let rgb = [Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)]
        UserDefaults.standard.set(rgb, forKey: "smokeTintRGB")
        applySmokeTint()
    }
    @objc private func resetSmokeColor() {
        UserDefaults.standard.removeObject(forKey: "smokeTintRGB")
        applySmokeTint()
    }

    private func applySmokeTint() {
        for session in [self] + additionalSessions {
            session.smokeDisplays.values.forEach { session.configureSmoke($0.view, for: session.cigaretteStyle) }
        }
    }

    @objc private func openControlPanel() {
        if let window = controlPanelWindow {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
            return
        }
        let cigaretteManager = StyleManagerView(scope: .cigarettes, onSelectCigarette: { [weak self] style in
            guard let self else { return }
            self.cigaretteStyleStore.defaultStyleID = style.id
            self.boxView?.refreshCigaretteArtwork()
            self.boxView?.refreshCigaretteScale()
            if self.cigaretteExists { self.applyCigaretteStyle(style) }
            self.additionalSessions.forEach { child in if child.cigaretteExists { child.applyCigaretteStyle(style) } }
        }, onSelectBox: { _ in }, onSelectAshtray: { _ in }, onAssociate: { _, _ in })
        let styleManager = StyleManagerView(scope: .boxes, onSelectCigarette: { [weak self] style in
            guard let self else { return }
            self.cigaretteStyleStore.defaultStyleID = style.id
            self.boxView?.refreshCigaretteArtwork()
            self.boxView?.refreshCigaretteScale()
            if self.cigaretteExists { self.applyCigaretteStyle(style) }
            self.additionalSessions.forEach { child in if child.cigaretteExists { child.applyCigaretteStyle(style) } }
        }, onSelectBox: { [weak self] style in
            guard let self, let box = self.boxView else { return }
            box.style = style
            box.refreshCigaretteScale()
            UserDefaults.standard.set(style.id, forKey: "cigaretteBoxStyleV1")
            self.rebuildStyleMenus()
        }, onSelectAshtray: { [weak self] style in
            guard let self, let tray = self.ashtrayView else { return }
            tray.style = style
            UserDefaults.standard.set(style.id, forKey: "ashtrayStyleV1")
            self.rebuildStyleMenus()
        }, onAssociate: { [weak self] boxID, cigaretteID in
            guard let self else { return }
            var mappings = self.boxCigaretteStyleOverrides()
            mappings[boxID] = cigaretteID
            UserDefaults.standard.set(mappings, forKey: "cigaretteStyleByBoxV1")
            self.boxView?.refreshCigaretteArtwork()
            self.boxView?.refreshCigaretteScale()
            for object in self.additionalDesktopObjects.values where object.boxView?.style.id == boxID {
                object.boxView?.refreshCigaretteArtwork()
                object.boxView?.refreshCigaretteScale()
            }
        })
        let ashtrayManager = StyleManagerView(scope: .ashtrays, onSelectCigarette: { _ in }, onSelectBox: { _ in }, onSelectAshtray: { [weak self] style in
            guard let self, let tray = self.ashtrayView else { return }
            tray.style = style
            UserDefaults.standard.set(style.id, forKey: "ashtrayStyleV1")
            if let window = self.ashtrayWindow { self.keepAshtrayVisible(window) }
            self.syncAshtrayAttachments()
        }, onAssociate: { _, _ in }, onAshtrayScale: { [weak self] scale in
            guard let self, let tray = self.ashtrayView else { return }
            tray.scale = scale
            if let window = self.ashtrayWindow { self.keepAshtrayVisible(window) }
            self.syncAshtrayAttachments()
        })
        let lighterManager = LighterStyleManagerView(onSelect: { [weak self] style in
            self?.lighterView?.style = style
            UserDefaults.standard.set(style.id, forKey: "lighterStyleV1")
        })
        let amountIndex = SmokeAmount.allCases.firstIndex(of: smoke.amount) ?? 1
        let savedDissipation = UserDefaults.standard.string(forKey: "smokeDissipation").flatMap(SmokeDissipation.init(rawValue:)) ?? smoke.dissipation
        let rgb = UserDefaults.standard.array(forKey: "smokeTintRGB") as? [Double]
        let panel = ControlPanelView(
            smokeAmount: amountIndex, ashAmount: ash.amount.rawValue,
            inhaleSpeed: Double([5, 10, 20].firstIndex(of: Int(inhaleMultiplier)) ?? 1),
            dissipation: savedDissipation, cloudVariation: smoke.cloudVariation,
            smokeBehindWindows: UserDefaults.standard.bool(forKey: "smokeBehindWindows"),
            energySaving: UserDefaults.standard.bool(forKey: "energySaving"), desktopVisible: visible,
            extractionMode: boxView?.extractionMode ?? .oneToOne,
            cigaretteMotionMode: cigaretteMotionMode,
            smokeColor: rgb.map { Color(.sRGB, red: $0[0], green: $0[1], blue: $0[2]) } ?? Color(.sRGB, red: 0.75, green: 0.79, blue: 0.82),
            cigaretteManager: AnyView(cigaretteManager), styleManager: AnyView(styleManager), ashtrayManager: AnyView(ashtrayManager), lighterManager: AnyView(lighterManager),
            onSmokeAmount: { [weak self] index in guard let self else { return }; let item = NSMenuItem(); item.tag = index; self.changeAmount(item) },
            onAshAmount: { [weak self] value in guard let self else { return }; let item = NSMenuItem(); item.tag = value; self.changeAshAmount(item) },
            onInhaleSpeed: { [weak self] value in guard let self else { return }; let item = NSMenuItem(); item.tag = value; self.changeInhaleSpeed(item) },
            onDissipation: { [weak self] mode in guard let self, let index = SmokeDissipation.allCases.firstIndex(of: mode) else { return }; let item = NSMenuItem(); item.tag = index; self.changeSmokeDissipation(item) },
            onCloudVariation: { [weak self] _ in guard let self else { return }; self.toggleCloudVariation(NSMenuItem()) },
            onSmokeBehind: { [weak self] _ in guard let self else { return }; self.toggleSmokeBehindWindows(NSMenuItem()) },
            onEnergySaving: { [weak self] enabled in enabled ? self?.ecoQuality() : self?.highQuality() },
            onExtractionMode: { [weak self] mode in guard let self, let index = CigaretteExtractionMode.allCases.firstIndex(of: mode) else { return }; let item = NSMenuItem(); item.tag = index; self.changeCigaretteExtractionMode(item) },
            onCigaretteMotionMode: { [weak self] mode in self?.changeCigaretteMotionMode(mode) },
            onSmokeColor: { [weak self] color in
                guard let self, let ns = NSColor(color).usingColorSpace(.sRGB) else { return }
                UserDefaults.standard.set([Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent)], forKey: "smokeTintRGB")
                self.applySmokeTint()
            }, onResetSmokeColor: { [weak self] in self?.resetSmokeColor() },
            onToggleVisibility: { [weak self] in self?.toggle() }, onTakeCigarette: { [weak self] in self?.addCigarette() },
            onToggleLit: { [weak self] in self?.setLit(!(self?.lit ?? false)) }, onClearSmoke: { [weak self] in self?.clearSmoke() },
            onClearAsh: { [weak self] in self?.clearAsh() }, onClearCigarettes: { [weak self] in self?.clearCigarettes() },
            onDumpAshtray: { [weak self] in self?.dumpAshtrayContents() },
            onOptimizedFlame: { [weak self] enabled in self?.lighterView?.optimizedFlame = enabled },
            onContinuousFlameBlend: { [weak self] enabled in self?.lighterView?.gentleFlame = enabled },
            onBoxLidDebugProgress: { [weak self] progress in self?.setBoxLidDebugProgress(progress) },
            onOpenStore: { [weak self] in self?.openStore() },
            onOpenInventory: { [weak self] in self?.openInventory() },
            onRestoreDeveloperSave: { [weak self] in self?.restoreDeveloperSave() },
            onResetForTesting: { [weak self] in self?.resetGameForTesting() },
            onResetLighterForTesting: { [weak self] in self?.lighterView?.resetFuelForTesting() })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = tr("DeskPuff 控制面板")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.04, blue: 0.08, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: panel)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak window] in
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
        window.isReleasedWhenClosed = false
        controlPanelWindow = window
    }

    private func setBoxLidDebugProgress(_ progress: Double?) {
        var views: [CigaretteBoxView] = []
        if let boxView { views.append(boxView) }
        views += additionalDesktopObjects.values.compactMap(\.boxView)
        var seen = Set<ObjectIdentifier>()
        for view in views where seen.insert(ObjectIdentifier(view)).inserted {
            view.setLidDebugProgress(progress)
        }
    }
    private func openInventory() { openPlayerHub(.inventory) }

    private func openStore() { openPlayerHub(.store) }

    private func openPlayerHub(_ tab: PlayerHubTab) {
        InventoryStore.shared.settleIncome()
        playerHubNavigation.selected = tab
        if let inventoryWindow {
            NSApp.activate(ignoringOtherApps: true)
            inventoryWindow.makeKeyAndOrderFront(nil)
            return
        }
        let root = PlayerHubView(navigation: playerHubNavigation, onDeploy: { [weak self] item in
            self?.deployInventoryItem(item)
        }, onToggleRecoveryBag: { [weak self] in self?.toggleRecoveryBag() },
           onResetSave: { [weak self] in self?.resetGameForPlayer() ?? false })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.contentMinSize = NSSize(width: 960, height: 640)
        window.title = "DeskPuff"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView); window.isOpaque = false
        window.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.04, blue: 0.08, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: root); window.center(); inventoryWindow = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }

    private func resetGameForTesting() {
        guard InventoryStore.shared.resetForTesting() else { return }
        clearDesktopRuntimeObjects()
    }

    private func resetGameForPlayer() -> Bool {
        guard InventoryStore.shared.resetForPlayer() else { return false }
        clearDesktopRuntimeObjects()
        return true
    }

    private func restoreDeveloperSave() {
        guard InventoryStore.shared.restoreDeveloperSave() else { return }
        clearDesktopRuntimeObjects()
        for item in InventoryStore.shared.layout.items where item.location == .desktop {
            deployInventoryItem(item, restoring: true)
        }
    }

    private func clearDesktopRuntimeObjects() {
        boxView?.cancelPendingExtraction(); lighterView?.cancelInteraction()
        for session in [self] + additionalSessions { session.deactivateCigarette() }
        for object in additionalDesktopObjects.values {
            object.boxView?.cancelPendingExtraction(); object.lighterView?.cancelInteraction(); object.window.orderOut(nil)
        }
        additionalDesktopObjects.removeAll()
        boxWindow?.orderOut(nil); lighterWindow?.orderOut(nil); ashtrayWindow?.orderOut(nil)
        primaryInventoryIDs.removeAll(); activeInventoryIDs.removeAll()
        hideRecoveryBag()
        clearAsh(); clearSmoke()
    }
    private func deployInventoryItem(_ item: InventoryItem, restoring: Bool = false) {
        guard item.kind.canDeploy else { return }
        let store = InventoryStore.shared
        if !restoring && !store.setLocation(item.id, .desktop) { return }
        if primaryInventoryIDs[item.kind] != nil {
            createAdditionalDesktopObject(for: item)
            return
        }
        switch item.kind {
        case .cigaretteBox:
            guard let view = boxView, let window = boxWindow else { return }
            let style = styleRegistry.cigaretteBoxes.first(where: { $0.id == item.styleID }) ?? .default
            view.style = style
            if let state = item.state { view.restoreInventoryState(state) } else { view.resetInventoryState() }
            view.refreshCigaretteArtwork(); view.refreshCigaretteScale()
            if let transform = item.desktopTransform {
                window.setFrameOrigin(NSPoint(x: transform.x, y: transform.y)); view.rotationAngle = transform.rotation
            }
            UserDefaults.standard.set(style.id, forKey: "cigaretteBoxStyleV1")
        case .lighter:
            guard let view = lighterView, let window = lighterWindow else { return }
            let style = styleRegistry.lighters.first(where: { $0.id == item.styleID }) ?? .default
            view.style = style
            if let state = item.state { view.restoreInventoryState(state) } else { view.resetInventoryState() }
            if let transform = item.desktopTransform {
                window.setFrameOrigin(NSPoint(x: transform.x, y: transform.y)); view.rotationAngle = transform.rotation
            }
            UserDefaults.standard.set(style.id, forKey: "lighterStyleV1")
        case .ashtray:
            guard let view = ashtrayView, let window = ashtrayWindow else { return }
            let style = styleRegistry.ashtrays.first(where: { $0.id == item.styleID }) ?? .default
            view.style = style
            if let state = item.state { view.restoreInventoryState(state) } else { view.resetInventoryState() }
            UserDefaults.standard.set(style.id, forKey: "ashtrayStyleV1")
            if let transform = item.desktopTransform {
                window.setFrameOrigin(NSPoint(x: transform.x, y: transform.y)); view.rotationAngle = transform.rotation
            }
            keepAshtrayVisible(window)
        default: return
        }
        primaryInventoryIDs[item.kind] = item.id
        activeInventoryIDs[item.kind, default: []].append(item.id)
        guard visible else { store.setMessage(nil); return }
        switch item.kind {
        case .cigaretteBox: boxWindow?.orderFrontRegardless()
        case .lighter: lighterWindow?.orderFrontRegardless()
        case .ashtray: ashtrayWindow?.orderFrontRegardless()
        default: break
        }
        store.setMessage(nil)
    }

    private func createAdditionalDesktopObject(for item: InventoryItem) {
        guard item.kind.canDeploy else { return }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let count = activeInventoryIDs[item.kind]?.count ?? 1
        let offset = CGFloat(count % 6) * 100
        let savedTransform = item.desktopTransform
        let frame: NSRect
        switch item.kind {
        case .cigaretteBox:
            frame = NSRect(x: savedTransform?.x ?? screen.minX + 36 + CGFloat(count % 5) * 90,
                           y: savedTransform?.y ?? screen.midY - offset * 0.45,
                           width: CigaretteBoxView.canvasSize, height: CigaretteBoxView.canvasSize)
        case .lighter:
            frame = NSRect(x: savedTransform?.x ?? screen.minX + 36 + CGFloat(count % 5) * 125 - LighterView.canvasPadding,
                           y: savedTransform?.y ?? screen.midY - offset * 0.45 - LighterView.canvasPadding,
                           width: LighterView.canvasSize.width, height: LighterView.canvasSize.height)
        case .ashtray:
            frame = NSRect(x: savedTransform?.x ?? screen.minX + 36 + CGFloat(count % 5) * 100,
                           y: savedTransform?.y ?? screen.midY - offset * 0.45,
                           width: AshtrayView.canvasSize.width, height: AshtrayView.canvasSize.height)
        default: return
        }
        let window = panel(frame, free: item.kind == .lighter || item.kind == .ashtray)
        switch item.kind {
        case .cigaretteBox:
            let style = styleRegistry.cigaretteBoxes.first { $0.id == item.styleID } ?? .default
            let view = CigaretteBoxView(frame: NSRect(origin: .zero, size: frame.size))
            view.style = style
            if let state = item.state { view.restoreInventoryState(state) } else { view.resetInventoryState() }
            view.rotationAngle = savedTransform?.rotation ?? view.rotationAngle
            view.cigaretteStyleResolver = { [weak self] box in
                self?.cigaretteStyleStore.style(for: box)
            }
            view.onCigaretteScale = { [weak self] point in self?.cigaretteScale(at: point) ?? 1 }
            view.onMove = { [weak self, weak window] origin, delta in
                guard let self, let window else { return .zero }
                window.setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
                let proposed = window.frame.origin; self.keepBoxVisible(window)
                return NSPoint(x: window.frame.minX - proposed.x, y: window.frame.minY - proposed.y)
            }
            view.onMoveFinished = { [weak self, weak window, weak view] in
                guard let self, let window, let view else { return }
                InventoryStore.shared.updateState(item.id, state: view.inventoryState)
                self.recordInventoryTransform(item.id, window: window, rotation: view.rotationAngle)
            }
            view.onRotationChanged = { [weak self, weak window] angle in
                guard let self, let window else { return }
                self.recordInventoryTransform(item.id, window: window, rotation: angle)
                self.keepBoxVisible(window)
            }
            view.onVisualBoundsChanged = { [weak self, weak window] in if let self, let window { self.keepBoxVisible(window) } }
            view.onInteractionFinished = { [weak self, weak window] in if let self, let window { self.keepBoxVisible(window) } }
            view.onInventoryChanged = { [weak view] _, _ in
                if let view { InventoryStore.shared.updateState(item.id, state: view.inventoryState) }
            }
            view.onTakeCigarette = { [weak self, weak view] point, angle, scale, lit, duringDrag in
                guard let self, let view else { return false }
                return self.takeCigarette(at: point, angle: angle, scale: scale, lit: lit, duringDrag: duringDrag, from: view)
            }
            view.onExtractionBecameFree = { [weak self] pointer in
                guard let self, let session = self.lastTakenSession else { return }
                self.extractionSession = session; session.beginExternalDrag(at: pointer)
            }
            view.onFreeCigaretteDrag = { [weak self] in self?.extractionSession?.moveExternalDrag(to: $0) }
            view.onFreeCigaretteDragFinished = { [weak self] in self?.extractionSession?.finishExternalDrag(); self?.extractionSession = nil }
            view.onStoreInInventory = { [weak self] in self?.returnInventoryItem(.cigaretteBox, id: item.id) }
            view.refreshCigaretteScale(); window.contentView = view
            let object = AdditionalDesktopObject(id: item.id, kind: .cigaretteBox, window: window); object.boxView = view
            additionalDesktopObjects[item.id] = object
        case .lighter:
            let style = styleRegistry.lighters.first { $0.id == item.styleID } ?? .default
            let view = LighterView(frame: NSRect(origin: .zero, size: LighterView.canvasSize))
            view.onInventoryStateChanged = { [weak view] in
                guard let view else { return }
                InventoryStore.shared.updateState(item.id, state: view.inventoryState)
            }
            view.style = style
            if let state = item.state { view.restoreInventoryState(state) } else { view.resetInventoryState() }
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2); window.contentView = view
            view.onMove = { [weak self, weak window] origin, delta in
                guard let self, let window else { return .zero }
                window.setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
                let proposed = window.frame.origin; self.keepLighterVisible(window)
                return NSPoint(x: window.frame.minX - proposed.x, y: window.frame.minY - proposed.y)
            }
            view.onMoveFinished = { [weak self, weak window, weak view] in
                guard let self, let window, let view else { return }
                InventoryStore.shared.updateState(item.id, state: view.inventoryState)
                self.recordInventoryTransform(item.id, window: window, rotation: view.rotationAngle)
            }
            view.rotationAngle = savedTransform?.rotation ?? 0
            view.onRotationChanged = { [weak self, weak window] angle in
                guard let self, let window else { return }
                self.recordInventoryTransform(item.id, window: window, rotation: angle); self.keepLighterVisible(window)
            }
            view.onStoreInInventory = { [weak self] in self?.returnInventoryItem(.lighter, id: item.id) }
            let object = AdditionalDesktopObject(id: item.id, kind: .lighter, window: window); object.lighterView = view
            additionalDesktopObjects[item.id] = object
        case .ashtray:
            let style = styleRegistry.ashtrays.first { $0.id == item.styleID } ?? .default
            let view = AshtrayView(frame: NSRect(origin: .zero, size: AshtrayView.canvasSize))
            view.style = style
            if let state = item.state { view.restoreInventoryState(state) } else { view.resetInventoryState() }
            window.level = .floating; window.contentView = view
            view.onMove = { [weak self, weak window] origin, delta in
                guard let self, let window else { return }
                window.setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
                self.keepAshtrayVisible(window)
                self.syncAshtrayAttachments()
            }
            view.rotationAngle = savedTransform?.rotation ?? 0
            view.onMoveFinished = { [weak self, weak window, weak view] in
                guard let self, let window, let view else { return }
                InventoryStore.shared.updateState(item.id, state: view.inventoryState)
                self.recordInventoryTransform(item.id, window: window, rotation: view.rotationAngle)
            }
            view.onRotationChanged = { [weak self, weak window] angle in
                guard let self, let window else { return }
                self.recordInventoryTransform(item.id, window: window, rotation: angle); self.syncAshtrayAttachments()
            }
            configureRecoveryTray(view)
            view.onAshSpilled = { [weak self] particles in self?.ash.scatterFromAshtray(particles, impulse: .zero) }
            view.onClearAsh = { [weak view] in view?.clearAsh() }
            view.onStoreInInventory = { [weak self] in self?.returnInventoryItem(.ashtray, id: item.id) }
            view.onDumpAsh = { [weak self, weak view] in
                guard let self, let view else { return }
                let angle = view.rotationAngle; self.ash.scatterFromAshtray(view.ejectStoredAsh(), impulse: NSPoint(x: sin(angle) * 82, y: -cos(angle) * 82))
            }
            let object = AdditionalDesktopObject(id: item.id, kind: .ashtray, window: window); object.ashtrayView = view
            additionalDesktopObjects[item.id] = object
        default: return
        }
        switch item.kind {
        case .cigaretteBox: keepBoxVisible(window)
        case .lighter: keepLighterVisible(window)
        case .ashtray: keepAshtrayVisible(window)
        default: break
        }
        activeInventoryIDs[item.kind, default: []].append(item.id)
        if visible { window.orderFrontRegardless() }
    }

    private func returnInventoryItem(_ kind: InventoryKind, id requestedID: UUID? = nil) {
        guard kind.canDeploy else { return }
        guard let id = requestedID ?? primaryInventoryIDs[kind] ?? activeInventoryIDs[kind]?.first else { return }
        let store = InventoryStore.shared
        let extra = additionalDesktopObjects[id]
        if kind == .ashtray {
            ([self] + additionalSessions).forEach { session in
                if session.ashtrayAttachment?.inventoryID == id { session.ashtrayAttachment = nil }
            }
        }
        switch kind {
        case .cigaretteBox:
            if let extra, let view = extra.boxView { store.updateState(id, state: view.inventoryState); store.updateStyle(id, styleID: view.style.id) }
            else {
            store.updateState(id, state: boxView?.inventoryState)
            if let view = boxView { store.updateStyle(id, styleID: view.style.id) }
            }
        case .lighter:
            let view = extra?.lighterView ?? lighterView
            view?.cancelInteraction(); store.updateState(id, state: view?.inventoryState)
            if let view { store.updateStyle(id, styleID: view.style.id) }
        case .ashtray:
            let view = extra?.ashtrayView ?? ashtrayView
            if let view { store.updateState(id, state: view.inventoryState); store.updateStyle(id, styleID: view.style.id) }
        default: break
        }
        switch store.storeBack(id) {
        case .stored:
            break
        case .requiresReorganization:
            let alert = NSAlert()
            alert.messageText = tr("整理背包并放回物品？")
            alert.informativeText = tr("当前排列没有合适空位。系统可以重新整理物品，并为这件物品腾出位置。")
            alert.addButton(withTitle: tr("整理并放回"))
            alert.addButton(withTitle: tr("取消"))
            guard alert.runModal() == .alertFirstButtonReturn,
                  store.confirmStoreBackAfterReorganization(id) else {
                store.cancelPendingStoreBack(id)
                return
            }
        case .noSpace:
            return
        }
        removeDesktopInventoryWindow(kind, id: id)
    }

    private func removeDesktopInventoryWindow(_ kind: InventoryKind, id: UUID) {
        if let extra = additionalDesktopObjects.removeValue(forKey: id) {
            extra.window.orderOut(nil)
        } else {
            switch kind {
            case .cigaretteBox: boxWindow?.orderOut(nil)
            case .lighter: lighterWindow?.orderOut(nil)
            case .ashtray: ashtrayWindow?.orderOut(nil)
            default: break
            }
        }
        activeInventoryIDs[kind]?.removeAll { $0 == id }
        if activeInventoryIDs[kind]?.isEmpty == true { activeInventoryIDs[kind] = nil }
        if primaryInventoryIDs[kind] == id { primaryInventoryIDs[kind] = nil }
    }

    private func recordInventoryTransform(_ id: UUID, window: NSWindow, rotation: Double) {
        InventoryStore.shared.updateTransform(id, transform: InventoryTransform(x: window.frame.minX,
                                                                                  y: window.frame.minY,
                                                                                  rotation: rotation))
    }

    @objc private func clearSmoke() { smokeDisplays.values.forEach { $0.view.clear() }; additionalSessions.forEach { $0.clearSmoke() } }
    @objc private func clearAsh() {
        ash.clear(); ashtrayView?.clearAsh()
        additionalDesktopObjects.values.forEach { $0.ashtrayView?.clearAsh() }
        additionalSessions.forEach { $0.clearAsh() }
    }
    @objc private func toggleRecoveryBag() {
        if recoveryBagWindow?.isVisible == true { hideRecoveryBag() }
        else { placeRecoveryBag() }
    }

    private func placeRecoveryBag() {
        if !visible { toggle() }
        if recoveryBagWindow == nil, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let bounds = screen.visibleFrame
            let size = DesktopRecoveryBag.canvasSize
            let window = panel(NSRect(x: bounds.maxX - size.width - 12, y: bounds.minY + 12,
                                      width: size.width, height: size.height), free: true)
            let bag = DesktopRecoveryBag(frame: CGRect(origin: .zero, size: size))
            bag.onOpen = { [weak self] in self?.openInventory() }
            bag.onHide = { [weak self] in self?.hideRecoveryBag() }
            bag.onMoveOpening = { [weak self] previous, current in
                self?.ash.sweepRecoveryOpening(from: previous, to: current)
            }
            window.contentView = bag
            recoveryBagWindow = window
            bag.constrainToScreen()
        }
        recoveryBagWindow?.orderFrontRegardless()
        playerHubNavigation.recoveryBagShown = recoveryBagWindow?.isVisible == true
        recoveryBag?.show(tr("用背包接住或扫过烟灰"))
    }

    private func hideRecoveryBag() {
        recoveryBagWindow?.orderOut(nil)
        recoveryBagWindow = nil
        playerHubNavigation.recoveryBagShown = false
    }

    private func configureRecoveryTray(_ tray: AshtrayView) {
        tray.onRecoveryContentsChanged = { [weak self, weak tray] in
            guard let self, let tray else { return }
            let id = tray === self.ashtrayView ? self.primaryInventoryIDs[.ashtray]
                : self.additionalDesktopObjects.values.first { $0.ashtrayView === tray }?.id
            if let id { InventoryStore.shared.updateState(id, state: tray.inventoryState) }
        }
    }

    private func receiveRecoveryAsh(_ offered: [(batch: AshRecoveryBatch, mass: Int)]) -> [AshRecoveryBatch: Int] {
        guard !offered.isEmpty else { return [:] }
        let store = InventoryStore.shared
        let before = store.recoveryItemCount
        let accepted = store.collectAshMass(offered)
        let received = store.recoveryItemCount - before
        if received > 0 || !accepted.isEmpty { recoveryBag?.showAshIntake(units: received) }
        // A parked opening may be blocked by a full bag for consecutive frames.
        return accepted
    }

    private func recycleCigaretteButt() {
        guard cigaretteExists else { return }
        let owner = parentSession ?? self
        guard cigarette.canRecycleButt else { return }
        guard InventoryStore.shared.collectRecovery(.cigaretteButt, count: 1) == 1 else {
            owner.recoveryBag?.show(tr("背包没有足够的格位"))
            return
        }
        deactivateCigarette()
        owner.recoveryBag?.show(tr("收进 1 个烟头"), success: true)
    }

    private func dumpAshtrayContents() {
        let trays = activeAshtrayTargets()
        for (_, tray, _) in trays {
            let angle = tray.rotationAngle
            let particles = tray.ejectStoredAsh()
            ash.scatterFromAshtray(particles, impulse: NSPoint(x: sin(angle) * 82, y: -cos(angle) * 82))
        }
    }
    private func toggleLighterVisibility() {
        guard let lighterWindow else { return }
        if lighterWindow.isVisible { lighterView?.cancelInteraction(); lighterWindow.orderOut(nil) }
        else { lighterWindow.orderFrontRegardless() }
    }
    private func deactivateCigarette() {
        guard cigaretteExists else { return }
        let sourceBox = sourceBoxView
        cigarette.cancel(); resetContactTracking(); cigaretteExists = false; lit = false; countsTowardRank = false; ashtrayAttachment = nil; sourceBoxView = nil
        cigarettePhysicsTimer?.invalidate(); cigarettePhysicsTimer = nil
        cigarette.setAnimating(false); cigaretteWindow.orderOut(nil)
        smokeDisplays.values.forEach { $0.view.inhaling = false; $0.view.emits = false; $0.view.burning = false }
        if !isChild && visible, let sourceBox {
            if sourceBox === boxView {
                if primaryInventoryIDs[.cigaretteBox] != nil { boxWindow?.orderFrontRegardless() }
            } else if let deployedBox = additionalDesktopObjects.values.first(where: { $0.boxView === sourceBox }) {
                deployedBox.window.orderFrontRegardless()
            }
        }
    }
    private func reviveCigarette() {
        guard !cigaretteExists else { return }
        cigaretteExists = true
        newCigarette()
        if visible { cigaretteWindow.orderFrontRegardless(); cigarette.setAnimating(true) }
        if cigaretteMotionMode == .gravity { startCigarettePhysics() }
    }
    @objc private func addCigarette() {
        if primaryInventoryIDs[.cigaretteBox] != nil, boxWindow?.isVisible == true, let boxView, boxView.remaining > 0 {
            boxView.openAndTakeNext(); return
        }
        if let box = additionalDesktopObjects.values.first(where: { $0.kind == .cigaretteBox && $0.window.isVisible && ($0.boxView?.remaining ?? 0) > 0 })?.boxView {
            box.openAndTakeNext(); return
        }
        InventoryStore.shared.setMessage(tr("桌面没有可取出的香烟，请从背包放置烟盒。"))
        openInventory()
    }
    private func takeCigarette(at center: NSPoint, angle: Double, scale: CGFloat, lit: Bool, duringDrag: Bool,
                               from sourceBox: CigaretteBoxView? = nil) -> Bool {
        let selectedStyle = styleForCurrentBox(sourceBox)
        if !cigaretteExists {
            sourceBoxView = sourceBox ?? boxView
            applyCigaretteStyle(selectedStyle)
            reviveCigarette()
            countsTowardRank = true
            cigarette.rotationAngle = angle
            externallyDragging = duringDrag
            placeCigarette(center: center, scaleOverride: scale)
            if lit { setLit(true, cancelGesture: false) }
            lastTakenSession = self
            if visible { smokeDisplays.values.forEach { $0.window.orderFrontRegardless() } }
            return true
        }
        if let child = additionalSessions.first(where: { !$0.cigaretteExists }) {
            child.sourceBoxView = sourceBox ?? boxView
            child.parentSession = self
            child.applyCigaretteMotionMode(cigaretteMotionMode)
            child.applyCigaretteStyle(selectedStyle)
            child.reviveCigarette(); child.cigarette.rotationAngle = angle
            child.countsTowardRank = true
            child.externallyDragging = duringDrag
            child.placeCigarette(center: center, scaleOverride: scale)
            if lit { child.setLit(true, cancelGesture: false) }
            lastTakenSession = child
            return true
        }
        let child = AppDelegate(isChild: true, sharedAsh: ash, sharedBoxView: sourceBox ?? boxView, sharedAshtrayView: ashtrayView)
        child.sourceBoxView = sourceBox ?? boxView
        child.cigaretteStyle = selectedStyle
        child.parentSession = self
        child.cigaretteMotionMode = cigaretteMotionMode
        child.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        guard child.cigaretteWindow != nil else { return false }
        child.countsTowardRank = true
        child.cigarette.rotationAngle = angle
        child.externallyDragging = duringDrag
        child.placeCigarette(center: center, scaleOverride: scale)
        if lit { child.setLit(true, cancelGesture: false) }
        if !visible { child.toggle() }
        additionalSessions.append(child)
        lastTakenSession = child
        return true
    }

    private func beginExternalDrag(at pointer: NSPoint) {
        externallyDragging = true
        lastCigaretteDragVelocity = .zero
        extractionPointer = pointer; extractionPointerTime = CACurrentMediaTime()
        contactPointer = pointer; contactPointerTime = extractionPointerTime
        let origin = cigaretteWindow.frame.origin
        extractionOffset = NSPoint(x: origin.x - pointer.x, y: origin.y - pointer.y)
        ashtrayAttachment = nil
    }

    private func moveExternalDrag(to pointer: NSPoint) {
        guard externallyDragging else { return }
        let now = CACurrentMediaTime()
        let elapsed = max(1.0 / 240, now - extractionPointerTime)
        let delta = NSPoint(x: pointer.x - extractionPointer.x, y: pointer.y - extractionPointer.y)
        lastCigaretteDragVelocity = NSPoint(x: delta.x / elapsed, y: delta.y / elapsed)
        let previousTip = cigaretteScreenPoint(x: cigarette.smokeTipX, y: 19)
        let previousFilter = cigaretteScreenPoint(x: 180, y: 19)
        let proposed = NSPoint(x: pointer.x + extractionOffset.x, y: pointer.y + extractionOffset.y)
        cigaretteWindow.setFrameOrigin(proposed)
        // Window placement can be rounded to display pixels. Only collision
        // corrections should change the pointer anchor; rounding must not
        // accumulate into a growing drag offset.
        let placed = cigaretteWindow.frame.origin
        applyContact(previousTip: previousTip, previousFilter: previousFilter)
        let actual = cigaretteWindow.frame.origin
        extractionOffset.x += actual.x - placed.x; extractionOffset.y += actual.y - placed.y
        positionSmoke()
        handleAshDrag(distance: hypot(delta.x, delta.y), motion: NSPoint(x: delta.x / elapsed, y: delta.y / elapsed))
        extractionPointer = pointer; extractionPointerTime = now
    }

    private func finishExternalDrag() {
        guard externallyDragging else { return }
        externallyDragging = false
        cigarette.onDragFinished?()
    }

    private func cigaretteTouchesAshtray(_ tray: AshtrayView) -> Bool {
        let longitudinalSamples = 36
        let crossSection: [CGFloat] = [10, 14, 19, 24, 28]
        for index in 0...longitudinalSamples {
            let x = CGFloat(index) * 180 / CGFloat(longitudinalSamples)
            for y in crossSection {
                if tray.containsBasin(screenPoint: cigaretteScreenPoint(x: x, y: y)) { return true }
            }
        }
        return false
    }

    private func updateAshtrayAttachmentAfterDrag() {
        guard cigaretteMotionMode == .free,
              let target = activeAshtrayTargets().first(where: { cigaretteTouchesAshtray($0.1) }) else {
            ashtrayAttachment = nil
            return
        }
        let (id, tray, _) = target
        let center = cigaretteScreenPoint(x: 95, y: 19)
        guard let localCenter = tray.trayLocalPoint(fromScreenPoint: center) else {
            ashtrayAttachment = nil
            return
        }
        ashtrayAttachment = AshtrayAttachment(inventoryID: id, localCenter: localCenter,
                                              relativeAngle: cigarette.rotationAngle - tray.rotationAngle)
    }

    private func syncAshtrayAttachments() {
        for session in [self] + additionalSessions {
            guard session.cigaretteExists, session.cigaretteMotionMode == .free,
                  let attachment = session.ashtrayAttachment,
                  let target = session.activeAshtrayTargets().first(where: { $0.0 == attachment.inventoryID }),
                  let center = target.1.screenPoint(fromTrayLocalPoint: attachment.localCenter) else { continue }
            let scale = session.cigaretteWindow.frame.width / 220
            session.cigarette.rotationAngle = target.1.rotationAngle + attachment.relativeAngle
            session.placeCigarette(center: center, scaleOverride: scale)
        }
    }

    private func placeCigarette(center: NSPoint, scaleOverride: CGFloat? = nil) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return }
        resizeCigarette(for: screen, scaleOverride: scaleOverride)
        let scale = cigaretteWindow.frame.width / 220
        cigaretteWindow.setFrameOrigin(NSPoint(x: center.x - 110 * scale, y: center.y - 110 * scale))
        if !externallyDragging { keepCigaretteInsideScreen() }
        positionSmoke()
        if visible { cigaretteWindow.orderFrontRegardless(); cigarette.setAnimating(true) }
        if cigaretteMotionMode == .gravity {
            cigaretteBody.reset(center: center, angle: cigarette.rotationAngle)
            if externallyDragging { cigaretteBody.moveWhileHeld(to: center, angle: cigarette.rotationAngle) }
            else { cigaretteBody.release(with: .zero); startCigarettePhysics() }
        }
    }
    @objc private func clearCigarettes() {
        deactivateCigarette(); additionalSessions.forEach { $0.deactivateCigarette() }
    }
    @objc private func changeAmount(_ sender: NSMenuItem) {
        guard SmokeAmount.allCases.indices.contains(sender.tag) else { return }
        let selected = SmokeAmount.allCases[sender.tag]
        smokeDisplays.values.forEach { $0.view.amount = selected }
        for child in additionalSessions { child.smokeDisplays.values.forEach { $0.view.amount = selected } }
        UserDefaults.standard.set(selected.rawValue, forKey: "smokeAmount")
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }
    @objc private func changeSmokeDissipation(_ sender: NSMenuItem) {
        guard SmokeDissipation.allCases.indices.contains(sender.tag) else { return }
        let mode = SmokeDissipation.allCases[sender.tag]
        smokeDisplays.values.forEach { $0.view.dissipation = mode }
        for child in additionalSessions { child.smokeDisplays.values.forEach { $0.view.dissipation = mode } }
        UserDefaults.standard.set(mode.rawValue, forKey: "smokeDissipation")
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }
    @objc private func changeCigaretteExtractionMode(_ sender: NSMenuItem) {
        guard CigaretteExtractionMode.allCases.indices.contains(sender.tag), let boxView else { return }
        boxView.extractionMode = CigaretteExtractionMode.allCases[sender.tag]
    }
    @objc private func changeCigaretteBoxStyle(_ sender: NSMenuItem) {
        let styles = styleRegistry.visibleCigaretteBoxes
        guard styles.indices.contains(sender.tag), let boxView else { return }
        let style = styles[sender.tag]
        boxView.style = style
        UserDefaults.standard.set(style.id, forKey: "cigaretteBoxStyleV1")
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }
    @objc private func changeAshtrayStyle(_ sender: NSMenuItem) {
        guard styleRegistry.ashtrays.indices.contains(sender.tag), let ashtrayView else { return }
        let style = styleRegistry.ashtrays[sender.tag]
        ashtrayView.style = style
        UserDefaults.standard.set(style.id, forKey: "ashtrayStyleV1")
        if let ashtrayWindow { keepAshtrayVisible(ashtrayWindow) }
        syncAshtrayAttachments()
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }
    private func rebuildStyleMenus() {
        cigaretteBoxStyleMenu?.removeAllItems()
        for (index, style) in styleRegistry.visibleCigaretteBoxes.enumerated() {
            let option = NSMenuItem(title: tr(style.name), action: #selector(changeCigaretteBoxStyle(_:)), keyEquivalent: "")
            option.target = self; option.tag = index; option.state = boxView?.style.id == style.id ? .on : .off
            option.image = style.previewArtwork.flatMap(menuPreviewImage)
            cigaretteBoxStyleMenu?.addItem(option)
        }
        ashtrayStyleMenu?.removeAllItems()
        for (index, style) in styleRegistry.ashtrays.enumerated() {
            let option = NSMenuItem(title: tr(style.name), action: #selector(changeAshtrayStyle(_:)), keyEquivalent: "")
            option.target = self; option.tag = index; option.state = ashtrayView?.style.id == style.id ? .on : .off
            option.image = style.previewArtwork.flatMap(menuPreviewImage)
            ashtrayStyleMenu?.addItem(option)
        }
    }
    private func menuPreviewImage(_ image: NSImage) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0, let copy = image.copy() as? NSImage else { return nil }
        let scale = min(28 / size.width, 22 / size.height)
        copy.size = NSSize(width: size.width * scale, height: size.height * scale)
        return copy
    }
    @objc private func openStyleFolder() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let folder = appSupport.appendingPathComponent("DeskPuff/Styles", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
    @objc private func reloadExternalStyles() {
        let defaults = UserDefaults.standard
        let boxID = defaults.string(forKey: "cigaretteBoxStyleV1") ?? boxView?.style.id
        let trayID = defaults.string(forKey: "ashtrayStyleV1") ?? ashtrayView?.style.id
        styleRegistry.reload()
        boxView?.style = styleRegistry.cigaretteBoxes.first { $0.id == boxID } ?? .default
        ashtrayView?.style = styleRegistry.ashtrays.first { $0.id == trayID } ?? .default
        if let style = boxView?.style, boxID == nil || style.id == boxID { defaults.set(style.id, forKey: "cigaretteBoxStyleV1") }
        if let style = ashtrayView?.style, trayID == nil || style.id == trayID { defaults.set(style.id, forKey: "ashtrayStyleV1") }
        rebuildStyleMenus()
        let alert = NSAlert()
        alert.messageText = tr("样式目录已重新加载")
        alert.informativeText = tr("烟盒：{{0}} 个外部样式\n烟灰缸：{{1}} 个外部样式{{2}}", max(0, styleRegistry.cigaretteBoxes.count - CigaretteBoxStyle.builtIns.count), max(0, styleRegistry.ashtrays.count - AshtrayStyle.builtIns.count), styleRegistry.diagnostics.isEmpty ? "" : tr("\n跳过 {{0}} 个无效样式；详情见控制台。", styleRegistry.diagnostics.count))
        alert.runModal()
    }
    private func updateExtractionModeMenu(_ mode: CigaretteExtractionMode) {
        guard let submenu = status?.menu?.items.first(where: { $0.title == tr("烟盒取放模式") })?.submenu else { return }
        for (index, option) in submenu.items.enumerated() {
            option.state = CigaretteExtractionMode.allCases.indices.contains(index) && CigaretteExtractionMode.allCases[index] == mode ? .on : .off
        }
    }
    @objc private func changeInhaleSpeed(_ sender: NSMenuItem) {
        guard [5, 10, 20].contains(sender.tag) else { return }
        inhaleMultiplier = Double(sender.tag)
        additionalSessions.forEach { $0.inhaleMultiplier = inhaleMultiplier }
        UserDefaults.standard.set(inhaleMultiplier, forKey: "inhaleMultiplier")
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }
    @objc private func changeAshAmount(_ sender: NSMenuItem) {
        guard let level = AshAmount(rawValue: sender.tag) else { return }
        ash.amount = level; additionalSessions.forEach { $0.ash.amount = level }; UserDefaults.standard.set(level.rawValue, forKey: "ashAmountV2")
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }
    @objc private func highQuality() { smokeDisplays.values.forEach { $0.view.energySaving = false }; additionalSessions.forEach { $0.highQuality() }; UserDefaults.standard.set(false, forKey: "energySaving") }
    @objc private func ecoQuality() { smokeDisplays.values.forEach { $0.view.energySaving = true }; additionalSessions.forEach { $0.ecoQuality() }; UserDefaults.standard.set(true, forKey: "energySaving") }
    @objc private func quit() { savePosition(); NSApp.terminate(nil) }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
