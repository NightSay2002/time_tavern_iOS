import Foundation
import Compression
import Security
import SwiftData

struct ChatAPIMessage: Codable, Hashable {
    var role: String
    var content: String
}

struct ChatCompletionResult: Hashable {
    var content: String
    var reasoningContent: String
    var model: String
    var usage: AIUsage?
}

struct ChatStreamDelta: Hashable, Sendable {
    enum Kind: String, Sendable {
        case reasoning
        case content
    }

    var kind: Kind
    var text: String
}

struct AIUsage: Codable, Hashable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    var promptCacheHitTokens: Int?
    var promptCacheMissTokens: Int?

    init(
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        promptCacheHitTokens: Int? = nil,
        promptCacheMissTokens: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.promptCacheHitTokens = promptCacheHitTokens
        self.promptCacheMissTokens = promptCacheMissTokens
    }

    var formattedSummary: String {
        let cacheHit = promptCacheHitTokens
        let cacheMiss = promptCacheMissTokens
        let cacheTotal = (cacheHit ?? 0) + (cacheMiss ?? 0)
        let cacheRate = cacheTotal > 0 && cacheHit != nil ? "\(Int((Double(cacheHit ?? 0) / Double(cacheTotal) * 100).rounded()))%" : ""
        return [
            promptTokens.map { "輸入 \($0)" },
            completionTokens.map { "輸出 \($0)" },
            totalTokens.map { "總計 \($0)" },
            cacheHit.map { "Cache Hit \($0)" },
            cacheMiss.map { "Cache Miss \($0)" },
            cacheRate.isEmpty ? nil : "命中率 \(cacheRate)"
        ].compactMap { $0 }.joined(separator: " / ")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try container.decodeIfPresent(Int.self, forKey: .promptTokens) ??
            container.decodeIfPresent(Int.self, forKey: .promptTokensSnake)
        completionTokens = try container.decodeIfPresent(Int.self, forKey: .completionTokens) ??
            container.decodeIfPresent(Int.self, forKey: .completionTokensSnake)
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ??
            container.decodeIfPresent(Int.self, forKey: .totalTokensSnake)
        let details = try container.decodeIfPresent(PromptTokensDetails.self, forKey: .promptTokensDetails)
        promptCacheHitTokens = try container.decodeIfPresent(Int.self, forKey: .promptCacheHitTokens) ??
            container.decodeIfPresent(Int.self, forKey: .promptCacheHitTokensSnake) ??
            details?.cachedTokens ??
            container.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ??
            container.decodeIfPresent(Int.self, forKey: .cacheReadTokens)
        promptCacheMissTokens = try container.decodeIfPresent(Int.self, forKey: .promptCacheMissTokens) ??
            container.decodeIfPresent(Int.self, forKey: .promptCacheMissTokensSnake)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(promptTokens, forKey: .promptTokens)
        try container.encodeIfPresent(completionTokens, forKey: .completionTokens)
        try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
        try container.encodeIfPresent(promptCacheHitTokens, forKey: .promptCacheHitTokens)
        try container.encodeIfPresent(promptCacheMissTokens, forKey: .promptCacheMissTokens)
    }

    private enum CodingKeys: String, CodingKey {
        case promptTokens
        case completionTokens
        case totalTokens
        case promptCacheHitTokens
        case promptCacheMissTokens
        case promptTokensSnake = "prompt_tokens"
        case completionTokensSnake = "completion_tokens"
        case totalTokensSnake = "total_tokens"
        case promptCacheHitTokensSnake = "prompt_cache_hit_tokens"
        case promptCacheMissTokensSnake = "prompt_cache_miss_tokens"
        case promptTokensDetails = "prompt_tokens_details"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheReadTokens = "cache_read_tokens"
    }

    private struct PromptTokensDetails: Decodable, Hashable {
        var cachedTokens: Int?

        enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }
}

struct NovelAIMetadataImportResult: Hashable {
    var settings: NovelAIStudioSettings
    var fallbackMessage: String?
}

struct NovelAIPromptExpansion: Codable, Hashable {
    var name: String = ""
    var placeholder: String = ""
    var selected: [String] = []
    var weightedSelected: [String] = []
    var result: String = ""
}

struct NovelAIPromptMetadata: Codable, Hashable {
    var promptTemplate: String = ""
    var finalPrompt: String = ""
    var snippets: [NovelAIPromptSnippet] = []
    var expansions: [NovelAIPromptExpansion] = []
}

struct NovelAIPromptResolution: Hashable {
    var promptTemplate: String = ""
    var finalPrompt: String = ""
    var fixedPrompt = NovelAIPromptMetadata()
    var randomPrompt = NovelAIPromptMetadata()
}

struct DeepSeekKeySet: Hashable {
    var primaryKey: String = ""
    var processingKeys: [String] = []

    var normalizedPrimaryKey: String {
        primaryKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedProcessingKeys: [String] {
        Self.normalizedProcessingKeys(processingKeys)
    }

    var allKeys: [String] {
        var seen = Set<String>()
        return ([normalizedPrimaryKey] + normalizedProcessingKeys)
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    var primaryOrFirstKey: String {
        normalizedPrimaryKey.isEmpty ? allKeys.first ?? "" : normalizedPrimaryKey
    }

    func chatKey(cursor: Int) -> String {
        let keys = allKeys
        guard !keys.isEmpty else { return "" }
        return keys[max(0, cursor) % keys.count]
    }

    func contextCompressionKey(profileIndex: Int = 0) -> String {
        let keys = normalizedProcessingKeys
        guard !keys.isEmpty else { return primaryOrFirstKey }
        return keys[min(max(0, profileIndex), keys.count - 1)]
    }

    static func normalizedProcessingKeys(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    static func decodeProcessingKeys(_ payload: String) -> [String] {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let data = trimmed.data(using: .utf8),
           let keys = try? JSONDecoder().decode([String].self, from: data) {
            return normalizedProcessingKeys(keys)
        }
        return normalizedProcessingKeys(trimmed.components(separatedBy: .newlines))
    }

    static func encodeProcessingKeys(_ keys: [String]) -> String {
        let normalized = normalizedProcessingKeys(keys)
        guard let data = try? JSONEncoder().encode(normalized) else {
            return normalized.joined(separator: "\n")
        }
        return String(data: data, encoding: .utf8) ?? normalized.joined(separator: "\n")
    }
}

final class SecretStore {
    enum Key: String {
        case deepSeekAPIKey
        case deepSeekProcessingAPIKeys
        case novelAIAPIKey
    }

    private let service = "com.wingfungwong.TimeTavern.secrets"

    func read(_ key: Key) throws -> String {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return "" }
        guard let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func save(_ value: String, for key: Key) throws {
        try delete(key)
        guard !value.isEmpty else { return }
        var query = baseQuery(key)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TimeTavernError.network("Keychain 保存失敗：\(status)")
        }
    }

    func delete(_ key: Key) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TimeTavernError.network("Keychain 刪除失敗：\(status)")
        }
    }

