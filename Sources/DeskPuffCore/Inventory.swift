import Foundation

/// A catalog look, an owned physical copy, and its current location are kept
/// separate so future acquisition sources do not become part of the save model.
public enum InventoryKind: String, Codable, CaseIterable, Identifiable {
    case cigaretteBox, lighter, ashtray, tool, fineAsh, ashClump, cigaretteButt, emberStone
    case emptyPack, premiumEmptyPack, ashSeal, gildedRelic
    case cloudMarble, fortuneCoin, smokeDuck, goldenCigarette, ashDumpling, mysteryJunk
    case phoneBooth, paperclipFrog, deskFan, marbleRun
    case redFoilMisprint, celadonSmokeMark, filterFossil, redBlueOverprint
    case goldSeal, fortuneFold, cloudGlass, paperCicada, ashSpoon, starAsh
    case lotusFoil, redTowerTicket, doubleJoySeal, riverCloudMedallion
    case peonyAshPrint, silverLining, ashLantern, emberStamp, boxFoldPavilion, moonInCellophane
    case doubleFoilFold, celadonAshPearl, ruyiAshRibbon, goldenCloudStamp, nanjingPaperWhistle
    case furongCinderButton, doubleJoyCigaretteSleeve, liqunAshSleeve, lotusEmberPetal
    case redTowerAshCoin, ashCigaretteRing, zhonghuaSmokeFilm, yuxiFilterCharm
    case nanjingGrayLeaf, furongEmberClip, doubleJoyAshBadge, crossBrandLantern
    case oldShopLedgerSeal, lotusGoldenCompass, whiteRedFoldedStage
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cigaretteBox: "烟盒"
        case .lighter: "打火机"
        case .ashtray: "烟灰缸"
        case .tool: "随身道具"
        case .fineAsh: "细灰"
        case .ashClump: "灰块"
        case .cigaretteButt: "烟头"
        case .emberStone: "余烬石"
        case .emptyPack, .premiumEmptyPack: "回收烟盒"
        case .ashSeal: "烟纹香囊"
        case .gildedRelic: "鎏金遗物"
        case .cloudMarble: "云纹琉璃珠"
        case .fortuneCoin: "好运结钱"
        case .smokeDuck: "吞云小黄鸭"
        case .goldenCigarette: "金光香烟棒"
        case .ashDumpling: "灰烬小笼包"
        case .phoneBooth: "桌角公用电话"
        case .paperclipFrog: "吞夹纸蛙"
        case .deskFan: "一档就喘风扇"
        case .marbleRun: "桌面过山车"
        case .mysteryJunk: "一坨灰"
        case .redFoilMisprint: "红箔错印"
        case .celadonSmokeMark: "青釉烟纹"
        case .filterFossil: "滤嘴化石"
        case .redBlueOverprint: "红青套印样"
        case .goldSeal: "鎏金封签"
        case .fortuneFold: "折福纸签"
        case .cloudGlass: "云纹玻璃珠"
        case .paperCicada: "纸壳知了"
        case .ashSpoon: "灰釉小匙"
        case .starAsh: "星屑拓片"
        case .lotusFoil: "荷影锡箔"
        case .redTowerTicket: "红塔车票"
        case .doubleJoySeal: "双喜压印章"
        case .riverCloudMedallion: "江云纪念牌"
        case .peonyAshPrint: "牡丹灰拓"
        case .silverLining: "白沙银边"
        case .ashLantern: "灰芯纸灯"
        case .emberStamp: "余烬邮戳"
        case .boxFoldPavilion: "折盒小亭"
        case .moonInCellophane: "玻璃纸月亮"
        case .doubleFoilFold: "双折金箔"
        case .celadonAshPearl: "青釉灰珠"
        case .ruyiAshRibbon: "如意灰绦"
        case .goldenCloudStamp: "天叶云戳"
        case .nanjingPaperWhistle: "炫赫门纸哨"
        case .furongCinderButton: "芙蓉灰扣"
        case .doubleJoyCigaretteSleeve: "双喜烟套"
        case .liqunAshSleeve: "利群烟屑"
        case .lotusEmberPetal: "荷瓣余烬"
        case .redTowerAshCoin: "红塔灰钱"
        case .ashCigaretteRing: "烟灰戒环"
        case .zhonghuaSmokeFilm: "中华烟膜"
        case .yuxiFilterCharm: "玉溪滤嘴坠"
        case .nanjingGrayLeaf: "炫赫门灰叶"
        case .furongEmberClip: "芙蓉余烬夹"
        case .doubleJoyAshBadge: "双喜灰徽"
        case .crossBrandLantern: "红青双牌灯"
        case .oldShopLedgerSeal: "旧摊账本封"
        case .lotusGoldenCompass: "荷叶金罗盘"
        case .whiteRedFoldedStage: "红白折叠戏台"
        }
    }
    public var recoveryMaterial: RecoveryMaterial? { RecoveryMaterial(rawValue: rawValue) }
    public var canDeploy: Bool { self == .cigaretteBox || self == .lighter || self == .ashtray }
    public var footprint: GridSize {
        switch self {
        case .cigaretteBox: GridSize(width: 2, height: 3)
        case .lighter: GridSize(width: 1, height: 3)
        case .ashtray: GridSize(width: 3, height: 3)
        case .tool: GridSize(width: 2, height: 2)
        case .fineAsh, .emberStone, .ashSeal, .gildedRelic, .emptyPack, .premiumEmptyPack,
             .cloudMarble, .fortuneCoin, .smokeDuck, .goldenCigarette, .ashDumpling, .mysteryJunk,
             .phoneBooth, .paperclipFrog, .deskFan, .marbleRun,
             .redFoilMisprint, .celadonSmokeMark, .filterFossil, .redBlueOverprint,
             .goldSeal, .fortuneFold, .cloudGlass, .paperCicada, .ashSpoon, .starAsh,
             .lotusFoil, .redTowerTicket, .doubleJoySeal, .riverCloudMedallion,
             .peonyAshPrint, .silverLining, .ashLantern, .emberStamp, .boxFoldPavilion,
             .moonInCellophane: GridSize(width: 1, height: 1)
        case .doubleFoilFold, .celadonAshPearl, .ruyiAshRibbon, .goldenCloudStamp, .nanjingPaperWhistle,
             .furongCinderButton, .doubleJoyCigaretteSleeve, .liqunAshSleeve, .lotusEmberPetal,
             .redTowerAshCoin, .ashCigaretteRing, .zhonghuaSmokeFilm, .yuxiFilterCharm,
             .nanjingGrayLeaf, .furongEmberClip, .doubleJoyAshBadge, .crossBrandLantern,
             .oldShopLedgerSeal, .lotusGoldenCompass, .whiteRedFoldedStage: GridSize(width: 1, height: 1)
        case .ashClump, .cigaretteButt: GridSize(width: 1, height: 2)
        }
    }
}

