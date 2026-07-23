import SurgeProfileRelayCore
import XCTest
@testable import SurgeShallow

final class SidebarUpdateStatusTests: XCTestCase {
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
