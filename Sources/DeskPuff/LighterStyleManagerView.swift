import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

struct ControlPanelStatusMessagePreferenceKey: PreferenceKey {
    static var defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) { value = nextValue() }
}

@MainActor private final class LighterStyleManagerModel: ObservableObject {
    @Published var selectedID = UserDefaults.standard.string(forKey: "lighterStyleV1") ?? LighterStyle.default.id
    @Published var showingImporter = false
    @Published var message: String?
    @Published var error: String?
    @Published var refreshToken = 0
    @Published var pendingDeletionID: String?
    let registry = StylePackageRegistry.shared
}

@MainActor struct LighterStyleManagerView: View {
    @StateObject private var model = LighterStyleManagerModel()
    let onSelect: (LighterStyle) -> Void

    var body: some View {
        let _ = model.refreshToken
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("打火机样式")).font(.system(size: 14, weight: .semibold))
                        Text(tr("查看已安装的打火机外观")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.showingImporter = true } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 27, height: 25)
                    }.buttonStyle(.bordered).help(tr("导入打火机外观包"))
                    Button { requestDeleteSelected() } label: {
                        Image(systemName: "trash").font(.system(size: 11, weight: .medium)).frame(width: 27, height: 25)
                    }.buttonStyle(.bordered).disabled(!model.selectedID.hasPrefix("user:"))
                        .help(tr("删除所选自定义样式"))
                }
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.registry.lighters) { style in
                            let selected = style.id == model.selectedID
                            Button { model.selectedID = style.id } label: {
                                HStack(spacing: 10) {
                                    lighterPreview(style).frame(width: 44, height: 50)
                                        .background(DeskPuffPalette.stage, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tr(style.name)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                                        Text(style.id.hasPrefix("user:") ? tr("自定义样式") : tr("内置预设"))
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(7)
                                .background(selected ? DeskPuffPalette.selectedControl : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(selected ? DeskPuffPalette.outline : .clear, lineWidth: 0.5))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(DeskPuffHoverStyle())
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
            .padding(.top, 4).frame(width: 254)
            Rectangle().fill(DeskPuffPalette.line).frame(width: 0.5).padding(.vertical, 4)
            if let style = selectedStyle {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        lighterPreview(style).frame(width: 96, height: 118)
                            .background(DeskPuffPalette.stage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 7) {
                            Text(tr(style.name)).font(.system(size: 16, weight: .semibold))
                            Text(tr("打火机外观")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            Text(tr("购买后可从背包取出。"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    if !model.registry.diagnostics.isEmpty {
                        Label(tr("{{0}} 个样式包未能载入", model.registry.diagnostics.count), systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 710, minHeight: 500, maxHeight: 780)
        .fileImporter(isPresented: $model.showingImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false, onCompletion: importPackage)
        .alert(tr("打火机样式"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(tr("好"), role: .cancel) { model.message = nil; model.error = nil }
        } message: { Text(model.error ?? model.message ?? "") }
        .confirmationDialog(tr("删除打火机外观？"), isPresented: Binding(
            get: { model.pendingDeletionID != nil }, set: { if !$0 { model.pendingDeletionID = nil } }
        ), titleVisibility: .visible) {
            Button(tr("删除"), role: .destructive) { deleteSelected() }
            Button(tr("取消"), role: .cancel) { model.pendingDeletionID = nil }
        } message: { Text(tr("此操作会删除用户外观包，无法撤销。")) }
        .preference(key: ControlPanelStatusMessagePreferenceKey.self, value: model.message)
        .onAppear {
            model.registry.reload()
            if !model.registry.lighters.contains(where: { $0.id == model.selectedID }) { model.selectedID = LighterStyle.default.id }
        }
    }

    private var selectedStyle: LighterStyle? { model.registry.lighters.first { $0.id == model.selectedID } }
    private func lighterPreview(_ style: LighterStyle) -> some View { LighterStylePreview(style: style) }
    private func requestDeleteSelected() {
        guard model.selectedID.hasPrefix("user:") else { return }
        model.pendingDeletionID = model.selectedID
    }

    private func deleteSelected() {
        guard let id = model.pendingDeletionID else { return }
        do {
            try model.registry.removePackage(styleID: id, expectedType: "lighter")
            model.registry.reload()
            model.selectedID = LighterStyle.default.id
            UserDefaults.standard.set(model.selectedID, forKey: "lighterStyleV1")
            model.message = tr("打火机样式已删除。")
        } catch { model.error = error.localizedDescription }
        model.pendingDeletionID = nil
    }

    private func importPackage(_ result: Result<[URL], Error>) {
        do {
            guard let source = try result.get().first else { return }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try model.registry.importPackage(from: source, expectedType: "lighter")
            let data = try Data(contentsOf: source.appendingPathComponent("manifest.json"))
            let manifest = try JSONDecoder().decode(LighterStylePackageManifest.self, from: data)
            model.selectedID = "user:\(manifest.id)"; model.registry.reload(); model.refreshToken &+= 1
            model.message = tr("打火机样式已导入。")
        } catch { model.error = error.localizedDescription }
    }
}

private struct LighterStylePackageManifest: Decodable { let id: String }

private struct LighterStylePreview: NSViewRepresentable {
    let style: LighterStyle

    func makeNSView(context: Context) -> LighterStylePreviewHost { LighterStylePreviewHost() }
    func updateNSView(_ view: LighterStylePreviewHost, context: Context) { view.configure(style) }
}

private final class LighterStylePreviewHost: NSView {
    private var styleID = ""
    private var lighter: LighterView?

    override var isOpaque: Bool { false }

    func configure(_ style: LighterStyle) {
        guard styleID != style.id else { return }
        styleID = style.id
        subviews.forEach { $0.removeFromSuperview() }
        lighter = nil
        let view = LighterView(frame: NSRect(origin: .zero, size: LighterView.canvasSize))
        view.style = style
        lighter = view
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.cgContext.clear(dirtyRect)
        guard let lighter else { return }
        let source = lighter.visibleBodyBounds().offsetBy(dx: lighter.bounds.minX, dy: lighter.bounds.minY)
        guard source.width > 0, source.height > 0 else { return }
        let target = bounds.insetBy(dx: 8, dy: 8)
        let scale = min(target.width / source.width, target.height / source.height)
        let width = source.width * scale, height = source.height * scale
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext.current?.cgContext
        context?.interpolationQuality = .high
        context?.translateBy(x: target.midX - width / 2, y: target.midY - height / 2)
        context?.scaleBy(x: scale, y: scale)
        context?.translateBy(x: -source.minX, y: -source.minY)
        lighter.draw(source)
        NSGraphicsContext.restoreGraphicsState()
    }
}
