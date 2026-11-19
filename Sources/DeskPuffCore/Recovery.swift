import Foundation

public enum RecoveryMaterial: String, Codable, CaseIterable, Identifiable {
    case fineAsh, ashClump, cigaretteButt, emberStone
    case emptyPack, premiumEmptyPack, ashSeal, gildedRelic
    case cloudMarble, fortuneCoin, smokeDuck, goldenCigarette, ashDumpling
    case phoneBooth, paperclipFrog, deskFan, marbleRun, mysteryJunk
    case redFoilMisprint, celadonSmokeMark, filterFossil, redBlueOverprint
    case goldSeal, fortuneFold, cloudGlass, paperCicada, ashSpoon, starAsh
    case lotusFoil, redTowerTicket, doubleJoySeal, riverCloudMedallion
    case peonyAshPrint, silverLining, ashLantern, emberStamp, boxFoldPavilion, moonInCellophane
    case doubleFoilFold, celadonAshPearl, ruyiAshRibbon, goldenCloudStamp, nanjingPaperWhistle
    case furongCinderButton, doubleJoyCigaretteSleeve, liqunAshSleeve, lotusEmberPetal
    case redTowerAshCoin, ashCigaretteRing, zhonghuaSmokeFilm, yuxiFilterCharm
    case nanjingGrayLeaf, furongEmberClip, doubleJoyAshBadge, crossBrandLantern
    case oldShopLedgerSeal, lotusGoldenCompass, whiteRedFoldedStage
    public static let massPerUnit = 100
    public static let legacyMassPerUnit = 1_000
    public var id: String { rawValue }
    public var kind: InventoryKind {
        switch self {
        case .fineAsh: .fineAsh
        case .ashClump: .ashClump
        case .cigaretteButt: .cigaretteButt
        case .emberStone: .emberStone
        case .emptyPack: .emptyPack
        case .premiumEmptyPack: .premiumEmptyPack
        case .ashSeal: .ashSeal
        case .gildedRelic: .gildedRelic
        case .cloudMarble: .cloudMarble
        case .fortuneCoin: .fortuneCoin
        case .smokeDuck: .smokeDuck
        case .goldenCigarette: .goldenCigarette
        case .ashDumpling: .ashDumpling
        case .phoneBooth: .phoneBooth
        case .paperclipFrog: .paperclipFrog
        case .deskFan: .deskFan
        case .marbleRun: .marbleRun
        case .mysteryJunk: .mysteryJunk
        case .redFoilMisprint: .redFoilMisprint
        case .celadonSmokeMark: .celadonSmokeMark
        case .filterFossil: .filterFossil
        case .redBlueOverprint: .redBlueOverprint
        case .goldSeal: .goldSeal
        case .fortuneFold: .fortuneFold
        case .cloudGlass: .cloudGlass
        case .paperCicada: .paperCicada
        case .ashSpoon: .ashSpoon
        case .starAsh: .starAsh
        case .lotusFoil: .lotusFoil
        case .redTowerTicket: .redTowerTicket
        case .doubleJoySeal: .doubleJoySeal
        case .riverCloudMedallion: .riverCloudMedallion
        case .peonyAshPrint: .peonyAshPrint
        case .silverLining: .silverLining
        case .ashLantern: .ashLantern
        case .emberStamp: .emberStamp
        case .boxFoldPavilion: .boxFoldPavilion
        case .moonInCellophane: .moonInCellophane
        case .doubleFoilFold: .doubleFoilFold
        case .celadonAshPearl: .celadonAshPearl
        case .ruyiAshRibbon: .ruyiAshRibbon
        case .goldenCloudStamp: .goldenCloudStamp
        case .nanjingPaperWhistle: .nanjingPaperWhistle
        case .furongCinderButton: .furongCinderButton
        case .doubleJoyCigaretteSleeve: .doubleJoyCigaretteSleeve
        case .liqunAshSleeve: .liqunAshSleeve
        case .lotusEmberPetal: .lotusEmberPetal
        case .redTowerAshCoin: .redTowerAshCoin
        case .ashCigaretteRing: .ashCigaretteRing
        case .zhonghuaSmokeFilm: .zhonghuaSmokeFilm
        case .yuxiFilterCharm: .yuxiFilterCharm
        case .nanjingGrayLeaf: .nanjingGrayLeaf
        case .furongEmberClip: .furongEmberClip
        case .doubleJoyAshBadge: .doubleJoyAshBadge
        case .crossBrandLantern: .crossBrandLantern
        case .oldShopLedgerSeal: .oldShopLedgerSeal
        case .lotusGoldenCompass: .lotusGoldenCompass
        case .whiteRedFoldedStage: .whiteRedFoldedStage
        }
    }
    public var isAsh: Bool { self == .fineAsh || self == .ashClump }
    public var isCollectible: Bool { RecoveryRecipe.products.contains(self) }

