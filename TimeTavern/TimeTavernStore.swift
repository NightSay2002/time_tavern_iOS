import Foundation
import SwiftData

@MainActor
final class TimeTavernStore: ObservableObject {
    @Published var state = AppState()
    @Published var deepSeekKey = ""
    @Published var novelAIKey = ""
    @Published var composerText = ""
    @Published var statusText = ""
    @Published var isGenerating = false
    @Published var exportedJSONURL: URL?

    private let secretStore = SecretStore()
    private let deepSeekClient = DeepSeekClient()
    private let novelAIClient = NovelAIClient()
    private let conversationEngine = ConversationEngine()
    private let importExportService = ImportExportService()
    private let bundledWebDefaultsService = BundledWebDefaultsService()
    private var database: AppDatabase?
    private var generationTask: Task<Void, Never>?

    func attach(modelContext: ModelContext) {
        guard database == nil else { return }
        database = AppDatabase(context: modelContext)
        state = database?.loadState() ?? AppState()
        deepSeekKey = (try? secretStore.read(.deepSeekAPIKey)) ?? ""
        novelAIKey = (try? secretStore.read(.novelAIAPIKey)) ?? ""
    }

    func saveSecrets() {
        do {
            try secretStore.save(deepSeekKey, for: .deepSeekAPIKey)
            try secretStore.save(novelAIKey, for: .novelAIAPIKey)
            statusText = "API keys 已保存到 Keychain。"
        } catch {
            statusText = error.localizedDescription
        }
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
            state.conversation.append(ConversationMessage(role: .assistant, content: opening, source: "opening"))
        }
        persist()
    }

    func deleteRoleCards(at offsets: IndexSet) {
        state.roleCards.remove(atOffsets: offsets)
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
        state.conversation.append(assistantMessage)
        let assistantID = assistantMessage.id
        let promptState = state
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let messages = try conversationEngine.buildPromptMessages(state: promptState, userInput: text)
                let result = try await deepSeekClient.streamCompletion(
                    apiKey: deepSeekKey,
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
                state.promptModes = conversationEngine.applyCompressionIfNeeded(state: state, latestUserInput: text)
                state.aiLogs.insert(AILogEntry(
                    purpose: "chat",
                    model: result.model,
                    requestPreview: messages.map(\.content).joined(separator: "\n\n").prefixString(1600),
                    responsePreview: result.content.prefixString(1600),
                    reasoningPreview: result.reasoningContent.prefixString(1600)
                ), at: 0)
                trimRuntimeLimits()
                statusText = "生成完成。"
            } catch is CancellationError {
                statusText = "生成已取消。"
            } catch {
                if let index = state.conversation.firstIndex(where: { $0.id == assistantID }) {
                    state.conversation[index].content = error.localizedDescription
                }
                state.aiLogs.insert(AILogEntry(
                    purpose: "chat",
                    model: state.apiSettings.deepSeekModel,
                    requestPreview: text,
                    responsePreview: "",
                    error: error.localizedDescription,
                    status: "error"
                ), at: 0)
                statusText = error.localizedDescription
            }
            isGenerating = false
            persist()
        }
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

    func runTime(turns: Int, seedMessage: String) {
        guard turns > 0 else { return }
        Task { @MainActor in
            for index in 1...min(turns, 20) {
                if Task.isCancelled { break }
                send("\(seedMessage)\n請自行推演第 \(index) 輪。")
                while isGenerating {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
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
        state.savedSessions.remove(atOffsets: offsets)
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

    private static func appState(from snapshot: AppDefaultsSnapshot) -> AppState {
        var state = AppState()
        state.userProfile = snapshot.userProfile
        state.apiSettings = snapshot.apiSettings
        state.roleCards = snapshot.roleCards
        state.activeRoleCardId = snapshot.activeRoleCardId
        state.activeAssistantMode = snapshot.activeAssistantMode
        state.promptModes = snapshot.promptModes
        state.timeTracking = snapshot.timeTracking
        state.novelAIStudioSettings = snapshot.novelAIStudioSettings
        return state
    }

    func testDeepSeek() {
        Task {
            do {
                let response = try await deepSeekClient.testConnection(apiKey: deepSeekKey, settings: state.apiSettings)
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
        Task {
            do {
                let images = try await novelAIClient.generateImages(
                    apiKey: novelAIKey,
                    settings: state.apiSettings,
                    studioSettings: studioSettings
                )
                await MainActor.run {
                    state.novelAIStudioSettings = studioSettings
                    state.novelAIAlbum.insert(contentsOf: images, at: 0)
                    statusText = "NovelAI 已生成 \(images.count) 張圖片。"
                    persist()
                }
            } catch {
                await MainActor.run { statusText = error.localizedDescription }
            }
        }
    }

    func deleteNovelAIAlbumItems(at offsets: IndexSet) {
        state.novelAIAlbum.remove(atOffsets: offsets)
        persist()
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
