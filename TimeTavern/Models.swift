import Foundation
import SwiftData

extension Array {
    mutating func remove(atValidOffsets offsets: IndexSet) {
        for offset in offsets.sorted(by: >) where indices.contains(offset) {
            remove(at: offset)
        }
    }
}

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

struct AssistantCard: Identifiable, Hashable, Codable {
    static let characterCardCreationAssistantID = "CharacterCardCreationAssistant"
    static let defaultAssistantName = "建立卡助手"
    static let defaultAssistantDescription = "專門協助建立角色卡、角色群組與無角色模式設定包。"
    static let characterCardCreationAssistant = AssistantCard(
        id: Self.characterCardCreationAssistantID,
        name: Self.defaultAssistantName,
        description: Self.defaultAssistantDescription,
        prompt: Self.defaultPrompt,
        locked: true
    )
    static let allCards: [AssistantCard] = [.characterCardCreationAssistant]
    static let defaultPrompt = "你是角色卡建立助手，請直接輸出正式正文。"

    var id: String
    var name: String
    var description: String
    var prompt: String
    var locked: Bool
    var createdAt: String
    var updatedAt: String

    init(
        id: String = Self.newAssistantID(),
        name: String = "",
        description: String = "",
        prompt: String = "",
        locked: Bool = false,
        createdAt: String = Self.nowISOString(),
        updatedAt: String = Self.nowISOString()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.prompt = prompt
        self.locked = locked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeFirstString(forKeys: [.name, .title, .label])
        description = try container.decodeFirstString(forKeys: [.description, .intro])
        prompt = try container.decodeFirstString(forKeys: [.prompt, .systemPrompt, .systemPromptSnake])
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? Self.nowISOString()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? Self.nowISOString()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(locked, forKey: .locked)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return isDefault ? Self.defaultAssistantName : "新助手"
    }

    var legacyDisplayName: String {
        isDefault ? Self.characterCardCreationAssistantID : id
    }

    var summary: String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return isDefault ? Self.defaultAssistantDescription : "自訂助手卡。"
    }

    var detail: String {
        "啟用後會重置目前對話，只使用助手卡 Prompt 直接回覆。"
    }

    var isDefault: Bool {
        id == Self.characterCardCreationAssistantID
    }

    static func normalizedCards(_ value: [AssistantCard], defaultPrompt: String? = nil) -> [AssistantCard] {
        var cardsById: [String: AssistantCard] = [:]
        var orderedIds: [String] = []
        let fallbackPrompt = defaultPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        for (index, card) in value.enumerated() {
            var next = card.normalized(index: index, defaultPrompt: fallbackPrompt)
            if next.id.isEmpty {
                continue
            }
            if cardsById[next.id] != nil {
                next.id = newAssistantID()
            }
            cardsById[next.id] = next
            orderedIds.append(next.id)
        }

        var defaultCard = characterCardCreationAssistant
        if let importedDefault = cardsById.removeValue(forKey: characterCardCreationAssistantID) {
            defaultCard.description = importedDefault.summary
            let importedPrompt = importedDefault.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            defaultCard.prompt = !fallbackPrompt.isEmpty
                ? fallbackPrompt
                : (importedPrompt.isEmpty ? Self.defaultPrompt : importedDefault.prompt)
            defaultCard.createdAt = importedDefault.createdAt
            defaultCard.updatedAt = importedDefault.updatedAt
        } else if !fallbackPrompt.isEmpty {
            defaultCard.prompt = fallbackPrompt
        }
        defaultCard.name = defaultAssistantName
        defaultCard.locked = true

        let customCards = orderedIds
            .filter { $0 != characterCardCreationAssistantID }
            .compactMap { cardsById[$0] }
        return [defaultCard] + customCards
    }

    static func normalizedMode(_ value: String?, cards: [AssistantCard]) -> String {
        let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return cards.contains { $0.id == normalized } ? normalized : ""
    }

    static func normalizedMode(_ value: String?) -> String {
        normalizedMode(value, cards: allCards)
    }

    static func card(for mode: String?, cards: [AssistantCard]) -> AssistantCard? {
        let normalized = normalizedMode(mode, cards: cards)
        return cards.first { $0.id == normalized }
    }

    static func card(for mode: String?) -> AssistantCard? {
        card(for: mode, cards: allCards)
    }

    static func custom(name: String, prompt: String) -> AssistantCard {
        AssistantCard(
            id: newAssistantID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新助手" : name,
            description: "自訂助手卡。",
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultPrompt : prompt,
            locked: false
        )
    }

    private func normalized(index: Int, defaultPrompt: String) -> AssistantCard {
        var next = self
        let trimmedId = next.id.trimmingCharacters(in: .whitespacesAndNewlines)
        next.id = trimmedId.isEmpty
            ? (index == 0 ? Self.characterCardCreationAssistantID : Self.newAssistantID())
            : trimmedId
        let isDefaultCard = next.id == Self.characterCardCreationAssistantID
        let trimmedName = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = next.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = next.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        next.name = isDefaultCard
            ? Self.defaultAssistantName
            : (trimmedName.isEmpty ? "新助手 \(index + 1)" : trimmedName)
        next.description = trimmedDescription.isEmpty
            ? (isDefaultCard ? Self.defaultAssistantDescription : "自訂助手卡。")
            : trimmedDescription
        next.prompt = trimmedPrompt.isEmpty
            ? (isDefaultCard ? (defaultPrompt.isEmpty ? Self.defaultPrompt : defaultPrompt) : Self.defaultPrompt)
            : next.prompt
        next.locked = isDefaultCard || next.locked
        next.createdAt = next.createdAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.nowISOString() : next.createdAt
        next.updatedAt = next.updatedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.nowISOString() : next.updatedAt
        return next
    }

    private static func newAssistantID() -> String {
        "assistant_\(UUID().uuidString.lowercased())"
    }

    private static func nowISOString() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    enum CodingKeys: String, CodingKey {
        case id, name, title, label, description, intro, prompt, systemPrompt, locked, createdAt, updatedAt
        case systemPromptSnake = "system_prompt"
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

    var isImageGeneration: Bool {
        self == .imageThenReasoner || self == .imageParallelReasoner
    }
}

enum CompressionProfileKind: String, CaseIterable, Identifiable {
    case normal
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "普通大模型"
        case .image: "跑圖大模型"
        }
    }

    var helpText: String {
        switch self {
        case .normal:
            "call api 後保存成模型內容；有模塊時使用 JSON model/delete，沒有模塊時直接保存純文本。"
        case .image:
            "call api 的輸出會當 NovelAI Base Prompt，並使用下方跑圖設定送去建立圖片。"
        }
    }
}

enum CompressionProfileStorageMode: String {
    case plainText
    case json

    var title: String {
        switch self {
        case .plainText: "純文本保存"
        case .json: "JSON 模塊保存"
        }
    }
}

enum CompressionProcessingPhase {
    case beforeReasoner
    case afterAssistant
}

enum UILanguageMode: String, Codable, CaseIterable, Identifiable {
    case traditional = "zh-Hant"
    case simplified = "zh-Hans"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .traditional: "繁體"
        case .simplified: "簡體"
        }
    }

    func title(in language: UILanguageMode) -> String {
        UIChineseTextConverter.convert(title, language: language)
    }
}

enum UIChineseTextConverter {
    static var activeLanguage: UILanguageMode = .traditional

    static let phrasePairs: [(traditional: String, simplified: String)] = [
        ("伺服器", "服务器"),
        ("本地服务器", "本地服务器"),
        ("滑鼠", "鼠标"),
        ("介面", "界面"),
        ("網頁", "网页"),
        ("資料", "资料"),
        ("訊息", "讯息"),
        ("角色卡建立助手", "角色卡建立助手"),
        ("簡繁轉換", "简繁转换"),
        ("繁體", "繁体"),
        ("簡體", "简体")
    ]

