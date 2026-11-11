import XCTest
@testable import BoneShellKit

@MainActor
final class ShellRulesTests: XCTestCase {
    func testAutomaticUsesSystemGlassWhenSupported() {
        let result = ShellMaterials.resolve(.automatic, supportsSystemGlass: true, reduceTransparency: false)
        XCTAssertEqual(result.requested, .automatic)
        XCTAssertEqual(result.resolved, .systemGlass)
        XCTAssertNil(result.reason)
    }

    func testAutomaticUsesSystemDefaultOnOldOS() {
        let result = ShellMaterials.resolve(.automatic, supportsSystemGlass: false, reduceTransparency: false)
        XCTAssertEqual(result.requested, .automatic)
        XCTAssertEqual(result.resolved, .systemDefault)
        XCTAssertNil(result.reason)
    }

    func testExplicitGlassFallsBackWithReasonOnOldOS() {
        let result = ShellMaterials.resolve(.systemGlass, supportsSystemGlass: false, reduceTransparency: false)
        XCTAssertEqual(result.requested, .systemGlass)
        XCTAssertEqual(result.resolved, .frostedGlass)
        XCTAssertFalse(result.reason?.isEmpty ?? true)
    }

    func testExplicitGlassStaysGlassWhenSupported() {
        let result = ShellMaterials.resolve(.systemGlass, supportsSystemGlass: true, reduceTransparency: false)
        XCTAssertEqual(result.resolved, .systemGlass)
        XCTAssertNil(result.reason)
    }

    func testReduceTransparencyOverridesEveryMaterialAndCapability() {
        for supported in [false, true] {
            for requested in ShellMaterial.allCases {
                let result = ShellMaterials.resolve(
                    requested, supportsSystemGlass: supported, reduceTransparency: true
                )
                XCTAssertEqual(result.requested, requested)
                XCTAssertEqual(result.resolved, .solid)
                if requested != .solid { XCTAssertFalse(result.reason?.isEmpty ?? true) }
            }
        }
    }

    func testExplicitNonGlassMaterialsArePreserved() {
        for supported in [false, true] {
            for material in [ShellMaterial.systemDefault, .frostedGlass, .solid] {
                let result = ShellMaterials.resolve(
                    material, supportsSystemGlass: supported, reduceTransparency: false
                )
                XCTAssertEqual(result.requested, material)
                XCTAssertEqual(result.resolved, material)
                XCTAssertNil(result.reason)
            }
        }
    }

    func testPriorityChoosesHighestAndRetainsInputDisplayOrder() {
        let actions = [action("a", 1), action("b", 9), action("c", 4), action("d", 7)]
        XCTAssertEqual(ShellActionLayout.visibleIDs(actions: actions, maximumVisible: 2), ["b", "d"])
        XCTAssertEqual(ShellActionLayout.visibleIDs(actions: actions, maximumVisible: 3), ["b", "c", "d"])
    }

    func testEqualPriorityRetainsFirstInputs() {
        let actions = [action("c", 2), action("a", 2), action("b", 2)]
        XCTAssertEqual(ShellActionLayout.visibleIDs(actions: actions, maximumVisible: 2), ["c", "a"])
    }

    func testDuplicateIDUsesFirstOccurrenceBeforePrioritySelection() {
        let actions = [action("a", 0), action("a", 100), action("b", 10), action("c", 5)]
        XCTAssertEqual(ShellActionLayout.visibleIDs(actions: actions, maximumVisible: 2), ["b", "c"])
        XCTAssertEqual(ShellActionLayout.visibleIDs(actions: actions, maximumVisible: 3), ["a", "b", "c"])
    }

    func testZeroAndNegativeCapacityReturnNoVisibleActions() {
        for capacity in [0, -1, Int.min] {
            XCTAssertEqual(ShellActionLayout.visibleIDs(actions: [action("a")], maximumVisible: capacity), [])
        }
        XCTAssertEqual(ShellActionLayout.visibleIDs(actions: [], maximumVisible: 4), [])
    }

    func testUnboundedCapacityDeduplicatesAndPreservesInputOrder() {
        let actions = [action("c", -3), action("a", 9), action("b", 4), action("a", 12)]
        XCTAssertEqual(ShellActionLayout.visibleIDs(actions: actions, maximumVisible: Int.max), ["c", "a", "b"])
    }

    func testDisabledActionKeepsItsPlaceAndHandlerIsNotInvokedByLayout() {
        var invocationCount = 0
        let disabled = NavigationAction(
            id: "disabled", title: "Disabled", symbol: "lock", priority: 10, isEnabled: false
        ) { invocationCount += 1 }
        XCTAssertEqual(
            ShellActionLayout.visibleIDs(actions: [action("a"), disabled], maximumVisible: 1),
            ["disabled"]
        )
        XCTAssertEqual(invocationCount, 0)
        XCTAssertFalse(disabled.isEnabled)
    }

    private func action(_ id: String, _ priority: Int = 0) -> NavigationAction {
        NavigationAction(id: id, title: id, symbol: "star", priority: priority) {}
    }
}
