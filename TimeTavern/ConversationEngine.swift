import Foundation

struct ConversationTurnOutput {
    var userMessage: ConversationMessage
    var assistantMessage: ConversationMessage
    var aiLog: AILogEntry
    var updatedPromptModes: [PromptModeConfig]
}

final class ConversationEngine {
    func buildPromptMessages(state: AppState, userInput: String) throws -> [ChatAPIMessage] {
        guard let roleCard = state.activeRoleCard else {
            throw TimeTavernError.missingActiveRoleCard
        }
        let promptMode = promptMode(for: roleCard, in: state)
        let lorebookContext = matchedLorebooks(roleCard: roleCard, conversation: state.conversation, userInput: userInput)
            .map { "【世界書：\($0.title)】\n\($0.content)" }
            .joined(separator: "\n\n")
        let sections = roleCard.customSections
            .filter(\.enabled)
            .map { "\($0.name):\n\($0.content)" }
            .joined(separator: "\n\n")
        let compression = promptMode.compressionProfiles
            .filter(\.enabled)
            .filter { !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "【大模型內容：\($0.name)】\n\($0.summary)" }
            .joined(separator: "\n\n")
        let systemPrompt = [
            "你正在 Time Tavern iOS 進行長篇角色互動。",
            "使用者稱呼：\(state.userProfile.userName)",
            "角色模式：\(roleCard.mode.title)",
            "目前角色卡：\(roleCard.name)",
            effectiveMainRules(promptMode),
            effectiveContextRules(promptMode),
            sections,
            lorebookContext,
            compression
        ]
            .map { replacePlaceholders($0, user: state.userProfile.userName, role: roleCard.name) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

        let recent = state.conversation.suffix(max(2, promptMode.dialogueContextRounds * 2)).map {
            ChatAPIMessage(role: $0.role.rawValue, content: $0.content)
        }
        let finalUserInput = [
            userInput,
            replacePlaceholders(state.userProfile.extraPrompt, user: state.userProfile.userName, role: roleCard.name)
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        return [ChatAPIMessage(role: "system", content: systemPrompt)] + recent + [ChatAPIMessage(role: "user", content: finalUserInput)]
    }

    func applyCompressionIfNeeded(state: AppState, latestUserInput: String) -> [PromptModeConfig] {
        guard let roleCard = state.activeRoleCard else { return state.promptModes }
        let turn = state.conversation.filter { $0.role == .user }.count + 1
        return state.promptModes.map { mode in
            guard mode.id == roleCard.promptModeId || mode.mode == roleCard.mode.rawValue else { return mode }
            var nextMode = mode
            nextMode.compressionProfiles = mode.compressionProfiles.map { profile in
                guard profile.enabled else { return profile }
                var nextProfile = profile
                let shouldTrigger = profile.triggerActions.contains { action in
                    guard action.enabled else { return false }
                    if action.triggers.everyTurn { return true }
                    if let targetTurn = action.turn, targetTurn == turn { return true }
                    if action.triggers.turns.contains(turn) { return true }
                    if !action.keywords.isEmpty && keywordExpression(action.keywords, matches: latestUserInput) { return true }
                    if !action.triggers.keywords.isEmpty && keywordList(action.triggers.keywords, matches: latestUserInput) { return true }
                    if action.triggers.roundLimit || profile.triggers.roundLimit {
                        return turn - profile.compressedThroughTurnNumber >= max(1, mode.dialogueContextRounds)
                    }
                    return false
                }
                guard shouldTrigger else { return nextProfile }
                if profile.triggerActions.contains(where: { $0.action == .copyUserInput }) {
                    nextProfile.summary = latestUserInput
                } else {
                    let addition = "第 \(turn) 回合摘要：\(latestUserInput.prefix(500))"
                    nextProfile.summary = [nextProfile.summary, addition]
                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .joined(separator: "\n")
                }
                nextProfile.compressedThroughTurnNumber = turn
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
        let context = profile.contextCompression.mainRules.isEmpty ? profile.mainRules : profile.contextCompression.mainRules
        let models = (profile.contextCompression.models.isEmpty ? profile.models : profile.contextCompression.models)
            .map { model in
                """
                [\(model.id)] \(model.name)
                add: \(model.addRules)
                delete: \(model.deleteRules)
                """
            }
            .joined(separator: "\n\n")
        return [
            "模式：\(mode.name)",
            "壓縮 Profile：\(profile.name)",
            "範圍：\(profile.contextScope.title)",
            context,
            models
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n---\n\n")
    }

    func branchSession(from state: AppState, name: String) -> SavedSession {
        SavedSession(
            name: name,
            roleCardName: state.activeRoleCard?.name ?? "",
            activeRoleCardId: state.activeRoleCardId,
            conversation: state.conversation,
            promptModes: state.promptModes,
            roleCards: state.roleCards,
            aiLogs: state.aiLogs
        )
    }

    private func promptMode(for roleCard: RoleCard, in state: AppState) -> PromptModeConfig {
        state.promptModes.first { $0.id == roleCard.promptModeId } ??
            state.promptModes.first { $0.mode == roleCard.mode.rawValue } ??
            state.promptModes.first { $0.id == "multi" } ??
            PromptModeConfig()
    }

    private func matchedLorebooks(roleCard: RoleCard, conversation: [ConversationMessage], userInput: String) -> [LorebookEntry] {
        let previousAssistant = conversation.last(where: { $0.role == .assistant })?.content ?? ""
        let target = "\(previousAssistant)\n\(userInput)".lowercased()
        return roleCard.lorebooks.filter { entry in
            guard entry.enabled else { return false }
            return entry.keywords.contains { keyword in
                let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !normalized.isEmpty && target.contains(normalized)
            }
        }
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

    private func replacePlaceholders(_ text: String, user: String, role: String) -> String {
        text
            .replacingOccurrences(of: "{{user}}", with: user)
            .replacingOccurrences(of: "{{chur}}", with: role)
    }
}
