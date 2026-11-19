import Foundation

enum InventoryBagCategory: String, CaseIterable, Identifiable, Hashable {
    case small, light, daily, expanded, travel, expedition

    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: tr("随身小包")
        case .light: tr("轻装挎包")
        case .daily: tr("日常背包")
        case .expanded: tr("扩展背包")
        case .travel: tr("旅行背包")
        case .expedition: tr("远行背包")
        }
    }
    var defaultStyleID: String {
        switch self {
        case .small: "urban-sling"
        case .light: "urban-daypack"
        case .daily: "campus-classic"
        case .expanded: "business-multi"
        case .travel: "urban-commuter"
        case .expedition: "mountaineering"
        }
    }
    var legacyGroup: String {
        switch self {
        case .small: "small"
        case .light, .daily, .expanded: "medium"
        case .travel, .expedition: "large"
        }
    }
}

/// Each appearance collection is sized for its matching capacity tier.
struct InventoryBagStyle: Identifiable, Hashable {
    let id: String
    let name: String
    let asset: String
    let category: InventoryBagCategory

    static let builtIns: [InventoryBagStyle] = [
        .init(id: "urban-sling", name: "黑色运动腰包", asset: "sport-belt", category: .small),
        .init(id: "leather-mini", name: "精致皮革小包", asset: "leather-mini", category: .small),
        .init(id: "crescent-sling", name: "弯月单肩包", asset: "crescent-sling", category: .small),

        .init(id: "urban-daypack", name: "都市机能斜挎包", asset: "light-tech-sling", category: .light),
        .init(id: "outdoor-shoulder", name: "户外运动单肩包", asset: "outdoor-shoulder", category: .light),
        .init(id: "canvas-mailbag", name: "复古帆布邮差包", asset: "canvas-mailbag", category: .light),

        .init(id: "campus-classic", name: "经典校园双肩包", asset: "campus-classic", category: .daily),
        .init(id: "city-minimal", name: "极简都市通勤包", asset: "city-minimal", category: .daily),
        .init(id: "casual-square", name: "休闲方形背包", asset: "casual-square", category: .daily),

        .init(id: "business-multi", name: "商务多隔层背包", asset: "business-multi", category: .expanded),
        .init(id: "outdoor-technical", name: "户外机能双肩包", asset: "outdoor-technical", category: .expanded),
        .init(id: "vintage-large", name: "复古大容量背包", asset: "vintage-large", category: .expanded),

        .init(id: "urban-commuter", name: "登机旅行背包", asset: "cabin-travel", category: .travel),
        .init(id: "travel-duffel", name: "大容量旅行桶包", asset: "travel-duffel", category: .travel),
        .init(id: "business-travel", name: "商务旅行双肩包", asset: "business-travel", category: .travel),

        .init(id: "mountaineering", name: "专业登山包", asset: "mountaineering", category: .expedition),
        .init(id: "multi-day-hike", name: "多日徒步重装包", asset: "multi-day-hike", category: .expedition),
        .init(id: "gear-hiker", name: "外部装备远足包", asset: "gear-hiker", category: .expedition)
    ]

    static func styles(for category: InventoryBagCategory) -> [InventoryBagStyle] {
        builtIns.filter { $0.category == category }
    }

    static func item(_ id: String) -> InventoryBagStyle? { builtIns.first { $0.id == id } }
}
