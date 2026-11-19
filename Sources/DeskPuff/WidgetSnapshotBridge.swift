import DeskPuffCore
import Foundation
import WidgetKit

enum WidgetSnapshotBridge {
    static let widgetKind = "DeskPuffStatusWidget"

    static func publish(economy: EconomyState, rules: EconomyRules) {
        guard let defaults = UserDefaults(suiteName: DeskPuffWidgetSnapshot.appGroupIdentifier) else { return }
        let progress = rules.progress(completed: economy.completedCigarettes)
        let snapshot = DeskPuffWidgetSnapshot(
            economy: economy,
            rules: rules,
            localizedRankName: tr(rules.ranks[progress.rankIndex].name)
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let previous = defaults.data(forKey: DeskPuffWidgetSnapshot.storageKey)
            .flatMap { try? JSONDecoder().decode(DeskPuffWidgetSnapshot.self, from: $0) }
        defaults.set(data, forKey: DeskPuffWidgetSnapshot.storageKey)

        let mustReload = previous == nil || previous?.balanceCents != snapshot.balanceCents ||
            previous?.rankName != snapshot.rankName || previous?.star != snapshot.star ||
            previous?.cigarettesToNextRank != snapshot.cigarettesToNextRank ||
            Date.now.timeIntervalSince(previous?.updatedAt ?? .distantPast) >= 60
        if mustReload {
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
    }
}