public struct GridSize: Codable, Hashable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
    public var rotated: GridSize { GridSize(width: height, height: width) }
}

public enum InventoryLocation: String, Codable { case stored, desktop }

public struct InventoryTransform: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var rotation: Double
    public init(x: Double, y: Double, rotation: Double = 0) { self.x = x; self.y = y; self.rotation = rotation }
}

public struct InventoryItem: Codable, Identifiable, Equatable {
    public var id: UUID
    public var kind: InventoryKind
    public var styleID: String
    public var location: InventoryLocation
    public var column: Int
    public var row: Int
    private var storedRotationAxis: Int
    public var rotationQuarterTurns: Int {
        get { storedRotationAxis }
        set { storedRotationAxis = newValue.isMultiple(of: 2) ? 0 : 1 }
    }
    public var isRotated: Bool {
        get { storedRotationAxis == 1 }
        set { rotationQuarterTurns = newValue ? 1 : 0 }
    }
    public var desktopTransform: InventoryTransform?
    /// Item-specific mutable state, encoded by the owning renderer.
    public var state: Data?
    public var recoveryBatchID: UUID?
    public init(id: UUID = UUID(), kind: InventoryKind, styleID: String,
                location: InventoryLocation = .stored, column: Int = 0, row: Int = 0,
                isRotated: Bool = false, rotationQuarterTurns: Int? = nil,
                desktopTransform: InventoryTransform? = nil, state: Data? = nil) {
        self.id = id; self.kind = kind; self.styleID = styleID; self.location = location
        self.column = column; self.row = row
        let turns = rotationQuarterTurns ?? (isRotated ? 1 : 0)
        self.storedRotationAxis = turns.isMultiple(of: 2) ? 0 : 1
        self.desktopTransform = desktopTransform; self.state = state
    }
    public var footprint: GridSize { isRotated ? kind.footprint.rotated : kind.footprint }