    private func baseQuery(_ key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}

@MainActor
final class AppDatabase {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(context: ModelContext) {
        self.context = context
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadState() -> AppState {
        let descriptor = FetchDescriptor<AppSnapshot>(
            predicate: #Predicate { $0.id == "main" }
        )
        guard
            let snapshot = try? context.fetch(descriptor).first,
            let state = try? decoder.decode(AppState.self, from: snapshot.payload)
        else {
            return AppState()
        }
        return state
    }

    func saveState(_ state: AppState) throws {
        let payload = try encoder.encode(state)
        let descriptor = FetchDescriptor<AppSnapshot>(
            predicate: #Predicate { $0.id == "main" }
        )
        if let snapshot = try context.fetch(descriptor).first {
            snapshot.payload = payload
            snapshot.updatedAt = Date()
        } else {
            context.insert(AppSnapshot(payload: payload))
        }
        try context.save()
    }
}

final class DeepSeekClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func testConnection(apiKey: String, settings: APISettings) async throws -> String {
        let messages = [ChatAPIMessage(role: "user", content: "Connection test. Reply with OK.")]
        let result = try await completion(apiKey: apiKey, settings: settings, messages: messages, stream: false)
        return result.content.isEmpty ? "連接成功。" : result.content
    }

    func streamCompletion(
        apiKey: String,
        settings: APISettings,
        messages: [ChatAPIMessage],
        onDelta: @escaping @Sendable (ChatStreamDelta) -> Void
    ) async throws -> ChatCompletionResult {
        try await completion(apiKey: apiKey, settings: settings, messages: messages, stream: true, onDelta: onDelta)
    }

    func complete(
        apiKey: String,
        settings: APISettings,
        messages: [ChatAPIMessage]
    ) async throws -> ChatCompletionResult {
        try await completion(apiKey: apiKey, settings: settings, messages: messages, stream: false)
    }

    private func completion(
        apiKey: String,
        settings: APISettings,
        messages: [ChatAPIMessage],
        stream: Bool,
        onDelta: (@Sendable (ChatStreamDelta) -> Void)? = nil
    ) async throws -> ChatCompletionResult {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TimeTavernError.missingDeepSeekKey
        }
        let url = URL(string: settings.deepSeekBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatRequest(
            model: settings.deepSeekModel,
            messages: messages,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens,
            stream: stream,
            streamOptions: stream ? ChatStreamOptions(includeUsage: true) : nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        if stream {
            let (bytes, response) = try await session.bytes(for: request)
            try validateHTTP(response)
            var content = ""
            var reasoning = ""
            var usage: AIUsage?
            for try await rawLine in bytes.lines {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8) else { continue }
                guard let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) else { continue }
                if let chunkUsage = chunk.usage {
                    usage = chunkUsage
                }
                if let delta = chunk.choices.first?.delta.reasoningContent, !delta.isEmpty {
                    reasoning += delta
                    onDelta?(ChatStreamDelta(kind: .reasoning, text: delta))
                }
                if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
                    content += delta
                    onDelta?(ChatStreamDelta(kind: .content, text: delta))
                }
            }
            return ChatCompletionResult(content: content, reasoningContent: reasoning, model: settings.deepSeekModel, usage: usage)
        } else {
            let (data, response) = try await session.data(for: request)
            try validateHTTP(response, data: data)
            let payload = try JSONDecoder().decode(ChatResponse.self, from: data)
            let message = payload.choices.first?.message
            return ChatCompletionResult(
                content: message?.content ?? "",
                reasoningContent: message?.reasoningContent ?? "",
                model: settings.deepSeekModel,
                usage: payload.usage
            )
        }
    }

    private func validateHTTP(_ response: URLResponse, data: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw TimeTavernError.network("HTTP \(http.statusCode) \(text)")
        }
    }
}

private struct ChatRequest: Encodable {
    var model: String
    var messages: [ChatAPIMessage]
    var temperature: Double
    var maxTokens: Int
    var stream: Bool
    var streamOptions: ChatStreamOptions?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
        case streamOptions = "stream_options"
    }
}

private struct ChatStreamOptions: Encodable {
    var includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        var message: Message
    }
    struct Message: Decodable {
        var content: String?
        var reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }
    var choices: [Choice]
    var usage: AIUsage?
}

private struct ChatStreamChunk: Decodable {
    struct Choice: Decodable {
        var delta: Delta
    }
    struct Delta: Decodable {
        var content: String?
        var reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }
    var choices: [Choice]
    var usage: AIUsage?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        usage = try container.decodeIfPresent(AIUsage.self, forKey: .usage)
    }

    enum CodingKeys: String, CodingKey {
        case choices, usage
    }
}

final class NovelAIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func status(apiKey: String, settings: APISettings) async throws -> String {
        guard !apiKey.isEmpty else { throw TimeTavernError.missingNovelAIKey }
        let url = URL(string: settings.naiPrimaryBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/user/subscription")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data)
        return String(data: data, encoding: .utf8) ?? "NovelAI 狀態讀取成功。"
    }

    func generateImage(
        apiKey: String,
        settings: APISettings,
        prompt: String,
        negativePrompt: String,
        model: String,
        width: Int,
        height: Int,
        steps: Int,
        scale: Double
    ) async throws -> [NovelAIAlbumItem] {
        var studioSettings = NovelAIStudioSettings()
        studioSettings.basePrompt = prompt
        studioSettings.negativePrompt = negativePrompt
        studioSettings.imageSettings.model = NovelAIModelOption.knownIDOrDefault(model)
        studioSettings.imageSettings.width = width
        studioSettings.imageSettings.height = height
        studioSettings.imageSettings.steps = steps
        studioSettings.imageSettings.scale = scale
        return try await generateImages(apiKey: apiKey, settings: settings, studioSettings: studioSettings)
    }

