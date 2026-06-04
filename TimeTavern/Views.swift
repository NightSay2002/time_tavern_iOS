import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: TimeTavernStore

    var body: some View {
        ZStack {
            TavernBackground()
            TabView {
                ChatView()
                    .tabItem { Label("對話", systemImage: "bubble.left.and.bubble.right.fill") }
                CharactersView()
                    .tabItem { Label("角色", systemImage: "person.crop.rectangle.stack.fill") }
                ArchiveView()
                    .tabItem { Label("存檔", systemImage: "archivebox.fill") }
                StudioView()
                    .tabItem { Label("工房", systemImage: "sparkles.rectangle.stack.fill") }
                SettingsView()
                    .tabItem { Label("設定", systemImage: "gearshape.fill") }
            }
            .tint(.pink)
        }
        .task {
            store.attach(modelContext: modelContext)
        }
    }
}

struct TavernBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.12, blue: 0.34),
                Color(red: 0.08, green: 0.22, blue: 0.52),
                Color(red: 0.03, green: 0.08, blue: 0.25)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.pink.opacity(0.30))
                .frame(width: 220, height: 220)
                .blur(radius: 55)
                .offset(x: 80, y: -80)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(.cyan.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: -100, y: 120)
        }
    }
}

struct ChatView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var showLogs = false
    @State private var showModelContent = false
    @State private var showRunTime = false
    @State private var replayMessage: ConversationMessage?
    @State private var replayText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ChatHeader()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.state.conversation) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                                    .contextMenu {
                                        Button("從此分支重跑") {
                                            replayMessage = message
                                            replayText = message.content
                                        }
                                    }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: store.state.conversation.count) { _, _ in
                        if let last = store.state.conversation.last?.id {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
                ChatComposer()
            }
            .background(TavernBackground())
            .navigationTitle("Time Tavern")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showModelContent = true } label: { Image(systemName: "doc.text.magnifyingglass") }
                    Button { showRunTime = true } label: { Image(systemName: "forward.frame.fill") }
                    Button { store.regenerateLatestAssistant() } label: { Image(systemName: "arrow.clockwise") }
                    Button { showLogs = true } label: { Image(systemName: "waveform.path.ecg") }
                }
            }
            .sheet(isPresented: $showLogs) { LogView() }
            .sheet(isPresented: $showModelContent) { ModelContentView() }
            .sheet(isPresented: $showRunTime) { RunTimeView() }
            .sheet(item: $replayMessage) { message in
                NavigationStack {
                    Form {
                        TextEditor(text: $replayText)
                            .frame(minHeight: 180)
                    }
                    .navigationTitle("分支重跑")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { replayMessage = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("重跑") {
                                store.replay(from: message, with: replayText)
                                replayMessage = nil
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ChatHeader: View {
    @EnvironmentObject private var store: TimeTavernStore

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.pink.opacity(0.22))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "moon.stars.fill").foregroundStyle(.pink))
            VStack(alignment: .leading, spacing: 3) {
                Text(store.state.activeRoleCard?.name ?? "尚未開始角色卡")
                    .font(.headline)
                    .foregroundStyle(Color(red: 1.0, green: 0.12, blue: 0.46))
                Text(store.statusText.isEmpty ? "DeepSeek \(store.state.apiSettings.deepSeekModel)" : store.statusText)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.05, green: 0.12, blue: 0.34).opacity(0.78))
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding()
        .background(.white.opacity(0.72))
    }
}

struct MessageBubble: View {
    var message: ConversationMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                Text(message.role == .user ? "你" : "角色")
                    .font(.caption.bold())
                    .foregroundStyle(.pink)
                if message.compressionNotice {
                    Label("模型內容已更新", systemImage: "tray.and.arrow.down.fill")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }
                Text(message.content.isEmpty ? "生成中..." : message.content)
                    .textSelection(.enabled)
                    .foregroundStyle(.white)
            }
            .padding(12)
            .background(message.role == .user ? .pink.opacity(0.28) : .blue.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
            if message.role != .user { Spacer(minLength: 40) }
        }
    }
}