    public var stackLimit: Int {
        switch self {
        case .fineAsh: 50
        case .ashClump: 20
        case .cigaretteButt, .emberStone, .emptyPack, .premiumEmptyPack, .ashSeal, .gildedRelic,
             .cloudMarble, .fortuneCoin, .smokeDuck, .goldenCigarette, .ashDumpling,
             .phoneBooth, .paperclipFrog, .deskFan, .marbleRun, .mysteryJunk,
             .redFoilMisprint, .celadonSmokeMark, .filterFossil, .redBlueOverprint,
             .goldSeal, .fortuneFold, .cloudGlass, .paperCicada, .ashSpoon, .starAsh,
             .lotusFoil, .redTowerTicket, .doubleJoySeal, .riverCloudMedallion,
             .peonyAshPrint, .silverLining, .ashLantern, .emberStamp, .boxFoldPavilion,
             .moonInCellophane: 5
        case .doubleFoilFold, .celadonAshPearl, .ruyiAshRibbon, .goldenCloudStamp, .nanjingPaperWhistle,
             .furongCinderButton, .doubleJoyCigaretteSleeve, .liqunAshSleeve, .lotusEmberPetal,
             .redTowerAshCoin, .ashCigaretteRing, .zhonghuaSmokeFilm, .yuxiFilterCharm,
             .nanjingGrayLeaf, .furongEmberClip, .doubleJoyAshBadge, .crossBrandLantern,
             .oldShopLedgerSeal, .lotusGoldenCompass, .whiteRedFoldedStage: 5
        }
    }

    public var stackStyleID: String { isAsh ? "\(rawValue)-small-grain" : rawValue }

