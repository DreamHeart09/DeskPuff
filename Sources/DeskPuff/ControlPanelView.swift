import SwiftUI
import DeskPuffCore
import AppKit

enum DeskPuffControlTab: String, CaseIterable, Identifiable {
    case overview = "概览", inventory = "背包", cigarettes = "香烟", styles = "烟盒", lighter = "打火机", ashtray = "烟灰缸", experience = "体验与快捷操作", craftingCollection = "合成图鉴", gameEditor = "游戏修改器"
    var id: String { rawValue }
    var navigationGroup: String {
        switch self {
        case .overview, .experience, .craftingCollection, .gameEditor: tr("工作台")
        case .inventory: tr("物件与配置")
        case .cigarettes, .styles, .ashtray, .lighter: tr("物件与配置")
        }
    }
    var symbol: String {
        switch self { case .overview: "slider.horizontal.3"; case .inventory: "backpack"; case .experience: "sparkles.rectangle.stack"; case .cigarettes: "pencil.and.outline"; case .styles: "shippingbox"; case .ashtray: "circle.hexagongrid"; case .lighter: "flame"; case .craftingCollection: "books.vertical"; case .gameEditor: "gamecontroller" }
    }
}

@MainActor private final class ControlPanelState: ObservableObject {
    @Published var tab: DeskPuffControlTab = .overview
    @Published var smokeAmount: Int
    @Published var ashAmount: Int
    @Published var inhaleSpeed: Double
    @Published var dissipation: SmokeDissipation
    @Published var cloudVariation: Bool
    @Published var smokeBehindWindows: Bool
    @Published var energySaving: Bool
    @Published var extractionMode: CigaretteExtractionMode
    @Published var cigaretteMotionMode: CigaretteMotionMode
    @Published var smokeColor: Color
    @Published var desktopVisible: Bool
    @Published var lighterStatusMessage: String?
    @Published var lidDebugEnabled = false
    @Published var lidDebugProgress = 0.0

    init(smokeAmount: Int, ashAmount: Int, inhaleSpeed: Double, dissipation: SmokeDissipation,
         cloudVariation: Bool, smokeBehindWindows: Bool, energySaving: Bool, desktopVisible: Bool,
         extractionMode: CigaretteExtractionMode, cigaretteMotionMode: CigaretteMotionMode, smokeColor: Color) {
        self.smokeAmount = smokeAmount; self.ashAmount = ashAmount; self.inhaleSpeed = inhaleSpeed
        self.dissipation = dissipation; self.cloudVariation = cloudVariation
        self.smokeBehindWindows = smokeBehindWindows; self.energySaving = energySaving
        self.desktopVisible = desktopVisible
        self.extractionMode = extractionMode; self.cigaretteMotionMode = cigaretteMotionMode; self.smokeColor = smokeColor
    }
}

@MainActor struct ControlPanelView: View {
    @StateObject private var state: ControlPanelState
    @ObservedObject private var inventoryStore = InventoryStore.shared
    @AppStorage("cigaretteBoxStyleV1") private var currentBoxID = CigaretteBoxStyle.default.id
    @AppStorage("ashtrayStyleV1") private var currentAshtrayID = AshtrayStyle.default.id
    @AppStorage("openControlPanelAtLaunch") private var openControlPanelAtLaunch = false
    @AppStorage("openInventoryAtLaunch") private var openInventoryAtLaunch = false
    @AppStorage("openStoreAtLaunch") private var openStoreAtLaunch = false
    @AppStorage("gentleLighterFlameV1") private var continuousFlameBlend = true
    @AppStorage("optimizedLighterFlameV1") private var optimizedFlame = true
    @AppStorage("lighterFuelLevelV1") private var lighterFuelRemaining = 0.9

