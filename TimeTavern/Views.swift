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
                    if card.customSections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("尚未新增自定義內容")
                                .font(.headline)
                            Text("新角色卡不再預設塞入欄位。需要角色設定、世界觀或規則時再新增。")
                                .font(.caption)
                                .foregroundStyle(VNTheme.textSecondary)
                        }
                        .padding(.vertical, 6)
                    }
                    ForEach($card.customSections) { $section in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(section.name.isEmpty ? "未命名欄位" : section.name)
                                    .font(.headline)
                                Spacer()
                                Button(role: .destructive) {
                                    deleteCustomSection(id: section.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
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
                            HStack {
                                Text(opening.name.isEmpty ? "開場" : opening.name)
                                    .font(.headline)
                                Spacer()
                                Button(role: .destructive) {
                                    deleteOpening(id: opening.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            TextField("標題", text: $opening.name)
                            TextEditor(text: $opening.content).frame(minHeight: 90)
                        }
                    }
                    Button("新增開場") { card.openingDialogues.append(OpeningDialogue(name: "開場 \(card.openingDialogues.count + 1)")) }
                }
                Section("世界書") {
                    ForEach($card.lorebooks) { $entry in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(entry.title.isEmpty ? "世界書" : entry.title)
                                    .font(.headline)
                                Spacer()
                                Button(role: .destructive) {
                                    deleteLorebook(id: entry.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
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
                        card = Self.normalizedForSave(card)
                        store.update(roleCard: card)
                        dismiss()
                    }
                }
            }
        }
    }

    static func normalizedForSave(_ card: RoleCard) -> RoleCard {
        var next = card
        if next.openingDialogues.isEmpty {
            next.openingDialogues = [OpeningDialogue()]
        }
        if !next.openingDialogues.contains(where: { $0.id == next.activeOpeningDialogueId }) {
            next.activeOpeningDialogueId = next.openingDialogues.first?.id ?? ""
        }
        return next
    }

    static func cardByDeletingOpening(_ card: RoleCard, openingID: String) -> RoleCard {
        var next = card
        next.openingDialogues.removeAll { $0.id == openingID }
        if next.openingDialogues.isEmpty {
            next.openingDialogues = [OpeningDialogue()]
        }
        if next.activeOpeningDialogueId == openingID || !next.openingDialogues.contains(where: { $0.id == next.activeOpeningDialogueId }) {
            next.activeOpeningDialogueId = next.openingDialogues.first?.id ?? ""
        }
        return next
    }

    private func deleteCustomSection(id: String) {
        card.customSections.removeAll { $0.id == id }
    }

    private func deleteOpening(id: String) {
        card = Self.cardByDeletingOpening(card, openingID: id)
    }

    private func deleteLorebook(id: String) {
        card.lorebooks.removeAll { $0.id == id }
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

    var body: some View {
        List {
            Section("模式") {
                ForEach($store.state.promptModes) { $mode in
                    NavigationLink {
                        PromptModeEditorView(mode: $mode, isBuiltIn: Self.isBuiltIn(mode.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(mode.name)
                                    .font(.headline)
                                if Self.isBuiltIn(mode.id) {
                                    Text("內建")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(VNTheme.accentSoft)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(VNTheme.accent.opacity(0.16)))
                                }
                            }
                            Text("\(mode.mode) · 上下文 \(mode.dialogueContextRounds) 輪 · Profiles \(mode.compressionProfiles.count)")
                                .font(.caption)
                                .foregroundStyle(VNTheme.textSecondary)
                        }
                    }
                }
                .onDelete(perform: deleteModes)
            }
            Section {
                Button {
                    let index = store.state.promptModes.filter { $0.mode == "custom" }.count + 1
                    store.state.promptModes.append(PromptModeConfig(
                        id: "custom_\(UUID().uuidString)",
                        name: "自訂模式 \(index)",
                        mode: "custom"
                    ))
                    store.persist()
                } label: {
                    Label("新增自訂模式", systemImage: "plus")
                }
            }
        }
        .visualNovelListChrome()
        .navigationTitle("Prompt Lab")
        .onDisappear { store.persist() }
    }

    static func isBuiltIn(_ id: String) -> Bool {
        ["single", "multi", "no_role"].contains(id)
    }

    private func deleteModes(at offsets: IndexSet) {
        let ids = offsets.map { store.state.promptModes[$0].id }
        store.state.promptModes.removeAll { ids.contains($0.id) && !Self.isBuiltIn($0.id) }
        store.persist()
    }
}

struct PromptModeEditorView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Binding var mode: PromptModeConfig
    var isBuiltIn: Bool

    var body: some View {
        Form {
            Section("模式設定") {
                TextField("名稱", text: $mode.name)
                TextField("Mode ID", text: $mode.mode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Stepper("對話上下文 \(mode.dialogueContextRounds) 輪", value: $mode.dialogueContextRounds, in: 1...80)
                if isBuiltIn {
                    Label("內建模式不可刪除，但可以調整內容。", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                }
            }
            Section("編輯器") {
                NavigationLink("正文規則") {
                    PromptRulesEditorView(mode: $mode)
                }
                NavigationLink("壓縮大模型") {
                    CompressionProfileListView(mode: $mode)
                }
                NavigationLink("雙 Prompt Preview") {
                    PromptPreviewView(mode: mode)
                }
            }
        }
        .visualNovelListChrome()
        .navigationTitle(mode.name)
        .toolbar {
            Button("保存") { store.persist() }
        }
    }
}

struct PromptRulesEditorView: View {
    @Binding var mode: PromptModeConfig

    var body: some View {
        Form {
            Section("正文 System Prompt") {
                TextEditor(text: $mode.reasonerHistoryConfig.mainRules)
                    .frame(minHeight: 220)
            }
            Section("上下文規則") {
                TextEditor(text: $mode.reasonerHistoryConfig.contextRules)
                    .frame(minHeight: 180)
            }
            Section("舊版欄位") {
                TextEditor(text: $mode.mainRules)
                    .frame(minHeight: 120)
                TextEditor(text: $mode.outputRules)
                    .frame(minHeight: 120)
            }
        }
        .visualNovelListChrome()
        .navigationTitle("正文規則")
    }
}

struct CompressionProfileListView: View {
    @Binding var mode: PromptModeConfig

    var body: some View {
        List {
            ForEach($mode.compressionProfiles) { $profile in
                NavigationLink {
                    CompressionProfileEditorView(profile: $profile)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(profile.name)
                                .font(.headline)
                            if profile.locked {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(VNTheme.accentSoft)
                            }
                        }
                        Text("\(profile.contextScope.title) · Trigger \(profile.triggerActions.count) · 模型 \(profile.contextCompression.models.count)")
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    }
                }
            }
            .onDelete(perform: deleteProfiles)
            Button {
                mode.compressionProfiles.append(CompressionProfile(
                    id: "compression_profile_\(UUID().uuidString)",
                    name: "自訂壓縮",
                    locked: false
                ))
            } label: {
                Label("新增 Profile", systemImage: "plus")
            }
        }
        .visualNovelListChrome()
        .navigationTitle("壓縮 Profiles")
    }

    private func deleteProfiles(at offsets: IndexSet) {
        let ids = offsets.map { mode.compressionProfiles[$0].id }
        mode.compressionProfiles.removeAll { ids.contains($0.id) && !$0.locked && $0.id != "standard" }
    }
}

