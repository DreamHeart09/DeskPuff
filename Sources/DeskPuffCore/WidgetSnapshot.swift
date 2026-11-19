import Foundation

/// Small, read-only snapshot shared with the optional WidgetKit extension.
public struct DeskPuffWidgetSnapshot: Codable, Equatable {
    public static let appGroupIdentifier = "group.local.deskpuff"
    public static let storageKey = "playerSnapshotV1"

    public var rankName: String
    public var rankIndex: Int
    public var star: Int
    public var balanceCents: Int
    public var completedCigarettes: Int
    public var progressToNextRank: Double
    public var cigarettesToNextRank: Int?
    public var nextPayoutCents: Int
    public var secondsToNextPayout: Int
    public var updatedAt: Date

    public init(economy: EconomyState, rules: EconomyRules, localizedRankName: String, at date: Date = .now) {
        let progress = rules.progress(completed: economy.completedCigarettes)
        let incomeProgress = economy.incomeProgress(at: date, rules: rules)
        rankName = localizedRankName
        rankIndex = progress.rankIndex
        star = progress.star
        balanceCents = economy.balanceCents
        completedCigarettes = economy.completedCigarettes
        if let next = progress.nextThreshold {
            progressToNextRank = min(1, max(0, Double(economy.completedCigarettes - progress.threshold) / Double(max(1, next - progress.threshold))))
            cigarettesToNextRank = max(0, next - economy.completedCigarettes)
        } else {
            progressToNextRank = 1
            cigarettesToNextRank = nil
        }
        nextPayoutCents = economy.estimatedPayoutCents(rules: rules)
        secondsToNextPayout = max(0, Int(ceil((1 - incomeProgress) * Double(rules.incomeIntervalSeconds))))
        updatedAt = date
    }

    public init(rankName: String = "青铜", rankIndex: Int = 0, star: Int = 1, balanceCents: Int = 0,
                completedCigarettes: Int = 0, progressToNextRank: Double = 0, cigarettesToNextRank: Int? = nil,
                nextPayoutCents: Int = 0, secondsToNextPayout: Int = 0, updatedAt: Date = .now) {
        self.rankName = rankName
        self.rankIndex = rankIndex
        self.star = star
        self.balanceCents = balanceCents
        self.completedCigarettes = completedCigarettes
        self.progressToNextRank = progressToNextRank
        self.cigarettesToNextRank = cigarettesToNextRank
        self.nextPayoutCents = nextPayoutCents
        self.secondsToNextPayout = secondsToNextPayout
        self.updatedAt = updatedAt
    }
}