    func generateImages(
        apiKey: String,
        settings: APISettings,
        studioSettings: NovelAIStudioSettings,
        requestCount: Int = 1
    ) async throws -> [NovelAIAlbumItem] {
        guard !apiKey.isEmpty else { throw TimeTavernError.missingNovelAIKey }
        let url = URL(string: settings.naiImageBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/ai/generate-image")!
        let loops = max(1, min(requestCount, 9999))
        var results: [NovelAIAlbumItem] = []
        for _ in 0..<loops {
            let resolution = try Self.resolvePrompt(from: studioSettings)
            let prompt = resolution.finalPrompt
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 600
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Self.correlationID(), forHTTPHeaderField: "x-correlation-id")
            let payload = Self.buildImageGenerationRequest(studioSettings: studioSettings, promptResolution: resolution)
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await session.data(for: request)
            try validateHTTP(response, data: data)
            results.append(contentsOf: try Self.extractImages(
                fromImageResponseData: data,
                prompt: prompt,
                negativePrompt: studioSettings.negativePrompt,
                model: payload.model
            ))
        }
        return results
    }

    static func estimatedAnlas(for settings: NovelAIStudioSettings) -> Int {
        let normalMegapixels = Double(832 * 1216) / Double(1024 * 1024)
        let width = max(64, settings.imageSettings.width)
        let height = max(64, settings.imageSettings.height)
        let megapixels = max(0.05, Double(width * height) / Double(1024 * 1024))
        let stepFactor = max(0.15, Double(max(1, settings.imageSettings.steps)) / 28)
        let baseImageFactor = settings.imageToImageImageData == nil ? 1.0 : 1.15
        let sampleCount = max(1, settings.imageSettings.samples)
        let vibeCount = settings.vibeTransferImages.filter { $0.enabled && $0.imageData != nil }.count
        let preciseCount = settings.preciseReferenceImages.filter { $0.enabled && $0.imageData != nil }.count
        let extraVibe = vibeCount > 4 ? Double((vibeCount - 4) * 2) : 0
        let extraPrecise = Double(preciseCount * 5)
        let estimate = (20 * (megapixels / normalMegapixels) * stepFactor * baseImageFactor + extraVibe + extraPrecise) * Double(sampleCount)
        return max(1, Int(ceil(estimate)))
    }

    static func loopRequestLimit(from loopCount: Int) -> Int? {
        loopCount == 0 ? nil : max(1, min(loopCount, 9999))
    }

    static func resolvedPrompt(from settings: NovelAIStudioSettings, randomIndex: ((Int) -> Int)? = nil) -> String {
        (try? resolvePrompt(from: settings, randomIndex: randomIndex).finalPrompt) ?? ""
    }

    static func resolvePrompt(from settings: NovelAIStudioSettings, randomIndex: ((Int) -> Int)? = nil) throws -> NovelAIPromptResolution {
        let template = settings.basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let fixedSnippets = settings.fixedSnippets
            .filter(\.enabled)
            .map(normalizedFixedSnippet)
            .filter { !$0.name.isEmpty || !$0.content.isEmpty }
        let randomSnippets = settings.randomSnippets
            .filter(\.enabled)
            .map(normalizedRandomSnippet)
            .filter { !$0.name.isEmpty || !$0.content.isEmpty }
        let fixedMap = Dictionary(grouping: fixedSnippets, by: \.name).compactMapValues(\.first)
        let randomMap = Dictionary(grouping: randomSnippets, by: \.name).compactMapValues(\.first)
        var fixedExpansions: [NovelAIPromptExpansion] = []
        var randomExpansions: [NovelAIPromptExpansion] = []
        var expanded = template

        expanded = try replacePromptPlaceholders(in: expanded, pattern: #"\|\|\s*([^|]+?)\s*\|\|"#) { placeholder, rawName in
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let fixed = fixedMap[name]
            let random = randomMap[name]
            if fixed != nil, random != nil {
                throw TimeTavernError.network("Prompt 片段名字重複：\(name)，固定與隨機片段不能同名。")
            }
            if let fixed {
                let result = cleanExpandedPrompt(fixed.content)
                fixedExpansions.append(NovelAIPromptExpansion(name: name, placeholder: placeholder, result: result))
                return result
            }
            if let random {
                let expansion = expandRandomPromptSnippet(random, placeholder: placeholder, randomIndex: randomIndex)
                randomExpansions.append(expansion)
                return expansion.result
            }
            throw TimeTavernError.network("Prompt 找不到片段：\(name)。")
        }

        expanded = try replacePromptPlaceholders(in: expanded, pattern: #"\{\{\s*([^}]+?)\s*\}\}"#) { placeholder, rawName in
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let random = randomMap[name] else { return placeholder }
            let expansion = expandRandomPromptSnippet(random, placeholder: placeholder, randomIndex: randomIndex)
            randomExpansions.append(expansion)
            return expansion.result
        }

        let finalPrompt = cleanExpandedPrompt(expanded)
        return NovelAIPromptResolution(
            promptTemplate: template,
            finalPrompt: finalPrompt,
            fixedPrompt: NovelAIPromptMetadata(
                promptTemplate: template,
                finalPrompt: finalPrompt,
                snippets: fixedSnippets,
                expansions: fixedExpansions
            ),
            randomPrompt: NovelAIPromptMetadata(
                promptTemplate: template,
                finalPrompt: finalPrompt,
                snippets: randomSnippets,
                expansions: randomExpansions
            )
        )
    }

    static func buildImageGenerationRequest(studioSettings: NovelAIStudioSettings, prompt: String? = nil) -> NovelAIRequest {
        let resolution = (try? resolvePrompt(from: studioSettings)) ?? NovelAIPromptResolution(
            promptTemplate: studioSettings.basePrompt,
            finalPrompt: prompt ?? cleanExpandedPrompt(studioSettings.basePrompt)
        )
        return buildImageGenerationRequest(studioSettings: studioSettings, promptResolution: resolution, overridePrompt: prompt)
    }