    let cigaretteManager: AnyView
    let styleManager: AnyView
    let ashtrayManager: AnyView
    let lighterManager: AnyView
    let onSmokeAmount: (Int) -> Void
    let onAshAmount: (Int) -> Void
    let onInhaleSpeed: (Int) -> Void
    let onDissipation: (SmokeDissipation) -> Void
    let onCloudVariation: (Bool) -> Void
    let onSmokeBehind: (Bool) -> Void
    let onEnergySaving: (Bool) -> Void
    let onExtractionMode: (CigaretteExtractionMode) -> Void
    let onCigaretteMotionMode: (CigaretteMotionMode) -> Void
    let onSmokeColor: (Color) -> Void
    let onResetSmokeColor: () -> Void
    let onToggleVisibility: () -> Void
    let onTakeCigarette: () -> Void
    let onToggleLit: () -> Void
    let onClearSmoke: () -> Void
    let onClearAsh: () -> Void
    let onClearCigarettes: () -> Void
    let onDumpAshtray: () -> Void
    let onOptimizedFlame: (Bool) -> Void
    let onContinuousFlameBlend: (Bool) -> Void
    let onBoxLidDebugProgress: (Double?) -> Void
    let onOpenStore: () -> Void
    let onOpenInventory: () -> Void
    let onRestoreDeveloperSave: () -> Void
    let onResetForTesting: () -> Void
    let onResetLighterForTesting: () -> Void

