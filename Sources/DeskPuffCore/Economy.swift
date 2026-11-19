import Foundation

public struct EconomyRank: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    /// One-star baseline, in cents per hour.
    public let hourlyCents: Int
    /// Additional cents per half-hour payout for each star above one.
    public let starBonusCentsPerHalfHour: Int
    /// Inclusive cumulative completed-cigarette thresholds for each star.
    public let starThresholds: [Int]

    public func hourlyRateCents(forStar star: Int) -> Int {
        let bonus = max(0, min(4, star - 1)) * starBonusCentsPerHalfHour * 2
        let (rate, overflow) = hourlyCents.addingReportingOverflow(bonus)
        return overflow ? Int.max : rate
    }

    public func halfHourPayoutCents(forStar star: Int) -> Int {
        hourlyCents / 2 + max(0, min(4, star - 1)) * starBonusCentsPerHalfHour
    }
}

public enum InventoryToolEffect: String, Codable, CaseIterable, Hashable {
    case lighterRuntime30
    case lighterRuntime60
    case lighterRuntime100
    case cigaretteDiscount5
    case cigaretteDiscount10
    case cigaretteDiscount15
    case ashtrayCapacity50

    public var symbol: String {
        switch self {
        case .lighterRuntime30, .lighterRuntime60, .lighterRuntime100: "flame.fill"
        case .cigaretteDiscount5, .cigaretteDiscount10, .cigaretteDiscount15: "creditcard.fill"
        case .ashtrayCapacity50: "circle.grid.3x3.fill"
        }
    }
    public var benefit: String {
        switch self {
        case .lighterRuntime30: "打火机续航 +30%"
        case .lighterRuntime60: "打火机续航 +60%"
        case .lighterRuntime100: "打火机续航 +100%"
        case .cigaretteDiscount5: "香烟购入价 −5%"
        case .cigaretteDiscount10: "香烟购入价 −10%"
        case .cigaretteDiscount15: "香烟购入价 −15%"
        case .ashtrayCapacity50: "烟灰缸容纳量 +50%"
        }
    }

    public var lighterRuntimeBonus: Double {
        switch self {
        case .lighterRuntime30: 0.30
        case .lighterRuntime60: 0.60
        case .lighterRuntime100: 1.00
        default: 0
        }
    }

    public var cigaretteDiscountRate: Double {
        switch self {
        case .cigaretteDiscount5: 0.05
        case .cigaretteDiscount10: 0.10
        case .cigaretteDiscount15: 0.15
        default: 0
        }
    }

    public var ashtrayCapacityBonus: Double {
        self == .ashtrayCapacity50 ? 0.50 : 0
    }
}

public struct StoreProduct: Codable, Identifiable, Equatable {
    public let id: String
    public let kind: InventoryKind
    public let styleID: String
    public let name: String
    public let specification: String
    public let priceCents: Int
    public let passiveEffect: InventoryToolEffect?
}

public struct BagOffer: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let stage: Int
    public let specification: String
    public let priceCents: Int
}

public struct BagStyleOffer: Codable, Identifiable, Equatable {
    public let id: String
    public let styleID: String
    public let priceCents: Int
}

public struct EconomyRules: Codable {
    public let startingCents: Int
    public let offlineLimitSeconds: Int
    public let incomeIntervalSeconds: Int
    public let ranks: [EconomyRank]
    public let products: [StoreProduct]
    public let bags: [BagOffer]
    public let bagStyles: [BagStyleOffer]

    public var isValid: Bool {
        let thresholds = ranks.flatMap(\.starThresholds)
        return startingCents >= 0 && (1...604_800).contains(offlineLimitSeconds) && (60...86400).contains(incomeIntervalSeconds) && !ranks.isEmpty &&
            ranks.allSatisfy { !$0.starThresholds.isEmpty && (1...100_000_000).contains($0.hourlyCents) && (0...100_000).contains($0.starBonusCentsPerHalfHour) } &&
            thresholds.first == 0 && zip(thresholds, thresholds.dropFirst()).allSatisfy { $0 < $1 } &&
            products.allSatisfy { $0.kind.recoveryMaterial == nil && $0.priceCents > 0 && !$0.id.isEmpty && !$0.styleID.isEmpty &&
                ($0.kind == .tool ? $0.passiveEffect != nil : $0.passiveEffect == nil) } &&
            Set(products.map(\.id)).count == products.count &&
            bags.allSatisfy { (1...5).contains($0.stage) && $0.priceCents > 0 } &&
            Set(bags.map(\.stage)).count == bags.count &&
            bagStyles.allSatisfy { !$0.id.isEmpty && !$0.styleID.isEmpty && $0.priceCents >= 0 } &&
            Set(bagStyles.map(\.styleID)).count == bagStyles.count
    }

