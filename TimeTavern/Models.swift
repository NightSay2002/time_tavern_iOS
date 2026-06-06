import Foundation
import SwiftData

enum MessageRole: String, Codable, CaseIterable, Identifiable {
    case user
    case assistant
    case system

    var id: String { rawValue }
}

enum RoleCardMode: String, Codable, CaseIterable, Identifiable {
    case single
    case multi
    case noRole = "no_role"
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "單角色"
        case .multi: "多角色"
        case .noRole: "無角色"
        case .custom: "自訂"
        }
    }
}

enum RoleCardCoverPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft = "top left"
    case topCenter = "top center"
    case topRight = "top right"
    case centerLeft = "center left"
    case centerCenter = "center center"
    case centerRight = "center right"
    case bottomLeft = "bottom left"
    case bottomCenter = "bottom center"
    case bottomRight = "bottom right"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: "左上"
        case .topCenter: "上方"
        case .topRight: "右上"
        case .centerLeft: "左側"
        case .centerCenter: "中央"
        case .centerRight: "右側"
        case .bottomLeft: "左下"
        case .bottomCenter: "下方"
        case .bottomRight: "右下"
        }
    }
}

enum CompressionTriggerActionKind: String, Codable, CaseIterable, Identifiable {
    case callAPI = "call_api"
    case copyUserInput = "copy_user_input"

    var id: String { rawValue }
}

enum CompressionContextScope: String, Codable, CaseIterable, Identifiable {
    case textOnly = "text_only"
    case roleAndText = "role_and_text"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .textOnly: "只壓縮正文"
        case .roleAndText: "角色卡 + 正文"
        }
    }
}

enum KeywordFollowupAction: String, Codable, CaseIterable, Identifiable {
    case continueReasoner = "continue_reasoner"
    case stopAfterModel = "stop_after_model"
    case imageThenReasoner = "image_then_reasoner"
    case imageParallelReasoner = "image_parallel_reasoner"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continueReasoner: "繼續正文"
        case .stopAfterModel: "模型後停止"
        case .imageThenReasoner: "先出圖再正文"
        case .imageParallelReasoner: "出圖與正文並行"
        }
    }
}

struct UserProfile: Codable, Hashable {
    var userName: String = "user"
    var extraPrompt: String = ""

    init(userName: String = "user", extraPrompt: String = "") {
        self.userName = userName
        self.extraPrompt = extraPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userName = try container.decodeIfPresent(String.self, forKey: .userName) ?? "user"
        extraPrompt = try container.decodeIfPresent(String.self, forKey: .extraPrompt) ?? ""
    }
}

struct APISettings: Codable, Hashable {
    var deepSeekBaseURL: String = "https://api.deepseek.com/v1"
    var deepSeekModel: String = "deepseek-reasoner"
    var maxTokens: Int = 32000
    var temperature: Double = 0.5
    var naiImageBaseURL: String = "https://image.novelai.net"
    var naiPrimaryBaseURL: String = "https://api.novelai.net"

    init(
        deepSeekBaseURL: String = "https://api.deepseek.com/v1",
        deepSeekModel: String = "deepseek-reasoner",
        maxTokens: Int = 32000,
        temperature: Double = 0.5,
        naiImageBaseURL: String = "https://image.novelai.net",
        naiPrimaryBaseURL: String = "https://api.novelai.net"
    ) {
        self.deepSeekBaseURL = deepSeekBaseURL
        self.deepSeekModel = deepSeekModel
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.naiImageBaseURL = naiImageBaseURL
        self.naiPrimaryBaseURL = naiPrimaryBaseURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deepSeekBaseURL = try container.decodeIfPresent(String.self, forKey: .deepSeekBaseURL) ?? "https://api.deepseek.com/v1"
        deepSeekModel = try container.decodeIfPresent(String.self, forKey: .deepSeekModel) ?? "deepseek-reasoner"
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 32000
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.5
        naiImageBaseURL = try container.decodeIfPresent(String.self, forKey: .naiImageBaseURL) ?? "https://image.novelai.net"
        naiPrimaryBaseURL = try container.decodeIfPresent(String.self, forKey: .naiPrimaryBaseURL) ?? "https://api.novelai.net"
    }
}

struct CustomSection: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var content: String = ""
    var enabled: Bool = true

    init(id: String = UUID().uuidString, name: String = "", content: String = "", enabled: Bool = true) {
        self.id = id
        self.name = name
        self.content = content
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

struct OpeningDialogue: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = "開場"
    var content: String = ""

    init(id: String = UUID().uuidString, name: String = "開場", content: String = "") {
        self.id = id
        self.name = name
        self.content = content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "開場"
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
    }
}