    static let traditionalToSimplifiedChars: [Character: Character] = [
        "並": "并", "併": "并", "來": "来", "係": "系", "個": "个", "們": "们",
        "偵": "侦", "儲": "储", "備": "备", "傳": "传", "傷": "伤", "內": "内",
        "關": "关", "刪": "删", "則": "则", "創": "创", "劇": "剧", "動": "动",
        "務": "务", "匯": "汇", "區": "区", "協": "协", "參": "参", "啟": "启",
        "單": "单", "嗎": "吗", "圍": "围", "圖": "图", "團": "团", "場": "场",
        "塊": "块", "壓": "压", "壞": "坏", "學": "学", "寫": "写", "實": "实",
        "專": "专", "對": "对", "導": "导", "張": "张", "後": "后", "從": "从",
        "復": "复", "應": "应", "態": "态", "憶": "忆", "戶": "户", "換": "换",
        "損": "损", "擇": "择", "攔": "拦", "敗": "败", "數": "数", "斷": "断",
        "時": "时", "暫": "暂", "書": "书", "會": "会", "機": "机", "檔": "档",
        "欄": "栏", "權": "权", "歡": "欢", "沒": "没", "測": "测", "準": "准",
        "溫": "温", "為": "为", "無": "无", "產": "产", "現": "现", "環": "环",
        "當": "当", "發": "发", "確": "确", "稱": "称", "範": "范", "簡": "简",
        "紀": "纪", "紅": "红", "純": "纯", "細": "细", "終": "终", "組": "组",
        "結": "结", "給": "给", "統": "统", "經": "经", "網": "网", "綴": "缀",
        "線": "线", "編": "编", "縮": "缩", "總": "总", "繼": "继", "續": "续",
        "義": "义", "與": "与", "舊": "旧", "蓋": "盖", "蘋": "苹", "處": "处",
        "製": "制", "複": "复", "覆": "复", "見": "见", "規": "规", "視": "视",
        "覽": "览", "觸": "触", "訂": "订", "計": "计", "訊": "讯", "記": "记",
        "設": "设", "註": "注", "詞": "词", "試": "试", "話": "话", "該": "该",
        "詳": "详", "誤": "误", "調": "调", "請": "请", "議": "议", "讀": "读",
        "變": "变", "貼": "贴", "資": "资", "載": "载", "輪": "轮", "輯": "辑",
        "輸": "输", "轉": "转", "這": "这", "連": "连", "進": "进", "過": "过",
        "達": "达", "選": "选", "還": "还", "鈕": "钮", "錄": "录", "錯": "错",
        "鍵": "键", "鐘": "钟", "門": "门", "閉": "闭", "開": "开", "間": "间",
        "頁": "页", "項": "项", "順": "顺", "須": "须", "預": "预", "題": "题",
        "顯": "显", "體": "体", "麼": "么", "點": "点"
    ]

    static func convert(_ text: String, language: UILanguageMode) -> String {
        guard language == .simplified else { return text }
        var output = text
        for pair in phrasePairs {
            output = output.replacingOccurrences(of: pair.traditional, with: pair.simplified)
        }
        return String(output.map { traditionalToSimplifiedChars[$0] ?? $0 })
    }
}

func uiStatic(_ text: String) -> String {
    UIChineseTextConverter.convert(text, language: UIChineseTextConverter.activeLanguage)
}

struct UserProfile: Codable, Hashable {
    var userName: String = "user"
    var extraPrompt: String = ""

    private enum CodingKeys: String, CodingKey {
        case userName
        case extraPrompt
        case displayName
        case name
        case identityText
    }

    init(userName: String = "user", extraPrompt: String = "") {
        self.userName = userName
        self.extraPrompt = extraPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userName = try container.decodeIfPresent(String.self, forKey: .userName) ??
            (try container.decodeIfPresent(String.self, forKey: .displayName)) ??
            (try container.decodeIfPresent(String.self, forKey: .name)) ??
            "user"
        extraPrompt = try container.decodeIfPresent(String.self, forKey: .extraPrompt) ??
            (try container.decodeIfPresent(String.self, forKey: .identityText)) ??
            ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userName, forKey: .userName)
        try container.encode(extraPrompt, forKey: .extraPrompt)
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
    var includeInImagePrompt: Bool = false

