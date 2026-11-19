import SwiftUI
import DeskPuffCore
import Combine

private enum StoreCategory: String, CaseIterable, Identifiable {
    case all = "全部", cigarettes = "香烟", lighters = "打火机", ashtrays = "烟灰缸", tools = "随身道具", capacity = "背包扩容", bags = "背包外观"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .cigarettes: "shippingbox.fill"
        case .lighters: "flame.fill"
        case .ashtrays: "circle.hexagongrid.fill"
        case .tools: "sparkles.rectangle.stack.fill"
        case .capacity: "square.grid.3x3.fill"
        case .bags: "backpack.fill"
        }
    }
}
@MainActor private final class StoreViewState: ObservableObject {
    @Published var category: StoreCategory = .all
}

@MainActor struct StoreView: View {
    @ObservedObject private var store = InventoryStore.shared
    @StateObject private var state = StoreViewState()
    private let columns = [GridItem(.adaptive(minimum: 178, maximum: 230), spacing: 16)]

    var body: some View {
        if let rules = store.economyRules {
            VStack(alignment: .leading, spacing: 18) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(StoreCategory.allCases) { category in
                            let selected = state.category == category
                            Button { state.category = category } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: category.symbol).font(.system(size: 11, weight: .semibold))
                                    Text(tr(category.rawValue)).font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(selected ? Color.white : InventoryTheme.secondaryText)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .playerHubSurface(selected ? .active : .panel, in: Capsule())
                            }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                .padding(7)
                .playerHubSurface(.inset, radius: 20)
                if state.category == .all {
                    allCatalogSections(rules)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    switch state.category {
                    case .all: EmptyView()
                    case .capacity:
                        ForEach(rules.bags) { offer in capacityCard(offer) }
                    case .bags:
                        ForEach(rules.bagStyles) { offer in
                            if let style = InventoryBagStyle.item(offer.styleID) { bagStyleCard(offer, style: style) }
                        }
                    case .cigarettes, .lighters, .ashtrays, .tools:
                        ForEach(rules.products.filter { $0.kind == selectedKind && isAvailable($0) }) { product in
                            productCard(product)
                        }
                    }
                    }
                }
            }.onAppear { store.settleIncome() }
        } else { Text(tr("商店暂不可用")).foregroundStyle(.secondary) }
    }

    private var selectedKind: InventoryKind {
        switch state.category {
        case .lighters: .lighter
        case .ashtrays: .ashtray
        case .tools: .tool
        default: .cigaretteBox
        }
    }

    @ViewBuilder private func allCatalogSections(_ rules: EconomyRules) -> some View {
        VStack(alignment: .leading, spacing: 25) {
            let cigarettes = rules.products.filter { $0.kind == .cigaretteBox && isAvailable($0) }
            if !cigarettes.isEmpty {
                catalogSection(tr("香烟"), symbol: StoreCategory.cigarettes.symbol, detail: tr("整盒购买 · 20 支装")) {
                    productGrid(cigarettes)
                }
            }
            let lighters = rules.products.filter { $0.kind == .lighter && isAvailable($0) }
            if !lighters.isEmpty {
                catalogSection(tr("打火机"), symbol: StoreCategory.lighters.symbol, detail: tr("一次性用品")) {
                    productGrid(lighters)
                }
            }
            let tools = rules.products.filter { $0.kind == .tool && isAvailable($0) }
            if !tools.isEmpty {
                catalogSection(tr("随身道具"), symbol: StoreCategory.tools.symbol, detail: tr("放入背包即生效 · 每类限持一件")) {
                    productGrid(tools)
                }
            }
            let ashtrays = rules.products.filter { $0.kind == .ashtray && isAvailable($0) }
            if !ashtrays.isEmpty {
                catalogSection(tr("烟灰缸"), symbol: StoreCategory.ashtrays.symbol, detail: tr("桌面器物")) {
                    productGrid(ashtrays)
                }
            }
            if !rules.bags.isEmpty {
                catalogSection(tr("背包扩容"), symbol: StoreCategory.capacity.symbol, detail: tr("按容量逐级解锁")) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(rules.bags) { capacityCard($0) }
                    }
                }
            }
            if !rules.bagStyles.isEmpty {
                catalogSection(tr("背包外观"), symbol: StoreCategory.bags.symbol, detail: tr("外观按背包规格适配")) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(rules.bagStyles) { offer in
                            if let style = InventoryBagStyle.item(offer.styleID) { bagStyleCard(offer, style: style) }
                        }
                    }
                }
            }
        }
    }

    private func productGrid(_ products: [StoreProduct]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(products) { product in productCard(product) }
        }
    }

    private func catalogSection<Content: View>(_ title: String, symbol: String, detail: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(InventoryTheme.accentBright)
                    .frame(width: 31, height: 31)
                    .playerHubSurface(.item, radius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(detail).font(.system(size: 11, weight: .medium)).foregroundStyle(InventoryTheme.secondaryText)
                }
                Rectangle()
                    .fill(LinearGradient(colors: [InventoryTheme.accent.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                    .padding(.leading, 8)
            }
            content()
        }
    }
    private func productCard(_ product: StoreProduct) -> some View {
        card {
            artworkStage {
                    if let effect = product.passiveEffect {
                        if let artwork = storeToolArtwork(productID: product.id) {
                            ZStack(alignment: .bottom) {
                                Image(nsImage: artwork)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(12)
                                Text(tr(effect.benefit))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(.black.opacity(0.38), in: Capsule())
                                    .padding(8)
                            }
                        } else {
                            VStack(spacing: 9) {
                                Image(systemName: effect.symbol).font(.system(size: 34, weight: .light)).foregroundStyle(InventoryTheme.accentBright)
                                Text(tr(effect.benefit)).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center).lineLimit(2)
                            }.padding(11)
                        }
                    } else {
                        ProductStylePreview(kind: previewKind(product.kind), styleID: product.styleID, revision: 0)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(13)
                            .shadow(color: .black.opacity(0.48), radius: 6, y: 5)
                    }
            }
            .frame(height: 150)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr(product.name)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    Text(tr(product.specification)).lineLimit(2)
                    Circle().fill(DeskPuffPalette.line).frame(width: 3, height: 3)
                    Text(tr("持有 {{0}}", store.layout.items.filter { $0.kind == product.kind && $0.styleID == product.styleID }.count))
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(InventoryTheme.secondaryText)
                let footprint = product.kind.footprint
                Text(tr("占用格子 {{0}}×{{1}}", footprint.width, footprint.height))
                    .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(InventoryTheme.secondaryText)
            }
            Rectangle().fill(DeskPuffPalette.line).frame(height: 0.5).padding(.vertical, 2)
            let carried = product.passiveEffect.map { store.hasCarriedTool($0) } ?? false
            priceRow(store.purchasePrice(for: product), originalPrice: product.priceCents,
                     title: carried ? tr("已携带") : tr("购入"), disabled: carried) { _ = store.purchase(product) }
        }
    }
    private func capacityCard(_ offer: BagOffer) -> some View {
        let isCurrent = offer.stage == store.capacityStage
        let isEarlier = offer.stage < store.capacityStage
        let owned = isEarlier || store.economy.ownedBagStages.contains(offer.stage)
        let isNext = offer.stage == store.capacityStage + 1
        let actionTitle: String
        switch (isCurrent, isEarlier, isNext, owned) {
        case (true, _, _, _): actionTitle = tr("当前使用")
        case (_, true, _, _): actionTitle = tr("已购买")
        case (_, _, true, true): actionTitle = tr("继续扩容")
        case (_, _, true, false): actionTitle = tr("解锁")
        case (_, _, false, true): actionTitle = tr("已购买")
        default: actionTitle = tr("先解锁上一级")
        }
        return card {
            ZStack {
                artworkStage {
                    VStack(spacing: 9) {
                        Image(systemName: "square.grid.3x3.fill").font(.system(size: 37, weight: .light))
                            .foregroundStyle(InventoryTheme.accentBright)
                        Text(tr(offer.specification)).font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                VStack { HStack { stagePill(offer.stage); Spacer() }; Spacer() }.padding(10)
            }.frame(height: 150)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr(offer.name)).font(.system(size: 13, weight: .semibold))
                Text(tr("容量逐阶提升 · 外观与格数同步适配")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Rectangle().fill(DeskPuffPalette.line).frame(height: 0.5).padding(.vertical, 2)
            HStack {
                Text(isCurrent ? tr("当前使用") : (owned ? tr("已购买") : money(offer.priceCents)))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Button(actionTitle) {
                    if isNext && owned { store.setCapacityStage(offer.stage) }
                    else { _ = store.purchaseBag(offer) }
                }
                .buttonStyle(PlayerHubButtonStyle(prominent: isNext && !isCurrent))
                .disabled(isCurrent || !isNext)
            }.padding(.top, 3)
        }
    }
    private func bagStyleCard(_ offer: BagStyleOffer, style: InventoryBagStyle) -> some View {
        let owned = (store.economy.ownedBagStyleIDs ?? []).contains(style.id)
        let compatible = style.category == store.currentBagCategory
        let image = Bundle.module.url(forResource: style.asset, withExtension: "png", subdirectory: "Resources/InventoryBags").flatMap(NSImage.init(contentsOf:))
        return card {
            artworkStage {
                    Group {
                        if let image {
                            Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(10)
                                .shadow(color: .black.opacity(0.48), radius: 6, y: 5)
                        }
                        else { Image(systemName: "backpack").resizable().scaledToFit().padding(30) }
                    }
            }.frame(height: 150)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr(style.name)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(tr("{{0}}系列 · 专属外观", tr(style.category.title))).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Rectangle().fill(DeskPuffPalette.line).frame(height: 0.5).padding(.vertical, 2)
            priceRow(offer.priceCents, title: owned ? tr("已拥有") : (compatible ? tr("购买") : tr("先扩容")), disabled: owned || !compatible) {
                _ = store.purchaseBagStyle(offer)
            }
        }
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7, content: content)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .playerHubSurface(.panel, radius: 18)
            .shadow(color: .black.opacity(0.18), radius: 7, y: 4)
    }
    private func priceRow(_ cents: Int, originalPrice: Int? = nil, title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(tr("售价")).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                    if let originalPrice, originalPrice != cents {
                        Text(money(originalPrice)).font(.system(size: 10, weight: .medium)).strikethrough().foregroundStyle(.tertiary)
                    }
                }
                Text(cents == 0 ? tr("初始") : money(cents)).font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(DeskPuffPalette.gold)
            }
            Spacer()
            Button(title, action: action).buttonStyle(PlayerHubButtonStyle(prominent: !disabled)).disabled(disabled)
        }.padding(.top, 1)
    }
    private func artworkStage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .playerHubSurface(.display, radius: 12)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func stagePill(_ stage: Int) -> some View {
        Text(tr("容量 · {{0}}", stage + 1)).font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(InventoryTheme.accentBright).padding(.horizontal, 8).padding(.vertical, 5)
            .playerHubSurface(.item, in: Capsule())
    }
    private func previewKind(_ kind: InventoryKind) -> ProductStyleKind {
        switch kind { case .cigaretteBox: .boxes; case .lighter: .lighters; default: .ashtrays }
    }
    private func isAvailable(_ product: StoreProduct) -> Bool {
        let registry = StylePackageRegistry.shared
        switch product.kind {
        case .cigaretteBox: return registry.visibleCigaretteBoxes.contains { $0.id == product.styleID }
        case .lighter: return registry.lighters.contains { $0.id == product.styleID }
        case .ashtray: return registry.ashtrays.contains { $0.id == product.styleID }
        case .tool: return product.passiveEffect != nil
        default: return false
        }
    }
    private func money(_ cents: Int) -> String { cents.isMultiple(of: 100) ? "¥\(cents / 100)" : String(format: "¥%.2f", Double(cents) / 100) }
}