    public func progress(completed: Int) -> RankProgress {
        let entries = ranks.enumerated().flatMap { rankIndex, rank in
            rank.starThresholds.enumerated().map { (rankIndex, $0.offset, $0.element) }
        }
        let current = entries.lastIndex(where: { completed >= $0.2 }) ?? 0
        let entry = entries[current]
        let next = current + 1 < entries.count ? entries[current + 1].2 : nil
        return RankProgress(rankIndex: entry.0, star: entry.1 + 1, threshold: entry.2, nextThreshold: next)
    }
}

public struct RankProgress: Equatable {
    public let rankIndex: Int
    public let star: Int
    public let threshold: Int
    public let nextThreshold: Int?
}

/// The wallet and physical inventory are persisted as one versioned value.
public struct InventoryDocument: Codable, Equatable {
    public var version: Int
    public var layout: InventoryLayout
    public var capacityStage: Int?
    public var economy: EconomyState?
    public init(version: Int, layout: InventoryLayout, capacityStage: Int?, economy: EconomyState?) {
        self.version = version; self.layout = layout
        self.capacityStage = capacityStage; self.economy = economy
    }
}

public struct EconomyState: Codable, Equatable {
    public var balanceCents: Int
    public var completedCigarettes: Int
    public var lastIncomeTime: Date
    /// Fractional cents retained between settlements.
    public var incomeRemainder: Double
    public var pendingIncomeCents: Double
    public var incomeIntervalElapsed: Double
    public var ownedBagStages: [Int]
    public var ownedBagStyleIDs: [String]?
    public var activeBagStyleID: String?
    public var recoveryRemainders: [String: Int] = [:]
    public var discoveredRecoveryItemIDs: [String] = []
    public var recoveryCraftCount = 0
    public var claimedAchievementIDs: [String] = []
    public var passiveIncomeCents = 0
    public var recoveryIncomeCents = 0
    public var achievementIncomeCents = 0
    public var recoveryItemsSold = 0
    public var cigaretteBoxesPurchasedByStyle: [String: Int] = [:]
    public var cigarettesCompletedByStyle: [String: Int] = [:]
    public var incomeHistory: [IncomeHistoryPoint] = []
    public var statistics: PlayerStatistics
    public init(balanceCents: Int, completedCigarettes: Int = 0, lastIncomeTime: Date = Date(), incomeRemainder: Double = 0, ownedBagStages: [Int] = [0]) {
        self.balanceCents = balanceCents; self.completedCigarettes = completedCigarettes
        self.lastIncomeTime = lastIncomeTime; self.incomeRemainder = incomeRemainder; self.ownedBagStages = ownedBagStages
        self.pendingIncomeCents = 0; self.incomeIntervalElapsed = 0
        self.ownedBagStyleIDs = ["urban-sling"]; self.activeBagStyleID = "urban-sling"
        self.statistics = PlayerStatistics()
    }
    private enum CodingKeys: String, CodingKey { case balanceCents, completedCigarettes, lastIncomeTime, incomeRemainder, ownedBagStages, pendingIncomeCents, incomeIntervalElapsed, ownedBagStyleIDs, activeBagStyleID, statistics, recoveryRemainders, discoveredRecoveryItemIDs, recoveryCraftCount, claimedAchievementIDs, passiveIncomeCents, recoveryIncomeCents, achievementIncomeCents, recoveryItemsSold, cigaretteBoxesPurchasedByStyle, cigarettesCompletedByStyle, incomeHistory }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        balanceCents = try values.decode(Int.self, forKey: .balanceCents)
        completedCigarettes = try values.decode(Int.self, forKey: .completedCigarettes)
        lastIncomeTime = try values.decode(Date.self, forKey: .lastIncomeTime)
        incomeRemainder = try values.decode(Double.self, forKey: .incomeRemainder)
        pendingIncomeCents = try values.decodeIfPresent(Double.self, forKey: .pendingIncomeCents) ?? 0
        incomeIntervalElapsed = try values.decodeIfPresent(Double.self, forKey: .incomeIntervalElapsed) ?? 0
        ownedBagStages = try values.decodeIfPresent([Int].self, forKey: .ownedBagStages) ?? [0]
        ownedBagStyleIDs = try values.decodeIfPresent([String].self, forKey: .ownedBagStyleIDs)
        activeBagStyleID = try values.decodeIfPresent(String.self, forKey: .activeBagStyleID)
        recoveryRemainders = try values.decodeIfPresent([String: Int].self, forKey: .recoveryRemainders) ?? [:]
        discoveredRecoveryItemIDs = try values.decodeIfPresent([String].self, forKey: .discoveredRecoveryItemIDs) ?? []
        recoveryCraftCount = max(0, try values.decodeIfPresent(Int.self, forKey: .recoveryCraftCount) ?? 0)
        claimedAchievementIDs = try values.decodeIfPresent([String].self, forKey: .claimedAchievementIDs) ?? []
        passiveIncomeCents = max(0, try values.decodeIfPresent(Int.self, forKey: .passiveIncomeCents) ?? 0)
        recoveryIncomeCents = max(0, try values.decodeIfPresent(Int.self, forKey: .recoveryIncomeCents) ?? 0)
        achievementIncomeCents = max(0, try values.decodeIfPresent(Int.self, forKey: .achievementIncomeCents) ?? 0)
        recoveryItemsSold = max(0, try values.decodeIfPresent(Int.self, forKey: .recoveryItemsSold) ?? 0)
        cigaretteBoxesPurchasedByStyle = Self.cleanCounts(try values.decodeIfPresent([String: Int].self, forKey: .cigaretteBoxesPurchasedByStyle) ?? [:])
        cigarettesCompletedByStyle = Self.cleanCounts(try values.decodeIfPresent([String: Int].self, forKey: .cigarettesCompletedByStyle) ?? [:])
        incomeHistory = Array((try values.decodeIfPresent([IncomeHistoryPoint].self, forKey: .incomeHistory) ?? []).sorted { $0.hour < $1.hour }.suffix(720))
        statistics = try values.decodeIfPresent(PlayerStatistics.self, forKey: .statistics) ?? PlayerStatistics()
    }
    private static func cleanCounts(_ counts: [String: Int]) -> [String: Int] {
        counts.reduce(into: [:]) { if !$1.key.isEmpty && $1.value > 0 { $0[$1.key] = $1.value } }
    }
    public var totalIncomeCents: Int {
        [passiveIncomeCents, recoveryIncomeCents, achievementIncomeCents].reduce(0) { result, value in
            let (sum, overflow) = result.addingReportingOverflow(value); return overflow ? Int.max : sum
        }
    }
    public mutating func recordCigaretteBoxPurchase(styleID: String) { Self.increment(styleID, in: &cigaretteBoxesPurchasedByStyle) }
    public mutating func recordCigaretteCompletion(styleID: String?) { if let styleID { Self.increment(styleID, in: &cigarettesCompletedByStyle) } }
    private static func increment(_ key: String, in counts: inout [String: Int]) {
        guard !key.isEmpty else { return }; let (value, overflow) = counts[key, default: 0].addingReportingOverflow(1); counts[key] = overflow ? Int.max : value
    }
    public mutating func recordIncome(_ cents: Int, source: IncomeSource, at date: Date) {
        guard cents > 0, date.timeIntervalSince1970.isFinite else { return }
        switch source {
        case .passive: passiveIncomeCents = Self.safeAdd(passiveIncomeCents, cents)
        case .recovery: recoveryIncomeCents = Self.safeAdd(recoveryIncomeCents, cents)
        case .achievement: achievementIncomeCents = Self.safeAdd(achievementIncomeCents, cents)
        }
        let hour = Int64(floor(date.timeIntervalSince1970 / 3600))
        if let index = incomeHistory.firstIndex(where: { $0.hour == hour }) { incomeHistory[index].add(cents, source: source) }
        else { var point = IncomeHistoryPoint(hour: hour); point.add(cents, source: source); incomeHistory.append(point) }
        incomeHistory.sort { $0.hour < $1.hour }; if incomeHistory.count > 720 { incomeHistory.removeFirst(incomeHistory.count - 720) }
    }
    public mutating func recordRecoverySale(count: Int, cents: Int, at date: Date) {
        let (sold, overflow) = recoveryItemsSold.addingReportingOverflow(max(0, count)); recoveryItemsSold = overflow ? Int.max : sold
        recordIncome(cents, source: .recovery, at: date)
    }
    fileprivate static func safeAdd(_ lhs: Int, _ rhs: Int) -> Int { let (sum, overflow) = lhs.addingReportingOverflow(rhs); return overflow ? Int.max : sum }
    public mutating func recordRecoveryDiscovery(_ material: RecoveryMaterial) {
        guard material.isCollectible || material == .mysteryJunk,
              !discoveredRecoveryItemIDs.contains(material.rawValue) else { return }
        discoveredRecoveryItemIDs.append(material.rawValue)
    }
    public mutating func recordRecoveryCraft(count: Int = 1) {
        guard count > 0 else { return }
        let (total, overflow) = recoveryCraftCount.addingReportingOverflow(count)
        recoveryCraftCount = overflow ? Int.max : total
    }
    public mutating func claimAchievement(_ id: String) {
        guard !id.isEmpty, !claimedAchievementIDs.contains(id) else { return }
        claimedAchievementIDs.append(id)
    }
    public mutating func migrateBagStyles(selected: String, previouslySelected: [String]) {
        activeBagStyleID = selected
        ownedBagStyleIDs = Array(Set(["urban-sling", selected] + previouslySelected)).sorted()
    }

    /// Starts a fresh earning clock for the current app session without granting time spent offline.
    public mutating func beginOnlineSession(at now: Date) {
        guard now.timeIntervalSinceReferenceDate.isFinite else { return }
        lastIncomeTime = now
    }

    public mutating func settle(at now: Date, rules: EconomyRules) {
        guard now.timeIntervalSinceReferenceDate.isFinite, now > lastIncomeTime else { return }
        var elapsed = min(now.timeIntervalSince(lastIncomeTime), Double(rules.offlineLimitSeconds))
        let progress = rules.progress(completed: completedCigarettes)
        let rate = rules.ranks[progress.rankIndex].hourlyRateCents(forStar: progress.star)
        let interval = Double(rules.incomeIntervalSeconds)
        // A previous ruleset may have used a longer payout interval. Settle any
        // already-earned full intervals before applying newly elapsed time.
        while incomeIntervalElapsed >= interval - 0.000_001 {
            let elapsedBeforePayout = incomeIntervalElapsed
            let payoutElapsed = min(interval, elapsedBeforePayout)
            let payoutPending = elapsedBeforePayout > interval
                ? pendingIncomeCents * payoutElapsed / elapsedBeforePayout
                : pendingIncomeCents
            let earned = payoutPending + incomeRemainder
            let wholeYuan = Int(((earned + 0.000_001) / 100).rounded(.down)) * 100
            balanceCents = balanceCents.addingReportingOverflow(wholeYuan).overflow ? Int.max : balanceCents + wholeYuan
            recordIncome(wholeYuan, source: .passive, at: now)
            incomeRemainder = max(0, earned - Double(wholeYuan))
            incomeIntervalElapsed = max(0, elapsedBeforePayout - interval)
            pendingIncomeCents = max(0, pendingIncomeCents - payoutPending)
        }
        while elapsed > 0 {
            let portion = min(elapsed, interval - incomeIntervalElapsed)
            pendingIncomeCents += portion * Double(rate) / 3600
            incomeIntervalElapsed += portion
            elapsed -= portion
            if incomeIntervalElapsed >= interval - 0.000_001 {
                let earned = pendingIncomeCents + incomeRemainder
                let wholeYuan = Int(((earned + 0.000_001) / 100).rounded(.down)) * 100
                balanceCents = balanceCents.addingReportingOverflow(wholeYuan).overflow ? Int.max : balanceCents + wholeYuan
                recordIncome(wholeYuan, source: .passive, at: now)
                incomeRemainder = max(0, earned - Double(wholeYuan))
                pendingIncomeCents = 0; incomeIntervalElapsed = 0
            }
        }
        lastIncomeTime = now
    }

    public func incomeProgress(at now: Date, rules: EconomyRules) -> Double {
        let since = max(0, min(now.timeIntervalSince(lastIncomeTime), Double(rules.offlineLimitSeconds)))
        return min(1, (incomeIntervalElapsed + since) / Double(rules.incomeIntervalSeconds))
    }

    public func estimatedPayoutCents(rules: EconomyRules) -> Int {
        let progress = rules.progress(completed: completedCigarettes)
        let rate = rules.ranks[progress.rankIndex].hourlyRateCents(forStar: progress.star)
        let remaining = max(0, Double(rules.incomeIntervalSeconds) - incomeIntervalElapsed)
        let estimated = pendingIncomeCents + incomeRemainder + remaining * Double(rate) / 3600
        return Int(((estimated + 0.000_001) / 100).rounded(.down)) * 100
    }
}

