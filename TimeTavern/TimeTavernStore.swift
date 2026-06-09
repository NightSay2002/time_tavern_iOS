import Foundation
import SwiftData

@MainActor
private final class StreamingAssistantMessageUpdater {
    private weak var store: TimeTavernStore?
    private let assistantID: String
    private var contentBuffer = ""
    private var reasoningBuffer = ""
    private var didStartContent = false
    private var flushTask: Task<Void, Never>?

    init(store: TimeTavernStore, assistantID: String) {
        self.store = store
        self.assistantID = assistantID
    }

    func receive(_ delta: ChatStreamDelta) {
        switch delta.kind {
        case .reasoning:
            guard !didStartContent else { return }
            reasoningBuffer += delta.text
            scheduleFlush()
        case .content:
            let isFirstContent = !didStartContent
            didStartContent = true
            reasoningBuffer = ""
            contentBuffer += delta.text
            if isFirstContent {
                flush()
            } else {
                scheduleFlush()
            }
        }
    }

    func finish(content: String) {
        flushTask?.cancel()
        flushTask = nil
        contentBuffer = content
        didStartContent = true
        reasoningBuffer = ""
        flush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: TimeTavernStore.streamingUIFlushIntervalNanoseconds)
            self?.flush()
        }
    }

    private func flush() {
        flushTask?.cancel()
        flushTask = nil
        if didStartContent {
            store?.updateStreamingAssistantMessage(
                assistantID: assistantID,
                content: contentBuffer,
                reasoningPreview: ""
            )
        } else {
            store?.updateStreamingAssistantMessage(
                assistantID: assistantID,
                content: nil,
                reasoningPreview: reasoningBuffer
            )
        }
    }
}

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
    static let compressionJSONMaxAttempts = 2
    static let streamingUIFlushIntervalNanoseconds: UInt64 = 60_000_000

    private struct CompressionPhaseResult {
        var completed: Int = 0
        var skipReasoner: Bool = false
        var skipRequests: [CompressionAPIRequest] = []
        var warning: String = ""
    }

    nonisolated static func shouldMarkCompressionNotice(completedProfileIDs: [String]) -> Bool {
        completedProfileIDs.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "standard" }
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
        if handleSlashCommandIfNeeded(text) {
            return
        }
        send(text)
    }

    @discardableResult
    func handleSlashCommandIfNeeded(_ text: String) -> Bool {
        guard let command = Self.slashCommandParts(text) else { return false }
        switch command.keyword {
        case "ai_help", "help":
            statusText = Self.slashCommandHelpText
        case "ai_status", "status":
            let activeRoleName = state.activeRoleCard?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let roleName = activeRoleName?.isEmpty == false ? activeRoleName ?? "未開始" : state.activeAssistantCard?.displayName ?? "未開始"
            statusText = "角色：\(roleName)；對話 \(state.conversation.count) 則；\(isGenerating ? "生成中" : "閒置")。"
        case "stop":
            let wasGenerating = isGenerating
            cancelGeneration()
            statusText = wasGenerating ? "已停止生成。" : "目前沒有正在生成。"
        case "ai_start", "start":
            if let roleCard = state.activeRoleCard {
                start(roleCard: roleCard)
            } else {
                statusText = "請先在角色頁選擇角色卡。"
            }
        case "reload":
            regenerateLatestAssistant()
        case "run_time":
            let parsed = Self.parseRunTimeArguments(command.argumentText)
            runTime(turns: parsed.turns, seedMessage: parsed.message)
        case "session_save":
            saveSession(named: command.argumentText.isEmpty ? "Slash 存檔" : command.argumentText)
            statusText = "已保存目前對話。"
        case "session_list":
            let names = state.savedSessions.prefix(5).map(\.name).joined(separator: "、")
            statusText = names.isEmpty ? "沒有可載入的存檔。" : "最近存檔：\(names)"
        case "session_load":
            guard !command.argumentText.isEmpty else {
                statusText = "請提供存檔 ID 或名稱。"
                return true
            }
            guard let session = state.savedSessions.first(where: { session in
                session.id == command.argumentText || session.name.localizedCaseInsensitiveContains(command.argumentText)
            }) else {
                statusText = "找不到指定存檔。"
                return true
            }
            load(session: session)
            statusText = "已載入存檔：\(session.name)"
        case "replay":
            statusText = "手機端請長按訊息選擇「從此分支重跑」。"
        default:
            return false
        }
        return true
    }

    static func slashCommandParts(_ text: String) -> (keyword: String, argumentText: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return ("ai_help", "") }
        let parts = body.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        let keyword = parts.first.map { String($0).lowercased() } ?? "ai_help"
        let argumentText = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return (keyword, argumentText)
    }

    static func parseRunTimeArguments(_ text: String) -> (turns: Int, message: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        if let first = parts.first, let turns = Int(first) {
            let message = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : "請根據目前劇情自然推進。"
            return (turns, message)
        }
        return (3, trimmed.isEmpty ? "請根據目前劇情自然推進。" : trimmed)
    }

    static let slashCommandHelpText = "/ai_start、/ai_status、/stop、/reload、/replay、/run_time、/session_save、/session_list、/session_load"

    func send(_ text: String) {
        guard !isGenerating else {
            statusText = uiStatic("生成中，請先停止目前回覆。")
            return
        }
        let userTurn = state.conversation.filter { $0.role == .user }.count + 1
        let userMessage = ConversationMessage(
            role: .user,
            content: text,
            turnNumber: userTurn,
            stateBeforeTurnSnapshot: captureNarrativeSnapshot()
        )
        state.conversation.append(userMessage)
        startAssistantGeneration(for: userMessage, updateTimeTrackingFromUser: true)
    }

    private func startAssistantGeneration(for userMessage: ConversationMessage, updateTimeTrackingFromUser: Bool) {
        generationTask?.cancel()
        isGenerating = true
        let text = userMessage.content
        var assistantMessage = ConversationMessage(role: .assistant, content: "", turnNumber: userMessage.turnNumber)
        if updateTimeTrackingFromUser {
            conversationEngine.updateTimeTrackingFromUserMessage(state: &state, text: text)
        }
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
                        state.conversation[index].stateAfterTurnSnapshot = captureNarrativeSnapshot()
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
                let streamUpdater = StreamingAssistantMessageUpdater(store: self, assistantID: assistantID)
                let result = try await deepSeekClient.streamCompletion(
                    apiKey: apiKey,
                    settings: state.apiSettings,
                    messages: messages
                ) { delta in
                    Task { @MainActor in
                        streamUpdater.receive(delta)
                    }
                }
                streamUpdater.finish(content: result.content)
                if let index = state.conversation.firstIndex(where: { $0.id == assistantID }) {
                    state.conversation[index].content = result.content
                    state.conversation[index].streamingReasoningPreview = ""
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
                let afterCompression = await applyCompressionForTurn(
                    latestUserInput: text,
                    latestAssistantText: result.content,
                    phase: .afterAssistant,
                    assistantID: assistantID
                )
                if let index = state.conversation.firstIndex(where: { $0.id == assistantID }) {
                    state.conversation[index].stateAfterTurnSnapshot = captureNarrativeSnapshot()
                    assistantMessage = state.conversation[index]
                }
                trimRuntimeLimits()
                let compressionWarning = afterCompression.warning.isEmpty ? beforeCompression.warning : afterCompression.warning
                statusText = compressionWarning.isEmpty ? "生成完成。" : compressionWarning
            } catch is CancellationError {
                statusText = "生成已取消。"
                if let index = state.conversation.firstIndex(where: { $0.id == assistantID }) {
                    state.conversation[index].streamingReasoningPreview = ""
                }
            } catch {
                if let index = state.conversation.firstIndex(where: { $0.id == assistantID }) {
                    state.conversation[index].content = error.localizedDescription
                    state.conversation[index].streamingReasoningPreview = ""
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

    fileprivate func updateStreamingAssistantMessage(
        assistantID: String,
        content: String?,
        reasoningPreview: String?
    ) {
        guard let index = state.conversation.firstIndex(where: { $0.id == assistantID }) else { return }
        if let content {
            state.conversation[index].content = content
        }
        if let reasoningPreview {
            state.conversation[index].streamingReasoningPreview = reasoningPreview
        }
        state.conversation[index].updatedAt = Date()
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
        var completedProfileIDs: [String] = []
        var skipRequests: [CompressionAPIRequest] = []
        var warning = ""
        for request in requests {
            do {
                let key = currentDeepSeekKeySet().contextCompressionKey(profileIndex: request.profileIndex)
                let result = try await completeValidatedCompressionRequest(request: request, apiKey: key)
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
                completedProfileIDs.append(request.profileID)
                if request.skipReasoner {
                    skipRequests.append(request)
                }
            } catch {
                warning = error.localizedDescription
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
        if Self.shouldMarkCompressionNotice(completedProfileIDs: completedProfileIDs),
           let index = state.conversation.firstIndex(where: { $0.id == assistantID }) {
            state.conversation[index].compressionNotice = true
        }
        return CompressionPhaseResult(
            completed: completed,
            skipReasoner: !skipRequests.isEmpty,
            skipRequests: skipRequests,
            warning: warning
        )
    }

    private func completeValidatedCompressionRequest(
        request: CompressionAPIRequest,
        apiKey: String
    ) async throws -> ChatCompletionResult {
        var lastValidationError = ""
        var messages = request.messages
        for attempt in 1...Self.compressionJSONMaxAttempts {
            let result = try await deepSeekClient.complete(
                apiKey: apiKey,
                settings: state.apiSettings,
                messages: messages
            )
            guard let validationError = conversationEngine.compressionCompletionValidationError(
                state: state,
                request: request,
                completion: result.content
            ) else {
                return result
            }
            lastValidationError = validationError
            if attempt < Self.compressionJSONMaxAttempts {
                messages = request.messages + [compressionJSONRetryMessage(validationError: validationError)]
                continue
            }
        }
        throw TimeTavernError.network("大模型輸出 JSON 格式不正確，已重試一次仍失敗：\(lastValidationError)")
    }

    private func compressionJSONRetryMessage(validationError: String) -> ChatAPIMessage {
        ChatAPIMessage(
            role: "user",
            content: """
            上一次輸出格式錯誤：\(validationError)

            請重新生成一次。只能輸出一個合法 JSON 物件，不要 Markdown，不要解釋文字，不要尾逗號。
            必須使用頂層 model / delete：
            {"model":{"模塊ID":["新增內容"]},"delete":{"模塊ID":["刪除內容"]}}

            不可使用 {"WorldLore":{"add":[],"delete":[]}} 這種每個模塊各自 add/delete 的格式。
            """
        )
    }

    func cancelGeneration() {
        generationTask?.cancel()
        isGenerating = false
    }

    private func captureNarrativeSnapshot() -> ConversationTurnSnapshot {
        ConversationTurnSnapshot(state: state)
    }

    private func applyNarrativeSnapshot(_ snapshot: ConversationTurnSnapshot) {
        state.promptModes = snapshot.promptModes
        state.timeTracking = snapshot.timeTracking
    }

    private func restoreNarrativeStateForReplay(targetIndex: Int) {
        guard state.conversation.indices.contains(targetIndex) else { return }
        if let snapshot = state.conversation[targetIndex].stateBeforeTurnSnapshot {
            applyNarrativeSnapshot(snapshot)
            return
        }
        if targetIndex > 0 {
            for index in stride(from: targetIndex - 1, through: 0, by: -1) {
                if let snapshot = state.conversation[index].stateAfterTurnSnapshot {
                    applyNarrativeSnapshot(snapshot)
                    return
                }
                if let snapshot = state.conversation[index].stateBeforeTurnSnapshot {
                    applyNarrativeSnapshot(snapshot)
                    return
                }
            }
        }
        let replayTurn = state.conversation[targetIndex].turnNumber
        state.promptModes = conversationEngine.rollbackCompressionProgressForReplay(
            state: state,
            replayTurnNumber: replayTurn
        )
    }

    func regenerateLatestAssistant() {
        guard !isGenerating else {
            statusText = uiStatic("生成中，請先停止目前回覆。")
            return
        }
        guard let assistantIndex = state.conversation.lastIndex(where: { $0.role == .assistant }) else { return }
        let user = state.conversation[..<assistantIndex].last(where: { $0.role == .user })
        guard let user else { return }
        guard let userIndex = state.conversation.firstIndex(where: { $0.id == user.id }) else { return }
        state.savedSessions.insert(conversationEngine.branchSession(from: state, name: "重跑前備份"), at: 0)
        restoreNarrativeStateForReplay(targetIndex: userIndex)
        if state.conversation[userIndex].stateBeforeTurnSnapshot == nil {
            state.conversation[userIndex].stateBeforeTurnSnapshot = captureNarrativeSnapshot()
        }
        state.conversation.removeSubrange(assistantIndex..<state.conversation.endIndex)
        persist()
        startAssistantGeneration(for: state.conversation[userIndex], updateTimeTrackingFromUser: true)
    }

    func replay(from message: ConversationMessage, with newContent: String) {
        guard !isGenerating else {
            statusText = uiStatic("生成中，請先停止目前回覆。")
            return
        }
        guard let index = state.conversation.firstIndex(where: { $0.id == message.id }) else { return }
        state.savedSessions.insert(conversationEngine.branchSession(from: state, name: "分支前備份"), at: 0)
        restoreNarrativeStateForReplay(targetIndex: index)
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
        state.conversation[index].feedback = Self.normalizedMessageFeedback(feedback)
        state.conversation[index].updatedAt = Date()
        persist()
    }

    static func normalizedMessageFeedback(_ feedback: String) -> String {
        switch feedback.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "like", "liked", "positive", "up", "thumbsup", "👍":
            return "like"
        case "dislike", "negative", "down", "thumbsdown", "👎":
            return "dislike"
        default:
            return ""
        }
    }

    func runTime(turns: Int, seedMessage: String) {
        guard !isGenerating else {
            statusText = uiStatic("生成中，請先停止目前回覆。")
            return
        }
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
