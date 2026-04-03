import AppKit
import ChooseBrowserCore
import SwiftUI

@MainActor
final class ConfigurationWindowController: NSWindowController {
    private let viewModel: ConfigurationViewModel

    init(
        router: BrowserRouter = BrowserRouter(),
        onRequestQuit: @escaping () -> Void,
        onRequestUninstall: @escaping () -> Void
    ) {
        self.viewModel = ConfigurationViewModel(
            router: router,
            onRequestQuit: onRequestQuit,
            onRequestUninstall: onRequestUninstall
        )

        let hostingController = NSHostingController(rootView: ConfigurationView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppIdentity.displayName
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 920, height: 640))
        window.minSize = NSSize(width: 820, height: 560)
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        viewModel.load()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndActivate() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class ConfigurationViewModel: ObservableObject {
    @Published var profileOptions: [ProfileOption] = []
    @Published var unmatchedLinkBehaviorMode: UnmatchedLinkBehaviorMode = .lastActiveBrowser
    @Published var defaultProfileEmail: String?
    @Published var defaultBrowserStatus = DefaultBrowserStatus(isDefaultForHTTP: false, isDefaultForHTTPS: false)
    @Published var lastUsedProfileEmail: String?
    @Published var logEntries: [AppLogEntry] = []
    @Published var rules: [EditableRule] = []
    @Published var draftPattern = ""
    @Published var draftProfileEmail = ""
    @Published var configPath = ""
    @Published var logPath = ""
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let router: BrowserRouter
    private let logStore: AppLogStore
    private let defaultBrowserService: DefaultBrowserService
    private let onRequestQuit: () -> Void
    private let onRequestUninstall: () -> Void
    private var isHydrating = false

    init(
        router: BrowserRouter,
        logStore: AppLogStore = .shared,
        defaultBrowserService: DefaultBrowserService = DefaultBrowserService(),
        onRequestQuit: @escaping () -> Void,
        onRequestUninstall: @escaping () -> Void
    ) {
        self.router = router
        self.logStore = logStore
        self.defaultBrowserService = defaultBrowserService
        self.onRequestQuit = onRequestQuit
        self.onRequestUninstall = onRequestUninstall
        self.configPath = router.configurationFileURL().path(percentEncoded: false)
        self.logPath = logStore.logFileURL.path(percentEncoded: false)
    }

    var canAddDraftRule: Bool {
        draftPattern.trimmedNilIfEmpty != nil && draftProfileEmail.trimmedNilIfEmpty != nil
    }

    func load() {
        do {
            isHydrating = true

            let catalog = try router.availableProfiles()
            let config = try router.loadConfig()
            let knownEmails = catalog.availableEmails

            profileOptions = ProfileOption.merged(
                chromeProfiles: catalog.profiles,
                configuredEmails: Set(config.rules.map(\.profileEmail)).union([config.defaultProfileEmail].compactMap { $0 }),
                lastUsedDirectoryName: catalog.lastUsedDirectoryName
            )
            unmatchedLinkBehaviorMode = config.effectiveUnmatchedLinkBehaviorMode
            defaultBrowserStatus = defaultBrowserService.currentStatus(bundleIdentifier: Bundle.main.bundleIdentifier)
            defaultProfileEmail = config.defaultProfileEmail
            lastUsedProfileEmail = catalog.email(forDirectoryName: catalog.lastUsedDirectoryName)
            rules = config.rules.map(EditableRule.init)
            draftPattern = ""
            draftProfileEmail = config.defaultProfileEmail ?? profileOptions.first?.email ?? ""

            if knownEmails.isEmpty {
                statusMessage = "\(AppIdentity.displayName) could not find signed-in Chrome profile emails yet."
            } else {
                statusMessage = "Loaded \(rules.count) rule" + (rules.count == 1 ? "." : "s.")
            }

            loadLogs()
            errorMessage = nil
            isHydrating = false
        } catch {
            isHydrating = false
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    func addDraftRule() {
        do {
            let committedRule = try buildDraftRule(index: rules.count)
            rules.append(EditableRule(rule: committedRule))
            draftPattern = ""
            if draftProfileEmail.trimmedNilIfEmpty == nil {
                draftProfileEmail = defaultProfileEmail ?? profileOptions.first?.email ?? ""
            }
            try persistCommittedState(status: "Rule added.")
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }

        do {
            try persistCommittedState(status: "Rule removed.")
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    func saveFallbackBehaviorIfNeeded() {
        guard !isHydrating else {
            return
        }

        do {
            try persistCommittedState(status: "Unmatched link behavior updated.")
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    func revealConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([router.configurationFileURL()])
    }

    func loadLogs() {
        logEntries = logStore.loadEntries()
    }

    func revealLogsInFinder() {
        logStore.revealInFinder()
    }

    func openDefaultBrowserSettings() {
        defaultBrowserService.openSettings()
    }

    func quitApplication() {
        onRequestQuit()
    }

    func requestUninstall() {
        onRequestUninstall()
    }

    private func persistCommittedState(status: String) throws {
        let config = try committedConfig()
        try router.saveConfig(config)
        defaultProfileEmail = config.defaultProfileEmail
        statusMessage = status
        errorMessage = nil
    }

    private func committedConfig() throws -> ChooseBrowserConfig {
        let committedRules = try rules.enumerated().map { index, rule in
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            let profileEmail = rule.profileEmail.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !pattern.isEmpty else {
                throw ChooseBrowserError.invalidConfiguration("Rule \(index + 1) is missing a URL pattern.")
            }

            guard !profileEmail.isEmpty else {
                throw ChooseBrowserError.invalidConfiguration("Rule \(index + 1) is missing a profile email.")
            }

            return URLRule(pattern: pattern, profileEmail: profileEmail)
        }

        return ChooseBrowserConfig(
            unmatchedLinkBehaviorMode: unmatchedLinkBehaviorMode,
            defaultProfileEmail: defaultProfileEmail?.trimmedNilIfEmpty,
            rules: committedRules
        )
    }

    private func buildDraftRule(index: Int) throws -> URLRule {
        let pattern = draftPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileEmail = draftProfileEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pattern.isEmpty else {
            throw ChooseBrowserError.invalidConfiguration("Rule \(index + 1) is missing a URL pattern.")
        }

        guard !profileEmail.isEmpty else {
            throw ChooseBrowserError.invalidConfiguration("Rule \(index + 1) is missing a profile email.")
        }

        return URLRule(pattern: pattern, profileEmail: profileEmail)
    }
}

struct ConfigurationView: View {
    @ObservedObject var viewModel: ConfigurationViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header

                TabView {
                    routingTab
                        .tabItem {
                            Label("Rules", systemImage: "list.bullet.rectangle")
                        }

                    advancedTab
                        .tabItem {
                            Label("Advanced", systemImage: "slider.horizontal.3")
                        }

                    logsTab
                        .tabItem {
                            Label("Logs", systemImage: "text.append")
                        }
                }
            }
            .padding(18)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var routingTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !viewModel.defaultBrowserStatus.isDefaultForWebLinks {
                defaultBrowserWarningSection
            }

            rulesSection
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var advancedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                unmatchedLinksSection
                defaultBrowserDetailsSection
                appDataSection
                actionsSection
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: viewModel.unmatchedLinkBehaviorMode) { _ in
            viewModel.saveFallbackBehaviorIfNeeded()
        }
        .onChange(of: viewModel.defaultProfileEmail) { _ in
            if viewModel.unmatchedLinkBehaviorMode == .chromeProfile {
                viewModel.saveFallbackBehaviorIfNeeded()
            }
        }
    }

    private var logsTab: some View {
        logsSection
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.loadLogs()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 10) {
                Text(AppIdentity.displayName)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Configure where to open links.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    HeaderPill(title: "\(viewModel.rules.count) rule" + (viewModel.rules.count == 1 ? "" : "s"), systemImage: "list.bullet.rectangle")
                    HeaderPill(
                        title: viewModel.defaultBrowserStatus.isDefaultForWebLinks ? "Default browser ready" : "Needs default browser",
                        systemImage: viewModel.defaultBrowserStatus.isDefaultForWebLinks ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: viewModel.defaultBrowserStatus.isDefaultForWebLinks ? .green : .orange
                    )
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var defaultBrowserWarningSection: some View {
        AppSectionCard(
            title: "Action Needed",
            systemImage: "exclamationmark.triangle.fill",
            tint: .orange
        ) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(AppIdentity.displayName) is not your default browser yet.")
                        .font(.headline)
                    Text("To make profile routing work from other apps, set \(AppIdentity.displayName) as the Default web browser in System Settings > Desktop & Dock.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open Settings") {
                    viewModel.openDefaultBrowserSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var unmatchedLinksSection: some View {
        AppSectionCard(
            title: "Unmatched Links",
            systemImage: "arrow.triangle.branch"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Behavior")
                            .font(.headline)
                        Picker("Unmatched links", selection: $viewModel.unmatchedLinkBehaviorMode) {
                            Text("Use last active browser")
                                .tag(UnmatchedLinkBehaviorMode.lastActiveBrowser)
                            Text("Use Chrome's last used profile")
                                .tag(UnmatchedLinkBehaviorMode.chromeLastUsed)
                            Text("Use a specific Chrome profile")
                                .tag(UnmatchedLinkBehaviorMode.chromeProfile)
                        }
                        .labelsHidden()
                    }

                    if viewModel.unmatchedLinkBehaviorMode == .chromeProfile {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Chrome Profile")
                                .font(.headline)
                            Picker("Chrome profile", selection: $viewModel.defaultProfileEmail) {
                                Text("Choose a profile")
                                    .tag(Optional<String>.none)

                                ForEach(viewModel.profileOptions) { option in
                                    Text(option.label)
                                        .tag(option.email as String?)
                                }
                            }
                            .labelsHidden()
                        }
                        .frame(maxWidth: 320, alignment: .leading)
                    }
                }

                Text(unmatchedLinksDescription)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(insetBackground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var defaultBrowserDetailsSection: some View {
        AppSectionCard(
            title: "Default Browser",
            systemImage: viewModel.defaultBrowserStatus.isDefaultForWebLinks ? "checkmark.circle.fill" : "network.badge.shield.half.filled",
            tint: viewModel.defaultBrowserStatus.isDefaultForWebLinks ? .green : .orange
        ) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.defaultBrowserStatus.isDefaultForWebLinks ? "\(AppIdentity.displayName) is the current default browser." : "\(AppIdentity.displayName) is not the current default browser.")
                        .font(.headline)
                    Text(viewModel.defaultBrowserStatus.isDefaultForWebLinks ? "Normal http and https links should route through this app." : "Use System Settings to make macOS send links here first.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open Settings") {
                    viewModel.openDefaultBrowserSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rulesSection: some View {
        AppSectionCard(
            title: "URL Rules",
            systemImage: "list.bullet.rectangle.portrait"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    HeaderPill(title: "First match wins", systemImage: "number")
                    HeaderPill(title: "Advanced tab controls unmatched links", systemImage: "slider.horizontal.3")
                }

                DraftRuleComposer(
                    pattern: $viewModel.draftPattern,
                    profileEmail: $viewModel.draftProfileEmail,
                    profileOptions: viewModel.profileOptions,
                    canAdd: viewModel.canAddDraftRule,
                    onAdd: viewModel.addDraftRule
                )

                if viewModel.rules.isEmpty {
                    EmptyRulesView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.rules) { rule in
                                CompactRuleRow(
                                    rule: rule,
                                    profileLabel: label(for: rule.profileEmail)
                                ) {
                                    viewModel.removeRule(id: rule.id)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var appDataSection: some View {
        AppSectionCard(
            title: "App Data",
            systemImage: "externaldrive.badge.gearshape"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.configPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(insetBackground)

                HStack(spacing: 10) {
                    Button("Reveal in Finder") {
                        viewModel.revealConfigInFinder()
                    }
                    Button("Reload") {
                        viewModel.load()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.08))
                    )
            }

            HStack(spacing: 10) {
                Button("Quit") {
                    viewModel.quitApplication()
                }
                .buttonStyle(.bordered)
                Button("Uninstall") {
                    viewModel.requestUninstall()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var logsSection: some View {
        AppSectionCard(
            title: "Event Log",
            systemImage: "text.append"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.logPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(insetBackground)

                HStack(spacing: 10) {
                    Button("Reload") {
                        viewModel.loadLogs()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Reveal in Finder") {
                        viewModel.revealLogsInFinder()
                    }
                    .buttonStyle(.bordered)
                }

                if viewModel.logEntries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No Logs Yet")
                            .font(.headline)
                        Text("Trigger a link open or auth flow, then come back here and reload.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.logEntries) { entry in
                                Text(entry.message)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(insetFill)
                                    )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private func label(for email: String) -> String {
        viewModel.profileOptions.first(where: { $0.email == email })?.label ?? email
    }

    private var unmatchedLinksDescription: String {
        switch viewModel.unmatchedLinkBehaviorMode {
        case .lastActiveBrowser:
            return "Unmatched links go to the most recently active browser app."
        case .chromeLastUsed:
            if let email = viewModel.lastUsedProfileEmail {
                return "Unmatched links open in Chrome's last used profile, currently \(email)."
            }
            return "Unmatched links open in Chrome's last used profile."
        case .chromeProfile:
            if let email = viewModel.defaultProfileEmail {
                return "Unmatched links always open in Chrome using \(email)."
            }
            return "Pick the Chrome profile that should receive unmatched links."
        }
    }

    private var insetBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(insetFill)
    }

    private var insetFill: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

struct DraftRuleComposer: View {
    @Binding var pattern: String
    @Binding var profileEmail: String
    let profileOptions: [ProfileOption]
    let canAdd: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New rule")
                        .font(.headline)
                    Text("Paste a URL prefix or wildcard pattern, then pick the Chrome profile that should receive it.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: onAdd) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add Rule")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canAdd)
                .help("Add this rule")
            }

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("URL Prefix Or Pattern")
                        .font(.headline)
                    PasteFriendlyTextField(text: $pattern, placeholder: "https://gitlab.com/eslfaceitgroup")
                        .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Chrome Profile")
                        .font(.headline)

                    if profileOptions.isEmpty {
                        PasteFriendlyTextField(text: $profileEmail, placeholder: "person@example.com")
                            .frame(width: 300)
                    } else {
                        Picker("Chrome profile", selection: $profileEmail) {
                            ForEach(profileOptions) { option in
                                Text(option.label)
                                    .tag(option.email)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 320, alignment: .leading)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.03), lineWidth: 1)
        )
    }
}

struct CompactRuleRow: View {
    let rule: EditableRule
    let profileLabel: String
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(rule.pattern)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Chrome")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(profileLabel)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .help("Delete this rule")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.03), lineWidth: 1)
        )
    }
}

struct EmptyRulesView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No rules yet")
                .font(.system(size: 18, weight: .semibold))
            Text("Paste a URL prefix above, choose the profile, and click + to add your first rule.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct AppSectionCard<Content: View>: View {
    let title: String
    var systemImage: String
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(tint.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

struct HeaderPill: View {
    let title: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct ProfileOption: Identifiable, Hashable {
    let email: String
    let label: String

    var id: String { email }

    static func merged(
        chromeProfiles: [ChromeProfile],
        configuredEmails: Set<String>,
        lastUsedDirectoryName: String?
    ) -> [ProfileOption] {
        var orderedEmails: [String] = []
        var labelsByEmail: [String: String] = [:]

        for profile in chromeProfiles {
            guard let email = profile.email?.trimmedNilIfEmpty else {
                continue
            }

            if labelsByEmail[email] == nil {
                orderedEmails.append(email)
            }

            let isLastUsed = profile.directoryName == lastUsedDirectoryName
            let name = profile.displayName?.trimmedNilIfEmpty ?? profile.directoryName
            labelsByEmail[email] = isLastUsed ? "\(email) - \(name) [last used]" : "\(email) - \(name)"
        }

        for email in configuredEmails.sorted() where labelsByEmail[email] == nil {
            orderedEmails.append(email)
            labelsByEmail[email] = "\(email) - missing in Chrome"
        }

        return orderedEmails.compactMap { email in
            guard let label = labelsByEmail[email] else {
                return nil
            }

            return ProfileOption(email: email, label: label)
        }
    }
}

struct EditableRule: Identifiable, Equatable {
    let id: UUID
    var pattern: String
    var profileEmail: String

    init(id: UUID = UUID(), pattern: String, profileEmail: String) {
        self.id = id
        self.pattern = pattern
        self.profileEmail = profileEmail
    }

    init(rule: URLRule) {
        self.init(pattern: rule.pattern, profileEmail: rule.profileEmail)
    }
}

struct PasteFriendlyTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> PasteEnabledTextField {
        let textField = PasteEnabledTextField()
        textField.placeholderString = placeholder
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ nsView: PasteEnabledTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            text = textField.stringValue
        }
    }
}

final class PasteEnabledTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch characters {
        case "v":
            currentEditor()?.paste(nil)
            return true
        case "c":
            currentEditor()?.copy(nil)
            return true
        case "x":
            currentEditor()?.cut(nil)
            return true
        case "a":
            currentEditor()?.selectAll(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
