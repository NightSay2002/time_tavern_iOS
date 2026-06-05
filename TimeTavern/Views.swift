import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum AppTab: String, CaseIterable, Identifiable {
    case chat
    case characters
    case archive
    case studio
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: "對話"
        case .characters: "角色"
        case .archive: "存檔"
        case .studio: "工房"
        case .settings: "設定"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: "text.bubble.fill"
        case .characters: "person.crop.square.fill"
        case .archive: "archivebox.fill"
        case .studio: "sparkles"
        case .settings: "gearshape.fill"
        }
    }
}

enum VNTheme {
    static let accent = Color(red: 1.0, green: 0.22, blue: 0.56)
    static let accentSoft = Color(red: 1.0, green: 0.50, blue: 0.72)
    static let ink = Color(red: 0.03, green: 0.04, blue: 0.12)
    static let panel = Color(red: 0.06, green: 0.07, blue: 0.20)
    static let panelBright = Color(red: 0.12, green: 0.11, blue: 0.32)
    static let textSecondary = Color(red: 0.78, green: 0.80, blue: 0.92)
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: TimeTavernStore
    @State private var selectedTab: AppTab = .chat

    var body: some View {
        ZStack {
            VisualNovelBackground()
            TabView(selection: $selectedTab) {
                ChatView()
                    .tag(AppTab.chat)
                CharactersView()
                    .tag(AppTab.characters)
                ArchiveView()
                    .tag(AppTab.archive)
                StudioView()
                    .tag(AppTab.studio)
                SettingsView()
                    .tag(AppTab.settings)
            }
            .toolbar(.hidden, for: .tabBar)
            .tint(VNTheme.accent)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VisualNovelTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(
                    LinearGradient(
                        colors: [.clear, VNTheme.ink.opacity(0.86)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
        }
        .preferredColorScheme(.dark)
        .task {
            store.attach(modelContext: modelContext)
        }
    }
}

struct VisualNovelBackground: View {
    var body: some View {
        GeometryReader { proxy in
            Image("TavernVisualNovelBackground")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .blur(radius: 1.2)
                .saturation(1.08)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.03, blue: 0.12).opacity(0.28),
                            Color(red: 0.08, green: 0.05, blue: 0.24).opacity(0.44),
                            Color(red: 0.01, green: 0.02, blue: 0.09).opacity(0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RadialGradient(
                        colors: [VNTheme.accent.opacity(0.26), .clear],
                        center: .topTrailing,
                        startRadius: 20,
                        endRadius: 360
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color(red: 0.14, green: 0.09, blue: 0.33).opacity(0.38),
                            VNTheme.ink.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blur(radius: 18)
                )
        }
        .ignoresSafeArea()
    }
}

struct TavernBackground: View {
    var body: some View {
        VisualNovelBackground()
    }
}

struct VNGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var accentOpacity: Double = 0.42
    var content: Content

    init(cornerRadius: CGFloat = 22, accentOpacity: Double = 0.42, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.accentOpacity = accentOpacity
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VNTheme.panel.opacity(0.66))
                    .overlay(.ultraThinMaterial.opacity(0.34))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                VNTheme.accent.opacity(accentOpacity),
                                Color.white.opacity(0.14),
                                Color(red: 0.36, green: 0.42, blue: 1.0).opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: VNTheme.ink.opacity(0.36), radius: 20, y: 12)
    }
}