struct ChatComposer: View {
    @EnvironmentObject private var store: TimeTavernStore

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("輸入對話", text: $store.composerText, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                Button {
                    store.isGenerating ? store.cancelGeneration() : store.sendCurrentMessage()
                } label: {
                    Image(systemName: store.isGenerating ? "stop.fill" : "paperplane.fill")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.isGenerating && store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

struct CharactersView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var editingCard: RoleCard?
    @State private var query = ""

    var filteredCards: [RoleCard] {
        guard !query.isEmpty else { return store.state.roleCards }
        return store.state.roleCards.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        store.createRoleCard()
                        editingCard = store.state.roleCards.first
                    } label: {
                        Label("建立角色卡", systemImage: "plus")
                    }
                }
                Section("角色卡") {
                    ForEach(filteredCards) { card in
                        RoleCardRow(card: card, isActive: card.id == store.state.activeRoleCardId)
                            .swipeActions {
                                Button("開始") { store.start(roleCard: card) }.tint(.pink)
                                Button("編輯") { editingCard = card }.tint(.blue)
                            }
                            .onTapGesture { editingCard = card }
                    }
                    .onDelete(perform: store.deleteRoleCards)
                }
            }
            .scrollContentBackground(.hidden)
            .background(TavernBackground())
            .searchable(text: $query, prompt: "搜尋角色")
            .navigationTitle("角色")
            .sheet(item: $editingCard) { card in
                RoleCardEditorView(card: card)
            }
        }
    }
}

struct RoleCardRow: View {
    var card: RoleCard
    var isActive: Bool

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.pink.opacity(0.20))
                .frame(width: 54, height: 54)
                .overlay(Image(systemName: "person.crop.square.fill").foregroundStyle(.pink))
            VStack(alignment: .leading) {
                Text(card.name.isEmpty ? "未命名角色" : card.name)
                    .font(.headline)
                Text("\(card.mode.title) · 世界書 \(card.lorebooks.count) · 開場 \(card.openingDialogues.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.pink)
            }
        }
    }
}