struct LorebookEntry: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String = ""
    var keywords: [String] = []
    var content: String = ""
    var enabled: Bool = true
    var insertedTurnNumbers: [Int] = []

    init(
        id: String = UUID().uuidString,
        title: String = "",
        keywords: [String] = [],
        content: String = "",
        enabled: Bool = true,
        insertedTurnNumbers: [Int] = []
    ) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.content = content
        self.enabled = enabled
        self.insertedTurnNumbers = insertedTurnNumbers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        insertedTurnNumbers = try container.decodeIfPresent([Int].self, forKey: .insertedTurnNumbers) ?? []
    }
}

struct RoleCard: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var mode: RoleCardMode = .multi
    var promptModeId: String = "multi"
    var coverImageData: Data?
    var coverImageDataURL: String = ""
    var coverPosition: String = RoleCardCoverPosition.centerCenter.rawValue
    var customSections: [CustomSection] = []
    var openingDialogues: [OpeningDialogue] = [OpeningDialogue()]
    var activeOpeningDialogueId: String = ""
    var lorebooks: [LorebookEntry] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: String = UUID().uuidString,
        name: String = "",
        mode: RoleCardMode = .multi,
        promptModeId: String = "multi",
        coverImageData: Data? = nil,
        coverImageDataURL: String = "",
        coverPosition: String = RoleCardCoverPosition.centerCenter.rawValue,
        customSections: [CustomSection] = [],
        openingDialogues: [OpeningDialogue] = [OpeningDialogue()],
        activeOpeningDialogueId: String = "",
        lorebooks: [LorebookEntry] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.promptModeId = promptModeId
        self.coverImageData = coverImageData
        self.coverImageDataURL = coverImageDataURL
        self.coverPosition = RoleCardCoverPosition(rawValue: coverPosition)?.rawValue ?? RoleCardCoverPosition.centerCenter.rawValue
        self.customSections = customSections
        self.openingDialogues = openingDialogues.isEmpty ? [OpeningDialogue()] : openingDialogues
        self.activeOpeningDialogueId = activeOpeningDialogueId.isEmpty ? self.openingDialogues.first?.id ?? "" : activeOpeningDialogueId
        self.lorebooks = lorebooks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        mode = try container.decodeIfPresent(RoleCardMode.self, forKey: .mode) ?? .multi
        promptModeId = try container.decodeIfPresent(String.self, forKey: .promptModeId) ?? mode.rawValue
        coverImageData = try container.decodeIfPresent(Data.self, forKey: .coverImageData)
        coverImageDataURL = try container.decodeIfPresent(String.self, forKey: .coverImageDataURL) ?? ""
        coverPosition = try container.decodeIfPresent(String.self, forKey: .coverPosition) ?? RoleCardCoverPosition.centerCenter.rawValue
        if RoleCardCoverPosition(rawValue: coverPosition) == nil {
            coverPosition = RoleCardCoverPosition.centerCenter.rawValue
        }
        customSections = try container.decodeIfPresent([CustomSection].self, forKey: .customSections) ?? []
        openingDialogues = try container.decodeIfPresent([OpeningDialogue].self, forKey: .openingDialogues) ?? [OpeningDialogue()]
        if openingDialogues.isEmpty {
            openingDialogues = [OpeningDialogue()]
        }
        activeOpeningDialogueId = try container.decodeIfPresent(String.self, forKey: .activeOpeningDialogueId) ?? openingDialogues.first?.id ?? ""
        if !openingDialogues.contains(where: { $0.id == activeOpeningDialogueId }) {
            activeOpeningDialogueId = openingDialogues.first?.id ?? ""
        }
        lorebooks = try container.decodeIfPresent([LorebookEntry].self, forKey: .lorebooks) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    var activeOpeningDialogue: OpeningDialogue? {
        openingDialogues.first { $0.id == activeOpeningDialogueId } ?? openingDialogues.first
    }
}

struct NovelAIModelOption: Identifiable, Hashable {
    var id: String
    var title: String
    var description: String

    static let defaultID = "nai-diffusion-4-5-full"

    static let allCases: [NovelAIModelOption] = [
        NovelAIModelOption(
            id: "nai-diffusion-4-5-full",
            title: "V4.5 Full",
            description: "NovelAI Diffusion V4.5 Full：最新完整模型。"
        ),
        NovelAIModelOption(
            id: "nai-diffusion-4-5-curated",
            title: "V4.5 Curated",
            description: "NovelAI Diffusion V4.5 Curated：較乾淨穩定的 curated 模型。"
        ),
        NovelAIModelOption(
            id: "nai-diffusion-4-full",
            title: "V4 Full",
            description: "NovelAI Diffusion V4 Full：V4 完整模型。"
        ),
        NovelAIModelOption(
            id: "nai-diffusion-4-curated-preview",
            title: "V4 Curated",
            description: "NovelAI Diffusion V4 Curated：V4 curated preview。"
        ),
        NovelAIModelOption(
            id: "nai-diffusion-3",
            title: "Anime V3",
            description: "NovelAI Diffusion Anime V3。"
        ),
        NovelAIModelOption(
            id: "nai-diffusion-furry-3",
            title: "Furry V3",
            description: "NovelAI Diffusion Furry V3。"
        )
    ]

