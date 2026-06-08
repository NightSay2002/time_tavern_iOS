import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum AppTab: String, CaseIterable, Identifiable, Hashable {
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

    func title(in language: UILanguageMode) -> String {
        UIChineseTextConverter.convert(title, language: language)
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
    @State private var tabBarVisible = false
    @State private var tabResetIDs = TabResetIDs()
    static let usesCustomTabContentHost = true
    static let tabBarHiddenByDefault = true
    static let repeatedTabTapResetsCurrentTab = true
    private var shouldShowTabBar: Bool {
        Self.shouldDisplayTabBar(selectedTab: selectedTab, tabBarVisible: tabBarVisible)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                VisualNovelBackground()
                TabContentHost(selectedTab: selectedTab, resetIDs: tabResetIDs)
                    .padding(.bottom, shouldShowTabBar ? VisualNovelTabBar.contentAvoidanceHeight : 0)
                    .animation(.spring(response: 0.34, dampingFraction: 0.88), value: shouldShowTabBar)
                if shouldShowTabBar {
                    VisualNovelTabBar(
                        selectedTab: $selectedTab,
                        onSelect: { tab, wasSelected in
                            if Self.shouldResetTabAfterTap(wasSelected: wasSelected) {
                                tabResetIDs.reset(tab)
                            }
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                tabBarVisible = Self.tabBarVisibleAfterSelecting(tab)
                            }
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 24).onEnded { value in
                    if Self.shouldRevealTabBar(
                        from: selectedTab,
                        startY: value.startLocation.y,
                        containerHeight: proxy.size.height,
                        translation: value.translation
                    ) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                            tabBarVisible = true
                        }
                    } else if Self.shouldHideTabBar(
                        from: selectedTab,
                        isVisible: tabBarVisible,
                        translation: value.translation
                    ) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                            tabBarVisible = false
                        }
                    }
                }
            )
        }
        .preferredColorScheme(.dark)
        .background(GlobalKeyboardDismissInstaller().frame(width: 0, height: 0))
        .task {
            store.attach(modelContext: modelContext)
            UIChineseTextConverter.activeLanguage = store.state.uiLanguage
        }
        .onChange(of: store.state.uiLanguage) { _, language in
            UIChineseTextConverter.activeLanguage = language
        }
    }

    static func shouldDisplayTabBar(selectedTab: AppTab, tabBarVisible: Bool) -> Bool {
        selectedTab != .chat || tabBarVisible
    }

    static func tabBarVisibleAfterSelecting(_ tab: AppTab) -> Bool {
        tab != .chat
    }

    static func shouldResetTabAfterTap(wasSelected: Bool) -> Bool {
        wasSelected
    }

    static func shouldRevealTabBar(from selectedTab: AppTab, startY: CGFloat, containerHeight: CGFloat, translation: CGSize) -> Bool {
        selectedTab == .chat && shouldRevealTabBar(startY: startY, containerHeight: containerHeight, translation: translation)
    }

    static func shouldHideTabBar(from selectedTab: AppTab, isVisible: Bool, translation: CGSize) -> Bool {
        selectedTab == .chat && shouldHideTabBar(isVisible: isVisible, translation: translation)
    }

    static func shouldRevealTabBar(startY: CGFloat, containerHeight: CGFloat, translation: CGSize) -> Bool {
        let startsNearBottom = startY >= containerHeight - 96
        let swipesUp = translation.height <= -28
        let mostlyVertical = abs(translation.height) > abs(translation.width) * 0.8
        return startsNearBottom && swipesUp && mostlyVertical
    }

    static func shouldHideTabBar(isVisible: Bool, translation: CGSize) -> Bool {
        isVisible && translation.height >= 32 && abs(translation.height) > abs(translation.width) * 0.8
    }
}

struct GlobalKeyboardDismissInstaller: UIViewRepresentable {
    static let dismissesKeyboardOnNonInputTap = true
    static let preservesEditableInputTouches = true

    func makeCoordinator() -> KeyboardDismissTapDelegate {
        KeyboardDismissTapDelegate()
    }

    func makeUIView(context: Context) -> KeyboardDismissInstallingView {
        KeyboardDismissInstallingView(tapDelegate: context.coordinator)
    }

    func updateUIView(_ uiView: KeyboardDismissInstallingView, context: Context) {
        uiView.tapDelegate = context.coordinator
        uiView.installIfNeeded()
    }
}

final class KeyboardDismissInstallingView: UIView {
    var tapDelegate: KeyboardDismissTapDelegate
    private weak var installedWindow: UIWindow?
    private var tapGesture: UITapGestureRecognizer?

    init(tapDelegate: KeyboardDismissTapDelegate) {
        self.tapDelegate = tapDelegate
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    func installIfNeeded() {
        guard let window else { return }
        guard installedWindow !== window else { return }
        if let installedWindow, let tapGesture {
            installedWindow.removeGestureRecognizer(tapGesture)
        }
        let gesture = UITapGestureRecognizer(target: tapDelegate, action: #selector(KeyboardDismissTapDelegate.handleTap(_:)))
        gesture.cancelsTouchesInView = false
        gesture.delegate = tapDelegate
        window.addGestureRecognizer(gesture)
        installedWindow = window
        tapGesture = gesture
    }

    deinit {
        if let installedWindow, let tapGesture {
            installedWindow.removeGestureRecognizer(tapGesture)
        }
    }
}

final class KeyboardDismissTapDelegate: NSObject, UIGestureRecognizerDelegate {
    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !Self.isEditableTextInputView(touch.view)
    }

    static func isEditableTextInputView(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UITextField {
                return true
            }
            if let textView = candidate as? UITextView, textView.isEditable {
                return true
            }
            current = candidate.superview
        }
        return false
    }
}

struct ImagePreviewItem: Identifiable {
    let id = UUID()
    var title: String
    var imageData: Data
}

struct GeneratedImagePreview: View {
    @Environment(\.dismiss) private var dismiss
    let item: ImagePreviewItem
    static let showsCloseButton = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = UIImage(data: item.imageData) {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .accessibilityLabel(item.title.isEmpty ? uiStatic("放大圖片") : item.title)
                }
            } else {
                Text(uiStatic("圖片無法顯示"))
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.58), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.trailing, 18)
            .accessibilityLabel(uiStatic("關閉"))
        }
    }
}

struct GeneratedImageZoomBadge: View {
    var body: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 12, weight: .bold))
            .frame(width: 28, height: 28)
            .foregroundStyle(.white)
            .background(.black.opacity(0.54), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

struct TabResetIDs: Equatable {
    private var chat = UUID()
    private var characters = UUID()
    private var archive = UUID()
    private var studio = UUID()
    private var settings = UUID()

    subscript(tab: AppTab) -> UUID {
        switch tab {
        case .chat:
            chat
        case .characters:
            characters
        case .archive:
            archive
        case .studio:
            studio
        case .settings:
            settings
        }
    }

    mutating func reset(_ tab: AppTab) {
        let next = UUID()
        switch tab {
        case .chat:
            chat = next
        case .characters:
            characters = next
        case .archive:
            archive = next
        case .studio:
            studio = next
        case .settings:
            settings = next
        }
    }
}

struct TabContentHost: View {
    let selectedTab: AppTab
    let resetIDs: TabResetIDs
    static let keepsInactiveTabsMounted = true
    static let resetsOnlyRepeatedlyTappedTab = true

    var body: some View {
        ZStack {
            tabLayer(.chat) {
                ChatView()
            }
            tabLayer(.characters) {
                CharactersView()
            }
            tabLayer(.archive) {
                ArchiveView()
            }
            tabLayer(.studio) {
                StudioView()
            }
            tabLayer(.settings) {
                SettingsView()
            }
        }
        .tint(VNTheme.accent)
    }

    private func tabLayer<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .id(resetIDs[tab])
            .opacity(Self.opacity(for: tab, selectedTab: selectedTab))
            .allowsHitTesting(Self.isInteractive(tab, selectedTab: selectedTab))
            .accessibilityHidden(!Self.isInteractive(tab, selectedTab: selectedTab))
            .zIndex(Self.zIndex(for: tab, selectedTab: selectedTab))
    }

    static func isInteractive(_ tab: AppTab, selectedTab: AppTab) -> Bool {
        tab == selectedTab
    }

    static func opacity(for tab: AppTab, selectedTab: AppTab) -> Double {
        isInteractive(tab, selectedTab: selectedTab) ? 1 : 0
    }

    static func zIndex(for tab: AppTab, selectedTab: AppTab) -> Double {
        isInteractive(tab, selectedTab: selectedTab) ? 1 : 0
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
            .background(VNGlassRoundedBackground(cornerRadius: cornerRadius, fill: VNTheme.panel.opacity(0.66), materialOpacity: 0.34))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

struct VNGlassRoundedBackground: View {
    var cornerRadius: CGFloat
    var fill: Color
    var materialOpacity: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(materialOpacity)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct VNGlassCapsuleBackground: View {
    var fill: Color
    var materialOpacity: Double

    var body: some View {
        ZStack {
            Capsule()
                .fill(fill)
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(materialOpacity)
        }
        .clipShape(Capsule())
    }
}

struct VisualNovelTabBar: View {
    @Binding var selectedTab: AppTab
    var onSelect: (AppTab, Bool) -> Void = { _, _ in }
    @EnvironmentObject private var store: TimeTavernStore
    static let clipsBackgroundToRoundedShape = true
    static let reservesContentAboveBottomBar = true
    static let contentAvoidanceHeight: CGFloat = 104
    static let reportsRepeatedTabSelection = true

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    let wasSelected = Self.wasAlreadySelected(tab, selectedTab: selectedTab)
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                    onSelect(tab, wasSelected)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.title(in: store.state.uiLanguage))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .foregroundStyle(selectedTab == tab ? VNTheme.accentSoft : VNTheme.textSecondary.opacity(0.78))
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(VNTheme.accent.opacity(0.18))
                                .shadow(color: VNTheme.accent.opacity(0.58), radius: 16, y: 0)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }
        .padding(6)
        .background(VNGlassRoundedBackground(cornerRadius: 28, fill: VNTheme.ink.opacity(0.78), materialOpacity: 0.20))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    static func wasAlreadySelected(_ tab: AppTab, selectedTab: AppTab) -> Bool {
        tab == selectedTab
    }
}

struct ChatView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var showLogs = false
    @State private var showModelContent = false
    @State private var showRunTime = false
    @State private var replayMessage: ConversationMessage?
    @State private var replayText = ""
    @State private var editingMessage: ConversationMessage?
    @State private var editText = ""
    @State private var showRegenerateConfirmation = false
    @State private var previewImage: ImagePreviewItem?
    @FocusState private var composerFocused: Bool

    static func shouldDismissComposerOnOutsideTap(isFocused: Bool) -> Bool {
        isFocused
    }
    static let composerBottomPadding: CGFloat = 16
    static let requiresRegenerateConfirmation = true

    var body: some View {
        NavigationStack {
            ZStack {
                VisualNovelBackground()
                VStack(spacing: 0) {
                    ChatSceneHeader(
                        isGenerating: store.isGenerating,
                        showModelContent: {
                            dismissComposerInput()
                            showModelContent = true
                        },
                        showRunTime: {
                            dismissComposerInput()
                            showRunTime = true
                        },
                        regenerate: {
                            dismissComposerInput()
                            showRegenerateConfirmation = true
                        },
                        showLogs: {
                            dismissComposerInput()
                            showLogs = true
                        }
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                    ZStack {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(store.state.conversation) { message in
                                        MessageRow(
                                            message: message,
                                            edit: {
                                                editingMessage = message
                                                editText = message.content
                                            },
                                            replay: {
                                                replayMessage = message
                                                replayText = message.content
                                            },
                                            setFeedback: { feedback in
                                                store.setMessageFeedback(id: message.id, feedback: feedback)
                                            },
                                            previewImage: { imageData in
                                                previewImage = ImagePreviewItem(title: uiStatic("生成圖片"), imageData: imageData)
                                            }
                                        )
                                            .id(message.id)
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
                            .scrollDismissesKeyboard(.interactively)
                        }
                        if store.state.conversation.isEmpty {
                            EmptyStoryHintCard()
                                .padding(.horizontal, 34)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { _ in dismissComposerInput() })

                    VisualNovelComposer(inputFocused: $composerFocused)
                        .padding(.horizontal, 16)
                        .padding(.bottom, Self.composerBottomPadding)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showLogs) { LogView() }
            .sheet(isPresented: $showModelContent) { ModelContentView() }
            .sheet(isPresented: $showRunTime) { RunTimeView() }
            .confirmationDialog(
                uiStatic("重新生成最新回覆？"),
                isPresented: $showRegenerateConfirmation,
                titleVisibility: .visible
            ) {
                Button(uiStatic("重新生成"), role: .destructive) {
                    store.regenerateLatestAssistant()
                }
                Button(uiStatic("取消"), role: .cancel) {}
            } message: {
                Text(uiStatic("會刪除最新 AI 回覆並重新生成，不會立刻執行。"))
            }
            .fullScreenCover(item: $previewImage) { item in
                GeneratedImagePreview(item: item)
            }
            .sheet(item: $replayMessage) { message in
                NavigationStack {
                    Form {
                        TextEditor(text: $replayText)
                            .frame(minHeight: 180)
                    }
                    .visualNovelListChrome()
                    .navigationTitle(uiStatic("分支重跑"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(uiStatic("取消")) { replayMessage = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(uiStatic("重跑")) {
                                store.replay(from: message, with: replayText)
                                replayMessage = nil
                            }
                        }
                    }
                }
            }
            .sheet(item: $editingMessage) { message in
                NavigationStack {
                    Form {
                        TextEditor(text: $editText)
                            .frame(minHeight: 180)
                    }
                    .visualNovelListChrome()
                    .navigationTitle(uiStatic("編輯訊息"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(uiStatic("取消")) { editingMessage = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(uiStatic("保存")) {
                                store.updateMessage(id: message.id, content: editText)
                                editingMessage = nil
                            }
                        }
                    }
                }
            }
        }
    }

    private func dismissComposerInput() {
        guard Self.shouldDismissComposerOnOutsideTap(isFocused: composerFocused) else { return }
        composerFocused = false
    }
}

struct ChatSceneHeader: View {
    @EnvironmentObject private var store: TimeTavernStore
    var isGenerating: Bool
    var showModelContent: () -> Void
    var showRunTime: () -> Void
    var regenerate: () -> Void
    var showLogs: () -> Void
    static let hidesStaticAppTitle = true

    static func isTopActionDisabled(isGenerating: Bool) -> Bool {
        isGenerating
    }

    static func sessionTitle(activeRoleCard: RoleCard?, activeAssistantCard: AssistantCard?) -> String {
        activeRoleCard?.name.nonEmpty ?? activeAssistantCard?.displayName ?? uiStatic("尚未開始角色卡")
    }

    static func modelSubtitle(model: String) -> String {
        "DeepSeek \(model)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CharacterAvatarView(
                imageData: store.state.activeRoleCard?.coverImageData,
                fallbackSystemImage: store.state.activeAssistantCard == nil ? "moon.stars.fill" : "wand.and.stars",
                size: 50,
                cornerRadius: 15
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.sessionTitle(activeRoleCard: store.state.activeRoleCard, activeAssistantCard: store.state.activeAssistantCard))
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                    .shadow(color: VNTheme.accent.opacity(0.55), radius: 12, y: 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(Self.modelSubtitle(model: store.state.apiSettings.deepSeekModel))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VNTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                HeaderIconButton(systemImage: "doc.text.magnifyingglass", action: showModelContent, label: uiStatic("模型內容"), disabled: Self.isTopActionDisabled(isGenerating: isGenerating))
                HeaderIconButton(systemImage: "forward.frame.fill", action: showRunTime, label: uiStatic("自動推演"), disabled: Self.isTopActionDisabled(isGenerating: isGenerating))
                HeaderIconButton(systemImage: "arrow.clockwise", action: regenerate, label: uiStatic("重新生成"), disabled: Self.isTopActionDisabled(isGenerating: isGenerating))
                HeaderIconButton(systemImage: "waveform.path.ecg", action: showLogs, label: "AI Logs", disabled: Self.isTopActionDisabled(isGenerating: isGenerating))
            }
            .padding(5)
            .background(VNGlassCapsuleBackground(fill: VNTheme.ink.opacity(0.66), materialOpacity: 0.22))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: VNTheme.ink.opacity(0.4), radius: 18, y: 10)
        }
    }
}

struct HeaderIconButton: View {
    var systemImage: String
    var action: () -> Void
    var label: String
    var disabled = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 31, height: 31)
                .foregroundStyle(disabled ? VNTheme.textSecondary.opacity(0.45) : VNTheme.accentSoft)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .accessibilityLabel(label)
    }
}

