import SwiftUI
import Combine
import DeskPuffCore
import AppKit

enum PlayerHubTab: String, CaseIterable, Identifiable {
    case rank = "档案", inventory = "背包", store = "商店", recovery = "回收"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .inventory: "shippingbox"; case .store: "storefront"; case .rank: "shield.lefthalf.filled"; case .recovery: "arrow.3.trianglepath" }
    }
}

private struct CigaretteStyleRecord: Identifiable {
    let id: String
    let name: String
    let boxes: Int
    let smoked: Int
    let color: Color
}

private struct CigaretteStylePieChart: View {
    let records: [CigaretteStyleRecord]
    let value: KeyPath<CigaretteStyleRecord, Int>
    private var total: Int { records.reduce(0) { $0 + max(0, $1[keyPath: value]) } }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 2
            guard total > 0 else {
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(InventoryTheme.outline))
                return
            }
            var start = -90.0
            for record in records where record[keyPath: value] > 0 {
                let end = start + Double(record[keyPath: value]) / Double(total) * 360
                var slice = Path()
                slice.move(to: center)
                slice.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
                slice.closeSubpath()
                context.fill(slice, with: .color(record.color))
                start = end
            }
            let innerRadius = radius * 0.57
            context.fill(Path(ellipseIn: CGRect(x: center.x - innerRadius, y: center.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2)), with: .color(InventoryTheme.backgroundBottom))
        }
        .accessibilityLabel(tr("烟盒购入数量饼图，共 {{0}} 盒", total))
    }
}

private struct CigaretteStyleBarChart: View {
    let records: [CigaretteStyleRecord]
    private var maximum: Int { max(1, records.map(\.smoked).max() ?? 0) }

    var body: some View {
        VStack(spacing: 7) {
            ForEach(records) { record in
                GeometryReader { geometry in
                    HStack(spacing: 7) {
                        Text(record.name).font(.system(size: 9, weight: .medium)).lineLimit(1)
                            .frame(width: 66, alignment: .trailing).foregroundStyle(.secondary)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            Capsule().fill(record.color.opacity(0.85))
                                .frame(width: record.smoked == 0 ? 0 : max(3, (geometry.size.width - 105) * CGFloat(record.smoked) / CGFloat(maximum)))
                        }.frame(height: 12)
                        Text("\(record.smoked)").font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                            .frame(width: 25, alignment: .trailing)
                    }
                }.frame(height: 15)
            }
        }
        .accessibilityLabel(tr("各款烟盒完整抽毕数量柱状图"))
    }
}

@MainActor final class PlayerHubNavigation: ObservableObject {
    @Published var selected: PlayerHubTab = .inventory
    @Published var recoveryBagShown = false
}

@MainActor private final class PlayerHubToast: ObservableObject {
    @Published var message: String?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { self.message = message }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.24)) { self?.message = nil }
        }
    }
}

@MainActor private final class PlayerHubLocalState: ObservableObject {
    @Published var confirmingSaveReset = false
    @Published var showingAchievements = false
}

struct PlayerHubButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .playerHubSurface(prominent ? .active : .panel, radius: 10)
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.62)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

@MainActor struct PlayerHubView: View {
    @ObservedObject var navigation: PlayerHubNavigation
    @ObservedObject private var store = InventoryStore.shared
    @StateObject private var toast = PlayerHubToast()
    @StateObject private var localState = PlayerHubLocalState()
    let onDeploy: (InventoryItem) -> Void
    let onToggleRecoveryBag: () -> Void
    let onResetSave: () -> Bool

