import XCTest
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

    @MainActor
    func testCreateRoleCardStartsWithEmptyCustomSections() {
        let store = TimeTavernStore()

        store.createRoleCard()

        XCTAssertEqual(store.state.roleCards.first?.customSections, [])
    }

    func testRoleCardEditorDeleteOpeningFallsBackToEmptyOpening() {
        var card = RoleCard()
        card.openingDialogues = [OpeningDialogue(id: "opening_1", name: "開場一", content: "hi")]
        card.activeOpeningDialogueId = "opening_1"

        let updated = RoleCardEditorView.cardByDeletingOpening(card, openingID: "opening_1")

        XCTAssertEqual(updated.openingDialogues.count, 1)
        XCTAssertEqual(updated.activeOpeningDialogueId, updated.openingDialogues.first?.id)
        XCTAssertEqual(updated.openingDialogues.first?.content, "")
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

    func testBundledWebDefaultsDecodeSanitizedRoleCardsAndPromptModes() throws {
        let state = try BundledWebDefaultsService.loadDefaults(from: webDefaultsURL())

        XCTAssertEqual(state.roleCards.count, 9)
        XCTAssertEqual(state.promptModes.map(\.id).sorted(), ["multi", "no_role", "single"])
        XCTAssertEqual(state.userProfile.userName, "時分")
        XCTAssertFalse(state.userProfile.extraPrompt.isEmpty)
        XCTAssertTrue(state.roleCards.allSatisfy { $0.customSections.isEmpty })
    }

    func testWebPromptModeReasonerHistoryObjectAndCompressionProfilesDecode() throws {
        let data = try Data(contentsOf: webDefaultsURL().appendingPathComponent("prompts/modular/multi.json"))
        let mode = try JSONDecoder().decode(PromptModeConfig.self, from: data)

        XCTAssertEqual(mode.id, "multi")
        XCTAssertFalse(mode.reasonerHistoryConfig.mainRules.isEmpty)
        XCTAssertFalse(mode.reasonerHistoryConfig.contextRules.isEmpty)
        XCTAssertGreaterThanOrEqual(mode.compressionProfiles.count, 2)
        XCTAssertEqual(mode.compressionProfiles.first?.contextScope, .textOnly)
        XCTAssertFalse(mode.compressionProfiles.first?.contextCompression.models.isEmpty ?? true)
        XCTAssertEqual(mode.compressionProfiles.first?.triggerActions.first?.keywordFollowupAction, .continueReasoner)
    }

    func testOldIOSAppStateJSONStillDecodesWithNewPromptSchema() throws {
        let json = """
        {
          "userProfile": {"userName": "u", "extraPrompt": ""},
          "apiSettings": {},
          "roleCards": [],
          "activeRoleCardId": "",
          "activeAssistantMode": "",
          "promptModes": [
            {
              "id": "multi",
              "name": "多角色",
              "mode": "multi",
              "dialogueContextRounds": 20,
              "mainRules": "old main",
              "outputRules": "old output",
              "reasonerHistory": "legacy",
              "compressionProfiles": [
                {"id": "standard", "name": "標準", "enabled": true, "mainRules": "compress", "models": []}
              ]
            }
          ],
          "conversation": [],
          "savedSessions": [],
          "aiLogs": [],
          "timeTracking": {},
          "novelAIAlbum": []
        }
        """

        let state = try JSONDecoder().decode(AppState.self, from: Data(json.utf8))

        XCTAssertEqual(state.promptModes.first?.reasonerHistoryConfig.mainRules, "old main")
        XCTAssertEqual(state.promptModes.first?.compressionProfiles.first?.contextCompression.mainRules, "compress")
        XCTAssertEqual(state.novelAIStudioSettings.imageSettings.model, NovelAIModelOption.defaultID)
    }

    @MainActor
    func testRestoreDefaultsFallsBackToBundledWebDefaultsPreservesSessionsAlbumAndLogs() {
        let store = TimeTavernStore()
        store.state.savedSessions = [SavedSession(name: "keep")]
        store.state.novelAIAlbum = [NovelAIAlbumItem(prompt: "image", imageData: Data([1, 2, 3]))]
        store.state.aiLogs = [AILogEntry(responsePreview: "log")]

        store.restoreDefaultsPreferLocal()

        XCTAssertEqual(store.state.roleCards.count, 9)
        XCTAssertEqual(store.state.promptModes.count, 3)
        XCTAssertTrue(store.state.savedSessions.contains { $0.name == "keep" })
        XCTAssertTrue(store.state.savedSessions.contains { $0.name == "還原預設前備份" })
        XCTAssertEqual(store.state.novelAIAlbum.count, 1)
        XCTAssertEqual(store.state.aiLogs.count, 1)
    }

    @MainActor
    func testSaveLocalDefaultsAndRestorePreservesSessionsAlbumAndLogs() {
        let store = TimeTavernStore()
        store.state.userProfile = UserProfile(userName: "saved", extraPrompt: "identity")
        store.state.apiSettings.deepSeekModel = "deepseek-chat"
        store.state.roleCards = [RoleCard(id: "saved_card", name: "保存角色")]
        store.state.activeRoleCardId = "saved_card"
        store.state.promptModes = [PromptModeConfig(id: "saved_mode", name: "保存模式", mode: "saved")]
        store.state.novelAIStudioSettings.imageSettings.model = "nai-diffusion-4-5-curated"

        store.saveCurrentAsLocalDefaults()
        store.state.userProfile.userName = "mutated"
        store.state.roleCards = [RoleCard(name: "臨時角色")]
        store.state.promptModes = []
        store.state.savedSessions = [SavedSession(name: "keep")]
        store.state.novelAIAlbum = [NovelAIAlbumItem(prompt: "image", imageData: Data([9]))]
        store.state.aiLogs = [AILogEntry(responsePreview: "log")]

        store.restoreDefaultsPreferLocal()

        XCTAssertEqual(store.state.userProfile.userName, "saved")
        XCTAssertEqual(store.state.apiSettings.deepSeekModel, "deepseek-chat")
        XCTAssertEqual(store.state.roleCards.first?.name, "保存角色")
        XCTAssertEqual(store.state.promptModes.first?.id, "saved_mode")
        XCTAssertEqual(store.state.novelAIStudioSettings.imageSettings.model, "nai-diffusion-4-5-curated")
        XCTAssertTrue(store.state.savedSessions.contains { $0.name == "keep" })
        XCTAssertEqual(store.state.novelAIAlbum.count, 1)
        XCTAssertEqual(store.state.aiLogs.count, 1)
        XCTAssertNotNil(store.state.localDefaults)
    }

    func testNovelAISettingsSnippetExpansionPayloadAndMetadataImport() throws {
        var settings = NovelAIStudioSettings()
        settings.basePrompt = "masterpiece, ||pose||"
        settings.fixedSnippets = [NovelAIPromptSnippet(name: "pose", content: "standing")]
        settings.randomSnippets = [
            NovelAIPromptSnippet(name: "light", content: "moonlight"),
            NovelAIPromptSnippet(name: "light", content: "lantern")
        ]
        settings.characterPrompts = [NovelAICharacterPrompt(name: "A", prompt: "blue hair")]
        settings.imageSettings.seed = 123

        let prompt = NovelAIClient.resolvedPrompt(from: settings, randomIndex: { _ in 1 })
        let request = NovelAIClient.buildImageGenerationRequest(studioSettings: settings, prompt: prompt)
        let metadata = """
        {"input":"new prompt","model":"nai-test","parameters":{"negative_prompt":"bad","width":1024,"height":1024,"steps":30,"scale":6.5,"sampler":"k_euler","cfg_rescale":0.4,"seed":99}}
        """
        let importResult = NovelAIClient.importMetadata(metadata, into: settings)
        let imported = importResult.settings

        XCTAssertEqual(NovelAIModelOption.allCases.count, 6)
        XCTAssertTrue(prompt.contains("standing"))
        XCTAssertTrue(prompt.contains("lantern"))
        XCTAssertTrue(prompt.contains("A: blue hair"))
        XCTAssertEqual(request.parameters.seed, 123)
        XCTAssertEqual(request.model, NovelAIModelOption.defaultID)
        XCTAssertEqual(imported.basePrompt, "new prompt")
        XCTAssertEqual(imported.imageSettings.model, NovelAIModelOption.defaultID)
        XCTAssertNotNil(importResult.fallbackMessage)
        XCTAssertEqual(imported.imageSettings.width, 1024)
        XCTAssertEqual(imported.imageSettings.seed, 99)
    }

    func testJSONRoleCardImportExportRoundTripAndConflictCopy() throws {
        let service = ImportExportService()
        let coverData = Data([1, 2, 3])
        let coverURL = "data:image/png;base64,\(coverData.base64EncodedString())"
        var card = RoleCard(id: "role_1", name: "測試角色")
        card.coverImageData = coverData
        card.coverImageDataURL = coverURL
        card.coverPosition = RoleCardCoverPosition.topCenter.rawValue

        let url = try service.exportRoleCardJSON(card)
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try service.importRoleCardJSON(from: url, existingRoleCards: [card])

        XCTAssertNotEqual(imported.id, card.id)
        XCTAssertEqual(imported.name, "測試角色 副本")
        XCTAssertEqual(imported.coverImageData, coverData)
        XCTAssertEqual(imported.coverPosition, RoleCardCoverPosition.topCenter.rawValue)
    }

    func testJSONRoleCardImportSupportsWebAndSillyTavernFormats() throws {
        let service = ImportExportService()
        let coverData = Data([4, 5, 6])
        let coverURL = "data:image/png;base64,\(coverData.base64EncodedString())"
        let webJSON = """
        {"id":"web_1","name":"網頁角色","mode":"multi","coverImage":"\(coverURL)","coverPosition":"bottom right","customSections":[{"name":"設定","content":"內容","enabled":true}],"openingDialogue":"你好","lorebooks":[{"title":"井","keywords":["井"],"content":"古井"}]}
        """
        let webCard = try service.importRoleCardJSON(from: Data(webJSON.utf8), existingRoleCards: [])

        XCTAssertEqual(webCard.name, "網頁角色")
        XCTAssertEqual(webCard.coverImageData, coverData)
        XCTAssertEqual(webCard.coverPosition, RoleCardCoverPosition.bottomRight.rawValue)
        XCTAssertEqual(webCard.customSections.first?.name, "設定")

        let sillyJSON = """
        {"spec":"chara_card_v2","data":{"name":"ST角色","description":"描述","personality":"性格","first_mes":"開場","alternate_greetings":["替代"],"character_book":{"entries":[{"id":1,"name":"Lore","keys":["key"],"content":"lore text"}]}}}
        """
        let sillyCard = try service.importRoleCardJSON(from: Data(sillyJSON.utf8), existingRoleCards: [])

        XCTAssertEqual(sillyCard.name, "ST角色")
        XCTAssertEqual(sillyCard.customSections.map(\.name), ["描述", "性格"])
        XCTAssertEqual(sillyCard.openingDialogues.count, 2)
        XCTAssertEqual(sillyCard.lorebooks.first?.keywords, ["key"])
    }

    func testJSONModeAndCompressionProfileImportCreateCopiesOnConflict() throws {
        let service = ImportExportService()
        let mode = PromptModeConfig(id: "multi", name: "多角色", mode: "multi")
        let modeData = try JSONEncoder().encode(mode)
        let importedMode = try service.importPromptModeJSON(from: modeData, existingModes: [mode])

        XCTAssertNotEqual(importedMode.id, "multi")
        XCTAssertTrue(importedMode.name.hasPrefix("多角色 副本"))
        XCTAssertNotEqual(importedMode.mode, "multi")

        let profile = CompressionProfile(id: "standard", name: "標準壓縮模型", locked: true)
        let profileData = try JSONEncoder().encode(profile)
        let importedProfile = try service.importCompressionProfileJSON(from: profileData, existingProfiles: [profile])

        XCTAssertNotEqual(importedProfile.id, "standard")
        XCTAssertTrue(importedProfile.name.hasPrefix("標準壓縮模型 副本"))
        XCTAssertFalse(importedProfile.locked)
    }

    func testRoleCardCoverPositionAndPromptUIFlags() throws {
        var card = RoleCard(name: "cover")
        card.coverPosition = RoleCardCoverPosition.bottomCenter.rawValue

        let decoded = try JSONDecoder().decode(RoleCard.self, from: JSONEncoder().encode(card))

        XCTAssertEqual(decoded.coverPosition, RoleCardCoverPosition.bottomCenter.rawValue)
        XCTAssertFalse(PromptRulesEditorView.exposesLegacyFields)
        XCTAssertFalse(PromptModeEditorView.exposesManualRoundEditing)
    }

    private func webDefaultsURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TimeTavern/Resources/WebDefaults")
    }
}