struct RoleCardEditorView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Environment(\.dismiss) private var dismiss
    @State var card: RoleCard

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("名字", text: $card.name)
                    Picker("模式", selection: $card.mode) {
                        ForEach(RoleCardMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Picker("Prompt 模式", selection: $card.promptModeId) {
                        ForEach(store.state.promptModes) { mode in
                            Text(mode.name).tag(mode.id)
                        }
                    }
                }
                Section("自定義內容") {
                    ForEach($card.customSections) { $section in
                        VStack(alignment: .leading) {
                            TextField("名稱", text: $section.name)
                            TextEditor(text: $section.content).frame(minHeight: 90)
                            Toggle("啟用", isOn: $section.enabled)
                        }
                    }
                    Button("新增欄位") { card.customSections.append(CustomSection(name: "新欄位")) }
                }
                Section("開場") {
                    ForEach($card.openingDialogues) { $opening in
                        VStack(alignment: .leading) {
                            TextField("標題", text: $opening.name)
                            TextEditor(text: $opening.content).frame(minHeight: 90)
                        }
                    }
                    Button("新增開場") { card.openingDialogues.append(OpeningDialogue(name: "開場 \(card.openingDialogues.count + 1)")) }
                }
                Section("世界書") {
                    ForEach($card.lorebooks) { $entry in
                        VStack(alignment: .leading) {
                            TextField("標題", text: $entry.title)
                            TextField("關鍵字，用逗號分隔", text: Binding(
                                get: { entry.keywords.joined(separator: ", ") },
                                set: { entry.keywords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                            TextEditor(text: $entry.content).frame(minHeight: 90)
                            Toggle("啟用", isOn: $entry.enabled)
                        }
                    }
                    Button("新增世界書") { card.lorebooks.append(LorebookEntry(title: "世界書")) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(TavernBackground())
            .navigationTitle(card.name.isEmpty ? "角色卡" : card.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.update(roleCard: card)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ArchiveView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var sessionName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("保存目前對話") {
                    TextField("存檔名稱", text: $sessionName)
                    Button("保存") {
                        store.saveSession(named: sessionName)
                        sessionName = ""
                    }
                }
                Section("存檔") {
                    ForEach(store.state.savedSessions) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.name).font(.headline)
                            Text("角色：\(session.roleCardName) · 訊息 \(session.conversation.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("載入") { store.load(session: session) }
                                Spacer()
                                Text(session.updatedAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: store.deleteSessions)
                }
            }
            .scrollContentBackground(.hidden)
            .background(TavernBackground())
            .navigationTitle("存檔")
        }
    }
}

struct StudioView: View {
    enum StudioMode: String, CaseIterable, Identifiable {
        case prompt = "Prompt Lab"
        case novelAI = "NovelAI"
        var id: String { rawValue }
    }

    @State private var mode: StudioMode = .prompt

    var body: some View {
        NavigationStack {
            VStack {
                Picker("工房", selection: $mode) {
                    ForEach(StudioMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                if mode == .prompt {
                    PromptLabView()
                } else {
                    NovelAIView()
                }
            }
            .navigationTitle("工房")
            .background(TavernBackground())
        }
    }
}

struct PromptLabView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var selectedModeID = "multi"

    var body: some View {
        List {
            ForEach($store.state.promptModes) { $mode in
                Section(mode.name) {
                    TextField("名稱", text: $mode.name)
                    Stepper("上下文 \(mode.dialogueContextRounds) 輪", value: $mode.dialogueContextRounds, in: 1...80)
                    TextEditor(text: $mode.mainRules)
                        .frame(minHeight: 100)
                    TextEditor(text: $mode.outputRules)
                        .frame(minHeight: 100)
                    NavigationLink("壓縮 Profiles") {
                        CompressionProfileListView(mode: $mode)
                    }
                    NavigationLink("Prompt Preview") {
                        PromptPreviewView(mode: mode)
                    }
                }
            }
            Button("新增自訂模式") {
                store.state.promptModes.append(PromptModeConfig(id: "custom_\(store.state.promptModes.count + 1)", name: "自訂模式", mode: "custom"))
                store.persist()
            }
        }
        .scrollContentBackground(.hidden)
        .background(TavernBackground())
        .onDisappear { store.persist() }
    }
}

struct CompressionProfileListView: View {
    @Binding var mode: PromptModeConfig

    var body: some View {
        List {
            ForEach($mode.compressionProfiles) { $profile in
                Section(profile.name) {
                    TextField("名稱", text: $profile.name)
                    Toggle("啟用", isOn: $profile.enabled)
                    TextEditor(text: $profile.mainRules).frame(minHeight: 90)
                    TextEditor(text: $profile.summary).frame(minHeight: 120)
                    Stepper("已壓縮到第 \(profile.compressedThroughTurnNumber) 回合", value: $profile.compressedThroughTurnNumber, in: 0...9999)
                    NavigationLink("觸發組合") {
                        TriggerActionListView(profile: $profile)
                    }
                    NavigationLink("追加詞") {
                        AppendTermListView(profile: $profile)
                    }
                }
            }
            Button("新增 Profile") {
                mode.compressionProfiles.append(CompressionProfile(id: "compression_profile_\(mode.compressionProfiles.count + 1)", name: "自訂壓縮"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(TavernBackground())
        .navigationTitle("壓縮 Profiles")
    }
}

struct TriggerActionListView: View {
    @Binding var profile: CompressionProfile

    var body: some View {
        Form {
            ForEach($profile.triggerActions) { $action in
                Section(action.name) {
                    TextField("名稱", text: $action.name)
                    Toggle("啟用", isOn: $action.enabled)
                    Picker("動作", selection: $action.action) {
                        ForEach(CompressionTriggerActionKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    TextField("關鍵字表達式", text: $action.keywords)
                    Toggle("不 call 正文", isOn: $action.skipChat)
                    Toggle("觸發 NovelAI Prompt", isOn: $action.novelAIEnabled)
                    TextEditor(text: $action.novelAIPromptTemplate).frame(minHeight: 90)
                }
            }
            Button("新增觸發") { profile.triggerActions.append(CompressionTriggerAction()) }
        }
        .scrollContentBackground(.hidden)
        .background(TavernBackground())
    }
}

struct AppendTermListView: View {
    @Binding var profile: CompressionProfile

    var body: some View {
        Form {
            ForEach($profile.appendTerms) { $term in
                TextField("玩家座位", text: $term.playerSlot)
                TextEditor(text: $term.content).frame(minHeight: 80)
                Toggle("啟用", isOn: $term.enabled)
            }
            Button("新增追加詞") { profile.appendTerms.append(CompressionAppendTerm()) }
        }
        .scrollContentBackground(.hidden)
        .background(TavernBackground())
    }
}

struct PromptPreviewView: View {
    @EnvironmentObject private var store: TimeTavernStore
    var mode: PromptModeConfig

    var body: some View {
        ScrollView {
            Text(store.state.activeRoleCard.map { ConversationEngine().promptPreview(state: store.state, roleCard: $0, input: "測試輸入") } ?? "請先開始角色卡。")
                .font(.system(.body, design: .monospaced))
                .padding()
        }
        .background(TavernBackground())
        .navigationTitle("Preview")
    }
}

struct NovelAIView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var prompt = ""
    @State private var negativePrompt = "lowres, bad anatomy"
    @State private var model = "nai-diffusion-4-full"
    @State private var width = 832
    @State private var height = 1216
    @State private var steps = 28
    @State private var scale = 5.0

    var body: some View {
        List {
            Section("生成") {
                TextEditor(text: $prompt).frame(minHeight: 100)
                TextEditor(text: $negativePrompt).frame(minHeight: 80)
                TextField("模型", text: $model)
                Stepper("寬 \(width)", value: $width, in: 512...1536, step: 64)
                Stepper("高 \(height)", value: $height, in: 512...1536, step: 64)
                Stepper("步數 \(steps)", value: $steps, in: 1...50)
                Slider(value: $scale, in: 1...12) { Text("Scale") }
                Button("生成圖片") {
                    store.generateNovelAIImage(prompt: prompt, negativePrompt: negativePrompt, model: model, width: width, height: height, steps: steps, scale: scale)
                }
            }
            Section("本地相簿") {
                ForEach(store.state.novelAIAlbum) { item in
                    VStack(alignment: .leading) {
                        if let image = UIImage(data: item.imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text(item.prompt).font(.caption)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TavernBackground())
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("DeepSeek") {
                    SecureField("DeepSeek API Key", text: $store.deepSeekKey)
                    TextField("Base URL", text: $store.state.apiSettings.deepSeekBaseURL)
                    TextField("Model", text: $store.state.apiSettings.deepSeekModel)
                    Stepper("Max Tokens \(store.state.apiSettings.maxTokens)", value: $store.state.apiSettings.maxTokens, in: 512...64000, step: 512)
                    Slider(value: $store.state.apiSettings.temperature, in: 0...1.5) { Text("Temperature") }
                    Button("測試 DeepSeek") { store.testDeepSeek() }
                }
                Section("NovelAI") {
                    SecureField("NovelAI API Token", text: $store.novelAIKey)
                    TextField("Image API", text: $store.state.apiSettings.naiImageBaseURL)
                    TextField("Primary API", text: $store.state.apiSettings.naiPrimaryBaseURL)
                    Button("測試 NovelAI") { store.testNovelAI() }
                }
                Section("使用者") {
                    TextField("稱呼", text: $store.state.userProfile.userName)
                    TextEditor(text: $store.state.userProfile.extraPrompt).frame(minHeight: 90)
                }
                Section("時間追蹤") {
                    Toggle("啟用", isOn: $store.state.timeTracking.enabled)
                    Stepper("第 \(store.state.timeTracking.day) 天", value: $store.state.timeTracking.day, in: 1...9999)
                    TextField("時段", text: $store.state.timeTracking.period)
                    Stepper("每 \(store.state.timeTracking.autoAdvanceRounds) 輪切換", value: $store.state.timeTracking.autoAdvanceRounds, in: 1...20)
                }
                Section("匯入/匯出") {
                    Button("匯入 Web ZIP") { showImporter = true }
                    Button("匯出 iOS ZIP") { store.exportBundle() }
                    if let url = store.exportedBundleURL {
                        ShareLink(item: url) {
                            Label("分享匯出檔", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                if !store.statusText.isEmpty {
                    Section("狀態") {
                        Text(store.statusText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(TavernBackground())
            .navigationTitle("設定")
            .toolbar {
                Button("保存") {
                    store.saveSecrets()
                    store.persist()
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip]) { result in
                if case let .success(url) = result {
                    _ = url.startAccessingSecurityScopedResource()
                    store.importBundle(url: url)
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
    }
}

struct LogView: View {
    @EnvironmentObject private var store: TimeTavernStore

    var body: some View {
        NavigationStack {
            List(store.state.aiLogs) { log in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(log.purpose) · \(log.model)").font(.headline)
                    Text(log.status).font(.caption).foregroundStyle(log.status == "error" ? .red : .secondary)
                    if !log.error.isEmpty { Text(log.error).foregroundStyle(.red) }
                    Text(log.responsePreview).font(.caption).lineLimit(8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(TavernBackground())
            .navigationTitle("AI Logs")
        }
    }
}

struct ModelContentView: View {
    @EnvironmentObject private var store: TimeTavernStore

    var body: some View {
        NavigationStack {
            List {
                ForEach($store.state.promptModes) { $mode in
                    ForEach($mode.compressionProfiles) { $profile in
                        Section("\(mode.name) · \(profile.name)") {
                            TextEditor(text: $profile.summary).frame(minHeight: 150)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(TavernBackground())
            .navigationTitle("模型內容")
            .toolbar {
                Button("保存") { store.persist() }
            }
        }
    }
}

struct RunTimeView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Environment(\.dismiss) private var dismiss
    @State private var turns = 3
    @State private var message = "請根據目前劇情自然推進。"

    var body: some View {
        NavigationStack {
            Form {
                Stepper("輪數 \(turns)", value: $turns, in: 1...20)
                TextEditor(text: $message).frame(minHeight: 160)
            }
            .scrollContentBackground(.hidden)
            .background(TavernBackground())
            .navigationTitle("自動推演")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("開始") {
                        store.runTime(turns: turns, seedMessage: message)
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension UTType {
    static var zip: UTType {
        UTType(filenameExtension: "zip") ?? .data
    }
}
