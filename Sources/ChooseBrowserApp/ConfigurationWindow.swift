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
        window.title = "ChooseBrowser"
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
    @Published var defaultProfileEmail: String?
    @Published var defaultBrowserStatus = DefaultBrowserStatus(isDefaultForHTTP: false, isDefaultForHTTPS: false)
    @Published var lastUsedProfileEmail: String?
    @Published var rules: [EditableRule] = []
    @Published var draftPattern = ""
    @Published var draftProfileEmail = ""
    @Published var configPath = ""
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let router: BrowserRouter
    private let defaultBrowserService: DefaultBrowserService
    private let onRequestQuit: () -> Void
    private let onRequestUninstall: () -> Void
    private var isHydrating = false

    init(
        router: BrowserRouter,
        defaultBrowserService: DefaultBrowserService = DefaultBrowserService(),
        onRequestQuit: @escaping () -> Void,
        onRequestUninstall: @escaping () -> Void
    ) {
        self.router = router
        self.defaultBrowserService = defaultBrowserService
        self.onRequestQuit = onRequestQuit
        self.onRequestUninstall = onRequestUninstall
        self.configPath = router.configurationFileURL().path(percentEncoded: false)
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
            defaultBrowserStatus = defaultBrowserService.currentStatus(bundleIdentifier: Bundle.main.bundleIdentifier)
            defaultProfileEmail = config.defaultProfileEmail
            lastUsedProfileEmail = catalog.email(forDirectoryName: catalog.lastUsedDirectoryName)
            rules = config.rules.map(EditableRule.init)
            draftPattern = ""
            draftProfileEmail = config.defaultProfileEmail ?? profileOptions.first?.email ?? ""

            if knownEmails.isEmpty {
                statusMessage = "ChooseBrowser could not find signed-in Chrome profile emails yet."
            } else {
                statusMessage = "Loaded \(rules.count) rule" + (rules.count == 1 ? "." : "s.")
            }

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

    func saveDefaultProfileIfNeeded() {
        guard !isHydrating else {
            return
        }

        do {
            try persistCommittedState(status: "Default profile updated.")
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    func revealConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([router.configurationFileURL()])
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
        VStack(alignment: .leading, spacing: 18) {
            header
            defaultBrowserSection
            defaultProfileSection
            rulesSection
            footer
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 560)
        .onChange(of: viewModel.defaultProfileEmail) { _ in
            viewModel.saveDefaultProfileIfNeeded()
        }
    }

    private var defaultBrowserSection: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: viewModel.defaultBrowserStatus.isDefaultForWebLinks ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(viewModel.defaultBrowserStatus.isDefaultForWebLinks ? .green : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    if viewModel.defaultBrowserStatus.isDefaultForWebLinks {
                        Text("ChooseBrowser is currently your default browser for web links.")
                            .font(.headline)
                        Text("macOS should route normal http and https links through this app.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("ChooseBrowser is not your default browser yet.")
                            .font(.headline)
                        Text("To make profile routing work from other apps, set ChooseBrowser as the Default web browser in System Settings > Desktop & Dock.")
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !viewModel.defaultBrowserStatus.isDefaultForWebLinks {
                    Button("Open Settings") {
                        viewModel.openDefaultBrowserSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Default Browser")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ChooseBrowser")
                .font(.system(size: 28, weight: .semibold))
            Text("Paste a URL prefix, pick the Chrome profile, and click +. Plain URLs match deeper paths automatically. Use * and ? only when you want advanced matching.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(viewModel.configPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                Button("Reveal in Finder") {
                    viewModel.revealConfigInFinder()
                }
            }
        }
    }

    private var defaultProfileSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Fallback profile", selection: $viewModel.defaultProfileEmail) {
                    Text("Use Chrome's last used profile")
                        .tag(Optional<String>.none)

                    ForEach(viewModel.profileOptions) { option in
                        Text(option.label)
                            .tag(option.email as String?)
                    }
                }

                Text(fallbackDescription)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Default Behavior")
        }
    }

    private var rulesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text("Rules are matched top to bottom. The first match wins.")
                    .foregroundStyle(.secondary)

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
                        VStack(spacing: 10) {
                            ForEach(viewModel.rules) { rule in
                                CompactRuleRow(
                                    rule: rule,
                                    profileLabel: label(for: rule.profileEmail)
                                ) {
                                    viewModel.removeRule(id: rule.id)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        } label: {
            Text("URL Rules")
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Reload") {
                viewModel.load()
            }
            Button("Quit") {
                viewModel.quitApplication()
            }
            Button("Uninstall") {
                viewModel.requestUninstall()
            }
        }
    }

    private var fallbackDescription: String {
        if let email = viewModel.defaultProfileEmail {
            return "Links that do not match a rule will open in \(email)."
        }

        if let email = viewModel.lastUsedProfileEmail {
            return "Links that do not match a rule will follow Chrome's last used profile, currently \(email)."
        }

        return "Links that do not match a rule will fall back to Chrome's last used profile."
    }

    private func label(for email: String) -> String {
        viewModel.profileOptions.first(where: { $0.email == email })?.label ?? email
    }
}

struct DraftRuleComposer: View {
    @Binding var pattern: String
    @Binding var profileEmail: String
    let profileOptions: [ProfileOption]
    let canAdd: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("URL prefix or pattern")
                    .font(.headline)
                PasteFriendlyTextField(text: $pattern, placeholder: "https://gitlab.com/eslfaceitgroup")
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Chrome profile")
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
                    .frame(width: 300, alignment: .leading)
                }
            }

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canAdd)
            .help("Add this rule")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct CompactRuleRow: View {
    let rule: EditableRule
    let profileLabel: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.pattern)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(profileLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .help("Delete this rule")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct EmptyRulesView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No rules yet")
                .font(.headline)
            Text("Paste a URL prefix above, choose the profile, and click + to add your first rule.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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