struct VisualNovelTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(selectedTab == tab ? VNTheme.accentSoft : VNTheme.textSecondary.opacity(0.78))
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(VNTheme.accent.opacity(0.18))
                                .shadow(color: VNTheme.accent.opacity(0.58), radius: 16, y: 0)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(VNTheme.ink.opacity(0.78))
                .overlay(.ultraThinMaterial.opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
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
            ZStack {
                VisualNovelBackground()
                VStack(spacing: 0) {
                    ChatSceneHeader(
                        showModelContent: { showModelContent = true },
                        showRunTime: { showRunTime = true },
                        regenerate: { store.regenerateLatestAssistant() },
                        showLogs: { showLogs = true }
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                    CharacterStatusCard()
                        .padding(.horizontal, 18)
                        .padding(.top, 10)

                    ZStack {
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
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                                .padding(.bottom, 8)
                            }
                            .onChange(of: store.state.conversation.count) { _, _ in
                                if let last = store.state.conversation.last?.id {
                                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                                }
                            }
                        }
                        if store.state.conversation.isEmpty {
                            EmptyStoryHintCard()
                                .padding(.horizontal, 34)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VisualNovelComposer()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showLogs) { LogView() }
            .sheet(isPresented: $showModelContent) { ModelContentView() }
            .sheet(isPresented: $showRunTime) { RunTimeView() }
            .sheet(item: $replayMessage) { message in
                NavigationStack {
                    Form {
                        TextEditor(text: $replayText)
                            .frame(minHeight: 180)
                    }
                    .visualNovelListChrome()
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

struct ChatSceneHeader: View {
    var showModelContent: () -> Void
    var showRunTime: () -> Void
    var regenerate: () -> Void
    var showLogs: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Time Tavern")
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                    .shadow(color: VNTheme.accent.opacity(0.55), radius: 12, y: 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text("AI Roleplay Session")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VNTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                HeaderIconButton(systemImage: "doc.text.magnifyingglass", action: showModelContent, label: "模型內容")
                HeaderIconButton(systemImage: "forward.frame.fill", action: showRunTime, label: "自動推演")
                HeaderIconButton(systemImage: "arrow.clockwise", action: regenerate, label: "重新生成")
                HeaderIconButton(systemImage: "waveform.path.ecg", action: showLogs, label: "AI Logs")
            }
            .padding(5)
            .background(
                Capsule()
                    .fill(VNTheme.ink.opacity(0.66))
                    .overlay(.ultraThinMaterial.opacity(0.22))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: VNTheme.ink.opacity(0.4), radius: 18, y: 10)
        }
    }
}

struct HeaderIconButton: View {
    var systemImage: String
    var action: () -> Void
    var label: String

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 31, height: 31)
                .foregroundStyle(VNTheme.accentSoft)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct CharacterStatusCard: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var appeared = false

    var activeCard: RoleCard? { store.state.activeRoleCard }
    var ready: Bool { activeCard != nil }

    static func statusTitle(isReady: Bool) -> String {
        isReady ? "Ready" : "Idle"
    }

    var body: some View {
        VNGlassCard(cornerRadius: 20, accentOpacity: 0.62) {
            HStack(spacing: 12) {
                CharacterAvatarView(imageData: activeCard?.coverImageData)
                VStack(alignment: .leading, spacing: 5) {
                    Text(activeCard?.name.nonEmpty ?? "尚未開始角色卡")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(VNTheme.accentSoft)
                        .lineLimit(1)
                    Text("DeepSeek \(store.state.apiSettings.deepSeekModel)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VNTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(Self.statusTitle(isReady: ready))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ready ? VNTheme.accentSoft : VNTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill((ready ? VNTheme.accent : Color.white).opacity(ready ? 0.18 : 0.10))
                    )
                    .overlay(Capsule().stroke((ready ? VNTheme.accent : Color.white).opacity(0.28), lineWidth: 1))
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.54, dampingFraction: 0.86).delay(0.08)) {
                appeared = true
            }
        }
    }
}

struct CharacterAvatarView: View {
    var imageData: Data?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [VNTheme.accent.opacity(0.32), Color(red: 0.23, green: 0.22, blue: 0.54).opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(VNTheme.accentSoft)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(VNTheme.accent.opacity(0.38), lineWidth: 1)
        )
    }
}

struct EmptyStoryHintCard: View {
    var body: some View {
        VNGlassCard(cornerRadius: 24, accentOpacity: 0.46) {
            VStack(spacing: 8) {
                Text("尚未開始故事")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("選擇角色卡或直接輸入內容開始。")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VNTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
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
                    .foregroundStyle(VNTheme.accentSoft)
                if message.compressionNotice {
                    Label("模型內容已更新", systemImage: "tray.and.arrow.down.fill")
                        .font(.caption)
                        .foregroundStyle(VNTheme.accentSoft)
                }
                Text(message.content.isEmpty ? "生成中..." : message.content)
                    .textSelection(.enabled)
                    .foregroundStyle(.white)
            }
            .padding(12)
            .background(
                message.role == .user ? VNTheme.accent.opacity(0.30) : VNTheme.panelBright.opacity(0.68),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(message.role == .user ? VNTheme.accent.opacity(0.32) : Color.white.opacity(0.12), lineWidth: 1)
            )
            if message.role != .user { Spacer(minLength: 40) }
        }
    }
}

struct VisualNovelComposer: View {
    @EnvironmentObject private var store: TimeTavernStore
    @FocusState private var inputFocused: Bool

    static func isSendDisabled(isGenerating: Bool, text: String) -> Bool {
        !isGenerating && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var sendDisabled: Bool {
        Self.isSendDisabled(isGenerating: store.isGenerating, text: store.composerText)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("輸入對話", text: $store.composerText, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .font(.body)
                .foregroundStyle(.white)
                .tint(VNTheme.accentSoft)
                .padding(.vertical, 8)
            Button {
                store.isGenerating ? store.cancelGeneration() : store.sendCurrentMessage()
            } label: {
                Image(systemName: store.isGenerating ? "stop.fill" : "paperplane.fill")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
                    .background(
                        Circle()
                            .fill(sendDisabled ? Color.white.opacity(0.12) : VNTheme.accent.opacity(0.88))
                    )
                    .shadow(color: sendDisabled ? .clear : VNTheme.accent.opacity(0.42), radius: 14, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(sendDisabled)
            .opacity(sendDisabled ? 0.46 : 1)
            .scaleEffect(sendDisabled ? 0.94 : 1)
            .animation(.easeInOut(duration: 0.2), value: sendDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(VNTheme.ink.opacity(0.82))
                .overlay(.ultraThinMaterial.opacity(0.20))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [VNTheme.accent.opacity(0.44), Color.white.opacity(0.13)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: VNTheme.ink.opacity(0.56), radius: 24, y: 14)
        .offset(y: inputFocused ? -10 : 0)
        .padding(.bottom, inputFocused ? 12 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: inputFocused)
        .accessibilityIdentifier("visualNovelComposer")
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
                                Button("開始") { store.start(roleCard: card) }.tint(VNTheme.accent)
                                Button("編輯") { editingCard = card }.tint(Color(red: 0.36, green: 0.42, blue: 1.0))
                            }
                            .onTapGesture { editingCard = card }
                    }
                    .onDelete(perform: store.deleteRoleCards)
                }
            }
            .visualNovelListChrome()
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VNTheme.accent.opacity(0.20))
                .frame(width: 54, height: 54)
                .overlay(Image(systemName: "person.crop.square.fill").foregroundStyle(VNTheme.accentSoft))
            VStack(alignment: .leading) {
                Text(card.name.isEmpty ? "未命名角色" : card.name)
                    .font(.headline)
                Text("\(card.mode.title) · 世界書 \(card.lorebooks.count) · 開場 \(card.openingDialogues.count)")
                    .font(.caption)
                    .foregroundStyle(VNTheme.textSecondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(VNTheme.accentSoft)
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
            .visualNovelListChrome()
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
                                .foregroundStyle(VNTheme.textSecondary)
                            HStack {
                                Button("載入") { store.load(session: session) }
                                Spacer()
                                Text(session.updatedAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(VNTheme.textSecondary)
                            }
                        }
                    }
                    .onDelete(perform: store.deleteSessions)
                }
            }
            .visualNovelListChrome()
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
            VStack(spacing: 12) {
                VNGlassCard(cornerRadius: 20, accentOpacity: 0.34) {
                    Picker("工房", selection: $mode) {
                        ForEach(StudioMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                if mode == .prompt {
                    PromptLabView()
                } else {
                    NovelAIView()
                }
            }
            .navigationTitle("工房")
            .background(VisualNovelBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
        .visualNovelListChrome()
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
        .visualNovelListChrome()
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
        .visualNovelListChrome()
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
        .visualNovelListChrome()
    }
}

struct PromptPreviewView: View {
    @EnvironmentObject private var store: TimeTavernStore
    var mode: PromptModeConfig

    var body: some View {
        ScrollView {
            VNGlassCard(cornerRadius: 20, accentOpacity: 0.28) {
                Text(store.state.activeRoleCard.map { ConversationEngine().promptPreview(state: store.state, roleCard: $0, input: "測試輸入") } ?? "請先開始角色卡。")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .background(VisualNovelBackground())
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
        .visualNovelListChrome()
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
            .visualNovelListChrome()
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
                    Text(log.status).font(.caption).foregroundStyle(log.status == "error" ? .red : VNTheme.textSecondary)
                    if !log.error.isEmpty { Text(log.error).foregroundStyle(.red) }
                    Text(log.responsePreview).font(.caption).lineLimit(8)
                }
            }
            .visualNovelListChrome()
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
            .visualNovelListChrome()
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
            .visualNovelListChrome()
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

private struct VisualNovelListChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(VisualNovelBackground())
            .environment(\.colorScheme, .dark)
            .tint(VNTheme.accent)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private extension View {
    func visualNovelListChrome() -> some View {
        modifier(VisualNovelListChrome())
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension UTType {
    static var zip: UTType {
        UTType(filenameExtension: "zip") ?? .data
    }
}
