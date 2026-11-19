import SwiftUI
import DeskPuffCore

@MainActor private final class DeveloperGameEditorState: ObservableObject {
    enum Grant: Hashable {
        case product(String)
        case material(RecoveryMaterial)
    }

    enum Confirmation {
        case restore, reset, remove(UUID)

        var title: String {
            switch self {
            case .restore: tr("还原测试前存档？")
            case .reset: tr("重置测试存档？")
            case .remove: tr("移除所选物品？")
            }
        }

        var detail: String {
            switch self {
            case .restore: tr("将快照之后的游玩进度、钱包和库存替换为快照中的状态。")
            case .reset: tr("将清空背包与桌面物件，并将钱包、购买记录和段位恢复为初始状态。重置前会保留一份本地备份。")
            case .remove: tr("整件物品或整组堆叠会从背包移除。")
            }
        }
    }

    @Published var balance = ""
    @Published var completed = ""
    @Published var crafted = ""
    @Published var sold = ""
    @Published var grant: Grant?
    @Published var grantCount = 1
    @Published var selectedItem: UUID?
    @Published var itemCount = 1
    @Published var confirmation: Confirmation?

    func clearProgressFields() {
        balance = ""
        completed = ""
        crafted = ""
        sold = ""
    }
}

@MainActor struct DeveloperGameEditorView: View {
    @ObservedObject var store: InventoryStore
    let onRestore: () -> Void
    let onReset: () -> Void
    @StateObject private var state = DeveloperGameEditorState()

