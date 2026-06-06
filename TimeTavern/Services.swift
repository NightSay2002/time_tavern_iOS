import Foundation
import Security
import SwiftData
import ZIPFoundation

struct ChatAPIMessage: Codable, Hashable {
    var role: String
    var content: String
}

struct ChatCompletionResult: Hashable {
    var content: String
    var reasoningContent: String
    var model: String
}

final class SecretStore {
    enum Key: String {
        case deepSeekAPIKey
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
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> ChatCompletionResult {
        try await completion(apiKey: apiKey, settings: settings, messages: messages, stream: true, onDelta: onDelta)
    }

    private func completion(
        apiKey: String,
        settings: APISettings,
        messages: [ChatAPIMessage],
        stream: Bool,
        onDelta: (@Sendable (String) -> Void)? = nil
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
            stream: stream
        )
        request.httpBody = try JSONEncoder().encode(body)

        if stream {
            let (bytes, response) = try await session.bytes(for: request)
            try validateHTTP(response)
            var content = ""
            var reasoning = ""
            for try await rawLine in bytes.lines {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8) else { continue }
                guard let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) else { continue }
                if let delta = chunk.choices.first?.delta.reasoningContent, !delta.isEmpty {
                    reasoning += delta
                }
                if let delta = chunk.choices.first?.delta.content, !delta.isEmpty {
                    content += delta
                    onDelta?(delta)
                }
            }
            return ChatCompletionResult(content: content, reasoningContent: reasoning, model: settings.deepSeekModel)
        } else {
            let (data, response) = try await session.data(for: request)
            try validateHTTP(response, data: data)
            let payload = try JSONDecoder().decode(ChatResponse.self, from: data)
            let message = payload.choices.first?.message
            return ChatCompletionResult(
                content: message?.content ?? "",
                reasoningContent: message?.reasoningContent ?? "",
                model: settings.deepSeekModel
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

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
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
        studioSettings.imageSettings.model = model
        studioSettings.imageSettings.width = width
        studioSettings.imageSettings.height = height
        studioSettings.imageSettings.steps = steps
        studioSettings.imageSettings.scale = scale
        return try await generateImages(apiKey: apiKey, settings: settings, studioSettings: studioSettings)
    }

    func generateImages(
        apiKey: String,
        settings: APISettings,
        studioSettings: NovelAIStudioSettings
    ) async throws -> [NovelAIAlbumItem] {
        guard !apiKey.isEmpty else { throw TimeTavernError.missingNovelAIKey }
        let url = URL(string: settings.naiImageBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/ai/generate-image")!
        let loops = max(1, min(studioSettings.loopCount, 20))
        var results: [NovelAIAlbumItem] = []
        for _ in 0..<loops {
            let prompt = Self.resolvedPrompt(from: studioSettings)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 600
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Self.correlationID(), forHTTPHeaderField: "x-correlation-id")
            let payload = Self.buildImageGenerationRequest(studioSettings: studioSettings, prompt: prompt)
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await session.data(for: request)
            try validateHTTP(response, data: data)
            results.append(contentsOf: try extractImages(
                fromZipData: data,
                prompt: prompt,
                negativePrompt: studioSettings.negativePrompt,
                model: studioSettings.imageSettings.model
            ))
        }
        return results
    }

    static func resolvedPrompt(from settings: NovelAIStudioSettings, randomIndex: ((Int) -> Int)? = nil) -> String {
        var prompt = settings.basePrompt
        let fixed = settings.fixedSnippets.filter(\.enabled)
        let random = settings.randomSnippets.filter(\.enabled)
        let snippets = fixed + selectedRandomSnippets(random, randomIndex: randomIndex)
        for snippet in snippets where !snippet.name.isEmpty {
            prompt = prompt.replacingOccurrences(of: "||\(snippet.name)||", with: snippet.content)
        }
        let appendedSnippets = snippets.filter { !prompt.contains($0.content) }.map(\.content)
        let characterPrompts = settings.characterPrompts
            .filter(\.enabled)
            .map { $0.name.isEmpty ? $0.prompt : "\($0.name): \($0.prompt)" }
        return ([prompt] + appendedSnippets + characterPrompts)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func buildImageGenerationRequest(studioSettings: NovelAIStudioSettings, prompt: String? = nil) -> NovelAIRequest {
        let imageSettings = studioSettings.imageSettings
        let resolvedPrompt = prompt ?? resolvedPrompt(from: studioSettings)
        let references = studioSettings.vibeTransferImages.filter { $0.enabled && $0.imageData != nil }
        let preciseReferences = studioSettings.preciseReferenceImages.filter { $0.enabled && $0.imageData != nil }
        return NovelAIRequest(
            action: "generate",
            input: resolvedPrompt,
            model: imageSettings.model,
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
                referenceStrengthMultiple: (references + preciseReferences).map(\.strength)
            )
        )
    }

    static func settingsByImportingMetadata(_ metadata: String, into settings: NovelAIStudioSettings) -> NovelAIStudioSettings {
        guard let data = metadata.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return settings }
        var next = settings
        if let input = object["input"] as? String {
            next.basePrompt = input
        }
        if let model = object["model"] as? String {
            next.imageSettings.model = model
        }
        let parameters = object["parameters"] as? [String: Any] ?? object
        if let negative = parameters["negative_prompt"] as? String {
            next.negativePrompt = negative
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
        return next
    }

    private static func selectedRandomSnippets(_ snippets: [NovelAIPromptSnippet], randomIndex: ((Int) -> Int)?) -> [NovelAIPromptSnippet] {
        guard !snippets.isEmpty else { return [] }
        let index = randomIndex?(snippets.count) ?? Int.random(in: 0..<snippets.count)
        return [snippets[max(0, min(index, snippets.count - 1))]]
    }

    private func extractImages(fromZipData data: Data, prompt: String, negativePrompt: String, model: String) throws -> [NovelAIAlbumItem] {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let archive = try Archive(url: tempURL, accessMode: .read, pathEncoding: nil)
        var items: [NovelAIAlbumItem] = []
        for entry in archive {
            let lower = entry.path.lowercased()
            guard lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".webp") else {
                continue
            }
            var imageData = Data()
            _ = try archive.extract(entry) { chunk in
                imageData.append(chunk)
            }
            let mimeType = lower.hasSuffix(".webp") ? "image/webp" : lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") ? "image/jpeg" : "image/png"
            items.append(NovelAIAlbumItem(
                fileName: URL(fileURLWithPath: entry.path).lastPathComponent,
                mimeType: mimeType,
                prompt: prompt,
                negativePrompt: negativePrompt,
                model: model,
                imageData: imageData,
                metadata: "{}"
            ))
        }
        if items.isEmpty {
            throw TimeTavernError.network("NovelAI 沒有回傳圖片。")
        }
        return items
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

    enum CodingKeys: String, CodingKey {
        case width, height, scale, sampler, steps, prompt, seed, image, strength, noise
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
    }
}
