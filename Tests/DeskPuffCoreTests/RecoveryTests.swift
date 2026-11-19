import Foundation
import XCTest
@testable import DeskPuffCore

final class RecoveryTests: XCTestCase {
    func testReleaseBatchesContinueAcrossFramesAndSurviveEncoding() throws {
        let first = UUID(), second = UUID()
        var layout = InventoryLayout()
        XCTAssertEqual(layout.addRecovery(.fineAsh, count: 4, batchID: first), 4)
        layout = try JSONDecoder().decode(InventoryLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(layout.addRecovery(.fineAsh, count: 15, batchID: second), 15)
        XCTAssertEqual(layout.addRecovery(.fineAsh, count: 6, batchID: first), 6)
        XCTAssertEqual(layout.items.map(\.recoveryCount), [10, 15])
        XCTAssertEqual(layout.mergeRecovery(from: layout.items[1].id, into: layout.items[0].id), 15)
        XCTAssertEqual(layout.items.map(\.recoveryCount), [25])
    }

    func testManualMergeFillsTargetAndKeepsOverflowInSource() {
        var layout = InventoryLayout()
        layout.addRecovery(.fineAsh, count: 45)
        layout.addRecovery(.fineAsh, count: 15)
        let target = layout.items[0].id, source = layout.items[1].id
        XCTAssertEqual(layout.mergeRecovery(from: source, into: target), 5)
        XCTAssertEqual(layout.items.map(\.recoveryCount), [50, 10])
        XCTAssertEqual(layout.mergeRecovery(from: source, into: target), 0)
    }

    func testCraftReusesFreedCellsAndRollsBackIfThereIsNoRoom() {
        var layout = InventoryLayout(columns: 1, rows: 4)
        layout.addRecovery(.ashClump, count: 2)
        layout.addRecovery(.cigaretteButt, count: 2)
        let selection: [RecoveryIngredient: Int] = [.material(.ashClump): 1, .material(.cigaretteButt): 1]
        let before = layout
        XCTAssertEqual(layout.mixRecoveryMaterials(selection), .noSpace)
        XCTAssertEqual(layout, before)
        layout.setRecoveryCount(1, for: layout.items[0].id)
        XCTAssertEqual(layout.mixRecoveryMaterials(selection), .crafted(.mysteryJunk, count: 1))
        XCTAssertEqual(layout.items.map(\.kind), [.cigaretteButt, .mysteryJunk])
        XCTAssertEqual(layout.items.map(\.recoveryCount), [1, 1])
        XCTAssertTrue(layout.hasValidStoredPlacements)
    }

    func testPartialQuotePricesEachBatchAndCountsOnlyFreedCells() {
        let legacy = InventoryItem(kind: .fineAsh, styleID: "fineAsh", state: Data([2]))
        var layout = InventoryLayout(items: [legacy])
        layout.addRecovery(.fineAsh, count: 10)
        let hour: Int64 = 28
        let recent = layout.items[1]
        XCTAssertEqual(layout.recoveryMergeCount(from: recent, into: legacy), 0)
        let quote = layout.recoverySale(.fineAsh, quantity: 3, hour: hour)
        XCTAssertEqual(quote.lines.map(\.count), [2, 1])
        XCTAssertEqual(quote.count, 3)
        XCTAssertEqual(quote.slots, 1)
        XCTAssertEqual(quote.cents, RecoveryMaterial.fineAsh.priceCents(hour: hour) * 21)
    }

    func testBrandsRemainDistinctAndPartlyUsedBoxesCanBeCrafted() throws {
        var layout = InventoryLayout(columns: 8, rows: 6)
        let zhonghua = "user:zhonghua-classic", yuxi = "user:yuxi-hexie"
        let open = InventoryItem(kind: .cigaretteBox, styleID: zhonghua, state: Data(#"{"remaining":7}"#.utf8))
        var deployed = InventoryItem(kind: .cigaretteBox, styleID: yuxi)
        deployed.location = .desktop
        layout.items = [open, deployed]
        layout.addRecovery(.premiumEmptyPack, count: 1, styleID: yuxi)
        layout.addRecovery(.cigaretteButt, count: 2)
        XCTAssertEqual(layout.craftingStock[.pack(styleID: zhonghua)], 1)
        XCTAssertEqual(layout.craftingStock[.pack(styleID: yuxi)], 1)
        XCTAssertEqual(layout.mixRecoveryMaterials([.pack(styleID: zhonghua): 1, .material(.fineAsh): 1]),
                       .crafted(.redFoilMisprint, count: 1))
        XCTAssertEqual(layout.mixRecoveryMaterials([.material(.fineAsh): 1, .pack(styleID: yuxi): 1]),
                       .crafted(.celadonSmokeMark, count: 1))
        XCTAssertFalse(layout.items.contains { $0.id == open.id })
        XCTAssertTrue(layout.items.contains(deployed))
        let decoded = try JSONDecoder().decode(InventoryLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(decoded.items.map(\.kind), [.cigaretteBox, .redFoilMisprint, .celadonSmokeMark])
    }

    func testBatchCountAndOverageConsumption() {
        let zhonghua = RecoveryIngredient.pack(styleID: "user:zhonghua-classic")
        let yuxi = RecoveryIngredient.pack(styleID: "user:yuxi-hexie")
        let ash = RecoveryIngredient.material(.fineAsh)
        var layout = InventoryLayout()
        layout.addRecovery(.emptyPack, count: 1, styleID: "user:zhonghua-classic")
        layout.addRecovery(.premiumEmptyPack, count: 1, styleID: "user:zhonghua-classic")
        layout.addRecovery(.emptyPack, count: 2, styleID: "user:yuxi-hexie")
        layout.addRecovery(.fineAsh, count: 2)
        let original = layout
        XCTAssertEqual(layout.mixRecoveryMaterials([zhonghua: 2, yuxi: 2, ash: 2]), .crafted(.redBlueOverprint, count: 2))
        XCTAssertEqual(layout.items.map(\.recoveryCount), [2])
        layout = original
        XCTAssertEqual(layout.mixRecoveryMaterials([zhonghua: 2, yuxi: 1, ash: 1]), .crafted(.redBlueOverprint, count: 1))
        XCTAssertNil(layout.craftingStock[zhonghua])
        XCTAssertEqual(layout.craftingStock[yuxi], 1)
        XCTAssertEqual(layout.craftingStock[ash], 1)
    }

    func testUnknownCombinationAndLegacyScrapCanBeSold() {
        var layout = InventoryLayout(items: [InventoryItem(kind: .mysteryJunk, styleID: "mysteryJunk")])
        layout.addRecovery(.fineAsh, count: 3)
        let before = layout
        XCTAssertEqual(layout.mixRecoveryMaterials([.material(.fineAsh): 4]), .missingMaterials)
        XCTAssertEqual(layout, before)
        XCTAssertEqual(layout.mixRecoveryMaterials([.material(.fineAsh): 2]), .crafted(.mysteryJunk, count: 2))
        let sale = layout.recoverySale(.mysteryJunk, hour: 4)
        XCTAssertEqual(sale.count, 3)
        XCTAssertGreaterThan(sale.cents, 0)
    }

    func testSalvageKeepsBoxStyleAndReusesTheSameMarketCategory() {
        let full = InventoryItem(kind: .cigaretteBox, styleID: "box", state: Data(#"{"remaining":1}"#.utf8))
        var layout = InventoryLayout(items: [full])
        XCTAssertFalse(layout.salvageEmptyPack(full.id))
        layout.items[0].state = Data(#"{"remaining":0}"#.utf8)
        XCTAssertTrue(layout.salvageEmptyPack(full.id))
        XCTAssertEqual(layout.items.first?.kind, .emptyPack)
        XCTAssertEqual(layout.items.first?.styleID, "box")
        layout.addRecovery(.premiumEmptyPack, count: 1, styleID: "older box")
        XCTAssertEqual(layout.recoverySale(.emptyPack, hour: 0).count, 2)
    }

    func testHourlyRatesKeepButtsCheapAndRewardCrafting() {
        var buttPrices: Set<Int> = []
        for hour: Int64 in 0..<336 {
            let butt = RecoveryMaterial.cigaretteButt.priceCents(hour: hour)
            let fine = RecoveryMaterial.fineAsh.priceCents(hour: hour)
            let clump = RecoveryMaterial.ashClump.priceCents(hour: hour)
            XCTAssertTrue((30...90).contains(butt))
            XCTAssertGreaterThan(fine, clump)
            for recipe in RecoveryRecipe.all {
                let inputPrice = recipe.ingredients.reduce(0) { price, ingredient in
                    switch ingredient {
                    case .material(let material): price + material.priceCents(hour: hour)
                    case .pack: price + RecoveryMaterial.emptyPack.priceCents(hour: hour)
                    }
                }
                XCTAssertGreaterThan(recipe.product.priceCents(hour: hour), inputPrice)
            }
            buttPrices.insert(butt)
        }
        XCTAssertGreaterThan(buttPrices.count, 30)
    }

    func testCatalogHasFortyDistinctRecipesAndCoversEveryPreset() {
        XCTAssertEqual(RecoveryRecipe.all.count, 40)
        XCTAssertEqual(Set(RecoveryRecipe.products).count, 40)
        let tierCounts = Dictionary(grouping: RecoveryRecipe.all, by: \.valueTier).mapValues(\.count)
        XCTAssertEqual(tierCounts[.low], 22)
        XCTAssertEqual(tierCounts[.medium], 10)
        XCTAssertEqual(tierCounts[.high], 8)
        XCTAssertTrue(RecoveryRecipe.all.filter { $0.valueTier == .low }.allSatisfy { $0.ingredients.count == 2 })
        XCTAssertTrue(RecoveryRecipe.all.filter { $0.valueTier == .medium }.allSatisfy { $0.ingredients.count == 3 })
        XCTAssertTrue(RecoveryRecipe.all.filter { $0.valueTier == .high }.allSatisfy { $0.ingredients.count >= 3 })
        let combinations = RecoveryRecipe.all.map { Set($0.ingredients) }
        XCTAssertEqual(Set(combinations).count, combinations.count)
        let expectedStyles: Set<String> = [
            "user:zhonghua-classic", "user:yuxi-hexie", "user:huanghelou-1916-ruyi",
            "user:huangjinye-tianye", "user:nanjing-xuanhemen", "user:furongwang-hard",
            "user:liqun-new", "user:shuangxi-classic1906", "user:hongtashan-classic1956",
            "user:diamond-lotus-hard", "user:baisha-hard"
        ]
        let coveredStyles = Set(RecoveryRecipe.all.flatMap(\.ingredients).compactMap { ingredient -> String? in
            guard case .pack(let styleID) = ingredient else { return nil }
            return styleID
        })
        XCTAssertEqual(coveredStyles, expectedStyles)
    }
}
