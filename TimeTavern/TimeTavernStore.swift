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
    @Published var exportedBundleURL: URL?

    private let secretStore = SecretStore()
    private let deepSeekClient = DeepSeekClient()
    private let novelAIClient = NovelAIClient()
    private let conversationEngine = ConversationEngine()
    private let importExportService = ImportExportService()
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
        card.customSections = [
            CustomSection(name: "性格", content: ""),
            CustomSection(name: "場景", content: "")
        ]
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

    func importBundle(url: URL) {
        do {
            let bundle = try importExportService.importBundle(from: url)
            if let patch = bundle.statePatch {
                if !patch.roleCards.isEmpty { state.roleCards = patch.roleCards }
                if !patch.conversation.isEmpty { state.conversation = patch.conversation }
                if !patch.aiLogs.isEmpty { state.aiLogs = patch.aiLogs }
                if !patch.activeRoleCardId.isEmpty { state.activeRoleCardId = patch.activeRoleCardId }
            }
            if !bundle.roleCards.isEmpty { state.roleCards = bundle.roleCards }
            if !bundle.promptModes.isEmpty { state.promptModes = bundle.promptModes }
            statusText = "已匯入 \(bundle.rawFiles.count) 個檔案。"
            persist()
        } catch {
            statusText = "匯入失敗：\(error.localizedDescription)"
        }
    }

    func exportBundle() {
        do {
            exportedBundleURL = try importExportService.exportBundle(state: state)
            statusText = "已建立匯出 ZIP。"
        } catch {
            statusText = "匯出失敗：\(error.localizedDescription)"
        }
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
        Task {
            do {
                let images = try await novelAIClient.generateImage(
                    apiKey: novelAIKey,
                    settings: state.apiSettings,
                    prompt: prompt,
                    negativePrompt: negativePrompt,
                    model: model,
                    width: width,
                    height: height,
                    steps: steps,
                    scale: scale
                )
                await MainActor.run {
                    state.novelAIAlbum.insert(contentsOf: images, at: 0)
                    statusText = "NovelAI 已生成 \(images.count) 張圖片。"
                    persist()
                }
            } catch {
                await MainActor.run { statusText = error.localizedDescription }
            }
        }
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
