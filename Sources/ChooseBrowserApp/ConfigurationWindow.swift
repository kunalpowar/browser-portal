import AppKit
import ChooseBrowserCore
import SwiftUI

@MainActor
final class ConfigurationWindowController: NSWindowController {
    private let viewModel: ConfigurationViewModel

    init(router: BrowserRouter = BrowserRouter()) {
        self.viewModel = ConfigurationViewModel(router: router)

        let hostingController = NSHostingController(rootView: ConfigurationView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ChooseBrowser"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 860, height: 620))
        window.minSize = NSSize(width: 760, height: 520)
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
    @Published var lastUsedProfileEmail: String?
    @Published var rules: [EditableRule] = []
    @Published var configPath = ""
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let router: BrowserRouter

    init(router: BrowserRouter) {
        self.router = router
        self.configPath = router.configurationFileURL().path(percentEncoded: false)
    }

    func load() {
        do {
            let catalog = try router.availableProfiles()
            let config = try router.loadConfig()
            let knownEmails = catalog.availableEmails

            profileOptions = ProfileOption.merged(
                chromeProfiles: catalog.profiles,
                configuredEmails: Set(config.rules.map(\.profileEmail)).union([config.defaultProfileEmail].compactMap { $0 }),
                lastUsedDirectoryName: catalog.lastUsedDirectoryName
            )
            defaultProfileEmail = config.defaultProfileEmail
            lastUsedProfileEmail = catalog.email(forDirectoryName: catalog.lastUsedDirectoryName)
            rules = config.rules.map(EditableRule.init)

            if knownEmails.isEmpty {
                statusMessage = "ChooseBrowser could not find signed-in Chrome profile emails yet."
            } else {
                statusMessage = "Loaded \(rules.count) rule" + (rules.count == 1 ? "." : "s.")
            }

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    func addRule() {
        let fallbackEmail = defaultProfileEmail ?? profileOptions.first?.email ?? ""
        rules.append(EditableRule(pattern: "", profileEmail: fallbackEmail))
        statusMessage = nil
        errorMessage = nil
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        statusMessage = nil
        errorMessage = nil
    }

    func save() {
        do {
            let config = try buildConfig()
            try router.saveConfig(config)
            defaultProfileEmail = config.defaultProfileEmail
            rules = config.rules.map(EditableRule.init)
            statusMessage = "Saved changes."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    func revealConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([router.configurationFileURL()])
    }

    private func buildConfig() throws -> ChooseBrowserConfig {
        let cleanedRules = try rules.enumerated().map { index, rule in
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

        let selectedDefaultProfile = defaultProfileEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmedNilIfEmpty

        return ChooseBrowserConfig(defaultProfileEmail: selectedDefaultProfile, rules: cleanedRules)
    }
}

struct ConfigurationView: View {
    @ObservedObject var viewModel: ConfigurationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            defaultProfileSection
            rulesSection
            footer
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ChooseBrowser")
                .font(.system(size: 28, weight: .semibold))
            Text("Launch the app directly to edit rules. When macOS launches it for a link, it stays quiet and routes the URL to the right Chrome profile.")
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
                HStack {
                    Text("Rules are matched top to bottom. The first match wins.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Rule") {
                        viewModel.addRule()
                    }
                }

                if viewModel.rules.isEmpty {
                    EmptyRulesView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(Array(viewModel.rules.indices), id: \.self) { index in
                                RuleEditorRow(
                                    index: index + 1,
                                    rule: $viewModel.rules[index],
                                    profileOptions: viewModel.profileOptions
                                ) {
                                    viewModel.removeRule(id: viewModel.rules[index].id)
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
            Button("Save") {
                viewModel.save()
            }
            .keyboardShortcut("s")
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
}

struct RuleEditorRow: View {
    let index: Int
    @Binding var rule: EditableRule
    let profileOptions: [ProfileOption]
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rule \(index)")
                    .font(.headline)
                TextField("https://*.example.com/*", text: $rule.pattern)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Chrome profile")
                    .font(.headline)

                if profileOptions.isEmpty {
                    TextField("person@example.com", text: $rule.profileEmail)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Chrome profile", selection: $rule.profileEmail) {
                        ForEach(profileOptions) { option in
                            Text(option.label)
                                .tag(option.email)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280, alignment: .leading)
                }
            }

            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .help("Remove this rule")
            .padding(.top, 28)
        }
        .padding(14)
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
            Text("Add a rule to route matching URLs into a specific Chrome profile.")
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

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
