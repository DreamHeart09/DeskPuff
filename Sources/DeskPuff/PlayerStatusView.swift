import SwiftUI
import DeskPuffCore

@MainActor struct PlayerStatusView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var store = InventoryStore.shared
    var compact = false

    var body: some View {
        if let rules = store.economyRules {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let completed = store.economy.completedCigarettes
                let rankInfo = rules.progress(completed: completed)
                let rank = rules.ranks[rankInfo.rankIndex]
                let incomeProgress = store.economy.incomeProgress(at: context.date, rules: rules)
                let remaining = max(0, Int(ceil((1 - incomeProgress) * Double(rules.incomeIntervalSeconds))))
                let payout = store.economy.estimatedPayoutCents(rules: rules)
                Group {
                    if compact {
                        compactStatus(rankInfo: rankInfo, rank: rank, completed: completed, remaining: remaining,
                                      progress: 1 - incomeProgress, payoutCents: payout,
                                      hourlyRateCents: rank.hourlyRateCents(forStar: rankInfo.star), rules: rules)
                    } else {
                        fullStatus(rankInfo: rankInfo, rank: rank, completed: completed, remaining: remaining,
                                   progress: 1 - incomeProgress, payoutCents: payout, rules: rules)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: completed)
            }
        }
    }

    private func compactStatus(rankInfo: RankProgress, rank: EconomyRank, completed: Int, remaining: Int,
                               progress: Double, payoutCents: Int, hourlyRateCents: Int, rules: EconomyRules) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                rankEmblem(star: rankInfo.star, rankIndex: rankInfo.rankIndex)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("{{0}} · {{1}} 星", tr(rank.name), rankInfo.star))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { index in
                            Image(systemName: index < rankInfo.star ? "star.fill" : "star")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(index < rankInfo.star ? MenuBarTheme.accent : MenuBarTheme.tertiaryText)
                        }
                    }
                    .accessibilityHidden(true)
                    Text(tr("已完整使用 {{0}} 支", completed))
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(MenuBarTheme.secondaryText).lineLimit(1).minimumScaleFactor(0.76)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                RoundedRectangle(cornerRadius: 0.5).fill(MenuBarTheme.heroDivider).frame(width: 1, height: 42)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tr("钱包余额")).font(.system(size: 9, weight: .medium)).foregroundStyle(MenuBarTheme.secondaryText)
                    Text(wallet(store.economy.balanceCents))
                        .font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(MenuBarTheme.gold)
                        .lineLimit(1).minimumScaleFactor(0.63)
                }
            }
            if let next = rankInfo.nextThreshold {
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Text(tr("晋级下一星"))
                        Spacer(minLength: 3)
                        Text("\(completed) / \(next)").monospacedDigit()
                    }.font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(MenuBarTheme.secondaryText)
                    MenuBarProgressBar(value: Double(completed - rankInfo.threshold),
                                       total: Double(max(1, next - rankInfo.threshold)))
                }
            }
            Rectangle().fill(MenuBarTheme.outline).frame(height: 0.5)
            HStack(spacing: 7) {
                rewardRing(progress: progress, payoutCents: payoutCents, compact: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("{{0}} / 小时", money(hourlyRateCents)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(MenuBarTheme.gold)
                    Text(tr("预计到账 {{0}}", money(payoutCents)))
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(MenuBarTheme.secondaryText)
                }
                Spacer(minLength: 2)
                Text(remaining == 0 ? tr("即将到账") : tr("{{0}} 后到账", remainingDescription(remaining)))
                    .font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(MenuBarTheme.secondaryText).monospacedDigit()
            }
        }
        .padding(11)
        .playerHubSurface(.item, radius: 16)
        .shadow(color: MenuBarTheme.accent.opacity(0.09), radius: 8, y: 3)
    }

    private func fullStatus(rankInfo: RankProgress, rank: EconomyRank, completed: Int, remaining: Int,
                            progress: Double, payoutCents: Int, rules: EconomyRules) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                rankEmblem(star: rankInfo.star, rankIndex: rankInfo.rankIndex)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("{{0}} · {{1}} 星", tr(rank.name), rankInfo.star)).font(.system(size: 16, weight: .semibold))
                    Text(tr("已完整使用 {{0}} 支", completed)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(tr("钱包余额")).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    Text(wallet(store.economy.balanceCents)).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                rewardRing(progress: progress, payoutCents: payoutCents, compact: false)
            }
            if let next = rankInfo.nextThreshold {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(tr("晋升至下一星"))
                        Spacer()
                        Text(tr("还需 {{0}} 支", max(0, next - completed)))
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    ProgressView(value: Double(completed - rankInfo.threshold), total: Double(max(1, next - rankInfo.threshold))).tint(DeskPuffPalette.accent)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "seal.fill").font(.system(size: 9)).foregroundStyle(DeskPuffPalette.accent)
                Text(tr("段位津贴"))
                Text(tr("{{0}} / 半小时", money(rank.halfHourPayoutCents(forStar: rankInfo.star)))).foregroundStyle(.primary).fontWeight(.semibold)
                Spacer(minLength: 6)
                Text(remaining == 0 ? tr("即将到账") : tr("{{0}} 后到账", remainingDescription(remaining))).monospacedDigit()
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            if rankInfo.rankIndex + 1 < rules.ranks.count {
                let nextRank = rules.ranks[rankInfo.rankIndex + 1]
                Text(tr("晋级 {{0}} 后，基础津贴为 {{1}} / 半小时", tr(nextRank.name), money(nextRank.halfHourPayoutCents(forStar: 1))))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func rankEmblem(star: Int, rankIndex: Int) -> some View {
        let rankColor = RankBadgeStyle.color(for: rankIndex)
        return ZStack {
            if compact {
                Circle().fill(RadialGradient(colors: [MenuBarTheme.accent.opacity(0.22), .clear], center: .center, startRadius: 1, endRadius: 34))
                    .frame(width: 58, height: 58)
            }
            if let artwork = RankBadgeStyle.artwork(for: rankIndex, small: true) {
                artwork.resizable().interpolation(.high).scaledToFit().padding(2)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(rankColor.opacity(0.14))
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(rankColor.opacity(0.22), lineWidth: 0.7)
                VStack(spacing: 1) {
                    Image(systemName: RankBadgeStyle.symbol(for: rankIndex)).font(.system(size: compactSize, weight: .medium))
                    Text(tr("{{0}}星", star)).font(.system(size: 7, weight: .bold, design: .rounded))
                }.foregroundStyle(rankColor)
            }
        }
        .frame(width: compact ? 58 : 48, height: compact ? 58 : 48)
        .accessibilityLabel(tr("当前 {{0}} 星", star))
    }

    private var compactSize: CGFloat { compact ? 17 : 22 }

    private func rewardRing(progress: Double, payoutCents: Int, compact: Bool) -> some View {
        let size: CGFloat = compact ? 18 : 62
        let lineWidth: CGFloat = compact ? 1.45 : 4
        let trackColor = compact ? MenuBarTheme.outline : DeskPuffPalette.outline.opacity(0.8)
        let accentColors = compact
            ? [MenuBarTheme.accent.opacity(0.43), InventoryTheme.accentBright]
            : [DeskPuffPalette.accent.opacity(0.48), DeskPuffPalette.accent]
        return ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(1, max(0, progress)))
                .stroke(AngularGradient(colors: accentColors, center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progress)
            Image(systemName: "clock")
                .font(.system(size: compact ? 8 : 15, weight: .medium))
                .foregroundStyle(compact ? InventoryTheme.accentBright : DeskPuffPalette.accent.opacity(0.78))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("段位津贴 {{0}}，剩余时间进度 {{1}}%", money(payoutCents), Int(progress * 100)))
    }

    private func remainingDescription(_ seconds: Int) -> String {
        if seconds < 60 { return tr("不到 1 分钟") }
        return tr("{{0}} 分 {{1}} 秒", seconds / 60, seconds % 60)
    }

    private func money(_ cents: Int) -> String {
        cents.isMultiple(of: 100) ? "¥\(cents / 100)" : String(format: "¥%.2f", Double(cents) / 100)
    }

    private func wallet(_ cents: Int) -> String { money(cents) }
}

private struct MenuBarProgressBar: View {
    let value: Double
    let total: Double

    private var fraction: Double { min(1, max(0, value / max(1, total))) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.25))
                Capsule()
                    .fill(LinearGradient(colors: [MenuBarTheme.progressHighlight, MenuBarTheme.accent, MenuBarTheme.accentDeep],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: max(4, geometry.size.width * fraction))
                    .shadow(color: MenuBarTheme.accent.opacity(0.18), radius: 2, y: 0)
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6))
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("晋级进度"))
        .accessibilityValue("\(Int(fraction * 100))%")
    }
}
