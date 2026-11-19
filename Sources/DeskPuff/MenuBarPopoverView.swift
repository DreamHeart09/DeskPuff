import SwiftUI
import DeskPuffCore
import Combine
import AppKit

@MainActor private final class MenuBarPopoverState: ObservableObject {
    @Published var isVisible: Bool
    @Published var motionMode: CigaretteMotionMode
    @Published var dissipation: SmokeDissipation
    @Published var smokeBehindWindows: Bool
    @Published var recoveryBagShown = false
    init(isVisible: Bool, motionMode: CigaretteMotionMode, dissipation: SmokeDissipation,
         smokeBehindWindows: Bool) {
        self.isVisible = isVisible; self.motionMode = motionMode
        self.dissipation = dissipation; self.smokeBehindWindows = smokeBehindWindows
    }
}

@MainActor struct MenuBarPopoverView: View {
    @StateObject private var state: MenuBarPopoverState
    let onToggleVisibility: () -> Void
    let onMotionMode: (CigaretteMotionMode) -> Void
    let onOpenControlPanel: () -> Void
    let onOpenInventory: () -> Void
    let onOpenStore: () -> Void
    let onOpenSupportDeveloper: () -> Void
    let onOpenSettings: () -> Void
    let onToggleRecoveryBag: () -> Void
    let onQuit: () -> Void
    let onDissipation: (SmokeDissipation) -> Void
    let onSmokeBehind: (Bool) -> Void