    static func buildImageGenerationRequest(
        studioSettings: NovelAIStudioSettings,
        promptResolution: NovelAIPromptResolution,
        overridePrompt: String? = nil
    ) -> NovelAIRequest {
        let imageSettings = studioSettings.imageSettings
        let resolvedPrompt = overridePrompt ?? promptResolution.finalPrompt
        let model = NovelAIModelOption.knownIDOrDefault(imageSettings.model)
        let references = studioSettings.vibeTransferImages.filter { $0.enabled && $0.imageData != nil }
        let preciseReferences = studioSettings.preciseReferenceImages.filter { $0.enabled && $0.imageData != nil }
        let enabledCharacters = studioSettings.characterPrompts.filter { $0.enabled && (!$0.prompt.isEmpty || !$0.negativePrompt.isEmpty) }
        return NovelAIRequest(
            action: "generate",
            input: resolvedPrompt,
            model: model,
            parameters: NovelAIParameters(
                width: imageSettings.width,
                height: imageSettings.height,
                scale: imageSettings.scale,
                sampler: imageSettings.sampler,
                steps: imageSettings.steps,
                nSamples: max(1, min(imageSettings.samples, 8)),
                ucPreset: imageSettings.ucPreset,
                qualityToggle: true,
                dynamicThresholding: false,
                sm: imageSettings.varietyPlus,
                smDyn: imageSettings.varietyPlus,
                cfgRescale: imageSettings.cfgRescale,
                imageFormat: imageSettings.imageFormat,
                prompt: resolvedPrompt,
                negativePrompt: studioSettings.negativePrompt,
                noiseSchedule: imageSettings.noiseSchedule,
                seed: imageSettings.seed,
                image: studioSettings.imageToImageImageData?.base64EncodedString(),
                strength: studioSettings.imageToImageImageData == nil ? nil : studioSettings.imageToImageStrength,
                noise: studioSettings.imageToImageImageData == nil ? nil : studioSettings.imageToImageNoise,
                referenceImageMultiple: (references + preciseReferences).compactMap { $0.imageData?.base64EncodedString() },
                referenceInformationExtractedMultiple: (references + preciseReferences).map(\.noise),
                referenceStrengthMultiple: (references + preciseReferences).map(\.strength),
                v4Prompt: NovelAIV4Prompt(
                    baseCaption: resolvedPrompt,
                    characterPrompts: enabledCharacters,
                    negative: false
                ),
                v4NegativePrompt: NovelAIV4Prompt(
                    baseCaption: studioSettings.negativePrompt,
                    characterPrompts: enabledCharacters,
                    negative: true
                ),
                uc: studioSettings.negativePrompt,
                fixedPrompt: promptResolution.fixedPrompt,
                fixedPromptSnippets: studioSettings.fixedSnippets,
                randomPrompt: promptResolution.randomPrompt,
                randomPromptSnippets: studioSettings.randomSnippets
            )
        )
    }

