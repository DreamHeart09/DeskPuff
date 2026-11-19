import SwiftUI
import UniformTypeIdentifiers
import AppKit
import DeskPuffCore
import Combine

@MainActor private final class StyleManagerModel: ObservableObject {
    enum Category: String, CaseIterable, Identifiable {
        case cigarettes = "烟支材质", boxes = "香烟与烟盒", ashtrays = "烟灰缸"
        var id: String { rawValue }
    }

    let cigaretteStore = CigaretteStyleStore.shared
    let packageRegistry = StylePackageRegistry.shared
    @Published var category: Category
    @Published var selectedCigaretteID = CigaretteStyleStore.shared.defaultStyleID
    @Published var selectedBoxID = UserDefaults.standard.string(forKey: "cigaretteBoxStyleV1") ?? CigaretteBoxStyle.default.id
    @Published var selectedAshtrayID = UserDefaults.standard.string(forKey: "ashtrayStyleV1") ?? AshtrayStyle.default.id
    @Published var draft = CigaretteStyleStore.shared.defaultStyle.manifest
    @Published var associateCigaretteID = CigaretteStyleStore.shared.defaultStyleID
    @Published var showingImporter = false
    @Published var message: String?
    @Published var errorMessage: String?
    @Published var editingStyleID: String?
    @Published var refreshToken = 0
    @Published var isEditingStyleName = false
    @Published var pendingDeletion: String?
    @Published var pendingDeletionType = ""

    init(category: Category) { self.category = category }
}

@MainActor struct NativeContinuousSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accessibilityLabel: String
    var tintColor: NSColor? = nil

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: context.coordinator, action: #selector(Coordinator.valueChanged(_:)))
        slider.isContinuous = true
        slider.numberOfTickMarks = 0
        slider.allowsTickMarkValuesOnly = false
        slider.controlSize = .regular
        slider.trackFillColor = tintColor
        slider.setAccessibilityLabel(accessibilityLabel)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.trackFillColor = tintColor
        slider.setAccessibilityLabel(accessibilityLabel)
        if abs(slider.doubleValue - value) > 0.000_001 {
            slider.doubleValue = value
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    @MainActor final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) { self.value = value }

        @objc func valueChanged(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue
        }
    }
}

struct ProductStylePreview: NSViewRepresentable {
    let kind: ProductStyleKind
    let styleID: String
    let revision: Int

    func makeNSView(context: Context) -> ProductStylePreviewHost { ProductStylePreviewHost() }
    func updateNSView(_ view: ProductStylePreviewHost, context: Context) {
        view.configure(kind: kind, styleID: styleID, revision: revision)
    }
}

@MainActor final class ProductStylePreviewHost: NSView {
    private var cacheKey = ""
    private var renderer: NSView?
    private var rendererContentBounds: NSRect?
    private var artwork: NSImage?
    private static var inventoryAspectCache: [String: CGFloat] = [:]

    override var isOpaque: Bool { false }

