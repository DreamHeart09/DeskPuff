import AppKit
import SwiftUI
import Combine
import DeskPuffCore

func recoveryMoney(_ cents: Int) -> String {
    cents.isMultiple(of: 100) ? "¥\(cents / 100)" : String(format: "¥%.2f", Double(cents) / 100)
}

extension RecoveryValueTier {
    var title: String {
        switch self {
        case .low: tr("低价值")
        case .medium: tr("中价值")
        case .high: tr("高价值")
        }
    }
}

extension RecoveryMaterial {
    var title: String { tr(kind.title) }

    var workshopDescription: String {
        switch self {
        case .phoneBooth: tr("电话只通向桌角的另一头，忙音倒很逼真。")
        case .paperclipFrog: tr("给它两枚回形针，它就假装没吃过。")
        case .deskFan: tr("二档是个摆设，一档已经够它喘了。")
        case .marbleRun: tr("上班摸鱼专线，单程三秒，弹珠从不迟到。")
        case .redFoilMisprint: tr("印对了反而没这么贵。")
        case .celadonSmokeMark: tr("摊主坚持这是窑变。")
        case .filterFossil: tr("年代不详，初步判断是昨天。")
        case .redBlueOverprint: tr("一张两层套色的旧印刷样张，红金边下透出青色暗纹。")
        case .goldSeal: tr("封的是旧盒，估的是手艺。")
        case .fortuneFold: tr("签文写着：宜放进玻璃柜。")
        case .cloudGlass: tr("看起来像珠子，摊主说是缩小的云。")
        case .paperCicada: tr("不叫，只在干燥天气里升值。")
        case .ashSpoon: tr("只能舀灰，收藏家偏说用途克制。")
        case .starAsh: tr("夜里看不见星星，拓片倒是能看见。")
        case .lotusFoil: tr("荷花没有留下，箔纸把影子留住了。")
        case .redTowerTicket: tr("目的地不明，票面仍然很坚定。")
        case .doubleJoySeal: tr("喜字压得很实，喜事还在路上。")
        case .riverCloudMedallion: tr("正面像江，背面像云，摊主收双景的钱。")
        case .peonyAshPrint: tr("牡丹只拓出一半，正好留给想象。")
        case .silverLining: tr("每片旧盒都有银边，今天这片尤其值钱。")
        case .ashLantern: tr("灯不点火，靠桌灯照样显得有故事。")
        case .emberStamp: tr("火漆没等到，余烬先盖了章。")
        case .boxFoldPavilion: tr("亭子不避雨，只避开了回收秤。")
        case .moonInCellophane: tr("薄膜里的一轮月亮，保鲜期暂定永久。")
        case .doubleFoilFold: tr("两道折痕一正一反，摊主称其为金箔的对称美。")
        case .celadonAshPearl: tr("灰珠不圆，摊主说这是手工留下的个性。")
        case .ruyiAshRibbon: tr("灰绦打了个如意结，解开会影响估价。")
        case .goldenCloudStamp: tr("云印只有半朵，另一半按珍稀留白计价。")
        case .nanjingPaperWhistle: tr("吹不响，但能证明纸盒曾经很有志气。")
        case .furongCinderButton: tr("缝在衣服上会掉灰，放进盒里就叫藏品。")
        case .doubleJoyCigaretteSleeve: tr("给一截烟头做的纸套，尺寸严丝合缝。")
        case .liqunAshSleeve: tr("烟屑被夹成了薄片，收藏家称之为轻量派。")
        case .lotusEmberPetal: tr("花瓣没烧着，只留下了一个余烬色的边。")
        case .redTowerAshCoin: tr("像枚旧铜钱，摊主拒绝收它抵账。")
        case .ashCigaretteRing: tr("烟灰绕烟头一圈，戒指本人不建议佩戴。")
        case .zhonghuaSmokeFilm: tr("一层薄膜留住了烟纹，也留住了估价空间。")
        case .yuxiFilterCharm: tr("滤嘴挂坠不辟邪，只负责看起来有来历。")
        case .nanjingGrayLeaf: tr("叶脉是灰拓的，叶柄是纸折的。")
        case .furongEmberClip: tr("夹子能夹住纸边，夹不住继续上涨的报价。")
        case .doubleJoyAshBadge: tr("喜字没写全，灰倒是压得很完整。")
        case .crossBrandLantern: tr("红边和蓝边各占一面，摊主说灯光因此更均匀。")
        case .oldShopLedgerSeal: tr("两种旧盒纸压出封口，账本内容概不公开。")
        case .lotusGoldenCompass: tr("一半荷纹一半金边，指针指向最近的灯。")
        case .whiteRedFoldedStage: tr("白纸搭台、红箔压檐，演出只有一场。")
        case .mysteryJunk: tr("成分不明，重量属实。")
        default: ""
        }
    }
    var symbol: String {
        switch self {
        case .fineAsh: "circle.grid.3x3.fill"
        case .ashClump: "square.stack.3d.up.fill"
        case .cigaretteButt: "capsule.lefthalf.filled"
        case .emberStone: "diamond.fill"
        case .emptyPack, .premiumEmptyPack: "shippingbox.fill"
        case .ashSeal: "seal.fill"
        case .gildedRelic: "sparkles.rectangle.stack.fill"
        case .cloudMarble: "circle.hexagongrid.fill"
        case .fortuneCoin: "dollarsign.circle.fill"
        case .smokeDuck: "bird.fill"
        case .goldenCigarette: "sparkles"
        case .ashDumpling: "takeoutbag.and.cup.and.straw.fill"
        case .phoneBooth: "phone.fill"
        case .paperclipFrog: "paperclip"
        case .deskFan: "fan.fill"
        case .marbleRun: "point.topleft.down.to.point.bottomright.curvepath"
        case .redFoilMisprint, .redBlueOverprint: "rectangle.inset.filled.and.person.filled"
        case .celadonSmokeMark, .cloudGlass, .riverCloudMedallion: "circle.hexagongrid.fill"
        case .filterFossil: "fossil.shell.fill"
        case .goldSeal, .doubleJoySeal, .emberStamp: "seal.fill"
        case .fortuneFold, .redTowerTicket, .boxFoldPavilion: "ticket.fill"
        case .paperCicada: "bird.fill"
        case .ashSpoon: "spoon.fill"
        case .starAsh: "sparkles"
        case .lotusFoil: "leaf.fill"
        case .peonyAshPrint: "camera.macro"
        case .silverLining: "sun.max.fill"
        case .ashLantern: "lamp.table.fill"
        case .moonInCellophane: "moon.fill"
        case .doubleFoilFold, .goldenCloudStamp: "sparkles.rectangle.stack.fill"
        case .celadonAshPearl, .redTowerAshCoin: "circle.fill"
        case .ruyiAshRibbon: "ribbon.fill"
        case .nanjingPaperWhistle: "speaker.wave.2.fill"
        case .furongCinderButton, .doubleJoyAshBadge: "circle.hexagongrid.fill"
        case .doubleJoyCigaretteSleeve, .liqunAshSleeve, .zhonghuaSmokeFilm: "rectangle.portrait.fill"
        case .lotusEmberPetal, .nanjingGrayLeaf: "leaf.fill"
        case .ashCigaretteRing: "circle.dotted"
        case .yuxiFilterCharm: "tag.fill"
        case .furongEmberClip: "paperclip"
        case .crossBrandLantern: "lamp.table.fill"
        case .oldShopLedgerSeal: "book.closed.fill"
        case .lotusGoldenCompass: "location.north.circle.fill"
        case .whiteRedFoldedStage: "theatermasks.fill"
        case .mysteryJunk: "wastebasket.fill"
        }
    }
}

