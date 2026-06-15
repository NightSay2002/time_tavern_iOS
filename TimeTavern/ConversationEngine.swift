import Foundation

struct ConversationTurnOutput {
    var userMessage: ConversationMessage
    var assistantMessage: ConversationMessage
    var aiLog: AILogEntry
    var updatedPromptModes: [PromptModeConfig]
}

struct CompressionAPIRequest: Hashable {
    var modeID: String
    var profileID: String
    var profileName: String
    var profileIndex: Int
    var triggerActionID: String
    var triggerActionName: String
    var keywordFollowupAction: KeywordFollowupAction
    var skipReasoner: Bool
    var turnNumber: Int
    var compressedThroughTurnNumber: Int
    var previousSummary: String
    var messages: [ChatAPIMessage]
}

struct CompressionImageRequest: Hashable {
    var modeID: String
    var profileID: String
    var profileName: String
    var profileIndex: Int
    var triggerActionID: String
    var triggerActionName: String
    var turnNumber: Int
    var compressedThroughTurnNumber: Int
    var messages: [ChatAPIMessage]
    var imageSettings: NovelAIImageGenerationSettings
    var runsInParallel: Bool
}

final class ConversationEngine {
    static func renderTemplate(_ text: String, user: String, role: String) -> String {
        var output = text
        [
            ("user", user),
            ("chur", role)
        ].forEach { key, value in
            let pattern = "\\{\\{\\s*\(NSRegularExpression.escapedPattern(for: key))\\s*\\}\\}"
            output = output.replacingOccurrences(
                of: pattern,
                with: value,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return output
    }

    static func runtimeTurnUserContent(message: String, turnNumber: Int, totalTurns: Int) -> String {
        let request = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "用戶要求你現在自行推演\(totalTurns)輪,包括用戶及角色",
            request.isEmpty ? "這是用戶的要求" : "「\(request)」這是用戶的要求",
            "現在是第\(turnNumber)輪"
        ].joined(separator: "\n")
    }

    static func normalizedRuntimeTurns(_ turns: Int) -> Int? {
        guard turns >= 1 else { return nil }
        return min(turns, 20)
    }

    func buildPromptMessages(state: AppState, userInput: String) throws -> [ChatAPIMessage] {
        if let assistantCard = state.activeAssistantCard {
            return buildAssistantPromptMessages(state: state, assistantCard: assistantCard, userInput: userInput)
        }
        guard let roleCard = state.activeRoleCard else {
            throw TimeTavernError.missingActiveRoleCard
        }
        let promptMode = promptMode(for: roleCard, in: state)
        let userName = resolvedUserName(state)
        let roleName = roleCard.name
        let latestUser = latestUserMessage(state: state, userInput: userInput)
        let systemPrompt = [
            "【主要規則】",
            renderTemplate(effectiveMainRules(promptMode), user: userName, role: roleName),
            roleCardPromptContext(state: state, roleCard: roleCard, latestUser: latestUser),
            "【輸出規則】",
            renderTemplate(effectiveContextRules(promptMode), user: userName, role: roleName),
            "【處理要求】",
            "後續獨立 user message 會提供目前模型內容；最近對話會以獨立 user/assistant messages 提供。本輪 user message 可能會按順序包含：目前輸入者、這一輪 user 的內容、已啟用大模型的追加詞、統計時間、觸發世界書 Lorebooks、自訂補充。請根據主要規則、角色卡、目前模型內容、最近對話與輸出規則輸出正文。"
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

        let compressionContent = compressionReasonerMessage(mode: promptMode, user: userName, role: roleName)
        return [
            ChatAPIMessage(role: "system", content: systemPrompt),
            compressionContent.isEmpty ? nil : ChatAPIMessage(role: "user", content: compressionContent)
        ].compactMap { $0 } + simpleCompressedContextMessages(
            state: state,
            roleCard: roleCard,
            mode: promptMode,
            userInput: userInput
        )
    }

    private func buildAssistantPromptMessages(state: AppState, assistantCard: AssistantCard, userInput: String) -> [ChatAPIMessage] {
        let cardPrompt = assistantCard.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyPrompt = state.characterCardCreationAssistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt: String
        if assistantCard.isDefault, !legacyPrompt.isEmpty {
            prompt = state.characterCardCreationAssistantPrompt
        } else if !cardPrompt.isEmpty {
            prompt = assistantCard.prompt
        } else {
            prompt = legacyPrompt.isEmpty ? AssistantCard.defaultPrompt : state.characterCardCreationAssistantPrompt
        }
        let userName = resolvedUserName(state)
        let systemPrompt = [
            prompt,
            "你正在 Time Tavern iOS 使用\(assistantCard.displayName)。",
            "使用者稱呼：\(userName)",
            state.userProfile.extraPrompt
        ]
            .map { renderTemplate($0, user: userName, role: assistantCard.displayName) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        let latestUser = latestUserMessage(state: state, userInput: userInput)
        let context = conversationContextBeforeLatestUser(state: state, latestUser: latestUser)
            .compactMap { cacheableDialogueMessage($0) }
        return [ChatAPIMessage(role: "system", content: systemPrompt)] +
            context +
            [ChatAPIMessage(role: "user", content: currentUserModelContent(state: state, roleCard: nil, mode: nil, latestUser: latestUser, userInput: userInput))]
    }

    private func roleCardPromptContext(state: AppState, roleCard: RoleCard, latestUser: ConversationMessage? = nil) -> String {
        let userName = resolvedUserName(state)
        let roleName = roleCard.name
        let title: String
        switch roleCard.mode {
        case .single:
            title = "【目前角色卡】"
        case .multi:
            title = "【多角色卡列表】"
        case .noRole:
            title = "【無角色卡自定義內容】"
        case .custom:
            title = "【自訂角色卡】"
        }
        let sections = roleCard.customSections
            .filter(\.enabled)
            .map { section in
                [
                    section.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "自定義內容"
                        : "【\(renderTemplate(section.name, user: userName, role: roleName))】",
                    renderTemplate(section.content, user: userName, role: roleName)
                ].joined(separator: "\n")
            }
            .joined(separator: "\n\n")
        let permanentLorebooks = roleCard.lorebooks
            .filter { entry in
                entry.enabled &&
                    entry.permanent &&
                    !entry.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    passesLorebookProbability(entry, state: state, latestUser: latestUser)
            }
            .map { entry in
                let key = lorebookKey(entry)
                let renderedKey = renderTemplate(key.isEmpty ? "永久啟用" : key, user: userName, role: roleName)
                let renderedContent = renderTemplate(entry.content, user: userName, role: roleName)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return renderedContent.isEmpty ? "" : "世界書-\(renderedKey):\(renderedContent)"
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return [
            title,
            "使用者稱呼：\(userName)",
            "角色模式：\(roleCard.mode.title)",
            "角色卡名稱：\(renderTemplate(roleCard.name, user: userName, role: roleName))",
            sections,
            permanentLorebooks
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private func compressionReasonerMessage(mode: PromptModeConfig, user: String, role: String) -> String {
        let summaries = mode.compressionProfiles
            .filter(\.enabled)
            .filter { !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap { compressionProfileSummaryForReasoner(profile: $0, user: user, role: role) }
            .joined(separator: "\n\n")
        guard !summaries.isEmpty else { return "" }
        return [
            "【目前模型內容】",
            summaries,
            "【模型內容規則】",
            "這是更早之前的大模型內容，可能來自多個獨立大模型；可用於補足背景、角色關係、已成立事件、未完成事項、玩家資料與特殊長期記憶。",
            "模型內容的承接優先級略高於正文主要規則；若最近對話或本輪輸入與目前模型內容衝突，以最近對話與本輪輸入為準。"
        ].joined(separator: "\n")
    }

    private func compressionProfileSummaryForReasoner(profile: CompressionProfile, user: String, role: String) -> String? {
        guard profile.modelKind != .image else { return nil }
        let profileName = renderTemplate(profile.name.isEmpty ? profile.id : profile.name, user: user, role: role)
        let models = compressionModels(for: profile)
        guard profile.modelKind == .normal, !models.isEmpty else {
            let summary = renderTemplate(profile.summary, user: user, role: role)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { return nil }
            return "【大模型內容：\(profileName)】\n\(summary)"
        }

        let normalized = normalizedCompressionJSONState(profile.summary, models: models)
        let modules = models.compactMap { model -> String? in
            let id = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            let items = (normalized.model[id] ?? [])
                .map { renderTemplate($0, user: user, role: role).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !items.isEmpty else { return nil }
            let name = renderTemplate(model.name.isEmpty ? id : model.name, user: user, role: role)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (["【\(name.isEmpty ? id : name)】"] + items.map { "- \($0)" })
                .joined(separator: "\n")
        }
        guard !modules.isEmpty else { return nil }
        return [
            "【大模型內容：\(profileName)】",
            modules.joined(separator: "\n\n")
        ].joined(separator: "\n")
    }

    private func simpleCompressedContextMessages(
        state: AppState,
        roleCard: RoleCard,
        mode: PromptModeConfig,
        userInput: String
    ) -> [ChatAPIMessage] {
        let latestUser = latestUserMessage(state: state, userInput: userInput)
        let contextLimit = max(1, mode.dialogueContextRounds)
        let contextBoundaryTurnNumber = dialogueContextBoundaryTurnNumber(mode: mode, latestUser: latestUser)
        let allRounds = completedDialogueRoundsBeforeLatestUser(state: state, latestUser: latestUser)
        let recentRounds = allRounds
            .filter { roundTurnNumber($0) > contextBoundaryTurnNumber }
            .suffix(contextLimit)
        var contextMessages = recentRounds.flatMap { $0 }

        if !contextMessages.contains(where: { $0.role == .assistant }),
           let bridgeRound = allRounds.last(where: {
               roundTurnNumber($0) <= contextBoundaryTurnNumber &&
                   $0.contains(where: { $0.role == .assistant })
           }) {
            contextMessages.insert(contentsOf: bridgeRound, at: 0)
        }

        if contextBoundaryTurnNumber <= 0,
           let opening = openingDialogueContextMessage(state: state, roleCard: roleCard),
           !contextMessages.contains(where: { $0.content == opening.content }) {
            contextMessages.insert(opening, at: 0)
        }

        let currentContent = currentUserModelContent(
            state: state,
            roleCard: roleCard,
            mode: mode,
            latestUser: latestUser,
            userInput: userInput
        )
        if !currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contextMessages.append(ConversationMessage(
                id: latestUser.id,
                role: .user,
                content: currentContent,
                turnNumber: latestUser.turnNumber
            ))
        }

        return contextMessages.compactMap { cacheableDialogueMessage($0) }
    }

    private func latestUserMessage(state: AppState, userInput: String) -> ConversationMessage {
        if let matching = state.conversation.last(where: { $0.role == .user && $0.content == userInput }) {
            return matching
        }
        return ConversationMessage(
            role: .user,
            content: userInput,
            turnNumber: currentCompressionTurn(state: state, latestUserInput: userInput)
        )
    }

    private func conversationContextBeforeLatestUser(state: AppState, latestUser: ConversationMessage) -> [ConversationMessage] {
        let conversation = state.conversation
        let endIndex = conversation.lastIndex { $0.id == latestUser.id } ?? conversation.endIndex
        return conversation[..<endIndex].filter { !isModelInvisible($0) }
    }

    private func completedDialogueRoundsBeforeLatestUser(state: AppState, latestUser: ConversationMessage) -> [[ConversationMessage]] {
        let messages = conversationContextBeforeLatestUser(state: state, latestUser: latestUser)
        var rounds: [[ConversationMessage]] = []
        var pendingUser: ConversationMessage?
        for message in messages {
            if message.role == .user {
                if let pendingUser {
                    rounds.append([pendingUser])
                }
                pendingUser = message
                continue
            }
            if message.role == .assistant, let currentPendingUser = pendingUser {
                rounds.append([currentPendingUser, message])
                pendingUser = nil
            }
        }
        if let pendingUser {
            rounds.append([pendingUser])
        }
        return rounds
    }

    private func roundTurnNumber(_ round: [ConversationMessage]) -> Int {
        round.first { $0.role == .user }?.turnNumber ?? 0
    }

    private func dialogueContextBoundaryTurnNumber(mode: PromptModeConfig, latestUser: ConversationMessage) -> Int {
        let contextLimit = max(1, mode.dialogueContextRounds)
        let latestTurn = max(0, latestUser.turnNumber)
        guard latestTurn > contextLimit else { return 0 }
        return ((latestTurn - 1) / contextLimit) * contextLimit
    }

    private func openingDialogueContextMessage(state: AppState, roleCard: RoleCard) -> ConversationMessage? {
        var leadingAssistantMessages: [ConversationMessage] = []
        for message in state.conversation {
            if message.role == .user {
                break
            }
            if message.role == .assistant, !isModelInvisible(message) {
                leadingAssistantMessages.append(message)
            }
        }
        if let storedOpening = leadingAssistantMessages.first(where: { $0.source == "opening" }) ?? leadingAssistantMessages.first {
            var rendered = storedOpening
            rendered.content = renderTemplate(storedOpening.content, user: resolvedUserName(state), role: roleCard.name)
            return rendered
        }
        guard let opening = roleCard.activeOpeningDialogue?.content.trimmingCharacters(in: .whitespacesAndNewlines), !opening.isEmpty else {
            return nil
        }
        return ConversationMessage(
            role: .assistant,
            content: renderTemplate(opening, user: resolvedUserName(state), role: roleCard.name),
            source: "opening"
        )
    }

    private func cacheableDialogueMessage(_ message: ConversationMessage) -> ChatAPIMessage? {
        guard message.role == .user || message.role == .assistant else { return nil }
        guard !isModelInvisible(message) else { return nil }
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        return ChatAPIMessage(role: message.role.rawValue, content: content)
    }

    private func currentUserModelContent(
        state: AppState,
        roleCard: RoleCard?,
        mode: PromptModeConfig?,
        latestUser: ConversationMessage,
        userInput: String
    ) -> String {
        let base = latestUser.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? userInput : latestUser.content
        let roleName = roleCard?.name ?? state.activeAssistantCard?.displayName ?? ""
        let userName = resolvedUserName(state)
        let appendTerms = activeModelAppendTerms(mode: mode, state: state, roleName: roleName)
        let lorebooks = roleCard.map {
            formatLorebooks(
                matchedLorebooks(roleCard: $0, state: state, conversation: state.conversation, latestUser: latestUser, userInput: base),
                user: userName,
                role: roleName
            )
        } ?? ""
        let userSupplement = renderTemplate(state.userProfile.extraPrompt, user: userName, role: roleName)
        return [
            base,
            appendTerms,
            roleCard == nil ? "" : timeTrackingPromptBlock(state: state),
            lorebooks,
            userSupplement.isEmpty ? "" : "【使用者自訂補充】\n\(userSupplement)"
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private func activeModelAppendTerms(mode: PromptModeConfig?, state: AppState, roleName: String) -> String {
        guard let mode else { return "" }
        return mode.compressionProfiles
            .filter(\.enabled)
            .filter { !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.compressedThroughTurnNumber > 0 }
            .flatMap(\.appendTerms)
            .filter(\.enabled)
            .map { renderTemplate($0.content, user: resolvedUserName(state), role: roleName) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private func formatLorebooks(_ entries: [LorebookEntry], user: String, role: String) -> String {
        let content = entries
            .enumerated()
            .map { index, entry in
                let key = lorebookKey(entry)
                return [
                    "\(index + 1). \(renderTemplate(key.isEmpty ? "世界書" : key, user: user, role: role))",
                    renderTemplate(entry.content, user: user, role: role)
                ].joined(separator: "\n")
            }
            .joined(separator: "\n\n")
        return content.isEmpty ? "" : "【觸發世界書 Lorebooks】\n\(content)"
    }

    private func isModelInvisible(_ message: ConversationMessage) -> Bool {
        message.source == "model_image" || message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func applyCompressionIfNeeded(
        state: AppState,
        latestUserInput: String,
        latestAssistantText: String = "",
        phase: CompressionProcessingPhase = .beforeReasoner
    ) -> [PromptModeConfig] {
        guard let roleCard = state.activeRoleCard,
              let activeMode = state.promptMode(for: roleCard)
        else { return state.promptModes }
        let turn = currentCompressionTurn(state: state, latestUserInput: latestUserInput)
        return state.promptModes.map { mode in
            guard mode.id == activeMode.id else { return mode }
            var nextMode = mode
            nextMode.compressionProfiles = mode.compressionProfiles.map { profile in
                guard profile.enabled else { return profile }
                var nextProfile = profile
                let uncompressedRoundCount = completedUncompressedRoundCount(
                    state: state,
                    latestUserInput: latestUserInput,
                    profile: profile
                )
                let triggeredActions = effectiveCompressionTriggerActions(profile: profile).filter { action in
                    shouldTriggerCompression(
                        action: action,
                        profile: profile,
                        mode: mode,
                        turn: turn,
                        uncompressedRoundCount: uncompressedRoundCount,
                        latestUserInput: latestUserInput,
                        latestAssistantText: latestAssistantText,
                        phase: phase
                    )
                }
                guard !triggeredActions.isEmpty else { return nextProfile }
                if triggeredActions.contains(where: { $0.action == .copyUserInput }) {
                    nextProfile.summary = latestUserInput
                } else {
                    return nextProfile
                }
                let progressTurn = triggeredActions
                    .map {
                        compressedThroughTurnNumber(
                            state: state,
                            latestUserInput: latestUserInput,
                            profile: profile,
                            action: $0,
                            latestAssistantText: latestAssistantText,
                            phase: phase
                        )
                    }
                    .max() ?? turn
                nextProfile.compressedThroughTurnNumber = progressTurn
                nextProfile.updatedAt = Date()
                return nextProfile
            }
            return nextMode
        }
    }

    func resetCompressionRuntimeForNewConversation(
        state: AppState,
        roleCard: RoleCard
    ) -> [PromptModeConfig] {
        guard let activeMode = state.promptMode(for: roleCard) else { return state.promptModes }
        return state.promptModes.map { mode in
            guard mode.id == activeMode.id else { return mode }
            var nextMode = mode
            nextMode.compressionProfiles = mode.compressionProfiles.map(resetCompressionRuntime)
            return nextMode
        }
    }

    func repairCompressionRuntimeIfBeyondCurrentConversation(state: AppState) -> [PromptModeConfig] {
        guard let roleCard = state.activeRoleCard,
              let activeMode = state.promptMode(for: roleCard)
        else { return state.promptModes }
        let latestConversationTurn = state.conversation
            .filter { $0.role == .user }
            .map(\.turnNumber)
            .max() ?? 0
        return state.promptModes.map { mode in
            guard mode.id == activeMode.id else { return mode }
            var nextMode = mode
            nextMode.compressionProfiles = mode.compressionProfiles.map { profile in
                guard profile.compressedThroughTurnNumber > latestConversationTurn else { return profile }
                return resetCompressionRuntime(profile)
            }
            return nextMode
        }
    }

    func compressionAPIRequests(
        state: AppState,
        latestUserInput: String,
        latestAssistantText: String = "",
        phase: CompressionProcessingPhase = .beforeReasoner
    ) -> [CompressionAPIRequest] {
        guard let roleCard = state.activeRoleCard else { return [] }
        let turn = currentCompressionTurn(state: state, latestUserInput: latestUserInput)
        guard let mode = state.promptMode(for: roleCard) else {
            return []
        }
        return mode.compressionProfiles.enumerated().compactMap { profileIndex, profile in
            guard profile.enabled, profile.modelKind == .normal else { return nil }
            let uncompressedRoundCount = completedUncompressedRoundCount(
                state: state,
                latestUserInput: latestUserInput,
                profile: profile
            )
            let triggeredActions = effectiveCompressionTriggerActions(profile: profile).filter { action in
                action.enabled && action.action == .callAPI && shouldTriggerCompression(
                    action: action,
                    profile: profile,
                    mode: mode,
                    turn: turn,
                    uncompressedRoundCount: uncompressedRoundCount,
                    latestUserInput: latestUserInput,
                    latestAssistantText: latestAssistantText,
                    phase: phase
                )
            }
            guard let action = triggeredActions.first else { return nil }
            let includeLatestUser = shouldIncludeLatestUserInCompression(
                action: action,
                profile: profile,
                turn: turn,
                latestUserInput: latestUserInput,
                latestAssistantText: latestAssistantText,
                phase: phase
            )
            let includeLatestAssistant = shouldIncludeLatestAssistantInCompression(
                action: action,
                profile: profile,
                latestUserInput: latestUserInput,
                latestAssistantText: latestAssistantText,
                phase: phase
            )
            return CompressionAPIRequest(
                modeID: mode.id,
                profileID: profile.id,
                profileName: profile.name,
                profileIndex: profileIndex,
                triggerActionID: action.id,
                triggerActionName: action.name.isEmpty ? profile.name : action.name,
                keywordFollowupAction: action.keywordFollowupAction,
                skipReasoner: shouldSkipReasoner(action: action, latestUserInput: latestUserInput, latestAssistantText: latestAssistantText, phase: phase),
                turnNumber: turn,
                compressedThroughTurnNumber: compressedThroughTurnNumber(
                    state: state,
                    latestUserInput: latestUserInput,
                    profile: profile,
                    action: action,
                    latestAssistantText: latestAssistantText,
                    phase: phase
                ),
                previousSummary: profile.summary,
                messages: compressionAPIMessages(
                    state: state,
                    mode: mode,
                    profile: profile,
                    latestUserInput: latestUserInput,
                    includeLatestUser: includeLatestUser,
                    includeLatestAssistant: includeLatestAssistant
                )
            )
        }
    }

    func compressionImageRequests(
        state: AppState,
        latestUserInput: String,
        latestAssistantText: String = "",
        phase: CompressionProcessingPhase = .beforeReasoner
    ) -> [CompressionImageRequest] {
        guard let roleCard = state.activeRoleCard else { return [] }
        let turn = currentCompressionTurn(state: state, latestUserInput: latestUserInput)
        guard let mode = state.promptMode(for: roleCard) else {
            return []
        }
        return mode.compressionProfiles.enumerated().flatMap { profileIndex, profile -> [CompressionImageRequest] in
            guard profile.enabled, profile.modelKind == .image else { return [] }
            var imageProfile = profile
            imageProfile.summary = ""
            let uncompressedRoundCount = completedUncompressedRoundCount(
                state: state,
                latestUserInput: latestUserInput,
                profile: profile
            )
            return effectiveCompressionTriggerActions(profile: profile).filter { action in
                action.enabled &&
                    action.action == .callAPI &&
                    action.keywordFollowupAction.isImageGeneration &&
                    shouldTriggerCompression(
                        action: action,
                        profile: profile,
                        mode: mode,
                        turn: turn,
                        uncompressedRoundCount: uncompressedRoundCount,
                        latestUserInput: latestUserInput,
                        latestAssistantText: latestAssistantText,
                        phase: phase
                    )
            }.map { action in
                CompressionImageRequest(
                    modeID: mode.id,
                    profileID: profile.id,
                    profileName: profile.name,
                    profileIndex: profileIndex,
                    triggerActionID: action.id,
                    triggerActionName: action.name.isEmpty ? profile.name : action.name,
                    turnNumber: turn,
                    compressedThroughTurnNumber: compressedThroughTurnNumber(
                        state: state,
                        latestUserInput: latestUserInput,
                        profile: profile,
                        action: action,
                        latestAssistantText: latestAssistantText,
                        phase: phase
                    ),
                    messages: imagePromptAPIMessages(
                        state: state,
                        mode: mode,
                        profile: imageProfile,
                        latestUserInput: latestUserInput,
                        latestAssistantText: latestAssistantText
                    ),
                    imageSettings: action.imageGeneration,
                    runsInParallel: action.keywordFollowupAction == .imageParallelReasoner
                )
            }
        }
    }

    func rollbackCompressionProgressForReplay(state: AppState, replayTurnNumber: Int) -> [PromptModeConfig] {
        let replayTurn = max(1, replayTurnNumber)
        return state.promptModes.map { mode in
            var nextMode = mode
            nextMode.compressionProfiles = mode.compressionProfiles.map { profile in
                guard profile.compressedThroughTurnNumber >= replayTurn else { return profile }
                var nextProfile = profile
                nextProfile.compressedThroughTurnNumber = previousCompressionBoundary(
                    profile: profile,
                    mode: mode,
                    beforeTurn: replayTurn
                )
                if nextProfile.compressedThroughTurnNumber < profile.compressedThroughTurnNumber {
                    nextProfile.summary = ""
                    nextProfile.updatedAt = Date()
                }
                return nextProfile
            }
            return nextMode
        }
    }

    func applyCompressionCompletion(
        state: AppState,
        request: CompressionAPIRequest,
        completion: String
    ) -> [PromptModeConfig] {
        state.promptModes.map { mode in
            guard mode.id == request.modeID else { return mode }
            var nextMode = mode
            nextMode.compressionProfiles = mode.compressionProfiles.map { profile in
                guard profile.id == request.profileID else { return profile }
                guard compressionCompletionValidationError(profile: profile, completion: completion) == nil else { return profile }
                var nextProfile = profile
                nextProfile.summary = mergeCompressionSummary(
                    currentSummary: request.previousSummary,
                    completionText: completion,
                    profile: profile
                )
                nextProfile.compressedThroughTurnNumber = max(profile.compressedThroughTurnNumber, request.compressedThroughTurnNumber)
                nextProfile.updatedAt = Date()
                return nextProfile
            }
            return nextMode
        }
    }

    func compressionCompletionValidationError(
        state: AppState,
        request: CompressionAPIRequest,
        completion: String
    ) -> String? {
        guard let profile = state.promptModes
            .first(where: { $0.id == request.modeID })?
            .compressionProfiles
            .first(where: { $0.id == request.profileID })
        else {
            return "找不到大模型設定，無法驗證輸出格式。"
        }
        return compressionCompletionValidationError(profile: profile, completion: completion)
    }

    func compressionCompletionValidationError(profile: CompressionProfile, completion: String) -> String? {
        let models = compressionModels(for: profile)
        guard profile.modelKind == .normal, !models.isEmpty else { return nil }
        let ids = models.map(\.id).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !ids.isEmpty else { return nil }
        guard let object = strictJSONObject(completion) else {
            return "請只輸出一個合法 JSON 物件，不能有 Markdown、說明文字或尾逗號。"
        }
        guard let model = object["model"] as? [String: Any],
              let delete = object["delete"] as? [String: Any]
        else {
            return "JSON 必須使用頂層 model / delete，不可使用每個模塊各自 add/delete 的格式。"
        }
        for id in ids {
            guard model.keys.contains(id), delete.keys.contains(id) else {
                return "JSON 缺少 model.\(id) 或 delete.\(id) 欄位。"
            }
            guard model[id] is [Any], delete[id] is [Any] else {
                return "model.\(id) 和 delete.\(id) 必須是陣列。"
            }
        }
        return nil
    }

    func applyImageCompressionStarted(state: AppState, request: CompressionImageRequest) -> [PromptModeConfig] {
        state.promptModes.map { mode in
            guard mode.id == request.modeID else { return mode }
            var nextMode = mode
            nextMode.compressionProfiles = mode.compressionProfiles.map { profile in
                guard profile.id == request.profileID else { return profile }
                var nextProfile = profile
                nextProfile.summary = ""
                nextProfile.compressedThroughTurnNumber = max(profile.compressedThroughTurnNumber, request.compressedThroughTurnNumber)
                nextProfile.updatedAt = Date()
                return nextProfile
            }
            return nextMode
        }
    }

    func promptPreview(state: AppState, roleCard: RoleCard, input: String) -> String {
        var previewState = state
        previewState.activeRoleCardId = roleCard.id
        return (try? buildPromptMessages(state: previewState, userInput: input)
            .map { "\($0.role.uppercased())\n\($0.content)" }
            .joined(separator: "\n\n---\n\n")) ?? ""
    }

    func compressionPromptPreview(mode: PromptModeConfig, profile: CompressionProfile) -> String {
        compressionPromptPreview(mode: mode, profile: profile, user: "user", role: "")
    }

    private func compressionPromptPreview(mode: PromptModeConfig, profile: CompressionProfile, user: String, role: String) -> String {
        let context = profile.contextCompression.mainRules.isEmpty ? profile.mainRules : profile.contextCompression.mainRules
        let modelList = compressionModels(for: profile)
        let outputRules: String
        if profile.modelKind == .image {
            outputRules = [
                "跑圖大模型輸出規則",
                "只輸出可直接送去 NovelAI 的 Base Prompt；不要輸出標題、解釋、JSON 或 Markdown。"
            ].joined(separator: "\n")
        } else if modelList.isEmpty {
            outputRules = [
                "普通大模型輸出規則",
                "直接輸出更新後的完整壓縮文本，禁止輸出 JSON。",
                "請把目前模型內容與本次上下文合併成可供正文長期承接的純文本。",
                "如果舊內容已被新資訊取代、完成或失效，請在輸出的完整文本中自然移除或改寫。"
            ].joined(separator: "\n")
        } else {
            outputRules = [
                "普通大模型輸出規則",
                "只能輸出一個合法 JSON 物件，禁止輸出 JSON 以外的任何文字。",
                "所有模型欄位都必須存在；沒有新增或刪除內容時輸出空陣列。",
                "model.<id> 只放本次需要新增保存的內容；delete.<id> 只放已失效、已完成、被新版取代或重複的舊內容。",
                "不可把本次剛新增到 model.<id> 的內容又放進 delete.<id>。",
                "後端會把 model.<id> 追加到既有模型內容，不會整體覆蓋；請避免重複輸出既有內容。",
                "JSON 格式範例:",
                compressionJSONOutputShape(models: modelList)
            ].joined(separator: "\n")
        }
        let models = modelList
            .enumerated()
            .map { index, model in
                """
                【模塊 \(index + 1): \(renderTemplate(model.name.isEmpty ? model.id : model.name, user: user, role: role))】
                id:\(model.id)
                新增模塊規則:
                \(renderTemplate(model.addRules, user: user, role: role).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "無" : renderTemplate(model.addRules, user: user, role: role))
                刪除模塊規則:
                \(renderTemplate(model.deleteRules, user: user, role: role).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "無" : renderTemplate(model.deleteRules, user: user, role: role))
                輸出欄位:model.\(model.id)
                刪除欄位:delete.\(model.id)
                """
            }
            .joined(separator: "\n\n")
        let sectionedPrompt: [String]
        if profile.modelKind == .normal, !modelList.isEmpty {
            sectionedPrompt = [
                "【模型主要規則】",
                renderTemplate(context, user: user, role: role),
                "【模塊規則】",
                models,
                "【輸出規則】",
                outputRules
            ]
        } else {
            sectionedPrompt = [
                "模式：\(renderTemplate(mode.name, user: user, role: role))",
                "壓縮 Profile：\(renderTemplate(profile.name, user: user, role: role))",
                "類型：\(profile.modelKind.title)",
                "範圍：\(profile.contextScope.title)",
                outputRules,
                renderTemplate(context, user: user, role: role),
                models
            ]
        }
        return sectionedPrompt
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n---\n\n")
    }

    private func compressionJSONOutputShape(models: [CompressionModel]) -> String {
        let ids = models.map(\.id).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let object: [String: Any] = [
            "model": Dictionary(uniqueKeysWithValues: ids.map { ($0, [String]()) }),
            "delete": Dictionary(uniqueKeysWithValues: ids.map { ($0, [String]()) })
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            return #"{"model":{},"delete":{}}"#
        }
        return json
    }

    private func compressionModels(for profile: CompressionProfile) -> [CompressionModel] {
        profile.contextCompression.models.isEmpty ? profile.models : profile.contextCompression.models
    }

    func effectiveCompressionTriggerActions(profile: CompressionProfile) -> [CompressionTriggerAction] {
        let sourceActions = profile.triggerActions
        if sourceActions.isEmpty {
            var fallback = CompressionTriggerAction(
                id: "default",
                name: profile.id == "standard" ? "標準壓縮" : "觸發組合 1",
                triggers: fallbackTriggerConfig(for: profile)
            )
            fallback.action = .callAPI
            return [fallback]
        }
        return sourceActions.map { action in
            var next = action
            next.triggers = resolvedTriggerConfig(action: action, profile: profile)
            return next
        }
    }

    static func modelProcessingCompletionMessage(for requests: [CompressionAPIRequest]) -> String {
        let names = requests
            .map { $0.triggerActionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? $0.profileName : $0.triggerActionName }
            .filter { !$0.isEmpty }
        let suffix = names.isEmpty ? "" : "：\(names.joined(separator: "、"))"
        return "大模型處理完成\(suffix)。"
    }

    private func shouldTriggerCompression(
        action: CompressionTriggerAction,
        profile: CompressionProfile,
        mode: PromptModeConfig,
        turn: Int,
        uncompressedRoundCount: Int,
        latestUserInput: String,
        latestAssistantText: String,
        phase: CompressionProcessingPhase
    ) -> Bool {
        guard action.enabled else { return false }
        let triggers = resolvedTriggerConfig(action: action, profile: profile)
        let alreadyCompressedCurrentTurn = profile.compressedThroughTurnNumber >= turn && turn > 0
        if triggers.everyTurn && !alreadyCompressedCurrentTurn { return true }
        if let targetTurn = action.turn, targetTurn == turn, profile.compressedThroughTurnNumber < targetTurn { return true }
        if triggers.turns.contains(0) {
            let alreadyStarted = !profile.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                profile.compressedThroughTurnNumber > 0
            if !alreadyStarted && turn <= 1 {
                return true
            }
        }
        let scheduledTurns = triggers.turns.filter { $0 != 0 }
        if scheduledTurnMatches(scheduledTurns, turn: turn, compressedThroughTurnNumber: profile.compressedThroughTurnNumber, interval: mode.dialogueContextRounds) {
            return true
        }
        if keywordTriggerMatches(action: action, triggers: triggers, latestUserInput: latestUserInput, latestAssistantText: latestAssistantText, phase: phase) {
            return true
        }
        if triggers.roundLimit {
            return uncompressedRoundCount >= max(1, mode.dialogueContextRounds)
        }
        return false
    }

    private func completedUncompressedRoundCount(
        state: AppState,
        latestUserInput: String,
        profile: CompressionProfile
    ) -> Int {
        let latestUser = latestUserMessage(state: state, userInput: latestUserInput)
        return completedDialogueRoundsBeforeLatestUser(state: state, latestUser: latestUser)
            .filter { roundTurnNumber($0) > profile.compressedThroughTurnNumber }
            .count
    }

    private func compressedThroughTurnNumber(
        state: AppState,
        latestUserInput: String,
        profile: CompressionProfile,
        action: CompressionTriggerAction,
        latestAssistantText: String,
        phase: CompressionProcessingPhase
    ) -> Int {
        let latestUser = latestUserMessage(state: state, userInput: latestUserInput)
        let latestCompletedTurn = completedDialogueRoundsBeforeLatestUser(state: state, latestUser: latestUser)
            .filter { roundTurnNumber($0) > profile.compressedThroughTurnNumber }
            .map { roundTurnNumber($0) }
            .max() ?? 0
        let latestUserTurn = max(0, latestUser.turnNumber)
        let includesLatestUser = shouldIncludeLatestUserInCompression(
            action: action,
            profile: profile,
            turn: latestUserTurn,
            latestUserInput: latestUserInput,
            latestAssistantText: latestAssistantText,
            phase: phase
        )
        return max(
            profile.compressedThroughTurnNumber,
            latestCompletedTurn,
            includesLatestUser || action.action == .copyUserInput ? latestUserTurn : 0
        )
    }

    private func shouldIncludeLatestUserInCompression(
        action: CompressionTriggerAction,
        profile: CompressionProfile,
        turn: Int,
        latestUserInput: String,
        latestAssistantText: String,
        phase: CompressionProcessingPhase
    ) -> Bool {
        let triggers = resolvedTriggerConfig(action: action, profile: profile)
        if action.action == .copyUserInput || action.keywordFollowupAction.isImageGeneration {
            return true
        }
        if triggers.everyTurn && profile.compressedThroughTurnNumber < turn {
            return true
        }
        if triggers.turns.contains(0) {
            let alreadyStarted = !profile.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                profile.compressedThroughTurnNumber > 0
            if !alreadyStarted && turn <= 1 {
                return true
            }
        }
        if !triggers.turns.isEmpty {
            return true
        }
        if keywordTriggerMatches(
            action: action,
            triggers: triggers,
            latestUserInput: latestUserInput,
            latestAssistantText: latestAssistantText,
            phase: phase
        ) {
            return normalizedKeywordSource(triggers.keywordSource.isEmpty ? action.source : triggers.keywordSource) != "assistant" ||
                phase == .afterAssistant
        }
        return false
    }

    private func shouldIncludeLatestAssistantInCompression(
        action: CompressionTriggerAction,
        profile: CompressionProfile,
        latestUserInput: String,
        latestAssistantText: String,
        phase: CompressionProcessingPhase
    ) -> Bool {
        guard phase == .afterAssistant else { return false }
        let triggers = resolvedTriggerConfig(action: action, profile: profile)
        return keywordTriggerMatches(
            action: action,
            triggers: triggers,
            latestUserInput: latestUserInput,
            latestAssistantText: latestAssistantText,
            phase: phase
        )
    }

    private func shouldSkipReasoner(
        action: CompressionTriggerAction,
        latestUserInput: String,
        latestAssistantText: String,
        phase: CompressionProcessingPhase
    ) -> Bool {
        phase == .beforeReasoner &&
            action.action == .callAPI &&
            (action.keywordFollowupAction == .stopAfterModel || action.skipReasoner) &&
            keywordTriggerMatches(
                action: action,
                triggers: action.triggers,
                latestUserInput: latestUserInput,
                latestAssistantText: latestAssistantText,
                phase: phase
            )
    }

    private func keywordTriggerMatches(
        action: CompressionTriggerAction,
        triggers: CompressionTriggerConfig,
        latestUserInput: String,
        latestAssistantText: String,
        phase: CompressionProcessingPhase
    ) -> Bool {
        let source = normalizedKeywordSource(triggers.keywordSource.isEmpty ? action.source : triggers.keywordSource)
        let userCanMatch = source != "assistant"
        let assistantCanMatch = source != "user"
        let userMatched = userCanMatch && (
            (!action.keywords.isEmpty && keywordExpression(action.keywords, matches: latestUserInput)) ||
                (!triggers.keywords.isEmpty && keywordList(triggers.keywords, matches: latestUserInput))
        )
        let assistantMatched = assistantCanMatch && (
            (!action.keywords.isEmpty && keywordExpression(action.keywords, matches: latestAssistantText)) ||
                (!triggers.keywords.isEmpty && keywordList(triggers.keywords, matches: latestAssistantText))
        )
        switch phase {
        case .beforeReasoner:
            return userMatched
        case .afterAssistant:
            return assistantMatched
        }
    }

    private func fallbackTriggerConfig(for profile: CompressionProfile) -> CompressionTriggerConfig {
        if profile.id == "standard" || profile.triggers.hasNonRoundLimitTrigger {
            return profile.triggers
        }
        return CompressionTriggerConfig(roundLimit: false)
    }

    private func resolvedTriggerConfig(action: CompressionTriggerAction, profile: CompressionProfile) -> CompressionTriggerConfig {
        let actionTriggers = action.triggers
        let profileTriggers = profile.triggers
        if actionTriggers.isDefaultRoundLimitOnly && profileTriggers.hasNonRoundLimitTrigger {
            return profileTriggers
        }
        var resolved = actionTriggers
        resolved.everyTurn = resolved.everyTurn || profileTriggers.everyTurn
        resolved.turns = Array(Set(resolved.turns + profileTriggers.turns)).sorted()
        if resolved.keywords.isEmpty {
            resolved.keywords = profileTriggers.keywords
        }
        if resolved.keywordSource == "both", profileTriggers.keywordSource != "both" {
            resolved.keywordSource = profileTriggers.keywordSource
        }
        if profile.id == "standard", profileTriggers.roundLimit {
            resolved.roundLimit = true
        }
        return resolved
    }

    private func scheduledTurnMatches(
        _ turns: [Int],
        turn: Int,
        compressedThroughTurnNumber: Int,
        interval: Int
    ) -> Bool {
        turns.contains { rawTurn in
            if rawTurn == 0, compressedThroughTurnNumber <= 0, turn <= 1 {
                return true
            }
            let target = recurringScheduledTurnTarget(rawTurn, currentTurn: turn, interval: interval)
            return target > 0 && compressedThroughTurnNumber < target
        }
    }

    private func recurringScheduledTurnTarget(_ rawTurn: Int, currentTurn: Int, interval: Int) -> Int {
        let normalizedTurn = max(0, rawTurn)
        let normalizedCurrent = max(0, currentTurn)
        let normalizedInterval = max(1, interval)
        guard normalizedCurrent > 0 else { return 0 }
        if normalizedTurn == 0 {
            guard normalizedCurrent >= normalizedInterval else { return 0 }
            return (normalizedCurrent / normalizedInterval) * normalizedInterval
        }
        guard normalizedCurrent >= normalizedTurn else { return 0 }
        let cycles = (normalizedCurrent - normalizedTurn) / normalizedInterval
        return normalizedTurn + cycles * normalizedInterval
    }

    private func currentCompressionTurn(state: AppState, latestUserInput: String) -> Int {
        if let latestUser = state.conversation.last(where: { $0.role == .user }),
           latestUser.content == latestUserInput,
           latestUser.turnNumber > 0 {
            return latestUser.turnNumber
        }
        let explicitTurn = state.conversation.map(\.turnNumber).max() ?? 0
        if explicitTurn > 0 { return explicitTurn + 1 }
        let userCount = state.conversation.filter { $0.role == .user }.count
        if state.conversation.last(where: { $0.role == .user })?.content == latestUserInput {
            return max(1, userCount)
        }
        return userCount + 1
    }

    private func normalizedKeywordSource(_ source: String) -> String {
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "user" || normalized == "assistant" {
            return normalized
        }
        return "both"
    }

    private func previousCompressionBoundary(profile: CompressionProfile, mode: PromptModeConfig, beforeTurn replayTurn: Int) -> Int {
        let interval = max(1, mode.dialogueContextRounds)
        let actions = effectiveCompressionTriggerActions(profile: profile)
        var boundaries = Set<Int>()
        for action in actions where action.enabled {
            let triggers = resolvedTriggerConfig(action: action, profile: profile)
            if triggers.everyTurn, replayTurn > 1 {
                boundaries.insert(replayTurn - 1)
            }
            if let targetTurn = action.turn, targetTurn > 0, targetTurn < replayTurn {
                boundaries.insert(targetTurn)
            }
            for rawTurn in triggers.turns {
                let normalizedTurn = max(0, rawTurn)
                if normalizedTurn == 0 {
                    let target = ((replayTurn - 1) / interval) * interval
                    if target > 0 {
                        boundaries.insert(target)
                    }
                    continue
                }
                var target = normalizedTurn
                while target < replayTurn {
                    boundaries.insert(target)
                    target += interval
                }
            }
            if triggers.roundLimit {
                let target = ((replayTurn - 1) / interval) * interval
                if target > 0 {
                    boundaries.insert(target)
                }
            }
        }
        return boundaries.max() ?? 0
    }

    private func compressionAPIMessages(
        state: AppState,
        mode: PromptModeConfig,
        profile: CompressionProfile,
        latestUserInput: String,
        includeLatestUser: Bool,
        includeLatestAssistant: Bool
    ) -> [ChatAPIMessage] {
        let roleName = state.activeRoleCard?.name ?? ""
        let userName = resolvedUserName(state)
        let instruction = compressionPromptPreview(mode: mode, profile: profile, user: userName, role: roleName)
        let context = compressionContextMessages(
            state: state,
            profile: profile,
            latestUserInput: latestUserInput,
            includeLatestUser: includeLatestUser,
            includeLatestAssistant: includeLatestAssistant
        )
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { message in
                "# \(message.role.rawValue) turn \(message.turnNumber)\n\(message.content)"
            }
            .joined(separator: "\n\n----------------\n\n")
        let currentSummary = profile.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "無"
            : renderTemplate(profile.summary, user: userName, role: roleName)
        let roleContext = compressionRoleContext(state: state, profile: profile)
        return [
            ChatAPIMessage(role: "user", content: instruction),
            roleContext.isEmpty ? nil : ChatAPIMessage(role: "user", content: roleContext),
            ChatAPIMessage(role: "user", content: "【上下文】\n\(context.isEmpty ? "無" : context)"),
            ChatAPIMessage(role: "user", content: "【目前模型內容】\n\(currentSummary)")
        ].compactMap { $0 }
    }

    private func compressionContextMessages(
        state: AppState,
        profile: CompressionProfile,
        latestUserInput: String,
        includeLatestUser: Bool,
        includeLatestAssistant: Bool
    ) -> [ConversationMessage] {
        let latestUser = latestUserMessage(state: state, userInput: latestUserInput)
        var messages = completedDialogueRoundsBeforeLatestUser(state: state, latestUser: latestUser)
            .filter { roundTurnNumber($0) > profile.compressedThroughTurnNumber }
            .flatMap { $0 }
        if includeLatestUser {
            messages.append(latestUser)
        }
        if includeLatestAssistant,
           let latestUserIndex = state.conversation.lastIndex(where: { $0.id == latestUser.id }),
           let assistant = state.conversation[(latestUserIndex + 1)..<state.conversation.endIndex]
            .first(where: { $0.role == .assistant && !isModelInvisible($0) }) {
            messages.append(assistant)
        }
        return messages
    }

    private func compressionRoleContext(state: AppState, profile: CompressionProfile) -> String {
        guard profile.contextScope == .roleAndText, let roleCard = state.activeRoleCard else { return "" }
        let userName = resolvedUserName(state)
        let roleName = roleCard.name
        let sections = roleCard.customSections
            .filter(\.enabled)
            .map {
                "\(renderTemplate($0.name, user: userName, role: roleName)):\n\(renderTemplate($0.content, user: userName, role: roleName))"
            }
            .joined(separator: "\n\n")
        return [
            "【角色卡資料】",
            "角色：\(renderTemplate(roleCard.name, user: userName, role: roleName))",
            sections
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private func imagePromptAPIMessages(
        state: AppState,
        mode: PromptModeConfig,
        profile: CompressionProfile,
        latestUserInput: String,
        latestAssistantText: String
    ) -> [ChatAPIMessage] {
        let roleName = state.activeRoleCard?.name ?? ""
        let userName = resolvedUserName(state)
        let instruction = compressionPromptPreview(mode: mode, profile: profile, user: userName, role: roleName)
        let roleContext = imagePromptRoleContext(state: state, profile: profile)
        let context = recentImagePromptContext(state: state, latestUserInput: latestUserInput, latestAssistantText: latestAssistantText)
        return [
            ChatAPIMessage(role: "system", content: instruction),
            roleContext.isEmpty ? nil : ChatAPIMessage(role: "user", content: roleContext),
            ChatAPIMessage(role: "user", content: "【上下文】\n\(context.isEmpty ? "無" : context)")
        ].compactMap { $0 }
    }

    private func imagePromptRoleContext(state: AppState, profile: CompressionProfile) -> String {
        guard let roleCard = state.activeRoleCard else { return "" }
        let userName = resolvedUserName(state)
        let roleName = roleCard.name
        let sections = roleCard.customSections
            .filter { $0.enabled && $0.includeInImagePrompt }
            .map { section in
                let name = renderTemplate(section.name, user: userName, role: roleName)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let content = renderTemplate(section.content, user: userName, role: roleName)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty || !content.isEmpty else { return "" }
                return "\(name.isEmpty ? "自定義內容" : name):\(content)"
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        if !sections.isEmpty {
            return [
                "繪圖角色卡資料",
                roleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "角色 1"
                    : "角色:\(renderTemplate(roleName, user: userName, role: roleName))",
                sections
            ].joined(separator: "\n")
        }
        return profile.contextScope == .roleAndText ? compressionRoleContext(state: state, profile: profile) : ""
    }

    private func recentImagePromptContext(
        state: AppState,
        latestUserInput: String,
        latestAssistantText: String
    ) -> String {
        let contextLimit = 5
        var messages = state.conversation
            .filter { !isModelInvisible($0) }
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let trimmedUserInput = latestUserInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUserInput.isEmpty && messages.last(where: { $0.role == .user })?.content != trimmedUserInput {
            messages.append(ConversationMessage(role: .user, content: trimmedUserInput, turnNumber: currentCompressionTurn(state: state, latestUserInput: trimmedUserInput)))
        }
        let trimmedAssistantText = latestAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAssistantText.isEmpty && messages.last?.content != trimmedAssistantText {
            messages.append(ConversationMessage(role: .assistant, content: trimmedAssistantText, turnNumber: currentCompressionTurn(state: state, latestUserInput: trimmedUserInput)))
        }
        return messages
            .suffix(contextLimit * 2)
            .map { message in
                "# \(message.role.rawValue) turn \(message.turnNumber)\n\(message.content)"
            }
            .joined(separator: "\n\n----------------\n\n")
    }

    private func mergeCompressionSummary(currentSummary: String, completionText: String, profile: CompressionProfile) -> String {
        let models = profile.contextCompression.models.isEmpty ? profile.models : profile.contextCompression.models
        let completion = completionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !models.isEmpty else {
            return completion.isEmpty ? currentSummary.trimmingCharacters(in: .whitespacesAndNewlines) : completion
        }

        var current = normalizedCompressionJSONState(currentSummary, models: models)
        let incoming = normalizedCompressionJSONState(completion, models: models)
        for id in current.model.keys.sorted() {
            let deleteKeys = Set((incoming.delete[id] ?? []).map(normalizedCompressionItemKey).filter { !$0.isEmpty })
            if !deleteKeys.isEmpty {
                current.model[id, default: []].removeAll { deleteKeys.contains(normalizedCompressionItemKey($0)) }
            }
            var seen = Set(current.model[id, default: []].map(normalizedCompressionItemKey).filter { !$0.isEmpty })
            for item in incoming.model[id] ?? [] {
                let key = normalizedCompressionItemKey(item)
                guard !key.isEmpty, !seen.contains(key) else { continue }
                current.model[id, default: []].append(item)
                seen.insert(key)
            }
            current.delete[id] = []
        }

        let object: [String: Any] = [
            "model": current.model,
            "delete": current.delete
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return completion.isEmpty ? currentSummary : completion }
        return json
    }

    private func resetCompressionRuntime(_ profile: CompressionProfile) -> CompressionProfile {
        var nextProfile = profile
        nextProfile.summary = ""
        nextProfile.compressedThroughTurnNumber = 0
        nextProfile.updatedAt = Date()
        return nextProfile
    }

    private func normalizedCompressionJSONState(
        _ text: String,
        models: [CompressionModel]
    ) -> (model: [String: [String]], delete: [String: [String]]) {
        let ids = models.map(\.id).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let effectiveIDs = ids.isEmpty ? ["Summary"] : ids
        var model = Dictionary(uniqueKeysWithValues: effectiveIDs.map { ($0, [String]()) })
        var delete = Dictionary(uniqueKeysWithValues: effectiveIDs.map { ($0, [String]()) })
        guard let object = parseJSONObject(text) else {
            let legacy = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !legacy.isEmpty, legacy != "無" {
                model[effectiveIDs[0]] = [legacy]
            }
            return (model, delete)
        }
        mergeJSONSection(object["model"], into: &model)
        mergeJSONSection(object["delete"], into: &delete)
        return (model, delete)
    }

    private func normalizedCompressionItemKey(_ item: String) -> String {
        item
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updatedCompressionSummary(profile: CompressionProfile, addition: String) -> String {
        let models = profile.contextCompression.models.isEmpty ? profile.models : profile.contextCompression.models
        guard profile.modelKind == .normal, !models.isEmpty else {
            return [profile.summary, addition]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
        }
        return updatedJSONCompressionSummary(existing: profile.summary, models: models, addition: addition)
    }

    private func updatedJSONCompressionSummary(existing: String, models: [CompressionModel], addition: String) -> String {
        let modelIDs = models
            .map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let ids = modelIDs.isEmpty ? ["Summary"] : modelIDs
        let normalizedExisting = normalizedCompressionJSONState(existing, models: models)
        var modelPayload = normalizedExisting.model
        let deletePayload = normalizedExisting.delete

        modelPayload[ids[0], default: []].append(addition)
        let object: [String: Any] = [
            "model": modelPayload,
            "delete": deletePayload
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            return addition
        }
        return json
    }

    private func mergeJSONSection(_ value: Any?, into target: inout [String: [String]]) {
        guard let section = value as? [String: Any] else { return }
        for (key, value) in section {
            guard target[key] != nil else { continue }
            appendJSONValues(value, into: &target[key, default: []])
        }
    }

    private func appendJSONValues(_ value: Any?, into target: inout [String]) {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { target.append(trimmed) }
            return
        }
        if let values = value as? [Any] {
            target.append(contentsOf: values.compactMap(normalizedJSONValueText))
            return
        }
        if let value, let text = normalizedJSONValueText(value) {
            target.append(text)
        }
    }

    private func normalizedJSONValueText(_ value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        let text = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func parseJSONObject(_ text: String) -> [String: Any]? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if let object = decodeJSONObject(raw) {
            return object
        }
        if let range = raw.range(of: #"\{[\s\S]*\}"#, options: .regularExpression) {
            return decodeJSONObject(String(raw[range]))
        }
        return nil
    }

    private func strictJSONObject(_ text: String) -> [String: Any]? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private func decodeJSONObject(_ text: String) -> [String: Any]? {
        let candidates = [
            text,
            text.replacingOccurrences(of: #",\s*([\}\]])"#, with: "$1", options: .regularExpression)
        ]
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            return object
        }
        return nil
    }

    func branchSession(from state: AppState, name: String) -> SavedSession {
        SavedSession(
            name: name,
            roleCardName: state.activeRoleCard?.name ?? state.activeAssistantCard?.displayName ?? "",
            activeRoleCardId: state.activeRoleCardId,
            conversation: state.conversation,
            promptModes: state.promptModes,
            roleCards: state.roleCards,
            aiLogs: state.aiLogs
        )
    }

    func updateTimeTrackingFromOpening(state: inout AppState, opening: String) {
        _ = updateTimeTrackingFromText(state: &state, text: opening, allowBareTimeExpressions: true)
    }

    func updateTimeTrackingFromUserMessage(state: inout AppState, text: String) {
        _ = updateTimeTrackingFromText(state: &state, text: text, allowBareTimeExpressions: true)
    }

    func updateTimeTrackingAfterAssistantTurn(state: inout AppState, assistantText: String, userInput: String) -> String {
        let textChanged = updateTimeTrackingFromText(state: &state, text: assistantText, allowBareTimeExpressions: false)
        var timeTracking = state.timeTracking
        guard timeTracking.enabled, timeTracking.autoPeriod.enabled, !textChanged else {
            state.timeTracking = timeTracking
            return ""
        }
        if hasKeepTimeDirective(userInput, directive: timeTracking.keepTimeDirective) {
            timeTracking.autoPeriod.turnsSinceChange = 0
            timeTracking.updatedAt = Date()
            state.timeTracking = timeTracking
            return ""
        }

        let nextCount = timeTracking.autoPeriod.turnsSinceChange + 1
        if nextCount >= max(1, timeTracking.autoPeriod.roundsPerPeriod) {
            state.timeTracking = advanceTimePeriod(timeTracking)
            return ""
        }

        timeTracking.autoPeriod.turnsSinceChange = nextCount
        timeTracking.updatedAt = Date()
        state.timeTracking = timeTracking
        return autoTimeWarning(for: timeTracking)
    }

    func timeTrackingPromptBlock(state: AppState) -> String {
        let timeTracking = state.timeTracking
        guard timeTracking.enabled else { return "" }
        return "當前時間 | 數值: 第\(timeTracking.currentDayNumber)天\(timeTracking.currentPeriodValue.title)\(timeTracking.currentYear)年\(timeTracking.currentMonth)月\(timeTracking.currentDate)日"
    }

    private func promptMode(for roleCard: RoleCard, in state: AppState) -> PromptModeConfig {
        state.promptMode(for: roleCard) ??
            state.promptModes.first { $0.id == "multi" } ??
            PromptModeConfig()
    }

    private func matchedLorebooks(
        roleCard: RoleCard,
        state: AppState,
        conversation: [ConversationMessage],
        latestUser: ConversationMessage,
        userInput: String
    ) -> [LorebookEntry] {
        let previousAssistant = conversation.last(where: { message in
            message.role == .assistant && !isModelInvisible(message)
        })?.content ?? ""
        let target = "\(previousAssistant)\n\(userInput)".lowercased()
        let userName = resolvedUserName(state)
        let roleName = roleCard.name
        return roleCard.lorebooks.filter { entry in
            guard entry.enabled else { return false }
            guard !entry.permanent else { return false }
            guard !entry.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            guard lorebookKeywordList(entry.keywords, matches: target, user: userName, role: roleName) else {
                return false
            }
            let secondaryKeywords = entry.secondaryKeywords
            if !secondaryKeywords.isEmpty,
               !lorebookKeywordList(secondaryKeywords, matches: target, user: userName, role: roleName) {
                return false
            }
            return passesLorebookProbability(entry, state: state, latestUser: latestUser)
        }
    }

    private func lorebookKey(_ entry: LorebookEntry) -> String {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        return entry.keywords.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func lorebookKeywordList(_ keywords: [String], matches text: String, user: String, role: String) -> Bool {
        keywords.contains { keyword in
            let normalized = renderTemplate(keyword, user: user, role: role)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return !normalized.isEmpty && text.contains(normalized)
        }
    }

    private func passesLorebookProbability(_ entry: LorebookEntry, state: AppState, latestUser: ConversationMessage?) -> Bool {
        let probability = LorebookEntry.clampedProbability(entry.probability)
        if probability >= 100 {
            return true
        }
        if probability <= 0 {
            return false
        }
        let seed = [
            entry.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? lorebookKey(entry) : entry.id,
            String(latestUser?.turnNumber ?? 0),
            latestUser?.id ?? "",
            String((latestUser?.content ?? "").prefix(120))
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "|")
        return hashStringToPercent(seed) < probability
    }

    private func hashStringToPercent(_ value: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for scalar in value.unicodeScalars {
            hash ^= UInt32(scalar.value)
            hash = hash &* 16_777_619
        }
        return Int(hash % 100)
    }

    private func keywordExpression(_ expression: String, matches text: String) -> Bool {
        let target = text.lowercased()
        return expression
            .split(separator: "+")
            .map { group in
                group.split(separator: "/").contains { keyword in
                    target.contains(keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                }
            }
            .allSatisfy { $0 }
    }

    private func keywordList(_ keywords: [String], matches text: String) -> Bool {
        let target = text.lowercased()
        return keywords.contains { keyword in
            let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !normalized.isEmpty && target.contains(normalized)
        }
    }

    private func effectiveMainRules(_ mode: PromptModeConfig) -> String {
        mode.reasonerHistoryConfig.mainRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? mode.mainRules : mode.reasonerHistoryConfig.mainRules
    }

    private func effectiveContextRules(_ mode: PromptModeConfig) -> String {
        mode.reasonerHistoryConfig.contextRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? mode.outputRules : mode.reasonerHistoryConfig.contextRules
    }

    private func renderTemplate(_ text: String, user: String, role: String) -> String {
        Self.renderTemplate(text, user: user, role: role)
    }

    private func resolvedUserName(_ state: AppState) -> String {
        let value = state.userProfile.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "你" : value
    }

    private func updateTimeTrackingFromText(state: inout AppState, text: String, allowBareTimeExpressions: Bool) -> Bool {
        var timeTracking = state.timeTracking
        let before = timeTracking
        guard timeTracking.enabled else {
            state.timeTracking = timeTracking
            return false
        }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            state.timeTracking = timeTracking
            return false
        }

        var dayChangedByText = false
        if let explicitDate = findExplicitMonthDate(content, config: timeTracking.config, fallbackYear: timeTracking.currentYear, allowBare: allowBareTimeExpressions) {
            timeTracking.currentYear = explicitDate.year
            timeTracking.currentMonth = explicitDate.month
            timeTracking.currentDate = explicitDate.date
            timeTracking.updatedAt = Date()
        } else if let explicitYear = findExplicitYear(content, config: timeTracking.config, allowBare: allowBareTimeExpressions) {
            timeTracking.currentYear = explicitYear
            timeTracking.updatedAt = Date()
        }

        if let explicitDayNumber = findExplicitDayNumber(content, config: timeTracking.config, allowBare: allowBareTimeExpressions) {
            timeTracking = setDayNumber(timeTracking, explicitDayNumber)
            dayChangedByText = true
        } else if let dayAfterIncrement = findDayAfterIncrement(content, config: timeTracking.config, allowBare: allowBareTimeExpressions), dayAfterIncrement > 0 {
            timeTracking = advanceDays(timeTracking, by: dayAfterIncrement)
            dayChangedByText = true
        } else if findNextDayIncrement(content, config: timeTracking.config, allowBare: allowBareTimeExpressions) {
            timeTracking = advanceDays(timeTracking, by: 1)
            dayChangedByText = true
        }

        if let detectedPeriod = detectTimePeriod(content, config: timeTracking.config, allowBare: allowBareTimeExpressions) {
            if !dayChangedByText, timeTracking.currentPeriodValue == .evening, detectedPeriod == .morning {
                timeTracking = advanceDays(timeTracking, by: 1)
            }
            timeTracking.currentPeriodValue = detectedPeriod
            timeTracking.updatedAt = Date()
        }

        let changed = before.currentDayNumber != timeTracking.currentDayNumber ||
            before.currentPeriod != timeTracking.currentPeriod ||
            before.currentYear != timeTracking.currentYear ||
            before.currentMonth != timeTracking.currentMonth ||
            before.currentDate != timeTracking.currentDate
        if changed {
            timeTracking.autoPeriod.turnsSinceChange = 0
        }
        state.timeTracking = timeTracking
        return changed
    }

    private func autoTimeWarning(for timeTracking: TimeTrackingConfig) -> String {
        guard timeTracking.enabled, timeTracking.autoPeriod.enabled else { return "" }
        guard timeTracking.autoPeriod.turnsSinceChange >= max(0, timeTracking.autoPeriod.roundsPerPeriod - 1) else { return "" }
        let current = timeTracking.currentPeriodValue.title
        let next = timeTracking.currentPeriodValue.next.title
        return "代碼即將自動切換時間 \(current)->\(next)，如果不想切換，請在對話中加入 \(timeTracking.keepTimeDirective)，會延後 \(timeTracking.autoPeriod.roundsPerPeriod) 回合"
    }

    private func hasKeepTimeDirective(_ text: String, directive: String) -> Bool {
        let normalized = normalizedTimeText(text)
        let escaped = NSRegularExpression.escapedPattern(for: directive.trimmingCharacters(in: .whitespacesAndNewlines))
            .replacingOccurrences(of: "\\{", with: "[｛{]")
            .replacingOccurrences(of: "\\}", with: "[｝}]")
            .replacingOccurrences(of: "\\ ", with: "\\s*")
        if let regex = try? NSRegularExpression(pattern: escaped, options: []) {
            return regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) != nil
        }
        return normalized.contains("保持時間")
    }

    private func advanceTimePeriod(_ timeTracking: TimeTrackingConfig) -> TimeTrackingConfig {
        var next = timeTracking
        let currentPeriod = next.currentPeriodValue
        if currentPeriod == .evening {
            next = advanceDays(next, by: 1)
        }
        next.currentPeriodValue = currentPeriod.next
        next.autoPeriod.turnsSinceChange = 0
        next.updatedAt = Date()
        return next
    }

    private func setDayNumber(_ timeTracking: TimeTrackingConfig, _ dayNumber: Int) -> TimeTrackingConfig {
        var next = timeTracking
        let nextDayNumber = max(1, dayNumber)
        let delta = nextDayNumber - next.currentDayNumber
        next.currentDayNumber = nextDayNumber
        if delta > 0 {
            let date = addDays(year: next.currentYear, month: next.currentMonth, date: next.currentDate, days: delta)
            next.currentYear = date.year
            next.currentMonth = date.month
            next.currentDate = date.date
        }
        next.updatedAt = Date()
        return next
    }

    private func advanceDays(_ timeTracking: TimeTrackingConfig, by days: Int) -> TimeTrackingConfig {
        var next = timeTracking
        let increment = max(0, days)
        guard increment > 0 else { return next }
        let date = addDays(year: next.currentYear, month: next.currentMonth, date: next.currentDate, days: increment)
        next.currentDayNumber += increment
        next.currentYear = date.year
        next.currentMonth = date.month
        next.currentDate = date.date
        next.updatedAt = Date()
        return next
    }

    private func addDays(year: Int, month: Int, date: Int, days: Int) -> (year: Int, month: Int, date: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = date
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(from: components) ?? Date()
        let next = calendar.date(byAdding: .day, value: max(0, days), to: base) ?? base
        return (
            calendar.component(.year, from: next),
            calendar.component(.month, from: next),
            calendar.component(.day, from: next)
        )
    }

    private func detectTimePeriod(_ text: String, config: TimeTrackingRulesConfig, allowBare: Bool) -> TimeTrackingPeriod? {
        let candidates: [(TimeTrackingPeriod, [String])] = [
            (.morning, config.morningWords),
            (.noon, config.noonWords),
            (.evening, config.eveningWords)
        ]
        return candidates
            .flatMap { period, words in
                wordOccurrences(in: text, words: words)
                    .filter { shouldApplyTimeRange(text: text, range: $0, config: config, allowBare: allowBare) }
                    .map { (period: period, index: $0.location) }
            }
            .sorted { $0.index > $1.index }
            .first?
            .period
    }

    private func findExplicitYear(_ text: String, config: TimeTrackingRulesConfig, allowBare: Bool) -> Int? {
        let candidates: [(year: Int, index: Int)] = matches(pattern: #"(\d{3,4}|[零一二三四五六七八九〇○Ｏ]{3,4})\s*年"#, in: text)
            .compactMap { match -> (year: Int, index: Int)? in
                guard shouldApplyTimeRange(text: text, range: match.range, config: config, allowBare: allowBare),
                      let raw = match.groups.first,
                      let year = parseChineseDigitYear(raw)
                else { return nil }
                return (year, match.range.location)
            }
        return candidates
            .sorted { $0.1 > $1.1 }
            .first?
            .0
    }

    private func findExplicitDayNumber(_ text: String, config: TimeTrackingRulesConfig, allowBare: Bool) -> Int? {
        let candidates: [(day: Int, index: Int)] = matches(pattern: #"第\s*(\d{1,4})\s*天"#, in: text)
            .compactMap { match -> (day: Int, index: Int)? in
                guard shouldApplyTimeRange(text: text, range: match.range, config: config, allowBare: allowBare),
                      let raw = match.groups.first,
                      let day = Int(raw),
                      day > 0
                else { return nil }
                return (day, match.range.location)
            }
        return candidates
            .sorted { $0.1 > $1.1 }
            .first?
            .0
    }

    private func findDayAfterIncrement(_ text: String, config: TimeTrackingRulesConfig, allowBare: Bool) -> Int? {
        let values = matches(pattern: #"([0-9]+|[一二三四五六七八九十百兩两]+)\s*天\s*[後后]"#, in: text)
            .compactMap { match -> Int? in
                guard shouldApplyTimeRange(text: text, range: match.range, config: config, allowBare: allowBare),
                      let raw = match.groups.first
                else { return nil }
                return parseChineseSmallNumber(raw)
            }
            .filter { $0 > 0 }
        return values.max()
    }

    private func findNextDayIncrement(_ text: String, config: TimeTrackingRulesConfig, allowBare: Bool) -> Bool {
        wordOccurrences(in: text, words: config.nextDayWords)
            .contains { shouldApplyTimeRange(text: text, range: $0, config: config, allowBare: allowBare) }
    }

    private func findExplicitMonthDate(_ text: String, config: TimeTrackingRulesConfig, fallbackYear: Int, allowBare: Bool) -> (year: Int, month: Int, date: Int)? {
        let candidates: [(year: Int, month: Int, date: Int, index: Int)] = matches(pattern: #"(?:(\d{3,4}|[零一二三四五六七八九〇○Ｏ]{3,4})\s*年\s*)?(\d{1,2})\s*月\s*(\d{1,2})\s*(?:日|號|号)"#, in: text)
            .compactMap { match -> (year: Int, month: Int, date: Int, index: Int)? in
                guard shouldApplyTimeRange(text: text, range: match.range, config: config, allowBare: allowBare),
                      match.groups.count >= 3
                else { return nil }
                let year = match.groups[0].isEmpty ? fallbackYear : (parseChineseDigitYear(match.groups[0]) ?? fallbackYear)
                let month = Int(match.groups[1]) ?? 0
                let date = Int(match.groups[2]) ?? 0
                guard isValidMonthDate(year: year, month: month, date: date) else { return nil }
                return (year, month, date, match.range.location)
            }
        return candidates
            .sorted { $0.3 > $1.3 }
            .first
            .map { ($0.0, $0.1, $0.2) }
    }

    private func shouldApplyTimeRange(text: String, range: NSRange, config: TimeTrackingRulesConfig, allowBare: Bool) -> Bool {
        guard !isBlockedByNoChange(text: text, range: range, config: config) else { return false }
        if allowBare { return true }
        return isNearConnector(text: text, range: range, config: config)
    }

    private func isNearConnector(text: String, range: NSRange, config: TimeTrackingRulesConfig) -> Bool {
        wordOccurrences(in: text, words: config.connectorWords)
            .contains { connector in
                connector.upperBound <= range.location &&
                    rangeGap(connector, range) <= 5 &&
                    !isBlockedByNoChange(text: text, range: connector, config: config)
            }
    }

    private func isBlockedByNoChange(text: String, range: NSRange, config: TimeTrackingRulesConfig) -> Bool {
        wordOccurrences(in: text, words: config.noChangeWords)
            .contains { rangeGap($0, range) <= 5 }
    }

    private func rangeGap(_ left: NSRange, _ right: NSRange) -> Int {
        if left.upperBound <= right.location {
            return right.location - left.upperBound
        }
        if right.upperBound <= left.location {
            return left.location - right.upperBound
        }
        return 0
    }

    private func wordOccurrences(in text: String, words: [String]) -> [NSRange] {
        let normalized = normalizedTimeText(text)
        return words.flatMap { word -> [NSRange] in
            let target = normalizedTimeText(word)
            guard !target.isEmpty else { return [] }
            var ranges: [NSRange] = []
            var searchStart = normalized.startIndex
            while searchStart < normalized.endIndex,
                  let range = normalized.range(of: target, range: searchStart..<normalized.endIndex) {
                ranges.append(NSRange(range, in: normalized))
                searchStart = range.upperBound
            }
            return ranges
        }
    }

    private func normalizedTimeText(_ text: String) -> String {
        text.folding(options: [.widthInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "兩", with: "二")
            .replacingOccurrences(of: "两", with: "二")
    }

    private func matches(pattern: String, in text: String) -> [(range: NSRange, groups: [String])] {
        let normalized = normalizedTimeText(text)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsRange = NSRange(normalized.startIndex..., in: normalized)
        return regex.matches(in: normalized, range: nsRange).map { match in
            let groups = (1..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: normalized) else { return "" }
                return String(normalized[swiftRange])
            }
            return (match.range, groups)
        }
    }

    private func parseChineseSmallNumber(_ value: String) -> Int? {
        let raw = normalizedTimeText(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(raw) {
            return max(0, number)
        }
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if raw.count == 1, let char = raw.first, let digit = digits[char] {
            return digit
        }
        if let hundredRange = raw.range(of: "百") {
            let left = String(raw[..<hundredRange.lowerBound])
            let right = String(raw[hundredRange.upperBound...])
            let hundreds = left.isEmpty ? 1 : (parseChineseSmallNumber(left) ?? 0)
            let rest = right.isEmpty ? 0 : (parseChineseSmallNumber(right) ?? 0)
            return hundreds * 100 + rest
        }
        if let tenRange = raw.range(of: "十") {
            let left = String(raw[..<tenRange.lowerBound])
            let right = String(raw[tenRange.upperBound...])
            let tens = left.isEmpty ? 1 : (parseChineseSmallNumber(left) ?? 0)
            let ones = right.isEmpty ? 0 : (parseChineseSmallNumber(right) ?? 0)
            return tens * 10 + ones
        }
        return nil
    }

    private func parseChineseDigitYear(_ value: String) -> Int? {
        let raw = normalizedTimeText(value)
            .replacingOccurrences(of: "〇", with: "零")
            .replacingOccurrences(of: "○", with: "零")
            .replacingOccurrences(of: "Ｏ", with: "零")
            .replacingOccurrences(of: " ", with: "")
        if let number = Int(raw), (1...9999).contains(number) {
            return number
        }
        let digits: [Character: String] = ["零": "0", "一": "1", "二": "2", "三": "3", "四": "4", "五": "5", "六": "6", "七": "7", "八": "8", "九": "9"]
        guard raw.count >= 3, raw.count <= 4 else { return nil }
        let mapped = raw.compactMap { digits[$0] }.joined()
        guard mapped.count == raw.count, let year = Int(mapped), (1...9999).contains(year) else { return nil }
        return year
    }

    private func isValidMonthDate(year: Int, month: Int, date: Int) -> Bool {
        guard (1...9999).contains(year), (1...12).contains(month), date > 0 else { return false }
        var components = DateComponents()
        components.year = year
        components.month = month
        let calendar = Calendar(identifier: .gregorian)
        guard let monthDate = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: monthDate)
        else { return false }
        return date <= range.count
    }
}

private extension NSRange {
    var upperBound: Int { location + length }
}

private extension CompressionTriggerConfig {
    var hasNonRoundLimitTrigger: Bool {
        everyTurn ||
            !keywords.isEmpty ||
            !turns.isEmpty ||
            keywordSource != "both"
    }

    var isDefaultRoundLimitOnly: Bool {
        !everyTurn &&
            roundLimit &&
            keywords.isEmpty &&
            keywordSource == "both" &&
            turns.isEmpty
    }
}