    static func option(for id: String) -> NovelAIModelOption? {
        allCases.first { $0.id == id }
    }

    static func knownIDOrDefault(_ id: String) -> String {
        option(for: id) == nil ? defaultID : id
    }

    static func title(for id: String) -> String {
        option(for: id)?.title ?? option(for: defaultID)?.title ?? "V4.5 Full"
    }
}

struct CompressionModel: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var addRules: String = ""
    var deleteRules: String = ""
}

struct CompressionTriggerConfig: Codable, Hashable {
    var everyTurn: Bool = false
    var roundLimit: Bool = true
    var keywords: [String] = []
    var keywordSource: String = "both"
    var turns: [Int] = []

    init(
        everyTurn: Bool = false,
        roundLimit: Bool = true,
        keywords: [String] = [],
        keywordSource: String = "both",
        turns: [Int] = []
    ) {
        self.everyTurn = everyTurn
        self.roundLimit = roundLimit
        self.keywords = keywords
        self.keywordSource = keywordSource
        self.turns = turns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        everyTurn = try container.decodeIfPresent(Bool.self, forKey: .everyTurn) ?? false
        roundLimit = try container.decodeIfPresent(Bool.self, forKey: .roundLimit) ?? true
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        keywordSource = try container.decodeIfPresent(String.self, forKey: .keywordSource) ?? "both"
        turns = try container.decodeIfPresent([Int].self, forKey: .turns) ?? []
    }
}

struct NovelAIImageGenerationSettings: Codable, Hashable {
    var model: String = NovelAIModelOption.defaultID
    var negativePrompt: String = "lowres, bad anatomy"
    var width: Int = 832
    var height: Int = 1216
    var steps: Int = 28
    var samples: Int = 1
    var scale: Double = 5
    var cfgRescale: Double = 0
    var sampler: String = "k_euler_ancestral"
    var noiseSchedule: String = "native"
    var ucPreset: Int = 0
    var varietyPlus: Bool = false
    var imageFormat: String = "png"
    var seed: Int?

    init(
        model: String = NovelAIModelOption.defaultID,
        negativePrompt: String = "lowres, bad anatomy",
        width: Int = 832,
        height: Int = 1216,
        steps: Int = 28,
        samples: Int = 1,
        scale: Double = 5,
        cfgRescale: Double = 0,
        sampler: String = "k_euler_ancestral",
        noiseSchedule: String = "native",
        ucPreset: Int = 0,
        varietyPlus: Bool = false,
        imageFormat: String = "png",
        seed: Int? = nil
    ) {
        self.model = NovelAIModelOption.knownIDOrDefault(model)
        self.negativePrompt = negativePrompt
        self.width = width
        self.height = height
        self.steps = steps
        self.samples = samples
        self.scale = scale
        self.cfgRescale = cfgRescale
        self.sampler = sampler
        self.noiseSchedule = noiseSchedule
        self.ucPreset = ucPreset
        self.varietyPlus = varietyPlus
        self.imageFormat = imageFormat
        self.seed = seed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = NovelAIModelOption.knownIDOrDefault(
            try container.decodeIfPresent(String.self, forKey: .model) ?? NovelAIModelOption.defaultID
        )
        negativePrompt = try container.decodeIfPresent(String.self, forKey: .negativePrompt) ?? "lowres, bad anatomy"
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 832
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 1216
        steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? 28
        samples = try container.decodeIfPresent(Int.self, forKey: .samples) ?? 1
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 5
        cfgRescale = try container.decodeIfPresent(Double.self, forKey: .cfgRescale) ?? 0
        sampler = try container.decodeIfPresent(String.self, forKey: .sampler) ?? "k_euler_ancestral"
        noiseSchedule = try container.decodeIfPresent(String.self, forKey: .noiseSchedule) ?? "native"
        ucPreset = try container.decodeIfPresent(Int.self, forKey: .ucPreset) ?? 0
        varietyPlus = try container.decodeIfPresent(Bool.self, forKey: .varietyPlus) ?? false
        imageFormat = try container.decodeIfPresent(String.self, forKey: .imageFormat) ?? "png"
        if let intSeed = try? container.decode(Int.self, forKey: .seed) {
            seed = intSeed
        } else if let stringSeed = try? container.decode(String.self, forKey: .seed) {
            seed = Int(stringSeed.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            seed = nil
        }
    }
}

struct ReasonerHistoryConfig: Codable, Hashable {
    var mainRules: String = ""
    var contextRules: String = ""