    init(smokeAmount: Int, ashAmount: Int, inhaleSpeed: Double, dissipation: SmokeDissipation,
         cloudVariation: Bool, smokeBehindWindows: Bool, energySaving: Bool, desktopVisible: Bool, extractionMode: CigaretteExtractionMode,
         cigaretteMotionMode: CigaretteMotionMode,
         smokeColor: Color, cigaretteManager: AnyView, styleManager: AnyView, ashtrayManager: AnyView, lighterManager: AnyView,
         onSmokeAmount: @escaping (Int) -> Void, onAshAmount: @escaping (Int) -> Void,
         onInhaleSpeed: @escaping (Int) -> Void, onDissipation: @escaping (SmokeDissipation) -> Void,
         onCloudVariation: @escaping (Bool) -> Void, onSmokeBehind: @escaping (Bool) -> Void,
         onEnergySaving: @escaping (Bool) -> Void, onExtractionMode: @escaping (CigaretteExtractionMode) -> Void,
         onCigaretteMotionMode: @escaping (CigaretteMotionMode) -> Void,
         onSmokeColor: @escaping (Color) -> Void, onResetSmokeColor: @escaping () -> Void,
         onToggleVisibility: @escaping () -> Void, onTakeCigarette: @escaping () -> Void,
         onToggleLit: @escaping () -> Void, onClearSmoke: @escaping () -> Void, onClearAsh: @escaping () -> Void,
         onClearCigarettes: @escaping () -> Void, onDumpAshtray: @escaping () -> Void,
         onOptimizedFlame: @escaping (Bool) -> Void, onContinuousFlameBlend: @escaping (Bool) -> Void,
         onBoxLidDebugProgress: @escaping (Double?) -> Void,
         onOpenStore: @escaping () -> Void, onOpenInventory: @escaping () -> Void,
         onRestoreDeveloperSave: @escaping () -> Void, onResetForTesting: @escaping () -> Void, onResetLighterForTesting: @escaping () -> Void) {
        _state = StateObject(wrappedValue: ControlPanelState(smokeAmount: smokeAmount, ashAmount: ashAmount,
            inhaleSpeed: inhaleSpeed, dissipation: dissipation, cloudVariation: cloudVariation,
            smokeBehindWindows: smokeBehindWindows, energySaving: energySaving, desktopVisible: desktopVisible,
            extractionMode: extractionMode, cigaretteMotionMode: cigaretteMotionMode, smokeColor: smokeColor))
        self.cigaretteManager = cigaretteManager
        self.styleManager = styleManager; self.ashtrayManager = ashtrayManager; self.lighterManager = lighterManager
        self.onSmokeAmount = onSmokeAmount; self.onAshAmount = onAshAmount; self.onInhaleSpeed = onInhaleSpeed
        self.onDissipation = onDissipation; self.onCloudVariation = onCloudVariation; self.onSmokeBehind = onSmokeBehind
        self.onEnergySaving = onEnergySaving; self.onExtractionMode = onExtractionMode
        self.onCigaretteMotionMode = onCigaretteMotionMode; self.onSmokeColor = onSmokeColor
        self.onResetSmokeColor = onResetSmokeColor; self.onToggleVisibility = onToggleVisibility
        self.onTakeCigarette = onTakeCigarette; self.onToggleLit = onToggleLit; self.onClearSmoke = onClearSmoke
        self.onClearAsh = onClearAsh; self.onClearCigarettes = onClearCigarettes; self.onDumpAshtray = onDumpAshtray
        self.onOptimizedFlame = onOptimizedFlame
        self.onContinuousFlameBlend = onContinuousFlameBlend
        self.onBoxLidDebugProgress = onBoxLidDebugProgress
        self.onOpenStore = onOpenStore; self.onOpenInventory = onOpenInventory
        self.onRestoreDeveloperSave = onRestoreDeveloperSave
        self.onResetForTesting = onResetForTesting; self.onResetLighterForTesting = onResetLighterForTesting
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(DeskPuffPalette.line).frame(width: 0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pageHeading
                    tabContent
                }
                .padding(.horizontal, 38).padding(.top, 43).padding(.bottom, 42)
                .frame(maxWidth: 1080, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
                    }
        .frame(minWidth: 1120, minHeight: 740)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(colors: [InventoryTheme.backgroundTop, InventoryTheme.backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [InventoryTheme.accent.opacity(0.085), .clear], center: .topLeading, startRadius: 0, endRadius: 610)
                Ellipse().fill(InventoryTheme.accentBright.opacity(0.035)).frame(width: 510, height: 180)
                    .blur(radius: 58).rotationEffect(.degrees(18)).offset(x: -450, y: -235)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .environment(\.colorScheme, .dark)
        .tint(DeskPuffPalette.accent)
        .toggleStyle(DeskPuffSegmentToggleStyle())
        .animation(.easeOut(duration: 0.16), value: state.tab)
        .onPreferenceChange(ControlPanelStatusMessagePreferenceKey.self) { state.lighterStatusMessage = $0 }
        .onDisappear {
            if state.lidDebugEnabled {
                state.lidDebugEnabled = false
                onBoxLidDebugProgress(nil)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let message = state.lighterStatusMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(DeskPuffPalette.outline, lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                    .padding(.top, 12).padding(.trailing, 18)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "smoke")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(DeskPuffPalette.accent)
                    .frame(width: 42, height: 42)
                    .background(DeskPuffPalette.selection, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("DeskPuff").font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(tr("桌面物件工作室")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.top, 43).padding(.bottom, 25)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    navigationSection(tr("工作台"), items: [.overview, .experience, .craftingCollection, .gameEditor])
                    navigationSection(tr("物件与配置"), items: [.inventory, .cigarettes, .styles, .lighter, .ashtray])
                }
            }
            Spacer(minLength: 16)
        }
        .padding(.horizontal, 14)
        .frame(width: 226)
        .background(DeskPuffPalette.chrome)
    }

    private func navigationSection(_ title: String, items: [DeskPuffControlTab]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary).padding(.leading, 10).padding(.bottom, 4)
            ForEach(items) { item in
                let selected = state.tab == item
                Button {
                    state.tab = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .frame(width: 18)
                        Text(tr(item.rawValue)).font(.system(size: 12, weight: selected ? .semibold : .regular))
                        Spacer(minLength: 0)
                        if selected { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(selected ? DeskPuffPalette.selectedControl : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(selected ? DeskPuffPalette.outline : .clear, lineWidth: 0.5))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(DeskPuffHoverStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var pageHeading: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: state.tab.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DeskPuffPalette.accent)
                .frame(width: 40, height: 40)
                .background(DeskPuffPalette.selection, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr(state.tab.rawValue)).font(.system(size: 20, weight: .semibold)).tracking(-0.2)
                Text(pageDescription).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
        }
        .padding(.bottom, 4)
    }

    private var pageDescription: String {
        switch state.tab {
        case .overview: tr("桌面物件与当前配置")
        case .inventory: tr("管理已拥有的背包和物件。")
        case .cigarettes: tr("定义烟支的颜色、尺寸和烟雾，供烟盒选用。")
        case .styles: tr("选择烟盒外观，并搭配盒内的香烟样式。")
        case .ashtray: tr("选择烟灰缸外观并即时应用。")
        case .experience: tr("调整桌面体验、快捷操作与开发测试工具。")
        case .lighter: tr("设置火焰表现、燃料与打火机外观。")
        case .craftingCollection: tr("查看全部工坊产物、材料和配方。")
        case .gameEditor: tr("调整钱包、游玩进度和背包物品，快速准备测试场景。")
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch state.tab {
        case .overview:
            VStack(spacing: 14) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Circle().fill(state.desktopVisible ? DeskPuffPalette.accent : Color.secondary.opacity(0.45)).frame(width: 7, height: 7)
                            Text(state.desktopVisible ? tr("桌面实时运行") : tr("桌面物件已隐藏"))
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        Text(tr("你的桌面，\n现在的样子。"))
                            .font(.system(size: 28, weight: .medium, design: .rounded)).lineSpacing(5)
                        Text(tr("查看物件、钱包与当前互动配置。"))
                            .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button(action: toggleDesktopVisibility) {
                            Label(state.desktopVisible ? tr("隐藏桌面物件") : tr("显示桌面物件"),
                                  systemImage: state.desktopVisible ? "eye.slash" : "eye")
                        }.buttonStyle(DeskPuffPrimaryButtonStyle()).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(tr("启动时自动打开控制面板"), isOn: $openControlPanelAtLaunch)
                            Toggle(tr("启动时打开背包"), isOn: $openInventoryAtLaunch)
                            Toggle(tr("启动时打开商店"), isOn: $openStoreAtLaunch)
                        }
                        .font(.system(size: 11, weight: .medium)).toggleStyle(.checkbox).padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 0) {
                        ProductStylePreview(kind: .boxes, styleID: currentBoxID, revision: 0)
                            .frame(width: 170, height: 220)
                        ProductStylePreview(kind: .ashtrays, styleID: currentAshtrayID, revision: 0)
                            .frame(width: 160, height: 160).offset(x: -12, y: 28)
                    }.accessibilityLabel(tr("当前烟盒和烟灰缸预览"))
                }
                .padding(.horizontal, 32).padding(.vertical, 26)
                .background(DeskPuffPalette.stage, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                PlayerStatusView(compact: true)
                overviewReadouts
                HStack(spacing: 12) {
                    statusReadout(tr("烟雾"), value: tr(SmokeAmount.allCases[state.smokeAmount].title), symbol: "smoke")
                    statusReadout(tr("消散"), value: tr(state.dissipation.title), symbol: "wind")
                    statusReadout(tr("烟支模式"), value: state.cigaretteMotionMode == .free ? tr("自由摆放") : tr("自然下落"), symbol: "arrow.down.to.line")
                    statusReadout(tr("猛吸倍率"), value: "\(Int([5, 10, 20][Int(state.inhaleSpeed.rounded())]))×", symbol: "lungs")
                }
            }
        case .experience:
            experienceSettings
        case .inventory:
            InventoryConfigurationView()
        case .cigarettes:
            cigaretteManager
        case .styles:
            styleManager
        case .ashtray: ashtrayManager
        case .lighter: lighterManager
        case .craftingCollection: RecoveryCollectionView(store: inventoryStore, developerPreview: true)
        case .gameEditor:
            DeveloperGameEditorView(store: inventoryStore, onRestore: onRestoreDeveloperSave, onReset: onResetForTesting)
        }
    }