    static func importMetadata(_ metadata: String, into settings: NovelAIStudioSettings) -> NovelAIMetadataImportResult {
        guard let data = metadata.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return NovelAIMetadataImportResult(settings: settings, fallbackMessage: nil) }
        var next = settings
        var fallbackMessage: String?
        let parameters = object["parameters"] as? [String: Any] ?? object
        if let template = object["prompt_template"] as? String ?? parameters["prompt_template"] as? String {
            next.basePrompt = template
        } else if let input = object["input"] as? String ?? object["prompt"] as? String {
            next.basePrompt = input
        }
        if let model = object["model"] as? String {
            if NovelAIModelOption.option(for: model) == nil {
                next.imageSettings.model = NovelAIModelOption.defaultID
                fallbackMessage = "Metadata 模型 \(model) 不在 iOS 選項內，已改用 \(NovelAIModelOption.title(for: NovelAIModelOption.defaultID))。"
            } else {
                next.imageSettings.model = model
            }
        }
        if let negative = parameters["negative_prompt"] as? String ?? parameters["uc"] as? String {
            next.negativePrompt = negative
        }
        if let fixed = decodePromptSnippets(parameters["fixed_prompt_snippets"] ?? object["fixed_prompt_snippets"]) {
            next.fixedSnippets = fixed
        }
        if let random = decodePromptSnippets(parameters["random_prompt_snippets"] ?? object["random_prompt_snippets"]) {
            next.randomSnippets = random
        } else if let randomPrompt = parameters["random_prompt"] as? [String: Any],
                  let snippets = decodePromptSnippets(randomPrompt["snippets"]) {
            next.randomSnippets = snippets
        }
        let positiveCharacters = characterPrompts(from: parameters["v4_prompt"] ?? object["v4_prompt"], negative: false)
        let negativeCharacters = characterPrompts(from: parameters["v4_negative_prompt"] ?? object["v4_negative_prompt"], negative: true)
        if !positiveCharacters.isEmpty || !negativeCharacters.isEmpty {
            next.characterPrompts = mergeCharacterPrompts(positive: positiveCharacters, negative: negativeCharacters)
        }
        if let width = parameters["width"] as? Int {
            next.imageSettings.width = width
        }
        if let height = parameters["height"] as? Int {
            next.imageSettings.height = height
        }
        if let steps = parameters["steps"] as? Int {
            next.imageSettings.steps = steps
        }
        if let scale = parameters["scale"] as? Double {
            next.imageSettings.scale = scale
        }
        if let sampler = parameters["sampler"] as? String {
            next.imageSettings.sampler = sampler
        }
        if let cfgRescale = parameters["cfg_rescale"] as? Double {
            next.imageSettings.cfgRescale = cfgRescale
        }
        if let seed = parameters["seed"] as? Int {
            next.imageSettings.seed = seed
        }
        return NovelAIMetadataImportResult(settings: next, fallbackMessage: fallbackMessage)
    }

    static func importMetadata(fromImageData data: Data, into settings: NovelAIStudioSettings) -> NovelAIMetadataImportResult? {
        guard let metadata = extractPngNovelAIMetadata(from: data) else { return nil }
        return importMetadata(metadata, into: settings)
    }

    static func settingsByImportingMetadata(_ metadata: String, into settings: NovelAIStudioSettings) -> NovelAIStudioSettings {
        importMetadata(metadata, into: settings).settings
    }

    private static func extractPngNovelAIMetadata(from data: Data) -> String? {
        let entries = readPngMetadataEntries(data)
        if let embedded = entries["NovelAIMetadata"] ?? entries["TimeTavernNovelAIMetadata"],
           parseJSONObject(embedded) != nil {
            return embedded
        }
        guard let comment = entries["Comment"],
              var object = parseJSONObject(comment)
        else { return nil }
        let looksNovelAI = object["signed_hash"] != nil ||
            object["request_type"] != nil ||
            object["v4_prompt"] != nil ||
            object["v4_negative_prompt"] != nil ||
            object["prompt"] != nil ||
            object["uc"] != nil ||
            object["negative_prompt"] != nil ||
            object["steps"] != nil ||
            object["sampler"] != nil ||
            String(describing: entries["Software"] ?? object["model"] ?? "").range(of: "novelai", options: [.caseInsensitive]) != nil ||
            String(describing: entries["Software"] ?? object["model"] ?? "").range(of: "nai-diffusion", options: [.caseInsensitive]) != nil
        guard looksNovelAI else { return nil }
        if object["prompt"] == nil, let description = entries["Description"] {
            object["prompt"] = description
        }
        if object["model"] == nil, let software = entries["Software"] {
            object["model"] = software
        }
        if object["negative_prompt"] == nil, let uc = object["uc"] {
            object["negative_prompt"] = uc
        }
        guard let output = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: output, encoding: .utf8)
        else { return comment }
        return text
    }

    private static func readPngMetadataEntries(_ data: Data) -> [String: String] {
        let bytes = [UInt8](data)
        let signature: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
        guard bytes.count >= signature.count,
              Array(bytes.prefix(signature.count)) == signature
        else { return [:] }
        var entries: [String: String] = [:]
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = (Int(bytes[offset]) << 24) |
                (Int(bytes[offset + 1]) << 16) |
                (Int(bytes[offset + 2]) << 8) |
                Int(bytes[offset + 3])
            let dataStart = offset + 8
            let dataEnd = dataStart + length
            guard length >= 0, dataEnd + 4 <= bytes.count else { break }
            let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            let chunk = Array(bytes[dataStart..<dataEnd])
            if let entry = type == "tEXt" ? readPngTextChunk(chunk) : (type == "iTXt" ? readPngInternationalTextChunk(chunk) : nil) {
                entries[entry.key] = entry.value
            }
            offset = dataEnd + 4
            if type == "IEND" {
                break
            }
        }
        return entries
    }

    private static func readPngTextChunk(_ bytes: [UInt8]) -> (key: String, value: String)? {
        guard let separator = bytes.firstIndex(of: 0), separator > 0 else { return nil }
        let key = String(data: Data(bytes[..<separator]), encoding: .isoLatin1) ?? ""
        let value = String(data: Data(bytes[(separator + 1)...]), encoding: .isoLatin1) ?? ""
        return key.isEmpty ? nil : (key, value)
    }

    private static func readPngInternationalTextChunk(_ bytes: [UInt8]) -> (key: String, value: String)? {
        guard let keywordEnd = bytes.firstIndex(of: 0),
              keywordEnd > 0,
              keywordEnd + 3 < bytes.count,
              bytes[keywordEnd + 1] == 0
        else { return nil }
        var cursor = keywordEnd + 3
        while cursor < bytes.count, bytes[cursor] != 0 {
            cursor += 1
        }
        cursor += 1
        while cursor < bytes.count, bytes[cursor] != 0 {
            cursor += 1
        }
        cursor += 1
        guard cursor < bytes.count else { return nil }
        let key = String(data: Data(bytes[..<keywordEnd]), encoding: .utf8) ?? ""
        let value = String(data: Data(bytes[cursor...]), encoding: .utf8) ?? ""
        return key.isEmpty ? nil : (key, value)
    }

    private static func parseJSONObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func decodePromptSnippets(_ value: Any?) -> [NovelAIPromptSnippet]? {
        guard let value else { return nil }
        if let snippets = value as? [[String: Any]],
           let data = try? JSONSerialization.data(withJSONObject: snippets),
           let decoded = try? JSONDecoder().decode([NovelAIPromptSnippet].self, from: data) {
            return decoded
        }
        if let snippets = value as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: snippets),
           let decoded = try? JSONDecoder().decode([NovelAIPromptSnippet].self, from: data) {
            return decoded
        }
        return nil
    }

    private static func characterPrompts(from value: Any?, negative: Bool) -> [NovelAICharacterPrompt] {
        guard let object = value as? [String: Any],
              let caption = object["caption"] as? [String: Any],
              let charCaptions = caption["char_captions"] as? [[String: Any]]
        else { return [] }
        return charCaptions.enumerated().compactMap { index, item in
            let text = item["char_caption"] as? String ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let center = (item["centers"] as? [[String: Any]])?.first ?? [:]
            let x = center["x"] as? Double ?? 0.5
            let y = center["y"] as? Double ?? 0.5
            if negative {
                return NovelAICharacterPrompt(name: "Character \(index + 1)", negativePrompt: text, x: x, y: y)
            }
            return NovelAICharacterPrompt(name: "Character \(index + 1)", prompt: text, x: x, y: y)
        }
    }

    private static func mergeCharacterPrompts(
        positive: [NovelAICharacterPrompt],
        negative: [NovelAICharacterPrompt]
    ) -> [NovelAICharacterPrompt] {
        let count = max(positive.count, negative.count)
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let positiveItem = index < positive.count ? positive[index] : NovelAICharacterPrompt(name: "Character \(index + 1)")
            let negativeItem = index < negative.count ? negative[index] : NovelAICharacterPrompt(name: positiveItem.name)
            return NovelAICharacterPrompt(
                name: positiveItem.name.isEmpty ? negativeItem.name : positiveItem.name,
                prompt: positiveItem.prompt,
                negativePrompt: negativeItem.negativePrompt,
                enabled: positiveItem.enabled && negativeItem.enabled,
                x: positiveItem.x,
                y: positiveItem.y
            )
        }
    }

    private static func normalizedFixedSnippet(_ snippet: NovelAIPromptSnippet) -> NovelAIPromptSnippet {
        var next = snippet
        next.name = snippet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.content = cleanExpandedPrompt(snippet.content)
        return next
    }

    private static func normalizedRandomSnippet(_ snippet: NovelAIPromptSnippet) -> NovelAIPromptSnippet {
        let items = promptItems(snippet.content, preserveLeadingSpace: true)
        var next = snippet
        next.name = snippet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.content = items.joined(separator: "\n")
        next.min = min(max(0, snippet.min), items.count)
        next.max = min(max(next.min, snippet.max), items.count)
        next.squareMax = max(0, min(12, snippet.squareMax))
        next.curlyMax = max(0, min(12, snippet.curlyMax))
        next.weightMin = max(0, min(5, snippet.weightMin))
        next.weightMax = max(next.weightMin, min(5, snippet.weightMax))
        next.weightBias = max(next.weightMin, min(next.weightMax, snippet.weightBias))
        return next
    }

    private static func replacePromptPlaceholders(
        in text: String,
        pattern: String,
        replacement: (String, String) throws -> String
    ) throws -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        var output = text
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let wholeRange = Range(match.range(at: 0), in: output),
                  let nameRange = Range(match.range(at: 1), in: output)
            else { continue }
            let placeholder = String(output[wholeRange])
            let name = String(output[nameRange])
            output.replaceSubrange(wholeRange, with: try replacement(placeholder, name))
        }
        return output
    }

    private static func expandRandomPromptSnippet(
        _ snippet: NovelAIPromptSnippet,
        placeholder: String,
        randomIndex: ((Int) -> Int)?
    ) -> NovelAIPromptExpansion {
        let items = promptItems(snippet.content, preserveLeadingSpace: true)
        let lower = min(snippet.min, snippet.max, items.count)
        let upper = min(max(snippet.min, snippet.max), items.count)
        let count = items.isEmpty ? 0 : randomIntInclusive(lower, upper, randomIndex: randomIndex)
        let selected = Array(shuffled(items, randomIndex: randomIndex).prefix(count))
        let weighted = selected
            .map { applyRandomPromptWeight($0, snippet: snippet, randomIndex: randomIndex) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let result = cleanExpandedPrompt(weighted.joined(separator: ","))
        return NovelAIPromptExpansion(
            name: snippet.name,
            placeholder: placeholder,
            selected: selected,
            weightedSelected: weighted,
            result: result
        )
    }

    private static func promptItems(_ text: String, preserveLeadingSpace: Bool = false) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { preserveLeadingSpace ? String($0).trimmingCharacters(in: .whitespacesAndNewlines.subtracting(.whitespaces)) : String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func cleanExpandedPrompt(_ prompt: String) -> String {
        prompt
            .replacingOccurrences(of: #"\r?\n+"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"[，,]\s*[，,]+"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"\s*[,，]\s*"#, with: ",", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",，").union(.whitespacesAndNewlines))
    }

    private static func shuffled<T>(_ values: [T], randomIndex: ((Int) -> Int)?) -> [T] {
        var output = values
        guard output.count > 1 else { return output }
        for index in stride(from: output.count - 1, through: 1, by: -1) {
            let swapIndex = randomIndex.map { max(0, min($0(index + 1), index)) } ?? Int.random(in: 0...index)
            output.swapAt(index, swapIndex)
        }
        return output
    }

    private static func randomIntInclusive(_ minValue: Int, _ maxValue: Int, randomIndex: ((Int) -> Int)?) -> Int {
        let low = min(minValue, maxValue)
        let high = max(minValue, maxValue)
        guard high > low else { return low }
        if let randomIndex {
            return low + max(0, min(randomIndex(high - low + 1), high - low))
        }
        return Int.random(in: low...high)
    }

    private static func splitPromptChain(_ text: String, preserveLeadingSpace: Bool = true) -> [String] {
        text.split { $0 == "," || $0 == "，" }
            .map { preserveLeadingSpace ? String($0).trimmingCharacters(in: .whitespacesAndNewlines.subtracting(.whitespaces)) : String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func applyRandomPromptWeight(
        _ text: String,
        snippet: NovelAIPromptSnippet,
        randomIndex: ((Int) -> Int)?
    ) -> String {
        splitPromptChain(text)
            .map { applyRandomPromptWeightToToken($0, snippet: snippet, randomIndex: randomIndex) }
            .joined(separator: ",")
    }

    private static func applyRandomPromptWeightToToken(
        _ text: String,
        snippet: NovelAIPromptSnippet,
        randomIndex: ((Int) -> Int)?
    ) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines.subtracting(.whitespaces))
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        var weightTypes: [String] = []
        if snippet.squareEnabled, snippet.squareMax > 0 { weightTypes.append("square") }
        if snippet.curlyEnabled, snippet.curlyMax > 0 { weightTypes.append("curly") }
        if snippet.weightEnabled, max(snippet.weightMin, snippet.weightMax) > 0 { weightTypes.append("numeric") }
        guard !weightTypes.isEmpty else { return output }
        let selectedType = weightTypes[randomIntInclusive(0, weightTypes.count - 1, randomIndex: randomIndex)]
        switch selectedType {
        case "square":
            let count = randomIntInclusive(1, snippet.squareMax, randomIndex: randomIndex)
            output = String(repeating: "[", count: count) + output + String(repeating: "]", count: count)
        case "curly":
            let count = randomIntInclusive(1, snippet.curlyMax, randomIndex: randomIndex)
            output = String(repeating: "{", count: count) + output + String(repeating: "}", count: count)
        default:
            let value = randomDouble(min: snippet.weightMin, max: snippet.weightMax, bias: snippet.weightBias)
            let protected = output.last?.isNumber == true ? "\(output) " : output
            output = "\(formatPromptWeight(value))::\(protected)::"
        }
        return output
    }

    private static func randomDouble(min minValue: Double, max maxValue: Double, bias: Double) -> Double {
        let low = min(minValue, maxValue)
        let high = max(minValue, maxValue)
        guard high > low else { return low }
        let center = max(low, min(high, bias))
        let focusedLow = max(low, center - 1)
        let focusedHigh = min(high, center + 1)
        let useFullRange = Double.random(in: 0...1) < 0.18 || focusedHigh <= focusedLow
        return Double.random(in: (useFullRange ? low : focusedLow)...(useFullRange ? high : focusedHigh))
    }

    private static func formatPromptWeight(_ value: Double) -> String {
        String(format: "%.1f", (value * 10).rounded() / 10)
    }

    static func extractImages(fromImageResponseData data: Data, prompt: String, negativePrompt: String, model: String) throws -> [NovelAIAlbumItem] {
        if let imageType = Self.detectImageType(in: data) {
            return [
                NovelAIAlbumItem(
                    fileName: "novelai-\(UUID().uuidString).\(imageType.fileExtension)",
                    mimeType: imageType.mimeType,
                    prompt: prompt,
                    negativePrompt: negativePrompt,
                    model: model,
                    imageData: data,
                    metadata: "{}"
                )
            ]
        }

        if Self.looksLikeZip(data) {
            let items = try Self.extractImagesFromZip(
                data,
                prompt: prompt,
                negativePrompt: negativePrompt,
                model: model
            )
            if !items.isEmpty {
                return items
            }
            throw TimeTavernError.network("NovelAI ZIP 沒有包含可用圖片。")
        }

        let jsonItems = Self.extractImagesFromJSON(
            data,
            prompt: prompt,
            negativePrompt: negativePrompt,
            model: model
        )
        if !jsonItems.isEmpty {
            return jsonItems
        }

        throw TimeTavernError.network("NovelAI 沒有回傳可用圖片。")
    }

    private static func detectImageType(in data: Data) -> (mimeType: String, fileExtension: String)? {
        guard data.count >= 3 else { return nil }
        if data.count >= 4, data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return ("image/png", "png")
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return ("image/jpeg", "jpg")
        }
        guard data.count >= 12 else { return nil }
        let riff = String(data: data.prefix(4), encoding: .ascii)
        let webp = String(data: data.dropFirst(8).prefix(4), encoding: .ascii)
        if riff == "RIFF", webp == "WEBP" {
            return ("image/webp", "webp")
        }
        return nil
    }

    private static func extractImagesFromZip(
        _ data: Data,
        prompt: String,
        negativePrompt: String,
        model: String
    ) throws -> [NovelAIAlbumItem] {
        try extractZipEntries(from: data).enumerated().compactMap { index, entry in
            guard let imageType = detectImageType(in: entry.data) ?? imageTypeFromFileName(entry.fileName) else {
                return nil
            }
            return NovelAIAlbumItem(
                fileName: imageFileName(entry.fileName, fallbackIndex: index, fileExtension: imageType.fileExtension),
                mimeType: imageType.mimeType,
                prompt: prompt,
                negativePrompt: negativePrompt,
                model: model,
                imageData: entry.data,
                metadata: "{}"
            )
        }
    }

    private static func extractImagesFromJSON(
        _ data: Data,
        prompt: String,
        negativePrompt: String,
        model: String
    ) -> [NovelAIAlbumItem] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var candidates: [String] = []
        collectImageStrings(from: object, into: &candidates)
        return candidates.enumerated().compactMap { index, value in
            guard let image = decodeImageString(value) else { return nil }
            return NovelAIAlbumItem(
                fileName: "novelai-\(index + 1).\(image.imageType.fileExtension)",
                mimeType: image.imageType.mimeType,
                prompt: prompt,
                negativePrompt: negativePrompt,
                model: model,
                imageData: image.data,
                metadata: "{}"
            )
        }
    }

    private static func collectImageStrings(from object: Any, into output: inout [String]) {
        guard output.count < 50 else { return }
        if let string = object as? String {
            output.append(string)
            return
        }
        if let array = object as? [Any] {
            for item in array {
                collectImageStrings(from: item, into: &output)
            }
            return
        }
        guard let dictionary = object as? [String: Any] else { return }
        for value in dictionary.values {
            collectImageStrings(from: value, into: &output)
        }
    }

    private static func decodeImageString(_ value: String) -> (data: Data, imageType: (mimeType: String, fileExtension: String))? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base64: String
        if trimmed.hasPrefix("data:image/"), let comma = trimmed.firstIndex(of: ",") {
            base64 = String(trimmed[trimmed.index(after: comma)...])
        } else {
            base64 = trimmed
        }
        guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]),
              let imageType = detectImageType(in: data) else {
            return nil
        }
        return (data, imageType)
    }

    private struct ZipEntry {
        var fileName: String
        var data: Data
    }

    private static func looksLikeZip(_ data: Data) -> Bool {
        data.count >= 4 && data.starts(with: [0x50, 0x4B, 0x03, 0x04])
    }

    private static func extractZipEntries(from data: Data) throws -> [ZipEntry] {
        guard let endOffset = findZipEndOfCentralDirectory(in: data),
              let totalEntries = data.littleEndianUInt16(at: endOffset + 10),
              let centralDirectoryOffset = data.littleEndianUInt32(at: endOffset + 16) else {
            throw TimeTavernError.network("NovelAI 回傳內容不是有效 ZIP。")
        }

        var entries: [ZipEntry] = []
        var offset = Int(centralDirectoryOffset)
        for _ in 0..<Int(totalEntries) {
            guard offset + 46 <= data.count,
                  data.littleEndianUInt32(at: offset) == 0x0201_4B50,
                  let method = data.littleEndianUInt16(at: offset + 10),
                  let compressedSizeValue = data.littleEndianUInt32(at: offset + 20),
                  let uncompressedSizeValue = data.littleEndianUInt32(at: offset + 24),
                  let fileNameLengthValue = data.littleEndianUInt16(at: offset + 28),
                  let extraLengthValue = data.littleEndianUInt16(at: offset + 30),
                  let commentLengthValue = data.littleEndianUInt16(at: offset + 32),
                  let localHeaderOffsetValue = data.littleEndianUInt32(at: offset + 42) else {
                break
            }

            let compressedSize = Int(compressedSizeValue)
            let uncompressedSize = Int(uncompressedSizeValue)
            let fileNameLength = Int(fileNameLengthValue)
            let extraLength = Int(extraLengthValue)
            let commentLength = Int(commentLengthValue)
            let nameStart = offset + 46
            guard let fileNameData = data.safeSubdata(offset: nameStart, count: fileNameLength) else {
                break
            }
            let fileName = String(data: fileNameData, encoding: .utf8) ?? ""
            let localHeaderOffset = Int(localHeaderOffsetValue)
            if let entry = try extractZipEntry(
                data: data,
                fileName: fileName,
                localHeaderOffset: localHeaderOffset,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                method: method
            ) {
                entries.append(entry)
            }
            offset += 46 + fileNameLength + extraLength + commentLength
        }
        return entries
    }

    private static func extractZipEntry(
        data: Data,
        fileName: String,
        localHeaderOffset: Int,
        compressedSize: Int,
        uncompressedSize: Int,
        method: UInt16
    ) throws -> ZipEntry? {
        guard localHeaderOffset + 30 <= data.count,
              data.littleEndianUInt32(at: localHeaderOffset) == 0x0403_4B50,
              let localNameLength = data.littleEndianUInt16(at: localHeaderOffset + 26),
              let localExtraLength = data.littleEndianUInt16(at: localHeaderOffset + 28) else {
            return nil
        }
        let dataStart = localHeaderOffset + 30 + Int(localNameLength) + Int(localExtraLength)
        guard let compressedData = data.safeSubdata(offset: dataStart, count: compressedSize) else {
            return nil
        }

        let output: Data
        switch method {
        case 0:
            output = uncompressedSize > 0 && compressedData.count > uncompressedSize
                ? compressedData.prefixData(uncompressedSize)
                : compressedData
        case 8:
            output = try inflateRawDeflate(compressedData, expectedSize: uncompressedSize)
        default:
            return nil
        }

        return ZipEntry(fileName: fileName, data: output)
    }

    private static func findZipEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let lowerBound = max(0, data.count - 66_000)
        var offset = data.count - 22
        while offset >= lowerBound {
            if data.littleEndianUInt32(at: offset) == 0x0605_4B50 {
                return offset
            }
            offset -= 1
        }
        return nil
    }

    private static func inflateRawDeflate(_ data: Data, expectedSize: Int) throws -> Data {
        var outputSize = max(expectedSize, data.count * 4, 1024)
        for _ in 0..<8 {
            var output = [UInt8](repeating: 0, count: outputSize)
            let decodedSize = data.withUnsafeBytes { sourceRawBuffer -> Int in
                guard let source = sourceRawBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    &output,
                    output.count,
                    source,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
            if decodedSize > 0 {
                return Data(output.prefix(expectedSize > 0 ? min(decodedSize, expectedSize) : decodedSize))
            }
            outputSize *= 2
        }
        throw TimeTavernError.network("NovelAI ZIP 圖片解壓失敗。")
    }

    private static func imageTypeFromFileName(_ fileName: String) -> (mimeType: String, fileExtension: String)? {
        switch fileName.split(separator: ".").last?.lowercased() {
        case "png": return ("image/png", "png")
        case "jpg", "jpeg": return ("image/jpeg", "jpg")
        case "webp": return ("image/webp", "webp")
        default: return nil
        }
    }

    private static func imageFileName(_ fileName: String, fallbackIndex: Int, fileExtension: String) -> String {
        let lastComponent = fileName.split(separator: "/").last.map(String.init) ?? ""
        let trimmed = lastComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "novelai-\(fallbackIndex + 1).\(fileExtension)" : trimmed
    }

    private func validateHTTP(_ response: URLResponse, data: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw TimeTavernError.network("NovelAI HTTP \(http.statusCode) \(text)")
        }
    }

    private static func correlationID() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<6).compactMap { _ in alphabet.randomElement() })
    }
}