    func configure(kind: ProductStyleKind, styleID: String, revision: Int) {
        let key = "\(kind)-\(styleID)-\(revision)"
        guard cacheKey != key else { return }
        cacheKey = key
        renderer = nil; rendererContentBounds = nil; artwork = nil
        switch kind {
        case .cigarettes:
            if let style = CigaretteStyleStore.shared.resolve(styleID) {
                artwork = style.previewArtwork.flatMap(Self.trimmedArtwork)
                let view = CigaretteView(frame: NSRect(x: 0, y: 0, width: 220, height: 220))
                view.cigaretteStyle = style; view.lit = false; view.setAnimating(false)
                renderer = view
            }
        case .boxes:
            if let style = StylePackageRegistry.shared.cigaretteBoxes.first(where: { $0.id == styleID }) {
                artwork = style.previewArtwork.flatMap(Self.trimmedArtwork)
                let view = CigaretteBoxView(frame: NSRect(x: 0, y: 0, width: CigaretteBoxView.canvasSize, height: CigaretteBoxView.canvasSize))
                view.style = style; view.extractionMode = .oneToOne
                view.cigaretteStyleResolver = { box in
                    CigaretteStyleStore.shared.style(for: box)
                }
                renderer = view
                rendererContentBounds = view.inventoryPreviewBounds()
            }
        case .ashtrays:
            if let style = StylePackageRegistry.shared.ashtrays.first(where: { $0.id == styleID }) {
                artwork = style.previewArtwork.flatMap(Self.trimmedArtwork)
                let view = AshtrayView(frame: NSRect(origin: .zero, size: AshtrayView.canvasSize))
                view.style = style
                renderer = view
            }
        case .lighters:
            if let style = StylePackageRegistry.shared.lighters.first(where: { $0.id == styleID }) {
                let sourceImage = style.previewArtwork ?? style.artwork
                if let sourceImage, let source = style.artworkSourceRect {
                    artwork = Self.croppedArtwork(sourceImage, normalizedRect: source).flatMap(Self.trimmedArtwork)
                } else {
                    artwork = sourceImage.flatMap(Self.trimmedArtwork)
                }
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let target = bounds.insetBy(dx: 5, dy: 5)
        if let artwork, artwork.size.width > 0, artwork.size.height > 0 {
            let scale = min(target.width / artwork.size.width, target.height / artwork.size.height)
            let size = NSSize(width: artwork.size.width * scale, height: artwork.size.height * scale)
            artwork.draw(in: NSRect(x: target.midX - size.width / 2, y: target.midY - size.height / 2,
                                    width: size.width, height: size.height))
            return
        }
        guard let renderer else {
            let message = NSAttributedString(string: tr("预览暂不可用"), attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor
            ])
            message.draw(at: NSPoint(x: target.midX - message.size().width / 2,
                                     y: target.midY - message.size().height / 2))
            return
        }
        let source = rendererContentBounds ?? renderer.bounds
        guard source.width > 0, source.height > 0 else { return }
        let scale = min(target.width / source.width, target.height / source.height)
        let width = source.width * scale, height = source.height * scale
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext.current?.cgContext
        context?.interpolationQuality = .high
        context?.translateBy(x: target.midX - width / 2, y: target.midY - height / 2)
        context?.scaleBy(x: scale, y: scale)
        context?.translateBy(x: -source.minX, y: -source.minY)
        renderer.draw(source)
        NSGraphicsContext.restoreGraphicsState()
    }

    @MainActor static func inventoryAspectRatio(kind: ProductStyleKind, styleID: String) -> CGFloat {
        let kindKey: String
        switch kind { case .cigarettes: kindKey = "cigarettes"; case .boxes: kindKey = "boxes"; case .ashtrays: kindKey = "ashtrays"; case .lighters: kindKey = "lighters" }
        let cacheKey = "\(kindKey):\(styleID)"
        if let cached = inventoryAspectCache[cacheKey] { return cached }

        let ratio: CGFloat
        switch kind {
        case .cigarettes:
            ratio = CigaretteStyleStore.shared.resolve(styleID)?.previewArtwork.flatMap(Self.trimmedArtwork).flatMap { $0.size.height > 0 ? $0.size.width / $0.size.height : nil } ?? 1.4
        case .boxes:
            if let image = StylePackageRegistry.shared.cigaretteBoxes.first(where: { $0.id == styleID })?.previewArtwork.flatMap(Self.trimmedArtwork), image.size.height > 0 {
                ratio = image.size.width / image.size.height
            } else {
                let view = CigaretteBoxView(frame: NSRect(x: 0, y: 0, width: CigaretteBoxView.canvasSize, height: CigaretteBoxView.canvasSize))
                view.style = StylePackageRegistry.shared.cigaretteBoxes.first(where: { $0.id == styleID }) ?? .default
                let bounds = view.inventoryPreviewBounds()
                ratio = bounds.height > 0 ? bounds.width / bounds.height : 55.0 / 86.0
            }
        case .ashtrays:
            if let image = StylePackageRegistry.shared.ashtrays.first(where: { $0.id == styleID })?.previewArtwork.flatMap(Self.trimmedArtwork), image.size.height > 0 {
                ratio = image.size.width / image.size.height
            } else { ratio = 1.65 }
        case .lighters:
            if let style = StylePackageRegistry.shared.lighters.first(where: { $0.id == styleID }) {
                let image: NSImage?
                if let sourceImage = style.previewArtwork ?? style.artwork, let crop = style.artworkSourceRect {
                    image = Self.croppedArtwork(sourceImage, normalizedRect: crop).flatMap(Self.trimmedArtwork)
                } else { image = (style.previewArtwork ?? style.artwork).flatMap(Self.trimmedArtwork) }
                ratio = image.flatMap { $0.size.height > 0 ? $0.size.width / $0.size.height : nil } ?? 0.34
            } else { ratio = 0.34 }
        }
        inventoryAspectCache[cacheKey] = ratio
        return ratio
    }

    private static func croppedArtwork(_ image: NSImage, normalizedRect: CGRect) -> NSImage? {
        let source = NSRect(x: normalizedRect.minX * image.size.width,
                            y: normalizedRect.minY * image.size.height,
                            width: normalizedRect.width * image.size.width,
                            height: normalizedRect.height * image.size.height)
        guard source.width > 0, source.height > 0 else { return nil }
        let cropped = NSImage(size: source.size)
        cropped.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: source.size), from: source, operation: .copy, fraction: 1)
        cropped.unlockFocus()
        return cropped
    }

    static func trimmedArtwork(_ image: NSImage) -> NSImage? {
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let providerData = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData) else { return image }
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        guard bytesPerPixel >= 4 else { return image }
        let alphaIndex: Int
        switch cgImage.alphaInfo {
        case .premultipliedFirst, .first: alphaIndex = 0
        case .premultipliedLast, .last: alphaIndex = bytesPerPixel - 1
        default: return image
        }

        var minX = cgImage.width, minY = cgImage.height
        var maxX = -1, maxY = -1
        let sampleStride = 2
        for y in stride(from: 0, to: cgImage.height, by: sampleStride) {
            for x in stride(from: 0, to: cgImage.width, by: sampleStride) {
                let offset = y * cgImage.bytesPerRow + x * bytesPerPixel + alphaIndex
                guard bytes[offset] > 12 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }

        let pad = max(2, min(cgImage.width, cgImage.height) / 50)
        let left = max(0, minX - pad)
        let right = min(cgImage.width, maxX + pad + 1)
        let top = max(0, minY - pad)
        let bottom = min(cgImage.height, maxY + pad + 1)
        let normalized = CGRect(x: CGFloat(left) / CGFloat(cgImage.width),
                                y: CGFloat(cgImage.height - bottom) / CGFloat(cgImage.height),
                                width: CGFloat(right - left) / CGFloat(cgImage.width),
                                height: CGFloat(bottom - top) / CGFloat(cgImage.height))
        return croppedArtwork(image, normalizedRect: normalized) ?? image
    }
}

