import Foundation
import ZIPFoundation

struct ImportedBundle {
    var roleCards: [RoleCard] = []
    var promptModes: [PromptModeConfig] = []
    var statePatch: AppState?
    var rawFiles: [String: Data] = [:]
}

final class ImportExportService {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func importBundle(from url: URL) throws -> ImportedBundle {
        let archive = try Archive(url: url, accessMode: .read, pathEncoding: nil)
        var files: [String: Data] = [:]
        for entry in archive {
            guard entry.type == .file else { continue }
            var data = Data()
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
            files[entry.path] = data
        }

        var bundle = ImportedBundle(rawFiles: files)
        if let defaultsData = find(files, named: "defaults/app-defaults.json"),
           let defaults = try? decoder.decode(WebDefaults.self, from: defaultsData) {
            bundle.roleCards = defaults.roleCards.map(\.native)
            if let state = defaults.nativeState {
                bundle.statePatch = state
            }
        }
        if let appStateData = find(files, named: "data/app-state.json"),
           let state = try? decoder.decode(WebAppState.self, from: appStateData) {
            var patch = bundle.statePatch ?? AppState()
            if !state.roleCards.isEmpty { patch.roleCards = state.roleCards.map(\.native) }
            patch.activeRoleCardId = state.activeRoleCardId ?? patch.activeRoleCardId
            patch.conversation = state.conversation.map(\.native)
            patch.aiLogs = state.aiLogs.map(\.native)
            bundle.statePatch = patch
        }
        let promptFiles = files.filter { $0.key.hasPrefix("prompts/modular/") && $0.key.hasSuffix(".json") }
        bundle.promptModes = promptFiles.compactMap { _, data in
            try? decoder.decode(WebPromptMode.self, from: data).native
        }
        return bundle
    }

    func exportBundle(state: AppState) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TimeTavern-iOS-\(Int(Date().timeIntervalSince1970)).zip")
        try? FileManager.default.removeItem(at: url)
        let archive = try Archive(url: url, accessMode: .create, pathEncoding: nil)
        let stateData = try encoder.encode(state)
        try archive.addEntry(with: "time-tavern-ios/state.json", type: .file, uncompressedSize: Int64(stateData.count)) { position, size in
            stateData.subdata(in: Int(position)..<Int(position) + size)
        }
        for mode in state.promptModes {
            let data = try encoder.encode(mode)
            try archive.addEntry(with: "time-tavern-ios/prompts/\(mode.id).json", type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    private func find(_ files: [String: Data], named name: String) -> Data? {
        files[name] ?? files.first { $0.key.hasSuffix(name) }?.value
    }
}

private struct WebDefaults: Decodable {
    var userProfile: UserProfile?
    var roleCards: [WebRoleCard] = []
    var conversationSettings: WebConversationSettings?
    var contextCompression: WebContextCompression?

    var nativeState: AppState? {
        var state = AppState()
        if let userProfile { state.userProfile = userProfile }
        state.roleCards = roleCards.map(\.native)
        if let conversationSettings {
            state.apiSettings.deepSeekModel = conversationSettings.chatOutputModel ?? state.apiSettings.deepSeekModel
        }
        return state
    }
}

private struct WebAppState: Decodable {
    var roleCards: [WebRoleCard] = []
    var activeRoleCardId: String?
    var conversation: [WebConversationMessage] = []
    var aiLogs: [WebAILog] = []
}

private struct WebConversationSettings: Decodable {
    var chatOutputModel: String?
    var dialogueContextRounds: Int?
}

private struct WebContextCompression: Decodable {
    var summary: String?
    var compressedThroughTurnNumber: Int?
}

private struct WebRoleCard: Decodable {
    var id: String?
    var name: String?
    var mode: String?
    var coverImage: String?
    var customSections: [CustomSection]?
    var openingDialogue: String?
    var openingDialogues: [OpeningDialogue]?
    var activeOpeningDialogueId: String?
    var lorebooks: [WebLorebookEntry]?

    var native: RoleCard {
        var card = RoleCard()
        card.id = id ?? UUID().uuidString
        card.name = name ?? "未命名角色"
        card.mode = RoleCardMode(rawValue: mode ?? "multi") ?? .custom
        card.promptModeId = card.mode.rawValue
        card.coverImageDataURL = coverImage ?? ""
        card.customSections = customSections ?? []
        if let openingDialogues, !openingDialogues.isEmpty {
            card.openingDialogues = openingDialogues
        } else {
            card.openingDialogues = [OpeningDialogue(content: openingDialogue ?? "")]
        }
        card.activeOpeningDialogueId = activeOpeningDialogueId ?? card.openingDialogues.first?.id ?? ""
        card.lorebooks = (lorebooks ?? []).map(\.native)
        return card
    }
}

private struct WebLorebookEntry: Decodable {
    var id: String?
    var title: String?
    var key: String?
    var keywords: [String]?
    var content: String?
    var enabled: Bool?

    var native: LorebookEntry {
        LorebookEntry(
            id: id ?? UUID().uuidString,
            title: title ?? key ?? "世界書",
            keywords: keywords ?? key.map { [$0] } ?? [],
            content: content ?? "",
            enabled: enabled ?? true
        )
    }
}

private struct WebConversationMessage: Decodable {
    var id: String?
    var role: String?
    var content: String?
    var source: String?
    var turnNumber: Int?
    var compressionNotice: Bool?

    var native: ConversationMessage {
        ConversationMessage(
            id: id ?? UUID().uuidString,
            role: MessageRole(rawValue: role ?? "assistant") ?? .assistant,
            content: content ?? "",
            source: source ?? "import",
            turnNumber: turnNumber ?? 0,
            compressionNotice: compressionNotice ?? false
        )
    }
}

private struct WebAILog: Decodable {
    var id: String?
    var purpose: String?
    var model: String?
    var requestMessages: [ChatAPIMessage]?
    var responseText: String?
    var debugReasoningContent: String?
    var error: String?
    var status: String?

    var native: AILogEntry {
        AILogEntry(
            id: id ?? UUID().uuidString,
            purpose: purpose ?? "chat",
            model: model ?? "",
            requestPreview: requestMessages?.map(\.content).joined(separator: "\n").prefixString(1200) ?? "",
            responsePreview: (responseText ?? "").prefixString(1200),
            reasoningPreview: (debugReasoningContent ?? "").prefixString(1200),
            error: error ?? "",
            status: status ?? "success"
        )
    }
}

private struct WebPromptMode: Decodable {
    var mode: String?
    var name: String?
    var dialogueContextRounds: Int?
    var reasonerHistory: String?
    var compressionProfiles: [CompressionProfile]?
    var contextCompressionPrompt: String?

    var native: PromptModeConfig {
        PromptModeConfig(
            id: mode ?? UUID().uuidString,
            name: name ?? mode ?? "Prompt",
            mode: mode ?? "custom",
            dialogueContextRounds: dialogueContextRounds ?? 15,
            mainRules: "",
            outputRules: "",
            reasonerHistory: reasonerHistory ?? "",
            compressionProfiles: compressionProfiles ?? [CompressionProfile(mainRules: contextCompressionPrompt ?? "")]
        )
    }
}

private extension String {
    func prefixString(_ maxLength: Int) -> String {
        String(prefix(maxLength))
    }
}
