import SwiftUI
import Combine
import DeskPuffCore

@MainActor struct RecoveryCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: InventoryStore
    var developerPreview = false

    private let columns = [GridItem(.adaptive(minimum: 225), spacing: 13)]
    private let products = RecoveryRecipe.products + [.mysteryJunk]
    private var discovered: [RecoveryMaterial] { products.filter(store.hasDiscoveredRecoveryItem) }
    private var visibleItems: [RecoveryMaterial] { products }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            LazyVGrid(columns: columns, alignment: .leading, spacing: 13) {
                ForEach(visibleItems) { product in
                    if developerPreview || store.hasDiscoveredRecoveryItem(product) {
                        entryCard(product)
                    } else {
                        unknownCard
                    }
                }
            }
        }
        .foregroundStyle(InventoryTheme.primaryText)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(InventoryTheme.gold)
                .frame(width: 46, height: 46)
                .playerHubSurface(.item, radius: 13)
                .accessibilityHidden(true)
            Text(tr("合成图鉴"))
                .font(.system(size: 21, weight: .semibold, design: .rounded))
            Spacer()
            Text(developerPreview
                 ? tr("{{0}} 件藏品", products.count)
                 : tr("已发现 {{0}} / {{1}}", discovered.count, products.count))
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(InventoryTheme.gold)
            if !developerPreview {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(tr("关闭"))
            }
        }
        .padding(16)
        .playerHubSurface(.panel, radius: 16)
    }

    private var unknownCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(InventoryTheme.backgroundBottom.opacity(0.65))
                Image(systemName: "lock.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(InventoryTheme.accentBright)
                    .accessibilityHidden(true)
            }
            .frame(height: 126)
            Text(tr("尚未发现的藏品")).font(.headline)
            Text(tr("首次合成后，图鉴会公开成品、配方与介绍。"))
                .font(.caption).foregroundStyle(InventoryTheme.secondaryText)
                .lineLimit(2).frame(height: 32, alignment: .topLeading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 430, alignment: .topLeading)
        .padding(12)
        .playerHubSurface(.panel, radius: 16)
    }

    private func entryCard(_ product: RecoveryMaterial) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            RecoveryMaterialArt(material: product)
                .padding(12)
                .frame(height: 126)
                .frame(maxWidth: .infinity)
                .playerHubSurface(.inset, radius: 12)
                .accessibilityHidden(true)
            Text(product.title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            if let recipe = RecoveryRecipe.all.first(where: { $0.product == product }) {
                Text(tr("{{0}}价值 · {{1}} 种材料", recipe.valueTier.title, recipe.ingredients.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(recipe.valueTier == .high ? InventoryTheme.gold : InventoryTheme.secondaryText)
                    .lineLimit(1)
            }
            Text(tr("当前回收报价 {{0}}", recoveryMoney(product.priceCents(hour: RecoveryMaterial.marketHour(at: Date())))))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(InventoryTheme.gold)
                .lineLimit(1)
            Text(product.workshopDescription)
                .font(.caption).foregroundStyle(InventoryTheme.secondaryText)
                .lineLimit(2).frame(height: 32, alignment: .topLeading)
            Divider()
            let recipes = RecoveryRecipe.all.filter { $0.product == product }
            if recipes.isEmpty {
                Label(tr("任意未配上的组合"), systemImage: "shuffle")
                    .font(.caption.weight(.medium))
            } else {
                ForEach(recipes) { recipe in
                    ForEach(recipe.ingredients) { ingredient in
                        HStack(spacing: 7) {
                            RecoveryIngredientArt(ingredient: ingredient)
                                .frame(width: 29, height: 26)
                                .accessibilityHidden(true)
                            Text(tr("{{0}} × 1", ingredient.title))
                                .font(.caption.weight(.medium))
                                .lineLimit(1).minimumScaleFactor(0.75)
                                .frame(height: 26, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 430, alignment: .topLeading)
        .padding(12)
        .playerHubSurface(.panel, radius: 16)
        .accessibilityElement(children: .combine)
    }
}