    public func priceCents(hour: Int64, legacyStack: Bool = false) -> Int {
        let range: ClosedRange<Int>
        let salt: UInt64
        switch self {
        case .fineAsh: (range, salt) = (4...14, 1)
        case .ashClump: (range, salt) = (2...8, 2)
        case .cigaretteButt: (range, salt) = (30...90, 3)
        case .emberStone: (range, salt) = (330...590, 4)
        case .emptyPack, .premiumEmptyPack: (range, salt) = (35...95, 5)
        case .ashSeal: (range, salt) = (640...980, 7)
        case .gildedRelic: (range, salt) = (1150...1690, 8)
        case .cloudMarble: (range, salt) = (540...920, 9)
        case .fortuneCoin: (range, salt) = (850...1320, 10)
        case .smokeDuck: (range, salt) = (180...520, 11)
        case .goldenCigarette: (range, salt) = (950...1480, 12)
        case .ashDumpling: (range, salt) = (120...360, 13)
        case .phoneBooth: (range, salt) = (190...310, 14)
        case .paperclipFrog: (range, salt) = (186...280, 15)
        case .deskFan: (range, salt) = (105...160, 16)
        case .marbleRun: (range, salt) = (320...470, 17)
        case .mysteryJunk: (range, salt) = (1...2, 18)
        case .redFoilMisprint: (range, salt) = (210...270, 19)
        case .celadonSmokeMark: (range, salt) = (260...320, 20)
        case .filterFossil: (range, salt) = (170...250, 21)
        case .redBlueOverprint: (range, salt) = (620...820, 22)
        case .goldSeal: (range, salt) = (280...320, 23)
        case .fortuneFold: (range, salt) = (240...310, 24)
        case .cloudGlass: (range, salt) = (260...320, 25)
        case .paperCicada: (range, salt) = (190...260, 26)
        case .ashSpoon: (range, salt) = (230...310, 27)
        case .starAsh: (range, salt) = (200...280, 28)
        case .lotusFoil: (range, salt) = (280...320, 29)
        case .redTowerTicket: (range, salt) = (240...300, 30)
        case .doubleJoySeal: (range, salt) = (330...470, 31)
        case .riverCloudMedallion: (range, salt) = (420...580, 32)
        case .peonyAshPrint: (range, salt) = (380...520, 33)
        case .silverLining: (range, salt) = (350...490, 34)
        case .ashLantern: (range, salt) = (440...590, 35)
        case .emberStamp: (range, salt) = (740...960, 36)
        case .boxFoldPavilion: (range, salt) = (690...890, 37)
        case .moonInCellophane: (range, salt) = (820...1080, 38)
        case .doubleFoilFold: (range, salt) = (230...310, 39)
        case .celadonAshPearl: (range, salt) = (240...310, 40)
        case .ruyiAshRibbon: (range, salt) = (210...300, 41)
        case .goldenCloudStamp: (range, salt) = (260...320, 42)
        case .nanjingPaperWhistle: (range, salt) = (180...250, 43)
        case .furongCinderButton: (range, salt) = (220...300, 44)
        case .doubleJoyCigaretteSleeve: (range, salt) = (200...280, 45)
        case .liqunAshSleeve: (range, salt) = (230...310, 46)
        case .lotusEmberPetal: (range, salt) = (250...320, 47)
        case .redTowerAshCoin: (range, salt) = (240...310, 48)
        case .ashCigaretteRing: (range, salt) = (200...280, 49)
        case .zhonghuaSmokeFilm: (range, salt) = (350...470, 50)
        case .yuxiFilterCharm: (range, salt) = (390...520, 51)
        case .nanjingGrayLeaf: (range, salt) = (330...450, 52)
        case .furongEmberClip: (range, salt) = (430...580, 53)
        case .doubleJoyAshBadge: (range, salt) = (370...510, 54)
        case .crossBrandLantern: (range, salt) = (1120...1290, 55)
        case .oldShopLedgerSeal: (range, salt) = (1180...1390, 56)
        case .lotusGoldenCompass: (range, salt) = (1100...1270, 57)
        case .whiteRedFoldedStage: (range, salt) = (1150...1350, 58)
        }
        var mixed = UInt64(bitPattern: hour) &+ salt &* 0x9E3779B97F4A7C15
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
        mixed ^= mixed >> 31
        var price = range.lowerBound + Int(mixed % UInt64(range.count))
        if self == .ashClump { price = min(price, RecoveryMaterial.fineAsh.priceCents(hour: hour) - 1) }
        return legacyStack && isAsh ? price * (Self.legacyMassPerUnit / Self.massPerUnit) : price
    }

    public static func marketHour(at date: Date) -> Int64 {
        Int64(floor(date.timeIntervalSince1970 / 3600))
    }
}

public enum RecoveryIngredient: Hashable, Identifiable {
    case material(RecoveryMaterial)
    case pack(styleID: String)

    public var id: String {
        switch self {
        case .material(let material): material.rawValue
        case .pack(let styleID): "pack::\(styleID)"
        }
    }
}

extension InventoryItem {
    public var isEmptyPack: Bool {
        struct PackStock: Decodable { let remaining: Int }
        guard kind == .cigaretteBox, let state else { return false }
        return (try? JSONDecoder().decode(PackStock.self, from: state))?.remaining == 0
    }

    public var craftingIngredient: RecoveryIngredient? {
        guard location == .stored else { return nil }
        switch kind {
        case .cigaretteBox:
            return .pack(styleID: styleID)
        case .emptyPack, .premiumEmptyPack:
            guard recoveryCount > 0 else { return nil }
            return .pack(styleID: styleID)
        case .fineAsh, .ashClump, .cigaretteButt:
            guard !isLegacyAshStack, recoveryCount > 0, let material = kind.recoveryMaterial else { return nil }
            return .material(material)
        default:
            return nil
        }
    }

    fileprivate var craftingCount: Int {
        kind == .cigaretteBox ? 1 : recoveryCount
    }

    public var isLegacyAshStack: Bool {
        guard let material = kind.recoveryMaterial else { return false }
        return material.isAsh && styleID == material.rawValue
    }

    public var recoveryCount: Int {
        if kind == .mysteryJunk && state == nil { return 1 }
        guard let material = kind.recoveryMaterial, let state, state.count == 1,
              let value = state.first, (1...material.stackLimit).contains(Int(value)) else { return 0 }
        return Int(value)
    }
}