    private var boxLidDebugSettings: some View {
        let progress = Binding<Double>(
            get: { state.lidDebugProgress },
            set: { value in
                let frameProgress = (value * 100).rounded() / 100
                state.lidDebugProgress = frameProgress
                if state.lidDebugEnabled { onBoxLidDebugProgress(frameProgress) }
            }
        )
        return VStack(alignment: .leading, spacing: 16) {
            PanelSection(title: tr("翻盖帧检查")) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(tr("暂停动画并手动定位"), isOn: $state.lidDebugEnabled)
                        .onChange(of: state.lidDebugEnabled) { _, enabled in
                            onBoxLidDebugProgress(enabled ? state.lidDebugProgress : nil)
                        }
                    labeledSlider(tr("开合进度"), value: progress, range: 0...1,
                                  labels: [tr("关闭"), "20%", tr("半开"), "80%", tr("全开")],
                                  valueLabel: "\(Int((state.lidDebugProgress * 100).rounded()))%")
                        .disabled(!state.lidDebugEnabled)
                    HStack(spacing: 8) {
                        debugProgressButton(tr("关闭"), value: 0)
                        debugProgressButton("20%", value: 0.2)
                        debugProgressButton(tr("半开"), value: 0.5)
                        debugProgressButton("80%", value: 0.8)
                        debugProgressButton(tr("全开"), value: 1)
                    }
                    .disabled(!state.lidDebugEnabled)
                }
            }
            PanelSection(title: tr("坐标与遮挡")) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(tr("盒身固定；盒盖绕同一条后侧铰链翻转。"), systemImage: "rectangle.portrait")
                    Label(tr("未取出的烟支保持在固定格位，只由开口与盒盖控制可见部分。"), systemImage: "cylinder.split.1x2")
                    Label(tr("拖动滑块可暂停在任意 1% 进度，方便逐帧截图。"), systemImage: "slider.horizontal.3")
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var overviewReadouts: some View {
        let items = inventoryStore.layout.items
        let capacity = inventoryStore.currentCapacity
        let slots = capacity.columns * capacity.rows
        let storedCount = items.filter { $0.location == .stored }.count
        let desktopCount = items.filter { $0.location == .desktop }.count
        let boxName = StylePackageRegistry.shared.cigaretteBoxes.first { $0.id == currentBoxID }?.name ?? tr("默认烟盒")
        let ashtrayName = StylePackageRegistry.shared.ashtrays.first { $0.id == currentAshtrayID }?.name ?? tr("默认烟灰缸")
        return HStack(spacing: 11) {
            statusReadout(tr("桌面物件"), value: tr("{{0}} 件 · {{1}}", desktopCount, state.desktopVisible ? tr("显示中") : tr("已隐藏")), symbol: "macwindow")
            statusReadout(tr("背包收纳"), value: tr("{{0}} 件 · {{1}} / {{2}} 格", storedCount, items.filter { $0.location == .stored }.reduce(0) { $0 + $1.footprint.width * $1.footprint.height }, slots), symbol: "backpack")
            statusReadout(tr("已完整使用"), value: tr("{{0}} 支", inventoryStore.economy.completedCigarettes), symbol: "smoke.fill")
            statusReadout(tr("当前外观"), value: "\(tr(boxName)) · \(tr(ashtrayName))", symbol: "square.grid.2x2")
        }
    }