public enum IncomeSource { case passive, recovery, achievement }

public struct IncomeHistoryPoint: Codable, Equatable, Identifiable {
    public let hour: Int64
    public var passiveCents = 0
    public var recoveryCents = 0
    public var achievementCents = 0
    public var id: Int64 { hour }
    public init(hour: Int64) { self.hour = hour }
    public mutating func add(_ cents: Int, source: IncomeSource) {
        guard cents > 0 else { return }
        switch source {
        case .passive: passiveCents = EconomyState.safeAdd(passiveCents, cents)
        case .recovery: recoveryCents = EconomyState.safeAdd(recoveryCents, cents)
        case .achievement: achievementCents = EconomyState.safeAdd(achievementCents, cents)
        }
    }
    public var totalCents: Int { EconomyState.safeAdd(EconomyState.safeAdd(passiveCents, recoveryCents), achievementCents) }
}

public struct PlayerStatistics: Codable, Equatable {
    public var totalSpentCents = 0
    public var cigaretteSpendCents = 0
    public var lighterSpendCents = 0
    public var ashtraySpendCents = 0
    public var capacitySpendCents = 0
    public var bagStyleSpendCents = 0
    public var cigaretteBoxesPurchased = 0
    public var lightersPurchased = 0
    public var ashtraysPurchased = 0
    public var capacityUpgrades = 0
    public var bagStylesPurchased = 0
    public var cigaretteBoxesDiscarded = 0
    public var lightersDiscarded = 0
    public var ashtraysDiscarded = 0