enum ProductStyleKind { case cigarettes, boxes, ashtrays, lighters }

enum StyleManagerScope { case cigarettes, boxes, ashtrays }

@MainActor struct StyleManagerView: View {
    private typealias Category = StyleManagerModel.Category
    private struct StyleRow: Identifiable {
        let id: String
        let name: String
        let detail: String
    }

    @StateObject private var model: StyleManagerModel
    private let scope: StyleManagerScope
    @AppStorage("ashtrayScaleV1") private var ashtrayScale = 1.0

    let onSelectCigarette: (CigaretteStyle) -> Void
    let onSelectBox: (CigaretteBoxStyle) -> Void
    let onSelectAshtray: (AshtrayStyle) -> Void
    let onAshtrayScale: (Double) -> Void
    let onAssociate: (String, String) -> Void

    init(scope: StyleManagerScope = .boxes,
         onSelectCigarette: @escaping (CigaretteStyle) -> Void,
         onSelectBox: @escaping (CigaretteBoxStyle) -> Void,
         onSelectAshtray: @escaping (AshtrayStyle) -> Void,
         onAssociate: @escaping (String, String) -> Void,
         onAshtrayScale: @escaping (Double) -> Void = { _ in }) {
        _model = StateObject(wrappedValue: StyleManagerModel(category: scope == .ashtrays ? .ashtrays : scope == .cigarettes ? .cigarettes : .boxes))
        self.scope = scope
        self.onSelectCigarette = onSelectCigarette; self.onSelectBox = onSelectBox
        self.onSelectAshtray = onSelectAshtray; self.onAssociate = onAssociate
        self.onAshtrayScale = onAshtrayScale
    }