struct NovelAIRequest: Encodable {
    var action: String
    var input: String
    var model: String
    var parameters: NovelAIParameters
}

struct NovelAIV4Prompt: Encodable, Hashable {
    var caption: NovelAIV4Caption
    var useCoords: Bool
    var useOrder: Bool
    var legacyUC: Bool

    init(baseCaption: String, characterPrompts: [NovelAICharacterPrompt], negative: Bool) {
        caption = NovelAIV4Caption(
            baseCaption: baseCaption,
            charCaptions: characterPrompts.compactMap { character in
                let text = negative ? character.negativePrompt : character.prompt
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return NovelAIV4CharacterCaption(
                    charCaption: text,
                    centers: [NovelAICenter(x: character.x, y: character.y)]
                )
            }
        )
        useCoords = !negative
        useOrder = !negative
        legacyUC = false
    }

    enum CodingKeys: String, CodingKey {
        case caption
        case useCoords = "use_coords"
        case useOrder = "use_order"
        case legacyUC = "legacy_uc"
    }
}

struct NovelAIV4Caption: Encodable, Hashable {
    var baseCaption: String
    var charCaptions: [NovelAIV4CharacterCaption]

    enum CodingKeys: String, CodingKey {
        case baseCaption = "base_caption"
        case charCaptions = "char_captions"
    }
}