    private func toggleDesktopVisibility() {
        state.desktopVisible.toggle()
        onToggleVisibility()
    }

    private func debugProgressButton(_ title: String, value: Double) -> some View {
        Button(title) {
            state.lidDebugProgress = value
            onBoxLidDebugProgress(value)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var experienceSettings: some View {
        let fadeOptions: [SmokeDissipation] = [.noAccumulation, .fast, .normal, .slow, .never]
        let fadeIndex = Binding<Double>(
            get: { Double(fadeOptions.firstIndex(of: state.dissipation) ?? 2) },
            set: { index in
                let value = fadeOptions[min(fadeOptions.count - 1, max(0, Int(index.rounded())))]
                state.dissipation = value
                onDissipation(value)
            }
        )
        let motionSelection = Binding<Int>(
            get: { state.cigaretteMotionMode == .gravity ? 1 : 0 },
            set: { index in
                let mode: CigaretteMotionMode = index == 1 ? .gravity : .free
                state.cigaretteMotionMode = mode
                onCigaretteMotionMode(mode)
            }
        )
        let extractionSelection = Binding<Int>(
            get: { state.extractionMode == .oneToOne ? 1 : 0 },
            set: { index in
                let mode: CigaretteExtractionMode = index == 1 ? .oneToOne : .scaled
                state.extractionMode = mode
                onExtractionMode(mode)
            }
        )
        return VStack(alignment: .leading, spacing: 16) {
            experienceSnapshot
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    PanelSection(title: tr("烟雾")) {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(tr("烟雾浓度")).font(.system(size: 12, weight: .medium))
                                DeskPuffSegmentedControl(selection: $state.smokeAmount,
                                                         options: SmokeAmount.allCases.map { tr($0.title) })
                                    .onChange(of: state.smokeAmount) { _, value in onSmokeAmount(value) }
                            }
                            labeledSlider(tr("烟雾消散"), value: fadeIndex, range: 0...4,
                                          labels: [tr("不积累"), tr("1 分钟"), tr("3 分钟"), tr("6 分钟"), tr("常驻")],
                                          valueLabel: tr(state.dissipation.title))
                            HStack(spacing: 12) {
                                ColorPicker(tr("全局烟雾颜色"), selection: Binding(
                                    get: { state.smokeColor },
                                    set: { state.smokeColor = $0; onSmokeColor($0) }
                                ), supportsOpacity: false)
                                Spacer(minLength: 8)
                                Button(action: {
                                    onResetSmokeColor()
                                    state.smokeColor = Color(.sRGB, red: 0.75, green: 0.79, blue: 0.82)
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.bordered).help(tr("恢复默认烟雾颜色")).accessibilityLabel(tr("恢复默认烟雾颜色"))
                            }
                            Divider()
                            Toggle(tr("背景烟雾浓淡层次"), isOn: $state.cloudVariation)
                                .onChange(of: state.cloudVariation) { _, value in onCloudVariation(value) }
                            Toggle(tr("显示在应用窗口后面"), isOn: $state.smokeBehindWindows)
                                .onChange(of: state.smokeBehindWindows) { _, value in onSmokeBehind(value) }
                            Toggle(tr("节能渲染"), isOn: $state.energySaving)
                                .onChange(of: state.energySaving) { _, value in onEnergySaving(value) }
                        }
                    }
                    PanelSection(title: tr("桌面快捷操作")) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 9) {
                            quickAction(tr("打开背包"), symbol: "shippingbox", action: onOpenInventory)
                            quickAction(tr("打开商店"), symbol: "storefront", action: onOpenStore)
                            quickAction(tr("整理背包"), symbol: "rectangle.3.group", action: { InventoryStore.shared.autoOrganize() })
                            quickAction(tr("显示 / 隐藏"), symbol: "eye", action: onToggleVisibility)
                            quickAction(tr("取出香烟"), symbol: "arrow.up.right", action: onTakeCigarette)
                            quickAction(tr("点燃 / 熄灭"), symbol: "flame", action: onToggleLit)
                            quickAction(tr("清空香烟"), symbol: "trash", action: onClearCigarettes)
                            quickAction(tr("清除烟雾"), symbol: "wind", action: onClearSmoke)
                            quickAction(tr("清除烟灰"), symbol: "sparkles", action: onClearAsh)
                            quickAction(tr("倒出烟灰缸"), symbol: "arrowshape.turn.up.left", action: onDumpAshtray)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 16) {
                    PanelSection(title: tr("烟支与烟灰")) {
                        VStack(alignment: .leading, spacing: 15) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(tr("香烟松手后")).font(.system(size: 12, weight: .medium))
                                DeskPuffSegmentedControl(selection: motionSelection, options: [tr("自由摆放"), tr("自然下落")])
                            }
                            VStack(alignment: .leading, spacing: 7) {
                                Text(tr("取烟方式")).font(.system(size: 12, weight: .medium))
                                DeskPuffSegmentedControl(selection: extractionSelection, options: [tr("缩放取放"), tr("一比一直接抽取")])
                            }
                            Divider()
                            labeledSlider(tr("猛吸燃烧速度"), value: $state.inhaleSpeed, range: 0...2,
                                          labels: ["5×", "10×", "20×"],
                                          valueLabel: "\(Int([5, 10, 20][Int(state.inhaleSpeed.rounded())]))×")
                                .onChange(of: state.inhaleSpeed) { _, value in onInhaleSpeed([5, 10, 20][Int(value.rounded())]) }
                            labeledSlider(tr("烟灰积累量"), value: Binding(
                                get: { Double(state.ashAmount - 1) },
                                set: { state.ashAmount = Int($0.rounded()) + 1; onAshAmount(state.ashAmount) }
                            ), range: 0...2, labels: [tr("较少"), tr("标准"), tr("较多")],
                                          valueLabel: tr(AshAmount(rawValue: state.ashAmount)?.title ?? "标准"))
                        }
                    }
                    boxLidDebugSettings
                    PanelSection(title: tr("火焰与燃料")) {
                        VStack(alignment: .leading, spacing: 13) {
                            Toggle(tr("火焰优化模式"), isOn: $optimizedFlame)
                                .onChange(of: optimizedFlame) { _, enabled in onOptimizedFlame(enabled) }
                            Toggle(tr("连续火焰帧间补间"), isOn: $continuousFlameBlend)
                                .onChange(of: continuousFlameBlend) { _, enabled in onContinuousFlameBlend(enabled) }
                            Divider()
                            HStack(spacing: 9) {
                                Text(tr("剩余燃料")).font(.system(size: 12)).foregroundStyle(.secondary)
                                ProgressView(value: lighterFuelRemaining).tint(lighterFuelRemaining < 0.15 ? .orange : .red)
                                Text("\(Int((lighterFuelRemaining * 100).rounded()))%")
                                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                                Button(tr("测试：重置燃料"), action: onResetLighterForTesting).buttonStyle(.bordered)
                            }
                            Text(tr("小、中、大火约可连续燃烧 5、3、1 分钟；熄火时燃料消耗暂停。"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, labels: [String], valueLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(valueLabel).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            NativeContinuousSlider(value: value, range: range, accessibilityLabel: title,
                                   tintColor: NSColor(srgbRed: 0.74, green: 0.48, blue: 0.98, alpha: 1))
                .frame(minWidth: 120, minHeight: 28)
            HStack {
                ForEach(labels.indices, id: \.self) { index in
                    Text(labels[index])
                        .frame(maxWidth: .infinity,
                               alignment: index == 0 ? .leading : index == labels.count - 1 ? .trailing : .center)
                }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
    private func quickAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DeskPuffPalette.accent)
                    .frame(width: 30, height: 30)
                    .background(DeskPuffPalette.selection, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
                Spacer(minLength: 3)
                Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(DeskPuffPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DeskPuffPalette.outline.opacity(0.6), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .help(title)
    }

    private var experienceSnapshot: some View {
        HStack(spacing: 0) {
            experienceMetric(tr("桌面氛围"), value: tr(SmokeAmount.allCases[state.smokeAmount].title), symbol: "smoke.fill")
            Divider().frame(height: 38)
            experienceMetric(tr("烟雾节奏"), value: tr(state.dissipation.title), symbol: "wind")
            Divider().frame(height: 38)
            experienceMetric(tr("香烟交互"), value: state.cigaretteMotionMode == .free ? tr("自由摆放") : tr("自然下落"), symbol: "arrow.down.to.line")
            Divider().frame(height: 38)
            experienceMetric(tr("吸烟反馈"), value: tr("猛吸 {{0}}×", Int([5, 10, 20][Int(state.inhaleSpeed.rounded())])), symbol: "lungs")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(DeskPuffPalette.stage, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func experienceMetric(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(DeskPuffPalette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 11, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
    private func statusReadout(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(DeskPuffPalette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 12, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 10)
        .background(DeskPuffPalette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
    private func actionCard(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DeskPuffPalette.accent).frame(width: 32, height: 32)
                    .background(DeskPuffPalette.selection, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            .padding(16)
            .background(DeskPuffPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DeskPuffPalette.outline, lineWidth: 0.7))
            .contentShape(Rectangle())
        }.buttonStyle(DeskPuffHoverStyle())
    }

    private func motionOption(_ mode: CigaretteMotionMode, symbol: String, subtitle: String, detail: String) -> some View {
        let selected = state.cigaretteMotionMode == mode
        return Button {
            guard state.cigaretteMotionMode != mode else { return }
            state.cigaretteMotionMode = mode
            onCigaretteMotionMode(mode)
        } label: {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(selected ? DeskPuffPalette.accent : Color.secondary)
                    Spacer()
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 15)).foregroundStyle(selected ? DeskPuffPalette.accent : Color.secondary.opacity(0.5))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(subtitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(18)
            .background(selected ? DeskPuffPalette.selection : DeskPuffPalette.stage, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? DeskPuffPalette.accent.opacity(0.3) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(DeskPuffHoverStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private final class DeskPuffHoverState: ObservableObject {
    @Published var hovered = false
}

struct DeskPuffHoverStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverButtonBody(configuration: configuration)
    }

    private struct HoverButtonBody: View {
        let configuration: Configuration
        @StateObject private var state = DeskPuffHoverState()
        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.65 : 1)
                .background(state.hovered ? Color.primary.opacity(0.045) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .onHover { state.hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: state.hovered)
        }
    }
}

enum DeskPuffPalette {
    static let accent = Color(red: 0.75, green: 0.58, blue: 1.0)
    static let action = Color(red: 0.57, green: 0.38, blue: 0.84)
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.53)
    static let chrome = Color(red: 0.07, green: 0.055, blue: 0.105)
    static let surface = Color.white.opacity(0.045)
    static let stage = Color.white.opacity(0.075)
    static let selection = accent.opacity(0.12)
    static let outline = Color(red: 0.82, green: 0.74, blue: 0.94).opacity(0.19)
    static let line = Color.white.opacity(0.12)
    static let selectedControl = Color(red: 0.67, green: 0.48, blue: 0.90).opacity(0.20)
}

struct DeskPuffPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(shape.fill(LinearGradient(colors: [DeskPuffPalette.accent.opacity(0.90), DeskPuffPalette.action], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(shape.fill(.black.opacity(configuration.isPressed ? 0.10 : 0)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.32), InventoryTheme.accentBright.opacity(0.14)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .shadow(color: DeskPuffPalette.accent.opacity(0.09), radius: 6, y: 2)
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.988 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PanelSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(DeskPuffPalette.accent)
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskPuffPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DeskPuffPalette.outline, lineWidth: 0.75))
    }
}

struct DeskPuffSegmentedControl: View {
    @Binding var selection: Int
    let options: [String]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let selected = selection == index
                Button {
                    selection = index
                } label: {
                    Text(options[index])
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(DeskPuffPalette.selectedControl)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct DeskPuffSegmentToggleStyle: ToggleStyle {
    var offTitle = tr("关闭")
    var onTitle = tr("开启")

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            DeskPuffSegmentedControl(
                selection: Binding(
                    get: { configuration.isOn ? 1 : 0 },
                    set: { configuration.isOn = ($0 == 1) }
                ),
                options: [offTitle, onTitle]
            )
            .frame(maxWidth: 140)
        }
    }
}
