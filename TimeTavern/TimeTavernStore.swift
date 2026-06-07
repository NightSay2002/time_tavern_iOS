import Foundation
import SwiftData

@MainActor
final class TimeTavernStore: ObservableObject {
    @Published var state = AppState()
    @Published var deepSeekKey = ""
    @Published var deepSeekProcessingKeys: [String] = []
    @Published var novelAIKey = ""
    @Published var composerText = ""
    @Published var statusText = ""
    @Published var isGenerating = false
    @Published var isNovelAIGenerating = false
    @Published var isNovelAILoopRunning = false
    @Published var exportedJSONURL: URL?

    private let secretStore = SecretStore()
    private let deepSeekClient = DeepSeekClient()
    private let novelAIClient = NovelAIClient()
    private let conversationEngine = ConversationEngine()
    private let importExportService = ImportExportService()
    private let bundledWebDefaultsService = BundledWebDefaultsService()
    private var database: AppDatabase?
    private var generationTask: Task<Void, Never>?
    private var novelAIGenerationTask: Task<Void, Never>?
    private var deepSeekChatKeyCursor = 0

    private struct CompressionPhaseResult {
        var completed: Int = 0
        var skipReasoner: Bool = false
        var skipRequests: [CompressionAPIRequest] = []
    }

    func attach(modelContext: ModelContext) {
        guard database == nil else { return }
        database = AppDatabase(context: modelContext)
        state = database?.loadState() ?? AppState()
        deepSeekKey = (try? secretStore.read(.deepSeekAPIKey)) ?? ""
        deepSeekProcessingKeys = DeepSeekKeySet.decodeProcessingKeys((try? secretStore.read(.deepSeekProcessingAPIKeys)) ?? "")
        novelAIKey = (try? secretStore.read(.novelAIAPIKey)) ?? ""
    }

