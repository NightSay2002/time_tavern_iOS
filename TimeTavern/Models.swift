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

enum CompressionTriggerActionKind: String, Codable, CaseIterable, Identifiable {
    case callAPI = "call_api"
    case copyUserInput = "copy_user_input"

    var id: String { rawValue }
}

struct UserProfile: Codable, Hashable {
    var userName: String = "user"
    var extraPrompt: String = ""
}

struct APISettings: Codable, Hashable {
    var deepSeekBaseURL: String = "https://api.deepseek.com/v1"
    var deepSeekModel: String = "deepseek-reasoner"
    var maxTokens: Int = 32000
    var temperature: Double = 0.5
    var naiImageBaseURL: String = "https://image.novelai.net"
    var naiPrimaryBaseURL: String = "https://api.novelai.net"
}

struct CustomSection: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var content: String = ""
    var enabled: Bool = true
}

struct OpeningDialogue: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = "開場"
    var content: String = ""
}

struct LorebookEntry: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String = ""
    var keywords: [String] = []
    var content: String = ""
    var enabled: Bool = true
    var insertedTurnNumbers: [Int] = []
}

struct RoleCard: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var mode: RoleCardMode = .multi
    var promptModeId: String = "multi"
    var coverImageData: Data?
    var coverImageDataURL: String = ""
    var customSections: [CustomSection] = []
    var openingDialogues: [OpeningDialogue] = [OpeningDialogue()]
    var activeOpeningDialogueId: String = ""
    var lorebooks: [LorebookEntry] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var activeOpeningDialogue: OpeningDialogue? {
        openingDialogues.first { $0.id == activeOpeningDialogueId } ?? openingDialogues.first
    }
}

struct CompressionModel: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var addRules: String = ""
    var deleteRules: String = ""
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
}

struct CompressionAppendTerm: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var playerSlot: String = "userx"
    var content: String = ""
    var enabled: Bool = true
}

struct CompressionProfile: Codable, Identifiable, Hashable {
    var id: String = "standard"
    var name: String = "標準壓縮模型"
    var enabled: Bool = true
    var mainRules: String = ""
    var models: [CompressionModel] = []
    var triggerActions: [CompressionTriggerAction] = [CompressionTriggerAction()]
    var appendTerms: [CompressionAppendTerm] = []
    var summary: String = ""
    var compressedThroughTurnNumber: Int = 0
    var updatedAt: Date?
}

struct PromptModeConfig: Codable, Identifiable, Hashable {
    var id: String = "multi"
    var name: String = "多角色"
    var mode: String = "multi"
    var dialogueContextRounds: Int = 15
    var mainRules: String = ""
    var outputRules: String = ""
    var reasonerHistory: String = ""
    var compressionProfiles: [CompressionProfile] = [CompressionProfile()]
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
