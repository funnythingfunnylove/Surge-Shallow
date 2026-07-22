import XCTest
@testable import SurgeProfileRelayCore

final class GitHubRuleRepositoryTests: XCTestCase {
    func testRepositoryURLParserSupportsRootTreeAndBlobURLs() throws {
        XCTAssertEqual(
            try GitHubRepositoryURLParser.parse("https://github.com/owner/rules"),
            GitHubRepositoryLocation(owner: "owner", repository: "rules")
        )
        XCTAssertEqual(
            try GitHubRepositoryURLParser.parse(
                "https://github.com/owner/rules/tree/main/rule/Surge"
            ),
            GitHubRepositoryLocation(
                owner: "owner",
                repository: "rules",
                reference: "main",
                path: "rule/Surge"
            )
        )
        XCTAssertEqual(
            try GitHubRepositoryURLParser.parse(
                "https://github.com/owner/rules/blob/main/Advertising.list"
            ),
            GitHubRepositoryLocation(
                owner: "owner",
                repository: "rules",
                reference: "main",
                path: "Advertising.list",
                selectsSingleFile: true
            )
        )
        XCTAssertThrowsError(try GitHubRepositoryURLParser.parse("https://example.com/owner/rules"))
    }

    func testTreeEntriesAreFilteredAndMappedToRawRuleURLs() {
        let location = GitHubRepositoryLocation(
            owner: "owner",
            repository: "rules",
            reference: "main",
            path: "Surge"
        )
        let entries = [
            TreeEntry(path: "README.md", type: "blob", size: 20),
            TreeEntry(path: "Surge/Advertising.list", type: "blob", size: 100),
            TreeEntry(path: "Surge/Streaming.yaml", type: "blob", size: 200),
            TreeEntry(path: "Surge/Profile.conf", type: "blob", size: 300),
            TreeEntry(path: "Clash/Other.list", type: "blob", size: 400),
            TreeEntry(path: "Surge/nested", type: "tree", size: nil)
        ]

        let files = GitHubRuleRepositoryClient.ruleFiles(
            from: entries,
            location: location,
            reference: "main"
        )

        XCTAssertEqual(files.map(\.path), [
            "Surge/Advertising.list",
            "Surge/Profile.conf",
            "Surge/Streaming.yaml"
        ])
        XCTAssertEqual(files[0].suggestedFormat, .automatic)
        XCTAssertEqual(files[1].suggestedFormat, .surgeProfile)
        XCTAssertEqual(files[2].suggestedFormat, .clashPayload)
        XCTAssertEqual(
            files[0].downloadURL,
            "https://raw.githubusercontent.com/owner/rules/main/Surge/Advertising.list"
        )
    }
}
