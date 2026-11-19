import SwiftUI
import DeskPuffCore

@MainActor struct InventoryConfigurationView: View {
    @ObservedObject private var store = InventoryStore.shared
    var onRestoreDeveloperSave: () -> Void = {}
    private let capacityColumns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(tr("背包")).font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(tr("{{0}}  ·  {{1}} 格", tr(store.currentCapacity.name), store.currentCapacity.columns * store.currentCapacity.rows))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    HStack(spacing: 11) {
                        Label("\(store.layout.occupiedCells) / \(store.currentCapacity.columns * store.currentCapacity.rows)", systemImage: "square.grid.3x3")
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { store.autoOrganize() }
                        } label: {
                            Label(tr("自动整理"), systemImage: "rectangle.3.group")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(DeskPuffPalette.accent)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let image = bagImage(store.currentBagAsset) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: 170, height: 126)
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                        .accessibilityLabel(tr("{{0}}外观预览", tr(store.currentCapacity.name)))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(tr("容量规格"), trailing: tr("开发测试 · 可直接切换"))
                LazyVGrid(columns: capacityColumns, alignment: .leading, spacing: 9) {
                    ForEach(0..<store.capacityOptions.count, id: \.self) { index in
                        let option = store.capacityOptions[index]
                        let selected = store.capacityStage == option.stage
                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                                store.setCapacityStageForTesting(option.stage)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13)).foregroundStyle(selected ? DeskPuffPalette.accent : Color.secondary.opacity(0.6))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tr(option.name)).font(.system(size: 11, weight: .semibold))
                                    Text(tr("{{0}} × {{1}}  ·  {{2}} 格", option.columns, option.rows, option.columns * option.rows))
                                        .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 11).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected ? DeskPuffPalette.selectedControl : .primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(selected ? DeskPuffPalette.accent.opacity(0.4) : DeskPuffPalette.outline, lineWidth: selected ? 0.9 : 0.55))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(tr("{{0}} · 外观", tr(store.currentCapacity.name)), trailing: tr("仅显示当前容量的 3 款适配样式"))
                LazyVGrid(columns: capacityColumns, alignment: .leading, spacing: 9) {
                    ForEach(InventoryBagStyle.styles(for: store.currentBagCategory)) { style in
                        bagStyleCard(style)
                    }
                }
            }

            inventoryTestRestoreSection

            if let message = store.message {
                Label(message, systemImage: "info.circle")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.capacityStage)
    }

    private var inventoryTestRestoreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(tr("背包测试还原"), trailing: tr("切换容量或外观时自动暂存"))
            HStack(spacing: 10) {
                Image(systemName: store.hasInventoryTestSnapshot ? "checkmark.icloud.fill" : "shippingbox")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(DeskPuffPalette.accent)
                    .frame(width: 36, height: 36).background(DeskPuffPalette.selection, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.hasInventoryTestSnapshot ? tr("测试前背包已暂存") : tr("尚未开始背包测试"))
                        .font(.system(size: 11, weight: .semibold))
                    Text(tr("还原背包物品、容量与外观，不影响钱包和段位。"))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(tr("还原测试前背包")) { _ = store.restoreInventoryTestSnapshot() }
                    .buttonStyle(PlayerHubButtonStyle(prominent: true))
                    .disabled(!store.hasInventoryTestSnapshot)
            }
            .padding(12)
            .background(DeskPuffPalette.stage, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func sectionHeading(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    private func bagStyleCard(_ style: InventoryBagStyle) -> some View {
        let selected = store.currentBagStyleID == style.id
        return Button { store.setBagStyleForTesting(style.id) } label: {
            HStack(spacing: 12) {
                if let image = bagImage(style.asset) {
                    Image(nsImage: image).resizable().interpolation(.high).antialiased(true).scaledToFit()
                        .frame(width: 112, height: 76)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr(style.name)).font(.system(size: 11, weight: .medium))
                    if selected { Label(tr("当前外观"), systemImage: "checkmark").font(.system(size: 9)).foregroundStyle(DeskPuffPalette.accent) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? DeskPuffPalette.selectedControl : .primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? DeskPuffPalette.accent.opacity(0.4) : DeskPuffPalette.outline, lineWidth: selected ? 0.9 : 0.55))
        }
        .buttonStyle(.plain)
    }

    private func bagImage(_ asset: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: asset, withExtension: "png", subdirectory: "Resources/InventoryBags") else { return nil }
        return NSImage(contentsOf: url)
    }

}