struct NovelAIV4CharacterCaption: Encodable, Hashable {
    var charCaption: String
    var centers: [NovelAICenter]

    enum CodingKeys: String, CodingKey {
        case charCaption = "char_caption"
        case centers
    }
}

struct NovelAICenter: Encodable, Hashable {
    var x: Double
    var y: Double
}

struct NovelAIParameters: Encodable {
    var width: Int
    var height: Int
    var scale: Double
    var sampler: String
    var steps: Int
    var nSamples: Int
    var ucPreset: Int
    var qualityToggle: Bool
    var dynamicThresholding: Bool
    var sm: Bool
    var smDyn: Bool
    var cfgRescale: Double
    var imageFormat: String
    var prompt: String
    var negativePrompt: String
    var noiseSchedule: String
    var seed: Int?
    var image: String?
    var strength: Double?
    var noise: Double?
    var referenceImageMultiple: [String]
    var referenceInformationExtractedMultiple: [Double]
    var referenceStrengthMultiple: [Double]
    var v4Prompt: NovelAIV4Prompt
    var v4NegativePrompt: NovelAIV4Prompt
    var uc: String
    var fixedPrompt: NovelAIPromptMetadata
    var fixedPromptSnippets: [NovelAIPromptSnippet]
    var randomPrompt: NovelAIPromptMetadata
    var randomPromptSnippets: [NovelAIPromptSnippet]

