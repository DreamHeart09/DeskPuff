import Combine
import DeskPuffCore
import AppKit
import Foundation

enum InventoryStoreBackResult: Equatable {
    case stored
    case requiresReorganization
    case noSpace
}

@MainActor final class InventoryStore: ObservableObject {
    static let shared = InventoryStore()
    private let defaults = UserDefaults.standard
    private let dataKey = "inventoryDocumentV1"
    private let developerBackupKey = "inventoryDocumentBeforeDeveloperSessionV1"
    private let inventoryTestBackupKey = "inventoryBeforeDeveloperBagTestV1"
    private let playerResetBackupKey = "inventoryDocumentBeforePlayerResetV1"
    private let migrationKey = "inventoryMigrationV1Complete"
    private struct Capacity: Equatable {
        let columns: Int
        let rows: Int
        let name: String
        let bagAsset: String
        let bagCategory: InventoryBagCategory
        var cells: Int { columns * rows }
    }
    private let capacities = [
        Capacity(columns: 5, rows: 3, name: "随身小包", bagAsset: "sport-belt", bagCategory: .small),
        Capacity(columns: 6, rows: 4, name: "轻装挎包", bagAsset: "light-tech-sling", bagCategory: .light),
        Capacity(columns: 6, rows: 5, name: "日常背包", bagAsset: "campus-classic", bagCategory: .daily),
        Capacity(columns: 7, rows: 5, name: "扩展背包", bagAsset: "business-multi", bagCategory: .expanded),
        Capacity(columns: 8, rows: 6, name: "旅行背包", bagAsset: "cabin-travel", bagCategory: .travel),
        Capacity(columns: 10, rows: 6, name: "远行背包", bagAsset: "mountaineering", bagCategory: .expedition)
    ]
    private typealias Document = InventoryDocument
    private struct InventoryTestSnapshot: Codable {
        let columns: Int
        let rows: Int
        let capacityStage: Int
        let storedItems: [InventoryItem]
        let activeBagStyleID: String?
        let ownedBagStyleIDs: [String]?
        let ownedBagStages: [Int]
    }
    private var canWrite = true
    let economyRules: EconomyRules? = {
        guard let url = Bundle.module.url(forResource: "Economy", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let rules = try? JSONDecoder().decode(EconomyRules.self, from: data), rules.isValid else { return nil }
        return rules
    }()
    @Published private(set) var economy = EconomyState(balanceCents: 0)
    @Published private(set) var layout = InventoryLayout()
    @Published private(set) var capacityStage = 0
    @Published private(set) var bagStylesByCategory: [String: String] = [:]
    @Published private(set) var message: String?
    @Published private(set) var hasDeveloperSaveBackup = false
    @Published private(set) var hasInventoryTestSnapshot = false
    private var pendingStoreBack: (id: UUID, layout: InventoryLayout)?
    var currentCapacity: (columns: Int, rows: Int, name: String, bagAsset: String) {
        let value = capacities[min(capacityStage, capacities.count - 1)]
        return (value.columns, value.rows, value.name, value.bagAsset)
    }
    var nextCapacity: (columns: Int, rows: Int, name: String, bagAsset: String)? {
        guard capacityStage + 1 < capacities.count else { return nil }
        let value = capacities[capacityStage + 1]
        return (value.columns, value.rows, value.name, value.bagAsset)
    }
    var expansionCount: Int { capacityStage }
    var capacityOptions: [(stage: Int, columns: Int, rows: Int, name: String, category: InventoryBagCategory)] {
        capacities.enumerated().map { ($0.offset, $0.element.columns, $0.element.rows, $0.element.name, $0.element.bagCategory) }
    }
    var currentBagCategory: InventoryBagCategory { capacities[min(capacityStage, capacities.count - 1)].bagCategory }
    var bagStylesForCurrentCapacity: [InventoryBagStyle] {
        InventoryBagStyle.builtIns.filter {
            $0.category == currentBagCategory && (economy.ownedBagStyleIDs ?? []).contains($0.id)
        }
    }
    var currentBagStyleID: String {
        if let active = economy.activeBagStyleID.flatMap(InventoryBagStyle.item), active.category == currentBagCategory { return active.id }
        return currentBagCategory.defaultStyleID
    }
    var currentBagAsset: String {
        InventoryBagStyle.item(currentBagStyleID)?.asset ?? currentCapacity.bagAsset
    }
    var lighterBurnDurationMultiplier: Double {
        1 + InventoryToolEffect.allCases.reduce(0) { total, effect in
            total + Double(min(toolCount(for: effect), 1)) * effect.lighterRuntimeBonus
        }
    }
    var cigarettePurchaseDiscount: Double {
        min(0.30, InventoryToolEffect.allCases.reduce(0) { total, effect in
            total + Double(min(toolCount(for: effect), 1)) * effect.cigaretteDiscountRate
        })
    }
    var ashtrayCapacityMultiplier: Double {
        1 + InventoryToolEffect.allCases.reduce(0) { total, effect in
            total + Double(min(toolCount(for: effect), 1)) * effect.ashtrayCapacityBonus
        }
    }
    func purchasePrice(for product: StoreProduct) -> Int {
        guard product.kind == .cigaretteBox else { return product.priceCents }
        return Int((Double(product.priceCents) * (1 - cigarettePurchaseDiscount)).rounded(.down))
    }
    private func toolCount(for effect: InventoryToolEffect) -> Int {
        return layout.items.filter { item in
            item.location == .stored && item.kind == .tool &&
                economyRules?.products.first(where: { $0.id == item.styleID })?.passiveEffect == effect
        }.count
    }
    func carriedToolCount(for effect: InventoryToolEffect) -> Int { toolCount(for: effect) }
    func hasCarriedTool(_ effect: InventoryToolEffect) -> Bool { toolCount(for: effect) > 0 }

    func setBagStyle(_ styleID: String) {
        guard let style = InventoryBagStyle.item(styleID), style.category == currentBagCategory,
              (economy.ownedBagStyleIDs ?? []).contains(styleID) else { return }
        var next = economy; next.activeBagStyleID = styleID
        _ = save(layout, economy: next)
    }
    func setBagStyleForTesting(_ styleID: String) {
        guard let style = InventoryBagStyle.item(styleID), style.category == currentBagCategory else { return }
        captureInventoryTestSnapshotIfNeeded()
        var next = economy
        next.activeBagStyleID = styleID
        if !(next.ownedBagStyleIDs ?? []).contains(styleID) { next.ownedBagStyleIDs = (next.ownedBagStyleIDs ?? []) + [styleID] }
        _ = save(layout, economy: next)
    }

    func setCapacityStageForTesting(_ requestedStage: Int) {
        guard capacities.indices.contains(requestedStage) else { return }
        captureInventoryTestSnapshotIfNeeded()
        if layout.columns == capacities[requestedStage].columns && layout.rows == capacities[requestedStage].rows {
            capacityStage = requestedStage
            if !economy.ownedBagStages.contains(requestedStage) { economy.ownedBagStages.append(requestedStage) }
            equipDefaultBagStyle(for: capacities[requestedStage].bagCategory)
            _ = save(layout)
            return
        }
        guard let migrated = migrateOldLayout(layout, minimumStage: requestedStage) else {
            message = tr("当前物品无法放入该规格，请先整理背包")
            return
        }
        capacityStage = migrated.stage
        if !economy.ownedBagStages.contains(migrated.stage) { economy.ownedBagStages.append(migrated.stage) }
        equipDefaultBagStyle(for: capacities[migrated.stage].bagCategory)
        _ = save(migrated.layout)
    }

    @discardableResult func setProgressForTesting(balanceCents: Int?, completedCigarettes: Int?,
                                                  craftCount: Int?, soldCount: Int?) -> Bool {
        guard let rules = economyRules,
              [balanceCents, completedCigarettes, craftCount, soldCount].compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else {
            message = tr("请输入有效的非负数")
            return false
        }
        var next = economy
        let now = Date()
        // Settle elapsed time at the old rank before changing the completion count.
        next.settle(at: now, rules: rules)
        if let balanceCents { next.balanceCents = balanceCents }
        if let completedCigarettes { next.completedCigarettes = completedCigarettes }
        if let craftCount { next.recoveryCraftCount = craftCount }
        if let soldCount { next.recoveryItemsSold = soldCount }
        return saveDeveloperEdit(layout, economy: next, message: tr("测试进度已更新"))
    }

    @discardableResult func grantForTesting(product: StoreProduct, count: Int) -> Bool {
        guard (1...(layout.columns * layout.rows)).contains(count),
              economyRules?.products.contains(product) == true else {
            message = tr("请选择有效的道具和数量")
            return false
        }
        if let effect = product.passiveEffect {
            guard count == 1 else {
                message = tr("这类道具每次只能发放一件")
                return false
            }
            guard !hasCarriedTool(effect) else {
                message = tr("该档道具已在背包中生效")
                return false
            }
        }
        var next = layout
        do {
            for _ in 0..<count {
                (next, _) = try ShopTransaction.prepare(product: product, layout: next, economy: economy, priceCents: 0)
            }
        } catch {
            message = tr("背包空间不足，请先整理或腾出空间")
            return false
        }
        return saveDeveloperEdit(next, message: tr("已发放 {{0}} 件 {{1}}", count, tr(product.name)))
    }

    @discardableResult func grantForTesting(material: RecoveryMaterial, count: Int) -> Bool {
        var next = layout
        guard count > 0,
              count <= layout.columns * layout.rows * material.stackLimit,
              next.addRecovery(material, count: count) == count else {
            message = tr("背包放不下所选数量")
            return false
        }
        return saveDeveloperEdit(next, message: tr("已发放 {{0}} 件 {{1}}", count, material.title))
    }

    @discardableResult func editStoredItemForTesting(_ id: UUID, count: Int?) -> Bool {
        var next = layout
        guard let index = next.items.firstIndex(where: { $0.id == id && $0.location == .stored }) else {
            message = tr("该物品已不在背包中")
            return false
        }
        let item = next.items[index]
        if let count {
            if item.kind == .cigaretteBox,
               let state = CigaretteBoxView.inventoryState(withStock: count, from: item.state) {
                next.items[index].state = state
            } else if let material = item.kind.recoveryMaterial, (1...material.stackLimit).contains(count) {
                next.setRecoveryCount(count, for: id)
            } else {
                message = tr("数量超出该物品的可用范围")
                return false
            }
        } else {
            next.items.remove(at: index)
        }
        return saveDeveloperEdit(next, message: tr("测试库存已更新"))
    }

    private func saveDeveloperEdit(_ next: InventoryLayout, economy: EconomyState? = nil, message success: String) -> Bool {
        guard captureDeveloperSaveIfNeeded(), save(next, economy: economy) else { return false }
        message = success
        return true
    }

    private init() {
        hasDeveloperSaveBackup = defaults.data(forKey: developerBackupKey) != nil
        hasInventoryTestSnapshot = defaults.data(forKey: inventoryTestBackupKey) != nil
        if let rules = economyRules { economy = EconomyState(balanceCents: rules.startingCents) }
        else { canWrite = false; message = tr("商店配置无法读取，原存档已保留。") }
        let savedBagStyles = defaults.dictionary(forKey: "inventoryBagStylesByCategoryV1") as? [String: String] ?? [:]
        var needsBagMigration = false
        var needsStatisticsMigration = false
        var newDocument = false
        if let data = defaults.data(forKey: dataKey) {
            if let decoded = try? JSONDecoder().decode(Document.self, from: data), (1...6).contains(decoded.version),
               decoded.version < 3 || decoded.economy.map({ $0.balanceCents >= 0 && $0.completedCigarettes >= 0 && $0.incomeRemainder.isFinite && (0..<100).contains($0.incomeRemainder) && $0.pendingIncomeCents.isFinite && (0...10_000_000_000).contains($0.pendingIncomeCents) && $0.incomeIntervalElapsed.isFinite && (0..<86_400).contains($0.incomeIntervalElapsed) && $0.lastIncomeTime.timeIntervalSinceReferenceDate.isFinite && (decoded.version < 5 || ($0.ownedBagStyleIDs != nil && $0.activeBagStyleID != nil && ($0.ownedBagStyleIDs ?? []).contains($0.activeBagStyleID ?? ""))) }) == true {
                needsBagMigration = decoded.version < 5
                needsStatisticsMigration = decoded.version < 6
                if needsBagMigration, canWrite, defaults.data(forKey: "inventoryDocumentBeforeBagSeparationV1") == nil {
                    defaults.set(data, forKey: "inventoryDocumentBeforeBagSeparationV1")
                }
                if needsStatisticsMigration, canWrite, defaults.data(forKey: "inventoryDocumentBeforeProgressStatsV1") == nil {
                    defaults.set(data, forKey: "inventoryDocumentBeforeProgressStatsV1")
                }
                if decoded.version < 3, canWrite, defaults.data(forKey: "inventoryDocumentBeforeEconomyV1") == nil {
                    defaults.set(data, forKey: "inventoryDocumentBeforeEconomyV1")
                }
                if decoded.version == 3, canWrite, defaults.data(forKey: "inventoryDocumentBeforeHourlyV1") == nil {
                    defaults.set(data, forKey: "inventoryDocumentBeforeHourlyV1")
                }
                if let saved = decoded.economy { economy = saved }
                if decoded.version < 3 { economy.ownedBagStages = Array(0..<capacities.count) }
                if decoded.version >= 2, let stage = decoded.capacityStage, capacities.indices.contains(stage),
                   decoded.layout.columns == capacities[stage].columns, decoded.layout.rows == capacities[stage].rows {
                    if decoded.layout.hasValidStoredPlacements {
                        capacityStage = stage
                        layout = decoded.layout
                    } else if let migrated = migrateOldLayout(decoded.layout, minimumStage: stage) {
                        capacityStage = migrated.stage
                        message = tr("烟灰缸规格已更新，背包物品已重新摆放。")
                        layout = migrated.layout
                    } else {
                        capacityStage = capacities.count - 1
                        layout = decoded.layout
                        message = tr("已保留现有物品；当前摆放超过背包容量，请先扩容或整理。")
                    }
                } else if let migrated = migrateOldLayout(decoded.layout) {
                    capacityStage = migrated.stage
                    layout = migrated.layout
                } else {
                    // Never discard or shrink a user's old save if it exceeds the new tier sizes.
                    capacityStage = capacities.count - 1
                    layout = decoded.layout
                    message = tr("已保留原有物品；当前内容超过扩容上限，请先整理背包。")
                }
            } else {
                canWrite = false; message = tr("背包存档版本无法识别，原数据已保留。")
            }
        } else { needsBagMigration = true; newDocument = true; migrateLegacyItems() }
        migrateBagStyles(savedBagStyles)
        if needsBagMigration {
            let selected = bagStylesByCategory[currentBagCategory.rawValue]
                ?? InventoryBagStyle.styles(for: currentBagCategory).first?.id ?? "urban-sling"
            economy.migrateBagStyles(selected: selected, previouslySelected: Array(bagStylesByCategory.values))
        }
        migrateDeprecatedBoxPresets()
        if !economy.ownedBagStages.contains(capacityStage) { economy.ownedBagStages.append(capacityStage) }
        let defaultStyleID = currentBagCategory.defaultStyleID
        let activeStyle = economy.activeBagStyleID.flatMap(InventoryBagStyle.item)
        if activeStyle?.category != currentBagCategory {
            economy.activeBagStyleID = defaultStyleID
            if !(economy.ownedBagStyleIDs ?? []).contains(defaultStyleID) {
                economy.ownedBagStyleIDs = (economy.ownedBagStyleIDs ?? []) + [defaultStyleID]
            }
        }
        if needsBagMigration || needsStatisticsMigration {
            if save(layout), newDocument { defaults.set(true, forKey: migrationKey) }
        }
        else if economy.activeBagStyleID == defaultStyleID, activeStyle?.category != currentBagCategory { _ = save(layout) }
        economy.beginOnlineSession(at: Date())
        _ = save(layout, economy: economy)
        syncPassiveEffects()
        settleIncome()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.settleIncome() }
        }
    }

    private func migrateBagStyles(_ saved: [String: String]) {
        var migrated: [String: String] = [:]
        for category in InventoryBagCategory.allCases {
            guard let styleID = saved[category.rawValue],
                  InventoryBagStyle.item(styleID)?.category == category else { continue }
            migrated[category.rawValue] = styleID
        }

        let category = currentBagCategory
        if migrated[category.rawValue] == nil, let legacyID = saved[category.legacyGroup] {
            let compatibleID = InventoryBagStyle.item(legacyID)?.category == category ? legacyID : nil
            migrated[category.rawValue] = compatibleID ?? InventoryBagStyle.styles(for: category).first?.id
        }

        bagStylesByCategory = migrated
        if migrated != saved { defaults.set(migrated, forKey: "inventoryBagStylesByCategoryV1") }
    }

    private func migrateLegacyItems() {
        let legacyKeys = ["cigaretteBoxRemaining", "cigaretteBoxPosition", "lighterPositionV1", "ashtrayPositionV1"]
        if !legacyKeys.contains(where: { defaults.object(forKey: $0) != nil }) {
            layout = InventoryLayout(columns: capacities[0].columns, rows: capacities[0].rows)
            return
        }
        economy.ownedBagStages = Array(0..<capacities.count)
        // Legacy desktop objects historically used coordinates in a 10×6 board.
        var migrated = InventoryLayout(columns: 10, rows: 6)
        let boxStyle = CigaretteBoxStyle.migratedPresetID(defaults.string(forKey: "cigaretteBoxStyleV1") ?? "jade-green")
        let lighterStyle = defaults.string(forKey: "lighterStyleV1") ?? "silver-flint"
        let trayStyle = defaults.string(forKey: "ashtrayStyleV1") ?? "clear-glass"
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        func point(_ key: String, fallback: NSPoint) -> NSPoint {
            let value = defaults.dictionary(forKey: key)
            return NSPoint(x: (value?["x"] as? NSNumber)?.doubleValue ?? fallback.x,
                           y: (value?["y"] as? NSNumber)?.doubleValue ?? fallback.y)
        }
        let boxPosition = point("cigaretteBoxPosition", fallback: NSPoint(x: visible.maxX - 400, y: visible.minY + 70))
        let lighterSaved = point("lighterPositionV1", fallback: NSPoint(x: visible.midX - 135, y: visible.minY + 145))
        let trayPosition = point("ashtrayPositionV1", fallback: NSPoint(x: visible.minX + 45, y: visible.minY + 55))
        let boxState = try? JSONSerialization.data(withJSONObject: [
            "remaining": defaults.object(forKey: "cigaretteBoxRemaining") ?? 20,
            "slots": defaults.array(forKey: "cigaretteBoxSlots") ?? Array(0..<20)
        ])
        let lighterState = try? JSONSerialization.data(withJSONObject: [
            "fuel": defaults.object(forKey: "lighterFuelLevelV1") ?? 0.9,
            "flame": defaults.object(forKey: "lighterFlameLevelV1") ?? 0.55
        ])
        let items = [
            InventoryItem(kind: .cigaretteBox, styleID: boxStyle, column: 0, row: 0,
                          desktopTransform: InventoryTransform(x: boxPosition.x, y: boxPosition.y,
                                                               rotation: defaults.double(forKey: "cigaretteBoxRotation")), state: boxState),
            InventoryItem(kind: .lighter, styleID: lighterStyle, column: 3, row: 0,
                          desktopTransform: InventoryTransform(x: lighterSaved.x - LighterView.canvasPadding,
                                                               y: lighterSaved.y - LighterView.canvasPadding,
                                                               rotation: defaults.double(forKey: "lighterRotationV1")), state: lighterState),
            InventoryItem(kind: .ashtray, styleID: trayStyle, column: 4, row: 0,
                          desktopTransform: InventoryTransform(x: trayPosition.x, y: trayPosition.y,
                                                               rotation: defaults.double(forKey: "ashtrayRotationV1")))
        ]
        // The 3×3 ashtray makes the starter set exceed the 15-cell tier, so the
        // initial layout is moved to the smallest tier that safely contains all items.
        migrated.items = items
        let migratedResult = migrateOldLayout(migrated) ?? (layout: migrated, stage: capacities.count - 1)
        capacityStage = migratedResult.stage
        layout = migratedResult.layout
    }

    /// Change only the box's style key. The opaque state blob and every layout
    /// field (including empty slots, position, rotation and extraction mode)
    /// remain byte-for-byte associated with the same inventory item.
    private func migrateDeprecatedBoxPresets() {
        var next = layout
        var changed = false
        for index in next.items.indices where [.cigaretteBox, .emptyPack, .premiumEmptyPack].contains(next.items[index].kind) {
            let canonical = CigaretteBoxStyle.migratedPresetID(next.items[index].styleID)
            guard canonical != next.items[index].styleID else { continue }
            next.items[index].styleID = canonical
            changed = true
        }
        if changed { _ = save(next) }
        let legacyID = defaults.string(forKey: "cigaretteBoxStyleV1")
        if let legacyID {
            let canonical = CigaretteBoxStyle.migratedPresetID(legacyID)
            if canonical != legacyID { defaults.set(canonical, forKey: "cigaretteBoxStyleV1") }
        }
    }

    @discardableResult private func save(_ value: InventoryLayout, economy nextEconomy: EconomyState? = nil) -> Bool {
        let nextEconomy = nextEconomy ?? economy
        guard canWrite, let data = try? JSONEncoder().encode(Document(version: 6, layout: value, capacityStage: capacityStage, economy: nextEconomy)) else { message = tr("无法保存背包"); return false }
        defaults.set(data, forKey: dataKey)
        layout = value
        economy = nextEconomy
        if let economyRules { WidgetSnapshotBridge.publish(economy: nextEconomy, rules: economyRules) }
        syncPassiveEffects()
        return true
    }

    private func syncPassiveEffects() {
        defaults.set(lighterBurnDurationMultiplier, forKey: "inventoryToolLighterRuntimeMultiplierV1")
        defaults.set(ashtrayCapacityMultiplier, forKey: "inventoryToolAshtrayCapacityMultiplierV1")
    }

    func settleIncome(at now: Date = Date()) {
        guard let rules = economyRules, canWrite else { return }
        var next = economy
        next.settle(at: now, rules: rules)
        if next != economy { _ = save(layout, economy: next) }
    }

    /// Explicit developer action; preserve a recoverable copy before replacing the save.
    @discardableResult func resetForTesting() -> Bool {
        guard let rules = economyRules, canWrite else { message = tr("无法重置存档"); return false }
        guard captureDeveloperSaveIfNeeded() else { return false }
        if let data = defaults.data(forKey: dataKey) { defaults.set(data, forKey: "inventoryDocumentBeforeDebugResetV1") }
        let oldStage = capacityStage
        capacityStage = 0
        let empty = InventoryLayout(columns: capacities[0].columns, rows: capacities[0].rows)
        guard save(empty, economy: EconomyState(balanceCents: rules.startingCents)) else { capacityStage = oldStage; return false }
        pendingStoreBack = nil
        message = tr("测试存档已重置")
        return true
    }

    func captureDeveloperSave() {
        if captureDeveloperSaveIfNeeded() { message = tr("已保存玩家存档快照") }
    }

    @discardableResult func restoreDeveloperSave() -> Bool {
        guard canWrite,
              let data = defaults.data(forKey: developerBackupKey),
              let document = try? JSONDecoder().decode(Document.self, from: data),
              (1...6).contains(document.version),
              var savedEconomy = document.economy else {
            message = tr("没有可恢复的玩家存档快照")
            return false
        }
        let previousStage = capacityStage
        let restoredStage = document.capacityStage.flatMap { capacities.indices.contains($0) ? $0 : nil }
            ?? capacities.firstIndex { $0.columns == document.layout.columns && $0.rows == document.layout.rows }
            ?? previousStage
        capacityStage = restoredStage
        savedEconomy.beginOnlineSession(at: Date())
        guard save(document.layout, economy: savedEconomy) else {
            capacityStage = previousStage
            return false
        }
        defaults.removeObject(forKey: developerBackupKey)
        hasDeveloperSaveBackup = false
        pendingStoreBack = nil
        message = tr("已恢复测试前的玩家存档")
        return true
    }

    private func captureInventoryTestSnapshotIfNeeded() {
        guard defaults.data(forKey: inventoryTestBackupKey) == nil else { return }
        let snapshot = InventoryTestSnapshot(
            columns: layout.columns,
            rows: layout.rows,
            capacityStage: capacityStage,
            storedItems: layout.items.filter { $0.location == .stored },
            activeBagStyleID: economy.activeBagStyleID,
            ownedBagStyleIDs: economy.ownedBagStyleIDs,
            ownedBagStages: economy.ownedBagStages
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: inventoryTestBackupKey)
        hasInventoryTestSnapshot = true
    }

    @discardableResult func restoreInventoryTestSnapshot() -> Bool {
        guard canWrite,
              let data = defaults.data(forKey: inventoryTestBackupKey),
              let snapshot = try? JSONDecoder().decode(InventoryTestSnapshot.self, from: data),
              capacities.indices.contains(snapshot.capacityStage),
              capacities[snapshot.capacityStage].columns == snapshot.columns,
              capacities[snapshot.capacityStage].rows == snapshot.rows else {
            message = tr("没有可恢复的测试前背包状态")
            return false
        }
        let restoredLayout = InventoryLayout(
            columns: snapshot.columns,
            rows: snapshot.rows,
            items: layout.items.filter { $0.location == .desktop } + snapshot.storedItems
        )
        guard restoredLayout.hasValidStoredPlacements else {
            message = tr("测试前背包状态无效，未执行还原")
            return false
        }
        let previousStage = capacityStage
        let previousEconomy = economy
        capacityStage = snapshot.capacityStage
        var restoredEconomy = economy
        restoredEconomy.activeBagStyleID = snapshot.activeBagStyleID
        restoredEconomy.ownedBagStyleIDs = snapshot.ownedBagStyleIDs
        restoredEconomy.ownedBagStages = snapshot.ownedBagStages
        guard save(restoredLayout, economy: restoredEconomy) else {
            capacityStage = previousStage
            economy = previousEconomy
            return false
        }
        defaults.removeObject(forKey: inventoryTestBackupKey)
        hasInventoryTestSnapshot = false
        pendingStoreBack = nil
        message = tr("已还原测试前的背包内容、容量与外观")
        return true
    }

    @discardableResult func resetForPlayer() -> Bool {
        guard let rules = economyRules, canWrite else { message = tr("无法重置存档"); return false }
        if let data = defaults.data(forKey: dataKey) { defaults.set(data, forKey: playerResetBackupKey) }
        let previousStage = capacityStage
        capacityStage = 0
        let empty = InventoryLayout(columns: capacities[0].columns, rows: capacities[0].rows)
        guard save(empty, economy: EconomyState(balanceCents: rules.startingCents)) else {
            capacityStage = previousStage
            return false
        }
        pendingStoreBack = nil
        message = tr("新存档已建立")
        return true
    }

    private func captureDeveloperSaveIfNeeded() -> Bool {
        guard canWrite, let data = defaults.data(forKey: dataKey) else {
            message = tr("当前没有可备份的玩家存档")
            return false
        }
        if !hasDeveloperSaveBackup {
            defaults.set(data, forKey: developerBackupKey)
            hasDeveloperSaveBackup = true
        }
        return true
    }

    @discardableResult func completeCigarette(at now: Date = Date(), fromBoxStyleID: String? = nil) -> Bool {
        guard let rules = economyRules, canWrite else { return false }
        var next = economy
        next.settle(at: now, rules: rules)
        guard next.completedCigarettes < Int.max else { return false }
        next.completedCigarettes += 1
        next.recordCigaretteCompletion(styleID: fromBoxStyleID)
        return save(layout, economy: next)
    }

    @discardableResult func purchase(_ product: StoreProduct, at now: Date = Date()) -> Bool {
        guard let rules = economyRules, rules.products.contains(product), canWrite else { message = tr("商店暂不可用"); return false }
        if product.kind == .tool, let effect = product.passiveEffect, hasCarriedTool(effect) {
            message = tr("该档道具已在背包中生效")
            return false
        }
        var nextEconomy = economy
        nextEconomy.settle(at: now, rules: rules)
        let transaction: (InventoryLayout, EconomyState)
        let chargedPrice = purchasePrice(for: product)
        do { transaction = try ShopTransaction.prepare(product: product, layout: layout, economy: nextEconomy, priceCents: chargedPrice) }
        catch {
            _ = save(layout, economy: nextEconomy)
            message = (error as? PurchaseError) == .insufficientFunds ? tr("余额不足，段位津贴会随时间到账") : tr("背包空间不足，请先整理或腾出空间")
            return false
        }
        var purchasedEconomy = transaction.1
        purchasedEconomy.statistics.recordPurchase(kind: product.kind, priceCents: chargedPrice)
        if product.kind == .cigaretteBox { purchasedEconomy.recordCigaretteBoxPurchase(styleID: product.styleID) }
        guard save(transaction.0, economy: purchasedEconomy) else { return false }
        message = product.kind == .tool
            ? tr("已购买 {{0}}，放入背包后持续生效", tr(product.name))
            : (chargedPrice < product.priceCents ? tr("已购入 {{0}}，会员优惠已抵扣", tr(product.name)) : tr("已购买 {{0}}，放入背包", tr(product.name)))
        return true
    }

    @discardableResult func purchaseBag(_ offer: BagOffer, at now: Date = Date()) -> Bool {
        guard let rules = economyRules, rules.bags.contains(offer), canWrite else { message = tr("商店暂不可用"); return false }
        guard offer.stage == capacityStage + 1 else { message = tr("请按顺序解锁下一档背包容量"); return false }
        if economy.ownedBagStages.contains(offer.stage) {
            setCapacityStage(offer.stage)
            return capacityStage == offer.stage
        }
        var next = economy
        next.settle(at: now, rules: rules)
        guard next.balanceCents >= offer.priceCents else {
            _ = save(layout, economy: next); message = tr("余额不足，段位津贴会随时间到账"); return false
        }
        next.balanceCents -= offer.priceCents
        next.statistics.recordCapacityPurchase(priceCents: offer.priceCents)
        next.ownedBagStages.append(offer.stage)
        let capacity = capacities[offer.stage]
        let target = InventoryLayout(columns: capacity.columns, rows: capacity.rows, items: layout.items)
        let defaultStyleID = capacity.bagCategory.defaultStyleID
        next.activeBagStyleID = defaultStyleID
        if !(next.ownedBagStyleIDs ?? []).contains(defaultStyleID) {
            next.ownedBagStyleIDs = (next.ownedBagStyleIDs ?? []) + [defaultStyleID]
        }
        let previousStage = capacityStage
        capacityStage = offer.stage
        guard save(target, economy: next) else { capacityStage = previousStage; return false }
        message = tr("已扩容至 {{0}} 格，并解锁匹配外观 {{1}}", capacity.cells, tr(InventoryBagStyle.item(defaultStyleID)?.name ?? ""))
        return true
    }

    @discardableResult func purchaseBagStyle(_ offer: BagStyleOffer, at now: Date = Date()) -> Bool {
        guard let rules = economyRules, rules.bagStyles.contains(offer), let style = InventoryBagStyle.item(offer.styleID), canWrite else { message = tr("商品暂不可用"); return false }
        guard style.category == currentBagCategory else { message = tr("请先解锁对应容量，再购买这组外观"); return false }
        guard !(economy.ownedBagStyleIDs ?? []).contains(offer.styleID) else { message = tr("已拥有此背包外观"); return false }
        var next = economy; next.settle(at: now, rules: rules)
        guard next.balanceCents >= offer.priceCents else { _ = save(layout, economy: next); message = tr("余额不足，段位津贴会随时间到账"); return false }
        guard var purchased = try? ShopTransaction.prepareBagStyle(offer: offer, economy: next) else { return false }
        purchased.statistics.recordBagStylePurchase(priceCents: offer.priceCents)
        guard save(layout, economy: purchased) else { return false }
        message = tr("已购买背包外观，可在背包中切换")
        return true
    }

    private func migrateOldLayout(_ source: InventoryLayout, minimumStage: Int = 0) -> (layout: InventoryLayout, stage: Int)? {
        for stage in max(0, minimumStage)..<capacities.count {
            let capacity = capacities[stage]
            guard source.occupiedCells <= capacity.cells else { continue }
            var compact = InventoryLayout(columns: capacity.columns, rows: capacity.rows,
                                          items: source.items.filter { $0.location == .desktop })
            let stored = source.items.filter { $0.location == .stored }.sorted {
                let lhsArea = $0.footprint.width * $0.footprint.height
                let rhsArea = $1.footprint.width * $1.footprint.height
                if lhsArea != rhsArea { return lhsArea > rhsArea }
                let lhsEdge = max($0.footprint.width, $0.footprint.height)
                let rhsEdge = max($1.footprint.width, $1.footprint.height)
                if lhsEdge != rhsEdge { return lhsEdge > rhsEdge }
                if $0.row != $1.row { return $0.row < $1.row }
                if $0.column != $1.column { return $0.column < $1.column }
                return $0.id.uuidString < $1.id.uuidString
            }
            for var item in stored {
                if let slot = compact.firstOpenSlot(for: item) {
                    item.column = slot.column; item.row = slot.row
                    compact.items.append(item)
                } else {
                    var rotated = item
                    rotated.isRotated.toggle()
                    guard let slot = compact.firstOpenSlot(for: rotated) else { return nil }
                    rotated.column = slot.column; rotated.row = slot.row
                    compact.items.append(rotated)
                }
            }
            return (compact, stage)
        }
        return nil
    }

    func expandCapacity() {
        guard capacityStage + 1 < capacities.count else { message = tr("背包已达到当前最大容量"); return }
        setCapacityStage(capacityStage + 1)
    }

    func setCapacityStage(_ stage: Int) {
        guard capacities.indices.contains(stage), stage == capacityStage + 1 else {
            message = tr("背包容量只能按顺序向上扩展，不能退回较小规格。")
            return
        }
        guard economy.ownedBagStages.contains(stage) else { message = tr("请先在商店购买下一档容量"); return }
        let capacity = capacities[stage]
        let target: InventoryLayout
        if capacity.columns >= layout.columns && capacity.rows >= layout.rows {
            target = InventoryLayout(columns: capacity.columns, rows: capacity.rows, items: layout.items)
        } else {
            let smaller = InventoryLayout(columns: capacity.columns, rows: capacity.rows, items: layout.items)
            guard let packed = InventoryPacker.pack(smaller) else {
                message = tr("现有物品无法放入 {{0}} 格，请先取出部分物品。", capacity.cells)
                return
            }
            target = packed
        }
        let previousStage = capacityStage
        let previousEconomy = economy
        capacityStage = stage
        equipDefaultBagStyle(for: capacity.bagCategory)
        guard save(target) else { capacityStage = previousStage; economy = previousEconomy; return }
        message = tr("已切换到 {{0}} · {{1}} 格", tr(capacity.name), capacity.cells)
    }

    private func equipDefaultBagStyle(for category: InventoryBagCategory) {
        let styleID = category.defaultStyleID
        economy.activeBagStyleID = styleID
        if !(economy.ownedBagStyleIDs ?? []).contains(styleID) {
            economy.ownedBagStyleIDs = (economy.ownedBagStyleIDs ?? []) + [styleID]
        }
    }

    func move(_ id: UUID, column: Int, row: Int) {
        var next = layout
        guard next.place(id, column: column, row: row) else { message = tr("这里放不下"); return }
        message = nil; _ = save(next)
    }

    func rotate(_ id: UUID) {
        rotate(id, by: 1)
    }

    func rotate(_ id: UUID, by quarterTurns: Int) {
        guard let item = layout.items.first(where: { $0.id == id }) else { return }
        guard !quarterTurns.isMultiple(of: 2) else { return }
        let targetTurns = item.isRotated ? 0 : 1
        var next = layout
        if !next.place(id, column: item.column, row: item.row, rotationQuarterTurns: targetTurns) {
            let turnedItem = itemWithRotation(item, turns: targetTurns)
            let candidate = rotationCandidates(item: item, columns: next.columns, rows: next.rows)
                .first { next.canPlace(turnedItem, at: $0.column, row: $0.row, ignoring: item.id) }
            guard let candidate else { message = tr("附近没有合适位置，请先整理背包"); return }
            guard next.place(id, column: candidate.column, row: candidate.row, rotationQuarterTurns: targetTurns) else { message = tr("附近没有合适位置，请先整理背包"); return }
        }
        message = nil; _ = save(next)
    }

    private func itemWithRotation(_ item: InventoryItem, turns: Int) -> InventoryItem { var value = item; value.isRotated = !turns.isMultiple(of: 2); return value }
    private func rotationCandidates(item: InventoryItem, columns: Int, rows: Int) -> [(column: Int, row: Int)] {
        (0..<rows).flatMap { row in (0..<columns).map { (column: $0, row: row) } }
            .sorted {
                let ld = abs($0.column - item.column) + abs($0.row - item.row)
                let rd = abs($1.column - item.column) + abs($1.row - item.row)
                return ld == rd ? ($0.row == $1.row ? $0.column < $1.column : $0.row < $1.row) : ld < rd
            }
    }

    @discardableResult func setLocation(_ id: UUID, _ location: InventoryLocation) -> Bool {
        guard let index = layout.items.firstIndex(where: { $0.id == id }) else { return false }
        if location == .stored {
            return storeBack(id) == .stored
        }
        guard layout.items[index].kind.canDeploy else { return false }
        var next = layout
        next.items[index].location = .desktop
        message = nil; return save(next)
    }

    func storeBack(_ id: UUID) -> InventoryStoreBackResult {
        guard let index = layout.items.firstIndex(where: { $0.id == id }),
              layout.items[index].location == .desktop else { return .noSpace }
        pendingStoreBack = nil
        var next = layout
        next.items[index].location = .stored
        let originalRotation = next.items[index].isRotated
        for rotated in [originalRotation, !originalRotation] {
            next.items[index].isRotated = rotated
            if let slot = next.firstOpenSlot(for: next.items[index]) {
                next.items[index].column = slot.column
                next.items[index].row = slot.row
                message = nil
                return save(next) ? .stored : .noSpace
            }
        }
        guard let rearranged = InventoryPacker.pack(next) else {
            message = tr("背包空间不足，物品仍留在桌面")
            return .noSpace
        }
        pendingStoreBack = (id, rearranged)
        message = tr("需要整理背包才能放回这件物品")
        return .requiresReorganization
    }

    @discardableResult func confirmStoreBackAfterReorganization(_ id: UUID) -> Bool {
        guard let pendingStoreBack, pendingStoreBack.id == id else { return false }
        self.pendingStoreBack = nil
        message = tr("已自动整理并放回背包")
        return save(pendingStoreBack.layout)
    }

    func cancelPendingStoreBack(_ id: UUID) {
        guard pendingStoreBack?.id == id else { return }
        pendingStoreBack = nil
        message = nil
    }

    func autoOrganize() {
        guard let rearranged = InventoryPacker.pack(layout) else {
            message = tr("无法在当前容量内摆放全部物品")
            return
        }
        guard rearranged != layout else { message = tr("背包已经整理好了"); return }
        message = nil
        _ = save(rearranged)
    }

    func setMessage(_ value: String?) { message = value }

    func updateState(_ id: UUID, state: Data?) {
        guard let index = layout.items.firstIndex(where: { $0.id == id }) else { return }
        var next = layout; next.items[index].state = state; _ = save(next)
    }

    func updateStyle(_ id: UUID, styleID: String) {
        guard let index = layout.items.firstIndex(where: { $0.id == id }) else { return }
        var next = layout; next.items[index].styleID = styleID; _ = save(next)
    }

    func updateTransform(_ id: UUID, transform: InventoryTransform) {
        guard let index = layout.items.firstIndex(where: { $0.id == id }) else { return }
        var next = layout; next.items[index].desktopTransform = transform; _ = save(next)
    }

    func discard(_ id: UUID) {
        guard let item = layout.items.first(where: { $0.id == id && $0.location == .stored }) else { return }
        var next = layout
        next.items.removeAll { $0.id == id }
        var nextEconomy = economy
        nextEconomy.statistics.recordDiscard(kind: item.kind)
        if let material = item.kind.recoveryMaterial {
            nextEconomy.recordRecoveryDiscovery(material)
        }
        message = nil
        _ = save(next, economy: nextEconomy)
    }

    func collectRecovery(_ material: RecoveryMaterial, count: Int) -> Int {
        var next = layout
        let accepted = next.addRecovery(material, count: count)
        return accepted > 0 && save(next) ? accepted : 0
    }

    /// Save partial ash alongside the stacks it completes, in one inventory write.
    func collectAshMass(_ offered: [(batch: AshRecoveryBatch, mass: Int)]) -> [AshRecoveryBatch: Int] {
        var next = layout
        var wallet = economy
        var accepted: [AshRecoveryBatch: Int] = [:]
        let unit = RecoveryMaterial.massPerUnit
        var changed = false
        for (batch, amount) in offered where batch.material.isAsh && amount > 0 {
            let material = batch.material
            let previous = min(RecoveryMaterial.legacyMassPerUnit - 1,
                               max(0, wallet.recoveryRemainders[material.rawValue, default: 0]))
            let whole = (amount + previous) / unit
            let stored = next.addRecovery(material, count: whole, batchID: batch.id)
            let taken = min(amount, max(0, (stored + 1) * unit - 1 - previous))
            guard taken > 0 || stored > 0 else { continue }
            wallet.recoveryRemainders[material.rawValue] = previous + taken - stored * unit
            if taken > 0 { accepted[batch, default: 0] += taken }
            changed = true
        }
        return changed && save(next, economy: wallet) ? accepted : [:]
    }

    var recoveryItemCount: Int {
        layout.items.reduce(0) { $0 + $1.recoveryCount }
    }

    func mergeRecovery(from source: UUID, into target: UUID) {
        var next = layout
        let count = next.mergeRecovery(from: source, into: target)
        guard count > 0, save(next) else { return }
        message = tr("已合并 {{0}} 个", count)
    }

    @discardableResult func mixRecoveryMaterials(_ selected: [RecoveryIngredient: Int]) -> RecoveryMixResult {
        var next = layout
        let result = next.mixRecoveryMaterials(selected)
        guard case .crafted(let product, let count) = result else {
            if result == .noSpace { message = tr("背包缺少空格") }
            else if result == .missingMaterials { message = tr("材料不足") }
            return result
        }
        var nextEconomy = economy
        nextEconomy.recordRecoveryCraft(count: count)
        nextEconomy.recordRecoveryDiscovery(product)
        guard save(next, economy: nextEconomy) else { return .saveFailed }
        message = nil
        return result
    }

    @discardableResult func claimAchievement(id: String, current: Int, target: Int, rewardCents: Int) -> Bool {
        guard current >= target, target > 0, rewardCents > 0,
              !economy.claimedAchievementIDs.contains(id), !id.isEmpty else { return false }
        var nextEconomy = economy
        if let rules = economyRules { nextEconomy.settle(at: Date(), rules: rules) }
        let (balance, overflow) = nextEconomy.balanceCents.addingReportingOverflow(rewardCents)
        guard !overflow else { return false }
        nextEconomy.balanceCents = balance
        nextEconomy.claimAchievement(id)
        nextEconomy.recordIncome(rewardCents, source: .achievement, at: Date())
        guard save(layout, economy: nextEconomy) else { return false }
        message = tr("成就奖励已领取 +{{0}}", recoveryMoney(rewardCents))
        return true
    }

    @discardableResult func salvageEmptyPack(_ id: UUID) -> Bool {
        guard let box = item(id), box.isEmptyPack else { return false }
        var next = layout
        guard next.salvageEmptyPack(id) else {
            message = tr("背包没有足够的格位")
            return false
        }
        guard save(next) else { return false }
        message = tr("空盒已收进背包，可出售或合成。")
        return true
    }

    func sellRecovery(_ quote: RecoverySale, sellAll: Bool, at now: Date = Date()) {
        let current = layout.recoverySale(quote.material, quantity: sellAll ? nil : quote.count, hour: quote.hour)
        guard quote.hour == RecoveryMaterial.marketHour(at: now), quote == current else {
            message = tr("报价或库存有变动，请重新确认。")
            return
        }
        guard quote.cents > 0 else { return }
        var next = layout
        var wallet = economy
        for line in quote.lines {
            if let item = layout.items.first(where: { $0.id == line.id }),
               let material = item.kind.recoveryMaterial {
                wallet.recordRecoveryDiscovery(material)
            }
            next.setRecoveryCount(line.originalCount - line.count, for: line.id)
        }
        if let rules = economyRules { wallet.settle(at: now, rules: rules) }
        let (balance, overflow) = wallet.balanceCents.addingReportingOverflow(quote.cents)
        guard !overflow else { return }
        wallet.balanceCents = balance
        wallet.recordRecoverySale(count: quote.count, cents: quote.cents, at: now)
        if save(next, economy: wallet) {
            message = tr("回收到账 {{0}}", recoveryMoney(quote.cents))
        }
    }

    func item(_ id: UUID) -> InventoryItem? { layout.items.first { $0.id == id } }

    func hasDiscoveredRecoveryItem(_ material: RecoveryMaterial) -> Bool {
        economy.discoveredRecoveryItemIDs.contains(material.rawValue)
            || layout.items.contains { $0.kind == material.kind && $0.recoveryCount > 0 }
    }
}