    var body: some View {
        let _ = model.refreshToken
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(listTitle).font(.system(size: 14, weight: .semibold))
                        Text(listSubtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if scope == .cigarettes {
                        Button { copyStyle(model.cigaretteStore.resolve(model.selectedCigaretteID) ?? model.cigaretteStore.defaultStyle) } label: {
                            Image(systemName: "doc.on.doc").font(.system(size: 11, weight: .semibold)).frame(width: 27, height: 25)
                        }.buttonStyle(.bordered).help(tr("复制所选样式"))
                        Button {
                            if let selected = model.cigaretteStore.resolve(model.selectedCigaretteID), !selected.isBuiltIn {
                                model.pendingDeletionType = "cigarette"; model.pendingDeletion = selected.id
                            }
                        } label: {
                            Image(systemName: "trash").font(.system(size: 11, weight: .medium)).frame(width: 27, height: 25)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.cigaretteStore.resolve(model.selectedCigaretteID)?.isBuiltIn != false)
                        .help(tr("删除所选自定义样式"))
                    } else {
                        Button { model.showingImporter = true } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 27, height: 25)
                        }.buttonStyle(.bordered).help(tr("导入外观包"))
                        Button { requestDeleteSelectedPackage() } label: {
                            Image(systemName: "trash").font(.system(size: 11, weight: .medium)).frame(width: 27, height: 25)
                        }
                        .buttonStyle(.bordered).disabled(!selectedPackageID.hasPrefix("user:"))
                        .help(tr("删除所选自定义样式"))
                    }
                }
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(styleRows) { row in
                            let selected = selectionBinding.wrappedValue == row.id
                            Button { selectionBinding.wrappedValue = row.id } label: {
                                HStack(spacing: 10) {
                                    preview(for: row.id).frame(width: 44, height: 50)
                                        .background(DeskPuffPalette.stage, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tr(row.name)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                                        Text(row.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
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
            .padding(.top, 4)
            .frame(width: 254)
            Rectangle().fill(DeskPuffPalette.line).frame(width: 0.5).padding(.vertical, 4)
            Group {
                if model.category == .cigarettes {
                    detailContent
                        .padding(.leading, 2).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) { detailContent }
                            .padding(.leading, 2).padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.scrollIndicators(.automatic)
                }
            }
        }
        .frame(minWidth: 710, minHeight: 500, maxHeight: 780)
        .fileImporter(isPresented: $model.showingImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false, onCompletion: importPackage)
        .alert(tr("样式管理"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(tr("好"), role: .cancel) { model.message = nil; model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? model.message ?? "") }
        .confirmationDialog(tr("确认删除样式？"), isPresented: Binding(get: { model.pendingDeletion != nil }, set: { if !$0 { model.pendingDeletion = nil } }), titleVisibility: .visible) {
            Button(tr("删除"), role: .destructive) {
                guard let id = model.pendingDeletion else { return }
                if model.pendingDeletionType == "cigarette", let style = model.cigaretteStore.resolve(id) { removeCigarette(style) }
                else { removePackage(id, type: model.pendingDeletionType) }
                model.pendingDeletion = nil
            }
            Button(tr("取消"), role: .cancel) { model.pendingDeletion = nil }
        } message: { Text(tr("此操作会删除用户样式文件夹，无法撤销。")) }
        .onChange(of: model.category) { _, _ in syncDraft() }
        .onChange(of: model.selectedCigaretteID) { _, _ in syncDraft() }
        .preference(key: ControlPanelStatusMessagePreferenceKey.self, value: model.message)
        .onAppear { reloadPackages(); syncDraft(); syncAssociatedCigarette() }
        .onChange(of: model.selectedBoxID) { _, _ in syncAssociatedCigarette() }
    }

    private var styleRows: [StyleRow] {
        switch model.category {
        case .cigarettes:
            return model.cigaretteStore.styles.map {
                let diameter = String(format: "%.1f", $0.manifest.diameterMM)
                return StyleRow(id: $0.id, name: $0.manifest.name,
                                detail: "\($0.isBuiltIn ? tr("内置") : tr("社区样式")) · \(diameter) mm")
            }
        case .boxes:
            return model.packageRegistry.visibleCigaretteBoxes
                .map { StyleRow(id: $0.id, name: $0.name, detail: $0.id.hasPrefix("user:") ? tr("社区样式") : tr("烟盒")) }
        case .ashtrays:
            return model.packageRegistry.ashtrays.map { StyleRow(id: $0.id, name: $0.name, detail: $0.id.hasPrefix("user:") ? tr("社区样式") : tr("烟灰缸")) }
        }
    }

    private var listTitle: String {
        switch scope {
        case .cigarettes: tr("香烟样式")
        case .boxes: tr("烟盒样式")
        case .ashtrays: tr("烟灰缸样式")
        }
    }

    private var listSubtitle: String {
        switch scope {
        case .cigarettes: tr("预设与自定义烟支材质")
        case .boxes: tr("选择外观，配置盒内烟支")
        case .ashtrays: tr("选择并应用桌面烟灰缸")
        }
    }

    private var selectedPackageID: String {
        scope == .boxes ? model.selectedBoxID : model.selectedAshtrayID
    }

    private func requestDeleteSelectedPackage() {
        model.pendingDeletionType = scope == .boxes ? "cigaretteBox" : "ashtray"
        model.pendingDeletion = selectedPackageID
    }

    private var previewKind: ProductStyleKind {
        switch model.category {
        case .cigarettes: .cigarettes
        case .boxes: .boxes
        case .ashtrays: .ashtrays
        }
    }

    private var selectionBinding: Binding<String?> {
        switch model.category {
        case .cigarettes: return Binding(get: { model.selectedCigaretteID }, set: { model.selectedCigaretteID = $0 ?? model.selectedCigaretteID })
        case .boxes: return Binding(get: { model.selectedBoxID }, set: { model.selectedBoxID = $0 ?? model.selectedBoxID })
        case .ashtrays: return Binding(get: { model.selectedAshtrayID }, set: { model.selectedAshtrayID = $0 ?? model.selectedAshtrayID })
        }
    }

    @ViewBuilder private var detailContent: some View {
        switch model.category {
        case .cigarettes: cigaretteDetails
        case .boxes: boxDetails
        case .ashtrays: ashtrayDetails
        }
    }

    private var cigaretteDetails: some View {
        let style = model.cigaretteStore.resolve(model.selectedCigaretteID) ?? model.cigaretteStore.defaultStyle
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                preview(for: style.id).frame(width: 96, height: 118)
                    .background(DeskPuffPalette.stage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        if style.isBuiltIn {
                            Text(tr(style.manifest.name)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        } else if model.isEditingStyleName {
                            TextField(tr("样式名称"), text: binding(\.name))
                                .font(.system(size: 15, weight: .semibold)).textFieldStyle(.plain)
                                .onSubmit { model.isEditingStyleName = false }
                        } else {
                            Text(tr(model.draft.name)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        }
                        if !style.isBuiltIn {
                            Button { model.isEditingStyleName.toggle() } label: { Image(systemName: model.isEditingStyleName ? "checkmark" : "pencil") }
                                .buttonStyle(.plain).foregroundStyle(DeskPuffPalette.accent).help(tr("编辑样式名称"))
                        }
                    }
                    Text(style.isBuiltIn ? tr("内置预设 · 复制后可编辑") : tr("自定义烟支样式"))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        metricPill(tr("直径"), value: String(format: "%.1f mm", model.draft.diameterMM))
                        metricPill(tr("烟雾"), value: String(format: "×%.2f", model.draft.smoke.emissionMultiplier))
                    }
                    if !style.isBuiltIn {
                        Button(tr("保存修改")) { saveDraft() }.buttonStyle(DeskPuffPrimaryButtonStyle())
                    }
                }
                Spacer(minLength: 0)
            }
            if style.manifest.artwork != nil && !style.isBuiltIn {
                Text(tr("保留素材纹理，并使用下方材质颜色。"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 9) {
                PanelSection(title: tr("纸张与滤嘴")) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        colorPicker(tr("纸张"), hex: binding(\.paper.color))
                        colorPicker(tr("高光"), hex: binding(\.paper.highlight))
                        colorPicker(tr("阴影"), hex: binding(\.paper.shade))
                        colorPicker(tr("滤嘴"), hex: binding(\.filter.color))
                        colorPicker(tr("滤嘴高光"), hex: binding(\.filter.highlight))
                        colorPicker(tr("滤嘴阴影"), hex: binding(\.filter.shade))
                        colorPicker(tr("环带"), hex: binding(\.filter.band))
                    }
                }
                PanelSection(title: tr("尺寸与烟雾")) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                        GridRow {
                            Text(tr("直径")).font(.system(size: 12)).frame(width: 52, alignment: .leading)
                            NativeContinuousSlider(value: binding(\.diameterMM), range: 5...11, accessibilityLabel: tr("直径"))
                                .frame(minWidth: 100, minHeight: 26)
                            Text("\(model.draft.diameterMM, specifier: "%.1f") mm")
                                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .trailing)
                        }
                        GridRow {
                            Text(tr("烟雾量")).font(.system(size: 12)).frame(width: 52, alignment: .leading)
                            NativeContinuousSlider(value: binding(\.smoke.emissionMultiplier), range: 0.25...3, accessibilityLabel: tr("烟雾量"))
                                .frame(minWidth: 100, minHeight: 26)
                            Text("×\(model.draft.smoke.emissionMultiplier, specifier: "%.2f")")
                                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(tr("烟雾颜色"), isOn: Binding(
                            get: { model.draft.smoke.colorMode == .custom },
                            set: { model.draft.smoke.colorMode = $0 ? .custom : .inheritGlobal }
                        ))
                        .toggleStyle(DeskPuffSegmentToggleStyle(offTitle: tr("跟随全局"), onTitle: tr("自定义")))
                        if model.draft.smoke.colorMode == .custom { colorPicker(tr("烟雾色"), hex: binding(\.smoke.color)) }
                    }
                }
            }
            .disabled(style.isBuiltIn)
            if let error = model.errorMessage { Text(error).foregroundStyle(.red).font(.callout) }
        }
    }

    private var boxDetails: some View {
        guard let style = model.packageRegistry.cigaretteBoxes.first(where: { $0.id == model.selectedBoxID }) else { return AnyView(Text(tr("请选择烟盒样式"))) }
        return AnyView(VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                preview(for: style.id).frame(width: 96, height: 118)
                    .background(DeskPuffPalette.stage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 7) {
                    Text(tr(style.name)).font(.system(size: 16, weight: .semibold))
                    Text(style.id.hasPrefix("user:") ? tr("自定义烟盒") : tr("烟盒外观"))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text(tr("为这款烟盒选择固定的盒内烟支。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(tr("购买后可从背包取出，烟支搭配在下方设置。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            PanelSection(title: tr("盒内香烟")) {
                VStack(alignment: .leading, spacing: 9) {
                    Picker(tr("配套烟支"), selection: $model.associateCigaretteID) {
                        ForEach(model.cigaretteStore.styles) { cigarette in
                            Text(tr(cigarette.manifest.name)).tag(cigarette.id)
                        }
                    }
                    .pickerStyle(.menu)
                    Button(tr("保存烟支搭配")) {
                        onAssociate(style.id, model.associateCigaretteID)
                        model.message = tr("烟支搭配已保存。")
                    }.buttonStyle(.bordered)
                    Text(tr("烟支样式在“香烟”页面创建和编辑。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading))
    }

    private var ashtrayDetails: some View {
        guard let style = model.packageRegistry.ashtrays.first(where: { $0.id == model.selectedAshtrayID }) else { return AnyView(Text(tr("请选择烟灰缸样式"))) }
        return AnyView(VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                preview(for: style.id).frame(width: 96, height: 118)
                    .background(DeskPuffPalette.stage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 7) {
                    Text(tr(style.name)).font(.system(size: 16, weight: .semibold))
                    Text(style.id.hasPrefix("user:") ? tr("自定义烟灰缸") : tr("烟灰缸外观"))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text(tr("购买后可从背包取出。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            PanelSection(title: tr("桌面尺寸")) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(tr("缩放比例")).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("×\(ashtrayScale, specifier: "%.1f")")
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    NativeContinuousSlider(value: $ashtrayScale, range: 0.5...2,
                                           accessibilityLabel: tr("烟灰缸缩放比例"))
                        .frame(minWidth: 120, minHeight: 26)
                    HStack {
                        Text("0.5×")
                        Spacer()
                        Text("2×")
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .onChange(of: ashtrayScale) { _, value in onAshtrayScale(value) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading))
    }

    @ViewBuilder private func preview(for id: String) -> some View {
        ProductStylePreview(kind: previewKind, styleID: id, revision: model.refreshToken)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CigaretteStyleManifest, Value>) -> Binding<Value> {
        Binding(get: { model.draft[keyPath: keyPath] }, set: { model.draft[keyPath: keyPath] = $0 })
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CigaretteSmokeProfile, Value>) -> Binding<Value> {
        Binding(get: { model.draft.smoke[keyPath: keyPath] }, set: { model.draft.smoke[keyPath: keyPath] = $0 })
    }
    private func binding<Value>(_ keyPath: WritableKeyPath<CigarettePaperProfile, Value>) -> Binding<Value> {
        Binding(get: { model.draft.paper[keyPath: keyPath] }, set: { model.draft.paper[keyPath: keyPath] = $0 })
    }
    private func binding<Value>(_ keyPath: WritableKeyPath<CigaretteFilterProfile, Value>) -> Binding<Value> {
        Binding(get: { model.draft.filter[keyPath: keyPath] }, set: { model.draft.filter[keyPath: keyPath] = $0 })
    }

    private func colorPicker(_ title: String, hex: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).lineLimit(1)
            Spacer(minLength: 4)
            ColorPicker(title, selection: Binding(get: { color(hex.wrappedValue) }, set: { hex.wrappedValue = hexString($0) })).labelsHidden()
        }
        .frame(minHeight: 28)
    }

    private func metricPill(_ title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium).monospacedDigit()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(DeskPuffPalette.stage, in: Capsule())
    }
    private func color(_ hex: String) -> Color {
        let raw = UInt32(hex.dropFirst(), radix: 16) ?? 0xffffff
        return Color(.sRGB, red: Double((raw >> 16) & 0xff) / 255, green: Double((raw >> 8) & 0xff) / 255, blue: Double(raw & 0xff) / 255, opacity: 1)
    }
    private func hexString(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int(ns.redComponent * 255), Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
    }

    private func syncDraft() {
        guard model.category == .cigarettes, let style = model.cigaretteStore.resolve(model.selectedCigaretteID) else { return }
        model.draft = style.manifest
        model.editingStyleID = style.id.hasPrefix("user:") ? style.manifest.id : nil
    }
    private func syncAssociatedCigarette() {
        let box = model.packageRegistry.cigaretteBoxes.first { $0.id == model.selectedBoxID }
        model.associateCigaretteID = box.map { model.cigaretteStore.style(for: $0).id } ?? model.cigaretteStore.defaultStyleID
    }
    private func copyStyle(_ style: CigaretteStyle) {
        do { let copy = try model.cigaretteStore.copyForEditing(style.id); model.selectedCigaretteID = copy.id; syncDraft(); model.message = tr("已复制为可编辑的社区样式。") }
        catch { model.errorMessage = error.localizedDescription }
    }
    private func saveDraft() {
        do {
            if let editingStyleID = model.editingStyleID { model.draft.id = editingStyleID }
            let saved = try model.cigaretteStore.save(model.draft)
            model.selectedCigaretteID = saved.id; model.refreshToken &+= 1
            model.message = tr("香烟样式已保存，可在烟盒页面关联使用。")
        } catch { model.errorMessage = error.localizedDescription }
    }
    private func removeCigarette(_ style: CigaretteStyle) {
        let associations = UserDefaults.standard.dictionary(forKey: "cigaretteStyleByBoxV1") as? [String: String] ?? [:]
        guard !associations.values.contains(style.id), model.cigaretteStore.defaultStyleID != style.id else {
            model.errorMessage = tr("此样式正在使用。请先为相关烟盒选择其他香烟，并将当前香烟切换到其他样式。")
            return
        }
        do { try model.cigaretteStore.remove(style.id); model.selectedCigaretteID = model.cigaretteStore.defaultStyleID; syncDraft(); model.message = tr("香烟样式已删除。") }
        catch { model.errorMessage = error.localizedDescription }
    }
    private func reloadPackages() {
        model.cigaretteStore.reload()
        model.packageRegistry.reload()
        if scope == .ashtrays,
           !model.packageRegistry.ashtrays.contains(where: { $0.id == model.selectedAshtrayID }) {
            model.selectedAshtrayID = AshtrayStyle.default.id
            UserDefaults.standard.set(AshtrayStyle.default.id, forKey: "ashtrayStyleV1")
        }
        model.refreshToken &+= 1
    }
    private func removePackage(_ id: String, type: String) {
        do { try model.packageRegistry.removePackage(styleID: id, expectedType: type); reloadPackages(); model.message = tr("样式已删除。") }
        catch { model.errorMessage = error.localizedDescription }
    }
    private func importPackage(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            switch model.category {
            case .cigarettes:
                try model.cigaretteStore.importPackage(from: url)
                let data = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
                let manifest = try JSONDecoder().decode(CigaretteStyleManifest.self, from: data)
                model.selectedCigaretteID = "user:\(manifest.id)"
            case .boxes: try model.packageRegistry.importPackage(from: url, expectedType: "cigaretteBox")
            case .ashtrays: try model.packageRegistry.importPackage(from: url, expectedType: "ashtray")
            }
            reloadPackages(); syncDraft(); model.message = tr("樣式已導入。")
        } catch { model.errorMessage = error.localizedDescription }
    }
}