    init(mainRules: String = "", contextRules: String = "") {
        self.mainRules = mainRules
        self.contextRules = contextRules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mainRules = try container.decodeIfPresent(String.self, forKey: .mainRules) ?? ""
        contextRules = try container.decodeIfPresent(String.self, forKey: .contextRules) ?? ""
    }
}

struct CompressionContextConfig: Codable, Hashable {
    var mainRules: String = ""
    var models: [CompressionModel] = []

    init(mainRules: String = "", models: [CompressionModel] = []) {
        self.mainRules = mainRules
        self.models = models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mainRules = try container.decodeIfPresent(String.self, forKey: .mainRules) ?? ""
        models = try container.decodeIfPresent([CompressionModel].self, forKey: .models) ?? []
    }
}

struct CompressionTriggerAction: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = "觸發"
    var enabled: Bool = true
    var action: CompressionTriggerActionKind = .callAPI
    var turn: Int?
    var keywords: String = ""
    var source: String = "both"
    var skipChat: Bool = false
    var novelAIEnabled: Bool = false
    var novelAIPromptTemplate: String = ""
    var keywordFollowupAction: KeywordFollowupAction = .continueReasoner
    var skipReasoner: Bool = false
    var imageGeneration: NovelAIImageGenerationSettings = NovelAIImageGenerationSettings()
    var triggers: CompressionTriggerConfig = CompressionTriggerConfig()
    var expanded: Bool = false

    init(
        id: String = UUID().uuidString,
        name: String = "觸發",
        enabled: Bool = true,
        action: CompressionTriggerActionKind = .callAPI,
        turn: Int? = nil,
        keywords: String = "",
        source: String = "both",
        skipChat: Bool = false,
        novelAIEnabled: Bool = false,
        novelAIPromptTemplate: String = "",
        keywordFollowupAction: KeywordFollowupAction = .continueReasoner,
        skipReasoner: Bool = false,
        imageGeneration: NovelAIImageGenerationSettings = NovelAIImageGenerationSettings(),
        triggers: CompressionTriggerConfig = CompressionTriggerConfig(),
        expanded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.action = action
        self.turn = turn
        self.keywords = keywords
        self.source = source
        self.skipChat = skipChat
        self.novelAIEnabled = novelAIEnabled
        self.novelAIPromptTemplate = novelAIPromptTemplate
        self.keywordFollowupAction = keywordFollowupAction
        self.skipReasoner = skipReasoner
        self.imageGeneration = imageGeneration
        var resolvedTriggers = triggers
        if let turn, resolvedTriggers.turns.isEmpty {
            resolvedTriggers.turns = [turn]
        }
        if !keywords.isEmpty && resolvedTriggers.keywords.isEmpty {
            resolvedTriggers.keywords = keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        if source != "both" {
            resolvedTriggers.keywordSource = source
        }
        self.triggers = resolvedTriggers
        self.expanded = expanded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "觸發"
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        action = try container.decodeIfPresent(CompressionTriggerActionKind.self, forKey: .action) ?? .callAPI
        turn = try container.decodeIfPresent(Int.self, forKey: .turn)
        keywords = try container.decodeIfPresent(String.self, forKey: .keywords) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "both"
        skipChat = try container.decodeIfPresent(Bool.self, forKey: .skipChat) ?? false
        novelAIEnabled = try container.decodeIfPresent(Bool.self, forKey: .novelAIEnabled) ?? false
        novelAIPromptTemplate = try container.decodeIfPresent(String.self, forKey: .novelAIPromptTemplate) ?? ""
        keywordFollowupAction = try container.decodeIfPresent(KeywordFollowupAction.self, forKey: .keywordFollowupAction) ?? .continueReasoner
        skipReasoner = try container.decodeIfPresent(Bool.self, forKey: .skipReasoner) ?? skipChat
        imageGeneration = try container.decodeIfPresent(NovelAIImageGenerationSettings.self, forKey: .imageGeneration) ?? NovelAIImageGenerationSettings()
        triggers = try container.decodeIfPresent(CompressionTriggerConfig.self, forKey: .triggers) ?? CompressionTriggerConfig()
        expanded = try container.decodeIfPresent(Bool.self, forKey: .expanded) ?? false
        if let turn, triggers.turns.isEmpty {
            triggers.turns = [turn]
        }
        if !keywords.isEmpty && triggers.keywords.isEmpty {
            triggers.keywords = keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        if source != "both" {
            triggers.keywordSource = source
        }
    }
}

struct CompressionAppendTerm: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var playerSlot: String = "userx"
    var player: String = "userx"
    var content: String = ""
    var enabled: Bool = true

    init(id: String = UUID().uuidString, playerSlot: String = "userx", player: String? = nil, content: String = "", enabled: Bool = true) {
        self.id = id
        self.playerSlot = playerSlot
        self.player = player ?? playerSlot
        self.content = content
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        playerSlot = try container.decodeIfPresent(String.self, forKey: .playerSlot) ?? "userx"
        player = try container.decodeIfPresent(String.self, forKey: .player) ?? playerSlot
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        if playerSlot == "userx", player != "userx" {
            playerSlot = player
        }
    }
}

struct CompressionProfile: Codable, Identifiable, Hashable {
    var id: String = "standard"
    var name: String = "標準壓縮模型"
    var enabled: Bool = true
    var locked: Bool = false
    var contextScope: CompressionContextScope = .textOnly
    var triggers: CompressionTriggerConfig = CompressionTriggerConfig()
    var contextCompression: CompressionContextConfig = CompressionContextConfig()
    var mainRules: String = ""
    var models: [CompressionModel] = []
    var triggerActions: [CompressionTriggerAction] = [CompressionTriggerAction()]
    var appendTerms: [CompressionAppendTerm] = []
    var summary: String = ""
    var compressedThroughTurnNumber: Int = 0
    var updatedAt: Date?

