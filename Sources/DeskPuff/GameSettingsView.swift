import Combine
import AppKit
import SwiftUI
import WidgetKit

@MainActor struct GameSettingsView: View {
    private final class SettingsState: ObservableObject {
        @Published var language = GameLanguage.current
        @Published var energySaving = UserDefaults.standard.bool(forKey: "energySaving")
        @Published var confirmingReset = false
        @Published var resetResult: Bool?
        @Published var showingWidgetSetup = false
    }

    @StateObject private var state = SettingsState()
    let onLanguageChanged: (GameLanguage) -> Void
    let onQualityChanged: (Bool) -> Void
    let onResetSave: () -> Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settings
                about
            }
            .padding(22)
        }
        .frame(width: 640, height: 800)
        .foregroundStyle(InventoryTheme.primaryText)
        .background(LinearGradient(colors: [InventoryTheme.panelTop, InventoryTheme.backgroundBottom],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $state.showingWidgetSetup) { widgetSetupSheet }
        .alert(tr("清空游戏存档？"), isPresented: $state.confirmingReset) {
            Button(tr("清空存档"), role: .destructive) { state.resetResult = onResetSave() }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("将清空背包与桌面物件，并将钱包、购买记录和段位恢复为初始状态。重置前会保留一份本地备份。"))
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("游戏设置")).font(.headline)
            HStack(spacing: 12) {
                Text(tr("界面语言")).font(.callout.weight(.medium))
                Spacer()
                MenuBarSegmentedControl(selection: Binding(get: {
                    GameLanguage.allCases.firstIndex(of: state.language) ?? 0
                }, set: { index in
                    guard GameLanguage.allCases.indices.contains(index) else { return }
                    let language = GameLanguage.allCases[index]
                    state.language = language
                    onLanguageChanged(language)
                }), options: GameLanguage.allCases.map(\.name))
                    .frame(width: 190)
                    .accessibilityLabel(tr("界面语言"))
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("画面质量")).font(.callout.weight(.medium))
                    Text(tr("节能模式降低烟雾渲染负载")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                MenuBarSegmentedControl(selection: Binding(get: {
                    state.energySaving ? 1 : 0
                }, set: { index in
                    let energySaving = index == 1
                    guard state.energySaving != energySaving else { return }
                    state.energySaving = energySaving
                    onQualityChanged(energySaving)
                }), options: [tr("高画质"), tr("节能")])
                    .frame(width: 190)
                    .accessibilityLabel(tr("画面质量"))
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("桌面小组件")).font(.callout.weight(.medium))
                    Text(tr("打开添加步骤与系统组件设置")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    WidgetCenter.shared.reloadAllTimelines()
                    state.showingWidgetSetup = true
                } label: {
                    Label(tr("设置小组件"), systemImage: "rectangle.stack.badge.plus")
                }
                .buttonStyle(PlayerHubButtonStyle(prominent: true))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(tr("存档管理")).font(.callout.weight(.semibold))
                Text(tr("清除当前玩家进度，并创建全新的初始存档。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(tr("清空存档…"), role: .destructive) { state.confirmingReset = true }
                    Spacer()
                    if let resetResult = state.resetResult {
                        Text(tr(resetResult ? "新存档已建立" : "无法重置存档"))
                            .font(.caption).foregroundStyle(resetResult ? InventoryTheme.accentBright : .red)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .playerHubSurface(.panel, radius: 13)
    }

    private var about: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let repository = (Bundle.main.infoDictionary?["DeskPuffGitHubURL"] as? String)
            .flatMap(URL.init(string:))
            .flatMap { $0.scheme == "https" && $0.host != nil ? $0 : nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text(tr("关于")).font(.callout.weight(.semibold))
            HStack(alignment: .firstTextBaseline) {
                Text(tr("DeskPuff 赛博烟民"))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
                Text(tr("版本 {{0}} · 构建 {{1}}", version, build))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(tr("在桌面摆放、互动和收藏烟具的小桌面游戏。"))
                .font(.callout).foregroundStyle(.secondary)
            if let repository {
                Link("GitHub", destination: repository)
            } else {
                Text(tr("GitHub 地址待公布")).font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("DeskPuff 赛博烟民玩家交流群"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(tr("进群下载最新测试版本，参与讨论交流。"))
                        .font(.system(size: 11))
                        .foregroundStyle(InventoryTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tr("群号：{{0}}", "207898947"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospaced())
                        .foregroundStyle(InventoryTheme.accentBright)
                }
                Spacer(minLength: 0)
                AboutQRCode(title: tr("加入交流群"), resourceName: "QQGroupQR", fileExtension: "jpg", size: 138)
            }
            .padding(11)
            .playerHubSurface(.inset, radius: 12)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("赞助开发者"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(tr("纯自愿支持 · 不影响游戏功能"))
                        .font(.system(size: 10))
                        .foregroundStyle(InventoryTheme.secondaryText)
                }
                Spacer(minLength: 0)
                AboutQRCode(title: tr("微信赞赏"), resourceName: "WeChatQR", fileExtension: "JPG", size: 94)
                AboutQRCode(title: tr("支付宝支持"), resourceName: "AlipayQR", fileExtension: "PNG", size: 94)
            }
            .padding(10)
            .playerHubSurface(.inset, radius: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .playerHubSurface(.panel, radius: 13)
    }

    private var widgetSetupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(InventoryTheme.accentBright)
                    .frame(width: 42, height: 42).playerHubSurface(.item, radius: 13)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("添加 DeskPuff 小组件")).font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(tr("无需额外隐私授权")).font(.caption).foregroundStyle(InventoryTheme.accentBright)
                }
                Spacer()
                Button { state.showingWidgetSetup = false } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26).background(Color.white.opacity(0.08), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel(tr("关闭"))
            }

            VStack(alignment: .leading, spacing: 11) {
                widgetSetupStep("1", tr("确认系统桌面小组件已开启"), tr("系统设置 → 桌面与程序坞 → 小组件 → 在桌面上显示"))
                widgetSetupStep("2", tr("打开桌面组件库"), tr("按住 Control 点击桌面，选择“编辑小组件”。"))
                widgetSetupStep("3", tr("搜索并添加组件"), tr("搜索 DeskPuff Status，选择小号或中号。"))
            }
            .padding(14).playerHubSurface(.panel, radius: 14)

            HStack {
                Button(tr("打开系统设置")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                }.buttonStyle(PlayerHubButtonStyle())
                Spacer()
                Button(tr("完成")) { state.showingWidgetSetup = false }
                    .buttonStyle(PlayerHubButtonStyle(prominent: true))
            }
        }
        .padding(22)
        .frame(width: 470)
        .foregroundStyle(InventoryTheme.primaryText)
        .background(LinearGradient(colors: [InventoryTheme.panelTop, InventoryTheme.backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
        .environment(\.colorScheme, .dark)
    }

    private func widgetSetupStep(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white).frame(width: 21, height: 21).playerHubSurface(.active, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(InventoryTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AboutQRCode: View {
    let title: String
    let resourceName: String
    let fileExtension: String
    let size: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .padding(4)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel(title)
            }
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(InventoryTheme.secondaryText)
                .lineLimit(1)
        }
        .fixedSize()
    }

    private var image: NSImage? {
        guard let url = Bundle.module.url(forResource: resourceName,
                                          withExtension: fileExtension,
                                          subdirectory: "Resources/Support") else { return nil }
        return NSImage(contentsOf: url)
    }
}
