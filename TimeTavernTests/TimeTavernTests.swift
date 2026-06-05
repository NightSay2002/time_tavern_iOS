import XCTest
import ZIPFoundation
@testable import TimeTavern

final class TimeTavernTests: XCTestCase {
    func testAppTabsKeepExpectedNavigationLabels() {
        XCTAssertEqual(AppTab.allCases.count, 5)
        XCTAssertEqual(AppTab.allCases.map(\.title), ["對話", "角色", "存檔", "工房", "設定"])
    }

    func testVisualNovelComposerSendDisabledState() {
        XCTAssertTrue(VisualNovelComposer.isSendDisabled(isGenerating: false, text: "   \n"))
        XCTAssertFalse(VisualNovelComposer.isSendDisabled(isGenerating: false, text: "開始故事"))
        XCTAssertFalse(VisualNovelComposer.isSendDisabled(isGenerating: true, text: ""))
    }

    func testCharacterStatusChipTitle() {
        XCTAssertEqual(CharacterStatusCard.statusTitle(isReady: false), "Idle")
        XCTAssertEqual(CharacterStatusCard.statusTitle(isReady: true), "Ready")
    }

    func testSecretStoreRoundTrip() throws {
        let store = SecretStore()
        try store.save("test-key-\(UUID().uuidString)", for: .deepSeekAPIKey)
        XCTAssertTrue(try store.read(.deepSeekAPIKey).hasPrefix("test-key-"))
        try store.delete(.deepSeekAPIKey)
        XCTAssertEqual(try store.read(.deepSeekAPIKey), "")
    }

    func testConversationPromptIncludesRoleCardSectionsAndLorebook() throws {
        var state = AppState()
        var card = RoleCard()
        card.name = "千夜"
        card.promptModeId = "multi"
        card.customSections = [CustomSection(name: "性格", content: "冷靜但毒舌")]
        card.lorebooks = [LorebookEntry(title: "古井", keywords: ["古井"], content: "古井連接舊時間線。")]
        state.roleCards = [card]
        state.activeRoleCardId = card.id
        state.userProfile.userName = "旅人"

        let messages = try ConversationEngine().buildPromptMessages(state: state, userInput: "我走到古井旁。")

        XCTAssertEqual(messages.first?.role, "system")
        XCTAssertTrue(messages.first?.content.contains("千夜") == true)
        XCTAssertTrue(messages.first?.content.contains("冷靜但毒舌") == true)
        XCTAssertTrue(messages.first?.content.contains("古井連接舊時間線") == true)
        XCTAssertEqual(messages.last?.role, "user")
    }

    func testCompressionCopiesUserInputWhenTriggerMatches() {
        var state = AppState()
        var card = RoleCard()
        card.promptModeId = "multi"
        state.roleCards = [card]
        state.activeRoleCardId = card.id
        state.conversation = [ConversationMessage(role: .user, content: "之前", turnNumber: 1)]
        state.promptModes = [
            PromptModeConfig(
                id: "multi",
                name: "多角色",
                mode: "multi",
                dialogueContextRounds: 20,
                compressionProfiles: [
                    CompressionProfile(
                        id: "copy",
                        name: "複製",
                        triggerActions: [
                            CompressionTriggerAction(action: .copyUserInput, keywords: "秘密")
                        ]
                    )
                ]
            )
        ]

        let modes = ConversationEngine().applyCompressionIfNeeded(state: state, latestUserInput: "這是一個秘密")

        XCTAssertEqual(modes.first?.compressionProfiles.first?.summary, "這是一個秘密")
    }

    func testExportBundleCreatesZip() throws {
        let service = ImportExportService()
        var state = AppState()
        state.roleCards = [RoleCard(name: "測試角色")]

        let url = try service.exportBundle(state: state)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNoThrow(try Archive(url: url, accessMode: .read, pathEncoding: nil))
    }
}