    var body: some View {
        VStack(spacing: 0) {
            PlayerHubHeader(navigation: navigation, balance: wallet(store.economy.balanceCents))
            Group {
                switch navigation.selected {
                case .rank:
                    rankPage
                case .inventory:
                    InventoryWindowView(store: store, onDeploy: onDeploy, recoveryBagShown: navigation.recoveryBagShown,
                                        onToggleRecoveryBag: onToggleRecoveryBag)
                case .store:
                    ScrollView {
                        StoreView()
                            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .recovery:
                    ScrollView {
                        RecoveryMarketView(store: store)
                            .padding(24).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 960, minHeight: 640)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(colors: [InventoryTheme.backgroundTop.opacity(0.91), InventoryTheme.backgroundBottom.opacity(0.97)], startPoint: .topLeading, endPoint: .bottomTrailing)
                GeometryReader { proxy in
                    Image("AmbientSmoke", bundle: .module)
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(width: proxy.size.width * 0.68)
                        .position(x: proxy.size.width * 0.76, y: proxy.size.height * 0.34)
                        .opacity(0.20)
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                RadialGradient(colors: [InventoryTheme.accent.opacity(0.11), .clear], center: .topTrailing, startRadius: 0, endRadius: 500)
            }
            .allowsHitTesting(false)
            .ignoresSafeArea(.container, edges: .top)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { store.settleIncome() }
        .onReceive(store.$message.dropFirst()) { message in
            if let message, !message.isEmpty { toast.show(message) }
        }
        .sheet(isPresented: $localState.showingAchievements) { achievementsSheet }
        .confirmationDialog(tr("建立新的玩家存档？"), isPresented: $localState.confirmingSaveReset, titleVisibility: .visible) {
            Button(tr("清除并重建存档"), role: .destructive) {
                guard onResetSave() else { return }
                navigation.selected = .rank
            }
            Button(tr("取消"), role: .cancel) { }
        } message: {
            Text(tr("这会清除钱包余额、段位与星数、购买记录、背包扩容、背包外观和桌面物件，并从初始存档重新开始。此操作无法在玩家档案中撤销。"))
        }
        .overlay(alignment: .bottom) {
            if let message = toast.message {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DeskPuffPalette.accent)
                    Text(message).font(.system(size: 12, weight: .medium)).lineLimit(2)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(DeskPuffPalette.outline, lineWidth: 0.7))
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
    }
    private var rankPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let rules = store.economyRules {
                    rankHero(rules: rules)
                    let progress = rules.progress(completed: store.economy.completedCigarettes)
                    rankJourney(rules: rules, currentRank: progress.rankIndex)
                }
                let stats = store.economy.statistics
                let currentRankIndex = store.economyRules?.progress(completed: store.economy.completedCigarettes).rankIndex ?? 0
                let currentRankProgress = store.economyRules.map { rules in
                    let rank = rules.progress(completed: store.economy.completedCigarettes)
                    return rank.rankIndex * 5 + rank.star
                } ?? 0
                let recoveryCraftCount = store.economy.recoveryCraftCount
                let discoveredCrafts = RecoveryRecipe.products.filter(store.hasDiscoveredRecoveryItem).count
                sectionHeading(tr("生涯记录"), detail: tr("每一次完整使用与收藏都留在这里"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], alignment: .leading, spacing: 10) {
                    recordCard(tr("完整使用"), value: "\(store.economy.completedCigarettes)", unit: tr("支"), symbol: "smoke.fill", featured: true)
                    recordCard(tr("累计消费"), value: money(stats.totalSpentCents), unit: "", symbol: "creditcard")
                    recordCard(tr("购入烟盒"), value: "\(stats.cigaretteBoxesPurchased)", unit: tr("盒"), symbol: "shippingbox")
                    recordCard(tr("购入打火机"), value: "\(stats.lightersPurchased)", unit: tr("个"), symbol: "flame")
                    recordCard(tr("购入烟灰缸"), value: "\(stats.ashtraysPurchased)", unit: tr("个"), symbol: "circle.dotted")
                    recordCard(tr("背包收藏"), value: "\(stats.capacityUpgrades + stats.bagStylesPurchased)", unit: tr("项"), symbol: "backpack")
                    recordCard(tr("回收物件"), value: "\(store.economy.recoveryItemsSold)", unit: tr("件"), symbol: "arrow.3.trianglepath")
                    recordCard(tr("回收收入"), value: money(store.economy.recoveryIncomeCents), unit: "", symbol: "yensign.circle")
                    recordCard(tr("合成次数"), value: "\(recoveryCraftCount)", unit: tr("次"), symbol: "sparkles")
                    recordCard(tr("发现工坊产物"), value: "\(discoveredCrafts)", unit: tr("种"), symbol: "gift")
                }
                cigaretteStyleRecords
                if let rules = store.economyRules { incomeFootprint(rules: rules) }
                let ownedStyles = (store.economy.ownedBagStyleIDs ?? []).count
                let badgeProgress = [
                    store.economy.completedCigarettes >= 1, store.economy.completedCigarettes >= 10,
                    store.economy.completedCigarettes >= 50, store.economy.completedCigarettes >= 200,
                    store.economy.completedCigarettes >= 1000,
                    currentRankIndex >= 1, currentRankIndex >= 2, currentRankIndex >= 4, currentRankIndex >= 8,
                    currentRankProgress >= 3, currentRankProgress >= 15, currentRankProgress >= 30,
                    stats.cigaretteBoxesPurchased >= 1, stats.cigaretteBoxesPurchased >= 10,
                    stats.lightersPurchased >= 1, stats.lightersPurchased >= 10,
                    stats.ashtraysPurchased >= 1, stats.ashtraysPurchased >= 5,
                    stats.totalSpentCents >= 10_000, stats.totalSpentCents >= 100_000,
                    stats.capacityUpgrades >= 1, stats.capacityUpgrades >= 4,
                    ownedStyles >= 1, ownedStyles >= 5,
                    stats.cigaretteBoxesDiscarded + stats.lightersDiscarded + stats.ashtraysDiscarded >= 1,
                    stats.cigaretteBoxesDiscarded + stats.lightersDiscarded + stats.ashtraysDiscarded >= 10,
                    recoveryCraftCount >= 1, recoveryCraftCount >= 10, recoveryCraftCount >= 50,
                    discoveredCrafts >= 1, discoveredCrafts >= RecoveryRecipe.products.count
                ]
                sectionHeading(tr("成就"), detail: tr("记录使用、晋阶与收藏旅程中的重要时刻"))
                Button { localState.showingAchievements = true } label: {
                    HStack(spacing: 12) {
                        achievementOverview(unlocked: badgeProgress.filter { $0 }.count, total: badgeProgress.count)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(InventoryTheme.accentBright).padding(.trailing, 15)
                    }
                    .playerHubSurface(.panel, radius: 18)
                }.buttonStyle(.plain).contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                sectionHeading(tr("消费足迹"), detail: tr("累计支出 {{0}}", money(stats.totalSpentCents)))
                spendingBreakdown(stats: stats)
                Text(tr("已丢弃 · 烟盒 {{0}} · 打火机 {{1}} · 烟灰缸 {{2}}", stats.cigaretteBoxesDiscarded, stats.lightersDiscarded, stats.ashtraysDiscarded))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                playerResetCard
            }.padding(26).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private var cigaretteStyleRecords: some View {
        let purchased = store.economy.cigaretteBoxesPurchasedByStyle
        let smoked = store.economy.cigarettesCompletedByStyle
        let products = store.economyRules?.products.filter { $0.kind == .cigaretteBox } ?? []
        let ids = Set(purchased.keys).union(smoked.keys)
        let rows = products.filter { ids.contains($0.styleID) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let palette: [Color] = [DeskPuffPalette.accent, InventoryTheme.gold, Color(red: 0.42, green: 0.72, blue: 0.87), Color(red: 0.79, green: 0.52, blue: 0.78), Color(red: 0.47, green: 0.73, blue: 0.57), Color(red: 0.91, green: 0.62, blue: 0.40)]
        let data = rows.enumerated().map { index, product in
            CigaretteStyleRecord(id: product.styleID, name: tr(product.name), boxes: purchased[product.styleID, default: 0], smoked: smoked[product.styleID, default: 0], color: palette[index % palette.count])
        }
        let recordedPurchases = purchased.values.reduce(0, saturatedSum)
        let totalBoxes = purchased.values.reduce(0, saturatedSum)
        let totalSmoked = smoked.values.reduce(0, saturatedSum)
        return VStack(alignment: .leading, spacing: 11) {
            sectionHeading(tr("烟火记事"), detail: tr("每一盒的相逢、每一支的落幕，都留有一笔。"))
            if rows.isEmpty {
                Text(tr("从此刻起，替每款烟盒记下相逢与送别。"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).playerHubSurface(.inset, radius: 13)
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 8) {
                        profileRecordPill(tr("记下 {{0}} 款", rows.count), symbol: "shippingbox")
                        profileRecordPill(tr("共迎 {{0}} 盒", totalBoxes), symbol: "tray.full")
                        profileRecordPill(tr("送别 {{0}} 支", totalSmoked), symbol: "smoke.fill")
                        Spacer(minLength: 0)
                    }
                    HStack(alignment: .top, spacing: 13) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(tr("烟盒相逢 · 购入分布")).font(.system(size: 12, weight: .semibold))
                            HStack(spacing: 15) {
                                CigaretteStylePieChart(records: data, value: \.boxes)
                                    .frame(width: 116, height: 116)
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(data) { record in
                                        HStack(spacing: 6) {
                                            Circle().fill(record.color).frame(width: 7, height: 7)
                                            Text(record.name).lineLimit(1)
                                            Spacer(minLength: 4)
                                            Text("\(record.boxes)").monospacedDigit().foregroundStyle(.primary)
                                        }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).playerHubSurface(.inset, radius: 13)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(tr("烟支送别 · 完整抽毕")).font(.system(size: 12, weight: .semibold))
                            CigaretteStyleBarChart(records: data)
                                .frame(height: max(116, CGFloat(data.count * 31)))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).playerHubSurface(.inset, radius: 13)
                    }
                    VStack(spacing: 0) {
                        ForEach(data) { record in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2).fill(record.color).frame(width: 3, height: 18)
                                Text(record.name).lineLimit(1)
                                Spacer()
                                Text(tr("购入 {{0}} 盒", record.boxes)).foregroundStyle(.secondary)
                                Text(tr("抽毕 {{0}} 支", record.smoked)).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                            }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
                            if record.id != data.last?.id { Divider().opacity(0.35).padding(.leading, 14) }
                        }
                    }.playerHubSurface(.panel, radius: 13)
                }
            }
            if store.economy.statistics.cigaretteBoxesPurchased > recordedPurchases {
                Text(tr("旧时只记下烟盒总数，款式明细自此页启用后开始留存。"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func profileRecordPill(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(InventoryTheme.secondaryText)
            .padding(.horizontal, 9).padding(.vertical, 6).playerHubSurface(.inset, in: Capsule())
    }

    private func incomeFootprint(rules: EconomyRules) -> some View {
        let entries = store.economy.incomeHistory
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days: [(Date, Int)] = (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let cents = entries.filter { calendar.isDate(Date(timeIntervalSince1970: Double($0.hour) * 3600), inSameDayAs: date) }
                .reduce(0) { saturatedSum($0, $1.totalCents) }
            return (date, cents)
        }
        let maximum = max(1, days.map(\.1).max() ?? 0)
        let rank = rules.progress(completed: store.economy.completedCigarettes)
        let hourly = rules.ranks[rank.rankIndex].hourlyRateCents(forStar: rank.star)
        return VStack(alignment: .leading, spacing: 11) {
            sectionHeading(tr("收入足迹"), detail: tr("查看已到账收入与近七日变化"))
            HStack(spacing: 10) {
                recordCard(tr("累计到账"), value: money(store.economy.totalIncomeCents), unit: "", symbol: "yensign.circle.fill", featured: true)
                recordCard(tr("当前时薪"), value: money(hourly), unit: tr("/小时"), symbol: "clock")
                recordCard(tr("下次预计"), value: money(store.economy.estimatedPayoutCents(rules: rules)), unit: "", symbol: "arrow.down.circle")
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(tr("近七日到账")).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(tr("累计来源：津贴 {{0}} · 回收 {{1}} · 成就 {{2}}", money(store.economy.passiveIncomeCents), money(store.economy.recoveryIncomeCents), money(store.economy.achievementIncomeCents)))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(days, id: \.0) { day, cents in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4).fill(DeskPuffPalette.accent.opacity(cents > 0 ? 0.88 : 0.2))
                                .frame(maxWidth: .infinity).frame(height: max(4, 56 * CGFloat(cents) / CGFloat(maximum)))
                                .help(money(cents))
                            Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }.frame(height: 78, alignment: .bottom)
                if entries.isEmpty {
                    Text(tr("收入历史从本版本开始记录，旧存档无法还原过去的到账明细。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(14).playerHubSurface(.panel, radius: 14)
        }
    }


    private var achievementsSheet: some View {
        let stats = store.economy.statistics
        let completed = store.economy.completedCigarettes
        let rankProgressValue = store.economyRules?.progress(completed: completed)
        let rankIndex = rankProgressValue?.rankIndex ?? 0
        let rankProgress = rankProgressValue.map { $0.rankIndex * 5 + $0.star } ?? 0
        let ownedStyles = (store.economy.ownedBagStyleIDs ?? []).count
        let recoveryCraftCount = store.economy.recoveryCraftCount
        let discoveredCrafts = RecoveryRecipe.products.filter(store.hasDiscoveredRecoveryItem).count
        let total = 31
        let unlocked = achievementCount(stats: stats, completed: completed, rankIndex: rankIndex, rankProgress: rankProgress,
                                        ownedStyles: ownedStyles, recoveryCraftCount: recoveryCraftCount,
                                        discoveredCrafts: discoveredCrafts)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("成就图鉴")).font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(tr("已点亮 {{0}} / {{1}} 项 · 每一段旅程都有印记", unlocked, total)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { localState.showingAchievements = false } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28).background(Color.primary.opacity(0.06), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel(tr("关闭"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                achievementGroup(tr("烟火初见"), detail: tr("完整使用带来的成长印记"), symbol: "flame.fill") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                        achievementCard(tr("初次完整使用"), id: "初次完整使用", subtitle: tr("完成第一支香烟"), current: completed, target: 1, unit: tr("支"), symbol: "sparkle", rarity: tr("启程"))
                        achievementCard(tr("渐入佳境"), id: "渐入佳境", subtitle: tr("累计完整使用十支"), current: completed, target: 10, unit: tr("支"), symbol: "wind", rarity: tr("进阶"))
                        achievementCard(tr("烟火相伴"), id: "烟火相伴", subtitle: tr("累计完整使用五十支"), current: completed, target: 50, unit: tr("支"), symbol: "flame.fill", rarity: tr("珍藏"))
                        achievementCard(tr("百支纪念"), id: "百支纪念", subtitle: tr("累计完整使用二百支"), current: completed, target: 200, unit: tr("支"), symbol: "sun.max.fill", rarity: tr("稀有"))
                        achievementCard(tr("千支烟云"), id: "千支烟云", subtitle: tr("累计完整使用一千支"), current: completed, target: 1000, unit: tr("支"), symbol: "sparkles", rarity: tr("典藏"))
                    }
                }
                achievementGroup(tr("段位勋章"), detail: tr("每一次升星与晋阶都会留下新徽记"), symbol: "rosette") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                        achievementCard(tr("白银来客"), id: "白银来客", subtitle: tr("晋升至白银段位"), current: rankIndex, target: 1, unit: tr("阶"), symbol: RankBadgeStyle.symbol(for: 1), rarity: tr("进阶"), badgeColor: RankBadgeStyle.color(for: 1))
                        achievementCard(tr("黄金之路"), id: "黄金之路", subtitle: tr("晋升至黄金段位"), current: rankIndex, target: 2, unit: tr("阶"), symbol: RankBadgeStyle.symbol(for: 2), rarity: tr("珍藏"), badgeColor: RankBadgeStyle.color(for: 2))
                        achievementCard(tr("钻石之心"), id: "钻石之心", subtitle: tr("晋升至钻石段位"), current: rankIndex, target: 5, unit: tr("阶"), symbol: RankBadgeStyle.symbol(for: 5), rarity: tr("史诗"), badgeColor: RankBadgeStyle.color(for: 5))
                        achievementCard(tr("王者印记"), id: "王者印记", subtitle: tr("抵达王者段位"), current: rankIndex, target: 8, unit: tr("阶"), symbol: RankBadgeStyle.symbol(for: 8), rarity: tr("传说"), badgeColor: RankBadgeStyle.color(for: 8))
                        achievementCard(tr("三星渐满"), id: "三星渐满", subtitle: tr("当前段位达到三星"), current: rankProgress, target: 3, unit: tr("星阶"), symbol: "star.leadinghalf.filled", rarity: tr("进阶"))
                        achievementCard(tr("段位历程"), id: "段位历程", subtitle: tr("累计跨越十五个星阶"), current: rankProgress, target: 15, unit: tr("星阶"), symbol: "star.fill", rarity: tr("珍藏"))
                        achievementCard(tr("星河远征"), id: "星河远征", subtitle: tr("累计跨越三十个星阶"), current: rankProgress, target: 30, unit: tr("星阶"), symbol: "sparkles", rarity: tr("典藏"))
                    }
                }
                achievementGroup(tr("器物珍藏"), detail: tr("把喜欢的日常物件收入行囊"), symbol: "seal.fill") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                        achievementCard(tr("第一盒烟"), id: "第一盒烟", subtitle: tr("在商店购入第一盒香烟"), current: stats.cigaretteBoxesPurchased, target: 1, unit: tr("盒"), symbol: "shippingbox.fill", rarity: tr("启程"))
                        achievementCard(tr("常备烟仓"), id: "常备烟仓", subtitle: tr("累计购入十盒香烟"), current: stats.cigaretteBoxesPurchased, target: 10, unit: tr("盒"), symbol: "shippingbox.fill", rarity: tr("珍藏"))
                        achievementCard(tr("火种初藏"), id: "火种初藏", subtitle: tr("购入第一只打火机"), current: stats.lightersPurchased, target: 1, unit: tr("只"), symbol: "bolt.fill", rarity: tr("启程"))
                        achievementCard(tr("火种收藏家"), id: "火种收藏家", subtitle: tr("累计购入十只打火机"), current: stats.lightersPurchased, target: 10, unit: tr("只"), symbol: "bolt.fill", rarity: tr("稀有"))
                        achievementCard(tr("桌边雅器"), id: "桌边雅器", subtitle: tr("购入第一只烟灰缸"), current: stats.ashtraysPurchased, target: 1, unit: tr("只"), symbol: "circle.dotted", rarity: tr("启程"))
                        achievementCard(tr("器物陈列"), id: "器物陈列", subtitle: tr("累计购入五只烟灰缸"), current: stats.ashtraysPurchased, target: 5, unit: tr("只"), symbol: "circle.hexagongrid.fill", rarity: tr("稀有"))
                        achievementCard(tr("百元珍藏"), id: "百元珍藏", subtitle: tr("累计消费达到 ¥100"), current: stats.totalSpentCents, target: 10_000, unit: "", formatted: money(stats.totalSpentCents), targetLabel: "¥100", symbol: "seal.fill", rarity: tr("珍藏"))
                        achievementCard(tr("千元珍藏"), id: "千元珍藏", subtitle: tr("累计消费达到 ¥1,000"), current: stats.totalSpentCents, target: 100_000, unit: "", formatted: money(stats.totalSpentCents), targetLabel: "¥1,000", symbol: "crown.fill", rarity: tr("典藏"))
                    }
                }
                achievementGroup(tr("行囊旅程"), detail: tr("扩展容量，收集适配外观"), symbol: "backpack.fill") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                        achievementCard(tr("行囊初阶"), id: "行囊初阶", subtitle: tr("完成第一次容量扩展"), current: stats.capacityUpgrades, target: 1, unit: tr("次"), symbol: "backpack.fill", rarity: tr("进阶"))
                        achievementCard(tr("行囊进阶"), id: "行囊进阶", subtitle: tr("累计完成四次容量扩展"), current: stats.capacityUpgrades, target: 4, unit: tr("次"), symbol: "backpack.fill", rarity: tr("史诗"))
                        achievementCard(tr("风格初藏"), id: "风格初藏", subtitle: tr("解锁第一款背包外观"), current: ownedStyles, target: 1, unit: tr("款"), symbol: "bag.fill", rarity: tr("启程"))
                        achievementCard(tr("随身收藏"), id: "随身收藏", subtitle: tr("解锁五款背包外观"), current: ownedStyles, target: 5, unit: tr("款"), symbol: "sparkles", rarity: tr("典藏"))
                        let discarded = stats.cigaretteBoxesDiscarded + stats.lightersDiscarded + stats.ashtraysDiscarded
                        achievementCard(tr("轻装上路"), id: "轻装上路", subtitle: tr("整理并丢弃第一件物品"), current: discarded, target: 1, unit: tr("件"), symbol: "arrow.up.forward.box.fill", rarity: tr("启程"))
                        achievementCard(tr("行囊有序"), id: "行囊有序", subtitle: tr("累计处理十件物品"), current: discarded, target: 10, unit: tr("件"), symbol: "tray.full.fill", rarity: tr("珍藏"))
                    }
                }
                achievementGroup(tr("合成发现"), detail: tr("尝试搭配，点亮合成图鉴"), symbol: "sparkles") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                        achievementCard(tr("初次合成"), id: "recovery.craft.first", subtitle: tr("完成第一次材料合成"), current: recoveryCraftCount, target: 1, unit: tr("次"), symbol: "sparkles", rarity: tr("启程"), rewardCents: 500)
                        achievementCard(tr("配方探索者"), id: "recovery.craft.10", subtitle: tr("累计完成十次合成"), current: recoveryCraftCount, target: 10, unit: tr("次"), symbol: "wand.and.stars", rarity: tr("进阶"), rewardCents: 1_000)
                        achievementCard(tr("合成达人"), id: "recovery.craft.50", subtitle: tr("累计完成五十次合成"), current: recoveryCraftCount, target: 50, unit: tr("次"), symbol: "sparkles", rarity: tr("珍藏"), rewardCents: 2_500)
                        achievementCard(tr("第一次出件"), id: "recovery.discover.first", subtitle: tr("发现第一件工坊作品"), current: discoveredCrafts, target: 1, unit: tr("件"), symbol: "seal.fill", rarity: tr("进阶"), rewardCents: 1_000)
                        achievementCard(tr("图鉴收藏家"), id: "recovery.discover.all", subtitle: tr("发现所有工坊作品"), current: discoveredCrafts, target: RecoveryRecipe.products.count, unit: tr("件"), symbol: "books.vertical.fill", rarity: tr("典藏"), rewardCents: 5_000)
                    }
                }
                }.padding(.vertical, 4)
            }
        }
        .padding(22).frame(width: 780, height: 660)
        .foregroundStyle(InventoryTheme.primaryText)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(colors: [InventoryTheme.backgroundTop, InventoryTheme.backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [InventoryTheme.accent.opacity(0.09), .clear], center: .topLeading, startRadius: 0, endRadius: 510)
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
    }

    private func achievementCount(stats: PlayerStatistics, completed: Int, rankIndex: Int, rankProgress: Int, ownedStyles: Int,
                                  recoveryCraftCount: Int, discoveredCrafts: Int) -> Int {
        [completed >= 1, completed >= 10, completed >= 50, completed >= 200, completed >= 1000,
         rankIndex >= 1, rankIndex >= 2, rankIndex >= 4, rankIndex >= 8,
         rankProgress >= 3, rankProgress >= 15, rankProgress >= 30,
         stats.cigaretteBoxesPurchased >= 1, stats.cigaretteBoxesPurchased >= 10,
         stats.lightersPurchased >= 1, stats.lightersPurchased >= 10,
         stats.ashtraysPurchased >= 1, stats.ashtraysPurchased >= 5,
         stats.totalSpentCents >= 10_000, stats.totalSpentCents >= 100_000,
         stats.capacityUpgrades >= 1, stats.capacityUpgrades >= 4,
         ownedStyles >= 1, ownedStyles >= 5,
         stats.cigaretteBoxesDiscarded + stats.lightersDiscarded + stats.ashtraysDiscarded >= 1,
         stats.cigaretteBoxesDiscarded + stats.lightersDiscarded + stats.ashtraysDiscarded >= 10,
         recoveryCraftCount >= 1, recoveryCraftCount >= 10, recoveryCraftCount >= 50,
         discoveredCrafts >= 1, discoveredCrafts >= RecoveryRecipe.products.count].filter { $0 }.count
    }

    private var playerResetCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 19)).foregroundStyle(DeskPuffPalette.accent)
                .frame(width: 40, height: 40).background(DeskPuffPalette.selection, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("重新开始一段旅程")).font(.system(size: 13, weight: .semibold))
                Text(tr("清除当前玩家进度，并创建全新的初始存档。"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(tr("重置存档…")) { localState.confirmingSaveReset = true }
                .buttonStyle(PlayerHubButtonStyle())
        }
        .padding(14)
        .playerHubSurface(.inset, radius: 16)
    }
    private func sectionHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(detail).font(.system(size: 12)).foregroundStyle(InventoryTheme.secondaryText)
        }
    }
    private func rankHero(rules: EconomyRules) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let completed = store.economy.completedCigarettes
            let progress = rules.progress(completed: completed)
            let rank = rules.ranks[progress.rankIndex]
            let nextThreshold = progress.nextThreshold
            let progressValue = nextThreshold.map { min(1, max(0, Double(completed - progress.threshold) / Double(max(1, $0 - progress.threshold)))) } ?? 1
            let incomeProgress = store.economy.incomeProgress(at: context.date, rules: rules)
            let secondsLeft = max(0, Int(ceil((1 - incomeProgress) * Double(rules.incomeIntervalSeconds))))
            HStack(alignment: .center, spacing: 24) {
                ZStack {
                    if let artwork = RankBadgeStyle.artwork(for: progress.rankIndex) {
                        artwork.resizable().interpolation(.high).scaledToFit().frame(width: 132, height: 132)
                            .shadow(color: RankBadgeStyle.color(for: progress.rankIndex).opacity(0.30), radius: 14, y: 2)
                    } else {
                        Circle().fill(RankBadgeStyle.color(for: progress.rankIndex).opacity(0.12)).frame(width: 132, height: 132)
                        Circle().strokeBorder(RankBadgeStyle.color(for: progress.rankIndex).opacity(0.30), lineWidth: 1).frame(width: 116, height: 116)
                        VStack(spacing: 2) {
                            Image(systemName: RankBadgeStyle.symbol(for: progress.rankIndex)).font(.system(size: 38, weight: .regular))
                            Text(tr("{{0}} 星", progress.star)).font(.system(size: 11, weight: .semibold, design: .rounded))
                        }.foregroundStyle(RankBadgeStyle.color(for: progress.rankIndex))
                    }
                }
                .background {
                    RadialGradient(colors: [RankBadgeStyle.color(for: progress.rankIndex).opacity(0.22), .clear],
                                   center: .center, startRadius: 8, endRadius: 80)
                        .allowsHitTesting(false)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("逐星而行 · 自在成章"))
                        .font(.system(size: 10, weight: .semibold)).tracking(1.3)
                        .foregroundStyle(DeskPuffPalette.accent)
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(tr(rank.name)).font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(tr("段位")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 7) {
                        ForEach(Array(rank.starThresholds.enumerated()), id: \.offset) { index, threshold in
                            HStack(spacing: 4) {
                                Image(systemName: completed >= threshold ? "star.fill" : "star")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("\(index + 1)").font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(completed >= threshold ? InventoryTheme.gold : InventoryTheme.secondaryText)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .playerHubSurface(completed >= threshold ? .item : .inset, in: Capsule())
                        }
                    }
                    if let nextThreshold {
                        HStack(spacing: 10) {
                            ProgressView(value: progressValue).tint(DeskPuffPalette.accent).frame(maxWidth: 240)
                            Text(tr("还差 {{0}} 支晋升", max(0, nextThreshold - completed)))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(tr("已抵达最高段位")).font(.system(size: 11, weight: .medium)).foregroundStyle(DeskPuffPalette.accent)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 12) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(tr("可用余额")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Text(wallet(store.economy.balanceCents)).font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(DeskPuffPalette.gold)
                    }
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(tr("段位津贴 · 每半小时")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Text("¥\(rank.halfHourPayoutCents(forStar: progress.star) / 100)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(DeskPuffPalette.gold)
                        Text(secondsLeft == 0 ? tr("即将到账") : tr("{{0}}分后到账", secondsLeft / 60))
                            .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(22)
            .playerHubSurface(.panel, radius: 21)
            .shadow(color: .black.opacity(0.23), radius: 10, y: 5)
        }
    }
    private func rankJourney(rules: EconomyRules, currentRank: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(tr("段位旅程"), detail: tr("完整使用香烟，逐星向更高段位前进"))
            HStack(alignment: .top, spacing: 7) {
                ForEach(Array(rules.ranks.enumerated()), id: \.element.id) { index, rank in
                    VStack(spacing: 8) {
                        ZStack {
                            if let artwork = RankBadgeStyle.artwork(for: index, small: true) {
                                artwork.resizable().interpolation(.high).scaledToFit().padding(1)
                                    .opacity(index <= currentRank ? 1 : 0.42)
                            } else {
                                Circle().fill(index <= currentRank ? RankBadgeStyle.color(for: index).opacity(index == currentRank ? 0.19 : 0.11) : Color.primary.opacity(0.035))
                                Circle().strokeBorder(index == currentRank ? RankBadgeStyle.color(for: index).opacity(0.52) : DeskPuffPalette.outline, lineWidth: 0.8)
                                Image(systemName: RankBadgeStyle.symbol(for: index))
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(index <= currentRank ? RankBadgeStyle.color(for: index) : Color.secondary.opacity(0.5))
                            }
                        }.frame(width: 42, height: 42)
                        Text(tr(rank.name)).font(.system(size: 11, weight: index == currentRank ? .semibold : .medium))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(index == currentRank ? DeskPuffPalette.action : Color.primary.opacity(0.78))
                        HStack(spacing: 2) {
                            ForEach(Array(rank.starThresholds.enumerated()), id: \.offset) { star, threshold in
                                Circle().fill(store.economy.completedCigarettes >= threshold ? DeskPuffPalette.accent : Color.secondary.opacity(0.18))
                                    .frame(width: 5, height: 5)
                                    .help(tr("{{0}} {{1}} 星 · {{2}} 支", tr(rank.name), star + 1, threshold))
                            }
                        }
                        Text(tr("¥{{0}}–¥{{1}}/次", rank.halfHourPayoutCents(forStar: 1) / 100, rank.halfHourPayoutCents(forStar: 5) / 100))
                            .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if index == currentRank {
                            PlayerHubSurface.item.fill(RoundedRectangle(cornerRadius: 13), tint: RankBadgeStyle.color(for: index))
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .playerHubSurface(.inset, radius: 17)
        }
    }
    private func recordCard(_ title: String, value: String, unit: String, symbol: String, featured: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(featured ? InventoryTheme.gold : InventoryTheme.accentBright)
                .frame(width: 28, height: 28)
                .playerHubSurface(featured ? .item : .inset, radius: 8)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: featured ? 22 : 18, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                if !unit.isEmpty { Text(tr(unit)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary) }
            }
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
        .playerHubSurface(featured ? .item : .panel, radius: 15)
    }
    private func money(_ cents: Int) -> String { "¥\(cents / 100)" }
    private func saturatedSum(_ lhs: Int, _ rhs: Int) -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : value
    }
    private func spendingBreakdown(stats: PlayerStatistics) -> some View {
        let knownSpend = stats.cigaretteSpendCents + stats.lighterSpendCents + stats.ashtraySpendCents + stats.capacitySpendCents + stats.bagStyleSpendCents
        let rows: [(String, String, Int, Color)] = [
            (tr("香烟"), "shippingbox", stats.cigaretteSpendCents, Color(red: 0.67, green: 0.51, blue: 0.94)),
            (tr("打火机"), "flame", stats.lighterSpendCents, Color(red: 0.92, green: 0.72, blue: 0.50)),
            (tr("烟灰缸"), "circle.dotted", stats.ashtraySpendCents, Color(red: 0.50, green: 0.67, blue: 0.86)),
            (tr("容量扩展"), "square.grid.3x3", stats.capacitySpendCents, Color(red: 0.85, green: 0.52, blue: 0.69)),
            (tr("背包外观"), "backpack", stats.bagStyleSpendCents, Color(red: 0.53, green: 0.46, blue: 0.77)),
            (tr("随身道具及其他"), "sparkles", max(0, stats.totalSpentCents - knownSpend), Color(red: 0.61, green: 0.59, blue: 0.68))
        ]
        let total = rows.reduce(0) { $0 + $1.2 }
        let durableSpend = stats.lighterSpendCents + stats.ashtraySpendCents + stats.capacitySpendCents + stats.bagStyleSpendCents + max(0, stats.totalSpentCents - knownSpend)
        let avgPerCigarette = store.economy.completedCigarettes > 0 ? stats.totalSpentCents / store.economy.completedCigarettes : 0
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 25) {
                ZStack {
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let radius = min(size.width, size.height) / 2 - 14
                        let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                          width: radius * 2, height: radius * 2))
                        context.stroke(ring, with: .color(InventoryTheme.outline.opacity(0.55)), lineWidth: 21)

                        let segments = rows.filter { $0.2 > 0 }
                        if segments.count == 1, let segment = segments.first {
                            context.stroke(ring, with: .linearGradient(
                                Gradient(colors: [segment.3, segment.3.opacity(0.66)]),
                                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 21)
                        } else if total > 0 {
                            var start = -90.0
                            for segment in segments {
                                let sweep = 360 * Double(segment.2) / Double(total)
                                let gap = min(2.8, sweep * 0.30) / 2
                                let end = start + sweep
                                var arc = Path()
                                arc.addArc(center: center, radius: radius, startAngle: .degrees(start + gap),
                                           endAngle: .degrees(end - gap), clockwise: false)
                                context.stroke(arc, with: .linearGradient(
                                    Gradient(colors: [segment.3, segment.3.opacity(0.68)]),
                                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 21)
                                start = end
                            }
                        }
                    }
                    .accessibilityHidden(true)
                    Circle()
                        .fill(RadialGradient(colors: [InventoryTheme.panelTop, InventoryTheme.gridBottom],
                                             center: .topLeading, startRadius: 0, endRadius: 94))
                        .overlay(Circle().strokeBorder(InventoryTheme.cardEdge, lineWidth: 0.75))
                        .frame(width: 89, height: 89)
                    VStack(spacing: 2) {
                        Text(tr("总支出")).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        Text(money(total)).font(.system(size: 16, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(InventoryTheme.gold).lineLimit(1).minimumScaleFactor(0.6)
                    }.frame(width: 77)
                }.frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 7) {
                            Circle().fill(row.3).frame(width: 8, height: 8).accessibilityHidden(true)
                            Image(systemName: row.1).font(.system(size: 11)).foregroundStyle(InventoryTheme.secondaryText)
                                .frame(width: 15).accessibilityHidden(true)
                            Text(row.0).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(money(row.2)) · \(total > 0 ? Int(Double(row.2) * 100 / Double(total)) : 0)%")
                                .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                                .foregroundStyle(InventoryTheme.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Rectangle().fill(DeskPuffPalette.line).frame(height: 0.5)
            HStack(spacing: 10) {
                spendingMetric(tr("日常消耗"), value: money(stats.cigaretteSpendCents + stats.lighterSpendCents + stats.ashtraySpendCents), caption: tr("香烟、打火机与烟灰缸"))
                spendingMetric(tr("收藏与装备"), value: money(durableSpend), caption: tr("扩容、外观与随身道具"))
                spendingMetric(tr("每支均摊"), value: money(avgPerCigarette), caption: tr("累计消费 ÷ 完整使用"))
            }
        }
        .padding(17)
        .playerHubSurface(.panel, radius: 17)
    }

    private func spendingMetric(_ title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(caption).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .playerHubSurface(.inset, radius: 11)
    }
    private func achievementOverview(unlocked: Int, total: Int) -> some View {
        HStack(spacing: 15) {
            ZStack {
                Circle().stroke(DeskPuffPalette.outline, lineWidth: 5)
                Circle().trim(from: 0, to: Double(unlocked) / Double(max(1, total)))
                    .stroke(AngularGradient(colors: [DeskPuffPalette.accent.opacity(0.55), DeskPuffPalette.action], center: .center),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(unlocked)").font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("/ \(total)").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 5) {
                Text(unlocked == total ? tr("成就图鉴已点亮") : tr("旅程仍在继续"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(tr("已点亮 {{0}} 项 · 尚有 {{1}} 项等待解锁", unlocked, total - unlocked))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                ProgressView(value: Double(unlocked), total: Double(max(1, total))).tint(DeskPuffPalette.accent)
            }
            Spacer(minLength: 8)
            Image(systemName: unlocked == total ? "rosette" : "medal.fill")
                .font(.system(size: 23, weight: .medium)).foregroundStyle(DeskPuffPalette.accent.opacity(0.85))
                .frame(width: 48, height: 48).background(DeskPuffPalette.selection, in: Circle())
        }
        .padding(15)
    }

    private func achievementGroup<Content: View>(_ title: String, detail: String, symbol: String,
                                                  @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(DeskPuffPalette.accent)
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            content()
        }
    }

    private func achievementCard(_ title: String, id: String, subtitle: String, current: Int, target: Int, unit: String, formatted: String? = nil, targetLabel: String? = nil, symbol: String, rarity: String, badgeColor: Color? = nil, rewardCents: Int = 500) -> some View {
        let complete = current >= target
        let progress = min(Double(max(0, current)), Double(target)) / Double(target)
        let emblemColor = badgeColor ?? (complete ? Color(red: 0.78, green: 0.56, blue: 0.22) : DeskPuffPalette.accent)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 11) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [emblemColor.opacity(0.20), emblemColor.opacity(0.055)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle().strokeBorder(emblemColor.opacity(complete ? 0.48 : 0.19), lineWidth: 1)
                    Circle().strokeBorder(emblemColor.opacity(0.12), lineWidth: 0.6).padding(4)
                    Image(systemName: complete ? symbol : "lock.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(emblemColor.opacity(complete ? 1 : 0.54))
                }.frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Text(rarity).font(.system(size: 10, weight: .semibold)).foregroundStyle(emblemColor)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(emblemColor.opacity(0.09), in: Capsule())
                Spacer()
                Text(complete ? tr("已点亮") : tr("成长中")).font(.system(size: 10, weight: .medium)).foregroundStyle(complete ? emblemColor : .secondary)
            }
            ProgressView(value: progress).tint(emblemColor)
            HStack {
                Text("\(formatted ?? "\(current)\(unit)") / \(targetLabel ?? "\(target)\(unit)")")
                    .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(emblemColor)
            }
            if complete {
                if store.economy.claimedAchievementIDs.contains(id) {
                    Label(tr("奖励已领取"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(InventoryTheme.gold)
                } else {
                    Button {
                        store.claimAchievement(id: id, current: current, target: target, rewardCents: rewardCents)
                    } label: {
                        Label(tr("领取金币 {{0}}", money(rewardCents)), systemImage: "gift.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(InventoryTheme.gold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .playerHubSurface(complete ? .item : .panel, radius: 16, tint: emblemColor)
    }
    private func wallet(_ cents: Int) -> String {
        cents.isMultiple(of: 100) ? "¥\(cents / 100)" : String(format: "¥%.2f", Double(cents) / 100)
    }
}