extension InventoryLayout {
    /// Only particles from the same physical release can share a stack on intake.
    @discardableResult public mutating func addRecovery(_ material: RecoveryMaterial, count: Int, batchID: UUID? = nil,
                                                        styleID: String? = nil) -> Int {
        guard count > 0 else { return 0 }
        let resolvedStyleID = styleID ?? material.stackStyleID
        var remaining = count
        for index in items.indices where batchID != nil && items[index].recoveryBatchID == batchID
            && items[index].kind == material.kind && items[index].styleID == resolvedStyleID
            && items[index].location == .stored && items[index].recoveryCount > 0 {
            let existing = items[index].recoveryCount
            let add = min(remaining, material.stackLimit - existing)
            items[index].state = Data([UInt8(existing + add)])
            remaining -= add
            if remaining == 0 { return count }
        }
        while remaining > 0 {
            let units = min(material.stackLimit, remaining)
            var item = InventoryItem(kind: material.kind, styleID: resolvedStyleID, state: Data([UInt8(units)]))
            item.recoveryBatchID = batchID
            var slot = firstOpenSlot(for: item)
            if slot == nil && item.footprint.width != item.footprint.height {
                item.isRotated = true
                slot = firstOpenSlot(for: item)
            }
            guard let slot else { break }
            item.column = slot.column
            item.row = slot.row
            items.append(item)
            remaining -= units
        }
        return count - remaining
    }
}

public struct AshRecoveryBatch: Hashable {
    public let material: RecoveryMaterial
    public let id: UUID?

    public init(material: RecoveryMaterial, id: UUID?) {
        self.material = material
        self.id = id
    }
}

public enum RecoveryValueTier: String, CaseIterable, Hashable {
    case low, medium, high
}

public struct RecoveryRecipe: Identifiable {
    public let product: RecoveryMaterial
    public let ingredients: [RecoveryIngredient]
    public var id: RecoveryMaterial { product }
    public var valueTier: RecoveryValueTier {
        if ingredients.count >= 4 || product == .redBlueOverprint { return .high }
        if ingredients.count == 3 { return .medium }
        return .low
    }