    init(
        id: String = UUID().uuidString,
        name: String = "",
        content: String = "",
        enabled: Bool = true,
        includeInImagePrompt: Bool = false
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.enabled = enabled
        self.includeInImagePrompt = includeInImagePrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeStringFromPossibleKeys([.name, .title, .key, .label]) ?? ""
        content = try container.decodeStringFromPossibleKeys([.content, .text, .value]) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        includeInImagePrompt = [
            CodingKeys.includeInImagePrompt,
            .imagePrompt,
            .drawPrompt,
            .includeInDrawing,
            .useForImagePrompt
        ].contains { key in
            (try? container.decodeIfPresent(Bool.self, forKey: key)) == true
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(content, forKey: .content)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(includeInImagePrompt, forKey: .includeInImagePrompt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name, title, key, label
        case content, text, value
        case enabled
        case includeInImagePrompt
        case imagePrompt
        case drawPrompt
        case includeInDrawing
        case useForImagePrompt
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
    var secondaryKeywords: [String] = []
    var content: String = ""
    var enabled: Bool = true
    var permanent: Bool = false
    var probability: Int = 100
    var expanded: Bool = false
    var insertedTurnNumbers: [Int] = []

    init(
        id: String = UUID().uuidString,
        title: String = "",
        keywords: [String] = [],
        secondaryKeywords: [String] = [],
        content: String = "",
        enabled: Bool = true,
        permanent: Bool = false,
        probability: Int = 100,
        expanded: Bool = false,
        insertedTurnNumbers: [Int] = []
    ) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.secondaryKeywords = secondaryKeywords
        self.content = content
        self.enabled = enabled
        self.permanent = permanent
        self.probability = Self.clampedProbability(probability)
        self.expanded = expanded
        self.insertedTurnNumbers = insertedTurnNumbers
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case key
        case name
        case comment
        case chineseTitle = "標題"
        case chineseName = "名稱"
        case keywords
        case keyword
        case keys
        case chineseKeywords = "關鍵字"
        case simplifiedChineseKeywords = "关键词"
        case secondaryKeywords
        case secondaryKeyword
        case secondaryKeys
        case secondaryUnderscoreKeys = "secondary_keys"
        case chineseSecondaryKeywords = "第二關鍵字"
        case simplifiedChineseSecondaryKeywords = "第二关键词"
        case content
        case text
        case chineseContent = "內容"
        case enabled
        case permanent
        case constant
        case alwaysActive
        case alwaysActiveSnake = "always_active"
        case probability
        case expanded
        case insertedTurnNumbers
        case activation
        case extensions
    }

    private struct LorebookActivation: Decodable {
        var permanent: Bool?
        var probability: Int?
    }

    private struct LorebookExtensions: Decodable {
        var probability: Int?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        content = try Self.firstDecodedString(in: container, keys: [.content, .text, .chineseContent]) ?? ""
        keywords = Self.decodeTextList(in: container, keys: [.keywords, .keyword, .keys, .chineseKeywords, .simplifiedChineseKeywords])
        secondaryKeywords = Self.decodeTextList(in: container, keys: [
            .secondaryKeywords,
            .secondaryKeyword,
            .secondaryKeys,
            .secondaryUnderscoreKeys,
            .chineseSecondaryKeywords,
            .simplifiedChineseSecondaryKeywords
        ])
        title = Self.firstNonEmpty([
            try Self.firstDecodedString(in: container, keys: [.title, .key, .name, .comment, .chineseTitle, .chineseName]),
            Self.firstMarkdownHeading(in: content),
            keywords.first
        ])
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let activation = try container.decodeIfPresent(LorebookActivation.self, forKey: .activation)
        let extensions = try container.decodeIfPresent(LorebookExtensions.self, forKey: .extensions)
        permanent = try container.decodeIfPresent(Bool.self, forKey: .permanent) ??
            container.decodeIfPresent(Bool.self, forKey: .constant) ??
            container.decodeIfPresent(Bool.self, forKey: .alwaysActive) ??
            container.decodeIfPresent(Bool.self, forKey: .alwaysActiveSnake) ??
            activation?.permanent ??
            false
        let decodedProbability = try container.decodeIfPresent(Int.self, forKey: .probability) ??
            activation?.probability ??
            extensions?.probability ??
            100
        probability = Self.clampedProbability(decodedProbability)
        expanded = try container.decodeIfPresent(Bool.self, forKey: .expanded) ?? false
        insertedTurnNumbers = try container.decodeIfPresent([Int].self, forKey: .insertedTurnNumbers) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(secondaryKeywords, forKey: .secondaryKeywords)
        try container.encode(content, forKey: .content)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(permanent, forKey: .permanent)
        try container.encode(Self.clampedProbability(probability), forKey: .probability)
        try container.encode(expanded, forKey: .expanded)
        try container.encode(insertedTurnNumbers, forKey: .insertedTurnNumbers)
    }

    static func clampedProbability(_ value: Int) -> Int {
        min(100, max(0, value))
    }

    private static func firstDecodedString(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) throws -> String? {
        for key in keys {
            if let value = try container.decodeIfPresent(String.self, forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func decodeTextList(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> [String] {
        for key in keys {
            if let array = try? container.decodeIfPresent([String].self, forKey: key) {
                return dedupeTerms(array)
            }
            if let string = try? container.decodeIfPresent(String.self, forKey: key) {
                return splitTerms(string)
            }
        }
        return []
    }

    private static func splitTerms(_ value: String) -> [String] {
        let separators = CharacterSet(charactersIn: "\n,，、;；|/／")
        return dedupeTerms(value.components(separatedBy: separators))
    }

    private static func dedupeTerms(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private static func firstMarkdownHeading(in text: String) -> String? {
        text.components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("#") else { return nil }
                let title = trimmed.drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? nil : title
            }
            .first
    }

    private static func firstNonEmpty(_ values: [String?]) -> String {
        values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
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
        promptModeId: String? = nil,
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
        self.promptModeId = promptModeId ?? mode.rawValue
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

    static let compressionTriggerDefault = NovelAIImageGenerationSettings(
        model: "nai-diffusion-4-5-curated",
        scale: 6,
        noiseSchedule: "karras"
    )

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
        negativePrompt = try container.decodeStringFromPossibleKeys([.negativePrompt, .negative_prompt, .uc]) ?? "lowres, bad anatomy"
        width = min(2048, max(64, try container.decodeIfPresent(Int.self, forKey: .width) ?? 832))
        height = min(2048, max(64, try container.decodeIfPresent(Int.self, forKey: .height) ?? 1216))
        steps = min(50, max(1, try container.decodeIfPresent(Int.self, forKey: .steps) ?? 28))
        samples = min(8, max(1, try container.decodeIntFromPossibleKeys([.samples, .n_samples]) ?? 1))
        scale = min(20, max(0, try container.decodeDoubleFromPossibleKeys([.scale, .guidance, .promptGuidance]) ?? 5))
        cfgRescale = min(1.5, max(0, try container.decodeDoubleFromPossibleKeys([.cfgRescale, .cfg_rescale, .promptGuidanceRescale]) ?? 0))
        sampler = try container.decodeIfPresent(String.self, forKey: .sampler) ?? "k_euler_ancestral"
        noiseSchedule = try container.decodeStringFromPossibleKeys([.noiseSchedule, .noise_schedule]) ?? "native"
        ucPreset = try container.decodeIfPresent(Int.self, forKey: .ucPreset) ?? 0
        varietyPlus = try container.decodeIfPresent(Bool.self, forKey: .varietyPlus) ??
            (try container.decodeIfPresent(Bool.self, forKey: .skipCfgAboveSigma) ?? false)
        let decodedFormat = try container.decodeStringFromPossibleKeys([.imageFormat, .image_format]) ?? "png"
        imageFormat = decodedFormat == "webp" ? "webp" : "png"
        if let intSeed = try? container.decode(Int.self, forKey: .seed) {
            seed = intSeed
        } else if let stringSeed = try? container.decode(String.self, forKey: .seed) {
            seed = Int(stringSeed.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            seed = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(negativePrompt, forKey: .negativePrompt)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(steps, forKey: .steps)
        try container.encode(samples, forKey: .samples)
        try container.encode(scale, forKey: .scale)
        try container.encode(cfgRescale, forKey: .cfgRescale)
        try container.encode(sampler, forKey: .sampler)
        try container.encode(noiseSchedule, forKey: .noiseSchedule)
        try container.encode(ucPreset, forKey: .ucPreset)
        try container.encode(varietyPlus, forKey: .varietyPlus)
        try container.encode(imageFormat, forKey: .imageFormat)
        try container.encodeIfPresent(seed, forKey: .seed)
    }

    enum CodingKeys: String, CodingKey {
        case model
        case negativePrompt, negative_prompt, uc
        case width, height, steps
        case samples, n_samples
        case scale, guidance, promptGuidance
        case cfgRescale, cfg_rescale, promptGuidanceRescale
        case sampler
        case noiseSchedule, noise_schedule
        case ucPreset
        case varietyPlus, skipCfgAboveSigma
        case imageFormat, image_format
        case seed
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
    var imageGeneration: NovelAIImageGenerationSettings = .compressionTriggerDefault
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
        imageGeneration: NovelAIImageGenerationSettings = .compressionTriggerDefault,
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
        imageGeneration = try container.decodeIfPresent(NovelAIImageGenerationSettings.self, forKey: .imageGeneration) ?? .compressionTriggerDefault
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

    var modelKind: CompressionProfileKind {
        triggerActions.contains { $0.keywordFollowupAction.isImageGeneration } ? .image : .normal
    }

    var storageMode: CompressionProfileStorageMode {
        contextCompression.models.isEmpty ? .plainText : .json
    }

    var storageModeDescription: String {
        switch storageMode {
        case .plainText:
            "無模塊：普通大模型會以純文本保存模型內容，等同網頁端沒有模塊時的 save。"
        case .json:
            "已建立 \(contextCompression.models.count) 個模塊：普通大模型會要求輸出 JSON，使用 model.ID 新增與 delete.ID 刪除。"
        }
    }

    var primaryImageTriggerActionIndex: Int? {
        triggerActions.firstIndex { $0.keywordFollowupAction.isImageGeneration }
    }

    mutating func applyModelKind(_ kind: CompressionProfileKind) {
        if triggerActions.isEmpty {
            triggerActions = [CompressionTriggerAction(name: "觸發組合 1")]
        }

        switch kind {
        case .normal:
            for index in triggerActions.indices where triggerActions[index].keywordFollowupAction.isImageGeneration {
                triggerActions[index].keywordFollowupAction = .continueReasoner
                triggerActions[index].novelAIEnabled = false
            }
        case .image:
            let index = primaryImageTriggerActionIndex ?? triggerActions.startIndex
            triggerActions[index].action = .callAPI
            triggerActions[index].keywordFollowupAction = .imageThenReasoner
            triggerActions[index].novelAIEnabled = true
            if triggerActions[index].imageGeneration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                triggerActions[index].imageGeneration = .compressionTriggerDefault
            }
        }
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

struct ConversationTurnSnapshot: Codable, Hashable {
    var promptModes: [PromptModeConfig] = []
    var timeTracking: TimeTrackingConfig = TimeTrackingConfig()

    init(promptModes: [PromptModeConfig] = [], timeTracking: TimeTrackingConfig = TimeTrackingConfig()) {
        self.promptModes = promptModes
        self.timeTracking = timeTracking
    }

    init(state: AppState) {
        promptModes = state.promptModes
        timeTracking = state.timeTracking
    }
}

struct ConversationMessage: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var role: MessageRole = .user
    var content: String = ""
    var source: String = "ios"
    var turnNumber: Int = 0
    var compressionNotice: Bool = false
    var autoTimeWarning: String = ""
    var feedback: String = ""
    var streamingReasoningPreview: String = ""
    var stateBeforeTurnSnapshot: ConversationTurnSnapshot?
    var stateAfterTurnSnapshot: ConversationTurnSnapshot?
    var imageData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: String = UUID().uuidString,
        role: MessageRole = .user,
        content: String = "",
        source: String = "ios",
        turnNumber: Int = 0,
        compressionNotice: Bool = false,
        autoTimeWarning: String = "",
        feedback: String = "",
        streamingReasoningPreview: String = "",
        stateBeforeTurnSnapshot: ConversationTurnSnapshot? = nil,
        stateAfterTurnSnapshot: ConversationTurnSnapshot? = nil,
        imageData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.source = source
        self.turnNumber = turnNumber
        self.compressionNotice = compressionNotice
        self.autoTimeWarning = autoTimeWarning
        self.feedback = feedback
        self.streamingReasoningPreview = streamingReasoningPreview
        self.stateBeforeTurnSnapshot = stateBeforeTurnSnapshot
        self.stateAfterTurnSnapshot = stateAfterTurnSnapshot
        self.imageData = imageData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        role = try container.decodeIfPresent(MessageRole.self, forKey: .role) ?? .user
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "ios"
        turnNumber = try container.decodeIfPresent(Int.self, forKey: .turnNumber) ?? 0
        compressionNotice = try container.decodeIfPresent(Bool.self, forKey: .compressionNotice) ?? false
        autoTimeWarning = try container.decodeIfPresent(String.self, forKey: .autoTimeWarning) ?? ""
        feedback = try container.decodeIfPresent(String.self, forKey: .feedback) ?? ""
        streamingReasoningPreview = try container.decodeIfPresent(String.self, forKey: .streamingReasoningPreview) ?? ""
        stateBeforeTurnSnapshot = try container.decodeIfPresent(ConversationTurnSnapshot.self, forKey: .stateBeforeTurnSnapshot)
        stateAfterTurnSnapshot = try container.decodeIfPresent(ConversationTurnSnapshot.self, forKey: .stateAfterTurnSnapshot)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

struct AILogEntry: Codable, Identifiable, Hashable {
    static let storesBoundedRuntimePayloads = true
    static let maxStoredRequestCharacters = 6000
    static let maxStoredResponseCharacters = 6000
    static let maxStoredReasoningCharacters = 2400
    static let truncationNotice = "\n\n[內容過長，已只保留預覽以避免記憶體暴增。]"

    var id: String = UUID().uuidString
    var purpose: String = "chat"
    var model: String = ""
    var temperature: Double?
    var maxTokens: Int?
    var requestMessages: [ChatAPIMessage] = []
    var responseText: String = ""
    var debugReasoningContent: String = ""
    var usage: AIUsage?
    var requestPreview: String = ""
    var responsePreview: String = ""
    var reasoningPreview: String = ""
    var usageSummary: String = ""
    var error: String = ""
    var status: String = "success"
    var createdAt: Date = Date()

    private enum CodingKeys: String, CodingKey {
        case id
        case purpose
        case model
        case temperature
        case maxTokens
        case requestMessages
        case responseText
        case debugReasoningContent
        case usage
        case requestPreview
        case responsePreview
        case reasoningPreview
        case usageSummary
        case error
        case status
        case createdAt
    }

    init(
        id: String = UUID().uuidString,
        purpose: String = "chat",
        model: String = "",
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        requestMessages: [ChatAPIMessage] = [],
        responseText: String = "",
        debugReasoningContent: String = "",
        usage: AIUsage? = nil,
        requestPreview: String = "",
        responsePreview: String = "",
        reasoningPreview: String = "",
        usageSummary: String = "",
        error: String = "",
        status: String = "success",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.purpose = purpose
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.requestMessages = Self.compactedMessages(requestMessages, maxTotalCharacters: Self.maxStoredRequestCharacters)
        self.responseText = Self.truncated(responseText.isEmpty ? responsePreview : responseText, maxCharacters: Self.maxStoredResponseCharacters)
        self.debugReasoningContent = Self.truncated(debugReasoningContent.isEmpty ? reasoningPreview : debugReasoningContent, maxCharacters: Self.maxStoredReasoningCharacters)
        self.usage = usage
        self.requestPreview = requestPreview.isEmpty ? Self.preview(for: self.requestMessages) : Self.truncated(requestPreview, maxCharacters: 1600)
        self.responsePreview = responsePreview.isEmpty ? self.responseText.prefixString(1600) : Self.truncated(responsePreview, maxCharacters: 1600)
        self.reasoningPreview = reasoningPreview.isEmpty ? self.debugReasoningContent.prefixString(1600) : Self.truncated(reasoningPreview, maxCharacters: 1600)
        self.usageSummary = usageSummary.isEmpty ? (usage?.formattedSummary ?? "") : usageSummary
        self.error = error
        self.status = status
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose) ?? "chat"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
        let decodedRequestMessages = try container.decodeIfPresent([ChatAPIMessage].self, forKey: .requestMessages) ?? []
        requestMessages = Self.compactedMessages(decodedRequestMessages, maxTotalCharacters: Self.maxStoredRequestCharacters)
        let decodedResponseText = try container.decodeIfPresent(String.self, forKey: .responseText) ??
            (try container.decodeIfPresent(String.self, forKey: .responsePreview) ?? "")
        responseText = Self.truncated(decodedResponseText, maxCharacters: Self.maxStoredResponseCharacters)
        let decodedReasoning = try container.decodeIfPresent(String.self, forKey: .debugReasoningContent) ??
            (try container.decodeIfPresent(String.self, forKey: .reasoningPreview) ?? "")
        debugReasoningContent = Self.truncated(decodedReasoning, maxCharacters: Self.maxStoredReasoningCharacters)
        usage = try container.decodeIfPresent(AIUsage.self, forKey: .usage)
        requestPreview = try container.decodeIfPresent(String.self, forKey: .requestPreview) ?? Self.preview(for: requestMessages)
        responsePreview = try container.decodeIfPresent(String.self, forKey: .responsePreview) ?? responseText.prefixString(1600)
        reasoningPreview = try container.decodeIfPresent(String.self, forKey: .reasoningPreview) ?? debugReasoningContent.prefixString(1600)
        requestPreview = Self.truncated(requestPreview, maxCharacters: 1600)
        responsePreview = Self.truncated(responsePreview, maxCharacters: 1600)
        reasoningPreview = Self.truncated(reasoningPreview, maxCharacters: 1600)
        usageSummary = try container.decodeIfPresent(String.self, forKey: .usageSummary) ?? (usage?.formattedSummary ?? "")
        error = try container.decodeIfPresent(String.self, forKey: .error) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "success"
        createdAt = Self.decodeCreatedAt(from: container) ?? Date()
    }

    func compactedForRuntimeStorage() -> AILogEntry {
        AILogEntry(
            id: id,
            purpose: purpose,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens,
            requestMessages: requestMessages,
            responseText: responseText,
            debugReasoningContent: debugReasoningContent,
            usage: usage,
            requestPreview: requestPreview,
            responsePreview: responsePreview,
            reasoningPreview: reasoningPreview,
            usageSummary: usageSummary,
            error: error,
            status: status,
            createdAt: createdAt
        )
    }

    static func compactedMessages(_ messages: [ChatAPIMessage], maxTotalCharacters: Int) -> [ChatAPIMessage] {
        guard maxTotalCharacters > 0 else { return [] }
        var remaining = maxTotalCharacters
        var output: [ChatAPIMessage] = []
        for message in messages {
            guard remaining > 0 else { break }
            let reservedForNotice = truncationNotice.count
            let limit = max(0, remaining)
            let content = truncated(message.content, maxCharacters: max(limit, reservedForNotice + 1))
            remaining -= min(message.content.count, limit)
            output.append(ChatAPIMessage(role: message.role, content: content))
            if content.count > limit {
                remaining = 0
            }
        }
        if output.count < messages.count {
            output.append(ChatAPIMessage(role: "system", content: "[AI Log 已省略 \(messages.count - output.count) 則過長訊息以節省記憶體。]"))
        }
        return output
    }

    static func truncated(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0, text.count > maxCharacters else { return text }
        let headCount = max(0, maxCharacters - truncationNotice.count)
        return String(text.prefix(headCount)) + truncationNotice
    }

    private static func preview(for messages: [ChatAPIMessage]) -> String {
        messages.enumerated()
            .map { index, message in
                "#\(index + 1) \(message.role)\n\(message.content)"
            }
            .joined(separator: "\n\n----------------\n\n")
            .prefixString(1600)
    }

    private static func decodeCreatedAt(from container: KeyedDecodingContainer<CodingKeys>) -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: .createdAt) {
            return date
        }
        guard let text = try? container.decodeIfPresent(String.self, forKey: .createdAt) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: text)
    }
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

enum TimeTrackingPeriod: String, Codable, CaseIterable, Identifiable {
    case morning
    case noon
    case evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: "早上"
        case .noon: "中午"
        case .evening: "晚上"
        }
    }

    var next: TimeTrackingPeriod {
        switch self {
        case .morning: .noon
        case .noon: .evening
        case .evening: .morning
        }
    }

    static func normalized(_ value: String?) -> TimeTrackingPeriod {
        switch (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "morning", "早", "早上":
            .morning
        case "noon", "afternoon", "午", "中午", "下午":
            .noon
        case "evening", "night", "晚", "晚上":
            .evening
        default:
            .morning
        }
    }
}

struct TimeTrackingAutoPeriodConfig: Codable, Hashable {
    var enabled: Bool = false
    var roundsPerPeriod: Int = 3
    var turnsSinceChange: Int = 0

    init(enabled: Bool = false, roundsPerPeriod: Int = 3, turnsSinceChange: Int = 0) {
        self.enabled = enabled
        self.roundsPerPeriod = max(1, roundsPerPeriod)
        self.turnsSinceChange = max(0, turnsSinceChange)
    }

    enum CodingKeys: String, CodingKey {
        case enabled, roundsPerPeriod, turnsPerPeriod, intervalRounds, rounds, turns
        case turnsSinceChange, roundsSinceChange, counter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let rawRounds = try container.decodeIntFromPossibleKeys([
            .roundsPerPeriod, .turnsPerPeriod, .intervalRounds, .rounds, .turns
        ]) ?? 3
        roundsPerPeriod = max(1, rawRounds)
        let rawTurnsSinceChange = try container.decodeIntFromPossibleKeys([
            .turnsSinceChange, .roundsSinceChange, .counter
        ]) ?? 0
        turnsSinceChange = max(0, rawTurnsSinceChange)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(roundsPerPeriod, forKey: .roundsPerPeriod)
        try container.encode(turnsSinceChange, forKey: .turnsSinceChange)
    }
}

struct TimeTrackingRulesConfig: Codable, Hashable {
    static let defaultNextDayWords = ["下一天", "第二天", "隔天", "翌日", "次日", "明天", "明日"]
    static let defaultConnectorWords = ["來到", "来到", "已經", "已经", "現在", "现在", "到了", "變成", "变成", "已是"]
    static let defaultNoChangeWords = ["等到", "等一下", "的時候", "的时候"]
    static let defaultMorningWords = ["早上", "早晨", "清晨", "早餐", "早飯", "早饭", "上午", "天亮"]
    static let defaultNoonWords = ["中午", "下午", "午餐", "午飯", "午饭", "正午"]
    static let defaultEveningWords = ["晚上", "夜晚", "晚餐", "晚飯", "晚饭", "傍晚", "深夜", "夜裡", "夜里"]

    var nextDayWords: [String] = Self.defaultNextDayWords
    var connectorWords: [String] = Self.defaultConnectorWords
    var noChangeWords: [String] = Self.defaultNoChangeWords
    var morningWords: [String] = Self.defaultMorningWords
    var noonWords: [String] = Self.defaultNoonWords
    var eveningWords: [String] = Self.defaultEveningWords

    init(
        nextDayWords: [String] = Self.defaultNextDayWords,
        connectorWords: [String] = Self.defaultConnectorWords,
        noChangeWords: [String] = Self.defaultNoChangeWords,
        morningWords: [String] = Self.defaultMorningWords,
        noonWords: [String] = Self.defaultNoonWords,
        eveningWords: [String] = Self.defaultEveningWords
    ) {
        self.nextDayWords = Self.normalizedWords(nextDayWords, fallback: Self.defaultNextDayWords)
        self.connectorWords = Self.normalizedWords(connectorWords, fallback: Self.defaultConnectorWords)
        self.noChangeWords = Self.normalizedWords(noChangeWords, fallback: Self.defaultNoChangeWords)
        self.morningWords = Self.normalizedWords(morningWords, fallback: Self.defaultMorningWords)
        self.noonWords = Self.normalizedWords(noonWords, fallback: Self.defaultNoonWords)
        self.eveningWords = Self.normalizedWords(eveningWords, fallback: Self.defaultEveningWords)
    }

    enum CodingKeys: String, CodingKey {
        case nextDayWords, dayWords, dayProgressWords
        case connectorWords, timeConnectorWords, matchWords
        case noChangeWords, blockWords, ignoreWords, preventWords
        case morningWords, earlyWords
        case noonWords, afternoonWords
        case eveningWords, nightWords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextDayWords = Self.normalizedWords(
            try container.decodeStringArrayFromPossibleKeys([.nextDayWords, .dayWords, .dayProgressWords]),
            fallback: Self.defaultNextDayWords
        )
        connectorWords = Self.normalizedWords(
            try container.decodeStringArrayFromPossibleKeys([.connectorWords, .timeConnectorWords, .matchWords]),
            fallback: Self.defaultConnectorWords
        )
        noChangeWords = Self.normalizedWords(
            try container.decodeStringArrayFromPossibleKeys([.noChangeWords, .blockWords, .ignoreWords, .preventWords]),
            fallback: Self.defaultNoChangeWords
        )
        morningWords = Self.normalizedWords(
            try container.decodeStringArrayFromPossibleKeys([.morningWords, .earlyWords]),
            fallback: Self.defaultMorningWords
        )
        noonWords = Self.normalizedWords(
            try container.decodeStringArrayFromPossibleKeys([.noonWords, .afternoonWords]),
            fallback: Self.defaultNoonWords
        )
        eveningWords = Self.normalizedWords(
            try container.decodeStringArrayFromPossibleKeys([.eveningWords, .nightWords]),
            fallback: Self.defaultEveningWords
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nextDayWords, forKey: .nextDayWords)
        try container.encode(connectorWords, forKey: .connectorWords)
        try container.encode(noChangeWords, forKey: .noChangeWords)
        try container.encode(morningWords, forKey: .morningWords)
        try container.encode(noonWords, forKey: .noonWords)
        try container.encode(eveningWords, forKey: .eveningWords)
    }

    private static func normalizedWords(_ words: [String]?, fallback: [String]) -> [String] {
        var seen = Set<String>()
        let normalized = (words ?? [])
            .flatMap { $0.split(whereSeparator: { "\n,，、;；|/／".contains($0) }).map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { word in
                let key = word.folding(options: [.widthInsensitive, .caseInsensitive], locale: nil)
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
        return normalized.isEmpty ? fallback : normalized
    }
}

struct TimeTrackingConfig: Codable, Hashable {
    var enabled: Bool = true
    var currentDayNumber: Int = 1
    var currentPeriod: String = TimeTrackingPeriod.morning.rawValue
    var currentYear: Int = Calendar.current.component(.year, from: Date())
    var currentMonth: Int = max(1, Calendar.current.component(.month, from: Date()))
    var currentDate: Int = max(1, Calendar.current.component(.day, from: Date()))
    var autoPeriod = TimeTrackingAutoPeriodConfig()
    var config = TimeTrackingRulesConfig()
    var keepTimeDirective: String = "{保持時間}"
    var updatedAt: Date = Date()

    var day: Int {
        get { currentDayNumber }
        set { currentDayNumber = max(1, newValue) }
    }

    var period: String {
        get { currentPeriodValue.title }
        set { currentPeriod = TimeTrackingPeriod.normalized(newValue).rawValue }
    }

    var autoAdvanceRounds: Int {
        get { autoPeriod.roundsPerPeriod }
        set { autoPeriod.roundsPerPeriod = max(1, newValue) }
    }

    var currentPeriodValue: TimeTrackingPeriod {
        get { TimeTrackingPeriod.normalized(currentPeriod) }
        set { currentPeriod = newValue.rawValue }
    }

    init(
        enabled: Bool = true,
        day: Int = 1,
        period: String = TimeTrackingPeriod.morning.rawValue,
        autoAdvanceRounds: Int = 3,
        keepTimeDirective: String = "{保持時間}"
    ) {
        self.enabled = enabled
        currentDayNumber = max(1, day)
        currentPeriod = TimeTrackingPeriod.normalized(period).rawValue
        autoPeriod = TimeTrackingAutoPeriodConfig(enabled: false, roundsPerPeriod: autoAdvanceRounds)
        self.keepTimeDirective = keepTimeDirective
    }

    enum CodingKeys: String, CodingKey {
        case enabled, currentDayNumber, dayNumber, day
        case currentPeriod, period, timeOfDay
        case currentYear, year
        case currentMonth, month, startMonth
        case currentDate, date, dayOfMonth, startDate
        case autoPeriod, autoTime, autoSwitch, autoAdvanceRounds
        case config, rules
        case keepTimeDirective, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        currentDayNumber = max(1, try container.decodeIntFromPossibleKeys([.currentDayNumber, .dayNumber, .day]) ?? 1)
        currentPeriod = TimeTrackingPeriod.normalized(
            try container.decodeStringFromPossibleKeys([.currentPeriod, .period, .timeOfDay])
        ).rawValue
        let fallbackYear = Calendar.current.component(.year, from: Date())
        currentYear = max(1, try container.decodeIntFromPossibleKeys([.currentYear, .year]) ?? fallbackYear)
        let decodedMonth = try container.decodeIntFromPossibleKeys([.currentMonth, .month, .startMonth])
        let decodedDate = try container.decodeIntFromPossibleKeys([.currentDate, .date, .dayOfMonth, .startDate])
        currentMonth = min(12, max(1, decodedMonth ?? Calendar.current.component(.month, from: Date())))
        currentDate = min(Self.daysInMonth(year: currentYear, month: currentMonth), max(1, decodedDate ?? Calendar.current.component(.day, from: Date())))
        if let decodedAuto = try container.decodeIfPresent(TimeTrackingAutoPeriodConfig.self, forKey: .autoPeriod) ??
            container.decodeIfPresent(TimeTrackingAutoPeriodConfig.self, forKey: .autoTime) ??
            container.decodeIfPresent(TimeTrackingAutoPeriodConfig.self, forKey: .autoSwitch) {
            autoPeriod = decodedAuto
        } else {
            autoPeriod = TimeTrackingAutoPeriodConfig(
                enabled: false,
                roundsPerPeriod: try container.decodeIfPresent(Int.self, forKey: .autoAdvanceRounds) ?? 3
            )
        }
        config = try container.decodeIfPresent(TimeTrackingRulesConfig.self, forKey: .config) ??
            container.decodeIfPresent(TimeTrackingRulesConfig.self, forKey: .rules) ??
            TimeTrackingRulesConfig()
        keepTimeDirective = try container.decodeIfPresent(String.self, forKey: .keepTimeDirective) ?? "{保持時間}"
        if let date = try? container.decode(Date.self, forKey: .updatedAt) {
            updatedAt = date
        } else if let rawDate = try container.decodeIfPresent(String.self, forKey: .updatedAt),
                  let date = ISO8601DateFormatter().date(from: rawDate) {
            updatedAt = date
        } else {
            updatedAt = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(currentDayNumber, forKey: .currentDayNumber)
        try container.encode(currentPeriod, forKey: .currentPeriod)
        try container.encode(currentYear, forKey: .currentYear)
        try container.encode(currentMonth, forKey: .currentMonth)
        try container.encode(currentDate, forKey: .currentDate)
        try container.encode(autoPeriod, forKey: .autoPeriod)
        try container.encode(config, forKey: .config)
        try container.encode(keepTimeDirective, forKey: .keepTimeDirective)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components) ?? Date()
        return calendar.range(of: .day, in: .month, for: date)?.count ?? 31
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
    var min: Int = 1
    var max: Int = 1
    var squareEnabled: Bool = false
    var squareMax: Int = 0
    var curlyEnabled: Bool = false
    var curlyMax: Int = 0
    var weightEnabled: Bool = false
    var weightMin: Double = 0
    var weightMax: Double = 0
    var weightBias: Double = 0

    init(
        id: String = UUID().uuidString,
        name: String = "",
        content: String = "",
        enabled: Bool = true,
        min: Int = 1,
        max: Int = 1,
        squareEnabled: Bool = false,
        squareMax: Int = 0,
        curlyEnabled: Bool = false,
        curlyMax: Int = 0,
        weightEnabled: Bool = false,
        weightMin: Double = 0,
        weightMax: Double = 0,
        weightBias: Double = 0
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.enabled = enabled
        self.min = Swift.max(0, min)
        self.max = Swift.max(self.min, max)
        self.squareEnabled = squareEnabled
        self.squareMax = Swift.max(0, squareMax)
        self.curlyEnabled = curlyEnabled
        self.curlyMax = Swift.max(0, curlyMax)
        self.weightEnabled = weightEnabled
        self.weightMin = Swift.max(0, weightMin)
        self.weightMax = Swift.max(self.weightMin, weightMax)
        self.weightBias = Swift.max(self.weightMin, Swift.min(self.weightMax, weightBias))
    }

    enum CodingKeys: String, CodingKey {
        case id, name, title, key, content, prompt, text, randomText, randomItems, random
        case choices, enabled, min, max, minPick, maxPick, pickMin, pickMax
        case squareEnabled, squareMax, curlyEnabled, curlyMax
        case weightEnabled, weightMin, weightMax, weightBias
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeStringFromPossibleKeys([.name, .title, .key]) ?? ""
        content = try container.decodeStringFromPossibleKeys([.content, .prompt, .text, .randomText, .randomItems, .random, .choices]) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let decodedMin = try container.decodeIntFromPossibleKeys([.min, .minPick, .pickMin]) ?? 1
        let decodedMax = try container.decodeIntFromPossibleKeys([.max, .maxPick, .pickMax]) ?? Swift.max(1, decodedMin)
        min = Swift.max(0, decodedMin)
        max = Swift.max(min, decodedMax)
        squareEnabled = try container.decodeIfPresent(Bool.self, forKey: .squareEnabled) ?? false
        squareMax = Swift.max(0, try container.decodeIfPresent(Int.self, forKey: .squareMax) ?? 0)
        curlyEnabled = try container.decodeIfPresent(Bool.self, forKey: .curlyEnabled) ?? false
        curlyMax = Swift.max(0, try container.decodeIfPresent(Int.self, forKey: .curlyMax) ?? 0)
        weightEnabled = try container.decodeIfPresent(Bool.self, forKey: .weightEnabled) ?? false
        weightMin = Swift.max(0, try container.decodeIfPresent(Double.self, forKey: .weightMin) ?? 0)
        weightMax = Swift.max(weightMin, try container.decodeIfPresent(Double.self, forKey: .weightMax) ?? weightMin)
        weightBias = Swift.max(weightMin, Swift.min(weightMax, try container.decodeIfPresent(Double.self, forKey: .weightBias) ?? ((weightMin + weightMax) / 2)))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(content, forKey: .content)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(min, forKey: .min)
        try container.encode(max, forKey: .max)
        try container.encode(squareEnabled, forKey: .squareEnabled)
        try container.encode(squareMax, forKey: .squareMax)
        try container.encode(curlyEnabled, forKey: .curlyEnabled)
        try container.encode(curlyMax, forKey: .curlyMax)
        try container.encode(weightEnabled, forKey: .weightEnabled)
        try container.encode(weightMin, forKey: .weightMin)
        try container.encode(weightMax, forKey: .weightMax)
        try container.encode(weightBias, forKey: .weightBias)
    }
}

struct NovelAICharacterPositionCell: Identifiable, Hashable {
    var row: Int
    var col: Int

    var id: String { "\(row)-\(col)" }
    var label: String { "R\(row) C\(col)" }
    var buttonTitle: String { "\(row),\(col)" }
    var x: Double { Double(col - 1) / 4 }
    var y: Double { Double(row - 1) / 4 }

    static let allCells: [NovelAICharacterPositionCell] = (1...5).flatMap { row in
        (1...5).map { col in
            NovelAICharacterPositionCell(row: row, col: col)
        }
    }

    init(row: Int, col: Int) {
        self.row = min(5, max(1, row))
        self.col = min(5, max(1, col))
    }

    init(x: Double, y: Double) {
        let col = Int((min(1, max(0, x)) * 4).rounded()) + 1
        let row = Int((min(1, max(0, y)) * 4).rounded()) + 1
        self.init(row: row, col: col)
    }
}

struct NovelAICharacterPrompt: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = "角色"
    var prompt: String = ""
    var negativePrompt: String = ""
    var enabled: Bool = true
    var x: Double = 0.5
    var y: Double = 0.5

    init(
        id: String = UUID().uuidString,
        name: String = "角色",
        prompt: String = "",
        negativePrompt: String = "",
        enabled: Bool = true,
        x: Double = 0.5,
        y: Double = 0.5
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.enabled = enabled
        self.x = min(1, max(0, x))
        self.y = min(1, max(0, y))
    }

    var positionCell: NovelAICharacterPositionCell {
        NovelAICharacterPositionCell(x: x, y: y)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, title
        case prompt, char_caption, caption
        case negativePrompt, negative_prompt, uc
        case enabled, x, y, center, centers
    }

    enum CenterCodingKeys: String, CodingKey {
        case x, y
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeStringFromPossibleKeys([.name, .title]) ?? "角色"
        prompt = try container.decodeStringFromPossibleKeys([.prompt, .char_caption, .caption]) ?? ""
        negativePrompt = try container.decodeStringFromPossibleKeys([.negativePrompt, .negative_prompt, .uc]) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true

        let center = try Self.decodeCenter(from: container)
        let decodedX = try container.decodeDoubleFromPossibleKeys([.x]) ?? center?.x ?? 0.5
        let decodedY = try container.decodeDoubleFromPossibleKeys([.y]) ?? center?.y ?? 0.5
        x = min(1, max(0, decodedX))
        y = min(1, max(0, decodedY))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(negativePrompt, forKey: .negativePrompt)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }

    private static func decodeCenter(from container: KeyedDecodingContainer<CodingKeys>) throws -> (x: Double, y: Double)? {
        if var centers = try? container.nestedUnkeyedContainer(forKey: .centers),
           !centers.isAtEnd {
            let center = try centers.nestedContainer(keyedBy: CenterCodingKeys.self)
            let x = try center.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
            let y = try center.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
            return (x, y)
        }
        if let center = try? container.nestedContainer(keyedBy: CenterCodingKeys.self, forKey: .center) {
            let x = try center.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
            let y = try center.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
            return (x, y)
        }
        return nil
    }
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
        basePrompt = try container.decodeStringFromPossibleKeys([.basePrompt, .prompt, .promptTemplate, .prompt_template]) ?? ""
        fixedSnippets = try container.decodeIfPresent([NovelAIPromptSnippet].self, forKey: .fixedSnippets) ?? []
        randomSnippets = try container.decodeIfPresent([NovelAIPromptSnippet].self, forKey: .randomSnippets) ?? []
        negativePrompt = try container.decodeStringFromPossibleKeys([.negativePrompt, .negative_prompt, .uc]) ?? "lowres, bad anatomy"
        characterPrompts = try container.decodeIfPresent([NovelAICharacterPrompt].self, forKey: .characterPrompts) ??
            (try container.decodeIfPresent([NovelAICharacterPrompt].self, forKey: .characters) ??
                (try container.decodeIfPresent([NovelAICharacterPrompt].self, forKey: .character_prompts) ?? []))
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelDescription, forKey: .modelDescription)
        try container.encode(basePrompt, forKey: .basePrompt)
        try container.encode(fixedSnippets, forKey: .fixedSnippets)
        try container.encode(randomSnippets, forKey: .randomSnippets)
        try container.encode(negativePrompt, forKey: .negativePrompt)
        try container.encode(characterPrompts, forKey: .characterPrompts)
        try container.encode(vibeTransferImages, forKey: .vibeTransferImages)
        try container.encodeIfPresent(imageToImageImageData, forKey: .imageToImageImageData)
        try container.encode(imageToImageStrength, forKey: .imageToImageStrength)
        try container.encode(imageToImageNoise, forKey: .imageToImageNoise)
        try container.encode(preciseReferenceImages, forKey: .preciseReferenceImages)
        try container.encode(sizePreset, forKey: .sizePreset)
        try container.encode(customWidth, forKey: .customWidth)
        try container.encode(customHeight, forKey: .customHeight)
        try container.encode(imageSettings, forKey: .imageSettings)
        try container.encode(loopCount, forKey: .loopCount)
        try container.encode(metadataDraft, forKey: .metadataDraft)
    }

    enum CodingKeys: String, CodingKey {
        case modelDescription
        case basePrompt, prompt, promptTemplate, prompt_template
        case fixedSnippets, randomSnippets
        case negativePrompt, negative_prompt, uc
        case characterPrompts, characters, character_prompts
        case vibeTransferImages
        case imageToImageImageData, imageToImageStrength, imageToImageNoise
        case preciseReferenceImages
        case sizePreset, customWidth, customHeight
        case imageSettings
        case loopCount
        case metadataDraft
    }
}

struct AppDefaultsSnapshot: Codable, Hashable {
    var userProfile = UserProfile()
    var apiSettings = APISettings()
    var roleCards: [RoleCard] = []
    var activeRoleCardId: String = ""
    var assistantCards: [AssistantCard] = [.characterCardCreationAssistant]
    var activeAssistantMode: String = ""
    var characterCardCreationAssistantPrompt: String = AssistantCard.defaultPrompt
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
        assistantCards = state.assistantCards
        activeAssistantMode = state.activeAssistantMode
        characterCardCreationAssistantPrompt = state.characterCardCreationAssistantPrompt
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
        characterCardCreationAssistantPrompt = try container.decodeIfPresent(String.self, forKey: .characterCardCreationAssistantPrompt) ?? AssistantCard.defaultPrompt
        assistantCards = AssistantCard.normalizedCards(
            try container.decodeIfPresent([AssistantCard].self, forKey: .assistantCards) ?? [],
            defaultPrompt: characterCardCreationAssistantPrompt
        )
        if let defaultAssistantPrompt = assistantCards.first(where: \.isDefault)?.prompt,
           !defaultAssistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            characterCardCreationAssistantPrompt = defaultAssistantPrompt
        }
        activeAssistantMode = AssistantCard.normalizedMode(
            try container.decodeIfPresent(String.self, forKey: .activeAssistantMode),
            cards: assistantCards
        )
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
    var assistantCards: [AssistantCard] = [.characterCardCreationAssistant]
    var activeAssistantMode: String = ""
    var characterCardCreationAssistantPrompt: String = AssistantCard.defaultPrompt
    var promptModes: [PromptModeConfig] = AppState.defaultPromptModes()
    var conversation: [ConversationMessage] = []
    var savedSessions: [SavedSession] = []
    var aiLogs: [AILogEntry] = []
    var timeTracking = TimeTrackingConfig()
    var novelAIAlbum: [NovelAIAlbumItem] = []
    var novelAIStudioSettings = NovelAIStudioSettings()
    var uiLanguage: UILanguageMode = .traditional
    var localDefaults: AppDefaultsSnapshot?
    var updatedAt: Date = Date()

    var activeRoleCard: RoleCard? {
        roleCards.first { $0.id == activeRoleCardId }
    }

    var activeAssistantCard: AssistantCard? {
        AssistantCard.card(for: activeAssistantMode, cards: assistantCards)
    }

    func promptModeIndex(for roleCard: RoleCard) -> Int? {
        let promptModeID = roleCard.promptModeId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !promptModeID.isEmpty,
           let explicitIndex = promptModes.indices.first(where: { promptModes[$0].id == promptModeID }),
           promptMode(promptModes[explicitIndex], isCompatibleWith: roleCard) {
            return explicitIndex
        }

        let roleMode = roleCard.mode.rawValue
        if let roleModeIndex = promptModes.indices.first(where: {
            promptModes[$0].mode == roleMode || promptModes[$0].id == roleMode
        }) {
            return roleModeIndex
        }

        if !promptModeID.isEmpty,
           let explicitIndex = promptModes.indices.first(where: { promptModes[$0].id == promptModeID }) {
            return explicitIndex
        }

        return promptModes.indices.first { promptModes[$0].id == RoleCardMode.multi.rawValue }
    }

    func promptMode(for roleCard: RoleCard) -> PromptModeConfig? {
        guard let index = promptModeIndex(for: roleCard) else { return nil }
        return promptModes[index]
    }

    private func promptMode(_ promptMode: PromptModeConfig, isCompatibleWith roleCard: RoleCard) -> Bool {
        let roleMode = roleCard.mode.rawValue
        let promptModeID = promptMode.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptModeKind = promptMode.mode.trimmingCharacters(in: .whitespacesAndNewlines)
        if promptModeID == roleMode || promptModeKind == roleMode {
            return true
        }
        let builtInModes: Set<String> = [
            RoleCardMode.single.rawValue,
            RoleCardMode.multi.rawValue,
            RoleCardMode.noRole.rawValue
        ]
        return !builtInModes.contains(promptModeID) && !builtInModes.contains(promptModeKind)
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
        characterCardCreationAssistantPrompt = try container.decodeIfPresent(String.self, forKey: .characterCardCreationAssistantPrompt) ??
            (try container.decodeIfPresent(String.self, forKey: .characterCardCreationAssistantPromptLegacy) ?? AssistantCard.defaultPrompt)
        assistantCards = AssistantCard.normalizedCards(
            try container.decodeIfPresent([AssistantCard].self, forKey: .assistantCards) ?? [],
            defaultPrompt: characterCardCreationAssistantPrompt
        )
        if let defaultAssistantPrompt = assistantCards.first(where: \.isDefault)?.prompt,
           !defaultAssistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            characterCardCreationAssistantPrompt = defaultAssistantPrompt
        }
        activeAssistantMode = AssistantCard.normalizedMode(
            try container.decodeIfPresent(String.self, forKey: .activeAssistantMode),
            cards: assistantCards
        )
        promptModes = try container.decodeIfPresent([PromptModeConfig].self, forKey: .promptModes) ?? AppState.defaultPromptModes()
        conversation = try container.decodeIfPresent([ConversationMessage].self, forKey: .conversation) ?? []
        savedSessions = try container.decodeIfPresent([SavedSession].self, forKey: .savedSessions) ?? []
        aiLogs = try container.decodeIfPresent([AILogEntry].self, forKey: .aiLogs) ?? []
        timeTracking = try container.decodeIfPresent(TimeTrackingConfig.self, forKey: .timeTracking) ?? TimeTrackingConfig()
        novelAIAlbum = try container.decodeIfPresent([NovelAIAlbumItem].self, forKey: .novelAIAlbum) ?? []
        novelAIStudioSettings = try container.decodeIfPresent(NovelAIStudioSettings.self, forKey: .novelAIStudioSettings) ?? NovelAIStudioSettings()
        uiLanguage = try container.decodeIfPresent(UILanguageMode.self, forKey: .uiLanguage) ?? .traditional
        localDefaults = try container.decodeIfPresent(AppDefaultsSnapshot.self, forKey: .localDefaults)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        if !activeAssistantMode.isEmpty {
            activeRoleCardId = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userProfile, forKey: .userProfile)
        try container.encode(apiSettings, forKey: .apiSettings)
        try container.encode(roleCards, forKey: .roleCards)
        try container.encode(activeRoleCardId, forKey: .activeRoleCardId)
        try container.encode(assistantCards, forKey: .assistantCards)
        try container.encode(activeAssistantMode, forKey: .activeAssistantMode)
        try container.encode(characterCardCreationAssistantPrompt, forKey: .characterCardCreationAssistantPrompt)
        try container.encode(promptModes, forKey: .promptModes)
        try container.encode(conversation, forKey: .conversation)
        try container.encode(savedSessions, forKey: .savedSessions)
        try container.encode(aiLogs, forKey: .aiLogs)
        try container.encode(timeTracking, forKey: .timeTracking)
        try container.encode(novelAIAlbum, forKey: .novelAIAlbum)
        try container.encode(novelAIStudioSettings, forKey: .novelAIStudioSettings)
        try container.encode(uiLanguage, forKey: .uiLanguage)
        try container.encodeIfPresent(localDefaults, forKey: .localDefaults)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case userProfile, apiSettings, roleCards, activeRoleCardId, assistantCards, activeAssistantMode
        case characterCardCreationAssistantPrompt
        case characterCardCreationAssistantPromptLegacy = "assistantPrompt"
        case promptModes, conversation, savedSessions, aiLogs, timeTracking
        case novelAIAlbum, novelAIStudioSettings, uiLanguage, localDefaults, updatedAt
    }
}

private extension String {
    func prefixString(_ maxLength: Int) -> String {
        String(prefix(maxLength))
    }
}

private extension KeyedDecodingContainer {
    func decodeFirstString(forKeys keys: [Key]) throws -> String {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return ""
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

private extension KeyedDecodingContainer {
    func decodeStringFromPossibleKeys(_ keys: [Key]) throws -> String? {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key) {
                return value
            }
            if let values = try decodeIfPresent([String].self, forKey: key) {
                return values.joined(separator: "\n")
            }
            if let intValue = try decodeIfPresent(Int.self, forKey: key) {
                return String(intValue)
            }
            if let doubleValue = try decodeIfPresent(Double.self, forKey: key) {
                return String(doubleValue)
            }
        }
        return nil
    }

    func decodeStringArrayFromPossibleKeys(_ keys: [Key]) throws -> [String]? {
        for key in keys {
            if let values = try decodeIfPresent([String].self, forKey: key) {
                return values
            }
            if let value = try decodeIfPresent(String.self, forKey: key) {
                return value
                    .split(whereSeparator: { "\n,，、;；|/／".contains($0) })
                    .map(String.init)
            }
        }
        return nil
    }

    func decodeIntFromPossibleKeys(_ keys: [Key]) throws -> Int? {
        for key in keys {
            if let value = try decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try decodeIfPresent(Double.self, forKey: key) {
                return Int(value)
            }
            if let value = try decodeIfPresent(String.self, forKey: key),
               let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return intValue
            }
        }
        return nil
    }

    func decodeDoubleFromPossibleKeys(_ keys: [Key]) throws -> Double? {
        for key in keys {
            if let value = try decodeIfPresent(Double.self, forKey: key) {
                return value
            }
            if let value = try decodeIfPresent(Int.self, forKey: key) {
                return Double(value)
            }
            if let value = try decodeIfPresent(String.self, forKey: key),
               let doubleValue = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return doubleValue
            }
        }
        return nil
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