    enum CodingKeys: String, CodingKey {
        case width, height, scale, sampler, steps, prompt, seed, image, strength, noise, uc
        case nSamples = "n_samples"
        case ucPreset = "ucPreset"
        case qualityToggle = "qualityToggle"
        case dynamicThresholding = "dynamic_thresholding"
        case sm
        case smDyn = "sm_dyn"
        case cfgRescale = "cfg_rescale"
        case imageFormat = "image_format"
        case negativePrompt = "negative_prompt"
        case noiseSchedule = "noise_schedule"
        case referenceImageMultiple = "reference_image_multiple"
        case referenceInformationExtractedMultiple = "reference_information_extracted_multiple"
        case referenceStrengthMultiple = "reference_strength_multiple"
        case v4Prompt = "v4_prompt"
        case v4NegativePrompt = "v4_negative_prompt"
        case fixedPrompt = "fixed_prompt"
        case fixedPromptSnippets = "fixed_prompt_snippets"
        case randomPrompt = "random_prompt"
        case randomPromptSnippets = "random_prompt_snippets"
    }
}

private extension Data {
    func littleEndianUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 1 < count else { return nil }
        let start = index(startIndex, offsetBy: offset)
        let next = index(after: start)
        return UInt16(self[start]) | (UInt16(self[next]) << 8)
    }

    func littleEndianUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 3 < count else { return nil }
        let start = index(startIndex, offsetBy: offset)
        let byte1 = self[start]
        let byte2 = self[index(start, offsetBy: 1)]
        let byte3 = self[index(start, offsetBy: 2)]
        let byte4 = self[index(start, offsetBy: 3)]
        return UInt32(byte1) |
            (UInt32(byte2) << 8) |
            (UInt32(byte3) << 16) |
            (UInt32(byte4) << 24)
    }

    func safeSubdata(offset: Int, count requestedCount: Int) -> Data? {
        guard offset >= 0, requestedCount >= 0, offset + requestedCount <= count else { return nil }
        return subdata(in: offset..<(offset + requestedCount))
    }

    func prefixData(_ length: Int) -> Data {
        Data(prefix(Swift.max(0, length)))
    }
}