struct CompressionProfileEditorView: View {
    @Binding var profile: CompressionProfile

    var body: some View {
        Form {
            Section("Profile") {
                TextField("名稱", text: $profile.name)
                Toggle("啟用", isOn: $profile.enabled)
                Toggle("鎖定", isOn: $profile.locked)
                Picker("壓縮範圍", selection: $profile.contextScope) {
                    ForEach(CompressionContextScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
            }
            Section("壓縮狀態") {
                TextEditor(text: $profile.summary).frame(minHeight: 120)
                Stepper("已壓縮到第 \(profile.compressedThroughTurnNumber) 回合", value: $profile.compressedThroughTurnNumber, in: 0...9999)
            }
            Section("規則與動作") {
                NavigationLink("壓縮 Prompt / 模型") {
                    CompressionContextEditorView(profile: $profile)
                }
                NavigationLink("觸發組合") {
                    TriggerActionListView(profile: $profile)
                }
                NavigationLink("首次觸發追加詞") {
                    AppendTermListView(profile: $profile)
                }
            }
        }
        .visualNovelListChrome()
        .navigationTitle(profile.name)
    }
}

struct CompressionContextEditorView: View {
    @Binding var profile: CompressionProfile

    var body: some View {
        Form {
            Section("壓縮主規則") {
                TextEditor(text: $profile.contextCompression.mainRules)
                    .frame(minHeight: 240)
            }
            Section("模塊") {
                ForEach($profile.contextCompression.models) { $model in
                    NavigationLink {
                        CompressionModelEditorView(model: $model)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name.isEmpty ? model.id : model.name)
                                .font(.headline)
                            Text(model.id)
                                .font(.caption)
                                .foregroundStyle(VNTheme.textSecondary)
                        }
                    }
                }
                .onDelete { offsets in
                    profile.contextCompression.models.remove(atOffsets: offsets)
                }
                Button {
                    profile.contextCompression.models.append(CompressionModel(name: "新模塊"))
                } label: {
                    Label("新增模塊", systemImage: "plus")
                }
            }
        }
        .visualNovelListChrome()
        .navigationTitle("壓縮 Prompt")
    }
}