    init(isVisible: Bool, motionMode: CigaretteMotionMode, dissipation: SmokeDissipation,
         smokeBehindWindows: Bool,
         onToggleVisibility: @escaping () -> Void,
         onMotionMode: @escaping (CigaretteMotionMode) -> Void,
         onOpenControlPanel: @escaping () -> Void, onOpenInventory: @escaping () -> Void,
         onOpenStore: @escaping () -> Void, onOpenSupportDeveloper: @escaping () -> Void,
         recoveryBagShown: Bool, onToggleRecoveryBag: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void,
         onDissipation: @escaping (SmokeDissipation) -> Void,
         onSmokeBehind: @escaping (Bool) -> Void) {
        let initial = MenuBarPopoverState(isVisible: isVisible, motionMode: motionMode,
            dissipation: dissipation, smokeBehindWindows: smokeBehindWindows)
        initial.recoveryBagShown = recoveryBagShown
        _state = StateObject(wrappedValue: initial)
        self.onToggleRecoveryBag = onToggleRecoveryBag
        self.onToggleVisibility = onToggleVisibility; self.onMotionMode = onMotionMode
        self.onOpenControlPanel = onOpenControlPanel; self.onOpenInventory = onOpenInventory
        self.onOpenStore = onOpenStore; self.onOpenSupportDeveloper = onOpenSupportDeveloper
        self.onOpenSettings = onOpenSettings; self.onQuit = onQuit
        self.onDissipation = onDissipation
        self.onSmokeBehind = onSmokeBehind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            brandHeader
            PlayerStatusView(compact: true)
            desktopControls
            smokeControls
            HStack(spacing: 8) {
                MenuBarQuickEntry(title: tr("背包"), detail: tr("管理随身物件"), artworkName: "Backpack", action: onOpenInventory)
                MenuBarQuickEntry(title: tr("商店"), detail: tr("挑选香烟与物件"), artworkName: "Storefront", action: onOpenStore)
            }
            Button {
                onToggleRecoveryBag()
                state.recoveryBagShown.toggle()
            } label: {
                Label(tr(state.recoveryBagShown ? "收起桌面背包" : "把背包放到桌面"),
                      systemImage: state.recoveryBagShown ? "backpack.fill" : "backpack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PlayerHubButtonStyle())

            supportDeveloperEntry

            HStack(spacing: 0) {
                Button(action: onOpenControlPanel) {
                    Label(tr("游戏编辑器"), systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .contentShape(Rectangle())
                }
                Button(action: onOpenSettings) {
                    Label(tr("设置与关于"), systemImage: "gearshape")
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(Rectangle())
                }
                Button(action: onQuit) {
                    Label(tr("退出"), systemImage: "power")
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .trailing)
                        .contentShape(Rectangle())
                }
            }
            .font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.75)
            .foregroundStyle(MenuBarTheme.secondaryText).buttonStyle(.plain)
            .padding(.horizontal, 10)
            .playerHubSurface(.inset, radius: 10)
        }
        .padding(13)
        .frame(width: 310)
        .foregroundStyle(MenuBarTheme.primaryText)
        .tint(MenuBarTheme.accent)
        .environment(\.colorScheme, .dark)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(colors: [MenuBarTheme.backgroundTop, MenuBarTheme.backgroundBottom],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .overlay {
                    RadialGradient(colors: [MenuBarTheme.accent.opacity(0.18), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 250)
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.clear, InventoryTheme.accentBright.opacity(0.65), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 1)
                }
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 9) {
            appIcon.frame(width: 35, height: 35)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(InventoryTheme.cardEdge, lineWidth: 0.7))
                .shadow(color: MenuBarTheme.accent.opacity(0.32), radius: 6)
                .accessibilityHidden(true)
            Text(tr("DeskPuff 赛博烟民"))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.82)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(state.isVisible ? MenuBarTheme.live : MenuBarTheme.tertiaryText).frame(width: 5, height: 5)
                Text(state.isVisible ? tr("桌面已显示") : tr("桌面已隐藏"))
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(MenuBarTheme.secondaryText)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .playerHubSurface(.inset, in: Capsule())
        }
        .padding(.horizontal, 1).padding(.bottom, 1)
    }

    private var supportDeveloperEntry: some View {
        Button(action: onOpenSupportDeveloper) {
            HStack(spacing: 9) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MenuBarTheme.gold)
                    .frame(width: 30, height: 30)
                    .background(MenuBarTheme.gold.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("支持开发者"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MenuBarTheme.primaryText)
                    Text(tr("请开发者喝杯咖啡"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MenuBarTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MenuBarTheme.secondaryText.opacity(0.8))
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .playerHubSurface(.item, radius: 12, tint: InventoryTheme.gold)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("支持开发者"))
    }

    private var desktopControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeading(tr("桌面与物件"), symbol: "square.3.layers.3d")
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    controlLabel(tr("桌面"), symbol: state.isVisible ? "eye" : "eye.slash")
                    Spacer(minLength: 3)
                    MenuBarSegmentedControl(selection: visibilitySelection, options: [tr("隐藏"), tr("显示")]).frame(width: 166)
                }
                .padding(.vertical, 4)
                Rectangle().fill(MenuBarTheme.outline).frame(height: 0.5)
                HStack(spacing: 8) {
                    controlLabel(tr("物理模式"), symbol: "arrow.down.to.line.compact")
                    Spacer(minLength: 3)
                    MenuBarSegmentedControl(selection: motionSelection, options: [tr("自由摆放"), tr("自然下落")]).frame(width: 166)
                }
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 9).padding(.vertical, 3)
            .playerHubSurface(.panel, radius: 13)
        }
    }

    private func sectionHeading(_ title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(MenuBarTheme.accent)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(MenuBarTheme.primaryText.opacity(0.92))
            Spacer()
        }.padding(.horizontal, 2)
    }

    private var smokeControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeading(tr("烟雾配置"), symbol: "smoke.fill")
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    controlLabel(tr("消散"), symbol: "wind")
                    Spacer(minLength: 4)
                    Text(tr(state.dissipation.title)).font(.system(size: 10, weight: .medium)).foregroundStyle(MenuBarTheme.secondaryText)
                }
                Slider(value: dissipationIndex, in: 0...4, step: 1)
                    .tint(InventoryTheme.accentBright)
                    .accessibilityLabel(tr("烟雾消散"))
                    .accessibilityValue(tr(state.dissipation.title))
                    .frame(height: 19)
                HStack {
                    ForEach([tr("不积累"), tr("1 分钟"), tr("3 分钟"), tr("6 分钟"), tr("常驻")].indices, id: \.self) { index in
                        Text([tr("不积累"), tr("1 分钟"), tr("3 分钟"), tr("6 分钟"), tr("常驻")][index])
                            .font(.system(size: 8)).lineLimit(1).minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : index == 4 ? .trailing : .center)
                    }
                }.foregroundStyle(MenuBarTheme.secondaryText.opacity(0.86))
                Rectangle().fill(MenuBarTheme.outline).frame(height: 0.5)
                HStack(spacing: 8) {
                    controlLabel(tr("烟雾显示"), symbol: "macwindow.on.rectangle")
                    Spacer(minLength: 4)
                    MenuBarSegmentedControl(selection: smokeBehindSelection, options: [tr("遮挡"), tr("不遮挡")]).frame(width: 166)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .playerHubSurface(.panel, radius: 13)
        }
    }

    private var dissipationOptions: [SmokeDissipation] { [.noAccumulation, .fast, .normal, .slow, .never] }

    private var dissipationIndex: Binding<Double> {
        Binding(get: { Double(dissipationOptions.firstIndex(of: state.dissipation) ?? 2) }, set: { index in
            let selected = min(dissipationOptions.count - 1, max(0, Int(index.rounded())))
            state.dissipation = dissipationOptions[selected]
            onDissipation(state.dissipation)
        })
    }

    private func controlLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 14)
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.72)
        }.foregroundStyle(MenuBarTheme.secondaryText).frame(width: 80, alignment: .leading)
    }

    private var motionSelection: Binding<Int> {
        Binding(get: { state.motionMode == .gravity ? 1 : 0 }, set: { index in
            let mode: CigaretteMotionMode = index == 1 ? .gravity : .free
            guard mode != state.motionMode else { return }
            state.motionMode = mode
            onMotionMode(mode)
        })
    }
    private var visibilitySelection: Binding<Int> {
        Binding(get: { state.isVisible ? 1 : 0 }, set: { index in
            let visible = index == 1
            guard visible != state.isVisible else { return }
            state.isVisible = visible
            onToggleVisibility()
        })
    }
    private var smokeBehindSelection: Binding<Int> {
        Binding(get: { state.smokeBehindWindows ? 1 : 0 }, set: { index in
            let enabled = index == 1
            guard enabled != state.smokeBehindWindows else { return }
            state.smokeBehindWindows = enabled
            onSmokeBehind(enabled)
        })
    }

    @ViewBuilder private var appIcon: some View {
        if let url = Bundle.module.url(forResource: "PlayerHubLogo", withExtension: "png", subdirectory: "Resources"),
           let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().interpolation(.high).scaledToFit() }
        else { Image(systemName: "smoke.fill").resizable().scaledToFit().foregroundStyle(MenuBarTheme.accent) }
    }
}