    public init() {}
    private static func add(_ value: Int, to target: inout Int) {
        let (result, overflow) = target.addingReportingOverflow(max(0, value))
        target = overflow ? Int.max : result
    }
    public mutating func recordPurchase(kind: InventoryKind, priceCents: Int) {
        Self.add(priceCents, to: &totalSpentCents)
        switch kind {
        case .cigaretteBox: Self.add(priceCents, to: &cigaretteSpendCents); Self.add(1, to: &cigaretteBoxesPurchased)
        case .lighter: Self.add(priceCents, to: &lighterSpendCents); Self.add(1, to: &lightersPurchased)
        case .ashtray: Self.add(priceCents, to: &ashtraySpendCents); Self.add(1, to: &ashtraysPurchased)
        default: break
        }
    }
    public mutating func recordCapacityPurchase(priceCents: Int) {
        Self.add(priceCents, to: &totalSpentCents); Self.add(priceCents, to: &capacitySpendCents); Self.add(1, to: &capacityUpgrades)
    }
    public mutating func recordBagStylePurchase(priceCents: Int) {
        Self.add(priceCents, to: &totalSpentCents); Self.add(priceCents, to: &bagStyleSpendCents); Self.add(1, to: &bagStylesPurchased)
    }
    public mutating func recordDiscard(kind: InventoryKind) {
        switch kind {
        case .cigaretteBox: Self.add(1, to: &cigaretteBoxesDiscarded)
        case .lighter: Self.add(1, to: &lightersDiscarded)
        case .ashtray: Self.add(1, to: &ashtraysDiscarded)
        default: break
        }
    }
}