    public static let all: [RecoveryRecipe] = {
        func box(_ id: String) -> RecoveryIngredient { .pack(styleID: "user:\(id)") }
        let zhonghua = box("zhonghua-classic")
        let yuxi = box("yuxi-hexie")
        let huanghelou = box("huanghelou-1916-ruyi")
        let huangjinye = box("huangjinye-tianye")
        let nanjing = box("nanjing-xuanhemen")
        let furongwang = box("furongwang-hard")
        let liqun = box("liqun-new")
        let shuangxi = box("shuangxi-classic1906")
        let hongtashan = box("hongtashan-classic1956")
        let lotus = box("diamond-lotus-hard")
        let baisha = box("baisha-hard")
        let ash = RecoveryIngredient.material(.fineAsh)
        let clump = RecoveryIngredient.material(.ashClump)
        let butt = RecoveryIngredient.material(.cigaretteButt)
        return [
            .init(product: .redFoilMisprint, ingredients: [zhonghua, ash]),
            .init(product: .celadonSmokeMark, ingredients: [yuxi, ash]),
            .init(product: .filterFossil, ingredients: [butt, clump]),
            .init(product: .redBlueOverprint, ingredients: [zhonghua, yuxi, ash]),
            .init(product: .goldSeal, ingredients: [huangjinye, clump]),
            .init(product: .fortuneFold, ingredients: [huanghelou, butt]),
            .init(product: .cloudGlass, ingredients: [baisha, ash]),
            .init(product: .paperCicada, ingredients: [nanjing, butt]),
            .init(product: .ashSpoon, ingredients: [furongwang, clump]),
            .init(product: .starAsh, ingredients: [liqun, ash]),
            .init(product: .lotusFoil, ingredients: [lotus, ash]),
            .init(product: .redTowerTicket, ingredients: [hongtashan, butt]),
            .init(product: .doubleJoySeal, ingredients: [shuangxi, clump, ash]),
            .init(product: .riverCloudMedallion, ingredients: [baisha, clump, butt]),
            .init(product: .peonyAshPrint, ingredients: [liqun, clump, ash]),
            .init(product: .silverLining, ingredients: [baisha, butt, ash]),
            .init(product: .ashLantern, ingredients: [lotus, clump, ash]),
            .init(product: .emberStamp, ingredients: [huangjinye, huanghelou, butt, ash]),
            .init(product: .boxFoldPavilion, ingredients: [hongtashan, baisha, clump, ash]),
            .init(product: .moonInCellophane, ingredients: [zhonghua, yuxi, clump, butt]),
            .init(product: .doubleFoilFold, ingredients: [zhonghua, clump]),
            .init(product: .celadonAshPearl, ingredients: [yuxi, clump]),
            .init(product: .ruyiAshRibbon, ingredients: [huanghelou, ash]),
            .init(product: .goldenCloudStamp, ingredients: [huangjinye, ash]),
            .init(product: .nanjingPaperWhistle, ingredients: [nanjing, ash]),
            .init(product: .furongCinderButton, ingredients: [furongwang, ash]),
            .init(product: .doubleJoyCigaretteSleeve, ingredients: [shuangxi, butt]),
            .init(product: .liqunAshSleeve, ingredients: [liqun, butt]),
            .init(product: .lotusEmberPetal, ingredients: [lotus, butt]),
            .init(product: .redTowerAshCoin, ingredients: [hongtashan, clump]),
            .init(product: .ashCigaretteRing, ingredients: [ash, butt]),
            .init(product: .zhonghuaSmokeFilm, ingredients: [zhonghua, butt, ash]),
            .init(product: .yuxiFilterCharm, ingredients: [yuxi, butt, ash]),
            .init(product: .nanjingGrayLeaf, ingredients: [nanjing, clump, ash]),
            .init(product: .furongEmberClip, ingredients: [furongwang, butt, ash]),
            .init(product: .doubleJoyAshBadge, ingredients: [shuangxi, clump, butt]),
            .init(product: .crossBrandLantern, ingredients: [nanjing, furongwang, ash, butt]),
            .init(product: .oldShopLedgerSeal, ingredients: [liqun, shuangxi, ash, butt]),
            .init(product: .lotusGoldenCompass, ingredients: [lotus, huangjinye, clump, butt]),
            .init(product: .whiteRedFoldedStage, ingredients: [baisha, zhonghua, ash, clump])
        ]
    }()

    public static let products = all.map(\.product)

    public static func matching(_ ingredients: Set<RecoveryIngredient>) -> Self? {
        all.first { Set($0.ingredients) == ingredients }
    }
}

public enum RecoveryMixResult: Equatable {
    case crafted(RecoveryMaterial, count: Int)
    case missingMaterials
    case noSpace
    case saveFailed
}

extension InventoryLayout {
    public func recoveryMergeCount(from source: InventoryItem, into target: InventoryItem) -> Int {
        guard source.id != target.id, source.location == .stored, target.location == .stored,
              source.kind == target.kind, source.styleID == target.styleID,
              let material = source.kind.recoveryMaterial, target.recoveryCount > 0 else { return 0 }
        return min(source.recoveryCount, material.stackLimit - target.recoveryCount)
    }

    @discardableResult public mutating func mergeRecovery(from sourceID: UUID, into targetID: UUID) -> Int {
        guard let source = items.first(where: { $0.id == sourceID }),
              let target = items.first(where: { $0.id == targetID }) else { return 0 }
        let count = recoveryMergeCount(from: source, into: target)
        guard count > 0 else { return 0 }
        setRecoveryCount(target.recoveryCount + count, for: target.id)
        setRecoveryCount(source.recoveryCount - count, for: source.id)
        return count
    }

    public var craftingStock: [RecoveryIngredient: Int] {
        items.reduce(into: [:]) { stock, item in
            guard let ingredient = item.craftingIngredient else { return }
            stock[ingredient, default: 0] += item.craftingCount
        }
    }

