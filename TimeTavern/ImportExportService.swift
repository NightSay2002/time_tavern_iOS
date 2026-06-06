import Foundation

final class ImportExportService {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func importRoleCardJSON(from url: URL, existingRoleCards: [RoleCard]) throws -> RoleCard {
        try importRoleCardJSON(from: try Data(contentsOf: url), existingRoleCards: existingRoleCards)
    }

    func importRoleCardJSON(from data: Data, existingRoleCards: [RoleCard]) throws -> RoleCard {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TimeTavernError.invalidImport
        }
        let decoded: RoleCard
        if object["roleCard"] != nil || object["timeTavernRoleCard"] != nil {
            decoded = try decoder.decode(TimeTavernRoleCardFile.self, from: data).roleCard
        } else if object["spec"] != nil || object["data"] != nil {
            decoded = try decoder.decode(SillyTavernCardFile.self, from: data).native
        } else if object.keys.contains(where: Self.isRoleCardKey) {
            decoded = try decoder.decode(WebRoleCard.self, from: data).native
        } else {
            throw TimeTavernError.invalidImport
        }
        return uniqueRoleCard(decoded, existing: existingRoleCards)
    }

    func importPromptModeJSON(from url: URL, existingModes: [PromptModeConfig]) throws -> PromptModeConfig {
        try importPromptModeJSON(from: try Data(contentsOf: url), existingModes: existingModes)
    }

    func importPromptModeJSON(from data: Data, existingModes: [PromptModeConfig]) throws -> PromptModeConfig {
        let mode = try decoder.decode(PromptModeConfig.self, from: data)
        return uniquePromptMode(mode, existing: existingModes)
    }

    func importCompressionProfileJSON(from url: URL, existingProfiles: [CompressionProfile]) throws -> CompressionProfile {
        try importCompressionProfileJSON(from: try Data(contentsOf: url), existingProfiles: existingProfiles)
    }

    func importCompressionProfileJSON(from data: Data, existingProfiles: [CompressionProfile]) throws -> CompressionProfile {
        let profile = try decoder.decode(CompressionProfile.self, from: data)
        return uniqueCompressionProfile(profile, existing: existingProfiles)
    }

    func exportRoleCardJSON(_ card: RoleCard) throws -> URL {
        try writeJSON(TimeTavernRoleCardFile(roleCard: card), fileName: "role-card-\(safeFileName(card.name)).json")
    }

    func exportPromptModeJSON(_ mode: PromptModeConfig) throws -> URL {
        try writeJSON(mode, fileName: "prompt-mode-\(safeFileName(mode.name)).json")
    }

    func exportCompressionProfileJSON(_ profile: CompressionProfile) throws -> URL {
        try writeJSON(profile, fileName: "compression-profile-\(safeFileName(profile.name)).json")
    }

    private func writeJSON<T: Encodable>(_ value: T, fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(fileName)")
        try encoder.encode(value).write(to: url, options: .atomic)
        return url
    }

    private static func isRoleCardKey(_ key: String) -> Bool {
        [
            "id", "name", "mode", "promptModeId", "coverImage", "coverImageDataURL",
            "coverImageData", "coverPosition", "customSections", "openingDialogue",
            "openingDialogues", "lorebooks"
        ].contains(key)
    }

    private func uniqueRoleCard(_ card: RoleCard, existing: [RoleCard]) -> RoleCard {
        var next = normalizedRoleCard(card)
        if next.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.name = "未命名角色"
        }
        let idConflict = existing.contains { $0.id == next.id }
        let nameConflict = existing.contains { $0.name == next.name }
        if idConflict || nameConflict {
            next.id = UUID().uuidString
            next.name = uniqueName(next.name, existingNames: existing.map(\.name))
            next.createdAt = Date()
            next.updatedAt = Date()
        }
        return next
    }

    private func uniquePromptMode(_ mode: PromptModeConfig, existing: [PromptModeConfig]) -> PromptModeConfig {
        var next = mode
        let idConflict = existing.contains { $0.id == next.id }
        let nameConflict = existing.contains { $0.name == next.name }
        if idConflict || nameConflict {
            let baseID = next.id.isEmpty ? "custom" : next.id
            next.id = "\(baseID)_copy_\(UUID().uuidString.prefix(8))"
            next.mode = next.mode.isEmpty || existing.contains(where: { $0.mode == next.mode }) ? next.id : next.mode
            next.name = uniqueName(next.name.isEmpty ? "自訂模式" : next.name, existingNames: existing.map(\.name))
        }
        return next
    }

    private func uniqueCompressionProfile(_ profile: CompressionProfile, existing: [CompressionProfile]) -> CompressionProfile {
        var next = profile
        let idConflict = existing.contains { $0.id == next.id }
        let nameConflict = existing.contains { $0.name == next.name }
        if idConflict || nameConflict {
            let baseID = next.id.isEmpty ? "compression_profile" : next.id
            next.id = "\(baseID)_copy_\(UUID().uuidString.prefix(8))"
            next.name = uniqueName(next.name.isEmpty ? "自訂壓縮" : next.name, existingNames: existing.map(\.name))
            next.locked = false
        }
        return next
    }

    private func uniqueName(_ name: String, existingNames: [String]) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "副本" : name
        var candidate = "\(base) 副本"
        var index = 2
        while existingNames.contains(candidate) {
            candidate = "\(base) 副本 \(index)"
            index += 1
        }
        return candidate
    }

    private func safeFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "untitled" : trimmed
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return base.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
    }

    private func normalizedRoleCard(_ card: RoleCard) -> RoleCard {
        var next = card
        if next.openingDialogues.isEmpty {
            next.openingDialogues = [OpeningDialogue()]
        }
        if !next.openingDialogues.contains(where: { $0.id == next.activeOpeningDialogueId }) {
            next.activeOpeningDialogueId = next.openingDialogues.first?.id ?? ""
        }
        next.coverPosition = RoleCardCoverPosition(rawValue: next.coverPosition)?.rawValue ?? RoleCardCoverPosition.centerCenter.rawValue
        return next
    }
}