private let recoveryArtwork: [RecoveryMaterial: NSImage] = Dictionary(
    uniqueKeysWithValues: RecoveryMaterial.allCases.compactMap { material in
        let asset = material == .mysteryJunk ? "wastePile" : material.rawValue
        guard let url = Bundle.module.url(forResource: asset, withExtension: "png", subdirectory: "Resources/Recovery"),
              let image = NSImage(contentsOf: url) else { return nil }
        return (material, image)
    }
)

extension RecoveryMaterial {
    var artwork: NSImage? { recoveryArtwork[self] }
}

struct RecoveryMaterialArt: View {
    let material: RecoveryMaterial

    var body: some View {
        if let image = material.artwork {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: material.symbol)
                .resizable().scaledToFit()
                .foregroundStyle(LinearGradient(colors: [InventoryTheme.gold, Color(red: 0.69, green: 0.25, blue: 0.09)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: InventoryTheme.gold.opacity(0.45), radius: 5)
                .padding(5)
        }
    }
}

@MainActor extension RecoveryIngredient {
    var boxStyle: CigaretteBoxStyle? {
        guard case .pack(let styleID) = self else { return nil }
        return StylePackageRegistry.shared.cigaretteBoxes.first { $0.id == styleID }
    }

    var title: String {
        switch self {
        case .material(let material): return material.title
        case .pack(let styleID):
            if let style = boxStyle { return tr(style.name) }
            if [RecoveryMaterial.emptyPack.rawValue, RecoveryMaterial.premiumEmptyPack.rawValue].contains(styleID) {
                return tr("无标记烟盒")
            }
            return tr("烟盒 · {{0}}", styleID)
        }
    }
}

struct RecoveryIngredientArt: View {
    let ingredient: RecoveryIngredient