    @discardableResult public mutating func mixRecoveryMaterials(
        _ selected: [RecoveryIngredient: Int]
    ) -> RecoveryMixResult {
        guard let count = selected.values.min(), count > 0 else { return .missingMaterials }
        var result = self
        for (ingredient, submitted) in selected {
            var remaining = submitted
            let stacks = items.filter { $0.craftingIngredient == ingredient }
                .sorted { $0.craftingCount < $1.craftingCount }
            for stack in stacks where remaining > 0 {
                let used = min(remaining, stack.craftingCount)
                if stack.kind == .cigaretteBox {
                    result.items.removeAll { $0.id == stack.id }
                } else {
                    result.setRecoveryCount(stack.recoveryCount - used, for: stack.id)
                }
                remaining -= used
            }
            guard remaining == 0 else { return .missingMaterials }
        }
        let product = RecoveryRecipe.matching(Set(selected.keys))?.product ?? .mysteryJunk
        guard result.addRecovery(product, count: count) == count else { return .noSpace }
        self = result
        return .crafted(product, count: count)
    }

    @discardableResult public mutating func salvageEmptyPack(_ id: UUID) -> Bool {
        guard let emptyBox = items.first(where: { $0.id == id && $0.isEmptyPack }) else { return false }
        var next = self
        next.items.removeAll { $0.id == id }
        var pack = InventoryItem(kind: .emptyPack, styleID: emptyBox.styleID, state: Data([1]))
        guard let slot = next.firstOpenSlot(for: pack) else { return false }
        pack.column = slot.column
        pack.row = slot.row
        next.items.append(pack)
        self = next
        return true
    }

    public mutating func setRecoveryCount(_ count: Int, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let material = items[index].kind.recoveryMaterial, (0...material.stackLimit).contains(count) else { return }
        if count == 0 { items.remove(at: index) }
        else {
            items[index].state = Data([UInt8(count)])
            items[index].recoveryBatchID = nil
        }
    }

    public func recoverySale(_ material: RecoveryMaterial?, quantity: Int? = nil, hour: Int64) -> RecoverySale {
        var sale = RecoverySale(material: material, hour: hour)
        var remaining = max(0, quantity ?? Int.max)
        for item in items where item.location == .stored && remaining > 0 {
            guard let itemMaterial = item.kind.recoveryMaterial, item.recoveryCount > 0 else { continue }
            let kind: RecoveryMaterial = itemMaterial == .premiumEmptyPack ? .emptyPack : itemMaterial
            guard material == nil || material == kind else { continue }
            let count = min(remaining, item.recoveryCount)
            sale.lines.append(.init(id: item.id, count: count, originalCount: item.recoveryCount,
                                    unitCents: kind.priceCents(hour: hour, legacyStack: item.isLegacyAshStack)))
            if count == item.recoveryCount { sale.slots += item.footprint.width * item.footprint.height }
            remaining -= count
        }
        return sale
    }
}

public struct RecoverySale: Equatable {
    public struct Line: Equatable {
        public let id: UUID
        public let count: Int
        public let originalCount: Int
        public let unitCents: Int
    }

    public let material: RecoveryMaterial?
    public let hour: Int64
    public fileprivate(set) var lines: [Line] = []
    public fileprivate(set) var slots = 0
    public var count: Int { lines.reduce(0) { $0 + $1.count } }
    public var cents: Int { lines.reduce(0) { $0 + $1.count * $1.unitCents } }
}

/// The bag opening is expressed relative to the bag's rotation center.
public struct RecoveryOpening: Equatable {
    public let center: CGPoint
    public let angle: Double
    public let opening: CGRect

    public init(center: CGPoint, angle: Double, opening: CGRect) {
        self.center = center
        self.angle = angle
        self.opening = opening
    }

    public func localPoint(_ point: CGPoint) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let c = cos(angle), s = sin(angle)
        return CGPoint(x: dx * c + dy * s, y: -dx * s + dy * c)
    }

    public func crosses(from start: CGPoint, to end: CGPoint, previous: RecoveryOpening? = nil) -> Bool {
        let a = (previous ?? self).localPoint(start)
        let b = localPoint(end)
        let dx = b.x - a.x
        let dy = b.y - a.y
        var first = 0.0
        var last = 1.0
        for (origin, delta, lower, upper) in [
            (a.x, dx, opening.minX, opening.maxX),
            (a.y, dy, opening.minY, opening.maxY)
        ] {
            if delta == 0 {
                if origin < lower || origin > upper { return false }
                continue
            }
            let entry = (lower - origin) / delta
            let exit = (upper - origin) / delta
            first = max(first, min(entry, exit))
            last = min(last, max(entry, exit))
            if first > last { return false }
        }
        return true
    }
}
