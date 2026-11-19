import DeskPuffCore
import SwiftUI
import WidgetKit

private struct DeskPuffEntry: TimelineEntry {
    let date: Date
    let snapshot: DeskPuffWidgetSnapshot
}

private struct DeskPuffProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeskPuffEntry {
        DeskPuffEntry(date: .now, snapshot: DeskPuffWidgetSnapshot(
            rankName: "青铜", rankIndex: 0, star: 1, balanceCents: 7354,
            completedCigarettes: 8, progressToNextRank: 0.62, cigarettesToNextRank: 2,
            nextPayoutCents: 1600, secondsToNextPayout: 8 * 60
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (DeskPuffEntry) -> Void) {
        completion(DeskPuffEntry(date: .now, snapshot: loadSnapshot() ?? placeholder(in: context).snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeskPuffEntry>) -> Void) {
        let now = Date.now
        let snapshot = loadSnapshot() ?? placeholder(in: context).snapshot
        let entry = DeskPuffEntry(date: now, snapshot: snapshot)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
    }

    private func loadSnapshot() -> DeskPuffWidgetSnapshot? {
        WidgetSnapshotAccess.load()
    }
}

private struct DeskPuffWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeskPuffEntry

    private var snapshot: DeskPuffWidgetSnapshot { entry.snapshot }
    private var rankColor: Color {
        let colors: [Color] = [
            Color(red: 0.66, green: 0.39, blue: 0.24), Color(red: 0.58, green: 0.63, blue: 0.70),
            Color(red: 0.82, green: 0.62, blue: 0.20), Color(red: 0.42, green: 0.58, blue: 0.82),
            Color(red: 0.32, green: 0.66, blue: 0.52), Color(red: 0.32, green: 0.70, blue: 0.82),
            Color(red: 0.57, green: 0.47, blue: 0.82), Color(red: 0.78, green: 0.36, blue: 0.40),
            Color(red: 0.90, green: 0.67, blue: 0.22)
        ]
        return colors[min(max(snapshot.rankIndex, 0), colors.count - 1)]
    }
    private var rankSymbol: String {
        ["shield.lefthalf.filled", "shield.fill", "medal.fill", "seal.fill", "rosette", "crown.fill", "star.circle.fill", "sparkles", "sun.max.fill"]
            .dropFirst(min(max(snapshot.rankIndex, 0), 8)).first ?? "shield.fill"
    }
    private var balance: String {
        snapshot.balanceCents.isMultiple(of: 100)
            ? "¥\(snapshot.balanceCents / 100)"
            : String(format: "¥%.2f", Double(snapshot.balanceCents) / 100)
    }
    private var progressCaption: String {
        if let left = snapshot.cigarettesToNextRank { return String.localizedStringWithFormat(NSLocalizedString("%d cigarettes to next rank", comment: ""), left) }
        return NSLocalizedString("Top rank reached", comment: "")
    }

    var body: some View {
        Group {
            if family == .systemSmall { smallLayout }
            else { mediumLayout }
        }
        .padding(family == .systemSmall ? 15 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // macOS supplies the adaptive Liquid Glass widget surface.
        .containerBackground(.clear, for: .widget)
        .widgetURL(URL(string: "deskpuff://profile"))
    }

    private var rankLine: some View {
        HStack(spacing: 7) {
            Image(systemName: rankSymbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(rankColor)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.rankName).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1)
                Text(String.localizedStringWithFormat(NSLocalizedString("%d stars", comment: ""), snapshot.star))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            rankLine
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text("Balance").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Text(balance).font(.system(size: 23, weight: .bold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.72).lineLimit(1).foregroundStyle(Color(red: 1, green: 0.80, blue: 0.49))
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                Text(progressCaption).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.75)
            }.foregroundStyle(.secondary)
        }
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                rankLine
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Balance").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Text(balance).font(.system(size: 25, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Color(red: 1, green: 0.80, blue: 0.49))
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(progressCaption).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    if snapshot.cigarettesToNextRank != nil {
                        Text("\(Int(snapshot.progressToNextRank * 100))%")
                            .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(rankColor).widgetAccentable()
                    }
                }
                ProgressView(value: snapshot.progressToNextRank).tint(rankColor)
            }
            HStack(spacing: 5) {
                Image(systemName: "clock").font(.system(size: 9, weight: .semibold)).foregroundStyle(rankColor)
                Text("Next allowance").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text("¥\(snapshot.nextPayoutCents / 100)").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
            }
        }
    }
}

private struct DeskPuffStatusWidget: Widget {
    let kind = WidgetSnapshotAccess.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DeskPuffProvider()) { entry in
            DeskPuffWidgetView(entry: entry)
        }
        .configurationDisplayName("DeskPuff Status")
        .description("See your current rank, balance, and progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct DeskPuffWidgetBundle: WidgetBundle {
    var body: some Widget { DeskPuffStatusWidget() }
}