    private var products: [StoreProduct] { store.economyRules?.products ?? [] }
    private var storedItems: [InventoryItem] { store.layout.items.filter { $0.location == .stored } }
    private var selectedItem: InventoryItem? { storedItems.first { $0.id == state.selectedItem } }
    private var grantSelection: Binding<DeveloperGameEditorState.Grant?> {
        Binding(get: { state.grant }, set: { state.grantCount = 1; state.grant = $0 })
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(get: { state.confirmation != nil }, set: { if !$0 { state.confirmation = nil } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            snapshotBar
            progressPanel
            HStack(alignment: .top, spacing: 14) {
                grantPanel
                itemPanel
            }
        }
        .onAppear { store.setMessage(nil) }
        .onChange(of: selectedItem, initial: true) { _, item in
            state.itemCount = item.map(currentQuantity) ?? 1
        }
        .alert(state.confirmation?.title ?? "", isPresented: confirmationPresented, presenting: state.confirmation) { action in
            Button(tr("取消"), role: .cancel) {}
            Button(tr("确认修改"), role: .destructive) { confirm(action) }
        } message: { action in
            Text(action.detail)
        }
    }

    private var snapshotBar: some View {
        PanelSection(title: tr("测试存档")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(store.hasDeveloperSaveBackup ? tr("已保留玩家存档快照") : tr("首次修改时自动保留快照"),
                              systemImage: store.hasDeveloperSaveBackup ? "checkmark.shield" : "externaldrive")
                            .font(.callout.weight(.semibold))
                        Text(tr("修改直接写入当前存档。测试结束后可一键还原。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(tr("保存快照")) { store.captureDeveloperSave() }
                        .disabled(store.hasDeveloperSaveBackup)
                    Button(tr("还原快照…")) { state.confirmation = .restore }
                        .disabled(!store.hasDeveloperSaveBackup)
                    Button(tr("重置…")) { state.confirmation = .reset }
                }
                if let message = store.message {
                    Label(message, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(DeskPuffPalette.accent)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
        }
    }

    private var progressPanel: some View {
        PanelSection(title: tr("钱包与游玩进度")) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 105), spacing: 12), count: 4), spacing: 10) {
                    progressField(tr("钱包余额（元）"), current: recoveryMoney(store.economy.balanceCents), input: $state.balance)
                    progressField(tr("抽完烟支"), current: store.economy.completedCigarettes.formatted(), input: $state.completed)
                    progressField(tr("合成产物数"), current: store.economy.recoveryCraftCount.formatted(), input: $state.crafted)
                    progressField(tr("回收出售件数"), current: store.economy.recoveryItemsSold.formatted(), input: $state.sold)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("只应用填写的字段。余额可精确到分。"))
                        if let rules = store.economyRules {
                            let preview = rules.progress(completed: wholeNumber(state.completed) ?? store.economy.completedCigarettes)
                            Text(tr("预览段位：{{0}} · {{1}} 星", tr(rules.ranks[preview.rankIndex].name), preview.star))
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("应用测试数值"), action: applyProgress)
                        .buttonStyle(DeskPuffPrimaryButtonStyle())
                        .disabled(!hasProgressChanges)
                }
            }
        }
    }

    private func progressField(_ title: String, current: String, input: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(current).font(.title3.weight(.semibold)).monospacedDigit()
            TextField(title, text: input, prompt: Text(tr("填写新值")))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DeskPuffPalette.stage, in: RoundedRectangle(cornerRadius: 9))
    }

    private var grantPanel: some View {
        PanelSection(title: tr("发放道具与材料")) {
            VStack(alignment: .leading, spacing: 11) {
                Picker(tr("发放物品"), selection: grantSelection) {
                    Text(tr("选择物品")).tag(nil as DeveloperGameEditorState.Grant?)
                    Section(tr("商店道具")) {
                        ForEach(products) { product in
                            Text(tr(product.name)).tag(Optional(DeveloperGameEditorState.Grant.product(product.id)))
                        }
                    }
                    Section(tr("回收物与合成产物")) {
                        ForEach(RecoveryMaterial.allCases.filter { $0 != .premiumEmptyPack }) { material in
                            Text(material.title).tag(Optional(DeveloperGameEditorState.Grant.material(material)))
                        }
                    }
                }
                HStack {
                    Text(tr("发放数量")).font(.caption)
                    TextField(tr("发放数量"), value: $state.grantCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 62)
                        .disabled(state.grant == nil)
                    Spacer()
                    Button(tr("发放至背包"), action: grant)
                        .buttonStyle(DeskPuffPrimaryButtonStyle())
                        .disabled(state.grant == nil || !(1...grantLimit).contains(state.grantCount))
                }
                Text(tr("直接入包，无需付款。空间不足时整批取消。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var itemPanel: some View {
        PanelSection(title: tr("编辑背包库存")) {
            VStack(alignment: .leading, spacing: 11) {
                Picker(tr("背包物品"), selection: $state.selectedItem) {
                    Text(storedItems.isEmpty ? tr("背包为空") : tr("选择物品")).tag(nil as UUID?)
                    ForEach(storedItems) { item in
                        Text(tr("{{0}} · 第 {{1}} 行第 {{2}} 列", itemName(item), item.row + 1, item.column + 1))
                            .tag(Optional(item.id))
                    }
                }
                .disabled(storedItems.isEmpty)
                if let item = selectedItem {
                    if let range = quantityRange(item) {
                        Stepper(tr(item.kind == .cigaretteBox ? "盒内余量 · {{0}}" : "堆叠数量 · {{0}}", state.itemCount),
                                value: $state.itemCount, in: range)
                    }
                    HStack {
                        Button(tr("移除物品…"), role: .destructive) { state.confirmation = .remove(item.id) }
                        Spacer()
                        if quantityRange(item) != nil {
                            Button(tr("应用数量")) { store.editStoredItemForTesting(item.id, count: state.itemCount) }
                                .buttonStyle(DeskPuffPrimaryButtonStyle())
                                .disabled(state.itemCount == currentQuantity(item))
                        }
                    }
                } else {
                    Text(tr("可改烟盒余量和材料堆叠数量，也可移除背包物品。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var progressInputs: [String] { [state.balance, state.completed, state.crafted, state.sold] }
    private var hasProgressChanges: Bool { progressInputs.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    private func applyProgress() {
        let values = progressInputs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let parsed = [moneyCents(values[0]), wholeNumber(values[1]), wholeNumber(values[2]), wholeNumber(values[3])]
        guard zip(values, parsed).allSatisfy({ $0.isEmpty || $1 != nil }) else {
            store.setMessage(tr("请输入有效的非负数，余额最多两位小数。"))
            return
        }
        if store.setProgressForTesting(balanceCents: parsed[0], completedCigarettes: parsed[1],
                                       craftCount: parsed[2], soldCount: parsed[3]) {
            state.clearProgressFields()
        }
    }

    private func wholeNumber(_ source: String) -> Int? {
        let raw = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(raw)
    }

    private func moneyCents(_ source: String) -> Int? {
        let parts = source.replacingOccurrences(of: ",", with: ".").split(separator: ".", omittingEmptySubsequences: false)
        guard let yuan = parts.first, (1...2).contains(parts.count), wholeNumber(String(yuan)) != nil else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]) : "0"
        guard (1...2).contains(fraction.count), wholeNumber(fraction) != nil else { return nil }
        return Int(String(yuan) + fraction + (fraction.count == 1 ? "0" : ""))
    }

    private var grantLimit: Int {
        let slots = max(1, store.layout.rows * store.layout.columns)
        switch state.grant {
        case .material(let material): return slots * material.stackLimit
        case .product(let id): return products.first { $0.id == id }?.passiveEffect == nil ? slots : 1
        case nil: return 1
        }
    }

    private func grant() {
        switch state.grant {
        case .product(let id):
            if let product = products.first(where: { $0.id == id }) { store.grantForTesting(product: product, count: state.grantCount) }
        case .material(let material):
            store.grantForTesting(material: material, count: state.grantCount)
        case nil:
            break
        }
    }

    private func currentQuantity(_ item: InventoryItem) -> Int {
        if item.kind == .cigaretteBox { return CigaretteBoxView.inventoryStock(from: item.state) }
        return max(1, item.recoveryCount)
    }

    private func quantityRange(_ item: InventoryItem) -> ClosedRange<Int>? {
        if item.kind == .cigaretteBox { return 0...CigaretteBoxView.defaultStock }
        return item.kind.recoveryMaterial.map { 1...$0.stackLimit }
    }

    private func itemName(_ item: InventoryItem) -> String {
        let registry = StylePackageRegistry.shared
        switch item.kind {
        case .cigaretteBox, .emptyPack, .premiumEmptyPack:
            if let name = registry.cigaretteBoxes.first(where: { $0.id == item.styleID })?.name { return tr(name) }
        case .tool:
            if let product = products.first(where: { $0.id == item.styleID }) { return tr(product.name) }
        case .ashtray:
            if let name = registry.ashtrays.first(where: { $0.id == item.styleID })?.name { return tr(name) }
        case .lighter:
            if let name = registry.lighters.first(where: { $0.id == item.styleID })?.name { return tr(name) }
        default:
            break
        }
        return tr(item.kind.title)
    }

    private func confirm(_ action: DeveloperGameEditorState.Confirmation) {
        switch action {
        case .restore:
            onRestore()
            state.selectedItem = nil
            state.clearProgressFields()
        case .reset:
            onReset()
            state.selectedItem = nil
            state.clearProgressFields()
        case .remove(let id):
            if store.editStoredItemForTesting(id, count: nil) { state.selectedItem = nil }
        }
    }
}
