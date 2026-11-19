import AppKit
import SwiftUI
import Combine
import DeskPuffCore

@MainActor private final class RecoveryCraftingSelection: ObservableObject {
    @Published var materials: [RecoveryIngredient: Int] = [:]
    @Published var reveal: CraftReveal?
}

private struct CraftReveal: Identifiable {
    let id = UUID()
    let product: RecoveryMaterial
    let count: Int
    let isNewDiscovery: Bool
    let ingredients: [RecoveryIngredient]
}

@MainActor struct RecoveryCraftingView: View {
    @ObservedObject var store: InventoryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var selection = RecoveryCraftingSelection()

    private let columns = [GridItem(.adaptive(minimum: 205), spacing: 9)]
    private var stock: [RecoveryIngredient: Int] { store.layout.craftingStock }
    private var outputCount: Int { selection.materials.values.min() ?? 0 }
    private var excessCount: Int { selection.materials.values.reduce(0) { $0 + $1 - outputCount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text(tr("每种材料一份就能试做。烟盒按款式区分，整盒投入时剩余烟支会一起消耗。没配上的组合可回收为废品。"))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 9) {
                    ForEach(stock.keys.sorted { $0.id < $1.id }) { ingredient in
                        materialCard(ingredient, available: stock[ingredient, default: 0])
                    }
                }
                .padding(.vertical, 2)
                if stock.isEmpty {
                    Text(tr("背包里还没有可投入的材料。"))
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label(tr("本次产出 {{0}} 件", outputCount), systemImage: "basket")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(InventoryTheme.accentBright)
                    if outputCount > 0 {
                        let predicted = RecoveryRecipe.matching(Set(selection.materials.keys))?.product ?? .mysteryJunk
                        Text(tr("预计得到：{{0}}", predicted.title))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if excessCount > 0 {
                        Text(tr("会丢弃多投的 {{0}} 件材料", excessCount))
                            .font(.caption)
                            .foregroundStyle(InventoryTheme.gold)
                    }
                }
                Spacer()
                Button {
                    mixAndReveal()
                } label: {
                    Label(tr("投入材料，揭晓成果"), systemImage: "sparkles")
                }
                .buttonStyle(PlayerHubButtonStyle(prominent: outputCount > 0))
                .disabled(outputCount == 0)
            }
            if let message = store.message {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(InventoryTheme.accentBright)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(22)
        .frame(width: 700, height: 620)
        .background {
            LinearGradient(colors: [InventoryTheme.backgroundTop, InventoryTheme.backgroundBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { store.setMessage(nil) }
        .disabled(selection.reveal != nil)
        .accessibilityHidden(selection.reveal != nil)
        .overlay {
            if let reveal = selection.reveal {
                CraftingRevealOverlay(reveal: reveal) { selection.reveal = nil }
                    .transition(.opacity)
            }
        }
    }

    private func mixAndReveal() {
        let submitted = selection.materials
        let predictedProduct = RecoveryRecipe.matching(Set(submitted.keys))?.product ?? .mysteryJunk
        let isNewDiscovery = !store.hasDiscoveredRecoveryItem(predictedProduct)
        guard case .crafted(let product, let count) = store.mixRecoveryMaterials(submitted) else { return }
        selection.materials.removeAll()
        withAnimation(.easeInOut(duration: 0.2)) {
            selection.reveal = CraftReveal(product: product, count: count, isNewDiscovery: isNewDiscovery,
                                           ingredients: submitted.keys.sorted { $0.id < $1.id })
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(InventoryTheme.gold)
                .frame(width: 38, height: 38)
                .playerHubSurface(.item, radius: 11)
            Text(tr("自由合成工坊")).font(.title3.weight(.semibold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(tr("关闭"))
        }
    }

    private func materialCard(_ ingredient: RecoveryIngredient, available: Int) -> some View {
        let amount = selection.materials[ingredient, default: 0]
        return HStack(spacing: 9) {
            RecoveryIngredientArt(ingredient: ingredient)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(ingredient.title).font(.caption.weight(.semibold)).lineLimit(2)
                Text(tr("拥有 {{0}}", available))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 1)
            Button { change(ingredient, by: -1, maximum: available) } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(amount == 0)
            .accessibilityLabel(tr("减少 {{0}}", ingredient.title))
            Text("\(amount)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(minWidth: 18)
                .accessibilityLabel(tr("已选 {{0}}", amount))
            Button { change(ingredient, by: 1, maximum: available) } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(amount >= available)
            .accessibilityLabel(tr("增加 {{0}}", ingredient.title))
        }
        .padding(9)
        .frame(minHeight: 67)
        .playerHubSurface(amount > 0 ? .item : .panel, radius: 12)
        .opacity(available == 0 ? 0.55 : 1)
    }

    private func change(_ ingredient: RecoveryIngredient, by delta: Int, maximum: Int) {
        let next = min(maximum, max(0, selection.materials[ingredient, default: 0] + delta))
        if next == 0 { selection.materials.removeValue(forKey: ingredient) }
        else { selection.materials[ingredient] = next }
    }
}

@MainActor private final class CraftingRevealState: ObservableObject {
    @Published var materialsSettled = false
    @Published var smokeRising = false
    @Published var resultVisible = false
}

@MainActor private struct CraftingRevealOverlay: View {
    let reveal: CraftReveal
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var state = CraftingRevealState()

    private static let workshop = loadArt("workshop", extension: "jpg")
    private static let smoke = loadArt("workshopSmoke", extension: "png")
    private let sceneWidth: CGFloat = 496
    private let sceneHeight: CGFloat = 282

    private var estimatedValue: Int {
        reveal.product.priceCents(hour: RecoveryMaterial.marketHour(at: Date())) * reveal.count
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.73).ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 14) {
                Text(tr(state.resultVisible && reveal.isNewDiscovery ? "首次发现" : "工坊开箱"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(InventoryTheme.gold)
                scene
                VStack(spacing: 5) {
                    Text(state.resultVisible ? reveal.product.title : tr("工作台运转中…"))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    if state.resultVisible {
                        Text(tr("收获 {{0}} 件 · 当前估价 {{1}}", reveal.count, recoveryMoney(estimatedValue)))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(InventoryTheme.gold)
                        Text(reveal.product.workshopDescription)
                            .font(.caption).foregroundStyle(InventoryTheme.secondaryText)
                    }
                }
                .frame(height: 68)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                Button(tr(state.resultVisible ? "完成" : "跳过动画")) {
                    if state.resultVisible { onClose() }
                    else { state.resultVisible = true }
                }
                .buttonStyle(PlayerHubButtonStyle(prominent: state.resultVisible))
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .foregroundStyle(InventoryTheme.primaryText)
            .playerHubSurface(.panel, radius: 22)
            .shadow(color: .black.opacity(0.55), radius: 28, y: 12)
        }
        .task(id: reveal.id) {
            guard !reduceMotion else {
                state.resultVisible = true
                return
            }
            withAnimation(.easeIn(duration: 0.48)) { state.materialsSettled = true }
            try? await Task.sleep(nanoseconds: 430_000_000)
            guard !Task.isCancelled, !state.resultVisible else { return }
            withAnimation(.easeOut(duration: 0.62)) { state.smokeRising = true }
            try? await Task.sleep(nanoseconds: 530_000_000)
            guard !Task.isCancelled, !state.resultVisible else { return }
            withAnimation(.spring(response: 0.58, dampingFraction: 0.74)) { state.resultVisible = true }
        }
    }

    private var scene: some View {
        ZStack {
            if let workshop = Self.workshop {
                Image(nsImage: workshop)
                    .resizable().scaledToFill()
                    .frame(width: sceneWidth, height: sceneHeight)
                    .scaleEffect(state.smokeRising ? 1.05 : 1)
                    .brightness(state.smokeRising && !state.resultVisible ? 0.10 : 0)
            }
            if !state.resultVisible {
                let materials = Array(reveal.ingredients.prefix(6))
                ForEach(Array(materials.enumerated()), id: \.element.id) { index, ingredient in
                    let x = CGFloat(index) - CGFloat(materials.count - 1) / 2
                    RecoveryIngredientArt(ingredient: ingredient)
                        .frame(width: 58, height: 58)
                        .rotationEffect(.degrees(Double(x) * (state.materialsSettled ? 5 : 16)))
                        .scaleEffect(state.materialsSettled ? 0.52 : 1)
                        .offset(x: x * (state.materialsSettled ? 23 : 70), y: state.materialsSettled ? 62 : -22)
                        .opacity(state.smokeRising ? 0 : 1)
                }
            }
            if state.resultVisible {
                RecoveryMaterialArt(material: reveal.product)
                    .frame(width: 148, height: 148)
                    .shadow(color: .black.opacity(0.7), radius: 13, y: 14)
                    .offset(y: 23)
                    .transition(.scale(scale: 0.64, anchor: .bottom).combined(with: .opacity))
            }
            if state.smokeRising, let smoke = Self.smoke {
                Image(nsImage: smoke)
                    .resizable().scaledToFit()
                    .frame(width: 260, height: 228)
                    .scaleEffect(state.resultVisible ? 1.30 : 0.94)
                    .offset(y: state.resultVisible ? -65 : 3)
                    .opacity(state.resultVisible ? 0 : 0.82)
                    .transition(.scale(scale: 0.35, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: sceneWidth, height: sceneHeight)
        .background(InventoryTheme.backgroundBottom)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    private static func loadArt(_ name: String, extension ext: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources/Recovery") else { return nil }
        return NSImage(contentsOf: url)
    }
}
