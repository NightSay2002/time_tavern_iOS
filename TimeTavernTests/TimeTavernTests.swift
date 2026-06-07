import XCTest
import UIKit
@testable import TimeTavern

final class TimeTavernTests: XCTestCase {
    func testAppTabsKeepExpectedNavigationLabels() {
        XCTAssertEqual(AppTab.allCases.count, 5)
        XCTAssertEqual(AppTab.allCases.map(\.title), ["對話", "角色", "存檔", "工房", "設定"])
        XCTAssertEqual(AppTab.allCases.map { $0.title(in: .simplified) }, ["对话", "角色", "存档", "工房", "设定"])
    }

    func testVisualNovelComposerSendDisabledState() {
        XCTAssertTrue(VisualNovelComposer.isSendDisabled(isGenerating: false, text: "   \n"))
        XCTAssertFalse(VisualNovelComposer.isSendDisabled(isGenerating: false, text: "開始故事"))
        XCTAssertFalse(VisualNovelComposer.isSendDisabled(isGenerating: true, text: ""))
    }

    func testUILanguageToggleMatchesWebSimplifiedConversionAndPersists() throws {
        let traditional = "簡繁轉換：繁體 UI，設定、對話、存檔與壓縮狀態。"
        let simplified = SettingsView.localizedDisplayText(traditional, language: .simplified)
        let previousLanguage = UIChineseTextConverter.activeLanguage
        defer { UIChineseTextConverter.activeLanguage = previousLanguage }
        UIChineseTextConverter.activeLanguage = .simplified

        XCTAssertEqual(simplified, "简繁转换：繁体 UI，设定、对话、存档与压缩狀态。")
        XCTAssertEqual(SettingsView.localizedDisplayText(traditional, language: .traditional), traditional)
        XCTAssertEqual(uiStatic("設定與對話"), "设定与对话")
        XCTAssertEqual(UILanguageMode.simplified.title(in: .simplified), "简体")
        XCTAssertTrue(SettingsView.uiLanguageHelp.contains("不會改寫角色卡"))

        var state = AppState()
        state.uiLanguage = .simplified
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppState.self, from: encoded)
        let legacy = try JSONDecoder().decode(AppState.self, from: Data(#"{"userProfile":{"userName":"u"}}"#.utf8))

        XCTAssertEqual(decoded.uiLanguage, .simplified)
        XCTAssertEqual(legacy.uiLanguage, .traditional)
    }

    func testStaticChineseUILabelsUseDisplayConverter() throws {
        let viewsPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TimeTavern/Views.swift")
        let source = try String(contentsOf: viewsPath)
        let pattern = #"\b(Text|Button|Label|Section|Picker|Toggle|TextField|SecureField|Stepper|navigationTitle|accessibilityLabel|confirmationDialog|alert)\("[^"\n]*\p{Han}"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)

        XCTAssertTrue(NovelAITargetedImageImportSection.mirrorsWebDropChoiceActions)
        XCTAssertEqual(regex.numberOfMatches(in: source, range: range), 0)
    }

    func testDeepSeekKeySetNormalizesAndSelectsMultipleKeys() {
        let keySet = DeepSeekKeySet(primaryKey: " primary ", processingKeys: [" key2 ", "", "key3", "key2"])

        XCTAssertEqual(keySet.allKeys, ["primary", "key2", "key3"])
        XCTAssertEqual(keySet.chatKey(cursor: 0), "primary")
        XCTAssertEqual(keySet.chatKey(cursor: 1), "key2")
        XCTAssertEqual(keySet.chatKey(cursor: 2), "key3")
        XCTAssertEqual(keySet.chatKey(cursor: 3), "primary")
        XCTAssertEqual(keySet.contextCompressionKey(profileIndex: 0), "key2")
        XCTAssertEqual(keySet.contextCompressionKey(profileIndex: 9), "key3")
        XCTAssertEqual(DeepSeekKeySet.decodeProcessingKeys(DeepSeekKeySet.encodeProcessingKeys([" a ", "b"])), ["a", "b"])
    }

    @MainActor
    func testStoreRotatesDeepSeekChatKeys() {
        let store = TimeTavernStore()
        store.deepSeekKey = "primary"
        store.deepSeekProcessingKeys = ["key2", "key3"]

        XCTAssertEqual(store.nextDeepSeekChatKey(), "primary")
        XCTAssertEqual(store.nextDeepSeekChatKey(), "key2")
        XCTAssertEqual(store.nextDeepSeekChatKey(), "key3")
        XCTAssertEqual(store.nextDeepSeekChatKey(), "primary")
    }

    @MainActor
    func testMessageEditAndFeedbackMatchWebActions() {
        let store = TimeTavernStore()
        store.state.conversation = [
            ConversationMessage(id: "m1", role: .assistant, content: "old")
        ]

        store.updateMessage(id: "m1", content: "new")
        store.setMessageFeedback(id: "m1", feedback: "positive")

        XCTAssertEqual(store.state.conversation.first?.content, "new")
        XCTAssertEqual(store.state.conversation.first?.feedback, "positive")

        store.setMessageFeedback(id: "m1", feedback: "unknown")
        XCTAssertEqual(store.state.conversation.first?.feedback, "")

        let legacy = try? JSONDecoder().decode(ConversationMessage.self, from: Data(#"{"id":"legacy","role":"assistant","content":"old"}"#.utf8))
        XCTAssertEqual(legacy?.feedback, "")
    }

    @MainActor
    func testSessionRenameArchiveResumeAndDeleteByID() {
        let store = TimeTavernStore()
        store.state.savedSessions = [
            SavedSession(id: "s1", name: "舊名"),
            SavedSession(id: "s2", name: "保留")
        ]

        store.renameSession(id: "s1", name: "新名")
        store.setSessionArchived(id: "s1", archived: true)
        store.setSessionArchived(id: "s1", archived: false)
        store.deleteSession(id: "s2")

        XCTAssertEqual(store.state.savedSessions.first { $0.id == "s1" }?.name, "新名")
        XCTAssertEqual(store.state.savedSessions.first { $0.id == "s1" }?.archived, false)
        XCTAssertFalse(store.state.savedSessions.contains { $0.id == "s2" })
    }

    func testCharacterStatusChipTitle() {
        XCTAssertEqual(CharacterStatusCard.statusTitle(isReady: false), "Idle")
        XCTAssertEqual(CharacterStatusCard.statusTitle(isReady: true), "Ready")
    }

    func testAssistantCardDefaultNameAndPromptMessages() throws {
        var state = AppState()
        state.activeAssistantMode = AssistantCard.characterCardCreationAssistantID
        state.characterCardCreationAssistantPrompt = "助手 prompt for {{user}} and {{chur}}"
        state.userProfile.userName = "旅人"

        let messages = try ConversationEngine().buildPromptMessages(state: state, userInput: "幫我建立角色卡")

        XCTAssertEqual(AssistantCard.characterCardCreationAssistant.displayName, "建立卡助手")
        XCTAssertEqual(state.activeAssistantCard?.displayName, "建立卡助手")
        XCTAssertTrue(CharactersView.separatesRoleCardsAndAssistantCards)
        XCTAssertTrue(messages.first?.content.contains("助手 prompt for 旅人 and 建立卡助手") == true)
        XCTAssertEqual(messages.last?.role, "user")
        XCTAssertEqual(messages.last?.content, "幫我建立角色卡")
    }

    @MainActor
    func testStartAssistantCardClearsActiveRoleCardAndConversation() {
        let store = TimeTavernStore()
        store.state.roleCards = [RoleCard(id: "role_1", name: "角色")]
        store.state.activeRoleCardId = "role_1"
        store.state.conversation = [ConversationMessage(role: .assistant, content: "opening")]

        store.start(assistantCard: .characterCardCreationAssistant)

        XCTAssertEqual(store.state.activeRoleCardId, "")
        XCTAssertEqual(store.state.activeAssistantMode, AssistantCard.characterCardCreationAssistantID)
        XCTAssertEqual(store.state.conversation, [])
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

        try store.save(DeepSeekKeySet.encodeProcessingKeys(["processing-1", "processing-2"]), for: .deepSeekProcessingAPIKeys)
        XCTAssertEqual(DeepSeekKeySet.decodeProcessingKeys(try store.read(.deepSeekProcessingAPIKeys)), ["processing-1", "processing-2"])
        try store.delete(.deepSeekProcessingAPIKeys)
        XCTAssertEqual(try store.read(.deepSeekProcessingAPIKeys), "")
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
        XCTAssertFalse(messages.first?.content.contains("古井連接舊時間線") == true)
        XCTAssertEqual(messages.last?.role, "user")
        XCTAssertTrue(messages.last?.content.contains("古井連接舊時間線") == true)
    }

    func testConversationPromptUsesWebStyleCompletedRoundsAndCurrentUserContent() throws {
        var state = AppState()
        var card = RoleCard()
        card.name = "千夜"
        card.promptModeId = "multi"
        card.customSections = [CustomSection(name: "性格", content: "冷靜")]
        card.openingDialogues = [OpeningDialogue(id: "opening", name: "開場", content: "開場台詞")]
        card.activeOpeningDialogueId = "opening"
        card.lorebooks = [LorebookEntry(title: "古井", keywords: ["古井"], content: "古井連接舊時間線。")]
        state.roleCards = [card]
        state.activeRoleCardId = card.id
        state.userProfile.userName = "旅人"
        state.userProfile.extraPrompt = "玩家怕冷"
        state.timeTracking.enabled = true
        state.timeTracking.currentDayNumber = 2
        state.timeTracking.currentYear = 2026
        state.timeTracking.currentMonth = 6
        state.timeTracking.currentDate = 7
        state.timeTracking.currentPeriodValue = .morning
        state.promptModes = [
            PromptModeConfig(
                id: "multi",
                name: "多角色",
                mode: "multi",
                dialogueContextRounds: 1,
                compressionProfiles: [
                    CompressionProfile(
                        id: "standard",
                        name: "標準",
                        appendTerms: [CompressionAppendTerm(content: "追加詞 {{user}}/{{chur}}")],
                        summary: "第一回合以前的摘要"
                    )
                ]
            )
        ]
        state.conversation = [
            ConversationMessage(role: .assistant, content: "開場台詞", source: "opening"),
            ConversationMessage(role: .user, content: "第一問", turnNumber: 1),
            ConversationMessage(role: .assistant, content: "第一答", turnNumber: 1),
            ConversationMessage(role: .user, content: "第二問", turnNumber: 2),
            ConversationMessage(role: .assistant, content: "第二答", turnNumber: 2),
            ConversationMessage(role: .user, content: "我走到古井旁。", turnNumber: 3),
            ConversationMessage(role: .assistant, content: "", turnNumber: 3)
        ]

        let messages = try ConversationEngine().buildPromptMessages(state: state, userInput: "我走到古井旁。")

        XCTAssertEqual(messages[0].role, "system")
        XCTAssertTrue(messages[0].content.contains("【主要規則】"))
        XCTAssertTrue(messages[0].content.contains("冷靜"))
        XCTAssertEqual(messages[1].role, "user")
        XCTAssertTrue(messages[1].content.contains("【目前模型內容】"))
        XCTAssertTrue(messages[1].content.contains("第一回合以前的摘要"))
        XCTAssertTrue(messages.contains { $0.role == "assistant" && $0.content == "開場台詞" })
        XCTAssertTrue(messages.contains { $0.role == "user" && $0.content == "第二問" })
        XCTAssertTrue(messages.contains { $0.role == "assistant" && $0.content == "第二答" })
        XCTAssertEqual(messages.filter { $0.content.contains("我走到古井旁。") }.count, 1)
        XCTAssertFalse(messages.contains { $0.role == "assistant" && $0.content.isEmpty })
        XCTAssertTrue(messages.last?.content.contains("追加詞 旅人/千夜") == true)
        XCTAssertTrue(messages.last?.content.contains("當前時間 | 數值: 第2天早上2026年6月7日") == true)
        XCTAssertTrue(messages.last?.content.contains("【觸發世界書 Lorebooks】") == true)
        XCTAssertTrue(messages.last?.content.contains("古井連接舊時間線") == true)
        XCTAssertTrue(messages.last?.content.contains("【使用者自訂補充】") == true)
    }

    func testAILogEntryPreservesWebStylePayloadFields() throws {
        let usage = AIUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15, promptCacheHitTokens: 4, promptCacheMissTokens: 6)
        let log = AILogEntry(
            purpose: "reasoner_history_chat",
            model: "deepseek-reasoner",
            temperature: 0.5,
            maxTokens: 32000,
            requestMessages: [
                ChatAPIMessage(role: "system", content: "規則"),
                ChatAPIMessage(role: "user", content: "正文")
            ],
            responseText: "輸出",
            debugReasoningContent: "思考",
            usage: usage
        )

        XCTAssertEqual(log.requestMessages.count, 2)
        XCTAssertEqual(log.responseText, "輸出")
        XCTAssertEqual(log.debugReasoningContent, "思考")
        XCTAssertTrue(log.requestPreview.contains("#1 system"))
        XCTAssertTrue(log.usageSummary.contains("Cache Hit 4"))

        let encoded = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(AILogEntry.self, from: encoded)

        XCTAssertEqual(decoded.purpose, "reasoner_history_chat")
        XCTAssertEqual(decoded.requestMessages.last?.content, "正文")
        XCTAssertEqual(decoded.responseText, "輸出")
        XCTAssertEqual(decoded.debugReasoningContent, "思考")
        XCTAssertEqual(decoded.usage?.totalTokens, 15)

        let legacy = try JSONDecoder().decode(AILogEntry.self, from: Data(#"{"responsePreview":"舊輸出","reasoningPreview":"舊思考","status":"success"}"#.utf8))
        XCTAssertEqual(legacy.responseText, "舊輸出")
        XCTAssertEqual(legacy.debugReasoningContent, "舊思考")
    }

    func testTimeTrackingDetectsExplicitTextAddsPromptBlockAndAutoAdvances() throws {
        var state = AppState()
        let card = RoleCard()
        state.roleCards = [card]
        state.activeRoleCardId = card.id
        state.timeTracking.enabled = true
        state.timeTracking.currentDayNumber = 1
        state.timeTracking.currentYear = 2026
        state.timeTracking.currentMonth = 6
        state.timeTracking.currentDate = 6
        state.timeTracking.currentPeriodValue = .evening
        state.timeTracking.autoPeriod = TimeTrackingAutoPeriodConfig(enabled: true, roundsPerPeriod: 2, turnsSinceChange: 0)
        let engine = ConversationEngine()

        engine.updateTimeTrackingFromUserMessage(state: &state, text: "第二天早上，我推門進來。")
        let messages = try engine.buildPromptMessages(state: state, userInput: "測試")

        XCTAssertEqual(state.timeTracking.currentDayNumber, 2)
        XCTAssertEqual(state.timeTracking.currentPeriodValue, .morning)
        XCTAssertTrue(messages.last?.content.contains("當前時間 | 數值: 第2天早上2026年6月7日") == true)

        let warning = engine.updateTimeTrackingAfterAssistantTurn(state: &state, assistantText: "角色繼續說話。", userInput: "測試")
        XCTAssertEqual(state.timeTracking.autoPeriod.turnsSinceChange, 1)
        XCTAssertTrue(warning.contains("早上->中午"))

        let secondWarning = engine.updateTimeTrackingAfterAssistantTurn(state: &state, assistantText: "角色繼續說話。", userInput: "測試")
        XCTAssertEqual(secondWarning, "")
        XCTAssertEqual(state.timeTracking.currentPeriodValue, .noon)
        XCTAssertEqual(state.timeTracking.autoPeriod.turnsSinceChange, 0)

        _ = engine.updateTimeTrackingAfterAssistantTurn(state: &state, assistantText: "角色繼續說話。", userInput: "{保持時間}")
        XCTAssertEqual(state.timeTracking.autoPeriod.turnsSinceChange, 0)
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

    func testNormalCompressionStoresPlainTextOrJSONByModulePresence() throws {
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
                        id: "plain",
                        name: "純文本",
                        triggerActions: [CompressionTriggerAction(triggers: CompressionTriggerConfig(everyTurn: true))]
                    ),
                    CompressionProfile(
                        id: "json",
                        name: "JSON",
                        contextCompression: CompressionContextConfig(
                            models: [CompressionModel(id: "PlotProgression", name: "劇情狀態")]
                        ),
                        triggerActions: [CompressionTriggerAction(triggers: CompressionTriggerConfig(everyTurn: true))]
                    )
                ]
            )
        ]

        let modes = ConversationEngine().applyCompressionIfNeeded(state: state, latestUserInput: "新的事件")
        let profiles = modes.first?.compressionProfiles ?? []
        let plain = try XCTUnwrap(profiles.first { $0.id == "plain" })
        let json = try XCTUnwrap(profiles.first { $0.id == "json" })
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.summary.utf8)) as? [String: Any])
        let model = try XCTUnwrap(object["model"] as? [String: Any])
        let delete = try XCTUnwrap(object["delete"] as? [String: Any])
        let plot = try XCTUnwrap(model["PlotProgression"] as? [String])

        XCTAssertTrue(plain.summary.contains("新的事件"))
        XCTAssertFalse(plain.summary.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"))
        XCTAssertTrue(plot.first?.contains("新的事件") == true)
        XCTAssertNotNil(delete["PlotProgression"] as? [String])
    }

    func testCompressionAPIRequestsBuildMessagesAndMergeJSONCompletion() throws {
        var state = AppState()
        var card = RoleCard()
        card.promptModeId = "multi"
        card.customSections = [CustomSection(name: "設定", content: "角色設定")]
        state.roleCards = [card]
        state.activeRoleCardId = card.id
        state.conversation = [
            ConversationMessage(role: .user, content: "舊事件", turnNumber: 1),
            ConversationMessage(role: .assistant, content: "舊回覆", turnNumber: 1)
        ]
        let existingSummary = """
        {"model":{"PlotProgression":["舊事件"]},"delete":{"PlotProgression":[]}}
        """
        state.promptModes = [
            PromptModeConfig(
                id: "multi",
                name: "多角色",
                mode: "multi",
                dialogueContextRounds: 20,
                compressionProfiles: [
                    CompressionProfile(
                        id: "json",
                        name: "JSON",
                        contextScope: .roleAndText,
                        contextCompression: CompressionContextConfig(
                            mainRules: "壓縮規則",
                            models: [CompressionModel(id: "PlotProgression", name: "劇情狀態")]
                        ),
                        triggerActions: [CompressionTriggerAction(triggers: CompressionTriggerConfig(everyTurn: true))],
                        summary: existingSummary,
                        compressedThroughTurnNumber: 0
                    )
                ]
            )
        ]

        let engine = ConversationEngine()
        let requests = engine.compressionAPIRequests(state: state, latestUserInput: "新事件")
        var localState = state
        localState.promptModes = engine.applyCompressionIfNeeded(state: state, latestUserInput: "新事件")
        let mergedModes = engine.applyCompressionCompletion(
            state: localState,
            request: try XCTUnwrap(requests.first),
            completion: #"{"model":{"PlotProgression":["新事件"]},"delete":{"PlotProgression":["舊事件"]}}"#
        )
        let profile = try XCTUnwrap(mergedModes.first?.compressionProfiles.first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(profile.summary.utf8)) as? [String: Any])
        let model = try XCTUnwrap(object["model"] as? [String: Any])
        let plot = try XCTUnwrap(model["PlotProgression"] as? [String])

        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].messages.map(\.content).joined(separator: "\n").contains("【角色卡資料】"))
        XCTAssertTrue(requests[0].messages.map(\.content).joined(separator: "\n").contains("【目前模型內容】"))
        XCTAssertEqual(plot, ["新事件"])
        XCTAssertEqual(profile.compressedThroughTurnNumber, 2)
    }

    func testCompressionImageRequestsUseBasePromptAndDoNotSaveNormalSummary() throws {
        var state = AppState()
        var card = RoleCard()
        card.promptModeId = "multi"
        state.roleCards = [card]
        state.activeRoleCardId = card.id
        state.conversation = [
            ConversationMessage(role: .user, content: "角色看見月下酒館", turnNumber: 1),
            ConversationMessage(role: .assistant, content: "燈火映在木桌。", turnNumber: 1)
        ]
        var action = CompressionTriggerAction(
            name: "建立圖片",
            keywordFollowupAction: .imageThenReasoner,
            imageGeneration: NovelAIImageGenerationSettings(
                model: "nai-diffusion-4-5-curated",
                negativePrompt: "bad hands",
                width: 1216,
                height: 832,
                scale: 6
            ),
            triggers: CompressionTriggerConfig(everyTurn: true)
        )
        action.action = .callAPI
        action.novelAIEnabled = true
        var imageProfile = CompressionProfile(
            id: "image_profile",
            name: "跑圖大模型",
            contextCompression: CompressionContextConfig(mainRules: "把對話轉成畫面 prompt", models: []),
            triggerActions: [action],
            summary: "舊圖片狀態"
        )
        imageProfile.applyModelKind(.image)
        state.promptModes = [
            PromptModeConfig(
                id: "multi",
                name: "多角色",
                mode: "multi",
                compressionProfiles: [imageProfile]
            )
        ]

        let engine = ConversationEngine()
        let requests = engine.compressionImageRequests(state: state, latestUserInput: "跑圖")
        let localModes = engine.applyCompressionIfNeeded(state: state, latestUserInput: "跑圖")
        let locallyUpdated = try XCTUnwrap(localModes.first?.compressionProfiles.first)
        let startedModes = engine.applyImageCompressionStarted(
            state: state,
            request: try XCTUnwrap(requests.first)
        )
        let started = try XCTUnwrap(startedModes.first?.compressionProfiles.first)
        let requestText = requests.first?.messages.map(\.content).joined(separator: "\n") ?? ""

        XCTAssertEqual(engine.compressionAPIRequests(state: state, latestUserInput: "跑圖"), [])
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requestText.contains("只輸出可直接送去 NovelAI 的 Base Prompt"))
        XCTAssertTrue(requestText.contains("【上下文】"))
        XCTAssertEqual(requests.first?.imageSettings.model, "nai-diffusion-4-5-curated")
        XCTAssertEqual(requests.first?.imageSettings.negativePrompt, "bad hands")
        XCTAssertEqual(locallyUpdated.summary, "")
        XCTAssertEqual(locallyUpdated.compressedThroughTurnNumber, 2)
        XCTAssertEqual(started.summary, "")
        XCTAssertEqual(started.compressedThroughTurnNumber, 2)
    }

    func testCompressionBeforeReasonerCanSkipChatAfterUserKeyword() throws {
        var state = AppState()
        var card = RoleCard()
        card.promptModeId = "multi"
        state.roleCards = [card]
        state.activeRoleCardId = card.id
        state.conversation = [
            ConversationMessage(role: .user, content: "停下正文，只整理模型", turnNumber: 1),
            ConversationMessage(role: .assistant, content: "", turnNumber: 1)
        ]
        let action = CompressionTriggerAction(
            name: "只處理模型",
            keywordFollowupAction: .stopAfterModel,
            triggers: CompressionTriggerConfig(
                roundLimit: false,
                keywords: ["停下正文"],
                keywordSource: "user"
            )
        )
        state.promptModes = [
            PromptModeConfig(
                id: "multi",
                name: "多角色",
                mode: "multi",
                compressionProfiles: [
                    CompressionProfile(
                        id: "skip",
                        name: "停止正文模型",
                        triggerActions: [action],
                        compressedThroughTurnNumber: 0
                    )
                ]
            )
        ]

        let engine = ConversationEngine()
        let beforeRequests = engine.compressionAPIRequests(
            state: state,
            latestUserInput: "停下正文，只整理模型",
            phase: .beforeReasoner
        )
        let afterRequests = engine.compressionAPIRequests(
            state: state,
            latestUserInput: "停下正文，只整理模型",
            latestAssistantText: "",
            phase: .afterAssistant
        )

        XCTAssertEqual(beforeRequests.count, 1)
        XCTAssertTrue(try XCTUnwrap(beforeRequests.first).skipReasoner)
        XCTAssertTrue(ConversationEngine.modelProcessingCompletionMessage(for: beforeRequests).contains("只處理模型"))
        XCTAssertEqual(afterRequests.count, 0)
    }

    func testCompressionAfterAssistantRequiresAssistantKeywordMatch() throws {
        var state = AppState()
        var card = RoleCard()
        card.promptModeId = "multi"
        state.roleCards = [card]
        state.activeRoleCardId = card.id
        state.conversation = [
            ConversationMessage(role: .user, content: "普通輸入", turnNumber: 1),
            ConversationMessage(role: .assistant, content: "火焰照亮酒館", turnNumber: 1)
        ]
        let action = CompressionTriggerAction(
            name: "助手命中後壓縮",
            triggers: CompressionTriggerConfig(
                roundLimit: false,
                keywords: ["火焰"],
                keywordSource: "assistant"
            )
        )
        state.promptModes = [
            PromptModeConfig(
                id: "multi",
                name: "多角色",
                mode: "multi",
                compressionProfiles: [
                    CompressionProfile(
                        id: "assistant_keyword",
                        name: "助手關鍵字模型",
                        triggerActions: [action],
                        compressedThroughTurnNumber: 0
                    )
                ]
            )
        ]

        let engine = ConversationEngine()
        let beforeRequests = engine.compressionAPIRequests(
            state: state,
            latestUserInput: "普通輸入",
            phase: .beforeReasoner
        )
        let afterRequests = engine.compressionAPIRequests(
            state: state,
            latestUserInput: "普通輸入",
            latestAssistantText: "火焰照亮酒館",
            phase: .afterAssistant
        )
        let requestText = afterRequests.first?.messages.map(\.content).joined(separator: "\n") ?? ""

        XCTAssertEqual(beforeRequests.count, 0)
        XCTAssertEqual(afterRequests.count, 1)
        XCTAssertTrue(requestText.contains("火焰照亮酒館"))
    }

    func testCompressionEveryTurnDoesNotRepeatAfterCurrentTurnAlreadyCompressed() {
        var state = AppState()
        var card = RoleCard()
        card.promptModeId = "multi"
        state.roleCards = [card]
        state.activeRoleCardId = card.id
        state.conversation = [
            ConversationMessage(role: .user, content: "第一輪", turnNumber: 1),
            ConversationMessage(role: .assistant, content: "第一輪回覆", turnNumber: 1)
        ]
        state.promptModes = [
            PromptModeConfig(
                id: "multi",
                name: "多角色",
                mode: "multi",
                compressionProfiles: [
                    CompressionProfile(
                        id: "every",
                        name: "每輪",
                        triggerActions: [CompressionTriggerAction(triggers: CompressionTriggerConfig(everyTurn: true, roundLimit: false))],
                        compressedThroughTurnNumber: 1
                    )
                ]
            )
        ]

        let engine = ConversationEngine()

        XCTAssertEqual(engine.compressionAPIRequests(state: state, latestUserInput: "第一輪", phase: .beforeReasoner), [])
        XCTAssertEqual(engine.compressionAPIRequests(state: state, latestUserInput: "第一輪", latestAssistantText: "第一輪回覆", phase: .afterAssistant), [])
    }

    @MainActor
    func testRunTimeUsesWebTurnTemplateAndValidation() {
        let content = ConversationEngine.runtimeTurnUserContent(
            message: "推進酒館劇情",
            turnNumber: 2,
            totalTurns: 5
        )
        let emptyContent = ConversationEngine.runtimeTurnUserContent(message: "  ", turnNumber: 1, totalTurns: 1)
        let store = TimeTavernStore()
        store.state.activeAssistantMode = AssistantCard.characterCardCreationAssistantID

        store.runTime(turns: 3, seedMessage: "推演")

        XCTAssertEqual(ConversationEngine.normalizedRuntimeTurns(0), nil)
        XCTAssertEqual(ConversationEngine.normalizedRuntimeTurns(25), 20)
        XCTAssertEqual(content, "用戶要求你現在自行推演5輪,包括用戶及角色\n「推進酒館劇情」這是用戶的要求\n現在是第2輪")
        XCTAssertEqual(emptyContent, "用戶要求你現在自行推演1輪,包括用戶及角色\n這是用戶的要求\n現在是第1輪")
        XCTAssertEqual(store.statusText, "CharacterCardCreationAssistant 不支援 /run_time 自動推演。")
    }

    func testBundledWebDefaultsDecodeFullRoleCardsAndPromptModes() throws {
        let state = try BundledWebDefaultsService.loadDefaults(from: webDefaultsURL())

        XCTAssertEqual(state.roleCards.count, 9)
        XCTAssertEqual(state.promptModes.map(\.id).sorted(), ["multi", "no_role", "single"])
        XCTAssertEqual(state.userProfile.userName, "時分")
        XCTAssertFalse(state.userProfile.extraPrompt.isEmpty)
        XCTAssertTrue(state.roleCards.allSatisfy { !$0.customSections.isEmpty })
        XCTAssertTrue(state.roleCards.allSatisfy { $0.activeOpeningDialogue?.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false })
        XCTAssertTrue(state.roleCards.contains { !$0.coverImageDataURL.isEmpty })
        XCTAssertTrue(state.roleCards.allSatisfy { RoleCardCoverPosition(rawValue: $0.coverPosition) != nil })
        XCTAssertTrue(state.characterCardCreationAssistantPrompt.contains("你是中文設定助手"))
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
        settings.basePrompt = "masterpiece, ||pose||, ||light||, {{legacy}}"
        settings.fixedSnippets = [NovelAIPromptSnippet(name: "pose", content: "standing\nblack dress")]
        settings.randomSnippets = [
            NovelAIPromptSnippet(name: "light", content: "moonlight\nlantern", min: 1, max: 1),
            NovelAIPromptSnippet(name: "legacy", content: "soft focus\nfilm grain", min: 1, max: 1)
        ]
        settings.characterPrompts = [NovelAICharacterPrompt(name: "A", prompt: "blue hair", negativePrompt: "red hair", x: 0.25, y: 0.75)]
        settings.imageSettings.seed = 123

        let resolution = try NovelAIClient.resolvePrompt(from: settings, randomIndex: { max(0, $0 - 1) })
        let request = NovelAIClient.buildImageGenerationRequest(studioSettings: settings, promptResolution: resolution)
        let metadata = """
        {"input":"new prompt","model":"nai-test","parameters":{"prompt_template":"||pose||","fixed_prompt_snippets":[{"name":"pose","prompt":"sit"}],"random_prompt_snippets":[{"name":"tone","randomText":"warm\\ncool","min":1,"max":1}],"v4_prompt":{"caption":{"base_caption":"new prompt","char_captions":[{"char_caption":"blue hair","centers":[{"x":0.25,"y":0.75}]}]}},"v4_negative_prompt":{"caption":{"base_caption":"bad","char_captions":[{"char_caption":"red hair","centers":[{"x":0.25,"y":0.75}]}]}},"negative_prompt":"bad","width":1024,"height":1024,"steps":30,"scale":6.5,"sampler":"k_euler","cfg_rescale":0.4,"seed":99}}
        """
        let importResult = NovelAIClient.importMetadata(metadata, into: settings)
        let imported = importResult.settings

        XCTAssertEqual(NovelAIModelOption.allCases.count, 6)
        XCTAssertEqual(resolution.finalPrompt, "masterpiece,standing,black dress,moonlight,soft focus")
        XCTAssertEqual(resolution.fixedPrompt.expansions.first?.name, "pose")
        XCTAssertEqual(resolution.randomPrompt.expansions.count, 2)
        XCTAssertEqual(request.parameters.v4Prompt.caption.charCaptions.first?.charCaption, "blue hair")
        XCTAssertEqual(request.parameters.v4NegativePrompt.caption.charCaptions.first?.charCaption, "red hair")
        XCTAssertEqual(request.parameters.v4Prompt.caption.charCaptions.first?.centers.first?.x, 0.25)
        XCTAssertEqual(request.parameters.fixedPromptSnippets.count, 1)
        XCTAssertEqual(request.parameters.randomPromptSnippets.count, 2)
        XCTAssertEqual(request.parameters.seed, 123)
        XCTAssertEqual(request.model, NovelAIModelOption.defaultID)
        XCTAssertEqual(imported.basePrompt, "||pose||")
        XCTAssertEqual(imported.imageSettings.model, NovelAIModelOption.defaultID)
        XCTAssertNotNil(importResult.fallbackMessage)
        XCTAssertEqual(imported.fixedSnippets.first?.content, "sit")
        XCTAssertEqual(imported.randomSnippets.first?.content, "warm\ncool")
        XCTAssertEqual(imported.characterPrompts.first?.prompt, "blue hair")
        XCTAssertEqual(imported.characterPrompts.first?.negativePrompt, "red hair")
        XCTAssertEqual(imported.imageSettings.width, 1024)
        XCTAssertEqual(imported.imageSettings.seed, 99)
    }

    func testNovelAICostPreviewAndLoopLimitsMatchWebRules() {
        var settings = NovelAIStudioSettings()

        XCTAssertEqual(NovelAIClient.estimatedAnlas(for: settings), 20)
        XCTAssertEqual(NovelAIClient.loopRequestLimit(from: 1), 1)
        XCTAssertEqual(NovelAIClient.loopRequestLimit(from: 99999), 9999)
        XCTAssertNil(NovelAIClient.loopRequestLimit(from: 0))

        settings.imageSettings.samples = 2
        settings.imageToImageImageData = Data([1])
        settings.vibeTransferImages = (0..<5).map { index in
            NovelAIReferenceImage(id: "v\(index)", imageData: Data([UInt8(index)]))
        }
        settings.preciseReferenceImages = (0..<2).map { index in
            NovelAIReferenceImage(id: "p\(index)", imageData: Data([UInt8(index)]))
        }

        XCTAssertEqual(NovelAIClient.estimatedAnlas(for: settings), 70)
    }

    func testNovelAIPngMetadataImportMatchesWebITXt() throws {
        let metadata = """
        {"input":"from image","model":"nai-diffusion-4-5-curated","parameters":{"width":1216,"height":832,"negative_prompt":"bad","steps":32}}
        """
        let png = Self.pngDataWithITXt(keyword: "NovelAIMetadata", value: metadata)
        let result = try XCTUnwrap(NovelAIClient.importMetadata(fromImageData: png, into: NovelAIStudioSettings()))

        XCTAssertEqual(result.settings.basePrompt, "from image")
        XCTAssertEqual(result.settings.imageSettings.model, "nai-diffusion-4-5-curated")
        XCTAssertEqual(result.settings.imageSettings.width, 1216)
        XCTAssertEqual(result.settings.imageSettings.height, 832)
        XCTAssertEqual(result.settings.imageSettings.steps, 32)
        XCTAssertEqual(result.settings.negativePrompt, "bad")
    }

    func testNovelAITargetedImageImportMatchesWebDropChoiceActions() throws {
        let imageA = Data([1, 2, 3])
        let imageB = Data([4, 5, 6])
        let metadata = """
        {"input":"metadata prompt","model":"nai-diffusion-4-5-curated","parameters":{"width":832,"height":1216}}
        """
        let metadataImage = Self.pngDataWithITXt(keyword: "NovelAIMetadata", value: metadata)
        let targets = NovelAIImageImportTarget.allCases.map(\.title)

        let vibe = NovelAITargetedImageImportSection.apply(target: .vibe, images: [imageA, imageB], to: NovelAIStudioSettings())
        let imageToImage = NovelAITargetedImageImportSection.apply(target: .imageToImage, images: [imageA, imageB], to: NovelAIStudioSettings())
        let precise = NovelAITargetedImageImportSection.apply(target: .precise, images: [imageA], to: NovelAIStudioSettings())
        let imported = NovelAITargetedImageImportSection.apply(target: .metadata, images: [metadataImage], to: NovelAIStudioSettings())

        XCTAssertTrue(NovelAITargetedImageImportSection.mirrorsWebDropChoiceActions)
        XCTAssertEqual(targets, ["Vibe Transfer", "Image2Image", "Precise Reference", "匯入設定"])
        XCTAssertEqual(vibe.settings.vibeTransferImages.count, 2)
        XCTAssertEqual(vibe.settings.vibeTransferImages.first?.type, "vibe")
        XCTAssertEqual(vibe.settings.vibeTransferImages.first?.noise, 1)
        XCTAssertEqual(imageToImage.settings.imageToImageImageData, imageA)
        XCTAssertEqual(precise.settings.preciseReferenceImages.count, 1)
        XCTAssertEqual(precise.settings.preciseReferenceImages.first?.strength, 1)
        XCTAssertEqual(precise.settings.preciseReferenceImages.first?.noise, 1)
        XCTAssertEqual(imported.settings.basePrompt, "metadata prompt")
    }

    func testNovelAICharacterPositionMatchesWebFiveByFiveGridAndCentersDecode() throws {
        let center = NovelAICharacterPositionCell(x: 0.5, y: 0.5)
        let topLeft = NovelAICharacterPositionCell(row: 1, col: 1)
        let bottomRight = NovelAICharacterPositionCell(row: 5, col: 5)
        let rounded = NovelAICharacterPositionCell(x: 0.74, y: 0.24)
        let webSettingsJSON = """
        {
          "prompt": "base",
          "negative_prompt": "bad",
          "characters": [
            {
              "id": "char_1",
              "name": "A",
              "char_caption": "blue hair",
              "negative_prompt": "red hair",
              "centers": [{"x": 0.25, "y": 0.75}]
            }
          ]
        }
        """

        let settings = try JSONDecoder().decode(NovelAIStudioSettings.self, from: Data(webSettingsJSON.utf8))
        let request = NovelAIClient.buildImageGenerationRequest(studioSettings: settings)

        XCTAssertEqual(NovelAICharacterPromptSection.usesWebPositionGrid, true)
        XCTAssertEqual(center.label, "R3 C3")
        XCTAssertEqual(topLeft.x, 0)
        XCTAssertEqual(topLeft.y, 0)
        XCTAssertEqual(bottomRight.x, 1)
        XCTAssertEqual(bottomRight.y, 1)
        XCTAssertEqual(rounded.label, "R2 C4")
        XCTAssertEqual(settings.basePrompt, "base")
        XCTAssertEqual(settings.negativePrompt, "bad")
        XCTAssertEqual(settings.characterPrompts.first?.prompt, "blue hair")
        XCTAssertEqual(settings.characterPrompts.first?.negativePrompt, "red hair")
        XCTAssertEqual(settings.characterPrompts.first?.positionCell.label, "R4 C2")
        XCTAssertEqual(request.parameters.v4Prompt.caption.charCaptions.first?.centers.first?.x, 0.25)
        XCTAssertEqual(request.parameters.v4Prompt.caption.charCaptions.first?.centers.first?.y, 0.75)
        XCTAssertEqual(request.parameters.v4NegativePrompt.caption.charCaptions.first?.centers.first?.x, 0.25)
        XCTAssertEqual(request.parameters.v4NegativePrompt.caption.charCaptions.first?.centers.first?.y, 0.75)
    }

    func testAIUsageFormatsCacheHitSummaryAndSettingsHelp() throws {
        let json = """
        {"prompt_tokens":1000,"completion_tokens":200,"total_tokens":1200,"prompt_cache_hit_tokens":750,"prompt_cache_miss_tokens":250}
        """
        let usage = try JSONDecoder().decode(AIUsage.self, from: Data(json.utf8))

        XCTAssertEqual(usage.formattedSummary, "輸入 1000 / 輸出 200 / 總計 1200 / Cache Hit 750 / Cache Miss 250 / 命中率 75%")
        XCTAssertTrue(SettingsView.deepSeekMultiKeyHelp.contains("多條 DeepSeek API key"))
        XCTAssertTrue(SettingsView.deepSeekCacheHitHelp.contains("Cache Hit"))
        XCTAssertTrue(SettingsView.deepSeekCacheHitHelp.contains("命中率"))
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

        let legacyWebJSON = """
        {"id":"legacy_1","name":"舊欄位角色","mode":"multi","description":"描述內容","systemInstruction":"系統內容","relationships":"關係內容","openingDialogue":"開場內容"}
        """
        let legacyCard = try service.importRoleCardJSON(from: Data(legacyWebJSON.utf8), existingRoleCards: [])

        XCTAssertEqual(legacyCard.customSections.map(\.name), ["系統指令", "詳細描述", "人物關係（純文字）"])
        XCTAssertEqual(legacyCard.activeOpeningDialogue?.content, "開場內容")

        let sillyJSON = """
        {"spec":"chara_card_v2","data":{"name":"ST角色","description":"描述","personality":"性格","first_mes":"開場","alternate_greetings":["替代"],"character_book":{"entries":[{"id":1,"name":"Lore","keys":["key"],"content":"lore text"}]}}}
        """
        let sillyCard = try service.importRoleCardJSON(from: Data(sillyJSON.utf8), existingRoleCards: [])

        XCTAssertEqual(sillyCard.name, "ST角色")
        XCTAssertEqual(sillyCard.customSections.map(\.name), ["描述", "性格"])
        XCTAssertEqual(sillyCard.openingDialogues.count, 2)
        XCTAssertEqual(sillyCard.lorebooks.first?.keywords, ["key"])
    }

    func testRoleCardImageImportSupportsWebPngAndJpegMetadata() throws {
        let service = ImportExportService()
        let pngPayload = """
        {"spec":"chara_card_v2","data":{"name":"PNG角色","first_mes":"PNG開場","description":"PNG描述"}}
        """
        let png = Self.pngDataWithITXt(keyword: "chara", value: Data(pngPayload.utf8).base64EncodedString())
        let pngCard = try service.importRoleCard(from: png, fileName: "role.png", existingRoleCards: [])

        XCTAssertEqual(pngCard.name, "PNG角色")
        XCTAssertEqual(pngCard.activeOpeningDialogue?.content, "PNG開場")
        XCTAssertEqual(pngCard.coverImageData, png)
        XCTAssertTrue(pngCard.coverImageDataURL.hasPrefix("data:image/png;base64,"))

        let jpegPayload = """
        {"spec":"chara_card_v2","data":{"name":"JPG角色","first_mes":"JPG開場","personality":"JPG性格"}}
        """
        let jpeg = Self.jpegRoleCardData(payloadText: Data(jpegPayload.utf8).base64EncodedString())
        let jpegCard = try service.importRoleCard(from: jpeg, fileName: "role.jpg", existingRoleCards: [])

        XCTAssertEqual(jpegCard.name, "JPG角色")
        XCTAssertEqual(jpegCard.activeOpeningDialogue?.content, "JPG開場")
        XCTAssertEqual(jpegCard.coverImageData, jpeg)
        XCTAssertTrue(jpegCard.coverImageDataURL.hasPrefix("data:image/jpeg;base64,"))
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
        let imageData = try Self.testImageData(width: 100, height: 80)
        let cropped = try XCTUnwrap(RoleCardCoverCropEditor.cropImageData(
            imageData,
            crop: RoleCardCoverCrop(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            maxSide: 1000
        ))
        let croppedImage = try XCTUnwrap(UIImage(data: cropped))

        XCTAssertEqual(decoded.coverPosition, RoleCardCoverPosition.bottomCenter.rawValue)
        XCTAssertTrue(RoleCardCoverCropEditor.supportsFreeCrop)
        XCTAssertEqual(RoleCardCoverCrop.defaultCrop.normalized(), RoleCardCoverCrop.defaultCrop)
        XCTAssertEqual(RoleCardCoverCrop(x: 0.9, y: 0.9, width: 0.5, height: 0.5).normalized().x, 0.5, accuracy: 0.001)
        XCTAssertEqual(croppedImage.size.width, 50, accuracy: 1)
        XCTAssertEqual(croppedImage.size.height, 40, accuracy: 1)
        XCTAssertFalse(cropped.isEmpty)
        XCTAssertFalse(PromptRulesEditorView.exposesLegacyFields)
        XCTAssertFalse(PromptModeEditorView.exposesManualRoundEditing)
    }

    func testCompressionProfileKindSwitchesImageAndStorageModes() {
        var profile = CompressionProfile(
            id: "normal",
            name: "普通大模型",
            contextCompression: CompressionContextConfig(mainRules: "compress", models: [])
        )

        XCTAssertEqual(profile.modelKind, .normal)
        XCTAssertEqual(profile.storageMode, .plainText)
        XCTAssertTrue(profile.storageModeDescription.contains("純文本"))

        profile.contextCompression.models = [CompressionModel(id: "PlotProgression", name: "劇情狀態")]
        XCTAssertEqual(profile.storageMode, .json)
        XCTAssertTrue(profile.storageModeDescription.contains("JSON"))
        XCTAssertTrue(ConversationEngine().compressionPromptPreview(mode: PromptModeConfig(), profile: profile).contains("JSON"))

        profile.applyModelKind(.image)

        XCTAssertEqual(profile.modelKind, .image)
        XCTAssertEqual(profile.triggerActions.first?.action, .callAPI)
        XCTAssertEqual(profile.triggerActions.first?.keywordFollowupAction, .imageThenReasoner)
        XCTAssertEqual(profile.triggerActions.first?.novelAIEnabled, true)
        XCTAssertTrue(CompressionProfileEditorView.exposesProfileKindPicker)
        XCTAssertTrue(CompressionProfileEditorView.imageSettingsVisibility(for: profile))
    }

    func testWorkshopIndexHelpersIgnoreStaleOffsetsAndInvalidSymbolIsGone() {
        let modes = [
            PromptModeConfig(id: "multi", name: "多角色", mode: "multi"),
            PromptModeConfig(id: "custom", name: "自訂", mode: "custom")
        ]
        let profiles = [
            CompressionProfile(id: "standard", name: "標準"),
            CompressionProfile(id: "image", name: "跑圖")
        ]

        XCTAssertEqual(PromptLabView.modeIDs(at: IndexSet([1, 99]), in: modes), ["custom"])
        XCTAssertEqual(CompressionProfileListView.profileIDs(at: IndexSet([1, 99]), in: profiles), ["image"])
        XCTAssertEqual(SettingsView.roleCardImportSymbolName, "person.crop.square")
        XCTAssertTrue(PromptLabView.exposesQuickProfileKindAndImageSettings)
        XCTAssertTrue(PromptLabView.showsExpandedQuickImageSettings)
        XCTAssertEqual(
            TriggerActionListView.validActionOffsets(IndexSet([0, 99]), in: [CompressionTriggerAction(id: "a")]),
            IndexSet([0])
        )
    }

    func testCompressionTriggerImageGenerationReadsWebFieldsAndUIExposesThem() throws {
        let json = """
        {
          "id": "trigger_image",
          "name": "建立圖片",
          "novelAIEnabled": true,
          "keywordFollowupAction": "image_then_reasoner",
          "imageGeneration": {
            "model": "nai-diffusion-4-5-curated",
            "negative_prompt": "bad hands",
            "width": 1216,
            "height": 832,
            "steps": 30,
            "n_samples": 4,
            "guidance": 6.5,
            "cfg_rescale": 0.4,
            "sampler": "k_euler",
            "noise_schedule": "karras",
            "ucPreset": 2,
            "skipCfgAboveSigma": true,
            "image_format": "webp",
            "seed": "123"
          }
        }
        """

        let action = try JSONDecoder().decode(CompressionTriggerAction.self, from: Data(json.utf8))

        XCTAssertTrue(TriggerActionEditorView.exposesFullImageGenerationSettings)
        XCTAssertEqual(CompressionTriggerAction().imageGeneration.model, "nai-diffusion-4-5-curated")
        XCTAssertEqual(CompressionTriggerAction().imageGeneration.scale, 6)
        XCTAssertEqual(CompressionTriggerAction().imageGeneration.noiseSchedule, "karras")
        XCTAssertEqual(action.imageGeneration.model, "nai-diffusion-4-5-curated")
        XCTAssertEqual(action.imageGeneration.negativePrompt, "bad hands")
        XCTAssertEqual(action.imageGeneration.width, 1216)
        XCTAssertEqual(action.imageGeneration.height, 832)
        XCTAssertEqual(action.imageGeneration.steps, 30)
        XCTAssertEqual(action.imageGeneration.samples, 4)
        XCTAssertEqual(action.imageGeneration.scale, 6.5)
        XCTAssertEqual(action.imageGeneration.cfgRescale, 0.4)
        XCTAssertEqual(action.imageGeneration.sampler, "k_euler")
        XCTAssertEqual(action.imageGeneration.noiseSchedule, "karras")
        XCTAssertEqual(action.imageGeneration.ucPreset, 2)
        XCTAssertTrue(action.imageGeneration.varietyPlus)
        XCTAssertEqual(action.imageGeneration.imageFormat, "webp")
        XCTAssertEqual(action.imageGeneration.seed, 123)
        XCTAssertTrue(NovelAIOptionLists.samplerOptions.contains { $0.id == "k_euler_ancestral" })
        XCTAssertTrue(NovelAIOptionLists.noiseScheduleOptions.contains { $0.id == "karras" })
        XCTAssertTrue(NovelAIOptionLists.imageFormatOptions.contains { $0.id == "webp" })
    }

    @MainActor
    func testNovelAIAlbumCanDeleteByVisibleIDAction() {
        let store = TimeTavernStore()
        store.state.novelAIAlbum = [
            NovelAIAlbumItem(id: "keep", prompt: "keep", imageData: Data([1])),
            NovelAIAlbumItem(id: "delete", prompt: "delete", imageData: Data([2]))
        ]

        store.deleteNovelAIAlbumItem(id: "delete")

        XCTAssertEqual(store.state.novelAIAlbum.map(\.id), ["keep"])
        XCTAssertEqual(NovelAIHistoryPanel.itemsAfterDeleting(id: "keep", from: store.state.novelAIAlbum), [])
    }

    func testNovelAIDeleteHelpersMatchWebVisibleDeleteButtons() {
        let snippet = NovelAIPromptSnippet(id: "s1", name: "片段")
        let prompt = NovelAICharacterPrompt(id: "c1", name: "角色")
        let reference = NovelAIReferenceImage(id: "r1", name: "Reference")

        XCTAssertEqual(NovelAISnippetSection.snippetsAfterDeleting(id: "s1", from: [snippet]), [])
        XCTAssertEqual(NovelAICharacterPromptSection.promptsAfterDeleting(id: "c1", from: [prompt]), [])
        XCTAssertEqual(NovelAIReferenceSection.referencesAfterDeleting(id: "r1", from: [reference]), [])
    }

    func testNovelAICharacterPromptMoveKeepsWebOrderEditable() {
        let first = NovelAICharacterPrompt(id: "c1", name: "一")
        let second = NovelAICharacterPrompt(id: "c2", name: "二")
        let third = NovelAICharacterPrompt(id: "c3", name: "三")

        let movedDown = NovelAICharacterPromptSection.promptsAfterMoving(id: "c1", direction: 1, from: [first, second, third])
        let movedUp = NovelAICharacterPromptSection.promptsAfterMoving(id: "c3", direction: -1, from: [first, second, third])

        XCTAssertEqual(movedDown.map(\.id), ["c2", "c1", "c3"])
        XCTAssertEqual(movedUp.map(\.id), ["c1", "c3", "c2"])
    }

    func testTimeTrackingSettingsHelpExplainsWebRules() {
        let help = SettingsView.timeTrackingUsageHelp.joined(separator: "\n")

        XCTAssertTrue(help.contains("配合詞與 +1天關鍵字在 5 字內"))
        XCTAssertTrue(help.contains("3天後 / 三天後"))
        XCTAssertTrue(help.contains("第3天"))
        XCTAssertTrue(help.contains("不改詞與配合詞在 5 字內"))
        XCTAssertTrue(help.contains("早上→中午→晚上→早上"))
        XCTAssertTrue(help.contains("{保持時間}"))
    }

    private func webDefaultsURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TimeTavern/Resources/WebDefaults")
    }

    private static func pngDataWithITXt(keyword: String, value: String) -> Data {
        var output = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        output.append(pngChunk(type: "iTXt", payload: Array(keyword.utf8) + [0, 0, 0, 0, 0] + Array(value.utf8)))
        output.append(pngChunk(type: "IEND", payload: []))
        return output
    }

    private static func pngChunk(type: String, payload: [UInt8]) -> Data {
        var data = Data()
        let length = UInt32(payload.count)
        data.append(UInt8((length >> 24) & 0xff))
        data.append(UInt8((length >> 16) & 0xff))
        data.append(UInt8((length >> 8) & 0xff))
        data.append(UInt8(length & 0xff))
        data.append(contentsOf: Array(type.utf8.prefix(4)))
        data.append(contentsOf: payload)
        data.append(contentsOf: [0, 0, 0, 0])
        return data
    }

    private static func jpegRoleCardData(payloadText: String) -> Data {
        let metadata = Array("TimeTavernRoleCard\0\(String(1).leftPadded(to: 4))/\(String(1).leftPadded(to: 4))\0\(payloadText)".utf8)
        let length = UInt16(metadata.count + 2)
        var data = Data([0xff, 0xd8, 0xff, 0xef])
        data.append(UInt8((length >> 8) & 0xff))
        data.append(UInt8(length & 0xff))
        data.append(contentsOf: metadata)
        data.append(contentsOf: [0xff, 0xd9])
        return data
    }

    private static func testImageData(width: CGFloat, height: CGFloat) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 1.0))
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}