    func saveSecrets() {
        do {
            try secretStore.save(deepSeekKey, for: .deepSeekAPIKey)
            deepSeekProcessingKeys = DeepSeekKeySet.normalizedProcessingKeys(deepSeekProcessingKeys)
            try secretStore.save(DeepSeekKeySet.encodeProcessingKeys(deepSeekProcessingKeys), for: .deepSeekProcessingAPIKeys)
            try secretStore.save(novelAIKey, for: .novelAIAPIKey)
            statusText = "API keys 已保存到 Keychain。"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func currentDeepSeekKeySet() -> DeepSeekKeySet {
        DeepSeekKeySet(primaryKey: deepSeekKey, processingKeys: deepSeekProcessingKeys)
    }

    func nextDeepSeekChatKey() -> String {
        let keySet = currentDeepSeekKeySet()
        let key = keySet.chatKey(cursor: deepSeekChatKeyCursor)
        if !keySet.allKeys.isEmpty {
            deepSeekChatKeyCursor = (deepSeekChatKeyCursor + 1) % keySet.allKeys.count
        }
        return key
    }

    func persist() {
        state.updatedAt = Date()
        do {
            try database?.saveState(state)
        } catch {
            statusText = "保存失敗：\(error.localizedDescription)"
        }
    }

    func createRoleCard() {
        var card = RoleCard()
        card.name = "新角色"
        card.customSections = []
        state.roleCards.insert(card, at: 0)
        persist()
    }

    func start(roleCard: RoleCard) {
        state.activeRoleCardId = roleCard.id
        state.activeAssistantMode = ""
        state.conversation = []
        if let opening = roleCard.activeOpeningDialogue?.content, !opening.isEmpty {
            let renderedOpening = ConversationEngine.renderTemplate(
                opening,
                user: state.userProfile.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "你" : state.userProfile.userName,
                role: roleCard.name
            )
            state.conversation.append(ConversationMessage(role: .assistant, content: renderedOpening, source: "opening"))
            conversationEngine.updateTimeTrackingFromOpening(state: &state, opening: renderedOpening)
        }
        persist()
    }

    func start(assistantCard: AssistantCard) {
        state.activeRoleCardId = ""
        state.activeAssistantMode = assistantCard.id
        state.conversation = []
        statusText = "\(assistantCard.displayName) 已啟用。"
        persist()
    }

    func deleteRoleCards(at offsets: IndexSet) {
        state.roleCards.remove(atValidOffsets: offsets)
        if !state.roleCards.contains(where: { $0.id == state.activeRoleCardId }) {
            state.activeRoleCardId = ""
        }
        persist()
    }

    func update(roleCard: RoleCard) {
        if let index = state.roleCards.firstIndex(where: { $0.id == roleCard.id }) {
            var next = roleCard
            next.updatedAt = Date()
            state.roleCards[index] = next
            persist()
        }
    }

    func sendCurrentMessage() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composerText = ""
        send(text)
    }

    func send(_ text: String) {
        generationTask?.cancel()
        isGenerating = true
        let userTurn = state.conversation.filter { $0.role == .user }.count + 1
        let userMessage = ConversationMessage(role: .user, content: text, turnNumber: userTurn)
        var assistantMessage = ConversationMessage(role: .assistant, content: "", turnNumber: userTurn)
        state.conversation.append(userMessage)
        conversationEngine.updateTimeTrackingFromUserMessage(state: &state, text: text)
        state.conversation.append(assistantMessage)
        let assistantID = assistantMessage.id
        let apiKey = nextDeepSeekChatKey()
        let chatPurpose = state.activeAssistantCard == nil ? "reasoner_history_chat" : "character_card_creation_assistant_chat"
        generationTask = Task { [weak self] in
            guard let self else { return }
            var requestMessages = [ChatAPIMessage(role: "user", content: text)]
            do {
                let beforeCompression = await applyCompressionForTurn(
                    latestUserInput: text,
                    latestAssistantText: "",
                    phase: .beforeReasoner,
                    assistantID: assistantID
                )
                if beforeCompression.skipReasoner {
                    let completionText = ConversationEngine.modelProcessingCompletionMessage(for: beforeCompression.skipRequests)
                    if let index = state.conversation.firstIndex(where: { $0.id == assistantID }) {
                        state.conversation[index].content = completionText
                        assistantMessage = state.conversation[index]
                    }
                    state.aiLogs.insert(AILogEntry(
                        purpose: chatPurpose,
                        model: "model_processing",
                        temperature: state.apiSettings.temperature,
                        maxTokens: state.apiSettings.maxTokens,
                        requestMessages: requestMessages,
                        responseText: completionText,
                        status: "success"
                    ), at: 0)
                    trimRuntimeLimits()
                    statusText = "大模型處理完成。"
                    isGenerating = false
                    persist()
                    return
                }

                let messages = try conversationEngine.buildPromptMessages(state: state, userInput: text)
                requestMessages = messages
                let result = try await deepSeekClient.streamCompletion(
                    apiKey: apiKey,
                    settings: state.apiSettings,
                    messages: messages
                ) { delta in
                    Task { @MainActor in
                        guard let index = self.state.conversation.firstIndex(where: { $0.id == assistantID }) else { return }
                        self.state.conversation[index].content += delta
                    }
                }
                if let index = state.conversation.firstIndex(where: { $0.id == assistantID }) {
                    state.conversation[index].content = result.content
                    assistantMessage = state.conversation[index]
                }
                let autoTimeWarning = conversationEngine.updateTimeTrackingAfterAssistantTurn(
                    state: &state,
                    assistantText: result.content,
                    userInput: text
                )
                if let index = state.conversation.firstIndex(where: { $0.id == assistantID }) {
                    state.conversation[index].autoTimeWarning = autoTimeWarning
                    assistantMessage = state.conversation[index]
                }
                state.aiLogs.insert(AILogEntry(
                    purpose: chatPurpose,
                    model: result.model,
                    temperature: state.apiSettings.temperature,
                    maxTokens: state.apiSettings.maxTokens,
                    requestMessages: messages,
                    responseText: result.content,
                    debugReasoningContent: result.reasoningContent,
                    usage: result.usage
                ), at: 0)
                await applyCompressionForTurn(
                    latestUserInput: text,
                    latestAssistantText: result.content,
                    phase: .afterAssistant,
                    assistantID: assistantID
                )
                trimRuntimeLimits()
                statusText = "生成完成。"
            } catch is CancellationError {
                statusText = "生成已取消。"
            } catch {
                if let index = state.conversation.firstIndex(where: { $0.id == assistantID }) {
                    state.conversation[index].content = error.localizedDescription
                }
                state.aiLogs.insert(AILogEntry(
                    purpose: chatPurpose,
                    model: state.apiSettings.deepSeekModel,
                    temperature: state.apiSettings.temperature,
                    maxTokens: state.apiSettings.maxTokens,
                    requestMessages: requestMessages,
                    responseText: "",
                    error: error.localizedDescription,
                    status: "error"
                ), at: 0)
                statusText = error.localizedDescription
            }
            isGenerating = false
            persist()
        }
    }

    @discardableResult
    private func applyCompressionForTurn(
        latestUserInput: String,
        latestAssistantText: String,
        phase: CompressionProcessingPhase,
        assistantID: String
    ) async -> CompressionPhaseResult {
        let requests = conversationEngine.compressionAPIRequests(
            state: state,
            latestUserInput: latestUserInput,
            latestAssistantText: latestAssistantText,
            phase: phase
        )
        let imageRequests = conversationEngine.compressionImageRequests(
            state: state,
            latestUserInput: latestUserInput,
            latestAssistantText: latestAssistantText,
            phase: phase
        )
        state.promptModes = conversationEngine.applyCompressionIfNeeded(
            state: state,
            latestUserInput: latestUserInput,
            latestAssistantText: latestAssistantText,
            phase: phase
        )
        guard !requests.isEmpty || !imageRequests.isEmpty else { return CompressionPhaseResult() }

        var completed = 0
        var skipRequests: [CompressionAPIRequest] = []
        for request in requests {
            do {
                let key = currentDeepSeekKeySet().contextCompressionKey(profileIndex: request.profileIndex)
                let result = try await deepSeekClient.complete(
                    apiKey: key,
                    settings: state.apiSettings,
                    messages: request.messages
                )
                state.promptModes = conversationEngine.applyCompressionCompletion(
                    state: state,
                    request: request,
                    completion: result.content
                )
                state.aiLogs.insert(AILogEntry(
                    purpose: compressionPurpose(profileID: request.profileID),
                    model: result.model,
                    temperature: state.apiSettings.temperature,
                    maxTokens: state.apiSettings.maxTokens,
                    requestMessages: request.messages,
                    responseText: result.content,
                    debugReasoningContent: result.reasoningContent,
                    usage: result.usage
                ), at: 0)
                completed += 1
                if request.skipReasoner {
                    skipRequests.append(request)
                }
            } catch {
                state.aiLogs.insert(AILogEntry(
                    purpose: compressionPurpose(profileID: request.profileID),
                    model: state.apiSettings.deepSeekModel,
                    temperature: state.apiSettings.temperature,
                    maxTokens: state.apiSettings.maxTokens,
                    requestMessages: request.messages,
                    responseText: "",
                    error: error.localizedDescription,
                    status: "error"
                ), at: 0)
            }
        }
        for request in imageRequests {
            do {
                let key = currentDeepSeekKeySet().contextCompressionKey(profileIndex: request.profileIndex)
                let promptResult = try await deepSeekClient.complete(
                    apiKey: key,
                    settings: state.apiSettings,
                    messages: request.messages
                )
                let basePrompt = promptResult.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !basePrompt.isEmpty else {
                    throw TimeTavernError.network("跑圖大模型沒有輸出 NovelAI Base Prompt。")
                }
                state.promptModes = conversationEngine.applyImageCompressionStarted(state: state, request: request)
                var studioSettings = NovelAIStudioSettings()
                studioSettings.basePrompt = basePrompt
                studioSettings.negativePrompt = request.imageSettings.negativePrompt
                studioSettings.imageSettings = request.imageSettings
                let images = try await novelAIClient.generateImages(
                    apiKey: novelAIKey,
                    settings: state.apiSettings,
                    studioSettings: studioSettings
                )
                state.novelAIAlbum.insert(contentsOf: images, at: 0)
                let imageCount = images.count
                state.conversation.append(ConversationMessage(
                    role: .assistant,
                    content: "【\(request.triggerActionName)】圖片生成完成" + (imageCount > 0 ? "（\(imageCount) 張，已保存到 NovelAI 相簿）" : ""),
                    source: "model_image",
                    turnNumber: request.turnNumber,
                    imageData: images.first?.imageData
                ))
                state.aiLogs.insert(AILogEntry(
                    purpose: compressionPurpose(profileID: request.profileID, suffix: "image_prompt"),
                    model: "\(promptResult.model) + \(NovelAIModelOption.title(for: request.imageSettings.model))",
                    temperature: state.apiSettings.temperature,
                    maxTokens: state.apiSettings.maxTokens,
                    requestMessages: request.messages,
                    responseText: basePrompt,
                    debugReasoningContent: promptResult.reasoningContent,
                    usage: promptResult.usage
                ), at: 0)
                completed += 1
            } catch {
                state.conversation.append(ConversationMessage(
                    role: .assistant,
                    content: "【\(request.triggerActionName)】圖片生成失敗：\(error.localizedDescription)",
                    source: "model_image",
                    turnNumber: request.turnNumber
                ))
                state.aiLogs.insert(AILogEntry(
                    purpose: compressionPurpose(profileID: request.profileID, suffix: "image_prompt"),
                    model: state.apiSettings.deepSeekModel,
                    temperature: state.apiSettings.temperature,
                    maxTokens: state.apiSettings.maxTokens,
                    requestMessages: request.messages,
                    responseText: "",
                    error: error.localizedDescription,
                    status: "error"
                ), at: 0)
            }
        }
        if completed > 0, let index = state.conversation.firstIndex(where: { $0.id == assistantID }) {
            state.conversation[index].compressionNotice = true
        }
        return CompressionPhaseResult(
            completed: completed,
            skipReasoner: !skipRequests.isEmpty,
            skipRequests: skipRequests
        )
    }

    func cancelGeneration() {
        generationTask?.cancel()
        isGenerating = false
    }

    func regenerateLatestAssistant() {
        guard let assistantIndex = state.conversation.lastIndex(where: { $0.role == .assistant }) else { return }
        let user = state.conversation[..<assistantIndex].last(where: { $0.role == .user })
        guard let user else { return }
        state.savedSessions.insert(conversationEngine.branchSession(from: state, name: "重跑前備份"), at: 0)
        state.conversation.removeSubrange(assistantIndex..<state.conversation.endIndex)
        persist()
        send(user.content)
    }

    func replay(from message: ConversationMessage, with newContent: String) {
        guard let index = state.conversation.firstIndex(where: { $0.id == message.id }) else { return }
        state.savedSessions.insert(conversationEngine.branchSession(from: state, name: "分支前備份"), at: 0)
        state.conversation.removeSubrange(index..<state.conversation.endIndex)
        persist()
        send(newContent)
    }

    func updateMessage(id: String, content: String) {
        guard let index = state.conversation.firstIndex(where: { $0.id == id }) else { return }
        state.conversation[index].content = content
        state.conversation[index].updatedAt = Date()
        persist()
    }

    func setMessageFeedback(id: String, feedback: String) {
        guard let index = state.conversation.firstIndex(where: { $0.id == id }) else { return }
        state.conversation[index].feedback = ["positive", "negative"].contains(feedback) ? feedback : ""
        state.conversation[index].updatedAt = Date()
        persist()
    }

    func runTime(turns: Int, seedMessage: String) {
        guard let normalizedTurns = ConversationEngine.normalizedRuntimeTurns(turns) else {
            statusText = uiStatic("請提供有效輪數，最少為 1。")
            return
        }
        let request = seedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            statusText = uiStatic("請提供 /run_time 的推演要求。")
            return
        }
        guard state.activeAssistantMode.isEmpty else {
            statusText = "CharacterCardCreationAssistant 不支援 /run_time 自動推演。"
            return
        }
        Task { @MainActor in
            for index in 1...normalizedTurns {
                if Task.isCancelled { break }
                send(ConversationEngine.runtimeTurnUserContent(
                    message: request,
                    turnNumber: index,
                    totalTurns: normalizedTurns
                ))
                while isGenerating {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
            statusText = uiStatic("已完成 \(normalizedTurns) 輪推演。")
        }
    }

    func saveSession(named name: String) {
        let session = conversationEngine.branchSession(
            from: state,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名存檔" : name
        )
        state.savedSessions.insert(session, at: 0)
        persist()
    }

    func load(session: SavedSession) {
        state.roleCards = session.roleCards
        state.promptModes = session.promptModes
        state.activeRoleCardId = session.activeRoleCardId
        state.conversation = session.conversation
        state.aiLogs = session.aiLogs
        persist()
    }

    func deleteSessions(at offsets: IndexSet) {
        state.savedSessions.remove(atValidOffsets: offsets)
        persist()
    }

    func renameSession(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = state.savedSessions.firstIndex(where: { $0.id == id })
        else { return }
        state.savedSessions[index].name = trimmed
        state.savedSessions[index].updatedAt = Date()
        persist()
    }

    func setSessionArchived(id: String, archived: Bool) {
        guard let index = state.savedSessions.firstIndex(where: { $0.id == id }) else { return }
        state.savedSessions[index].archived = archived
        state.savedSessions[index].updatedAt = Date()
        persist()
    }

    func deleteSession(id: String) {
        state.savedSessions.removeAll { $0.id == id }
        persist()
    }

    func importRoleCardJSON(url: URL) {
        do {
            let card = try importExportService.importRoleCardJSON(from: url, existingRoleCards: state.roleCards)
            state.roleCards.insert(card, at: 0)
            statusText = "已匯入角色卡：\(card.name)"
            persist()
        } catch {
            statusText = "匯入角色卡失敗：\(error.localizedDescription)"
        }
    }

    func importRoleCardFile(url: URL) {
        do {
            let card = try importExportService.importRoleCardFile(from: url, existingRoleCards: state.roleCards)
            state.roleCards.insert(card, at: 0)
            statusText = "已匯入角色卡：\(card.name)"
            persist()
        } catch {
            statusText = "匯入角色卡失敗：\(error.localizedDescription)"
        }
    }

    func importPromptModeJSON(url: URL) {
        do {
            let mode = try importExportService.importPromptModeJSON(from: url, existingModes: state.promptModes)
            state.promptModes.append(mode)
            statusText = "已匯入模式：\(mode.name)"
            persist()
        } catch {
            statusText = "匯入模式失敗：\(error.localizedDescription)"
        }
    }

    func importCompressionProfileJSON(url: URL, modeID: String) {
        do {
            guard let index = state.promptModes.firstIndex(where: { $0.id == modeID }) else {
                throw TimeTavernError.invalidImport
            }
            let profile = try importExportService.importCompressionProfileJSON(
                from: url,
                existingProfiles: state.promptModes[index].compressionProfiles
            )
            state.promptModes[index].compressionProfiles.append(profile)
            statusText = "已匯入大模型：\(profile.name)"
            persist()
        } catch {
            statusText = "匯入大模型失敗：\(error.localizedDescription)"
        }
    }

    func exportRoleCardJSON(_ card: RoleCard) {
        do {
            exportedJSONURL = try importExportService.exportRoleCardJSON(card)
            statusText = "已建立角色卡 JSON。"
        } catch {
            statusText = "匯出角色卡失敗：\(error.localizedDescription)"
        }
    }

    func exportPromptModeJSON(_ mode: PromptModeConfig) {
        do {
            exportedJSONURL = try importExportService.exportPromptModeJSON(mode)
            statusText = "已建立模式 JSON。"
        } catch {
            statusText = "匯出模式失敗：\(error.localizedDescription)"
        }
    }

    func exportCompressionProfileJSON(_ profile: CompressionProfile) {
        do {
            exportedJSONURL = try importExportService.exportCompressionProfileJSON(profile)
            statusText = "已建立大模型 JSON。"
        } catch {
            statusText = "匯出大模型失敗：\(error.localizedDescription)"
        }
    }

    func bundledWebDefaultsSummary() -> BundledWebDefaultsSummary? {
        try? bundledWebDefaultsService.summary()
    }

    func saveCurrentAsLocalDefaults() {
        state.localDefaults = AppDefaultsSnapshot(state: state)
        statusText = "已保存目前角色卡、模式、使用者、時間、API 與 NovelAI 設定為本機預設。"
        persist()
    }

    func restoreDefaultsPreferLocal() {
        do {
            let localDefaults = state.localDefaults
            let restored: AppState
            if let localDefaults {
                restored = Self.appState(from: localDefaults)
            } else {
                restored = try bundledWebDefaultsService.loadDefaults()
            }
            let backup = conversationEngine.branchSession(from: state, name: "還原預設前備份")
            let preservedSessions = state.savedSessions
            let preservedAlbum = state.novelAIAlbum
            let preservedLogs = state.aiLogs

            var next = state
            next.roleCards = restored.roleCards
            next.promptModes = restored.promptModes
            next.userProfile = restored.userProfile
            next.timeTracking = restored.timeTracking
            next.apiSettings = restored.apiSettings
            next.novelAIStudioSettings = restored.novelAIStudioSettings
            next.activeRoleCardId = restored.activeRoleCardId
            next.activeAssistantMode = restored.activeAssistantMode
            next.characterCardCreationAssistantPrompt = restored.characterCardCreationAssistantPrompt
            next.conversation = []
            next.savedSessions = [backup] + preservedSessions
            next.novelAIAlbum = preservedAlbum
            next.aiLogs = preservedLogs
            next.localDefaults = localDefaults
            state = next
            let source = localDefaults == nil ? "網頁 bundle 預設" : "本機預設"
            statusText = "已還原\(source)：\(restored.roleCards.count) 張角色卡、\(restored.promptModes.count) 個 Prompt 模式。"
            persist()
        } catch {
            statusText = "還原預設失敗：\(error.localizedDescription)"
        }
    }

    func restoreBundledWebDefaults() {
        restoreDefaultsPreferLocal()
    }

    func resetCharacterCardCreationAssistantPrompt() {
        let bundledPrompt = (try? bundledWebDefaultsService.loadDefaults().characterCardCreationAssistantPrompt) ?? ""
        state.characterCardCreationAssistantPrompt = bundledPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AssistantCard.defaultPrompt
            : bundledPrompt
        persist()
    }

    private static func appState(from snapshot: AppDefaultsSnapshot) -> AppState {
        var state = AppState()
        state.userProfile = snapshot.userProfile
        state.apiSettings = snapshot.apiSettings
        state.roleCards = snapshot.roleCards
        state.activeRoleCardId = snapshot.activeRoleCardId
        state.activeAssistantMode = snapshot.activeAssistantMode
        state.characterCardCreationAssistantPrompt = snapshot.characterCardCreationAssistantPrompt
        state.promptModes = snapshot.promptModes
        state.timeTracking = snapshot.timeTracking
        state.novelAIStudioSettings = snapshot.novelAIStudioSettings
        return state
    }

    func testDeepSeek() {
        Task {
            do {
                let response = try await deepSeekClient.testConnection(apiKey: currentDeepSeekKeySet().primaryOrFirstKey, settings: state.apiSettings)
                await MainActor.run { statusText = "DeepSeek OK: \(response)" }
            } catch {
                await MainActor.run { statusText = error.localizedDescription }
            }
        }
    }

    func testNovelAI() {
        Task {
            do {
                let response = try await novelAIClient.status(apiKey: novelAIKey, settings: state.apiSettings)
                await MainActor.run { statusText = "NovelAI OK: \(response.prefixString(300))" }
            } catch {
                await MainActor.run { statusText = error.localizedDescription }
            }
        }
    }

    func generateNovelAIImage(prompt: String, negativePrompt: String, model: String, width: Int, height: Int, steps: Int, scale: Double) {
        var studioSettings = state.novelAIStudioSettings
        studioSettings.basePrompt = prompt
        studioSettings.negativePrompt = negativePrompt
        studioSettings.imageSettings.model = NovelAIModelOption.knownIDOrDefault(model)
        studioSettings.imageSettings.width = width
        studioSettings.imageSettings.height = height
        studioSettings.imageSettings.steps = steps
        studioSettings.imageSettings.scale = scale
        generateNovelAIImage(studioSettings: studioSettings)
    }

    func generateNovelAIImage(studioSettings: NovelAIStudioSettings) {
        novelAIGenerationTask?.cancel()
        isNovelAIGenerating = true
        isNovelAILoopRunning = false
        let apiKey = novelAIKey
        let apiSettings = state.apiSettings
        novelAIGenerationTask = Task {
            do {
                let images = try await novelAIClient.generateImages(
                    apiKey: apiKey,
                    settings: apiSettings,
                    studioSettings: studioSettings,
                    requestCount: 1
                )
                await MainActor.run {
                    state.novelAIStudioSettings = studioSettings
                    state.novelAIAlbum.insert(contentsOf: images, at: 0)
                    statusText = "NovelAI 已生成 \(images.count) 張圖片。"
                    isNovelAIGenerating = false
                    persist()
                }
            } catch is CancellationError {
                await MainActor.run {
                    statusText = "NovelAI 生成已停止。"
                    isNovelAIGenerating = false
                }
            } catch {
                await MainActor.run {
                    statusText = error.localizedDescription
                    isNovelAIGenerating = false
                }
            }
        }
    }

    func loopGenerateNovelAIImages(studioSettings: NovelAIStudioSettings) {
        if isNovelAILoopRunning {
            stopNovelAIGeneration()
            return
        }
        novelAIGenerationTask?.cancel()
        isNovelAIGenerating = true
        isNovelAILoopRunning = true
        let apiKey = novelAIKey
        let apiSettings = state.apiSettings
        let limit = NovelAIClient.loopRequestLimit(from: studioSettings.loopCount)
        novelAIGenerationTask = Task {
            var completed = 0
            do {
                while !Task.isCancelled && (limit == nil || completed < (limit ?? 0)) {
                    let images = try await novelAIClient.generateImages(
                        apiKey: apiKey,
                        settings: apiSettings,
                        studioSettings: studioSettings,
                        requestCount: 1
                    )
                    completed += 1
                    await MainActor.run {
                        state.novelAIStudioSettings = studioSettings
                        state.novelAIAlbum.insert(contentsOf: images, at: 0)
                        let total = limit.map(String.init) ?? "∞"
                        statusText = "Loop Generate \(completed)/\(total)，已新增 \(images.count) 張。"
                        persist()
                    }
                    if Task.isCancelled || limit.map({ completed >= $0 }) == true {
                        break
                    }
                    try await Task.sleep(nanoseconds: UInt64(Int.random(in: 1_000...5_000)) * 1_000_000)
                }
                await MainActor.run {
                    statusText = "Loop Generate 已完成 \(completed) 次。"
                    isNovelAIGenerating = false
                    isNovelAILoopRunning = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    statusText = "Loop Generate 已停止，已完成 \(completed) 次。"
                    isNovelAIGenerating = false
                    isNovelAILoopRunning = false
                }
            } catch {
                await MainActor.run {
                    statusText = error.localizedDescription
                    isNovelAIGenerating = false
                    isNovelAILoopRunning = false
                }
            }
        }
    }

    func stopNovelAIGeneration() {
        novelAIGenerationTask?.cancel()
        isNovelAIGenerating = false
        isNovelAILoopRunning = false
        statusText = "Loop Generate 會停止目前工作。"
    }

    func deleteNovelAIAlbumItems(at offsets: IndexSet) {
        state.novelAIAlbum.remove(atValidOffsets: offsets)
        persist()
    }

    func deleteNovelAIAlbumItem(id: String) {
        state.novelAIAlbum.removeAll { $0.id == id }
        persist()
    }

    private func compressionPurpose(profileID: String, suffix: String = "") -> String {
        let normalizedID = profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = normalizedID == "standard" || normalizedID.isEmpty
            ? "context_compression"
            : "context_compression:\(normalizedID)"
        return suffix.isEmpty ? base : "\(base):\(suffix)"
    }

    private func trimRuntimeLimits() {
        if state.conversation.count > 500 {
            state.conversation = Array(state.conversation.suffix(500))
        }
        if state.aiLogs.count > 200 {
            state.aiLogs = Array(state.aiLogs.prefix(200))
        }
    }
}

private extension String {
    func prefixString(_ maxLength: Int) -> String {
        String(prefix(maxLength))
    }
}