    private enum CodingKeys: String, CodingKey {
        case id, kind, styleID, location, column, row, isRotated, rotationQuarterTurns, desktopTransform, state, recoveryBatchID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(InventoryKind.self, forKey: .kind)
        styleID = try values.decode(String.self, forKey: .styleID)
        location = try values.decode(InventoryLocation.self, forKey: .location)
        column = try values.decode(Int.self, forKey: .column)
        row = try values.decode(Int.self, forKey: .row)
        let turns = try values.decodeIfPresent(Int.self, forKey: .rotationQuarterTurns)
            ?? ((try values.decodeIfPresent(Bool.self, forKey: .isRotated) ?? false) ? 1 : 0)
        storedRotationAxis = turns.isMultiple(of: 2) ? 0 : 1
        desktopTransform = try values.decodeIfPresent(InventoryTransform.self, forKey: .desktopTransform)
        state = try values.decodeIfPresent(Data.self, forKey: .state)
        recoveryBatchID = try values.decodeIfPresent(UUID.self, forKey: .recoveryBatchID)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(kind, forKey: .kind)
        try values.encode(styleID, forKey: .styleID)
        try values.encode(location, forKey: .location)
        try values.encode(column, forKey: .column)
        try values.encode(row, forKey: .row)
        try values.encode(isRotated, forKey: .isRotated)
        try values.encode(storedRotationAxis, forKey: .rotationQuarterTurns)
        try values.encodeIfPresent(desktopTransform, forKey: .desktopTransform)
        try values.encodeIfPresent(state, forKey: .state)
        try values.encodeIfPresent(recoveryBatchID, forKey: .recoveryBatchID)
    }
}

public struct InventoryLayout: Codable, Equatable {
    public let columns: Int
    public let rows: Int
    public var items: [InventoryItem]
    public init(columns: Int = 5, rows: Int = 3, items: [InventoryItem] = []) {
        self.columns = columns; self.rows = rows; self.items = items
    }
    public func canPlace(_ item: InventoryItem, at column: Int, row: Int, ignoring ignoredID: UUID? = nil) -> Bool {
        let size = item.footprint
        guard column >= 0, row >= 0, column + size.width <= columns, row + size.height <= rows else { return false }
        for other in items where other.id != item.id && other.id != ignoredID && other.location == .stored {
            let otherSize = other.footprint
            let overlaps = column < other.column + otherSize.width && column + size.width > other.column
                && row < other.row + otherSize.height && row + size.height > other.row
            if overlaps { return false }
        }
        return true
    }
    @discardableResult public mutating func place(_ id: UUID, column: Int, row: Int,
                                                  rotated: Bool? = nil, rotationQuarterTurns: Int? = nil) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id && $0.location == .stored }) else { return false }
        let old = items[index]
        if let rotated { items[index].isRotated = rotated }
        if let rotationQuarterTurns { items[index].rotationQuarterTurns = ((rotationQuarterTurns % 4) + 4) % 4 }
        guard canPlace(items[index], at: column, row: row, ignoring: id) else { items[index] = old; return false }
        items[index].column = column; items[index].row = row
        return true
    }
    public func firstOpenSlot(for item: InventoryItem) -> (column: Int, row: Int)? {
        for row in 0..<rows { for column in 0..<columns where canPlace(item, at: column, row: row) { return (column, row) } }
        return nil
    }
    public var occupiedCells: Int { items.filter { $0.location == .stored }.reduce(0) { $0 + $1.footprint.width * $1.footprint.height } }
    public var hasValidStoredPlacements: Bool {
        var occupied = Set<Int>()
        for item in items where item.location == .stored {
            let size = item.footprint
            guard item.column >= 0, item.row >= 0,
                  item.column + size.width <= columns, item.row + size.height <= rows else { return false }
            for row in item.row..<(item.row + size.height) {
                for column in item.column..<(item.column + size.width) {
                    guard occupied.insert(row * columns + column).inserted else { return false }
                }
            }
        }
        return true
    }
}