    var body: some View {
        switch ingredient {
        case .material(let material): RecoveryMaterialArt(material: material)
        case .pack:
            if let style = ingredient.boxStyle {
                ProductStylePreview(kind: .boxes, styleID: style.id, revision: 0)
            } else {
                RecoveryMaterialArt(material: .emptyPack)
            }
        }
    }
}

private struct RecoveryPriceSparkline: View {
    let values: [Int]
    let change: Int

    private var tone: Color {
        if change > 0 { Color(red: 0.96, green: 0.31, blue: 0.34) }
        else if change < 0 { Color(red: 0.24, green: 0.78, blue: 0.48) }
        else { InventoryTheme.secondaryText }
    }

    var body: some View {
        GeometryReader { geometry in
            let low = Double(values.min() ?? 0)
            let spread = max(1, Double((values.max() ?? 1) - (values.min() ?? 0)))
            let points = values.enumerated().map { index, value in
                CGPoint(x: 3 + CGFloat(index) * max(0, geometry.size.width - 6) / CGFloat(max(1, values.count - 1)),
                        y: geometry.size.height - 3 - CGFloat((Double(value) - low) / spread) * max(0, geometry.size.height - 6))
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(tone, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle().fill(tone).frame(width: 4, height: 4).position(last)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .accessibilityLabel(tr("近 12 小时价格趋势"))
    }
}

@MainActor private final class RecoveryMarketState: ObservableObject {
    struct Sale: Identifiable {
        let id = UUID()
        let material: RecoveryMaterial?
        let hour: Int64
        let layout: InventoryLayout
        let available: Int
    }
    @Published var sale: Sale?
    @Published var quantity = ""

}

@MainActor struct RecoveryMarketView: View {
    @ObservedObject var store: InventoryStore
    @StateObject private var state = RecoveryMarketState()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let hour = RecoveryMaterial.marketHour(at: context.date)
            let remaining = max(1, Int(ceil(Double(hour + 1) * 3600 - context.date.timeIntervalSince1970)))
            let total = store.layout.recoverySale(nil, hour: hour)
            let staples: [RecoveryMaterial] = [.fineAsh, .ashClump, .cigaretteButt, .emptyPack]
            let materials = RecoveryMaterial.allCases.filter { material in
                material != .premiumEmptyPack && (staples.contains(material)
                    || store.layout.recoverySale(material, hour: hour).count > 0)
            }
            VStack(alignment: .leading, spacing: 20) {
                recoveryHeader(total: total, remaining: remaining, hour: hour)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("逐件回收行情")).font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text(tr("每小时浮动报价 · 出售所得即时入账")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(tr("{{0}} 类物件", materials.count)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 390), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(materials) { material in
                        row(material: material, hour: hour) {
                            Text(tr(material.kind.title)).font(.system(size: 15, weight: .semibold, design: .rounded))
                            if store.layout.items.contains(where: { $0.kind == material.kind && $0.isLegacyAshStack }) {
                                Text(tr("含旧批次物件")).font(.system(size: 10, weight: .medium)).foregroundStyle(InventoryTheme.accentBright)
                            }
                        }
                    }
                }
                Label(tr("空烟盒可以直接回收，也可以留在背包工坊继续合成。"), systemImage: "sparkles")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $state.sale) { sale in
            saleSheet(sale)
        }
    }

    private func recoveryHeader(total: RecoverySale, remaining: Int, hour: Int64) -> some View {
        HStack(spacing: 19) {
            RecoveryMaterialArt(material: .mysteryJunk)
                .frame(width: 104, height: 104)
                .padding(7)
                .background(LinearGradient(colors: [InventoryTheme.backgroundTop, InventoryTheme.panelTop], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(InventoryTheme.outline.opacity(0.65), lineWidth: 1))
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("回收集市")).font(.system(size: 23, weight: .semibold, design: .rounded))
                Text(tr("零碎烟火，也能换成一笔踏实收入。"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Label(tr("{{0}} 件在手", total.count), systemImage: "shippingbox")
                    Label(tr("腾出 {{0}} 格", total.slots), systemImage: "square.grid.2x2")
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            VStack(alignment: .trailing, spacing: 8) {
                Text(tr("全部卖出可得")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Text(recoveryMoney(total.cents)).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(InventoryTheme.gold)
                Button(tr("一并出售")) {
                    state.quantity = String(total.count)
                    state.sale = .init(material: nil, hour: hour, layout: store.layout, available: total.count)
                }.buttonStyle(PlayerHubButtonStyle(prominent: total.count > 0)).disabled(total.count == 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .playerHubSurface(.panel, radius: 20)
        .overlay(alignment: .top) {
            Label(tr("报价更新 {{0}}分 {{1}}秒", remaining / 60, remaining % 60), systemImage: "clock")
                .font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(InventoryTheme.accentBright)
                .padding(.horizontal, 10).padding(.vertical, 6).playerHubSurface(.inset, in: Capsule())
                .offset(y: -14)
        }
        .padding(.top, 12)
    }

    private func saleSheet(_ sale: RecoveryMarketState.Sale) -> some View {
        let quantity = Int(state.quantity.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let valid = (1...sale.available).contains(quantity)
        let sellAll = sale.material == nil
        let quote = sale.layout.recoverySale(sale.material, quantity: sellAll ? nil : quantity, hour: sale.hour)
        return VStack(alignment: .leading, spacing: 16) {
            Text(tr("确认出售回收物？")).font(.title3.weight(.semibold))
            if let material = sale.material {
                HStack {
                    Text(material.title)
                    Spacer()
                    TextField(tr("出售数量"), text: $state.quantity)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Stepper(tr("出售数量"), value: Binding(
                        get: { max(1, min(sale.available, quantity)) },
                        set: { state.quantity = String($0) }
                    ), in: 1...sale.available)
                    .labelsHidden()
                    Button(tr("最大")) { state.quantity = String(sale.available) }
                        .disabled(quantity == sale.available)
                }
                Text(tr("可出售 {{0}} 个 · 按入库顺序结算", sale.available))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(tr("全部回收物 · {{0}} 个", quote.count)).foregroundStyle(.secondary)
            }
            HStack {
                Text(tr("出售可得"))
                Spacer()
                Text(valid ? recoveryMoney(quote.cents) : "—")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(InventoryTheme.gold)
            }
            Divider()
            HStack {
                Spacer()
                Button(tr("取消"), role: .cancel) { state.sale = nil }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(PlayerHubButtonStyle())
                Button(tr("出售")) {
                    store.sellRecovery(quote, sellAll: sellAll)
                    state.sale = nil
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PlayerHubButtonStyle(prominent: true))
                .disabled(!valid)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    private func row<Content: View>(material: RecoveryMaterial?, hour: Int64,
                                    @ViewBuilder content: () -> Content) -> some View {
        let quote = store.layout.recoverySale(material, hour: hour)
        return VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                if let material {
                    RecoveryMaterialArt(material: material)
                        .padding(5).frame(width: 82, height: 82)
                        .playerHubSurface(.display, radius: 15)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 7, content: content)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(tr("本类可得")).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Text(recoveryMoney(quote.cents)).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(InventoryTheme.gold)
                    Text(tr("库存 {{0}} 件", quote.count)).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            if let material {
                let price = material.priceCents(hour: hour)
                let change = price - material.priceCents(hour: hour - 1)
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("单件行情")).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        Text(recoveryMoney(price)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(InventoryTheme.gold)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("较上时")).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        Text(change == 0 ? tr("持平") : tr(change > 0 ? "上涨 {{0}}" : "回落 {{0}}", recoveryMoney(abs(change))))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(change > 0 ? Color(red: 0.96, green: 0.31, blue: 0.34) : change < 0 ? Color(red: 0.24, green: 0.78, blue: 0.48) : InventoryTheme.secondaryText)
                    }
                    Spacer(minLength: 2)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(tr("近十二时辰")).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        RecoveryPriceSparkline(values: (0..<12).map { material.priceCents(hour: hour - Int64(11 - $0)) }, change: change)
                            .frame(width: 112, height: 29)
                    }
                }
            }
            HStack {
                Label(tr("腾出 {{0}} 格", quote.slots), systemImage: "square.grid.2x2")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button(tr("出售此类")) {
                    state.quantity = String(quote.count)
                    state.sale = .init(material: material, hour: hour, layout: store.layout, available: quote.count)
                }.buttonStyle(PlayerHubButtonStyle(prominent: quote.count > 0)).disabled(quote.count == 0)
            }
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 188, alignment: .leading)
        .playerHubSurface(.panel, radius: 17)
    }
}