    init(
        id: String = "standard",
        name: String = "標準壓縮模型",
        enabled: Bool = true,
        locked: Bool = false,
        contextScope: CompressionContextScope = .textOnly,
        triggers: CompressionTriggerConfig = CompressionTriggerConfig(),
        contextCompression: CompressionContextConfig? = nil,
        mainRules: String = "",
        models: [CompressionModel] = [],
        triggerActions: [CompressionTriggerAction] = [CompressionTriggerAction()],
        appendTerms: [CompressionAppendTerm] = [],
        summary: String = "",
        compressedThroughTurnNumber: Int = 0,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.locked = locked
        self.contextScope = contextScope
        self.triggers = triggers
        let resolvedContext = contextCompression ?? CompressionContextConfig(mainRules: mainRules, models: models)
        self.contextCompression = resolvedContext
        self.mainRules = resolvedContext.mainRules
        self.models = resolvedContext.models
        self.triggerActions = triggerActions
        self.appendTerms = appendTerms
        self.summary = summary
        self.compressedThroughTurnNumber = compressedThroughTurnNumber
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "standard"
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "標準壓縮模型"
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        contextScope = try container.decodeIfPresent(CompressionContextScope.self, forKey: .contextScope) ?? .textOnly
        triggers = try container.decodeIfPresent(CompressionTriggerConfig.self, forKey: .triggers) ?? CompressionTriggerConfig()
        let legacyMainRules = try container.decodeIfPresent(String.self, forKey: .mainRules) ?? ""
        let legacyModels = try container.decodeIfPresent([CompressionModel].self, forKey: .models) ?? []
        let decodedContext = try container.decodeIfPresent(CompressionContextConfig.self, forKey: .contextCompression)
        contextCompression = decodedContext ?? CompressionContextConfig(mainRules: legacyMainRules, models: legacyModels)
        mainRules = legacyMainRules.isEmpty ? contextCompression.mainRules : legacyMainRules
        models = legacyModels.isEmpty ? contextCompression.models : legacyModels
        if contextCompression.mainRules.isEmpty || contextCompression.models.isEmpty {
            contextCompression = CompressionContextConfig(mainRules: mainRules, models: models)
        }
        triggerActions = try container.decodeIfPresent([CompressionTriggerAction].self, forKey: .triggerActions) ?? [CompressionTriggerAction()]
        appendTerms = try container.decodeIfPresent([CompressionAppendTerm].self, forKey: .appendTerms) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        compressedThroughTurnNumber = try container.decodeIfPresent(Int.self, forKey: .compressedThroughTurnNumber) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct PromptModeConfig: Codable, Identifiable, Hashable {
    var id: String = "multi"
    var name: String = "多角色"
    var mode: String = "multi"
    var dialogueContextRounds: Int = 15
    var mainRules: String = ""
    var outputRules: String = ""
    var reasonerHistory: String = ""
    var reasonerHistoryConfig: ReasonerHistoryConfig = ReasonerHistoryConfig()
    var contextCompression: CompressionContextConfig = CompressionContextConfig()
    var compressionProfiles: [CompressionProfile] = [CompressionProfile()]

    init(
        id: String = "multi",
        name: String = "多角色",
        mode: String = "multi",
        dialogueContextRounds: Int = 15,
        mainRules: String = "",
        outputRules: String = "",
        reasonerHistory: String = "",
        reasonerHistoryConfig: ReasonerHistoryConfig? = nil,
        contextCompression: CompressionContextConfig = CompressionContextConfig(),
        compressionProfiles: [CompressionProfile] = [CompressionProfile()]
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.dialogueContextRounds = dialogueContextRounds
        let resolvedHistory = reasonerHistoryConfig ?? ReasonerHistoryConfig(mainRules: mainRules, contextRules: outputRules)
        self.mainRules = mainRules.isEmpty ? resolvedHistory.mainRules : mainRules
        self.outputRules = outputRules.isEmpty ? resolvedHistory.contextRules : outputRules
        self.reasonerHistory = reasonerHistory
        self.reasonerHistoryConfig = resolvedHistory
        self.contextCompression = contextCompression
        self.compressionProfiles = compressionProfiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decodeIfPresent(String.self, forKey: .id)
        let decodedMode = try container.decodeIfPresent(String.self, forKey: .mode)
        id = decodedID ?? decodedMode ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        mode = decodedMode ?? id
        dialogueContextRounds = try container.decodeIfPresent(Int.self, forKey: .dialogueContextRounds) ?? 15
        mainRules = try container.decodeIfPresent(String.self, forKey: .mainRules) ?? ""
        outputRules = try container.decodeIfPresent(String.self, forKey: .outputRules) ?? ""
        if let historyObject = try? container.decode(ReasonerHistoryConfig.self, forKey: .reasonerHistory) {
            reasonerHistoryConfig = historyObject
            reasonerHistory = [historyObject.mainRules, historyObject.contextRules]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
        } else {
            reasonerHistory = try container.decodeIfPresent(String.self, forKey: .reasonerHistory) ?? ""
            reasonerHistoryConfig = try container.decodeIfPresent(ReasonerHistoryConfig.self, forKey: .reasonerHistoryConfig) ??
                ReasonerHistoryConfig(mainRules: mainRules, contextRules: outputRules)
        }
        if mainRules.isEmpty {
            mainRules = reasonerHistoryConfig.mainRules
        }
        if outputRules.isEmpty {
            outputRules = reasonerHistoryConfig.contextRules
        }
        contextCompression = try container.decodeIfPresent(CompressionContextConfig.self, forKey: .contextCompression) ?? CompressionContextConfig()
        compressionProfiles = try container.decodeIfPresent([CompressionProfile].self, forKey: .compressionProfiles) ?? [CompressionProfile()]
    }
}

struct ConversationMessage: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var role: MessageRole = .user
    var content: String = ""
    var source: String = "ios"
    var turnNumber: Int = 0
    var compressionNotice: Bool = false
    var imageData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct AILogEntry: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var purpose: String = "chat"
    var model: String = ""
    var requestPreview: String = ""
    var responsePreview: String = ""
    var reasoningPreview: String = ""
    var error: String = ""
    var status: String = "success"
    var createdAt: Date = Date()
}

struct SavedSession: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = "未命名存檔"
    var roleCardName: String = ""
    var activeRoleCardId: String = ""
    var conversation: [ConversationMessage] = []
    var promptModes: [PromptModeConfig] = []
    var roleCards: [RoleCard] = []
    var aiLogs: [AILogEntry] = []
    var archived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct TimeTrackingConfig: Codable, Hashable {
    var enabled: Bool = true
    var day: Int = 1
    var period: String = "早上"
    var autoAdvanceRounds: Int = 3
    var keepTimeDirective: String = "{保持時間}"

    init(
        enabled: Bool = true,
        day: Int = 1,
        period: String = "早上",
        autoAdvanceRounds: Int = 3,
        keepTimeDirective: String = "{保持時間}"
    ) {
        self.enabled = enabled
        self.day = day
        self.period = period
        self.autoAdvanceRounds = autoAdvanceRounds
        self.keepTimeDirective = keepTimeDirective
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        day = try container.decodeIfPresent(Int.self, forKey: .day) ?? 1
        period = try container.decodeIfPresent(String.self, forKey: .period) ?? "早上"
        autoAdvanceRounds = try container.decodeIfPresent(Int.self, forKey: .autoAdvanceRounds) ?? 3
        keepTimeDirective = try container.decodeIfPresent(String.self, forKey: .keepTimeDirective) ?? "{保持時間}"
    }
}

struct NovelAIAlbumItem: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var fileName: String = "novelai.png"
    var mimeType: String = "image/png"
    var prompt: String = ""
    var negativePrompt: String = ""
    var model: String = ""
    var seed: Int?
    var imageData: Data = Data()
    var metadata: String = ""
    var createdAt: Date = Date()
}

struct NovelAIPromptSnippet: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var content: String = ""
    var enabled: Bool = true
}