#Preview("Chat Header") {
    let store = TimeTavernStore()
    var card = RoleCard(name: "千夜")
    card.promptModeId = "multi"
    store.state.roleCards = [card]
    store.state.activeRoleCardId = card.id
    store.state.apiSettings.deepSeekModel = "deepseek-reasoner"

    return ZStack {
        VisualNovelBackground()
        ChatSceneHeader(
            isGenerating: false,
            showModelContent: {},
            showRunTime: {},
            regenerate: {},
            showLogs: {}
        )
        .padding(18)
    }
    .environmentObject(store)
    .preferredColorScheme(.dark)
}

struct CharacterStatusCard: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var appeared = false

    var activeCard: RoleCard? { store.state.activeRoleCard }
    var activeAssistantCard: AssistantCard? { store.state.activeAssistantCard }
    var ready: Bool { activeCard != nil || activeAssistantCard != nil }
    var displayName: String { activeCard?.name.nonEmpty ?? activeAssistantCard?.displayName ?? uiStatic("尚未開始角色卡") }

    static func statusTitle(isReady: Bool) -> String {
        isReady ? "Ready" : "Idle"
    }

    var body: some View {
        VNGlassCard(cornerRadius: 20, accentOpacity: 0.62) {
            HStack(spacing: 12) {
                CharacterAvatarView(
                    imageData: activeCard?.coverImageData,
                    fallbackSystemImage: activeAssistantCard == nil ? "moon.stars.fill" : "wand.and.stars"
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(displayName)
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
    var fallbackSystemImage: String = "moon.stars.fill"
    var size: CGFloat = 54
    var cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(VNTheme.accentSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(VNTheme.accent.opacity(0.38), lineWidth: 1)
        )
    }
}

struct EmptyStoryHintCard: View {
    var body: some View {
        VNGlassCard(cornerRadius: 24, accentOpacity: 0.46) {
            VStack(spacing: 8) {
                Text(uiStatic("尚未開始故事"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(uiStatic("選擇角色卡或直接輸入內容開始。"))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VNTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }
}

struct MessageRow: View {
    var message: ConversationMessage
    var edit: () -> Void
    var replay: () -> Void
    var setFeedback: (String) -> Void
    var previewImage: (Data) -> Void = { _ in }

    static let usesInlineActionButtons = true
    static let removesLongPressContextMenu = true

    var body: some View {
        VStack(spacing: 4) {
            MessageBubble(message: message, previewImage: previewImage)
            MessageActionBar(
                message: message,
                edit: edit,
                replay: replay,
                setFeedback: setFeedback
            )
        }
    }
}

struct MessageActionBar: View {
    var message: ConversationMessage
    var edit: () -> Void
    var replay: () -> Void
    var setFeedback: (String) -> Void

    static let usesEmojiFeedbackIcons = true

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            HStack(spacing: 6) {
                tinyIconButton(systemImage: "pencil", label: uiStatic("編輯內容"), action: edit)
                tinyIconButton(systemImage: "arrow.uturn.right", label: uiStatic("從此分支重跑"), action: replay)
                if message.role == .assistant {
                    emojiFeedbackButton(emoji: Self.feedbackEmoji(for: "like"), feedback: "like", label: uiStatic("喜歡"))
                    emojiFeedbackButton(emoji: Self.feedbackEmoji(for: "dislike"), feedback: "dislike", label: uiStatic("不喜歡"))
                    if !Self.normalizedFeedback(message.feedback).isEmpty {
                        tinyIconButton(systemImage: "xmark", label: uiStatic("清除評價")) {
                            setFeedback("")
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(VNTheme.ink.opacity(0.34), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            if message.role != .user { Spacer(minLength: 40) }
        }
        .font(.caption2.weight(.semibold))
    }

    static func feedbackEmoji(for feedback: String) -> String {
        normalizedFeedback(feedback) == "dislike" ? "👎" : "👍"
    }

    static func normalizedFeedback(_ feedback: String) -> String {
        TimeTavernStore.normalizedMessageFeedback(feedback)
    }

    private func tinyIconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .foregroundStyle(VNTheme.textSecondary.opacity(0.82))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func emojiFeedbackButton(emoji: String, feedback: String, label: String) -> some View {
        let isSelected = Self.normalizedFeedback(message.feedback) == feedback
        return Button {
            setFeedback(isSelected ? "" : feedback)
        } label: {
            Text(emoji)
                .font(.system(size: 12))
                .frame(width: 22, height: 22)
                .background(isSelected ? VNTheme.accent.opacity(0.26) : Color.clear, in: Circle())
                .overlay(Circle().stroke(isSelected ? VNTheme.accentSoft.opacity(0.8) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct MessageBubble: View {
    var message: ConversationMessage
    var previewImage: (Data) -> Void = { _ in }
    static let usesPartialTextSelectableView = true
    static let generatedImagesOpenPreviewOnTap = true

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                Text(message.role == .user ? uiStatic("你") : uiStatic("角色"))
                    .font(.caption.bold())
                    .foregroundStyle(VNTheme.accentSoft)
                if message.compressionNotice {
                    Label(uiStatic("模型內容已更新"), systemImage: "tray.and.arrow.down.fill")
                        .font(.caption)
                        .foregroundStyle(VNTheme.accentSoft)
                }
                SelectableMessageText(text: message.content.isEmpty ? uiStatic("生成中...") : message.content)
                if let imageData = message.imageData, let image = UIImage(data: imageData) {
                    Button {
                        previewImage(imageData)
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                                )
                            GeneratedImageZoomBadge()
                                .padding(8)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(uiStatic("放大生成圖片"))
                }
                if !message.autoTimeWarning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(message.autoTimeWarning, systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(VNTheme.accentSoft)
                }
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

struct SelectableMessageText: UIViewRepresentable {
    var text: String
    static let supportsPartialTextSelection = true
    static let isEditable = false

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.dataDetectorTypes = []
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textDragInteraction?.isEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        applyStyle(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        applyStyle(to: textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let maxWidth = max(1, proposal.width ?? UIScreen.main.bounds.width - 104)
        let fittingHeight = uiView.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude)).height
        let measuredWidth = Self.measuredTextWidth(text, font: uiView.font ?? .preferredFont(forTextStyle: .body), maxWidth: maxWidth)
        return CGSize(width: measuredWidth, height: fittingHeight)
    }

    private func applyStyle(to textView: UITextView) {
        textView.textColor = .white
        textView.tintColor = UIColor(red: 1.0, green: 0.50, blue: 0.72, alpha: 1.0)
        textView.font = .preferredFont(forTextStyle: .body)
    }

    static func measuredTextWidth(_ text: String, font: UIFont, maxWidth: CGFloat) -> CGFloat {
        let value = text.isEmpty ? " " : text
        let rect = (value as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return min(max(ceil(rect.width) + 1, 1), maxWidth)
    }
}

struct VisualNovelComposer: View {
    @EnvironmentObject private var store: TimeTavernStore
    @FocusState.Binding var inputFocused: Bool
    static let showsPlusInsertMenu = true
    static let quickInsertItems: [ComposerInsertItem] = [
        ComposerInsertItem(title: "繼續", text: "｛繼續｝", systemImage: "arrow.forward.circle"),
        ComposerInsertItem(title: "動作括號", text: "（）", systemImage: "textformat"),
        ComposerInsertItem(title: "推進場景", text: "｛推进剧情到下一个场景｝", systemImage: "arrow.right"),
        ComposerInsertItem(title: "時間流逝", text: "｛时间流逝——｝", systemImage: "clock")
    ]
    static let slashCommandItems: [ComposerInsertItem] = [
        ComposerInsertItem(title: "開始對話", text: "/ai_start", systemImage: "play.fill"),
        ComposerInsertItem(title: "目前狀態", text: "/ai_status", systemImage: "info.circle"),
        ComposerInsertItem(title: "停止生成", text: "/stop", systemImage: "stop.fill"),
        ComposerInsertItem(title: "重跑最新回覆", text: "/reload ", systemImage: "arrow.clockwise"),
        ComposerInsertItem(title: "分支重跑提示", text: "/replay ", systemImage: "arrow.uturn.right"),
        ComposerInsertItem(title: "自動推演", text: "/run_time 3 請根據目前劇情自然推進。", systemImage: "forward.frame.fill"),
        ComposerInsertItem(title: "保存對話", text: "/session_save ", systemImage: "tray.and.arrow.down.fill"),
        ComposerInsertItem(title: "列出存檔", text: "/session_list", systemImage: "archivebox.fill"),
        ComposerInsertItem(title: "載入存檔", text: "/session_load ", systemImage: "folder.fill"),
        ComposerInsertItem(title: "指令說明", text: "/ai_help", systemImage: "questionmark.circle")
    ]

    static func isSendDisabled(isGenerating: Bool, text: String) -> Bool {
        !isGenerating && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func shouldDismissInputAfterPrimaryAction(isGenerating: Bool, text: String) -> Bool {
        !isGenerating && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var sendDisabled: Bool {
        Self.isSendDisabled(isGenerating: store.isGenerating, text: store.composerText)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Menu {
                Section(uiStatic("快速輸入")) {
                    ForEach(Self.quickInsertItems) { item in
                        Button {
                            insert(item.text)
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                }
                Section(uiStatic("/ 指令")) {
                    ForEach(Self.slashCommandItems) { item in
                        Button {
                            insert(item.text)
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 40, height: 44)
                    .foregroundStyle(VNTheme.accentSoft)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(uiStatic("插入快捷內容"))

            TextField(uiStatic("輸入對話"), text: $store.composerText, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .font(.body)
                .foregroundStyle(.white)
                .tint(VNTheme.accentSoft)
                .padding(.vertical, 8)
            Button {
                if store.isGenerating {
                    store.cancelGeneration()
                } else {
                    let shouldDismissInput = Self.shouldDismissInputAfterPrimaryAction(
                        isGenerating: store.isGenerating,
                        text: store.composerText
                    )
                    store.sendCurrentMessage()
                    if shouldDismissInput {
                        inputFocused = false
                    }
                }
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
        .background(VNGlassRoundedBackground(cornerRadius: 28, fill: VNTheme.ink.opacity(0.82), materialOpacity: 0.20))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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

    private func insert(_ text: String) {
        store.composerText = Self.composerTextByInserting(current: store.composerText, insertion: text)
        inputFocused = true
    }

    static func composerTextByInserting(current: String, insertion: String) -> String {
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return insertion
        }
        if current.hasSuffix("\n") {
            return current + insertion
        }
        return current + "\n" + insertion
    }
}

struct ComposerInsertItem: Identifiable, Hashable {
    var title: String
    var text: String
    var systemImage: String
    var id: String { text }
}

struct CharactersView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var editingCard: RoleCard?
    @State private var showAssistantPromptEditor = false
    @State private var query = ""
    static let separatesRoleCardsAndAssistantCards = true

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
                        Label(uiStatic("建立角色卡"), systemImage: "plus")
                    }
                }
                Section(uiStatic("助手卡")) {
                    ForEach(AssistantCard.allCards) { assistantCard in
                        VStack(alignment: .leading, spacing: 10) {
                            AssistantCardRow(
                                assistantCard: assistantCard,
                                isActive: store.state.activeAssistantMode == assistantCard.id
                            )
                            HStack {
                                Button {
                                    store.start(assistantCard: assistantCard)
                                } label: {
                                    Label(uiStatic("啟用助手"), systemImage: "play.fill")
                                }
                                Button {
                                    showAssistantPromptEditor = true
                                } label: {
                                    Label(uiStatic("編輯 Prompt"), systemImage: "square.and.pencil")
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .swipeActions {
                            Button(uiStatic("啟用")) { store.start(assistantCard: assistantCard) }.tint(VNTheme.accent)
                            Button("Prompt") { showAssistantPromptEditor = true }.tint(Color(red: 0.36, green: 0.42, blue: 1.0))
                        }
                        .contextMenu {
                            Button(uiStatic("啟用助手")) { store.start(assistantCard: assistantCard) }
                            Button(uiStatic("編輯助手 Prompt")) { showAssistantPromptEditor = true }
                        }
                    }
                }
                Section(uiStatic("角色卡")) {
                    if filteredCards.isEmpty {
                        Text(store.state.roleCards.isEmpty ? uiStatic("尚無角色卡；可先使用上方建立卡助手。") : uiStatic("沒有符合搜尋的角色卡。"))
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    } else {
                        ForEach(filteredCards) { card in
                            RoleCardRow(card: card, isActive: card.id == store.state.activeRoleCardId)
                                .swipeActions {
                                    Button(uiStatic("開始")) { store.start(roleCard: card) }.tint(VNTheme.accent)
                                    Button(uiStatic("編輯")) { editingCard = card }.tint(Color(red: 0.36, green: 0.42, blue: 1.0))
                                }
                                .onTapGesture { editingCard = card }
                        }
                        .onDelete(perform: deleteFilteredRoleCards)
                    }
                }
            }
            .visualNovelListChrome()
            .searchable(text: $query, prompt: uiStatic("搜尋角色"))
            .navigationTitle(uiStatic("角色"))
            .sheet(item: $editingCard) { card in
                RoleCardEditorView(card: card)
            }
            .sheet(isPresented: $showAssistantPromptEditor) {
                AssistantPromptEditorView()
            }
        }
    }

    private func deleteFilteredRoleCards(at offsets: IndexSet) {
        let ids = offsets.compactMap { filteredCards.indices.contains($0) ? filteredCards[$0].id : nil }
        let roleOffsets = IndexSet(ids.compactMap { id in store.state.roleCards.firstIndex { $0.id == id } })
        store.deleteRoleCards(at: roleOffsets)
    }
}

struct AssistantCardRow: View {
    var assistantCard: AssistantCard
    var isActive: Bool

    var body: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(VNTheme.accent.opacity(0.20))
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(VNTheme.accentSoft)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(assistantCard.displayName)
                    .font(.headline)
                Text(assistantCard.summary)
                    .font(.caption)
                    .foregroundStyle(VNTheme.textSecondary)
                Text(assistantCard.detail)
                    .font(.caption2)
                    .foregroundStyle(VNTheme.textSecondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(VNTheme.accentSoft)
            }
        }
    }
}

struct AssistantPromptEditorView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(uiStatic("建立卡助手 Prompt")) {
                    Text(uiStatic("這會更新建立卡助手使用的 system prompt，保存後立即生效。可使用 {{user}} 代表稱呼，{{chur}} 代表助手卡名稱。"))
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                    TextEditor(text: $store.state.characterCardCreationAssistantPrompt)
                        .frame(minHeight: 260)
                }
                Section {
                    Button(uiStatic("還原預設 Prompt")) {
                        store.resetCharacterCardCreationAssistantPrompt()
                    }
                }
            }
            .visualNovelListChrome()
            .navigationTitle(uiStatic("助手 Prompt"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(uiStatic("關閉")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(uiStatic("保存")) {
                        store.persist()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RoleCardRow: View {
    var card: RoleCard
    var isActive: Bool

    var body: some View {
        HStack {
            RoleCardCoverView(card: card, height: 54, cornerRadius: 14)
                .frame(width: 54)
            VStack(alignment: .leading) {
                Text(card.name.isEmpty ? uiStatic("未命名角色") : card.name)
                    .font(.headline)
                Text(uiStatic("\(card.mode.title) · 世界書 \(card.lorebooks.count) · 開場 \(card.openingDialogues.count)"))
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

struct RoleCardCoverView: View {
    var card: RoleCard
    var height: CGFloat = 180
    var cornerRadius: CGFloat = 18

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(VNTheme.accent.opacity(0.20))
            if let imageData = card.coverImageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: height, alignment: Self.alignment(for: card.coverPosition))
            } else {
                Image(systemName: "person.crop.square.fill")
                    .font(.system(size: height > 80 ? 42 : 22, weight: .semibold))
                    .foregroundStyle(VNTheme.accentSoft)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(VNTheme.accent.opacity(0.28), lineWidth: 1)
        )
    }

    static func alignment(for coverPosition: String) -> Alignment {
        switch RoleCardCoverPosition(rawValue: coverPosition) ?? .centerCenter {
        case .topLeft: .topLeading
        case .topCenter: .top
        case .topRight: .topTrailing
        case .centerLeft: .leading
        case .centerCenter: .center
        case .centerRight: .trailing
        case .bottomLeft: .bottomLeading
        case .bottomCenter: .bottom
        case .bottomRight: .bottomTrailing
        }
    }
}

struct RoleCardEditorView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Environment(\.dismiss) private var dismiss
    @State var card: RoleCard
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var coverCropDraft: RoleCardCoverCropDraft?

    var body: some View {
        NavigationStack {
            Form {
                Section(uiStatic("基本")) {
                    TextField(uiStatic("名字"), text: $card.name)
                    Picker(uiStatic("模式"), selection: $card.mode) {
                        ForEach(RoleCardMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Picker(uiStatic("Prompt 模式"), selection: $card.promptModeId) {
                        ForEach(store.state.promptModes) { mode in
                            Text(mode.name).tag(mode.id)
                        }
                    }
                }
                Section(uiStatic("封面 / 預覽圖")) {
                    RoleCardCoverView(card: card, height: 220, cornerRadius: 20)
                    PhotosPicker(selection: $coverPickerItem, matching: .images) {
                        Label(card.coverImageData == nil ? uiStatic("選擇預覽圖") : uiStatic("更換預覽圖"), systemImage: "photo")
                    }
                    if card.coverImageData != nil || !card.coverImageDataURL.isEmpty {
                        Button {
                            if let data = card.coverImageData ?? Self.imageData(fromDataURL: card.coverImageDataURL) {
                                coverCropDraft = RoleCardCoverCropDraft(imageData: data)
                            }
                        } label: {
                            Label(uiStatic("裁切預覽圖"), systemImage: "crop")
                        }
                        Button(role: .destructive) {
                            card.coverImageData = nil
                            card.coverImageDataURL = ""
                        } label: {
                            Label(uiStatic("移除預覽圖"), systemImage: "trash")
                        }
                    }
                    Picker(uiStatic("取景位置"), selection: $card.coverPosition) {
                        ForEach(RoleCardCoverPosition.allCases) { position in
                            Text(position.title).tag(position.rawValue)
                        }
                    }
                }
                Section(uiStatic("自定義內容")) {
                    if card.customSections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(uiStatic("尚未新增自定義內容"))
                                .font(.headline)
                            Text(uiStatic("新角色卡不再預設塞入欄位。需要角色設定、世界觀或規則時再新增。"))
                                .font(.caption)
                                .foregroundStyle(VNTheme.textSecondary)
                        }
                        .padding(.vertical, 6)
                    }
                    ForEach($card.customSections) { $section in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(section.name.isEmpty ? uiStatic("未命名欄位") : section.name)
                                    .font(.headline)
                                Spacer()
                                Button(role: .destructive) {
                                    deleteCustomSection(id: section.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            TextField(uiStatic("名稱"), text: $section.name)
                            TextEditor(text: $section.content).frame(minHeight: 90)
                            Toggle(uiStatic("啟用"), isOn: $section.enabled)
                        }
                    }
                    Button(uiStatic("新增欄位")) { card.customSections.append(CustomSection(name: "新欄位")) }
                }
                Section(uiStatic("開場")) {
                    ForEach($card.openingDialogues) { $opening in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(opening.name.isEmpty ? uiStatic("開場") : opening.name)
                                    .font(.headline)
                                Spacer()
                                Button(role: .destructive) {
                                    deleteOpening(id: opening.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            TextField(uiStatic("標題"), text: $opening.name)
                            TextEditor(text: $opening.content).frame(minHeight: 90)
                        }
                    }
                    Button(uiStatic("新增開場")) { card.openingDialogues.append(OpeningDialogue(name: "開場 \(card.openingDialogues.count + 1)")) }
                }
                Section(uiStatic("世界書")) {
                    ForEach($card.lorebooks) { $entry in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(entry.title.isEmpty ? uiStatic("世界書") : entry.title)
                                    .font(.headline)
                                Spacer()
                                Button(role: .destructive) {
                                    deleteLorebook(id: entry.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            TextField(uiStatic("標題"), text: $entry.title)
                            TextField(uiStatic("關鍵字，用逗號分隔"), text: Binding(
                                get: { entry.keywords.joined(separator: ", ") },
                                set: { entry.keywords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                            TextEditor(text: $entry.content).frame(minHeight: 90)
                            Toggle(uiStatic("啟用"), isOn: $entry.enabled)
                        }
                    }
                    Button(uiStatic("新增世界書")) { card.lorebooks.append(LorebookEntry(title: "世界書")) }
                }
                Section("JSON") {
                    Button {
                        store.exportRoleCardJSON(Self.normalizedForSave(card))
                    } label: {
                        Label(uiStatic("匯出角色卡 JSON"), systemImage: "square.and.arrow.up")
                    }
                    if let url = store.exportedJSONURL {
                        ShareLink(item: url) {
                            Label(uiStatic("分享 JSON"), systemImage: "paperplane")
                        }
                    }
                }
            }
            .visualNovelListChrome()
            .navigationTitle(card.name.isEmpty ? uiStatic("角色卡") : card.name)
            .onChange(of: coverPickerItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            card.coverImageData = data
                            card.coverImageDataURL = Self.dataURL(for: data)
                        }
                    }
                }
            }
            .sheet(item: $coverCropDraft) { draft in
                RoleCardCoverCropEditor(imageData: draft.imageData) { croppedData in
                    card.coverImageData = croppedData
                    card.coverImageDataURL = Self.dataURL(for: croppedData, mimeType: "image/jpeg")
                    card.coverPosition = RoleCardCoverPosition.centerCenter.rawValue
                    coverCropDraft = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(uiStatic("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(uiStatic("保存")) {
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
        next.coverPosition = RoleCardCoverPosition(rawValue: next.coverPosition)?.rawValue ?? RoleCardCoverPosition.centerCenter.rawValue
        return next
    }

    static func dataURL(for imageData: Data, mimeType: String = "image/jpeg") -> String {
        "data:\(mimeType);base64,\(imageData.base64EncodedString())"
    }

    static func imageData(fromDataURL dataURL: String) -> Data? {
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let encoded = String(dataURL[dataURL.index(after: commaIndex)...])
        return Data(base64Encoded: encoded)
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

struct RoleCardCoverCropDraft: Identifiable {
    let id = UUID()
    var imageData: Data
}

struct RoleCardCoverCrop: Hashable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    static let defaultCrop = RoleCardCoverCrop(x: 0.12, y: 0.12, width: 0.76, height: 0.76)

    func normalized() -> RoleCardCoverCrop {
        let normalizedWidth = min(1, max(0.08, width))
        let normalizedHeight = min(1, max(0.08, height))
        return RoleCardCoverCrop(
            x: min(max(0, x), 1 - normalizedWidth),
            y: min(max(0, y), 1 - normalizedHeight),
            width: normalizedWidth,
            height: normalizedHeight
        )
    }
}

struct RoleCardCoverCropEditor: View {
    @Environment(\.dismiss) private var dismiss
    var imageData: Data
    var onApply: (Data) -> Void
    @State private var crop = RoleCardCoverCrop.defaultCrop

    static let supportsFreeCrop = true

    var body: some View {
        NavigationStack {
            Form {
                Section(uiStatic("裁切預覽")) {
                    if let image = UIImage(data: imageData) {
                        RoleCardCoverCropPreview(image: image, crop: crop)
                            .frame(height: 280)
                        Text(uiStatic("拖曳式裁切在網頁端完成；手機端以 X/Y/寬/高滑桿精準調整，同樣會輸出裁切後的 JPEG 預覽圖。"))
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    } else {
                        Text(uiStatic("圖片無法顯示。"))
                            .foregroundStyle(.red)
                    }
                }
                Section(uiStatic("裁切框")) {
                    cropSlider(title: "X", value: \.x)
                    cropSlider(title: "Y", value: \.y)
                    cropSlider(title: "寬", value: \.width, range: 0.08...1)
                    cropSlider(title: "高", value: \.height, range: 0.08...1)
                    Button(uiStatic("重置裁切框")) {
                        crop = .defaultCrop
                    }
                }
            }
            .visualNovelListChrome()
            .navigationTitle(uiStatic("裁切預覽圖"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(uiStatic("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(uiStatic("套用")) {
                        guard let cropped = Self.cropImageData(imageData, crop: crop) else { return }
                        onApply(cropped)
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cropSlider(
        title: String,
        value keyPath: WritableKeyPath<RoleCardCoverCrop, CGFloat>,
        range: ClosedRange<Double> = 0...1
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) \(Int(crop[keyPath: keyPath] * 100))%")
                .font(.caption)
                .foregroundStyle(VNTheme.textSecondary)
            Slider(
                value: Binding(
                    get: { Double(crop[keyPath: keyPath]) },
                    set: { next in
                        crop[keyPath: keyPath] = CGFloat(next)
                        crop = crop.normalized()
                    }
                ),
                in: range,
                step: 0.01
            )
        }
    }

    static func cropImageData(
        _ imageData: Data,
        crop: RoleCardCoverCrop,
        maxSide: CGFloat = 760,
        compressionQuality: CGFloat = 0.82
    ) -> Data? {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage
        else { return nil }
        let normalized = crop.normalized()
        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        let sourceRect = CGRect(
            x: normalized.x * sourceSize.width,
            y: normalized.y * sourceSize.height,
            width: normalized.width * sourceSize.width,
            height: normalized.height * sourceSize.height
        )
            .integral
            .intersection(CGRect(origin: .zero, size: sourceSize))
        guard sourceRect.width >= 1, sourceRect.height >= 1,
              let cropped = cgImage.cropping(to: sourceRect)
        else { return nil }
        let outputScale = min(1, maxSide / max(sourceRect.width, sourceRect.height))
        let outputSize = CGSize(width: sourceRect.width * outputScale, height: sourceRect.height * outputScale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let output = renderer.image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: outputSize))
        }
        return output.jpegData(compressionQuality: compressionQuality)
    }
}

struct RoleCardCoverCropPreview: View {
    var image: UIImage
    var crop: RoleCardCoverCrop

    var body: some View {
        GeometryReader { proxy in
            let imageRect = fittedImageRect(imageSize: image.size, containerSize: proxy.size)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.22)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                cropOverlay(in: imageRect)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func cropOverlay(in imageRect: CGRect) -> some View {
        let normalized = crop.normalized()
        let rect = CGRect(
            x: imageRect.minX + normalized.x * imageRect.width,
            y: imageRect.minY + normalized.y * imageRect.height,
            width: normalized.width * imageRect.width,
            height: normalized.height * imageRect.height
        )
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black.opacity(0.38))
                .mask {
                    Rectangle()
                        .overlay(alignment: .topLeading) {
                            Rectangle()
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                                .blendMode(.destinationOut)
                        }
                }
            Rectangle()
                .stroke(VNTheme.accentSoft, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .compositingGroup()
    }

    private func fittedImageRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

struct ArchiveView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var sessionName = ""
    @State private var previewSession: SavedSession?
    @State private var renamingSession: SavedSession?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section(uiStatic("保存目前對話")) {
                    TextField(uiStatic("存檔名稱"), text: $sessionName)
                    Button(uiStatic("保存")) {
                        store.saveSession(named: sessionName)
                        sessionName = ""
                    }
                }
                sessionSection(title: uiStatic("存檔"), sessions: activeSessions, archived: false)
                sessionSection(title: uiStatic("封存"), sessions: archivedSessions, archived: true)
            }
            .visualNovelListChrome()
            .navigationTitle(uiStatic("存檔"))
            .sheet(item: $previewSession) { session in
                SessionPreviewView(session: session)
            }
            .sheet(item: $renamingSession) { session in
                NavigationStack {
                    Form {
                        TextField(uiStatic("存檔名稱"), text: $renameText)
                    }
                    .visualNovelListChrome()
                    .navigationTitle(uiStatic("重新命名"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(uiStatic("取消")) { renamingSession = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(uiStatic("保存")) {
                                store.renameSession(id: session.id, name: renameText)
                                renamingSession = nil
                            }
                        }
                    }
                }
            }
        }
    }

    private var activeSessions: [SavedSession] {
        store.state.savedSessions.filter { !$0.archived }
    }

    private var archivedSessions: [SavedSession] {
        store.state.savedSessions.filter(\.archived)
    }

    @ViewBuilder
    private func sessionSection(title: String, sessions: [SavedSession], archived: Bool) -> some View {
        if !sessions.isEmpty {
            Section(title) {
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(session.name).font(.headline)
                            if session.archived {
                                Text(uiStatic("封存"))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(VNTheme.accentSoft)
                            }
                        }
                        Text(uiStatic("角色：\(session.roleCardName) · 訊息 \(session.conversation.count)"))
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                        HStack {
                            Button(uiStatic("載入")) { store.load(session: session) }
                            Button(uiStatic("預覽")) { previewSession = session }
                            Spacer()
                            Text(session.updatedAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(VNTheme.textSecondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.deleteSession(id: session.id)
                        } label: {
                            Label(uiStatic("刪除"), systemImage: "trash")
                        }
                        Button {
                            store.setSessionArchived(id: session.id, archived: !archived)
                        } label: {
                            Label(archived ? uiStatic("恢復") : uiStatic("封存"), systemImage: archived ? "arrow.uturn.backward" : "archivebox")
                        }
                    }
                    .contextMenu {
                        Button(uiStatic("載入")) { store.load(session: session) }
                        Button(uiStatic("預覽")) { previewSession = session }
                        Button(uiStatic("重新命名")) {
                            renamingSession = session
                            renameText = session.name
                        }
                        Button(archived ? uiStatic("恢復") : uiStatic("封存")) {
                            store.setSessionArchived(id: session.id, archived: !archived)
                        }
                        Button(role: .destructive) {
                            store.deleteSession(id: session.id)
                        } label: {
                            Text(uiStatic("刪除"))
                        }
                    }
                }
            }
        }
    }
}

struct SessionPreviewView: View {
    var session: SavedSession

    var body: some View {
        NavigationStack {
            List {
                Section(uiStatic("資訊")) {
                    Text(session.name)
                    Text(uiStatic("角色：\(session.roleCardName)"))
                    Text(uiStatic("訊息 \(session.conversation.count)"))
                    Text(session.updatedAt, style: .date)
                }
                Section(uiStatic("對話預覽")) {
                    ForEach(session.conversation.prefix(20)) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role == .user ? uiStatic("你") : "AI")
                                .font(.caption.bold())
                                .foregroundStyle(VNTheme.accentSoft)
                            Text(message.content)
                                .font(.caption)
                                .lineLimit(6)
                        }
                    }
                }
            }
            .visualNovelListChrome()
            .navigationTitle(uiStatic("存檔預覽"))
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
                    Picker(uiStatic("工房"), selection: $mode) {
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
            .navigationTitle(uiStatic("工房"))
            .background(VisualNovelBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct PromptLabView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var selectedQuickModeID = ""
    @State private var selectedQuickProfileID = ""
    @State private var showModeImporter = false
    static let exposesQuickProfileKindAndImageSettings = true
    static let showsExpandedQuickImageSettings = true
    static let hidesQuickCompressionSummaryEditor = true

    var body: some View {
        List {
            Section(uiStatic("壓縮狀態快捷區")) {
                if store.state.promptModes.isEmpty {
                    Text(uiStatic("尚未建立 Prompt 模式。"))
                        .foregroundStyle(VNTheme.textSecondary)
                } else {
                    Picker(uiStatic("模式"), selection: selectedModeBinding) {
                        ForEach(store.state.promptModes) { mode in
                            Text(mode.name).tag(mode.id)
                        }
                    }
                    .disabled(Self.shouldLockQuickModePicker(state: store.state))
                    if let caption = activeRoleQuickModeCaption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(VNTheme.accentSoft)
                    } else if store.state.activeRoleCard != nil {
                        Text(ModelContentView.emptyStateText(state: store.state))
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    }
                    if let mode = selectedMode {
                        Picker(uiStatic("大模型"), selection: selectedProfileBinding(modeID: mode.id)) {
                            ForEach(mode.compressionProfiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        if let profile = selectedProfile(modeID: mode.id) {
                            Text(profile.modelKind.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(profile.modelKind == .image ? VNTheme.accentSoft : VNTheme.textSecondary)
                            Picker(uiStatic("大模型類型"), selection: profileKindBinding(modeID: mode.id, profileID: profile.id)) {
                                ForEach(CompressionProfileKind.allCases) { kind in
                                    Text(kind.title).tag(kind)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(profile.modelKind.helpText)
                                .font(.caption)
                                .foregroundStyle(VNTheme.textSecondary)
                            if profile.modelKind == .image {
                                Text(uiStatic("建立圖片設定"))
                                    .font(.headline)
                                    .foregroundStyle(VNTheme.accentSoft)
                                Text(uiStatic("大模型 call api 的輸出會作為 NovelAI Base Prompt；以下設定會送到 NAI。"))
                                    .font(.caption)
                                    .foregroundStyle(VNTheme.textSecondary)
                                ImageGenerationSettingsEditor(settings: profileImageGenerationBinding(modeID: mode.id, profileID: profile.id))
                            } else {
                                Text(profile.storageModeDescription)
                                    .font(.caption)
                                    .foregroundStyle(VNTheme.textSecondary)
                                if let binding = profileBinding(modeID: mode.id, profileID: profile.id) {
                                    NavigationLink(uiStatic("編輯模塊 / 保存方式")) {
                                        CompressionContextEditorView(profile: binding)
                                    }
                                }
                            }
                            Text(uiStatic("已壓縮到第 \(profile.compressedThroughTurnNumber) 回合"))
                                .font(.caption)
                                .foregroundStyle(VNTheme.textSecondary)
                            NavigationLink(uiStatic("完整設定")) {
                                if let binding = profileBinding(modeID: mode.id, profileID: profile.id) {
                                    CompressionProfileEditorView(profile: binding)
                                } else {
                                    Text(uiStatic("此大模型已不存在。"))
                                }
                            }
                        }
                    }
                }
            }
            Section(uiStatic("模式")) {
                ForEach($store.state.promptModes) { $mode in
                    NavigationLink {
                        PromptModeEditorView(mode: $mode, isBuiltIn: Self.isBuiltIn(mode.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(mode.name)
                                    .font(.headline)
                                if Self.isBuiltIn(mode.id) {
                                    Text(uiStatic("內建"))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(VNTheme.accentSoft)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(VNTheme.accent.opacity(0.16)))
                                }
                            }
                            Text(uiStatic("\(mode.mode) · 自動上下文 · Profiles \(mode.compressionProfiles.count)"))
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
                    Label(uiStatic("新增自訂模式"), systemImage: "plus")
                }
                Button {
                    showModeImporter = true
                } label: {
                    Label(uiStatic("匯入模式 JSON"), systemImage: "square.and.arrow.down")
                }
                Button {
                    if let mode = store.state.promptModes.first(where: { $0.id == effectiveModeID }) {
                        store.exportPromptModeJSON(mode)
                    }
                } label: {
                    Label(uiStatic("匯出目前模式 JSON"), systemImage: "square.and.arrow.up")
                }
                .disabled(store.state.promptModes.isEmpty)
                if let url = store.exportedJSONURL {
                    ShareLink(item: url) {
                        Label(uiStatic("分享 JSON"), systemImage: "paperplane")
                    }
                }
            }
        }
        .visualNovelListChrome()
        .navigationTitle("Prompt Lab")
        .fileImporter(isPresented: $showModeImporter, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result {
                _ = url.startAccessingSecurityScopedResource()
                store.importPromptModeJSON(url: url)
                url.stopAccessingSecurityScopedResource()
            }
        }
        .onAppear {
            syncQuickModeWithActiveRoleCard()
        }
        .onChange(of: Self.activeRolePromptModeSignature(state: store.state)) { _, _ in
            syncQuickModeWithActiveRoleCard()
        }
        .onDisappear { store.persist() }
    }

    static func isBuiltIn(_ id: String) -> Bool {
        ["single", "multi", "no_role"].contains(id)
    }

    static func modeIDs(at offsets: IndexSet, in modes: [PromptModeConfig]) -> [String] {
        offsets.compactMap { modes.indices.contains($0) ? modes[$0].id : nil }
    }

    static func activeRolePromptModeID(state: AppState) -> String? {
        ModelContentView.visiblePromptModeIDs(state: state).first
    }

    static func effectiveQuickModeID(state: AppState, selectedModeID: String) -> String {
        if let activeModeID = activeRolePromptModeID(state: state) {
            return activeModeID
        }
        if state.promptModes.contains(where: { $0.id == selectedModeID }) {
            return selectedModeID
        }
        return state.promptModes.first?.id ?? ""
    }

    static func shouldLockQuickModePicker(state: AppState) -> Bool {
        activeRolePromptModeID(state: state) != nil
    }

    static func activeRolePromptModeSignature(state: AppState) -> String {
        guard let roleCard = state.activeRoleCard else { return "inactive" }
        let promptModeIDs = state.promptModes.map(\.id).joined(separator: ",")
        let visibleIDs = ModelContentView.visiblePromptModeIDs(state: state).joined(separator: ",")
        return [roleCard.id, roleCard.promptModeId, roleCard.mode.rawValue, visibleIDs, promptModeIDs].joined(separator: "|")
    }

    private func deleteModes(at offsets: IndexSet) {
        let ids = Self.modeIDs(at: offsets, in: store.state.promptModes)
        store.state.promptModes.removeAll { ids.contains($0.id) && !Self.isBuiltIn($0.id) }
        store.persist()
    }

    private var effectiveModeID: String {
        Self.effectiveQuickModeID(state: store.state, selectedModeID: selectedQuickModeID)
    }

    private var selectedMode: PromptModeConfig? {
        store.state.promptModes.first { $0.id == effectiveModeID }
    }

    private var selectedModeBinding: Binding<String> {
        Binding(
            get: { effectiveModeID },
            set: {
                guard !Self.shouldLockQuickModePicker(state: store.state) else { return }
                selectedQuickModeID = $0
                selectedQuickProfileID = ""
            }
        )
    }

    private var activeRoleQuickModeCaption: String? {
        guard let roleCard = store.state.activeRoleCard,
              let modeID = Self.activeRolePromptModeID(state: store.state),
              let mode = store.state.promptModes.first(where: { $0.id == modeID })
        else { return nil }
        let roleName = roleCard.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? uiStatic("未命名角色卡") : roleCard.name
        return "\(uiStatic("已跟隨目前角色卡"))：\(roleName) · \(mode.name)"
    }

    private func syncQuickModeWithActiveRoleCard() {
        guard let activeModeID = Self.activeRolePromptModeID(state: store.state),
              selectedQuickModeID != activeModeID
        else { return }
        selectedQuickModeID = activeModeID
        selectedQuickProfileID = ""
    }

    private func selectedProfileBinding(modeID: String) -> Binding<String> {
        Binding(
            get: {
                let profiles = profiles(for: modeID)
                if profiles.contains(where: { $0.id == selectedQuickProfileID }) {
                    return selectedQuickProfileID
                }
                return profiles.first?.id ?? ""
            },
            set: { selectedQuickProfileID = $0 }
        )
    }

    private func selectedProfile(modeID: String) -> CompressionProfile? {
        let profiles = profiles(for: modeID)
        let id = profiles.contains(where: { $0.id == selectedQuickProfileID }) ? selectedQuickProfileID : profiles.first?.id ?? ""
        return profiles.first { $0.id == id }
    }

    private func profiles(for modeID: String) -> [CompressionProfile] {
        store.state.promptModes.first { $0.id == modeID }?.compressionProfiles ?? []
    }

    private func profileBinding(modeID: String, profileID: String) -> Binding<CompressionProfile>? {
        guard let modeIndex = store.state.promptModes.firstIndex(where: { $0.id == modeID }),
              store.state.promptModes[modeIndex].compressionProfiles.contains(where: { $0.id == profileID })
        else { return nil }
        return Binding(
            get: {
                guard let modeIndex = store.state.promptModes.firstIndex(where: { $0.id == modeID }),
                      let profileIndex = store.state.promptModes[modeIndex].compressionProfiles.firstIndex(where: { $0.id == profileID })
                else { return CompressionProfile(id: profileID, name: "已刪除大模型", enabled: false) }
                return store.state.promptModes[modeIndex].compressionProfiles[profileIndex]
            },
            set: { next in
                guard let modeIndex = store.state.promptModes.firstIndex(where: { $0.id == modeID }),
                      let profileIndex = store.state.promptModes[modeIndex].compressionProfiles.firstIndex(where: { $0.id == profileID })
                else { return }
                store.state.promptModes[modeIndex].compressionProfiles[profileIndex] = next
            }
        )
    }

    private func profileKindBinding(modeID: String, profileID: String) -> Binding<CompressionProfileKind> {
        Binding(
            get: {
                profileBinding(modeID: modeID, profileID: profileID)?.wrappedValue.modelKind ?? .normal
            },
            set: { nextKind in
                guard var profile = profileBinding(modeID: modeID, profileID: profileID)?.wrappedValue else { return }
                profile.applyModelKind(nextKind)
                profileBinding(modeID: modeID, profileID: profileID)?.wrappedValue = profile
            }
        )
    }

    private func profileImageGenerationBinding(modeID: String, profileID: String) -> Binding<NovelAIImageGenerationSettings> {
        Binding(
            get: {
                guard var profile = profileBinding(modeID: modeID, profileID: profileID)?.wrappedValue else {
                    return .compressionTriggerDefault
                }
                profile.applyModelKind(.image)
                guard let index = profile.primaryImageTriggerActionIndex,
                      profile.triggerActions.indices.contains(index)
                else { return .compressionTriggerDefault }
                return profile.triggerActions[index].imageGeneration
            },
            set: { next in
                guard var profile = profileBinding(modeID: modeID, profileID: profileID)?.wrappedValue else { return }
                profile.applyModelKind(.image)
                guard let index = profile.primaryImageTriggerActionIndex,
                      profile.triggerActions.indices.contains(index)
                else { return }
                profile.triggerActions[index].imageGeneration = next
                profileBinding(modeID: modeID, profileID: profileID)?.wrappedValue = profile
            }
        )
    }

}

struct PromptModeEditorView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Binding var mode: PromptModeConfig
    var isBuiltIn: Bool

    static let exposesManualRoundEditing = false

    var body: some View {
        Form {
            Section(uiStatic("模式設定")) {
                TextField(uiStatic("名稱"), text: $mode.name)
                TextField("Mode ID", text: $mode.mode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text(uiStatic("上下文輪數由模式設定與壓縮觸發自動使用。"))
                    .font(.caption)
                    .foregroundStyle(VNTheme.textSecondary)
                if isBuiltIn {
                    Label(uiStatic("內建模式不可刪除，但可以調整內容。"), systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                }
            }
            Section(uiStatic("編輯器")) {
                NavigationLink(uiStatic("正文規則")) {
                    PromptRulesEditorView(mode: $mode)
                }
                NavigationLink(uiStatic("壓縮大模型")) {
                    CompressionProfileListView(mode: $mode)
                }
                NavigationLink(uiStatic("雙 Prompt Preview")) {
                    PromptPreviewView(mode: mode)
                }
            }
        }
        .visualNovelListChrome()
        .navigationTitle(mode.name)
        .toolbar {
            Button(uiStatic("保存")) { store.persist() }
        }
    }
}

struct PromptRulesEditorView: View {
    @Binding var mode: PromptModeConfig

    static let exposesLegacyFields = false

    var body: some View {
        Form {
            Section(uiStatic("正文 System Prompt")) {
                TextEditor(text: $mode.reasonerHistoryConfig.mainRules)
                    .frame(minHeight: 220)
            }
            Section(uiStatic("上下文規則")) {
                TextEditor(text: $mode.reasonerHistoryConfig.contextRules)
                    .frame(minHeight: 180)
            }
        }
        .visualNovelListChrome()
        .navigationTitle(uiStatic("正文規則"))
    }
}

struct CompressionProfileListView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Binding var mode: PromptModeConfig
    @State private var selectedProfileID = ""
    @State private var showProfileImporter = false

    var body: some View {
        List {
            Section(uiStatic("大模型 JSON")) {
                if !mode.compressionProfiles.isEmpty {
                    Picker(uiStatic("目前大模型"), selection: selectedProfileBinding) {
                        ForEach(mode.compressionProfiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                }
                Button {
                    showProfileImporter = true
                } label: {
                    Label(uiStatic("匯入大模型 JSON"), systemImage: "square.and.arrow.down")
                }
                Button {
                    if let profile = mode.compressionProfiles.first(where: { $0.id == effectiveProfileID }) {
                        store.exportCompressionProfileJSON(profile)
                    }
                } label: {
                    Label(uiStatic("匯出目前大模型 JSON"), systemImage: "square.and.arrow.up")
                }
                .disabled(mode.compressionProfiles.isEmpty)
                if let url = store.exportedJSONURL {
                    ShareLink(item: url) {
                        Label(uiStatic("分享 JSON"), systemImage: "paperplane")
                    }
                }
            }
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
                        Text("\(profile.modelKind.title) · \(profile.contextScope.title) · \(profile.storageMode.title) · Trigger \(profile.triggerActions.count)")
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    }
                }
            }
            .onDelete(perform: deleteProfiles)
            Button {
                mode.compressionProfiles.append(Self.newProfile(kind: .normal, count: mode.compressionProfiles.count))
            } label: {
                Label(uiStatic("新增普通大模型"), systemImage: "plus")
            }
            Button {
                mode.compressionProfiles.append(Self.newProfile(kind: .image, count: mode.compressionProfiles.count))
            } label: {
                Label(uiStatic("新增跑圖大模型"), systemImage: "photo")
            }
        }
        .visualNovelListChrome()
        .navigationTitle(uiStatic("壓縮 Profiles"))
        .fileImporter(isPresented: $showProfileImporter, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result {
                _ = url.startAccessingSecurityScopedResource()
                store.importCompressionProfileJSON(url: url, modeID: mode.id)
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    static func profileIDs(at offsets: IndexSet, in profiles: [CompressionProfile]) -> [String] {
        offsets.compactMap { profiles.indices.contains($0) ? profiles[$0].id : nil }
    }

    private static func newProfile(kind: CompressionProfileKind, count: Int) -> CompressionProfile {
        var profile = CompressionProfile(
            id: "compression_profile_\(UUID().uuidString)",
            name: kind == .image ? "跑圖大模型 \(count + 1)" : "普通大模型 \(count + 1)",
            locked: false
        )
        profile.applyModelKind(kind)
        return profile
    }

    private func deleteProfiles(at offsets: IndexSet) {
        let ids = Self.profileIDs(at: offsets, in: mode.compressionProfiles)
        mode.compressionProfiles.removeAll { ids.contains($0.id) && !$0.locked && $0.id != "standard" }
    }

    private var effectiveProfileID: String {
        if mode.compressionProfiles.contains(where: { $0.id == selectedProfileID }) {
            return selectedProfileID
        }
        return mode.compressionProfiles.first?.id ?? ""
    }

    private var selectedProfileBinding: Binding<String> {
        Binding(
            get: { effectiveProfileID },
            set: { selectedProfileID = $0 }
        )
    }
}

struct CompressionProfileEditorView: View {
    @Binding var profile: CompressionProfile
    static let exposesProfileKindPicker = true

    var body: some View {
        Form {
            Section("Profile") {
                TextField(uiStatic("名稱"), text: $profile.name)
                Toggle(uiStatic("啟用"), isOn: $profile.enabled)
                Toggle(uiStatic("鎖定"), isOn: $profile.locked)
                Picker(uiStatic("壓縮範圍"), selection: $profile.contextScope) {
                    ForEach(CompressionContextScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
            }
            Section(uiStatic("大模型類型")) {
                Picker(uiStatic("類型"), selection: profileKindBinding) {
                    ForEach(CompressionProfileKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                Text(profile.modelKind.helpText)
                    .font(.caption)
                    .foregroundStyle(VNTheme.textSecondary)
            }
            if Self.imageSettingsVisibility(for: profile) {
                Section(uiStatic("跑圖設定")) {
                    Text(uiStatic("對齊網頁端：大模型 call api 的輸出會作為 NovelAI Base Prompt，下方設定會送到 NAI。"))
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                    ImageGenerationSettingsEditor(settings: primaryImageGenerationBinding)
                }
            } else {
                Section(uiStatic("保存方式")) {
                    Text(profile.storageModeDescription)
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                }
            }
            Section(uiStatic("規則與動作")) {
                NavigationLink(uiStatic("壓縮 Prompt / 模型")) {
                    CompressionContextEditorView(profile: $profile)
                }
                NavigationLink(uiStatic("觸發組合")) {
                    TriggerActionListView(profile: $profile)
                }
                NavigationLink(uiStatic("首次觸發追加詞")) {
                    AppendTermListView(profile: $profile)
                }
            }
        }
        .visualNovelListChrome()
        .navigationTitle(profile.name)
    }

    static func imageSettingsVisibility(for profile: CompressionProfile) -> Bool {
        profile.modelKind == .image
    }

    private var profileKindBinding: Binding<CompressionProfileKind> {
        Binding(
            get: { profile.modelKind },
            set: { profile.applyModelKind($0) }
        )
    }

    private var primaryImageGenerationBinding: Binding<NovelAIImageGenerationSettings> {
        Binding(
            get: {
                guard let index = profile.primaryImageTriggerActionIndex else {
                    return .compressionTriggerDefault
                }
                guard profile.triggerActions.indices.contains(index) else {
                    return .compressionTriggerDefault
                }
                return profile.triggerActions[index].imageGeneration
            },
            set: { next in
                profile.applyModelKind(.image)
                guard let index = profile.primaryImageTriggerActionIndex,
                      profile.triggerActions.indices.contains(index)
                else { return }
                profile.triggerActions[index].imageGeneration = next
            }
        )
    }
}

struct CompressionContextEditorView: View {
    @Binding var profile: CompressionProfile

    var body: some View {
        Form {
            Section(uiStatic("保存方式")) {
                Text(profile.storageModeDescription)
                    .font(.caption)
                    .foregroundStyle(VNTheme.textSecondary)
            }
            Section(uiStatic("壓縮主規則")) {
                TextEditor(text: $profile.contextCompression.mainRules)
                    .frame(minHeight: 240)
            }
            Section(uiStatic("模塊")) {
                if profile.contextCompression.models.isEmpty {
                    Text(uiStatic("尚未建立模塊，這個普通大模型會以純文本方式保存模型內容。新增模塊後，輸出會改成 JSON model.ID / delete.ID。"))
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                }
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
                    profile.contextCompression.models.remove(atValidOffsets: offsets)
                }
                Button {
                    profile.contextCompression.models.append(CompressionModel(name: "新模塊"))
                } label: {
                    Label(uiStatic("新增模塊"), systemImage: "plus")
                }
            }
        }
        .visualNovelListChrome()
        .navigationTitle(uiStatic("壓縮 Prompt"))
    }
}

struct CompressionModelEditorView: View {
    @Binding var model: CompressionModel

    var body: some View {
        Form {
            TextField("ID", text: $model.id)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField(uiStatic("名稱"), text: $model.name)
            Section(uiStatic("新增規則")) {
                TextEditor(text: $model.addRules).frame(minHeight: 160)
            }
            Section(uiStatic("刪除規則")) {
                TextEditor(text: $model.deleteRules).frame(minHeight: 160)
            }
        }
        .visualNovelListChrome()
        .navigationTitle(model.name.isEmpty ? uiStatic("模塊") : model.name)
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
            .onDelete(perform: deleteActions)
            Button {
                profile.triggerActions.append(CompressionTriggerAction())
            } label: {
                Label(uiStatic("新增觸發"), systemImage: "plus")
            }
        }
        .visualNovelListChrome()
        .navigationTitle(uiStatic("觸發組合"))
    }

    static func validActionOffsets(_ offsets: IndexSet, in actions: [CompressionTriggerAction]) -> IndexSet {
        IndexSet(offsets.filter { actions.indices.contains($0) })
    }

    private func deleteActions(at offsets: IndexSet) {
        profile.triggerActions.remove(atValidOffsets: offsets)
        if profile.triggerActions.isEmpty {
            profile.triggerActions = [CompressionTriggerAction(name: "觸發組合 1")]
        }
    }
}

struct ImageGenerationSettingsEditor: View {
    @Binding var settings: NovelAIImageGenerationSettings

    var body: some View {
        NovelAIModelPicker(model: $settings.model, title: "模型")
        TextEditor(text: $settings.negativePrompt)
            .frame(minHeight: 80)
            .overlay(alignment: .topLeading) {
                if settings.negativePrompt.isEmpty {
                    Text("Undesired Content / Negative Prompt")
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                        .padding(6)
                }
            }
        Stepper(uiStatic("寬 \(settings.width)"), value: $settings.width, in: 64...2048, step: 64)
        Stepper(uiStatic("高 \(settings.height)"), value: $settings.height, in: 64...2048, step: 64)
        Stepper("Steps \(settings.steps)", value: $settings.steps, in: 1...50)
        Stepper(uiStatic("張數 \(settings.samples)"), value: $settings.samples, in: 1...4)
        Slider(value: $settings.scale, in: 0...20, step: 0.1) {
            Text("Prompt Guidance")
        }
        Text("Prompt Guidance \(settings.scale, specifier: "%.1f")")
            .font(.caption)
        Slider(value: $settings.cfgRescale, in: 0...1, step: 0.05) {
            Text("Prompt Guidance Rescale")
        }
        Text("Prompt Guidance Rescale \(settings.cfgRescale, specifier: "%.2f")")
            .font(.caption)
        Picker("Sampler", selection: $settings.sampler) {
            ForEach(NovelAIOptionLists.samplerOptions, id: \.id) { option in
                Text(option.title).tag(option.id)
            }
        }
        Picker("Noise Schedule", selection: $settings.noiseSchedule) {
            ForEach(NovelAIOptionLists.noiseScheduleOptions, id: \.id) { option in
                Text(option.title).tag(option.id)
            }
        }
        Stepper("UC Preset \(settings.ucPreset)", value: $settings.ucPreset, in: 0...99)
        Toggle("Variety+", isOn: $settings.varietyPlus)
        Picker(uiStatic("格式"), selection: $settings.imageFormat) {
            ForEach(NovelAIOptionLists.imageFormatOptions, id: \.id) { option in
                Text(option.title).tag(option.id)
            }
        }
        TextField(uiStatic("Seed（空白 = random）"), text: imageSeedBinding)
            .keyboardType(.numberPad)
    }

    private var imageSeedBinding: Binding<String> {
        Binding(
            get: { settings.seed.map(String.init) ?? "" },
            set: { settings.seed = Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }
}

struct TriggerActionEditorView: View {
    @Binding var action: CompressionTriggerAction
    static let exposesFullImageGenerationSettings = true
    static func parseTurnList(_ value: String) -> [Int] {
        let separatorCharacters = ",，、;；|/／"
        let parsed = value
            .split { character in
                character.isWhitespace || separatorCharacters.contains(character)
            }
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 >= 0 }
        return Array(Set(parsed)).sorted()
    }

    var body: some View {
        Form {
            Section(uiStatic("動作")) {
                TextField(uiStatic("名稱"), text: $action.name)
                Toggle(uiStatic("啟用"), isOn: $action.enabled)
                Picker(uiStatic("動作"), selection: $action.action) {
                    ForEach(CompressionTriggerActionKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                Picker(uiStatic("關鍵字後續"), selection: $action.keywordFollowupAction) {
                    ForEach(KeywordFollowupAction.allCases) { followup in
                        Text(followup.title).tag(followup)
                    }
                }
                Toggle(uiStatic("跳過正文 Reasoner"), isOn: $action.skipReasoner)
            }
            Section(uiStatic("觸發條件")) {
                Toggle(uiStatic("每輪觸發"), isOn: $action.triggers.everyTurn)
                Toggle(uiStatic("達到上下文輪數觸發"), isOn: $action.triggers.roundLimit)
                TextField(uiStatic("指定回合，例如 5 10 15 20"), text: intListBinding($action.triggers.turns))
                    .keyboardType(.numbersAndPunctuation)
                Text(uiStatic("可用空格、逗號、頓號或分號分隔；0 代表開始觸發。指定回合會像網頁端一樣按正文上限週期重複。"))
                    .font(.caption)
                    .foregroundStyle(VNTheme.textSecondary)
                TextField(uiStatic("關鍵字，用逗號分隔"), text: stringListBinding($action.triggers.keywords))
                TextField(uiStatic("關鍵字來源"), text: $action.triggers.keywordSource)
            }
            Section("NovelAI Prompt Trigger") {
                Toggle(uiStatic("啟用 NovelAI Prompt"), isOn: $action.novelAIEnabled)
                Text(uiStatic("大模型 call api 的輸出會作為 NovelAI Base Prompt；以下設定會跟網頁端的建立圖片設定一起送到 NAI。"))
                    .font(.caption)
                    .foregroundStyle(VNTheme.textSecondary)
                TextEditor(text: $action.novelAIPromptTemplate)
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if action.novelAIPromptTemplate.isEmpty {
                            Text(uiStatic("Prompt template / 留空時使用大模型輸出"))
                                .font(.caption)
                                .foregroundStyle(VNTheme.textSecondary)
                                .padding(6)
                        }
                    }
            }
            if action.keywordFollowupAction.isImageGeneration {
                Section(uiStatic("建立圖片設定")) {
                    ImageGenerationSettingsEditor(settings: $action.imageGeneration)
                }
            } else {
                Section(uiStatic("建立圖片設定")) {
                    Text(uiStatic("選擇「建立圖片，然後繼續觸發正文」或「建立圖片並行」後，這裡會顯示 NovelAI 跑圖設定。"))
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                }
            }
        }
        .visualNovelListChrome()
        .navigationTitle(action.name)
        .onChange(of: action.keywordFollowupAction) { _, next in
            guard next.isImageGeneration else { return }
            action.action = .callAPI
            action.novelAIEnabled = true
        }
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
                binding.wrappedValue = Self.parseTurnList($0)
            }
        )
    }

}

struct AppendTermListView: View {
    @Binding var profile: CompressionProfile

    var body: some View {
        Form {
            ForEach($profile.appendTerms) { $term in
                Section(term.player.isEmpty ? uiStatic("追加詞") : term.player) {
                    TextField(uiStatic("玩家座位"), text: $term.player)
                    TextEditor(text: $term.content).frame(minHeight: 80)
                    Toggle(uiStatic("啟用"), isOn: $term.enabled)
                }
            }
            .onDelete { offsets in
                profile.appendTerms.remove(atValidOffsets: offsets)
            }
            Button(uiStatic("新增追加詞")) { profile.appendTerms.append(CompressionAppendTerm()) }
        }
        .visualNovelListChrome()
        .navigationTitle(uiStatic("追加詞"))
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
                        Text(uiStatic("正文 system prompt"))
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
                            Text(uiStatic("壓縮 prompt · \(profile.name)"))
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
            NovelAIStudioTabBar(page: $page)
            .padding(.horizontal)
            .padding(.top, 2)
            .padding(.bottom, 8)
            .zIndex(2)

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
            .zIndex(0)
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

    var systemImage: String {
        switch self {
        case .settings: "slider.horizontal.3"
        case .prompt: "text.quote"
        case .reference: "photo.on.rectangle"
        case .output: "wand.and.stars"
        case .history: "clock.arrow.circlepath"
        }
    }

    var shortTitle: String {
        switch self {
        case .settings: "設定"
        case .prompt: "Prompt"
        case .reference: "Ref"
        case .output: "Output"
        case .history: "History"
        }
    }
}

struct NovelAIStudioTabBar: View {
    @Binding var page: NovelAIStudioPage

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NovelAIStudioPage.allCases) { item in
                VStack(spacing: 3) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 13, weight: .bold))
                    Text(uiStatic(item.shortTitle))
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .foregroundStyle(page == item ? VNTheme.accentSoft : VNTheme.textSecondary)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(page == item ? VNTheme.accent.opacity(0.20) : VNTheme.ink.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(page == item ? VNTheme.accent.opacity(0.48) : Color.white.opacity(0.12), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture().onEnded {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            page = item
                        }
                    }
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(uiStatic(item.rawValue))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        page = item
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct NovelAIModelPicker: View {
    @Binding var model: String
    var title: String = "模型"

    var body: some View {
        Picker(uiStatic(title), selection: normalizedBinding) {
            ForEach(NovelAIModelOption.allCases) { option in
                Text(option.title).tag(option.id)
            }
        }
    }

    private var normalizedBinding: Binding<String> {
        Binding(
            get: { NovelAIModelOption.knownIDOrDefault(model) },
            set: { model = $0 }
        )
    }
}

enum NovelAIOptionLists {
    static let samplerOptions: [(id: String, title: String)] = [
        ("k_euler_ancestral", "Euler Ancestral"),
        ("k_euler", "Euler"),
        ("k_dpmpp_2s_ancestral", "DPM++ 2S Ancestral"),
        ("k_dpmpp_2m", "DPM++ 2M"),
        ("k_dpmpp_2m_sde", "DPM++ 2M SDE"),
        ("k_dpmpp_sde", "DPM++ SDE")
    ]

    static let noiseScheduleOptions: [(id: String, title: String)] = [
        ("karras", "Karras"),
        ("exponential", "Exponential"),
        ("native", "Native"),
        ("polyexponential", "Polyexponential")
    ]

    static let imageFormatOptions: [(id: String, title: String)] = [
        ("png", "PNG"),
        ("webp", "WebP")
    ]
}

struct NovelAISettingsPanel: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Binding var settings: NovelAIStudioSettings

    var body: some View {
        Form {
            Section(uiStatic("狀態")) {
                Button(uiStatic("讀取 status / balance")) { store.testNovelAI() }
                if !store.statusText.isEmpty {
                    Text(store.statusText)
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                }
            }
            Section(uiStatic("模型")) {
                NovelAIModelPicker(model: $settings.imageSettings.model, title: "模型")
                Text(NovelAIModelOption.option(for: settings.imageSettings.model)?.description ?? NovelAIModelOption.option(for: NovelAIModelOption.defaultID)?.description ?? "")
                    .font(.caption)
                    .foregroundStyle(VNTheme.textSecondary)
                if !settings.modelDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(settings.modelDescription)
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                }
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
                Text(uiStatic("可用 ||片段名|| 插入固定或隨機片段；舊版 {{片段名}} 只會展開 Random Prompt。Character Prompt 會送入 NovelAI V4 角色 caption，不會混入 Base Prompt。"))
                    .font(.caption)
                    .foregroundStyle(VNTheme.textSecondary)
                TextEditor(text: $settings.basePrompt)
                    .frame(minHeight: 130)
            }
            Section("Negative Prompt") {
                TextEditor(text: $settings.negativePrompt)
                    .frame(minHeight: 90)
            }
            NovelAISnippetSection(title: "固定 Prompt 片段", snippets: $settings.fixedSnippets)
            NovelAISnippetSection(title: "隨機 Prompt 片段", snippets: $settings.randomSnippets, isRandom: true)
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
    var isRandom = false

    var body: some View {
        Section(uiStatic(title)) {
            ForEach($snippets) { $snippet in
                VStack(alignment: .leading, spacing: 8) {
                    TextField(uiStatic("名稱，可用 ||名稱|| 插入"), text: $snippet.name)
                    TextEditor(text: $snippet.content)
                        .frame(minHeight: isRandom ? 120 : 80)
                    if isRandom {
                        Stepper(uiStatic("抽選最少 \(snippet.min)"), value: $snippet.min, in: 0...99)
                        Stepper(uiStatic("抽選最多 \(snippet.max)"), value: $snippet.max, in: 0...99)
                        Toggle(uiStatic("啟用 [] 弱化"), isOn: $snippet.squareEnabled)
                        Stepper("[] max \(snippet.squareMax)", value: $snippet.squareMax, in: 0...12)
                        Toggle(uiStatic("啟用 {} 強化"), isOn: $snippet.curlyEnabled)
                        Stepper("{} max \(snippet.curlyMax)", value: $snippet.curlyMax, in: 0...12)
                        Toggle(uiStatic("啟用數值權重"), isOn: $snippet.weightEnabled)
                        Slider(value: $snippet.weightMin, in: 0...5, step: 0.1) { Text(uiStatic("最少權重")) }
                        Text("\(uiStatic("最少權重")) \(snippet.weightMin, specifier: "%.1f")")
                            .font(.caption)
                        Slider(value: $snippet.weightMax, in: 0...5, step: 0.1) { Text(uiStatic("最多權重")) }
                        Text("\(uiStatic("最多權重")) \(snippet.weightMax, specifier: "%.1f")")
                            .font(.caption)
                        Slider(value: $snippet.weightBias, in: 0...5, step: 0.1) { Text(uiStatic("權重偏向")) }
                        Text("\(uiStatic("權重偏向")) \(snippet.weightBias, specifier: "%.1f")")
                            .font(.caption)
                    }
                    Toggle(uiStatic("啟用"), isOn: $snippet.enabled)
                    Button(role: .destructive) {
                        snippets = Self.snippetsAfterDeleting(id: snippet.id, from: snippets)
                    } label: {
                        Label(uiStatic("刪除片段"), systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                snippets.remove(atValidOffsets: offsets)
            }
            Button(uiStatic("新增")) {
                snippets.append(NovelAIPromptSnippet(name: isRandom ? "隨機片段 \(snippets.count + 1)" : "固定片段 \(snippets.count + 1)"))
            }
        }
    }

    static func snippetsAfterDeleting(id: String, from snippets: [NovelAIPromptSnippet]) -> [NovelAIPromptSnippet] {
        snippets.filter { $0.id != id }
    }
}

struct NovelAICharacterPositionGrid: View {
    @Binding var x: Double
    @Binding var y: Double

    private let columns = Array(repeating: GridItem(.flexible(minimum: 36), spacing: 6), count: 5)

    var body: some View {
        let current = NovelAICharacterPositionCell(x: x, y: y)
        VStack(alignment: .leading, spacing: 8) {
            Text(uiStatic("位置 \(current.label)"))
                .font(.headline)
            Text(uiStatic("對齊網頁端 NovelAI 角色位置：R1 C1 是左上，R5 C5 是右下；會送入 V4 char_captions 的 centers。"))
                .font(.caption)
                .foregroundStyle(VNTheme.textSecondary)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(NovelAICharacterPositionCell.allCells) { cell in
                    Button {
                        x = cell.x
                        y = cell.y
                    } label: {
                        Text(cell.buttonTitle)
                            .font(.caption2.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(cell == current ? VNTheme.accent.opacity(0.82) : VNTheme.panel.opacity(0.34))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(cell == current ? VNTheme.accentSoft : Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(uiStatic("位置 \(cell.label)"))
                }
            }
            Text("\(uiStatic("目前 centers")): x \(x, specifier: "%.2f"), y \(y, specifier: "%.2f")")
                .font(.caption2)
                .foregroundStyle(VNTheme.textSecondary)
        }
    }
}

struct NovelAICharacterPromptSection: View {
    @Binding var prompts: [NovelAICharacterPrompt]
    static let usesWebPositionGrid = true

    var body: some View {
        Section("Character Prompts") {
            ForEach($prompts) { $prompt in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField(uiStatic("角色名"), text: $prompt.name)
                        Button {
                            prompts = Self.promptsAfterMoving(id: prompt.id, direction: -1, from: prompts)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(Self.index(of: prompt.id, in: prompts) == 0)
                        .accessibilityLabel(uiStatic("上移角色 Prompt"))
                        Button {
                            prompts = Self.promptsAfterMoving(id: prompt.id, direction: 1, from: prompts)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(Self.index(of: prompt.id, in: prompts).map { $0 >= prompts.count - 1 } ?? true)
                        .accessibilityLabel(uiStatic("下移角色 Prompt"))
                    }
                    TextEditor(text: $prompt.prompt).frame(minHeight: 90)
                    TextEditor(text: $prompt.negativePrompt).frame(minHeight: 70)
                        .overlay(alignment: .topLeading) {
                            if prompt.negativePrompt.isEmpty {
                                Text("Undesired / Negative Prompt")
                                    .font(.caption)
                                    .foregroundStyle(VNTheme.textSecondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                        }
                    NovelAICharacterPositionGrid(x: $prompt.x, y: $prompt.y)
                    Toggle(uiStatic("啟用"), isOn: $prompt.enabled)
                    Button(role: .destructive) {
                        prompts = Self.promptsAfterDeleting(id: prompt.id, from: prompts)
                    } label: {
                        Label(uiStatic("刪除角色 Prompt"), systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                prompts.remove(atValidOffsets: offsets)
            }
            Button(uiStatic("新增角色 Prompt")) {
                prompts.append(NovelAICharacterPrompt(name: "角色 \(prompts.count + 1)"))
            }
        }
    }

    static func promptsAfterDeleting(id: String, from prompts: [NovelAICharacterPrompt]) -> [NovelAICharacterPrompt] {
        prompts.filter { $0.id != id }
    }

    static func index(of id: String, in prompts: [NovelAICharacterPrompt]) -> Int? {
        prompts.firstIndex { $0.id == id }
    }

    static func promptsAfterMoving(id: String, direction: Int, from prompts: [NovelAICharacterPrompt]) -> [NovelAICharacterPrompt] {
        guard let index = index(of: id, in: prompts) else { return prompts }
        let newIndex = min(prompts.count - 1, max(0, index + direction))
        guard index != newIndex else { return prompts }
        var next = prompts
        next.swapAt(index, newIndex)
        return next
    }
}

struct NovelAIReferencePanel: View {
    @Binding var settings: NovelAIStudioSettings

    var body: some View {
        Form {
            NovelAITargetedImageImportSection(settings: $settings)
            NovelAIReferenceSection(title: "Vibe Transfer", references: $settings.vibeTransferImages, type: "vibe")
            Section("Image2Image") {
                ImagePickerButton(title: settings.imageToImageImageData == nil ? uiStatic("選擇底圖") : uiStatic("更換底圖")) { data in
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
                        Label(uiStatic("移除 Image2Image"), systemImage: "trash")
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

enum NovelAIImageImportTarget: String, CaseIterable, Identifiable {
    case vibe
    case imageToImage
    case precise
    case metadata

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vibe: "Vibe Transfer"
        case .imageToImage: "Image2Image"
        case .precise: "Precise Reference"
        case .metadata: "匯入設定"
        }
    }
}

struct NovelAITargetedImageImportResult: Hashable {
    var settings: NovelAIStudioSettings
    var statusText: String
}

struct NovelAITargetedImageImportSection: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Binding var settings: NovelAIStudioSettings
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var pendingImages: [Data] = []
    @State private var showTargetDialog = false

    static let mirrorsWebDropChoiceActions = true

    var body: some View {
        Section(uiStatic("圖片用途匯入")) {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: 12, matching: .images) {
                Label(uiStatic("選擇圖片並指定用途"), systemImage: "photo.stack")
            }
            Text(uiStatic("對齊網頁端拖入圖片後的用途選擇：可加入 Vibe Transfer、設定 Image2Image、加入 Precise Reference，或讀取 metadata 還原設定。"))
                .font(.caption)
                .foregroundStyle(VNTheme.textSecondary)
        }
        .onChange(of: selectedItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let images = await Self.imageData(from: items)
                await MainActor.run {
                    pendingImages = images
                    selectedItems = []
                    showTargetDialog = !images.isEmpty
                    if images.isEmpty {
                        store.statusText = uiStatic("沒有讀取到可用圖片。")
                    }
                }
            }
        }
        .confirmationDialog(uiStatic("選擇圖片用途"), isPresented: $showTargetDialog, titleVisibility: .visible) {
            ForEach(NovelAIImageImportTarget.allCases) { target in
                Button(target.title) {
                    apply(target)
                }
            }
            Button(uiStatic("取消"), role: .cancel) {
                pendingImages = []
            }
        } message: {
            Text(pendingImages.count > 1 ? uiStatic("已選擇 \(pendingImages.count) 張圖片。") : uiStatic("已選擇 1 張圖片。"))
        }
    }

    private func apply(_ target: NovelAIImageImportTarget) {
        let result = Self.apply(target: target, images: pendingImages, to: settings)
        settings = result.settings
        store.statusText = result.statusText
        pendingImages = []
    }

    static func apply(
        target: NovelAIImageImportTarget,
        images: [Data],
        to currentSettings: NovelAIStudioSettings
    ) -> NovelAITargetedImageImportResult {
        guard !images.isEmpty else {
            return NovelAITargetedImageImportResult(settings: currentSettings, statusText: uiStatic("沒有讀取到可用圖片。"))
        }
        var next = currentSettings
        switch target {
        case .vibe:
            let baseCount = next.vibeTransferImages.count
            next.vibeTransferImages.append(contentsOf: images.enumerated().map { index, data in
                NovelAIReferenceImage(
                    name: "Vibe Transfer \(baseCount + index + 1)",
                    type: "vibe",
                    imageData: data,
                    strength: 0.6,
                    noise: 1,
                    enabled: true
                )
            })
            return NovelAITargetedImageImportResult(settings: next, statusText: uiStatic("已加入 \(images.count) 張 Vibe Transfer 圖片。"))
        case .imageToImage:
            next.imageToImageImageData = images[0]
            return NovelAITargetedImageImportResult(settings: next, statusText: uiStatic("已設定 Image2Image 圖片。"))
        case .precise:
            let baseCount = next.preciseReferenceImages.count
            next.preciseReferenceImages.append(contentsOf: images.enumerated().map { index, data in
                NovelAIReferenceImage(
                    name: "Precise Reference \(baseCount + index + 1)",
                    type: "precise",
                    imageData: data,
                    strength: 1,
                    noise: 1,
                    enabled: true
                )
            })
            return NovelAITargetedImageImportResult(settings: next, statusText: uiStatic("已加入 \(images.count) 張 Precise Reference 圖片。"))
        case .metadata:
            if let imported = NovelAIClient.importMetadata(fromImageData: images[0], into: next) {
                return NovelAITargetedImageImportResult(
                    settings: imported.settings,
                    statusText: imported.fallbackMessage ?? uiStatic("已從圖片 metadata 還原設定。")
                )
            }
            return NovelAITargetedImageImportResult(settings: next, statusText: uiStatic("這張圖片沒有可讀取的 NovelAI PNG metadata。"))
        }
    }

    private static func imageData(from items: [PhotosPickerItem]) async -> [Data] {
        var images: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                images.append(data)
            }
        }
        return images
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
                    TextField(uiStatic("名稱"), text: $reference.name)
                    Toggle(uiStatic("啟用"), isOn: $reference.enabled)
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
                    ImagePickerButton(title: reference.imageData == nil ? uiStatic("選擇圖片") : uiStatic("更換圖片")) { data in
                        reference.imageData = data
                    }
                    Button(role: .destructive) {
                        references = Self.referencesAfterDeleting(id: reference.id, from: references)
                    } label: {
                        Label(uiStatic("刪除圖片"), systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                references.remove(atValidOffsets: offsets)
            }
            Button(uiStatic("新增 Reference")) {
                references.append(NovelAIReferenceImage(name: "\(title) \(references.count + 1)", type: type))
            }
        }
    }

    static func referencesAfterDeleting(id: String, from references: [NovelAIReferenceImage]) -> [NovelAIReferenceImage] {
        references.filter { $0.id != id }
    }
}

struct ImagePickerButton: View {
    var title: String
    var onData: (Data) -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Label(uiStatic(title), systemImage: "photo")
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
            Section(uiStatic("尺寸")) {
                Picker("Preset", selection: $settings.sizePreset) {
                    Text("Portrait").tag("portrait")
                    Text("Landscape").tag("landscape")
                    Text("Square").tag("square")
                    Text("Custom").tag("custom")
                }
                .onChange(of: settings.sizePreset) { _, value in
                    applySizePreset(value)
                }
                Stepper(uiStatic("寬 \(settings.imageSettings.width)"), value: $settings.imageSettings.width, in: 512...1536, step: 64)
                Stepper(uiStatic("高 \(settings.imageSettings.height)"), value: $settings.imageSettings.height, in: 512...1536, step: 64)
                Stepper("Samples \(settings.imageSettings.samples)", value: $settings.imageSettings.samples, in: 1...8)
            }
            Section("AI Settings") {
                NovelAIModelPicker(model: $settings.imageSettings.model, title: "模型")
                Stepper("Steps \(settings.imageSettings.steps)", value: $settings.imageSettings.steps, in: 1...50)
                Slider(value: $settings.imageSettings.scale, in: 1...12) { Text("Guidance") }
                Text("Guidance \(settings.imageSettings.scale, specifier: "%.1f")")
                    .font(.caption)
                Slider(value: $settings.imageSettings.cfgRescale, in: 0...1.5) { Text("CFG Rescale") }
                Text("CFG Rescale \(settings.imageSettings.cfgRescale, specifier: "%.2f")")
                    .font(.caption)
                Picker("Sampler", selection: $settings.imageSettings.sampler) {
                    ForEach(NovelAIOptionLists.samplerOptions, id: \.id) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                Picker("Noise Schedule", selection: $settings.imageSettings.noiseSchedule) {
                    ForEach(NovelAIOptionLists.noiseScheduleOptions, id: \.id) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                Toggle("Variety+", isOn: $settings.imageSettings.varietyPlus)
                TextField("Seed", text: seedBinding)
                    .keyboardType(.numberPad)
            }
            Section(uiStatic("成本預估")) {
                Label(uiStatic("約 \(NovelAIClient.estimatedAnlas(for: settings)) Anlas"), systemImage: "creditcard")
                    .font(.headline)
                Text(uiStatic("按網頁端公式本地估算：尺寸、Steps、Samples、Image2Image、Vibe Transfer 與 Precise Reference 都會影響結果；實際扣除以 NovelAI 為準。"))
                    .font(.caption)
                    .foregroundStyle(VNTheme.textSecondary)
            }
            Section("Metadata Import") {
                ImagePickerButton(title: uiStatic("選擇圖片讀取 metadata")) { data in
                    if let result = NovelAIClient.importMetadata(fromImageData: data, into: settings) {
                        settings = result.settings
                        store.statusText = result.fallbackMessage ?? uiStatic("已從圖片 metadata 還原設定。")
                    } else {
                        store.statusText = uiStatic("這張圖片沒有可讀取的 NovelAI PNG metadata。")
                    }
                }
                Text(uiStatic("支援網頁端寫入的 NovelAIMetadata / TimeTavernNovelAIMetadata，以及 NovelAI 原生 Comment。"))
                    .font(.caption)
                    .foregroundStyle(VNTheme.textSecondary)
                TextEditor(text: $settings.metadataDraft)
                    .frame(minHeight: 110)
                Button(uiStatic("套用 Metadata")) {
                    let result = NovelAIClient.importMetadata(settings.metadataDraft, into: settings)
                    settings = result.settings
                    if let fallback = result.fallbackMessage {
                        store.statusText = fallback
                    } else {
                        store.statusText = uiStatic("Metadata 已套用。")
                    }
                }
            }
            Section("Generate") {
                Stepper(uiStatic("生成數量 \(loopCountTitle)"), value: $settings.loopCount, in: 0...9999)
                Text(uiStatic("0 代表一直生成，直到按 Stop Loop；每次生成完成後會短暫等待再開始下一次。"))
                    .font(.caption)
                    .foregroundStyle(VNTheme.textSecondary)
                Button {
                    store.generateNovelAIImage(studioSettings: settings)
                } label: {
                    Label(store.isNovelAIGenerating && !store.isNovelAILoopRunning ? uiStatic("生成中...") : "Generate", systemImage: "sparkles")
                }
                .disabled(!NovelAIView.canGenerate(settings: settings, key: store.novelAIKey) || store.isNovelAIGenerating)
                Button {
                    store.loopGenerateNovelAIImages(studioSettings: settings)
                } label: {
                    Label(store.isNovelAILoopRunning ? "Stop Loop" : "Loop Generate", systemImage: store.isNovelAILoopRunning ? "stop.fill" : "repeat")
                }
                .disabled(!store.isNovelAILoopRunning && (!NovelAIView.canGenerate(settings: settings, key: store.novelAIKey) || store.isNovelAIGenerating))
            }
        }
        .visualNovelListChrome()
    }

    private var loopCountTitle: String {
        settings.loopCount == 0 ? "∞" : "\(settings.loopCount)"
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
    @State private var previewImage: ImagePreviewItem?
    static let generatedImagesOpenPreviewOnTap = true

    var body: some View {
        List {
            ForEach(store.state.novelAIAlbum) { item in
                VStack(alignment: .leading, spacing: 8) {
                    if let image = UIImage(data: item.imageData) {
                        Button {
                            previewImage = ImagePreviewItem(title: item.fileName, imageData: item.imageData)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                GeneratedImageZoomBadge()
                                    .padding(8)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(uiStatic("放大生成圖片"))
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
                                Label(uiStatic("匯出"), systemImage: "square.and.arrow.up")
                            }
                            .font(.caption)
                        }
                        Button(role: .destructive) {
                            store.deleteNovelAIAlbumItem(id: item.id)
                        } label: {
                            Label(uiStatic("刪除"), systemImage: "trash")
                        }
                        .font(.caption)
                    }
                }
            }
            .onDelete(perform: store.deleteNovelAIAlbumItems)
        }
        .visualNovelListChrome()
        .fullScreenCover(item: $previewImage) { item in
            GeneratedImagePreview(item: item)
        }
    }

    private static func exportURL(for item: NovelAIAlbumItem) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.fileName)
        try? item.imageData.write(to: url)
        return url
    }

    static func itemsAfterDeleting(id: String, from items: [NovelAIAlbumItem]) -> [NovelAIAlbumItem] {
        items.filter { $0.id != id }
    }
}

struct TimeTrackingWordListEditor: View {
    var title: String
    var help: String
    var examples: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(uiStatic(title))
                .font(.headline)
            Text(uiStatic(help))
                .font(.caption)
                .foregroundStyle(VNTheme.textSecondary)
            Text(uiStatic("例：\(examples)"))
                .font(.caption2)
                .foregroundStyle(VNTheme.textSecondary)
            TextEditor(text: $text)
                .frame(minHeight: 72)
                .overlay(alignment: .topLeading) {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(uiStatic(examples.replacingOccurrences(of: " / ", with: "\n")))
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                            .padding(6)
                    }
                }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @State private var showRoleJSONImporter = false
    @State private var showModeJSONImporter = false
    @State private var showRestoreDefaultsConfirm = false

    static let deepSeekMultiKeyHelp = "可加入多條 DeepSeek API key。主聊天會在已填 key 間輪流使用；Key 2+ 保留作處理/壓縮用途，對齊網頁端 CHAT_API_KEY2、DEEPSEEK_API_KEY2 的設計。"
    static let deepSeekCacheHitHelp = "DeepSeek 的 prompt cache 由服務端自動計算。當 system prompt、角色卡、壓縮內容等前綴保持穩定時，usage 可能回傳 Cache Hit / Cache Miss；AI Logs 會顯示命中率。不同 key 或帳號的 cache 統計可能不共用。"
    static let roleCardImportSymbolName = "person.crop.square"
    static let uiLanguageHelp = "對齊網頁端簡繁轉換：只影響 app UI 顯示；不會改寫角色卡、Prompt、對話、AI logs 或匯入匯出的 JSON。"
    static let timeTrackingUsageHelp = [
        "配合詞與 +1天關鍵字在 5 字內時，會自動 +1 天，例如「現在第二天早上」。",
        "配合詞與「3天後 / 三天後」在 5 字內時，會自動加對應天數，例如「已經三天後的晚上」。",
        "配合詞與「第3天」在 5 字內時，會直接把天數改成第 3 天，例如「現在第3天中午」。",
        "開場對話與用戶所有輸入可以不用配合詞直接更改時間；AI 生成內容需要配合詞輔助判斷。",
        "不改詞與配合詞在 5 字內時，本次不會改天數，也不會改早中晚，例如「等到早上再說」。",
        "自動切換會按早上→中午→晚上→早上前進，晚上→早上會自動 +1 天；可在對話加入 {保持時間} 延後目前設定的回合數。"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(ui("顯示"))) {
                    Picker(ui("UI 語言"), selection: $store.state.uiLanguage) {
                        ForEach(UILanguageMode.allCases) { language in
                            Text(language.title(in: store.state.uiLanguage)).tag(language)
                        }
                    }
                    Text(ui(Self.uiLanguageHelp))
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                    Text(ui("預覽：簡繁轉換會把 UI 顯示成繁體或簡體。"))
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                }
                Section("DeepSeek") {
                    Text(Self.deepSeekMultiKeyHelp)
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                    SecureField(uiStatic("主 DeepSeek API Key"), text: $store.deepSeekKey)
                    ForEach(Array(store.deepSeekProcessingKeys.indices), id: \.self) { index in
                        HStack {
                            SecureField("DeepSeek API Key \(index + 2)", text: processingKeyBinding(index))
                            Button(role: .destructive) {
                                guard store.deepSeekProcessingKeys.indices.contains(index) else { return }
                                store.deepSeekProcessingKeys.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(uiStatic("刪除 DeepSeek API Key \(index + 2)"))
                        }
                    }
                    Button {
                        store.deepSeekProcessingKeys.append("")
                    } label: {
                        Label(uiStatic("新增 DeepSeek API Key"), systemImage: "plus")
                    }
                    Text(Self.deepSeekCacheHitHelp)
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                    TextField("Base URL", text: $store.state.apiSettings.deepSeekBaseURL)
                    TextField("Model", text: $store.state.apiSettings.deepSeekModel)
                    Stepper("Max Tokens \(store.state.apiSettings.maxTokens)", value: $store.state.apiSettings.maxTokens, in: 512...64000, step: 512)
                    Slider(value: $store.state.apiSettings.temperature, in: 0...1.5) { Text("Temperature") }
                    Button(uiStatic("測試 DeepSeek")) { store.testDeepSeek() }
                }
                Section("NovelAI") {
                    SecureField("NovelAI API Token", text: $store.novelAIKey)
                    TextField("Image API", text: $store.state.apiSettings.naiImageBaseURL)
                    TextField("Primary API", text: $store.state.apiSettings.naiPrimaryBaseURL)
                    Button(uiStatic("測試 NovelAI")) { store.testNovelAI() }
                }
                Section(uiStatic("使用者")) {
                    TextField(uiStatic("稱呼"), text: $store.state.userProfile.userName)
                    TextEditor(text: $store.state.userProfile.extraPrompt).frame(minHeight: 90)
                }
                Section(uiStatic("時間追蹤")) {
                    Toggle(uiStatic("啟用"), isOn: $store.state.timeTracking.enabled)
                    Stepper(uiStatic("第 \(store.state.timeTracking.currentDayNumber) 天"), value: $store.state.timeTracking.currentDayNumber, in: 1...9999)
                    Stepper(uiStatic("\(store.state.timeTracking.currentYear) 年"), value: $store.state.timeTracking.currentYear, in: 1...9999)
                    Stepper(uiStatic("\(store.state.timeTracking.currentMonth) 月"), value: $store.state.timeTracking.currentMonth, in: 1...12)
                    Stepper(uiStatic("\(store.state.timeTracking.currentDate) 日"), value: $store.state.timeTracking.currentDate, in: 1...31)
                    Picker(uiStatic("當前時間"), selection: $store.state.timeTracking.currentPeriod) {
                        ForEach(TimeTrackingPeriod.allCases) { period in
                            Text(period.title).tag(period.rawValue)
                        }
                    }
                    Toggle(uiStatic("自動早中晚切換"), isOn: $store.state.timeTracking.autoPeriod.enabled)
                    Stepper(uiStatic("每 \(store.state.timeTracking.autoPeriod.roundsPerPeriod) 回合切換"), value: $store.state.timeTracking.autoPeriod.roundsPerPeriod, in: 1...20)
                    Text(uiStatic("目前計數 \(store.state.timeTracking.autoPeriod.turnsSinceChange) / \(store.state.timeTracking.autoPeriod.roundsPerPeriod)。輸入 {保持時間} 會重置計數。"))
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                    ForEach(Self.timeTrackingUsageHelp, id: \.self) { help in
                        Text(help)
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    }
                    TimeTrackingWordListEditor(
                        title: "+1 天關鍵字",
                        help: "命中後加一天；配合詞在附近時最穩定，用戶輸入與開場可直接命中。",
                        examples: "下一天 / 第二天 / 隔天 / 明天",
                        text: wordListBinding(\.nextDayWords)
                    )
                    TimeTrackingWordListEditor(
                        title: "配合詞",
                        help: "用來確認句子真的在描述時間變化；和第 N 天、N 天後、早中晚詞靠近時才觸發。",
                        examples: "來到 / 已經 / 現在 / 到了",
                        text: wordListBinding(\.connectorWords)
                    )
                    TimeTrackingWordListEditor(
                        title: "不改詞",
                        help: "阻止誤判。它和配合詞靠近時，本次不改天數，也不改早中晚。",
                        examples: "等到 / 等一下 / 的時候",
                        text: wordListBinding(\.noChangeWords)
                    )
                    TimeTrackingWordListEditor(
                        title: "早上欄位",
                        help: "命中後把當前時間設為早上；如果原本是晚上，切到早上會順便 +1 天。",
                        examples: "早上 / 早晨 / 早餐",
                        text: wordListBinding(\.morningWords)
                    )
                    TimeTrackingWordListEditor(
                        title: "中午欄位",
                        help: "命中後把當前時間設為中午或下午，用於午餐、下午等描述。",
                        examples: "中午 / 下午 / 午餐",
                        text: wordListBinding(\.noonWords)
                    )
                    TimeTrackingWordListEditor(
                        title: "晚上欄位",
                        help: "命中後把當前時間設為晚上，用於夜晚、晚餐、深夜等描述。",
                        examples: "晚上 / 夜晚 / 晚餐",
                        text: wordListBinding(\.eveningWords)
                    )
                }
                Section(uiStatic("JSON / 圖片匯入")) {
                    Button {
                        showRoleJSONImporter = true
                    } label: {
                        Label(uiStatic("匯入角色卡 JSON / PNG / JPG"), systemImage: Self.roleCardImportSymbolName)
                    }
                    Text(uiStatic("支援網頁端 JSON、SillyTavern chara_card_v2，以及含角色卡 metadata 的 PNG/JPG。"))
                        .font(.caption)
                        .foregroundStyle(VNTheme.textSecondary)
                    Button {
                        showModeJSONImporter = true
                    } label: {
                        Label(uiStatic("匯入模式 JSON"), systemImage: "slider.horizontal.below.square.filled.and.square")
                    }
                }
                Section(uiStatic("預設")) {
                    if let localDefaults = store.state.localDefaults {
                        Text(uiStatic("本機預設：\(localDefaults.roleCards.count) 張角色卡、\(localDefaults.promptModes.count) 個 Prompt 模式。"))
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    } else if let summary = store.bundledWebDefaultsSummary() {
                        Text(uiStatic("尚未保存本機預設。可回落網頁 bundle 預設：\(summary.roleCardCount) 張角色卡、\(summary.promptModeCount) 個 Prompt 模式。使用者：\(summary.userDisplayName)。"))
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    } else {
                        Text(uiStatic("尚未保存本機預設，且找不到 bundle 內的網頁預設。"))
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    }
                    Button {
                        store.saveCurrentAsLocalDefaults()
                    } label: {
                        Label(uiStatic("儲存目前為預設"), systemImage: "tray.and.arrow.down.fill")
                    }
                    Button(role: .destructive) {
                        showRestoreDefaultsConfirm = true
                    } label: {
                        Label(uiStatic("還原預設"), systemImage: "arrow.counterclockwise")
                    }
                }
                if !store.statusText.isEmpty {
                    Section(uiStatic("狀態")) {
                        Text(store.statusText)
                    }
                }
            }
            .visualNovelListChrome()
            .navigationTitle(uiStatic("設定"))
            .toolbar {
                Button(uiStatic("保存")) {
                    store.saveSecrets()
                    store.persist()
                }
            }
            .fileImporter(isPresented: $showRoleJSONImporter, allowedContentTypes: [.json, .png, .jpeg]) { result in
                if case let .success(url) = result {
                    _ = url.startAccessingSecurityScopedResource()
                    store.importRoleCardFile(url: url)
                    url.stopAccessingSecurityScopedResource()
                }
            }
            .fileImporter(isPresented: $showModeJSONImporter, allowedContentTypes: [.json]) { result in
                if case let .success(url) = result {
                    _ = url.startAccessingSecurityScopedResource()
                    store.importPromptModeJSON(url: url)
                    url.stopAccessingSecurityScopedResource()
                }
            }
            .alert(uiStatic("還原預設？"), isPresented: $showRestoreDefaultsConfirm) {
                Button(uiStatic("取消"), role: .cancel) {}
                Button(uiStatic("還原"), role: .destructive) {
                    store.restoreDefaultsPreferLocal()
                }
            } message: {
                Text(uiStatic("會覆蓋角色卡、Prompt 模式、使用者資料、時間追蹤、API 與 NovelAI 設定；Keychain、相簿、AI logs、saved sessions 會保留，並建立還原前備份。"))
            }
        }
    }

    static func localizedDisplayText(_ text: String, language: UILanguageMode) -> String {
        UIChineseTextConverter.convert(text, language: language)
    }

    private func ui(_ text: String) -> String {
        Self.localizedDisplayText(text, language: store.state.uiLanguage)
    }

    private func processingKeyBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard store.deepSeekProcessingKeys.indices.contains(index) else { return "" }
                return store.deepSeekProcessingKeys[index]
            },
            set: { value in
                guard store.deepSeekProcessingKeys.indices.contains(index) else { return }
                store.deepSeekProcessingKeys[index] = value
            }
        )
    }

    private func wordListBinding(_ keyPath: WritableKeyPath<TimeTrackingRulesConfig, [String]>) -> Binding<String> {
        Binding(
            get: { store.state.timeTracking.config[keyPath: keyPath].joined(separator: "\n") },
            set: { value in
                store.state.timeTracking.config[keyPath: keyPath] = value
                    .split(whereSeparator: { "\n,，、;；|/／".contains($0) })
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

struct LogView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Environment(\.dismiss) private var dismiss
    static let hasCloseToolbarAction = true

    var body: some View {
        NavigationStack {
            List(store.state.aiLogs) { log in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        if !log.usageSummary.isEmpty {
                            logBlock(title: uiStatic("本次 Token 消耗"), text: log.usageSummary, accent: VNTheme.accentSoft)
                        }
                        logBlock(
                            title: uiStatic("送給 AI 的內容"),
                            text: Self.formatMessages(log.requestMessages)
                        )
                        if !log.debugReasoningContent.isEmpty {
                            logBlock(title: uiStatic("模型思考過程"), text: log.debugReasoningContent, accent: VNTheme.textSecondary)
                        }
                        logBlock(
                            title: log.error.isEmpty ? uiStatic("AI 輸出") : uiStatic("AI 輸出 / 錯誤內容"),
                            text: log.error.isEmpty ? log.responseText : "\(log.responseText)\n\n[Error]\n\(log.error)",
                            accent: log.error.isEmpty ? .white : .red
                        )
                    }
                    .padding(.vertical, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Self.formatPurpose(log.purpose))｜\(log.model.isEmpty ? uiStatic("未指定模型") : log.model)")
                            .font(.headline)
                        HStack(spacing: 8) {
                            Text(Self.formatStatus(log.status))
                                .font(.caption)
                                .foregroundStyle(log.status == "error" ? .red : VNTheme.textSecondary)
                            if !log.usageSummary.isEmpty {
                                Text(log.usageSummary)
                                    .font(.caption)
                                    .foregroundStyle(VNTheme.accentSoft)
                                    .lineLimit(1)
                            }
                        }
                        Text(log.responsePreview.isEmpty ? log.responseText : log.responsePreview)
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                            .lineLimit(3)
                    }
                }
            }
            .visualNovelListChrome()
            .navigationTitle("AI Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(uiStatic("關閉")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func logBlock(title: String, text: String, accent: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VNTheme.accentSoft)
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? uiStatic("無") : text)
                .font(.caption.monospaced())
                .foregroundStyle(accent)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(VNTheme.panel.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    static func formatPurpose(_ purpose: String) -> String {
        if purpose.hasPrefix("context_compression") {
            return uiStatic("模型內容處理")
        }
        if purpose == "chat_expand" {
            return uiStatic("補寫")
        }
        return uiStatic("正文輸出")
    }

    static func formatStatus(_ status: String) -> String {
        if status == "error" { return uiStatic("失敗") }
        if status == "skipped" { return uiStatic("略過") }
        return uiStatic("成功")
    }

    static func formatMessages(_ messages: [ChatAPIMessage]) -> String {
        guard !messages.isEmpty else { return uiStatic("無") }
        return messages.enumerated()
            .map { index, message in
                "#\(index + 1) \(message.role)\n\(message.content.isEmpty ? uiStatic("(空白)") : message.content)"
            }
            .joined(separator: "\n\n----------------\n\n")
    }
}

struct ModelContentView: View {
    @EnvironmentObject private var store: TimeTavernStore
    @Environment(\.dismiss) private var dismiss
    static let hasCloseToolbarAction = true

    var body: some View {
        NavigationStack {
            List {
                let visibleIndices = Self.visiblePromptModeIndices(state: store.state)
                Section(uiStatic("目前角色卡")) {
                    if let roleCard = store.state.activeRoleCard {
                        Text("\(uiStatic("角色卡"))：\(roleCard.name.isEmpty ? uiStatic("未命名") : roleCard.name)")
                        Text("\(uiStatic("顯示模式"))：\(Self.visiblePromptModeNames(state: store.state).joined(separator: " / "))")
                            .foregroundStyle(VNTheme.accentSoft)
                        Text(uiStatic("模型內容只顯示目前角色卡會命中的模式，例如多人、開放世界或自訂模式。"))
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    } else {
                        Text(uiStatic("尚未開始角色卡"))
                            .foregroundStyle(VNTheme.textSecondary)
                        Text(uiStatic("請先在角色頁啟用角色卡；模型內容會按角色卡的 Prompt 模式顯示。"))
                            .font(.caption)
                            .foregroundStyle(VNTheme.textSecondary)
                    }
                }
                if visibleIndices.isEmpty {
                    Section(uiStatic("模型內容")) {
                        Text(Self.emptyStateText(state: store.state))
                            .foregroundStyle(VNTheme.textSecondary)
                    }
                } else {
                    ForEach(visibleIndices, id: \.self) { modeIndex in
                        if store.state.promptModes.indices.contains(modeIndex) {
                            let mode = store.state.promptModes[modeIndex]
                            if mode.compressionProfiles.isEmpty {
                                Section(mode.name) {
                                    Text(uiStatic("此模式沒有大模型內容。"))
                                        .foregroundStyle(VNTheme.textSecondary)
                                }
                            } else {
                                ForEach($store.state.promptModes[modeIndex].compressionProfiles) { $profile in
                                    Section("\(mode.name) · \(profile.name)") {
                                        TextEditor(text: $profile.summary).frame(minHeight: 150)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .visualNovelListChrome()
            .navigationTitle(uiStatic("模型內容"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(uiStatic("關閉")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(uiStatic("保存")) { store.persist() }
                }
            }
        }
    }

    static func visiblePromptModeIndices(state: AppState) -> [Int] {
        guard let roleCard = state.activeRoleCard else { return [] }
        let promptModeID = roleCard.promptModeId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !promptModeID.isEmpty {
            let idMatches = state.promptModes.indices.filter { state.promptModes[$0].id == promptModeID }
            if !idMatches.isEmpty {
                return Array(idMatches)
            }
        }
        let roleMode = roleCard.mode.rawValue
        let modeMatches = state.promptModes.indices.filter {
            state.promptModes[$0].mode == roleMode || state.promptModes[$0].id == roleMode
        }
        return Array(modeMatches)
    }

    static func visiblePromptModeIDs(state: AppState) -> [String] {
        visiblePromptModeIndices(state: state).map { state.promptModes[$0].id }
    }

    static func visiblePromptModeNames(state: AppState) -> [String] {
        let names = visiblePromptModeIndices(state: state).map { state.promptModes[$0].name }
        if !names.isEmpty { return names }
        if let roleCard = state.activeRoleCard {
            return [roleCard.mode.title]
        }
        return []
    }

    static func emptyStateText(state: AppState) -> String {
        guard let roleCard = state.activeRoleCard else {
            return uiStatic("尚未啟用角色卡。")
        }
        return "\(uiStatic("找不到角色卡指定的 Prompt 模式"))：\(roleCard.promptModeId.isEmpty ? roleCard.mode.rawValue : roleCard.promptModeId)"
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
                Stepper(uiStatic("輪數 \(turns)"), value: $turns, in: 1...20)
                TextEditor(text: $message).frame(minHeight: 160)
            }
            .visualNovelListChrome()
            .navigationTitle(uiStatic("自動推演"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(uiStatic("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(uiStatic("開始")) {
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