public enum PurchaseError: Error, Equatable { case insufficientFunds, insufficientSpace, alreadyOwned }

public enum ShopTransaction {
    public static func prepareBagStyle(offer: BagStyleOffer, economy: EconomyState) throws -> EconomyState {
        guard !(economy.ownedBagStyleIDs ?? []).contains(offer.styleID) else { throw PurchaseError.alreadyOwned }
        guard offer.priceCents >= 0, economy.balanceCents >= offer.priceCents else { throw PurchaseError.insufficientFunds }
        var next = economy
        next.balanceCents -= offer.priceCents
        next.ownedBagStyleIDs = (next.ownedBagStyleIDs ?? []) + [offer.styleID]
        return next
    }

    /// Produces both sides of a purchase without mutating either input on failure.
    public static func prepare(product: StoreProduct, layout: InventoryLayout,
                               economy: EconomyState, priceCents: Int? = nil) throws -> (InventoryLayout, EconomyState) {
        let price = priceCents ?? product.priceCents
        guard price >= 0, economy.balanceCents >= price else { throw PurchaseError.insufficientFunds }
        guard layout.hasValidStoredPlacements else { throw PurchaseError.insufficientSpace }
        var next = layout
        var item = InventoryItem(kind: product.kind, styleID: product.styleID)
        var slot: (column: Int, row: Int)?
        for rotated in [false, true] {
            item.isRotated = rotated
            if let found = next.firstOpenSlot(for: item) { slot = found; break }
        }
        guard let slot else { throw PurchaseError.insufficientSpace }
        item.column = slot.column; item.row = slot.row
        next.items.append(item)
        var balance = economy
        balance.balanceCents -= price
        return (next, balance)
    }
}