struct NovelAICharacterPrompt: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = "角色"
    var prompt: String = ""
    var enabled: Bool = true
}

struct NovelAIReferenceImage: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = "Reference"
    var type: String = "vibe"
    var imageData: Data?
    var strength: Double = 0.6
    var noise: Double = 0.2
    var enabled: Bool = true
}

struct NovelAIStudioSettings: Codable, Hashable {
    var modelDescription: String = ""
    var basePrompt: String = ""
    var fixedSnippets: [NovelAIPromptSnippet] = []
    var randomSnippets: [NovelAIPromptSnippet] = []
    var negativePrompt: String = "lowres, bad anatomy"
    var characterPrompts: [NovelAICharacterPrompt] = []
    var vibeTransferImages: [NovelAIReferenceImage] = []
    var imageToImageImageData: Data?
    var imageToImageStrength: Double = 0.7
    var imageToImageNoise: Double = 0.2
    var preciseReferenceImages: [NovelAIReferenceImage] = []
    var sizePreset: String = "portrait"
    var customWidth: Int = 832
    var customHeight: Int = 1216
    var imageSettings: NovelAIImageGenerationSettings = NovelAIImageGenerationSettings()
    var loopCount: Int = 1
    var metadataDraft: String = ""

    init(
        modelDescription: String = "",
        basePrompt: String = "",
        fixedSnippets: [NovelAIPromptSnippet] = [],
        randomSnippets: [NovelAIPromptSnippet] = [],
        negativePrompt: String = "lowres, bad anatomy",
        characterPrompts: [NovelAICharacterPrompt] = [],
        vibeTransferImages: [NovelAIReferenceImage] = [],
        imageToImageImageData: Data? = nil,
        imageToImageStrength: Double = 0.7,
        imageToImageNoise: Double = 0.2,
        preciseReferenceImages: [NovelAIReferenceImage] = [],
        sizePreset: String = "portrait",
        customWidth: Int = 832,
        customHeight: Int = 1216,
        imageSettings: NovelAIImageGenerationSettings = NovelAIImageGenerationSettings(),
        loopCount: Int = 1,
        metadataDraft: String = ""
    ) {
        self.modelDescription = modelDescription
        self.basePrompt = basePrompt
        self.fixedSnippets = fixedSnippets
        self.randomSnippets = randomSnippets
        self.negativePrompt = negativePrompt
        self.characterPrompts = characterPrompts
        self.vibeTransferImages = vibeTransferImages
        self.imageToImageImageData = imageToImageImageData
        self.imageToImageStrength = imageToImageStrength
        self.imageToImageNoise = imageToImageNoise
        self.preciseReferenceImages = preciseReferenceImages
        self.sizePreset = sizePreset
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.imageSettings = imageSettings
        self.loopCount = loopCount
        self.metadataDraft = metadataDraft
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelDescription = try container.decodeIfPresent(String.self, forKey: .modelDescription) ?? ""
        basePrompt = try container.decodeIfPresent(String.self, forKey: .basePrompt) ?? ""
        fixedSnippets = try container.decodeIfPresent([NovelAIPromptSnippet].self, forKey: .fixedSnippets) ?? []
        randomSnippets = try container.decodeIfPresent([NovelAIPromptSnippet].self, forKey: .randomSnippets) ?? []
        negativePrompt = try container.decodeIfPresent(String.self, forKey: .negativePrompt) ?? "lowres, bad anatomy"
        characterPrompts = try container.decodeIfPresent([NovelAICharacterPrompt].self, forKey: .characterPrompts) ?? []
        vibeTransferImages = try container.decodeIfPresent([NovelAIReferenceImage].self, forKey: .vibeTransferImages) ?? []
        imageToImageImageData = try container.decodeIfPresent(Data.self, forKey: .imageToImageImageData)
        imageToImageStrength = try container.decodeIfPresent(Double.self, forKey: .imageToImageStrength) ?? 0.7
        imageToImageNoise = try container.decodeIfPresent(Double.self, forKey: .imageToImageNoise) ?? 0.2
        preciseReferenceImages = try container.decodeIfPresent([NovelAIReferenceImage].self, forKey: .preciseReferenceImages) ?? []
        sizePreset = try container.decodeIfPresent(String.self, forKey: .sizePreset) ?? "portrait"
        customWidth = try container.decodeIfPresent(Int.self, forKey: .customWidth) ?? 832
        customHeight = try container.decodeIfPresent(Int.self, forKey: .customHeight) ?? 1216
        imageSettings = try container.decodeIfPresent(NovelAIImageGenerationSettings.self, forKey: .imageSettings) ?? NovelAIImageGenerationSettings()
        loopCount = try container.decodeIfPresent(Int.self, forKey: .loopCount) ?? 1
        metadataDraft = try container.decodeIfPresent(String.self, forKey: .metadataDraft) ?? ""
    }
}