struct TimeTavernRoleCardFile: Codable {
    var format: String = "time_tavern_role_card"
    var version: Int = 1
    var roleCard: RoleCard

    enum CodingKeys: String, CodingKey {
        case format, version, roleCard
        case timeTavernRoleCard
    }

    init(roleCard: RoleCard) {
        self.roleCard = roleCard
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        try container.encode(version, forKey: .version)
        try container.encode(roleCard, forKey: .roleCard)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? "time_tavern_role_card"
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        if let roleCard = try container.decodeIfPresent(RoleCard.self, forKey: .roleCard) {
            self.roleCard = roleCard
        } else if let roleCard = try container.decodeIfPresent(RoleCard.self, forKey: .timeTavernRoleCard) {
            self.roleCard = roleCard
        } else {
            throw TimeTavernError.invalidImport
        }
    }
}

private struct SillyTavernCardFile: Decodable {
    var spec: String?
    var data: SillyTavernCardData

    var native: RoleCard {
        data.native
    }
}

private struct SillyTavernCardData: Decodable {
    var name: String?
    var description: String?
    var personality: String?
    var scenario: String?
    var firstMes: String?
    var alternateGreetings: [String]?
    var mesExample: String?
    var systemPrompt: String?
    var postHistoryInstructions: String?
    var avatar: String?
    var characterBook: SillyTavernCharacterBook?

    enum CodingKeys: String, CodingKey {
        case name, description, personality, scenario, avatar
        case firstMes = "first_mes"
        case alternateGreetings = "alternate_greetings"
        case mesExample = "mes_example"
        case systemPrompt = "system_prompt"
        case postHistoryInstructions = "post_history_instructions"
        case characterBook = "character_book"
    }

    var native: RoleCard {
        var sections: [CustomSection] = []
        appendSection("描述", description, to: &sections)
        appendSection("性格", personality, to: &sections)
        appendSection("場景", scenario, to: &sections)
        appendSection("System Prompt", systemPrompt, to: &sections)
        appendSection("Post History", postHistoryInstructions, to: &sections)
        appendSection("範例對話", mesExample, to: &sections)

        let openings = ([firstMes] + (alternateGreetings ?? []).map(Optional.some))
            .compactMap { value -> String? in
                let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .enumerated()
            .map { index, content in
                OpeningDialogue(name: index == 0 ? "開場" : "替代開場 \(index)", content: content)
            }

        var card = RoleCard()
        card.name = name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name! : "未命名角色"
        card.mode = .multi
        card.promptModeId = RoleCardMode.multi.rawValue
        card.coverImageDataURL = avatar ?? ""
        card.coverImageData = Self.decodeDataURL(avatar)
        card.coverPosition = RoleCardCoverPosition.centerCenter.rawValue
        card.customSections = sections
        card.openingDialogues = openings.isEmpty ? [OpeningDialogue()] : openings
        card.activeOpeningDialogueId = card.openingDialogues.first?.id ?? ""
        card.lorebooks = characterBook?.entries.map(\.native) ?? []
        return card
    }

    private func appendSection(_ name: String, _ content: String?, to sections: inout [CustomSection]) {
        let trimmed = (content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sections.append(CustomSection(name: name, content: trimmed))
    }

    private static func decodeDataURL(_ dataURL: String?) -> Data? {
        guard let dataURL, let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let encoded = String(dataURL[dataURL.index(after: commaIndex)...])
        return Data(base64Encoded: encoded)
    }
}

private struct SillyTavernCharacterBook: Decodable {
    var entries: [SillyTavernBookEntry] = []

    enum CodingKeys: String, CodingKey {
        case entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let entries = try? container.decode([SillyTavernBookEntry].self, forKey: .entries) {
            self.entries = entries
        } else {
            self.entries = []
        }
    }
}

private struct SillyTavernBookEntry: Decodable {
    var id: String?
    var name: String?
    var comment: String?
    var content: String?
    var keys: [String]?
    var enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, comment, content, keys, enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = try container.decodeIfPresent(String.self, forKey: .id)
        }
        name = try container.decodeIfPresent(String.self, forKey: .name)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        keys = try container.decodeIfPresent([String].self, forKey: .keys) ?? []
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
    }

    var native: LorebookEntry {
        LorebookEntry(
            id: id ?? UUID().uuidString,
            title: name ?? comment ?? "世界書",
            keywords: keys ?? [],
            content: content ?? "",
            enabled: enabled ?? true
        )
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
    var promptModeId: String?
    var coverImage: String?
    var coverImageDataURL: String?
    var coverImageData: Data?
    var coverPosition: String?
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
        card.promptModeId = promptModeId ?? card.mode.rawValue
        let imageURL = coverImage ?? coverImageDataURL ?? ""
        card.coverImageDataURL = imageURL
        card.coverImageData = coverImageData ?? Self.decodeDataURL(imageURL)
        card.coverPosition = RoleCardCoverPosition(rawValue: coverPosition ?? "")?.rawValue ?? RoleCardCoverPosition.centerCenter.rawValue
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
