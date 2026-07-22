import XCTest
@testable import SurgeProfileRelayCore

final class RelayPolicyCatalogTests: XCTestCase {
    func testCatalogCombinesBuiltInsProxiesAndGroupsWithoutCaseInsensitiveDuplicates() {
        var shared = SharedProfile.defaults
        shared.proxies = [
            ProxyDefinition(name: "Home", type: "http", parameters: "127.0.0.1, 8080"),
            ProxyDefinition.rawLine("# note")
        ]
        shared.proxyGroups = [
            ProxyDefinition(name: "PROXY", type: "select", parameters: "Home, DIRECT"),
            ProxyDefinition(name: "direct", type: "select", parameters: "Home")
        ]

        XCTAssertEqual(RelayPolicyCatalog.proxyNames(in: shared), ["Home"])
        XCTAssertEqual(RelayPolicyCatalog.groupNames(in: shared), ["PROXY", "direct"])
        XCTAssertEqual(
            RelayPolicyCatalog.allNames(in: shared),
            ["DIRECT", "REJECT", "REJECT-DROP", "REJECT-TINYGIF", "REJECT-NO-DROP", "Home", "PROXY"]
        )
    }

    func testMemberRenamePreservesAdvancedGroupOptions() {
        let result = RelayPolicyCatalog.replacingMemberNames(
            in: "OldProxy, DIRECT, policy-priority=\"Premium:0.9\"",
            renames: ["oldproxy": "NewProxy"]
        )

        XCTAssertEqual(
            result,
            "NewProxy, DIRECT, policy-priority=\"Premium:0.9\""
        )
    }
}