struct CompressionModelEditorView: View {
    @Binding var model: CompressionModel

    var body: some View {
        Form {
            TextField("ID", text: $model.id)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("名稱", text: $model.name)
            Section("新增規則") {
                TextEditor(text: $model.addRules).frame(minHeight: 160)
            }
            Section("刪除規則") {
                TextEditor(text: $model.deleteRules).frame(minHeight: 160)
            }
        }
        .visualNovelListChrome()
        .navigationTitle(model.name.isEmpty ? "模塊" : model.name)
    }
}

struct TriggerActionListView: View {
    @Binding var profile: CompressionProfile

    var body: some View {
        List {
            ForEach($profile.triggerActions) { $action in
                NavigationLink {
                    TriggerActionEditorView(action: $action)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(action.name)
                            .font(.headline)
                        Text("\(action.action.rawValue) · \(action.keywordFollowupAction.title)")
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    }
                }
            }
            .onDelete { offsets in
                profile.triggerActions.remove(atOffsets: offsets)
            }
            Button {
                profile.triggerActions.append(CompressionTriggerAction())
            } label: {
                Label("新增觸發", systemImage: "plus")
            }
        }
        .visualNovelListChrome()
        .navigationTitle("觸發組合")
    }
}

struct TriggerActionEditorView: View {
    @Binding var action: CompressionTriggerAction

