import XCTest
@testable import DeskPuffCore

final class EconomyTests: XCTestCase {
    private func rules() throws -> EconomyRules {
        let json = #"{"startingCents":4000,"offlineLimitSeconds":28800,"incomeIntervalSeconds":3600,"ranks":[{"id":"bronze","name":"青铜","hourlyCents":2400,"starThresholds":[0,5]},{"id":"silver","name":"白银","hourlyCents":3000,"starThresholds":[10,20]}],"products":[{"id":"box","kind":"cigaretteBox","styleID":"user:box","name":"烟盒","specification":"20 支","priceCents":600}],"bags":[],"bagStyles":[]}"#
        return try JSONDecoder().decode(EconomyRules.self, from: Data(json.utf8))
    }
    func testIncomeIsCappedAndClockRollbackDoesNotPayTwice() throws {
        let rules = try rules(), start = Date(timeIntervalSince1970: 1_700_000_000)
        var state = EconomyState(balanceCents: 0, lastIncomeTime: start)
        state.settle(at: start.addingTimeInterval(3600 * 24), rules: rules)
        XCTAssertEqual(state.balanceCents, 8 * 2400)
        state.settle(at: start, rules: rules)
        state.settle(at: start.addingTimeInterval(3600 * 24), rules: rules)
        XCTAssertEqual(state.balanceCents, 8 * 2400)
    }
    func testIncomePaysOnlyAtHourAndRespectsMidHourPromotion() throws {
        let rules = try rules(), start = Date(timeIntervalSince1970: 1_700_000_000)
        var state = EconomyState(balanceCents: 0, lastIncomeTime: start)
        for second in stride(from: 5, through: 1800, by: 5) { state.settle(at: start.addingTimeInterval(Double(second)), rules: rules) }
        XCTAssertEqual(state.balanceCents, 0)
        state.completedCigarettes = 10
        for second in stride(from: 1805, through: 3600, by: 5) { state.settle(at: start.addingTimeInterval(Double(second)), rules: rules) }
        XCTAssertEqual(state.balanceCents, 2700)
        XCTAssertEqual(state.incomeIntervalElapsed, 0, accuracy: 0.001)
    }
    func testPendingIncomeSurvivesRestartAndOldWalletDecodes() throws {
        let rules = try rules(), start = Date(timeIntervalSince1970: 1_700_000_000)
        var state = EconomyState(balanceCents: 1000, lastIncomeTime: start)
        state.settle(at: start.addingTimeInterval(1800), rules: rules)
        XCTAssertEqual(state.balanceCents, 1000)
        var restored = try JSONDecoder().decode(EconomyState.self, from: JSONEncoder().encode(state))
        restored.settle(at: start.addingTimeInterval(3600), rules: rules)
        XCTAssertEqual(restored.balanceCents, 3400)
        let old = #"{"balanceCents":1234,"completedCigarettes":0,"lastIncomeTime":0,"incomeRemainder":0.5,"ownedBagStages":[0]}"#
        let oldState = try JSONDecoder().decode(EconomyState.self, from: Data(old.utf8))
        XCTAssertEqual(oldState.balanceCents, 1234)
        XCTAssertEqual(oldState.incomeIntervalElapsed, 0)
        XCTAssertEqual(oldState.incomeRemainder, 0.5)
        XCTAssertNil(oldState.ownedBagStyleIDs)
    }
    func testPurchaseDoesNotMutateInputsWhenUnavailable() throws {
        let rules = try rules(), product = try XCTUnwrap(rules.products.first)
        let layout = InventoryLayout(columns: 5, rows: 3)
        let poor = EconomyState(balanceCents: 599)
        XCTAssertThrowsError(try ShopTransaction.prepare(product: product, layout: layout, economy: poor))
        XCTAssertTrue(layout.items.isEmpty); XCTAssertEqual(poor.balanceCents, 599)
        let enough = EconomyState(balanceCents: 600)
        XCTAssertThrowsError(try ShopTransaction.prepare(product: product, layout: InventoryLayout(columns: 1, rows: 1), economy: enough))
        let (purchased, wallet) = try ShopTransaction.prepare(product: product, layout: layout, economy: enough)
        XCTAssertEqual(wallet.balanceCents, 0); XCTAssertEqual(purchased.items.count, 1)
        XCTAssertEqual(purchased.items[0].kind, .cigaretteBox); XCTAssertTrue(purchased.hasValidStoredPlacements)
    }
    func testBagStyleMigrationAndPurchase() throws {
        let old = #"{"balanceCents":150000,"completedCigarettes":0,"lastIncomeTime":0,"incomeRemainder":0,"ownedBagStages":[0,1,2]}"#
        var wallet = try JSONDecoder().decode(EconomyState.self, from: Data(old.utf8))
        wallet.migrateBagStyles(selected: "canvas-mailbag", previouslySelected: ["canvas-mailbag"])
        XCTAssertEqual(Set(wallet.ownedBagStyleIDs ?? []), Set(["urban-sling", "canvas-mailbag"]))
        XCTAssertEqual(wallet.ownedBagStages, [0, 1, 2])
        let offer = try JSONDecoder().decode(BagStyleOffer.self, from: Data(#"{"id":"skin","styleID":"leather-mini","priceCents":120000}"#.utf8))
        let purchased = try ShopTransaction.prepareBagStyle(offer: offer, economy: wallet)
        XCTAssertEqual(purchased.balanceCents, 30000)
        XCTAssertEqual(purchased.activeBagStyleID, "canvas-mailbag")
        XCTAssertTrue(purchased.ownedBagStyleIDs?.contains("leather-mini") == true)
        XCTAssertThrowsError(try ShopTransaction.prepareBagStyle(offer: offer, economy: purchased))
        XCTAssertThrowsError(try ShopTransaction.prepareBagStyle(offer: offer, economy: EconomyState(balanceCents: 0)))
        XCTAssertEqual(try JSONDecoder().decode(EconomyState.self, from: JSONEncoder().encode(purchased)), purchased)
    }
    func testRankBoundariesAndSaveRoundTrip() throws {
        let rules = try rules()
        XCTAssertEqual(rules.progress(completed: 4).star, 1)
        XCTAssertEqual(rules.progress(completed: 5).star, 2)
        XCTAssertEqual(rules.progress(completed: 10).rankIndex, 1)
        let state = EconomyState(balanceCents: 1337, completedCigarettes: 10, ownedBagStages: [0, 2])
        XCTAssertEqual(try JSONDecoder().decode(EconomyState.self, from: JSONEncoder().encode(state)), state)
    }
    func testLegacyInventoryDocumentRetainsItems() throws {
        let original = InventoryDocument(version: 2, layout: InventoryLayout(columns: 5, rows: 3,
            items: [InventoryItem(kind: .cigaretteBox, styleID: "user:box")]), capacityStage: 0, economy: nil)
        let legacy = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InventoryDocument.self, from: legacy)
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.layout, original.layout)
        XCTAssertNil(decoded.economy)
    }
}