struct AppDefaultsSnapshot: Codable, Hashable {
    var userProfile = UserProfile()
    var apiSettings = APISettings()
    var roleCards: [RoleCard] = []
    var activeRoleCardId: String = ""
    var activeAssistantMode: String = ""
    var promptModes: [PromptModeConfig] = AppState.defaultPromptModes()
    var timeTracking = TimeTrackingConfig()
    var novelAIStudioSettings = NovelAIStudioSettings()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    init(state: AppState, date: Date = Date()) {
        userProfile = state.userProfile
        apiSettings = state.apiSettings
        roleCards = state.roleCards
        activeRoleCardId = state.activeRoleCardId
        activeAssistantMode = state.activeAssistantMode
        promptModes = state.promptModes
        timeTracking = state.timeTracking
        novelAIStudioSettings = state.novelAIStudioSettings
        createdAt = date
        updatedAt = date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userProfile = try container.decodeIfPresent(UserProfile.self, forKey: .userProfile) ?? UserProfile()
        apiSettings = try container.decodeIfPresent(APISettings.self, forKey: .apiSettings) ?? APISettings()
        roleCards = try container.decodeIfPresent([RoleCard].self, forKey: .roleCards) ?? []
        activeRoleCardId = try container.decodeIfPresent(String.self, forKey: .activeRoleCardId) ?? ""
        activeAssistantMode = try container.decodeIfPresent(String.self, forKey: .activeAssistantMode) ?? ""
        promptModes = try container.decodeIfPresent([PromptModeConfig].self, forKey: .promptModes) ?? AppState.defaultPromptModes()
        timeTracking = try container.decodeIfPresent(TimeTrackingConfig.self, forKey: .timeTracking) ?? TimeTrackingConfig()
        novelAIStudioSettings = try container.decodeIfPresent(NovelAIStudioSettings.self, forKey: .novelAIStudioSettings) ?? NovelAIStudioSettings()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

struct AppState: Codable, Hashable {
    var userProfile = UserProfile()
    var apiSettings = APISettings()
    var roleCards: [RoleCard] = []
    var activeRoleCardId: String = ""
    var activeAssistantMode: String = ""
    var promptModes: [PromptModeConfig] = AppState.defaultPromptModes()
    var conversation: [ConversationMessage] = []
    var savedSessions: [SavedSession] = []
    var aiLogs: [AILogEntry] = []
    var timeTracking = TimeTrackingConfig()
    var novelAIAlbum: [NovelAIAlbumItem] = []
    var novelAIStudioSettings = NovelAIStudioSettings()
    var localDefaults: AppDefaultsSnapshot?
    var updatedAt: Date = Date()

    var activeRoleCard: RoleCard? {
        roleCards.first { $0.id == activeRoleCardId }
    }

    static func defaultPromptModes() -> [PromptModeConfig] {
        [
            PromptModeConfig(id: "single", name: "單角色", mode: "single", dialogueContextRounds: 20),
            PromptModeConfig(id: "multi", name: "多角色", mode: "multi", dialogueContextRounds: 15),
            PromptModeConfig(id: "no_role", name: "無角色", mode: "no_role", dialogueContextRounds: 20)
        ]
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userProfile = try container.decodeIfPresent(UserProfile.self, forKey: .userProfile) ?? UserProfile()
        apiSettings = try container.decodeIfPresent(APISettings.self, forKey: .apiSettings) ?? APISettings()
        roleCards = try container.decodeIfPresent([RoleCard].self, forKey: .roleCards) ?? []
        activeRoleCardId = try container.decodeIfPresent(String.self, forKey: .activeRoleCardId) ?? ""
        activeAssistantMode = try container.decodeIfPresent(String.self, forKey: .activeAssistantMode) ?? ""
        promptModes = try container.decodeIfPresent([PromptModeConfig].self, forKey: .promptModes) ?? AppState.defaultPromptModes()
        conversation = try container.decodeIfPresent([ConversationMessage].self, forKey: .conversation) ?? []
        savedSessions = try container.decodeIfPresent([SavedSession].self, forKey: .savedSessions) ?? []
        aiLogs = try container.decodeIfPresent([AILogEntry].self, forKey: .aiLogs) ?? []
        timeTracking = try container.decodeIfPresent(TimeTrackingConfig.self, forKey: .timeTracking) ?? TimeTrackingConfig()
        novelAIAlbum = try container.decodeIfPresent([NovelAIAlbumItem].self, forKey: .novelAIAlbum) ?? []
        novelAIStudioSettings = try container.decodeIfPresent(NovelAIStudioSettings.self, forKey: .novelAIStudioSettings) ?? NovelAIStudioSettings()
        localDefaults = try container.decodeIfPresent(AppDefaultsSnapshot.self, forKey: .localDefaults)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

@Model
final class AppSnapshot {
    @Attribute(.unique) var id: String
    @Attribute(.externalStorage) var payload: Data
    var updatedAt: Date

    init(id: String = "main", payload: Data = Data(), updatedAt: Date = Date()) {
        self.id = id
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

enum TimeTavernError: LocalizedError {
    case missingDeepSeekKey
    case missingNovelAIKey
    case missingActiveRoleCard
    case invalidImport
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingDeepSeekKey:
            "請先在設定輸入 DeepSeek API Key。"
        case .missingNovelAIKey:
            "請先在設定輸入 NovelAI API Token。"
        case .missingActiveRoleCard:
            "請先在角色頁開始一張角色卡。"
        case .invalidImport:
            "匯入檔案格式不正確。"
        case .network(let message):
            message
        }
    }
}
