import DeskPuffCore
import Foundation

enum WidgetSnapshotAccess {
    static let kind = "DeskPuffStatusWidget"

    static func load() -> DeskPuffWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: DeskPuffWidgetSnapshot.appGroupIdentifier)?
            .data(forKey: DeskPuffWidgetSnapshot.storageKey) else { return nil }
        return try? JSONDecoder().decode(DeskPuffWidgetSnapshot.self, from: data)
    }
}