enum MenuBarTheme {
    static let backgroundTop = Color(red: 0.18, green: 0.12, blue: 0.25).opacity(0.76)
    static let backgroundBottom = Color(red: 0.07, green: 0.05, blue: 0.105).opacity(0.85)
    static let heroDivider = Color.white.opacity(0.19)
    static let outline = Color.white.opacity(0.12)
    static let accent = Color(red: 0.73, green: 0.55, blue: 1.0)
    static let accentDeep = Color(red: 0.49, green: 0.31, blue: 0.79)
    static let progressHighlight = Color(red: 0.89, green: 0.76, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.53)
    static let live = Color(red: 0.48, green: 0.87, blue: 0.67)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.66)
    static let tertiaryText = Color.white.opacity(0.38)
    static let accentNSColor = NSColor(srgbRed: 0.73, green: 0.55, blue: 1.0, alpha: 1)
}

private final class MenuBarHoverState: ObservableObject {
    @Published var hoveredIndex: Int?
    @Published var isHovered = false
}

struct MenuBarSegmentedControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: Int
    let options: [String]
    @StateObject private var hoverState = MenuBarHoverState()

    init(selection: Binding<Int>, options: [String]) {
        _selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let selected = selection == index
                Button { selection = index } label: {
                    Text(options[index])
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.82)
                        .foregroundStyle(selected ? MenuBarTheme.primaryText : MenuBarTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 27)
                        .background {
                            Capsule().fill(.white.opacity(!selected && hoverState.hoveredIndex == index ? 0.07 : 0))
                                .allowsHitTesting(false)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered in
                    if hovered { hoverState.hoveredIndex = index }
                    else if hoverState.hoveredIndex == index { hoverState.hoveredIndex = nil }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoverState.hoveredIndex)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background {
            GeometryReader { geometry in
                let segmentWidth = geometry.size.width / CGFloat(options.count)
                PlayerHubSurface.active.fill(Capsule(), tint: InventoryTheme.accent)
                    .frame(width: segmentWidth, height: geometry.size.height)
                    .shadow(color: MenuBarTheme.accent.opacity(0.25), radius: 4)
                    .offset(x: segmentWidth * CGFloat(selection))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: selection)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(3)
        .playerHubSurface(.inset, in: Capsule())
    }
}

private enum MenuBarArtwork {
    private static let imageCache = NSCache<NSString, NSImage>()

    static func image(named name: String) -> Image? {
        let key = name as NSString
        if let cached = imageCache.object(forKey: key) { return Image(nsImage: cached) }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources/MenuBar"),
              let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: key)
        return Image(nsImage: image)
    }
}

private struct MenuBarQuickEntry: View {
    let title: String
    let detail: String
    let artworkName: String
    let action: () -> Void
    @StateObject private var hoverState = MenuBarHoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let artwork = MenuBarArtwork.image(named: artworkName) {
                    artwork.resizable().interpolation(.high).scaledToFit()
                        .frame(width: 43, height: 50)
                        .shadow(color: MenuBarTheme.gold.opacity(hoverState.isHovered ? 0.22 : 0.13), radius: 5, y: 2)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(MenuBarTheme.primaryText)
                    Text(detail).font(.system(size: 9, weight: .medium)).foregroundStyle(MenuBarTheme.secondaryText).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(MenuBarTheme.secondaryText.opacity(0.78))
            }
            .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .playerHubSurface(hoverState.isHovered ? .item : .panel, radius: 13)
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(detail)")
        .onHover { hoverState.isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: hoverState.isHovered)
    }
}
