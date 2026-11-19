import DeskPuffCore
import SwiftUI
import Combine

enum InventoryTheme {
    static let backgroundTop = Color(red: 0.105, green: 0.075, blue: 0.15)
    static let backgroundBottom = Color(red: 0.035, green: 0.03, blue: 0.065)
    static let panelTop = Color(red: 0.15, green: 0.11, blue: 0.22)
    static let gridBottom = Color(red: 0.045, green: 0.04, blue: 0.075)
    static let outline = Color(red: 0.78, green: 0.70, blue: 0.92).opacity(0.24)
    static let divider = Color.white.opacity(0.12)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color(red: 0.81, green: 0.77, blue: 0.88).opacity(0.76)
    static let accent = Color(red: 0.72, green: 0.52, blue: 0.98)
    static let accentBright = Color(red: 0.88, green: 0.75, blue: 1.0)
    static let accentDeep = Color(red: 0.43, green: 0.28, blue: 0.70)
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.53)
    static let cardEdge = LinearGradient(colors: [accentBright.opacity(0.38), accent.opacity(0.17), Color.white.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

private struct InventoryGridDrag {
    enum Mode: Equatable { case move, rotate }
    let id: UUID
    let mode: Mode
    var column: Int
    var row: Int
    var translation: CGSize
    var quarterTurns: Int
    var combinationTarget: UUID?
}

@MainActor private final class InventoryWindowInteraction: ObservableObject {
    @Published var gridDrag: InventoryGridDrag?
    @Published var bagImage: NSImage?
    @Published var hoveredItemID: UUID?
    @Published var inspectedItemID: UUID?
    @Published var hoverLocation = CGPoint.zero
    @Published var showingBagAppearancePicker = false
    @Published var showingCrafting = false
    @Published var showingCollection = false
}

@MainActor struct InventoryWindowView: View {
    @ObservedObject var store: InventoryStore
    let onDeploy: (InventoryItem) -> Void
    let recoveryBagShown: Bool
    let onToggleRecoveryBag: () -> Void
    @StateObject private var interaction = InventoryWindowInteraction()
    private var gridDrag: InventoryGridDrag? { interaction.gridDrag }

    private let cell: CGFloat = 54
    private let gap: CGFloat = 5
    private let inset: CGFloat = 8

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).scaledToFit()
                        .frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7))
                        .shadow(color: InventoryTheme.accent.opacity(0.24), radius: 8, y: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DeskPuff").font(.system(size: 14, weight: .bold, design: .rounded))
                        Text(tr("赛博烟民")).font(.system(size: 11, weight: .medium)).foregroundStyle(InventoryTheme.secondaryText)
                    }
                    Spacer()
                    Text(tr("背包")).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(InventoryTheme.accentBright).padding(.horizontal, 10).padding(.vertical, 6)
                        .playerHubSurface(.item, in: Capsule())
                }
                ZStack {
                    if let image = interaction.bagImage {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .padding(.horizontal, 24).padding(.vertical, 13)
                            .shadow(color: .black.opacity(0.50), radius: 10, y: 7)
                    }
                    VStack {
                        HStack {
                            Label(tr("当前外观"), systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(InventoryTheme.accentBright)
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .playerHubSurface(.item, in: Capsule())
                            Spacer()
                        }
                        Spacer()
                        HStack { Spacer(); Text("\(store.currentCapacity.columns) × \(store.currentCapacity.rows)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(InventoryTheme.secondaryText).padding(.horizontal, 8).padding(.vertical, 5)
                            .playerHubSurface(.inset, in: Capsule()) }
                    }.padding(11)
                }
                .frame(maxWidth: .infinity).frame(height: 220)
                .playerHubSurface(.display, radius: 19)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .shadow(color: .black.opacity(0.20), radius: 11, y: 5)
                .accessibilityLabel(tr(store.currentCapacity.name))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tr(store.currentCapacity.name)).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(store.layout.occupiedCells)").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                            Text(tr("/ {{0}} 格", store.layout.columns * store.layout.rows)).font(.system(size: 10, weight: .medium))
                        }.foregroundStyle(InventoryTheme.gold)
                    }
                    Text(tr("已用容量 · 当前尺寸专属外观"))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(InventoryTheme.secondaryText)
                    InventoryCapacityTrack(value: Double(store.layout.occupiedCells),
                                           total: Double(max(1, store.layout.columns * store.layout.rows)))
                }
                Rectangle().fill(InventoryTheme.divider).frame(height: 0.5).padding(.vertical, 2)
                HStack(spacing: 9) {
                    Button(action: onToggleRecoveryBag) {
                        Label(tr(recoveryBagShown ? "隐藏背包" : "显示背包"),
                              systemImage: recoveryBagShown ? "eye.slash" : "eye")
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .contentShape(Rectangle())
                    }.buttonStyle(PlayerHubButtonStyle(prominent: true))
                    Button { interaction.showingBagAppearancePicker = true } label: {
                        Label(tr("更换背包外观"), systemImage: "backpack")
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlayerHubButtonStyle())
                    .frame(width: 134)
                }
                let carriedEffects = InventoryToolEffect.allCases.filter { store.carriedToolCount(for: $0) > 0 }
                if !carriedEffects.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold)).foregroundStyle(InventoryTheme.accentBright)
                            Text(tr("随身增益")).font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text(tr("已生效")).font(.system(size: 10, weight: .medium)).foregroundStyle(InventoryTheme.secondaryText)
                        }
                        ForEach(carriedEffects, id: \.self) { effect in
                            HStack(spacing: 7) {
                                Image(systemName: effect.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(InventoryTheme.accentBright)
                                    .frame(width: 14)
                                Text(tr(effect.benefit)).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 2)
                                Text("×\(store.carriedToolCount(for: effect))").font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                                    .foregroundStyle(InventoryTheme.gold)
                            }.foregroundStyle(InventoryTheme.secondaryText)
                        }
                    }
                    .padding(10)
                    .playerHubSurface(.panel, radius: 13)
                }
            }
            .frame(width: 285, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.3x3.fill").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(InventoryTheme.accentBright)
                        .frame(width: 32, height: 32)
                        .playerHubSurface(.item, radius: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("随身物件")).font(.system(size: 16, weight: .semibold))
                        Text(tr("拖动整理 · 同类拖到一起可合并"))
                            .font(.system(size: 10)).foregroundStyle(InventoryTheme.secondaryText)
                    }
                    Spacer()
                    Button { interaction.showingCrafting = true } label: {
                        Label(tr("合成工坊"), systemImage: "sparkles")
                    }.buttonStyle(PlayerHubButtonStyle(prominent: true))
                    Button { interaction.showingCollection = true } label: {
                        Label(tr("合成图鉴"), systemImage: "books.vertical")
                    }.buttonStyle(PlayerHubButtonStyle())
                    Text("\(store.layout.columns) × \(store.layout.rows)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(InventoryTheme.secondaryText).padding(.horizontal, 10).padding(.vertical, 7)
                        .playerHubSurface(.inset, in: Capsule())
                }
                ScrollView([.horizontal, .vertical]) {
                    grid
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(spacing: 10) {
                    Label(tr("用桌面背包收灰，在回收页卖钱"), systemImage: "arrow.3.trianglepath")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(InventoryTheme.accentBright)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Label(tr("双击放置"), systemImage: "cursorarrow.click.2")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(InventoryTheme.secondaryText)
                    Rectangle().fill(InventoryTheme.divider).frame(width: 1, height: 12)
                    Label(tr("右键管理"), systemImage: "ellipsis.circle")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(InventoryTheme.secondaryText)
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { store.autoOrganize() } } label: {
                        Label(tr("自动整理"), systemImage: "rectangle.3.group")
                    }.buttonStyle(InventorySecondaryButtonStyle())
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(InventoryTheme.primaryText)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.layout)
        .coordinateSpace(name: "inventoryPanel")
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if gridDrag == nil, let id = interaction.inspectedItemID, id == interaction.hoveredItemID,
                   let item = store.item(id) {
                    let cursor = interaction.hoverLocation
                    let preferredLeft = cursor.x + 228 <= geometry.size.width ? cursor.x + 14 : cursor.x - 226
                    let left = min(max(8, preferredLeft), max(8, geometry.size.width - 220))
                    let top = cursor.y + 118 <= geometry.size.height ? cursor.y + 16 : max(8, cursor.y - 108)
                    itemDescription(item).offset(x: left, y: top)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .task(id: interaction.hoveredItemID) {
            interaction.inspectedItemID = nil
            guard let id = interaction.hoveredItemID else { return }
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            interaction.inspectedItemID = id
        }
        .task(id: store.currentBagAsset) { interaction.bagImage = Self.loadBagImage(asset: store.currentBagAsset) }
        .onAppear { store.settleIncome() }
        .sheet(isPresented: $interaction.showingBagAppearancePicker) { bagAppearancePicker }
        .sheet(isPresented: $interaction.showingCrafting) { RecoveryCraftingView(store: store) }
        .sheet(isPresented: $interaction.showingCollection) {
            ScrollView {
                RecoveryCollectionView(store: store)
                    .padding(22).frame(maxWidth: 980, alignment: .leading).frame(maxWidth: .infinity)
            }
            .frame(width: 760, height: 600)
            .foregroundStyle(InventoryTheme.primaryText)
            .background {
                LinearGradient(colors: [InventoryTheme.backgroundTop, InventoryTheme.backgroundBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .environment(\.colorScheme, .dark)
        }
    }

    private var bagAppearancePicker: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("选择背包外观")).font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(tr("适用于当前的{{0}} · 已拥有外观", tr(store.currentCapacity.name)))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { interaction.showingBagAppearancePicker = false } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28).background(Color.primary.opacity(0.06), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel(tr("关闭"))
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(store.bagStylesForCurrentCapacity) { style in bagStyleOption(style) }
                }
            }
        }
        .padding(22).frame(width: 590, height: 360)
        .foregroundStyle(InventoryTheme.primaryText)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(LinearGradient(colors: [InventoryTheme.backgroundTop, InventoryTheme.backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .environment(\.colorScheme, .dark)
    }

    private func bagStyleOption(_ style: InventoryBagStyle) -> some View {
        let selected = store.currentBagStyleID == style.id
        return Button {
            store.setBagStyle(style.id)
            interaction.showingBagAppearancePicker = false
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if let image = Self.loadBagImage(asset: style.asset) {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .padding(7)
                            .shadow(color: .black.opacity(0.44), radius: 6, y: 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .playerHubSurface(.display, radius: 10)
                HStack(spacing: 6) {
                    Text(tr(style.name)).font(.system(size: 11, weight: selected ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(InventoryTheme.gold) }
                }
            }
            .padding(10).frame(maxWidth: .infinity, minHeight: 145)
            .playerHubSurface(selected ? .item : .panel, radius: 14)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.plain).accessibilityLabel(tr(style.name))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var grid: some View {
        let width = CGFloat(store.layout.columns) * cell + CGFloat(store.layout.columns - 1) * gap
        let height = CGFloat(store.layout.rows) * cell + CGFloat(store.layout.rows - 1) * gap
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for column in 0..<store.layout.columns {
                        for row in 0..<store.layout.rows {
                            let rect = cellRect(column: column, row: row)
                            let path = Path(roundedRect: rect, cornerRadius: 7)
                            let top = CGPoint(x: rect.midX, y: rect.minY)
                            let bottom = CGPoint(x: rect.midX, y: rect.maxY)
                            context.fill(path, with: .linearGradient(
                                Gradient(stops: [.init(color: .white.opacity(0.085), location: 0),
                                                 .init(color: InventoryTheme.accent.opacity(0.024), location: 0.40),
                                                 .init(color: .clear, location: 1)]),
                                startPoint: top, endPoint: bottom))
                            context.stroke(path, with: .linearGradient(
                                Gradient(colors: [InventoryTheme.accentBright.opacity(0.31), InventoryTheme.accent.opacity(0.12)]),
                                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)), lineWidth: 0.75)
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                ForEach(store.layout.items.filter { $0.location == .stored }) { item in
                    inventoryItem(item)
                        .frame(width: tileWidth(item), height: tileHeight(item))
                        .position(x: inset + CGFloat(item.column) * (cell + gap) + tileWidth(item) / 2,
                                  y: inset + CGFloat(item.row) * (cell + gap) + tileHeight(item) / 2)
                        .offset(x: gridDrag?.id == item.id && gridDrag?.mode == .move ? gridDrag?.translation.width ?? 0 : 0,
                                y: gridDrag?.id == item.id && gridDrag?.mode == .move ? gridDrag?.translation.height ?? 0 : 0)
                        .zIndex(gridDrag?.id == item.id ? 2 : 1)
                        .id(item.id)
                        .accessibilityLabel(tr(itemName(item)))
                        .accessibilityHint(itemDescriptionText(item))
                }
                if let drag = gridDrag, drag.mode == .move, drag.combinationTarget == nil, let item = store.item(drag.id) {
                    let valid = store.layout.canPlace(item, at: drag.column, row: drag.row, ignoring: drag.id)
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(valid ? InventoryTheme.accent.opacity(0.13) : Color.red.opacity(0.11))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(valid ? InventoryTheme.accentBright.opacity(0.70) : Color.red.opacity(0.55), lineWidth: 1))
                        .frame(width: tileWidth(item), height: tileHeight(item))
                        .position(x: inset + CGFloat(drag.column) * (cell + gap) + tileWidth(item) / 2,
                                  y: inset + CGFloat(drag.row) * (cell + gap) + tileHeight(item) / 2)
                        .allowsHitTesting(false)
                        .zIndex(0)
                }
            }
            .frame(width: width + inset * 2, height: height + inset * 2, alignment: .topLeading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                shape.fill(.ultraThinMaterial.opacity(0.30))
                    .overlay(shape.fill(LinearGradient(colors: [InventoryTheme.accent.opacity(0.09), .clear],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(shape.strokeBorder(InventoryTheme.cardEdge, lineWidth: 0.75))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .coordinateSpace(name: "inventoryGrid")
            .simultaneousGesture(gridDragGesture)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(width: width + inset * 2, height: height + inset * 2)
    }

    private func inventoryItem(_ item: InventoryItem) -> some View {
        let itemID = item.id
        return itemTile(item)
            .overlay {
                let isDragged = interaction.gridDrag?.id == itemID
                let isHovered = interaction.hoveredItemID == itemID
                let isCombinationTarget = interaction.gridDrag?.combinationTarget == itemID
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isCombinationTarget ? InventoryTheme.gold : isDragged ? InventoryTheme.accentBright.opacity(0.88) : (isHovered ? InventoryTheme.accentBright.opacity(0.48) : .clear), lineWidth: isDragged ? 1.2 : 0.8)
                    .shadow(color: InventoryTheme.accent.opacity(isDragged ? 0.22 : 0.10), radius: isDragged ? 7 : 4)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                if let drag = gridDrag, drag.id == itemID, let targetID = drag.combinationTarget,
                   let target = store.item(targetID) {
                    Text(tr("合并 {{0}} 个", store.layout.recoveryMergeCount(from: item, into: target)))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(InventoryTheme.gold)
                        .padding(.horizontal, 4).padding(.vertical, 3)
                        .playerHubSurface(.inset, in: Capsule())
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.12), value: interaction.hoveredItemID == itemID)
            .onTapGesture(count: 2) {
                guard item.kind.canDeploy, let currentItem = store.item(itemID) else { return }
                onDeploy(currentItem)
            }
            .onContinuousHover(coordinateSpace: .named("inventoryPanel")) { phase in
                switch phase {
                case .active(let point):
                    interaction.hoverLocation = point
                    if interaction.hoveredItemID != itemID { interaction.hoveredItemID = itemID }
                case .ended:
                    if interaction.hoveredItemID == itemID { interaction.hoveredItemID = nil }
                }
            }
            .contextMenu {
                if item.kind.canDeploy || item.footprint.width != item.footprint.height {
                    Button(tr("旋转"), systemImage: "rotate.right") { withAnimation { store.rotate(itemID) } }
                }
                if item.kind.canDeploy {
                    Button(tr("放到桌面"), systemImage: "arrow.up.right.square") {
                        if let currentItem = store.item(itemID) { onDeploy(currentItem) }
                    }
                    Divider()
                }
                Button(role: .destructive) { store.discard(itemID) } label: {
                    Label(tr("丢弃"), systemImage: "trash")
                }
            }
    }

    private var gridDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("inventoryGrid"))
            .onChanged { value in
                let item: InventoryItem
                if let activeID = gridDrag?.id, let activeItem = store.item(activeID), activeItem.location == .stored {
                    item = activeItem
                } else if let hitItem = storedItem(at: value.startLocation) {
                    item = hitItem
                } else {
                    return
                }

                let itemOrigin = CGPoint(x: inset + CGFloat(item.column) * (cell + gap),
                                         y: inset + CGFloat(item.row) * (cell + gap))
                let itemStart = CGPoint(x: value.startLocation.x - itemOrigin.x,
                                        y: value.startLocation.y - itemOrigin.y)
                let mode: InventoryGridDrag.Mode
                if gridDrag?.id == item.id { mode = gridDrag?.mode ?? .move }
                else {
                    let canRotate = item.footprint.width != item.footprint.height || item.kind.canDeploy
                    mode = canRotate && itemStart.x >= tileWidth(item) - 36 && itemStart.y <= 36 ? .rotate : .move
                }
                let pitch = cell + gap
                let originX = inset + CGFloat(item.column) * pitch + value.translation.width
                let originY = inset + CGFloat(item.row) * pitch + value.translation.height
                let column = Int(((originX - inset) / pitch).rounded())
                let row = Int(((originY - inset) / pitch).rounded())
                let turns = mode == .rotate ? rotationTurns(for: value, item: item, start: itemStart) : 0
                interaction.gridDrag = InventoryGridDrag(id: item.id, mode: mode, column: column, row: row,
                                                         translation: value.translation, quarterTurns: turns,
                                                         combinationTarget: mode == .move ? combinationTarget(for: item, at: value.location) : nil)
            }
            .onEnded { value in
                guard let drag = gridDrag else { return }
                if drag.mode == .rotate {
                    if drag.quarterTurns != 0 { withAnimation { store.rotate(drag.id, by: drag.quarterTurns) } }
                } else if let item = store.item(drag.id), let target = combinationTarget(for: item, at: value.location) {
                    store.mergeRecovery(from: drag.id, into: target)
                } else {
                    store.move(drag.id, column: drag.column, row: drag.row)
                }
                interaction.gridDrag = nil
            }
    }

    private func combinationTarget(for source: InventoryItem, at point: CGPoint) -> UUID? {
        guard let target = storedItem(at: point),
              store.layout.recoveryMergeCount(from: source, into: target) > 0 else { return nil }
        return target.id
    }

    private func storedItem(at point: CGPoint) -> InventoryItem? {
        let pitch = cell + gap
        return store.layout.items.reversed().first { item in
            guard item.location == .stored else { return false }
            let originX = inset + CGFloat(item.column) * pitch
            let originY = inset + CGFloat(item.row) * pitch
            return CGRect(x: originX, y: originY, width: tileWidth(item), height: tileHeight(item)).contains(point)
        }
    }

    private func rotationTurns(for value: DragGesture.Value, item: InventoryItem, start: CGPoint) -> Int {
        let center = CGPoint(x: tileWidth(item) / 2, y: tileHeight(item) / 2)
        let end = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)
        var delta = endAngle - startAngle
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        return abs(delta) < .pi / 4 ? 0 : 1
    }

    @ViewBuilder private func itemTile(_ item: InventoryItem) -> some View {
        if let material = item.kind.recoveryMaterial {
            ZStack(alignment: .bottomTrailing) {
                GeometryReader { geometry in
                    RecoveryIngredientArt(ingredient: item.kind == .emptyPack || item.kind == .premiumEmptyPack
                                          ? .pack(styleID: item.styleID) : .material(material))
                        .padding(5)
                        .frame(width: geometry.size.width, height: geometry.size.height - 9)
                }
                Text("\(item.recoveryCount)/\(material.stackLimit)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(InventoryTheme.gold)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .playerHubSurface(.inset, in: Capsule())
                    .padding(3)
            }
            .frame(width: tileWidth(item), height: tileHeight(item))
            .contentShape(Rectangle())
            .playerHubSurface(.item, radius: 10)
        } else if item.kind == .tool {
            toolItemTile(item, width: tileWidth(item), height: tileHeight(item))
        } else {
            standardItemTile(item)
        }
    }

    private func itemDescription(_ item: InventoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr(itemName(item)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(InventoryTheme.primaryText)
            Text(itemDescriptionText(item))
                .font(.system(size: 11))
                .foregroundStyle(InventoryTheme.secondaryText)
            Text(tr("占用格子 {{0}}×{{1}}", item.footprint.width, item.footprint.height))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(InventoryTheme.accentBright)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 188, alignment: .leading)
        .padding(12)
        .playerHubSurface(.item, radius: 12)
        .shadow(color: .black.opacity(0.52), radius: 12, y: 5)
    }

    private func itemDescriptionText(_ item: InventoryItem) -> String {
        switch item.kind {
        case .cigaretteBox:
            item.isEmptyPack ? tr("已用完 · 可在合成工坊直接用于合成。")
                            : tr("剩余烟支 {{0}} · 可整盒投入合成", stockLabel(item))
        case .lighter: tr("剩余燃料 {{0}} · 双击放到桌面", lighterFuelLabel(item))
        case .ashtray: tr("接住落下的烟灰，拖动边缘可倾倒。")
        case .tool:
            store.economyRules?.products.first { $0.id == item.styleID }?.passiveEffect.map { tr($0.benefit) }
                ?? tr("放入背包即生效 · 同档限持一件")
        case .fineAsh, .ashClump:
            if item.isLegacyAshStack {
                tr("旧批次 · 按旧批次单价出售。")
            } else {
                tr("可在合成工坊使用，也可直接出售。")
            }
        case .cigaretteButt, .emptyPack, .premiumEmptyPack: tr("可在合成工坊使用，也可直接出售。")
        case .emberStone, .ashSeal, .gildedRelic, .cloudMarble, .fortuneCoin, .smokeDuck, .goldenCigarette, .ashDumpling,
             .phoneBooth, .paperclipFrog, .deskFan, .marbleRun,
             .redFoilMisprint, .celadonSmokeMark, .filterFossil, .redBlueOverprint,
             .goldSeal, .fortuneFold, .cloudGlass, .paperCicada, .ashSpoon, .starAsh,
             .lotusFoil, .redTowerTicket, .doubleJoySeal, .riverCloudMedallion,
             .peonyAshPrint, .silverLining, .ashLantern, .emberStamp, .boxFoldPavilion, .moonInCellophane,
             .doubleFoilFold, .celadonAshPearl, .ruyiAshRibbon, .goldenCloudStamp, .nanjingPaperWhistle,
             .furongCinderButton, .doubleJoyCigaretteSleeve, .liqunAshSleeve, .lotusEmberPetal,
             .redTowerAshCoin, .ashCigaretteRing, .zhonghuaSmokeFilm, .yuxiFilterCharm,
             .nanjingGrayLeaf, .furongEmberClip, .doubleJoyAshBadge, .crossBrandLantern,
             .oldShopLedgerSeal, .lotusGoldenCompass, .whiteRedFoldedStage:
            tr("工坊制作的收藏品，可在回收页出售。")
        case .mysteryJunk: tr("一坨灰 · 成分不明，重量属实。")
        }
    }

    private func standardItemTile(_ item: InventoryItem) -> some View {
        let width = tileWidth(item)
        let height = tileHeight(item)
        let artworkWidth = max(1, width - 12)
        let artworkHeight = max(1, height - 12)
        let aspect = previewAspectRatio(for: item)
        let isQuarterTurned = item.isRotated
        let sourceWidth: CGFloat
        let sourceHeight: CGFloat
        if isQuarterTurned {
            sourceHeight = min(artworkWidth, artworkHeight / aspect)
            sourceWidth = sourceHeight * aspect
        } else {
            sourceWidth = min(artworkWidth, artworkHeight * aspect)
            sourceHeight = sourceWidth / aspect
        }
        return ZStack(alignment: .topLeading) {
            ProductStylePreview(kind: previewKind(item.kind), styleID: item.styleID, revision: 0)
                .frame(width: sourceWidth, height: sourceHeight)
                .rotationEffect(.degrees(Double(item.rotationQuarterTurns) * 90))
                .position(x: width / 2, y: height / 2)
                .allowsHitTesting(false)
            if item.kind == .cigaretteBox {
                Text(stockLabel(item))
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .playerHubSurface(.inset, in: Capsule())
                    .padding(5)
                    .allowsHitTesting(false)
            } else if item.kind == .lighter {
                Text(lighterFuelLabel(item))
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .playerHubSurface(.inset, in: Capsule())
                    .padding(5).allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .playerHubSurface(.item, radius: 10)
        .shadow(color: .black.opacity(0.24), radius: 5, x: 0, y: 2)
    }

    private func toolItemTile(_ item: InventoryItem, width: CGFloat, height: CGFloat) -> some View {
        let product = store.economyRules?.products.first { $0.kind == .tool && $0.id == item.styleID }
        return ZStack {
            VStack(spacing: 6) {
                if let product, let artwork = storeToolArtwork(productID: product.id) {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(width - 12, 48), height: min(height * 0.34, 34))
                } else {
                    Image(systemName: product?.passiveEffect?.symbol ?? "sparkles")
                        .font(.system(size: 22, weight: .medium)).foregroundStyle(InventoryTheme.accentBright)
                }
                Text(tr(product?.name ?? "随身道具"))
                    .font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2)
                Text(tr("携带生效"))
                    .font(.system(size: 7, weight: .semibold)).foregroundStyle(InventoryTheme.gold)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .playerHubSurface(.inset, in: Capsule())
            }.padding(8)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .playerHubSurface(.item, radius: 10)
        .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 2)
    }

    private func previewAspectRatio(for item: InventoryItem) -> CGFloat {
        ProductStylePreviewHost.inventoryAspectRatio(kind: previewKind(item.kind), styleID: item.styleID)
    }

    private func cellRect(column: Int, row: Int) -> CGRect {
        CGRect(x: inset + CGFloat(column) * (cell + gap), y: inset + CGFloat(row) * (cell + gap), width: cell, height: cell)
    }
    private func tileWidth(_ item: InventoryItem) -> CGFloat { CGFloat(item.footprint.width) * cell + CGFloat(item.footprint.width - 1) * gap }
    private func tileHeight(_ item: InventoryItem) -> CGFloat { CGFloat(item.footprint.height) * cell + CGFloat(item.footprint.height - 1) * gap }
    private func previewKind(_ kind: InventoryKind) -> ProductStyleKind {
        switch kind {
        case .cigaretteBox: .boxes
        case .lighter: .lighters
        default: .ashtrays
        }
    }
    private static let bagImageCache = NSCache<NSString, NSImage>()
    static func loadBagImage(asset: String) -> NSImage? {
        if let cached = bagImageCache.object(forKey: asset as NSString) { return cached }
        guard let url = Bundle.module.url(forResource: asset, withExtension: "png", subdirectory: "Resources/InventoryBags"),
              let image = NSImage(contentsOf: url) else { return nil }
        bagImageCache.setObject(image, forKey: asset as NSString)
        return image
    }
    private func itemName(_ item: InventoryItem) -> String {
        let baseName: String
        switch item.kind {
        case .cigaretteBox: baseName = StylePackageRegistry.shared.cigaretteBoxes.first { $0.id == item.styleID }?.name ?? item.kind.title
        case .lighter: baseName = StylePackageRegistry.shared.lighters.first { $0.id == item.styleID }?.name ?? item.kind.title
        case .ashtray: baseName = StylePackageRegistry.shared.ashtrays.first { $0.id == item.styleID }?.name ?? item.kind.title
        case .tool: baseName = store.economyRules?.products.first { $0.id == item.styleID }?.name ?? item.kind.title
        case .emptyPack, .premiumEmptyPack:
            let name = RecoveryIngredient.pack(styleID: item.styleID).title
            baseName = tr("{{0}} · 回收烟盒", name)
        default:
            baseName = tr("{{0}} · {{1}} / {{2}}", tr(item.kind.title), item.recoveryCount, item.kind.recoveryMaterial?.stackLimit ?? 0)
        }
        guard item.styleID.hasPrefix("brand-trace:") else { return baseName }
        let brandIDs = item.styleID.dropFirst("brand-trace:".count).split(separator: "+").map(String.init)
        let brandNames = brandIDs.compactMap { id in StylePackageRegistry.shared.cigaretteBoxes.first { $0.id == id }?.name }
        guard !brandNames.isEmpty else { return baseName }
        return tr("{{0}}烟盒留下的烟迹 · {{1}}", brandNames.map { tr($0) }.joined(separator: " × "), baseName)
    }
    private func stockLabel(_ item: InventoryItem) -> String {
        guard let data = item.state else { return tr("20 支") }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let count = object["remaining"] as? Int, (0...20).contains(count) else { return tr("数量未知") }
        return tr("{{0}} 支", count)
    }
    private func lighterFuelLabel(_ item: InventoryItem) -> String {
        guard let data = item.state else { return "90%" }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fuel = object["fuel"] as? Double, fuel.isFinite else { return "?%" }
        return "\(Int((min(1, max(0, fuel)) * 100).rounded()))%"
    }
}

private struct InventoryCapacityTrack: View {
    let value: Double
    let total: Double
    private var fraction: Double { min(1, max(0, value / max(1, total))) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.28))
                Capsule()
                    .fill(LinearGradient(colors: [InventoryTheme.accentBright, InventoryTheme.accent, InventoryTheme.accentDeep],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: max(4, geometry.size.width * fraction))
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
        }
        .frame(height: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("背包已用容量"))
        .accessibilityValue("\(Int(fraction * 100))%")
    }
}

private struct InventoryPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.97))
            .padding(.horizontal, 15).padding(.vertical, 9)
            .playerHubSurface(.active, in: shape)
            .overlay(shape.fill(.black.opacity(configuration.isPressed ? 0.12 : 0)).allowsHitTesting(false))
            .shadow(color: InventoryTheme.accent.opacity(configuration.isPressed ? 0.08 : 0.14), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct InventorySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(InventoryTheme.primaryText)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .playerHubSurface(.panel, in: shape)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