    var body: some View {
        Form {
            Section("動作") {
                TextField("名稱", text: $action.name)
                Toggle("啟用", isOn: $action.enabled)
                Picker("動作", selection: $action.action) {
                    ForEach(CompressionTriggerActionKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                Picker("關鍵字後續", selection: $action.keywordFollowupAction) {
                    ForEach(KeywordFollowupAction.allCases) { followup in
                        Text(followup.title).tag(followup)
                    }
                }
                Toggle("跳過正文 Reasoner", isOn: $action.skipReasoner)
            }
            Section("觸發條件") {
                Toggle("每輪觸發", isOn: $action.triggers.everyTurn)
                Toggle("達到上下文輪數觸發", isOn: $action.triggers.roundLimit)
                TextField("指定回合，用逗號分隔", text: intListBinding($action.triggers.turns))
                    .keyboardType(.numbersAndPunctuation)
                TextField("關鍵字，用逗號分隔", text: stringListBinding($action.triggers.keywords))
                TextField("關鍵字來源", text: $action.triggers.keywordSource)
            }
            Section("NovelAI Prompt Trigger") {
                Toggle("啟用 NovelAI Prompt", isOn: $action.novelAIEnabled)
                TextEditor(text: $action.novelAIPromptTemplate).frame(minHeight: 120)
                TextField("模型", text: $action.imageGeneration.model)
                Stepper("寬 \(action.imageGeneration.width)", value: $action.imageGeneration.width, in: 512...1536, step: 64)
                Stepper("高 \(action.imageGeneration.height)", value: $action.imageGeneration.height, in: 512...1536, step: 64)
            }
        }
        .visualNovelListChrome()
        .navigationTitle(action.name)
    }

    private func stringListBinding(_ binding: Binding<[String]>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue.joined(separator: ", ") },
            set: {
                binding.wrappedValue = $0
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func intListBinding(_ binding: Binding<[Int]>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue.map(String.init).joined(separator: ", ") },
            set: {
                binding.wrappedValue = $0
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
        )
    }
}

struct AppendTermListView: View {
    @Binding var profile: CompressionProfile

    var body: some View {
        Form {
            ForEach($profile.appendTerms) { $term in
                Section(term.player.isEmpty ? "追加詞" : term.player) {
                    TextField("玩家座位", text: $term.player)
                    TextEditor(text: $term.content).frame(minHeight: 80)
                    Toggle("啟用", isOn: $term.enabled)
                }
            }
            .onDelete { offsets in
                profile.appendTerms.remove(atOffsets: offsets)
            }
            Button("新增追加詞") { profile.appendTerms.append(CompressionAppendTerm()) }
        }
        .visualNovelListChrome()
        .navigationTitle("追加詞")
    }
}

struct PromptPreviewView: View {
    @EnvironmentObject private var store: TimeTavernStore
    var mode: PromptModeConfig

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VNGlassCard(cornerRadius: 20, accentOpacity: 0.28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("正文 system prompt")
                            .font(.headline)
                            .foregroundStyle(VNTheme.accentSoft)
                        Text(reasonerPreview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(mode.compressionProfiles) { profile in
                    VNGlassCard(cornerRadius: 20, accentOpacity: 0.24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("壓縮 prompt · \(profile.name)")
                                .font(.headline)
                                .foregroundStyle(VNTheme.accentSoft)
                            Text(ConversationEngine().compressionPromptPreview(mode: mode, profile: profile))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding()
        }
        .background(VisualNovelBackground())
        .navigationTitle("Preview")
    }

    private var reasonerPreview: String {
        var previewState = store.state
        var card = previewState.activeRoleCard ?? RoleCard(name: "Preview")
        card.promptModeId = mode.id
        card.mode = RoleCardMode(rawValue: mode.mode) ?? .custom
        if !previewState.roleCards.contains(where: { $0.id == card.id }) {
            previewState.roleCards = [card] + previewState.roleCards
        }
        previewState.activeRoleCardId = card.id
        previewState.promptModes = previewState.promptModes.map { $0.id == mode.id ? mode : $0 }
        if !previewState.promptModes.contains(where: { $0.id == mode.id }) {
            previewState.promptModes.append(mode)
        }
        return ConversationEngine().promptPreview(state: previewState, roleCard: card, input: "測試輸入")
    }
}

struct NovelAIView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var page: NovelAIStudioPage = .settings

    var body: some View {
        VStack(spacing: 10) {
            Picker("NovelAI", selection: $page) {
                ForEach(NovelAIStudioPage.allCases) { page in
                    Text(page.rawValue).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Group {
                switch page {
                case .settings:
                    NovelAISettingsPanel(settings: $store.state.novelAIStudioSettings)
                case .prompt:
                    NovelAIPromptPanel(settings: $store.state.novelAIStudioSettings)
                case .reference:
                    NovelAIReferencePanel(settings: $store.state.novelAIStudioSettings)
                case .output:
                    NovelAIOutputPanel(settings: $store.state.novelAIStudioSettings)
                case .history:
                    NovelAIHistoryPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(VisualNovelBackground())
        .onDisappear { store.persist() }
    }

    static func canGenerate(settings: NovelAIStudioSettings, key: String) -> Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !NovelAIClient.resolvedPrompt(from: settings, randomIndex: { _ in 0 }).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum NovelAIStudioPage: String, CaseIterable, Identifiable {
    case settings = "設定"
    case prompt = "Prompt"
    case reference = "Reference"
    case output = "Output"
    case history = "History"

    var id: String { rawValue }
}

struct NovelAISettingsPanel: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Binding var settings: NovelAIStudioSettings

    var body: some View {
        Form {
            Section("狀態") {
                Button("讀取 status / balance") { store.testNovelAI() }
                if !store.statusText.isEmpty {
                    Text(store.statusText)
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                }
            }
            Section("模型") {
                TextField("Model", text: $settings.imageSettings.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextEditor(text: $settings.modelDescription)
                    .frame(minHeight: 120)
            }
            Section("Base URLs") {
                TextField("Image API", text: $store.state.apiSettings.naiImageBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Primary API", text: $store.state.apiSettings.naiPrimaryBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .visualNovelListChrome()
    }
}

struct NovelAIPromptPanel: View {
    @Binding var settings: NovelAIStudioSettings

    var body: some View {
        Form {
            Section("Base Prompt") {
                TextEditor(text: $settings.basePrompt)
                    .frame(minHeight: 130)
            }
            Section("Negative Prompt") {
                TextEditor(text: $settings.negativePrompt)
                    .frame(minHeight: 90)
            }
            NovelAISnippetSection(title: "固定 Snippets", snippets: $settings.fixedSnippets)
            NovelAISnippetSection(title: "隨機 Snippets", snippets: $settings.randomSnippets)
            NovelAICharacterPromptSection(prompts: $settings.characterPrompts)
            Section("Resolved Preview") {
                Text(NovelAIClient.resolvedPrompt(from: settings, randomIndex: { _ in 0 }))
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
        .visualNovelListChrome()
    }
}

struct NovelAISnippetSection: View {
    var title: String
    @Binding var snippets: [NovelAIPromptSnippet]

    var body: some View {
        Section(title) {
            ForEach($snippets) { $snippet in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("名稱，可用 ||名稱|| 插入", text: $snippet.name)
                    TextEditor(text: $snippet.content).frame(minHeight: 80)
                    Toggle("啟用", isOn: $snippet.enabled)
                }
            }
            .onDelete { offsets in
                snippets.remove(atOffsets: offsets)
            }
            Button("新增") {
                snippets.append(NovelAIPromptSnippet(name: "snippet_\(snippets.count + 1)"))
            }
        }
    }
}

struct NovelAICharacterPromptSection: View {
    @Binding var prompts: [NovelAICharacterPrompt]

    var body: some View {
        Section("Character Prompts") {
            ForEach($prompts) { $prompt in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("角色名", text: $prompt.name)
                    TextEditor(text: $prompt.prompt).frame(minHeight: 90)
                    Toggle("啟用", isOn: $prompt.enabled)
                }
            }
            .onDelete { offsets in
                prompts.remove(atOffsets: offsets)
            }
            Button("新增角色 Prompt") {
                prompts.append(NovelAICharacterPrompt(name: "角色 \(prompts.count + 1)"))
            }
        }
    }
}

struct NovelAIReferencePanel: View {
    @Binding var settings: NovelAIStudioSettings

    var body: some View {
        Form {
            NovelAIReferenceSection(title: "Vibe Transfer", references: $settings.vibeTransferImages, type: "vibe")
            Section("Image2Image") {
                ImagePickerButton(title: settings.imageToImageImageData == nil ? "選擇底圖" : "更換底圖") { data in
                    settings.imageToImageImageData = data
                }
                if let data = settings.imageToImageImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Button(role: .destructive) {
                        settings.imageToImageImageData = nil
                    } label: {
                        Label("移除 Image2Image", systemImage: "trash")
                    }
                }
                Slider(value: $settings.imageToImageStrength, in: 0...1) {
                    Text("Strength")
                }
                Text("Strength \(settings.imageToImageStrength, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $settings.imageToImageNoise, in: 0...1) {
                    Text("Noise")
                }
                Text("Noise \(settings.imageToImageNoise, specifier: "%.2f")")
                    .font(.caption)
            }
            NovelAIReferenceSection(title: "Precise Reference", references: $settings.preciseReferenceImages, type: "precise")
        }
        .visualNovelListChrome()
    }
}

struct NovelAIReferenceSection: View {
    var title: String
    @Binding var references: [NovelAIReferenceImage]
    var type: String

    var body: some View {
        Section(title) {
            ForEach($references) { $reference in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("名稱", text: $reference.name)
                    Toggle("啟用", isOn: $reference.enabled)
                    Slider(value: $reference.strength, in: 0...1) { Text("Strength") }
                    Text("Strength \(reference.strength, specifier: "%.2f")")
                        .font(.caption)
                    Slider(value: $reference.noise, in: 0...1) { Text("Information") }
                    Text("Information \(reference.noise, specifier: "%.2f")")
                        .font(.caption)
                    if let data = reference.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    ImagePickerButton(title: reference.imageData == nil ? "選擇圖片" : "更換圖片") { data in
                        reference.imageData = data
                    }
                }
            }
            .onDelete { offsets in
                references.remove(atOffsets: offsets)
            }
            Button("新增 Reference") {
                references.append(NovelAIReferenceImage(name: "\(title) \(references.count + 1)", type: type))
            }
        }
    }
}

struct ImagePickerButton: View {
    var title: String
    var onData: (Data) -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Label(title, systemImage: "photo")
        }
        .onChange(of: item) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    await MainActor.run { onData(data) }
                }
            }
        }
    }
}

struct NovelAIOutputPanel: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Binding var settings: NovelAIStudioSettings

    var body: some View {
        Form {
            Section("尺寸") {
                Picker("Preset", selection: $settings.sizePreset) {
                    Text("Portrait").tag("portrait")
                    Text("Landscape").tag("landscape")
                    Text("Square").tag("square")
                    Text("Custom").tag("custom")
                }
                .onChange(of: settings.sizePreset) { _, value in
                    applySizePreset(value)
                }
                Stepper("寬 \(settings.imageSettings.width)", value: $settings.imageSettings.width, in: 512...1536, step: 64)
                Stepper("高 \(settings.imageSettings.height)", value: $settings.imageSettings.height, in: 512...1536, step: 64)
                Stepper("Samples \(settings.imageSettings.samples)", value: $settings.imageSettings.samples, in: 1...8)
            }
            Section("AI Settings") {
                Stepper("Steps \(settings.imageSettings.steps)", value: $settings.imageSettings.steps, in: 1...50)
                Slider(value: $settings.imageSettings.scale, in: 1...12) { Text("Guidance") }
                Text("Guidance \(settings.imageSettings.scale, specifier: "%.1f")")
                    .font(.caption)
                Slider(value: $settings.imageSettings.cfgRescale, in: 0...1.5) { Text("CFG Rescale") }
                Text("CFG Rescale \(settings.imageSettings.cfgRescale, specifier: "%.2f")")
                    .font(.caption)
                TextField("Sampler", text: $settings.imageSettings.sampler)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Noise Schedule", text: $settings.imageSettings.noiseSchedule)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("Variety+", isOn: $settings.imageSettings.varietyPlus)
                TextField("Seed", text: seedBinding)
                    .keyboardType(.numberPad)
                Stepper("Loop \(settings.loopCount)", value: $settings.loopCount, in: 1...20)
            }
            Section("Metadata Import") {
                TextEditor(text: $settings.metadataDraft)
                    .frame(minHeight: 110)
                Button("套用 Metadata") {
                    settings = NovelAIClient.settingsByImportingMetadata(settings.metadataDraft, into: settings)
                }
            }
            Section("Generate") {
                Button {
                    store.generateNovelAIImage(studioSettings: settings)
                } label: {
                    Label("生成圖片", systemImage: "sparkles")
                }
                .disabled(!NovelAIView.canGenerate(settings: settings, key: store.novelAIKey))
            }
        }
        .visualNovelListChrome()
    }

    private var seedBinding: Binding<String> {
        Binding(
            get: { settings.imageSettings.seed.map(String.init) ?? "" },
            set: { settings.imageSettings.seed = Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    private func applySizePreset(_ preset: String) {
        switch preset {
        case "portrait":
            settings.imageSettings.width = 832
            settings.imageSettings.height = 1216
        case "landscape":
            settings.imageSettings.width = 1216
            settings.imageSettings.height = 832
        case "square":
            settings.imageSettings.width = 1024
            settings.imageSettings.height = 1024
        default:
            break
        }
    }
}

struct NovelAIHistoryPanel: View {
    @EnvironmentObject private var store: TimeTavernStore

    var body: some View {
        List {
            ForEach(store.state.novelAIAlbum) { item in
                VStack(alignment: .leading, spacing: 8) {
                    if let image = UIImage(data: item.imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Text(item.prompt)
                        .font(.caption)
                        .lineLimit(4)
                    HStack {
                        Text(item.model)
                            .font(.caption2)
                            .foregroundStyle(VNTheme.textSecondary)
                        Spacer()
                        if let url = Self.exportURL(for: item) {
                            ShareLink(item: url) {
                                Label("匯出", systemImage: "square.and.arrow.up")
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .onDelete(perform: store.deleteNovelAIAlbumItems)
        }
        .visualNovelListChrome()
    }

    private static func exportURL(for item: NovelAIAlbumItem) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.fileName)
        try? item.imageData.write(to: url)
        return url
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var showImporter = false
    @State private var showRestoreDefaultsConfirm = false

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
                Section("網頁預設") {
                    if let summary = store.bundledWebDefaultsSummary() {
                        Text("可還原 \(summary.roleCardCount) 張角色卡、\(summary.promptModeCount) 個 Prompt 模式。使用者：\(summary.userDisplayName)。")
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    } else {
                        Text("找不到 bundle 內的網頁預設。")
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    }
                    Button(role: .destructive) {
                        showRestoreDefaultsConfirm = true
                    } label: {
                        Label("還原網頁預設", systemImage: "arrow.counterclockwise")
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
            .alert("還原網頁預設？", isPresented: $showRestoreDefaultsConfirm) {
                Button("取消", role: .cancel) {}
                Button("還原", role: .destructive) {
                    store.restoreBundledWebDefaults()
                }
            } message: {
                Text("會覆蓋角色卡、Prompt 模式、使用者資料與時間追蹤；Keychain、相簿、AI logs、saved sessions 會保留，並建立還原前備份。")
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
