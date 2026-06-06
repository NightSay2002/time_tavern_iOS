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
            try? decoder.decode(PromptModeConfig.self, from: data)
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

struct BundledWebDefaultsSummary: Hashable {
    var roleCardCount: Int = 0
    var promptModeCount: Int = 0
    var userDisplayName: String = ""
    var activeRoleCardName: String = ""
}

final class BundledWebDefaultsService {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadDefaults() throws -> AppState {
        try Self.loadDefaults(from: defaultsRootURL())
    }

    func summary() throws -> BundledWebDefaultsSummary {
        let state = try loadDefaults()
        return BundledWebDefaultsSummary(
            roleCardCount: state.roleCards.count,
            promptModeCount: state.promptModes.count,
            userDisplayName: state.userProfile.userName,
            activeRoleCardName: state.activeRoleCard?.name ?? state.roleCards.first?.name ?? ""
        )
    }

    static func loadDefaults(from rootURL: URL) throws -> AppState {
        let decoder = JSONDecoder()
        var state = AppState()
        let defaultsURL = rootURL.appendingPathComponent("defaults/app-defaults.json")
        if FileManager.default.fileExists(atPath: defaultsURL.path) {
            let data = try Data(contentsOf: defaultsURL)
            let defaults = try decoder.decode(WebDefaults.self, from: data)
            if let nativeState = defaults.nativeState {
                state = nativeState
            }
        }

        let modularURL = rootURL.appendingPathComponent("prompts/modular")
        if let files = try? FileManager.default.contentsOfDirectory(at: modularURL, includingPropertiesForKeys: nil) {
            let modes = files
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { url -> PromptModeConfig? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? decoder.decode(PromptModeConfig.self, from: data)
                }
            if !modes.isEmpty {
                state.promptModes = modes
            }
        }
        return state
    }

    private func defaultsRootURL() throws -> URL {
        if let url = bundle.url(forResource: "WebDefaults", withExtension: nil) {
            return url
        }
        if let url = bundle.url(forResource: "Resources/WebDefaults", withExtension: nil) {
            return url
        }
        throw TimeTavernError.invalidImport
    }
}

private struct WebDefaults: Decodable {
    var activeRoleCardId: String?
    var activeAssistantMode: String?
    var userProfile: WebUserProfile?
    var roleCards: [WebRoleCard] = []
    var conversationSettings: WebConversationSettings?
    var timeTracking: WebTimeTracking?

    var nativeState: AppState? {
        var state = AppState()
        if let userProfile { state.userProfile = userProfile.native }
        state.roleCards = roleCards.map(\.native)
        if let activeRoleCardId, state.roleCards.contains(where: { $0.id == activeRoleCardId }) {
            state.activeRoleCardId = activeRoleCardId
        } else {
            state.activeRoleCardId = state.roleCards.first?.id ?? ""
        }
        state.activeAssistantMode = activeAssistantMode ?? ""
        if let timeTracking { state.timeTracking = timeTracking.native }
        if let conversationSettings {
            state.apiSettings.deepSeekModel = conversationSettings.chatOutputModel ?? state.apiSettings.deepSeekModel
            if let rounds = conversationSettings.dialogueContextRounds {
                state.promptModes = state.promptModes.map { mode in
                    var next = mode
                    next.dialogueContextRounds = rounds
                    return next
                }
            }
        }
        return state
    }
}

private struct WebUserProfile: Decodable {
    var displayName: String?
    var identityText: String?

    var native: UserProfile {
        UserProfile(
            userName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? displayName! : "user",
            extraPrompt: identityText ?? ""
        )
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

private struct WebTimeTracking: Decodable {
    struct AutoPeriod: Decodable {
        var enabled: Bool?
        var roundsPerPeriod: Int?
    }

    var enabled: Bool?
    var currentDayNumber: Int?
    var currentPeriod: String?
    var autoPeriod: AutoPeriod?

    var native: TimeTrackingConfig {
        TimeTrackingConfig(
            enabled: enabled ?? true,
            day: currentDayNumber ?? 1,
            period: Self.localizedPeriod(currentPeriod),
            autoAdvanceRounds: autoPeriod?.roundsPerPeriod ?? 3
        )
    }

    private static func localizedPeriod(_ value: String?) -> String {
        switch value {
        case "morning": "早上"
        case "noon": "中午"
        case "evening": "晚上"
        case let value?: value
        case nil: "早上"
        }
    }
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
        card.coverImageData = Self.decodeDataURL(coverImage)
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

    private static func decodeDataURL(_ dataURL: String?) -> Data? {
        guard let dataURL, let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let encoded = String(dataURL[dataURL.index(after: commaIndex)...])
        return Data(base64Encoded: encoded)
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

private extension String {
    func prefixString(_ maxLength: Int) -> String {
        String(prefix(maxLength))
    }
}
