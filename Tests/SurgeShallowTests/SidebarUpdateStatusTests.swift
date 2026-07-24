import SurgeProfileRelayCore
import XCTest
@testable import SurgeShallow

final class SidebarUpdateStatusTests: XCTestCase {
    func testUserFacingTitlesDescribeGenerationInsteadOfRulesetUpdates() {
        XCTAssertEqual(SidebarUpdateStatus.current.title, "Profile 已生成")
        XCTAssertEqual(SidebarUpdateStatus.warning.title, "已生成，有提示")
        XCTAssertEqual(SidebarUpdateStatus.failed.title, "合并生成失败")
        XCTAssertEqual(SidebarUpdateStatus.pending.title, "等待合并生成")
    }

    func testRefreshingStatusTakesPriorityAndKeepsProgressMessage() {
        XCTAssertEqual(
            SidebarUpdateStatus.resolve(
                isRefreshing: true,
                statusMessage: "正在合并规则…",
                enabledSourceStates: [.failed],
                latestOutcome: .failure,
                hasSuccessfulUpdate: false
            ),
            .refreshing("正在合并规则…")
        )
    }

    func testFailureTakesPriorityOverOtherRestingStates() {
        XCTAssertEqual(
            SidebarUpdateStatus.resolve(
                isRefreshing: false,
                statusMessage: "准备就绪",
                enabledSourceStates: [.current, .failed, .never],
                latestOutcome: .success,
                hasSuccessfulUpdate: true
            ),
            .failed
        )
    }

    func testWarningRepresentsStaleCacheOrWarningOutcome() {
        XCTAssertEqual(
            SidebarUpdateStatus.resolve(
                isRefreshing: false,
                statusMessage: "准备就绪",
                enabledSourceStates: [.current, .staleCache],
                latestOutcome: .success,
                hasSuccessfulUpdate: true
            ),
            .warning
        )
    }

    func testSuccessfulMergeTakesPriorityOverRemoteReferenceStates() {
        XCTAssertEqual(
            SidebarUpdateStatus.resolve(
                isRefreshing: false,
                statusMessage: "准备就绪",
                enabledSourceStates: [.current, .never],
                latestOutcome: .success,
                hasSuccessfulUpdate: true
            ),
            .current
        )
    }

    func testNeverUpdatedSourceWithoutSuccessfulMergeRemainsPending() {
        XCTAssertEqual(
            SidebarUpdateStatus.resolve(
                isRefreshing: false,
                statusMessage: "准备就绪",
                enabledSourceStates: [.current, .never],
                latestOutcome: nil,
                hasSuccessfulUpdate: false
            ),
            .pending
        )
    }

    func testSuccessfulHistoryAndCurrentSourcesAreCurrent() {
        XCTAssertEqual(
            SidebarUpdateStatus.resolve(
                isRefreshing: false,
                statusMessage: "准备就绪",
                enabledSourceStates: [.current, .updated],
                latestOutcome: .success,
                hasSuccessfulUpdate: true
            ),
            .current
        )
    }

    func testNoEnabledSourcesUsesEmptyState() {
        XCTAssertEqual(
            SidebarUpdateStatus.resolve(
                isRefreshing: false,
                statusMessage: "准备就绪",
                enabledSourceStates: [],
                latestOutcome: nil,
                hasSuccessfulUpdate: false
            ),
            .empty
        )
    }
}
