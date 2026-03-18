import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Foundation
import Combine

enum SetupWizardEntryPoint {
    case firstLaunch
    case settings
    case accounts
}

enum SetupWizardPresentationStyle {
    case fullScreen
    case sheet
}

enum SetupWizardStep: Int, CaseIterable, Identifiable {
    case checking
    case installCLI
    case createProject
    case enableAPIAndConsent
    case importCredentials
    case connectAccount
    case firstSync
    case complete

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .checking: return "Checking setup"
        case .installCLI: return "Install msgvault"
        case .createProject: return "Create GCP project"
        case .enableAPIAndConsent: return "Enable API + consent"
        case .importCredentials: return "Import credentials"
        case .connectAccount: return "Connect Gmail account"
        case .firstSync: return "Run first sync"
        case .complete: return "Done"
        }
    }
}

@MainActor
final class SetupWizardStore: ObservableObject {
    struct Preconditions {
        var cliInstalled = false
        var cliPath: String?
        var configExists = false
        var clientSecretPath: String?
        var validClientSecret = false
        var accounts: [String] = []
        var messageCount = 0
        var hasCompletedSync = false
    }

    @Published var currentStep: SetupWizardStep = .checking
    @Published var completedSteps: Set<SetupWizardStep> = []
    @Published var isEvaluating = true
    @Published var isRunningCommand = false
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var detectionSummary: [String] = []
    @Published var detectedClientSecretPath = ""
    @Published var detectedMessageCount = 0

    @Published var installLog = ""
    @Published var syncLog = ""

    @Published var projectCreated = false
    @Published var gmailAPIEnabled = false
    @Published var consentConfigured = false
    @Published var credentialImported = false
    @Published var importedCredentialPath = ""
    @Published var importedCredentialClientID = ""

    @Published var accountEmail = ""
    @Published var displayName = ""
    @Published var connectedEmail = ""
    @Published var knownAccounts: [String] = []
    @Published var testSyncSucceeded = false
    @Published var fullSyncStarted = false

    let entryPoint: SetupWizardEntryPoint

    private var msgvaultBinaryPath: String?
    private var lastPreconditions = Preconditions()

    private var msgvaultDirectoryURL: URL {
        URL(fileURLWithPath: RuntimePaths.realUserHomePath(), isDirectory: true)
            .appendingPathComponent(".msgvault", isDirectory: true)
    }

    private var configURL: URL {
        msgvaultDirectoryURL.appendingPathComponent("config.toml", isDirectory: false)
    }

    private var clientSecretURL: URL {
        msgvaultDirectoryURL.appendingPathComponent("client_secret.json", isDirectory: false)
    }

    init(entryPoint: SetupWizardEntryPoint) {
        self.entryPoint = entryPoint
        Task { await refreshPreconditions() }
    }

    func refreshPreconditions() async {
        isEvaluating = true
        errorMessage = nil
        statusMessage = "Detecting current setup..."
        defer {
            isEvaluating = false
            if statusMessage == "Detecting current setup..." {
                statusMessage = ""
            }
        }

        var pre = Preconditions()
        pre.cliPath = Self.findMsgvaultBinaryPath()
        pre.cliInstalled = pre.cliPath != nil
        msgvaultBinaryPath = pre.cliPath

        pre.configExists = FileManager.default.fileExists(atPath: configURL.path)
        if pre.configExists,
           let configText = try? String(contentsOf: configURL, encoding: .utf8),
           let configuredPath = Self.parseClientSecretsPath(from: configText) {
            pre.clientSecretPath = configuredPath
            pre.validClientSecret = Self.validateCredentialFile(atPath: configuredPath)
        } else {
            pre.validClientSecret = false
        }

        if pre.cliInstalled {
            if let output = try? await runMsgvault(arguments: ["list-accounts", "--json"]) {
                pre.accounts = Self.parseAccounts(output)
            }
            if let statsOutput = try? await runMsgvault(arguments: ["stats", "--json"]) {
                pre.messageCount = Self.parseMessageCount(fromStatsOutput: statsOutput)
                pre.hasCompletedSync = pre.messageCount > 0
            } else if let statsFallback = try? await runMsgvault(arguments: ["stats"]) {
                pre.messageCount = Self.parseMessageCount(fromStatsOutput: statsFallback)
                pre.hasCompletedSync = pre.messageCount > 0
            }
        }

        lastPreconditions = pre
        knownAccounts = pre.accounts
        if accountEmail.isEmpty, let first = pre.accounts.first {
            accountEmail = first
        }
        if connectedEmail.isEmpty, let first = pre.accounts.first {
            connectedEmail = first
        }
        if pre.hasCompletedSync {
            testSyncSucceeded = true
        }
        detectedClientSecretPath = pre.clientSecretPath ?? ""
        detectedMessageCount = pre.messageCount
        detectionSummary = Self.makeDetectionSummary(
            pre: pre,
            configPath: configURL.path
        )
        applyCompletedSteps(from: pre)
        currentStep = determineInitialStep(from: pre)
        statusMessage = summaryStatus(from: pre)
    }

    private func summaryStatus(from pre: Preconditions) -> String {
        if !pre.cliInstalled {
            return "msgvault not found yet."
        }
        if !pre.validClientSecret {
            return "msgvault found, but OAuth credentials are not configured."
        }
        if pre.accounts.isEmpty {
            return "OAuth is configured. Connect your first account."
        }
        if !pre.hasCompletedSync {
            return "Account connected. Run your first sync."
        }
        return "Setup detected: ready to use."
    }

    private func determineInitialStep(from pre: Preconditions) -> SetupWizardStep {
        if !pre.cliInstalled {
            return .installCLI
        }

        if entryPoint == .accounts && pre.validClientSecret {
            return .connectAccount
        }

        if !pre.validClientSecret {
            return .createProject
        }
        if pre.accounts.isEmpty || entryPoint == .accounts {
            return .connectAccount
        }
        if !pre.hasCompletedSync {
            return .firstSync
        }
        return .complete
    }

    private func applyCompletedSteps(from pre: Preconditions) {
        var steps = Set<SetupWizardStep>()
        if pre.cliInstalled {
            steps.insert(.installCLI)
        }
        if pre.validClientSecret {
            steps.insert(.createProject)
            steps.insert(.enableAPIAndConsent)
            steps.insert(.importCredentials)
            credentialImported = true
        }
        if !pre.accounts.isEmpty {
            steps.insert(.connectAccount)
        }
        if pre.hasCompletedSync {
            steps.insert(.firstSync)
        }
        completedSteps = steps
    }

    func openURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func installMsgvaultAutomatically() async {
        guard !isRunningCommand else { return }
        errorMessage = nil
        statusMessage = "Installing msgvault..."
        installLog = ""
        isRunningCommand = true
        defer { isRunningCommand = false }

        do {
            let command = "curl -fsSL https://msgvault.io/install.sh | bash"
            _ = try await Self.executeCommand(
                commandPath: "/bin/zsh",
                arguments: ["-lc", command],
                timeoutSeconds: 300
            ) { [weak self] chunk in
                DispatchQueue.main.async {
                    self?.installLog += chunk
                }
            }
            statusMessage = "Install complete. Re-checking setup..."
            await refreshPreconditions()
            if currentStep == .installCLI {
                currentStep = .createProject
            }
        } catch {
            errorMessage = Self.cleanError(error.localizedDescription)
            statusMessage = "Install failed."
        }
    }

    func continueFromProjectStep() {
        errorMessage = nil
        guard projectCreated else {
            errorMessage = "Tick the checkbox after creating your GCP project."
            return
        }
        completedSteps.insert(.createProject)
        currentStep = .enableAPIAndConsent
    }

    func continueFromAPIAndConsentStep() {
        errorMessage = nil
        guard gmailAPIEnabled && consentConfigured else {
            errorMessage = "Complete both checkboxes before continuing."
            return
        }
        completedSteps.insert(.enableAPIAndConsent)
        currentStep = .importCredentials
    }

    func chooseCredentialFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [UTType.json]
        panel.message = "Select the OAuth Desktop app JSON file downloaded from Google Cloud."
        if panel.runModal() == .OK, let url = panel.url {
            Task { await importCredential(from: url) }
        }
    }

    func importCredential(from url: URL) async {
        errorMessage = nil
        statusMessage = "Validating credential file..."
        do {
            let data = try Data(contentsOf: url)
            let clientID = try Self.validateCredentialJSON(data)
            try FileManager.default.createDirectory(at: msgvaultDirectoryURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: clientSecretURL.path) {
                try FileManager.default.removeItem(at: clientSecretURL)
            }
            try data.write(to: clientSecretURL, options: .atomic)
            try writeConfigToml(clientSecretPath: clientSecretURL.path)

            importedCredentialClientID = Self.redactClientID(clientID)
            importedCredentialPath = clientSecretURL.path
            credentialImported = true
            completedSteps.insert(.importCredentials)
            statusMessage = "Credential imported and config.toml written."
        } catch {
            credentialImported = false
            importedCredentialClientID = ""
            importedCredentialPath = ""
            errorMessage = Self.cleanError(error.localizedDescription)
            statusMessage = "Credential import failed."
        }
    }

    func continueFromCredentialStep() {
        errorMessage = nil
        guard credentialImported else {
            errorMessage = "Import a valid Desktop OAuth JSON file first."
            return
        }
        currentStep = .connectAccount
    }

    func connectAccount() async {
        guard !isRunningCommand else { return }
        errorMessage = nil

        let email = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeEmail(email) else {
            errorMessage = "Enter a valid Gmail address."
            return
        }

        isRunningCommand = true
        statusMessage = "Starting OAuth flow for \(email)..."
        defer { isRunningCommand = false }

        var arguments = ["add-account", email]
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            arguments += ["--display-name", name]
        }

        do {
            _ = try await runMsgvault(arguments: arguments, timeoutSeconds: 180)
            statusMessage = "Waiting for account to appear..."

            let deadline = Date().addingTimeInterval(180)
            while Date() < deadline {
                if let output = try? await runMsgvault(arguments: ["list-accounts", "--json"]) {
                    let emails = Self.parseAccounts(output)
                    knownAccounts = emails
                    if emails.contains(where: { $0.caseInsensitiveCompare(email) == .orderedSame }) {
                        connectedEmail = email
                        completedSteps.insert(.connectAccount)
                        statusMessage = "Account connected: \(email)"
                        currentStep = .firstSync
                        return
                    }
                }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }

            errorMessage = "Timed out waiting for account confirmation. Retry, then complete sign-in in your browser."
            statusMessage = "Connection timed out."
        } catch {
            let raw = error.localizedDescription
            errorMessage = Self.friendlyAddAccountError(raw)
            statusMessage = "Could not connect account."
        }
    }

    func startTestSync() async {
        guard !isRunningCommand else { return }
        errorMessage = nil
        syncLog = ""

        let email = selectedEmailForSync()
        guard !email.isEmpty else {
            errorMessage = "No account available for sync. Connect an account first."
            return
        }

        isRunningCommand = true
        statusMessage = "Running test sync for \(email)..."
        defer { isRunningCommand = false }

        do {
            let output = try await runMsgvault(
                arguments: ["sync-full", email, "--limit", "100"],
                timeoutSeconds: 900
            ) { [weak self] chunk in
                DispatchQueue.main.async {
                    self?.syncLog += chunk
                }
            }
            if syncLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                syncLog = output
            }
            testSyncSucceeded = true
            completedSteps.insert(.firstSync)
            statusMessage = "Test sync complete."
        } catch {
            errorMessage = Self.cleanError(error.localizedDescription)
            statusMessage = "Test sync failed."
        }
    }

    func startFullSyncInBackground() async {
        guard !isRunningCommand else { return }
        errorMessage = nil
        let email = selectedEmailForSync()
        guard !email.isEmpty else {
            errorMessage = "No account available for full sync."
            return
        }

        isRunningCommand = true
        statusMessage = "Starting full sync in background..."
        defer { isRunningCommand = false }

        let escapedEmail = Self.shellQuote(email)
        let command: String
        if let path = msgvaultBinaryPath ?? Self.findMsgvaultBinaryPath() {
            let escapedPath = Self.shellQuote(path)
            command = "\(escapedPath) --local sync-full \(escapedEmail) >/tmp/msgvault-sync-full.log 2>&1 &"
        } else {
            // PATH fallback when absolute binary detection fails.
            command = "/usr/bin/env msgvault --local sync-full \(escapedEmail) >/tmp/msgvault-sync-full.log 2>&1 &"
        }

        do {
            _ = try await Self.executeCommand(
                commandPath: "/bin/zsh",
                arguments: ["-lc", command],
                timeoutSeconds: 10
            )
            fullSyncStarted = true
            completedSteps.insert(.firstSync)
            statusMessage = "Full sync started in background."
            currentStep = .complete
        } catch {
            errorMessage = Self.cleanError(error.localizedDescription)
            statusMessage = "Could not start full sync."
        }
    }

    func skipForNow() {
        completedSteps.insert(.firstSync)
        currentStep = .complete
        statusMessage = "You can run full sync later from the app."
    }

    private func selectedEmailForSync() -> String {
        let explicit = connectedEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty {
            return explicit
        }
        return knownAccounts.first ?? accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeConfigToml(clientSecretPath: String) throws {
        let escaped = clientSecretPath.replacingOccurrences(of: "\"", with: "\\\"")
        let toml = """
        [oauth]
        client_secrets = "\(escaped)"

        [sync]
        rate_limit_qps = 5
        """
        try toml.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func runMsgvault(
        arguments: [String],
        timeoutSeconds: TimeInterval? = nil,
        onOutput: ((String) -> Void)? = nil
    ) async throws -> String {
        var lastError: Error?
        for executable in msgvaultExecutableCandidates() {
            do {
                let output = try await Self.executeCommand(
                    commandPath: executable,
                    arguments: msgvaultInvocationArguments(for: executable, commandArguments: arguments),
                    timeoutSeconds: timeoutSeconds,
                    onOutput: onOutput
                )
                if executable != "/usr/bin/env" {
                    msgvaultBinaryPath = executable
                } else if let resolved = Self.findMsgvaultBinaryPath() {
                    msgvaultBinaryPath = resolved
                }
                return output
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NSError(
            domain: "SetupWizard",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "msgvault binary not found."]
        )
    }

    private func msgvaultExecutableCandidates() -> [String] {
        var candidates: [String] = []
        let trimmed = msgvaultBinaryPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            candidates.append(trimmed)
        }
        if let discovered = Self.findMsgvaultBinaryPath(),
           !discovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(discovered)
        }
        candidates.append("/usr/bin/env")

        var unique: [String] = []
        var seen = Set<String>()
        for candidate in candidates {
            if seen.insert(candidate).inserted {
                unique.append(candidate)
            }
        }
        return unique
    }

    private func msgvaultInvocationArguments(for executable: String, commandArguments: [String]) -> [String] {
        if executable == "/usr/bin/env" {
            return ["msgvault", "--local"] + commandArguments
        }
        return ["--local"] + commandArguments
    }

    nonisolated private static func findMsgvaultBinaryPath() -> String? {
        RuntimePaths.resolveBinaryPath("msgvault")
    }

    nonisolated private static func runSimpleCommand(_ command: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = RuntimePaths.processEnvironmentForUserHome()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    nonisolated private static func executeCommand(
        commandPath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        onOutput: ((String) -> Void)? = nil
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                let lock = NSLock()
                var collected = Data()
                var didResume = false

                func finish(_ result: Result<String, Error>) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !didResume else { return }
                    didResume = true
                    switch result {
                    case .success(let output):
                        continuation.resume(returning: output)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                process.executableURL = URL(fileURLWithPath: commandPath)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe
                process.environment = RuntimePaths.processEnvironmentForUserHome()

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    lock.lock()
                    collected.append(data)
                    lock.unlock()
                    if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {
                        onOutput?(chunk)
                    }
                }

                do {
                    try process.run()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    finish(.failure(error))
                    return
                }

                let timeoutDate = timeoutSeconds.map { Date().addingTimeInterval($0) }
                var didTimeout = false

                while process.isRunning {
                    if let timeoutDate, Date() >= timeoutDate {
                        didTimeout = true
                        process.terminate()
                        Thread.sleep(forTimeInterval: 0.2)
                        if process.isRunning {
                            process.interrupt()
                        }
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.2)
                }

                process.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                let trailing = pipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                collected.append(trailing)
                let outputData = collected
                lock.unlock()

                let output = String(data: outputData, encoding: .utf8) ?? ""

                if didTimeout {
                    finish(.failure(NSError(
                        domain: "SetupWizard",
                        code: 408,
                        userInfo: [NSLocalizedDescriptionKey: "Command timed out."]
                    )))
                    return
                }

                if process.terminationStatus != 0 {
                    finish(.failure(NSError(
                        domain: "SetupWizard",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: cleanError(output.isEmpty ? "Unknown command error." : output)]
                    )))
                    return
                }

                finish(.success(output))
            }
        }
    }

    nonisolated private static func parseClientSecretsPath(from toml: String) -> String? {
        let pattern = #"(?m)^\s*client_secrets\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: toml, range: NSRange(toml.startIndex..., in: toml)),
              let range = Range(match.range(at: 1), in: toml) else {
            return nil
        }
        return String(toml[range])
    }

    nonisolated private static func validateCredentialFile(atPath path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return false
        }
        return (try? validateCredentialJSON(data)) != nil
    }

    nonisolated private static func validateCredentialJSON(_ data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "SetupWizard",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This file is not valid JSON."]
            )
        }
        if let installed = root["installed"] as? [String: Any] {
            guard let clientID = installed["client_id"] as? String, !clientID.isEmpty else {
                throw NSError(
                    domain: "SetupWizard",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Missing installed.client_id in credential JSON."]
                )
            }
            guard let secret = installed["client_secret"] as? String, !secret.isEmpty else {
                throw NSError(
                    domain: "SetupWizard",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Missing installed.client_secret in credential JSON."]
                )
            }
            guard let redirectURIs = installed["redirect_uris"] as? [String], !redirectURIs.isEmpty else {
                throw NSError(
                    domain: "SetupWizard",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Missing installed.redirect_uris in credential JSON."]
                )
            }
            _ = secret
            return clientID
        }
        if root["web"] != nil {
            throw NSError(
                domain: "SetupWizard",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "This looks like a Web app OAuth credential. Create a Desktop app OAuth client and download that JSON instead."]
            )
        }
        throw NSError(
            domain: "SetupWizard",
            code: 6,
            userInfo: [NSLocalizedDescriptionKey: "Credential JSON must contain an 'installed' section for a Desktop app OAuth client."]
        )
    }

    nonisolated private static func parseAccounts(_ output: String) -> [String] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let payload: String
        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]"), start <= end {
            payload = String(trimmed[start...end])
        } else {
            payload = trimmed
        }

        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json.compactMap { ($0["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func parseMessageCount(fromStatsOutput output: String) -> Int {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let keys = ["message_count", "messages", "total_messages", "messageCount", "totalMessages"]
            for key in keys {
                if let value = object[key] as? Int {
                    return value
                }
            }
        }

        let lines = trimmed.components(separatedBy: .newlines)
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("message") else { continue }
            if let match = line.range(of: #"[0-9,]+"#, options: .regularExpression) {
                let raw = line[match].replacingOccurrences(of: ",", with: "")
                if let value = Int(raw) {
                    return value
                }
            }
        }
        return 0
    }

    nonisolated private static func cleanError(_ raw: String) -> String {
        let lines = raw
            .replacingOccurrences(of: "Searching...", with: "")
            .replacingOccurrences(of: "Loading...", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("Usage:") }
            .filter { !$0.hasPrefix("Flags:") }
            .filter { !$0.hasPrefix("Global Flags:") }
            .filter { !$0.hasPrefix("msgvault ") }
            .filter { !$0.hasPrefix("-h,") && !$0.hasPrefix("--json") && !$0.hasPrefix("-n,") && !$0.hasPrefix("--offset") }
            .filter { !$0.hasPrefix("--config") && !$0.hasPrefix("--home") && !$0.hasPrefix("--local") && !$0.hasPrefix("-v,") }
        return lines.first?.replacingOccurrences(of: "Error: ", with: "") ?? "Unknown error."
    }

    nonisolated private static func friendlyAddAccountError(_ raw: String) -> String {
        let normalized = raw.lowercased()
        if normalized.contains("address already in use") ||
            (normalized.contains("listen tcp") && normalized.contains("8089")) {
            return "Local OAuth callback port 8089 is already in use. Close any other auth attempts, then retry."
        }
        if normalized.contains("access_denied") ||
            normalized.contains("developer-approved testers") ||
            normalized.contains("google verification process") {
            return "Google denied sign-in. Add this Gmail as a Test User in the OAuth consent screen, then retry."
        }
        if normalized.contains("timed out") {
            return "OAuth flow timed out. Retry and complete sign-in in the browser within 3 minutes."
        }
        return cleanError(raw)
    }

    nonisolated private static func looksLikeEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
        let domainStart = trimmed.index(after: at)
        guard domainStart < trimmed.endIndex else { return false }
        let domain = trimmed[domainStart...]
        return domain.contains(".")
    }

    nonisolated private static func redactClientID(_ clientID: String) -> String {
        if clientID.count <= 14 {
            return clientID
        }
        let prefix = clientID.prefix(8)
        let suffix = clientID.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    nonisolated private static func makeDetectionSummary(pre: Preconditions, configPath: String) -> [String] {
        var lines: [String] = []
        if pre.cliInstalled {
            if let cliPath = pre.cliPath, !cliPath.isEmpty {
                lines.append("CLI detected: \(cliPath)")
            } else {
                lines.append("CLI detected")
            }
        } else {
            lines.append("CLI missing")
        }

        if pre.configExists {
            lines.append("Config found: \(configPath)")
        } else {
            lines.append("Config missing: \(configPath)")
        }

        if pre.validClientSecret {
            if let secrets = pre.clientSecretPath, !secrets.isEmpty {
                lines.append("OAuth credential valid: \(secrets)")
            } else {
                lines.append("OAuth credential valid")
            }
        } else {
            lines.append("OAuth credential missing/invalid")
        }

        if pre.accounts.isEmpty {
            lines.append("Accounts: none")
        } else {
            lines.append("Accounts: \(pre.accounts.joined(separator: ", "))")
        }

        lines.append("Synced messages: \(pre.messageCount)")
        return lines
    }
}

struct SetupWizardView: View {
    @Environment(\.appAccentColor) private var accentColor
    @StateObject private var wizard: SetupWizardStore

    let presentationStyle: SetupWizardPresentationStyle
    let onClose: () -> Void

    @State private var isDropTargeted = false

    init(
        entryPoint: SetupWizardEntryPoint,
        presentationStyle: SetupWizardPresentationStyle,
        onClose: @escaping () -> Void
    ) {
        _wizard = StateObject(wrappedValue: SetupWizardStore(entryPoint: entryPoint))
        self.presentationStyle = presentationStyle
        self.onClose = onClose
    }

    private var visibleSteps: [SetupWizardStep] {
        [.installCLI, .createProject, .enableAPIAndConsent, .importCredentials, .connectAccount, .firstSync, .complete]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if wizard.isEvaluating {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Checking your setup...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                HStack(spacing: 0) {
                    stepSidebar
                        .frame(width: 220)
                        .background(Color(NSColor.controlBackgroundColor))
                    Divider()
                    ScrollView {
                        stepContent
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(20)
                    }
                }
            }
        }
        .frame(minWidth: presentationStyle == .fullScreen ? 940 : 860, minHeight: 640)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title3)
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Guided Setup Wizard")
                    .font(.title3.bold())
                Text("Get from zero to first sync with step-by-step help.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Re-check") {
                Task { await wizard.refreshPreconditions() }
            }
            .buttonStyle(.bordered)
            if presentationStyle == .sheet {
                Button("Close") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .background(.bar)
    }

    private var stepSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleSteps) { step in
                HStack(spacing: 10) {
                    Image(systemName: wizard.completedSteps.contains(step) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(wizard.completedSteps.contains(step) ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.subheadline.weight(wizard.currentStep == step ? .semibold : .regular))
                            .foregroundStyle(wizard.currentStep == step ? accentColor : .primary)
                        if wizard.currentStep == step {
                            Text("Current")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(wizard.currentStep == step ? accentColor.opacity(0.11) : Color.clear)
                )
            }
            Spacer()
            if !wizard.detectionSummary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detected setup")
                        .font(.caption.weight(.semibold))
                    ForEach(wizard.detectionSummary, id: \.self) { line in
                        Text("• \(line)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if !wizard.statusMessage.isEmpty {
                Text(wizard.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch wizard.currentStep {
            case .checking:
                ProgressView("Checking setup...")
            case .installCLI:
                installStep
            case .createProject:
                projectStep
            case .enableAPIAndConsent:
                apiConsentStep
            case .importCredentials:
                importStep
            case .connectAccount:
                connectStep
            case .firstSync:
                firstSyncStep
            case .complete:
                completionStep
            }

            if let error = wizard.errorMessage, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.top, 6)
            }
        }
    }

    private var installStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Step 1 - Install msgvault CLI")
                .font(.title3.bold())
            Text("MailTrawl needs the local msgvault CLI to authenticate, sync, and search your archive.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("What this does")
                    .font(.headline)
                Text("• Installs the `msgvault` binary on this Mac")
                    .font(.subheadline)
                Text("• Keeps your archive local (no app-hosted mailbox backend)")
                    .font(.subheadline)
                Text("• Enables account connect and sync commands used by this app")
                    .font(.subheadline)
            }

            commandSnippet(
                "curl -fsSL https://msgvault.io/install.sh | bash",
                textColor: .green
            )

            HStack(spacing: 10) {
                Button {
                    Task { await wizard.installMsgvaultAutomatically() }
                } label: {
                    HStack(spacing: 8) {
                        if wizard.isRunningCommand {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text(wizard.isRunningCommand ? "Installing..." : "Install Automatically")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .disabled(wizard.isRunningCommand)

            }

            VStack(alignment: .leading, spacing: 6) {
                Text("If install fails")
                    .font(.headline)
                Text("• Confirm internet access")
                    .font(.subheadline)
                Text("• Run the copied command manually in Terminal and compare output")
                    .font(.subheadline)
                Text("• Re-open this wizard and click Re-check")
                    .font(.subheadline)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !wizard.installLog.isEmpty {
                ScrollView {
                    Text(wizard.installLog)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 180)
                .background(Color.black.opacity(0.85))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var projectStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Step 2 - Create Google Cloud Project")
                .font(.title3.bold())
            Text("You own these credentials. The app does not upload tokens or credentials to any server.")
                .foregroundStyle(.secondary)

            Button("Open Google Cloud Project Create") {
                wizard.openURL("https://console.cloud.google.com/projectcreate")
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)

            VStack(alignment: .leading, spacing: 8) {
                Text("Checklist")
                    .font(.headline)
                Label("Create a new project (name suggestion: msgvault)", systemImage: "checkmark")
                Label("Note your Project ID", systemImage: "checkmark")
            }
            .font(.subheadline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Exact path in Google Cloud")
                    .font(.headline)
                Text("1. Open console.cloud.google.com")
                    .font(.subheadline)
                Text("2. Click project dropdown (top bar)")
                    .font(.subheadline)
                Text("3. Click New Project")
                    .font(.subheadline)
                Text("4. Name it `msgvault` (or any name) and click Create")
                    .font(.subheadline)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Toggle("I created my Google Cloud project", isOn: $wizard.projectCreated)
                .toggleStyle(.checkbox)
                .tint(accentColor)

            Button("Continue") {
                wizard.continueFromProjectStep()
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .disabled(!wizard.projectCreated)
        }
    }

    private var apiConsentStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Step 3 - Enable Gmail API and OAuth Consent")
                .font(.title3.bold())
            Text("Keep OAuth app status in Testing mode. Publishing is not required for personal use.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Enable Gmail API") {
                    wizard.openURL("https://console.cloud.google.com/apis/library/gmail.googleapis.com")
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                Button("Open Consent Screen") {
                    wizard.openURL("https://console.cloud.google.com/apis/credentials/consent")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("I enabled the Gmail API", isOn: $wizard.gmailAPIEnabled)
                    .toggleStyle(.checkbox)
                    .tint(accentColor)
                Toggle("I configured the consent screen and added my email as Test User", isOn: $wizard.consentConfigured)
                    .toggleStyle(.checkbox)
                    .tint(accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Consent screen details")
                    .font(.headline)
                Text("1. User type: External")
                    .font(.subheadline)
                Text("2. App name: msgvault")
                    .font(.subheadline)
                Text("3. Support email + developer contact: your email")
                    .font(.subheadline)
                Text("4. Save through Scopes (no extra changes required)")
                    .font(.subheadline)
                Text("5. Add your Gmail(s) under Test users")
                    .font(.subheadline)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Label("Do not publish the OAuth app. Testing mode is the intended personal-use setup.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Continue") {
                wizard.continueFromAPIAndConsentStep()
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .disabled(!(wizard.gmailAPIEnabled && wizard.consentConfigured))
        }
    }

    private var importStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Step 4 - Create OAuth Client and Import JSON")
                .font(.title3.bold())
            Text("Create an OAuth client as Desktop app, download JSON, then import it here.")
                .foregroundStyle(.secondary)

            Button("Open Credentials Page") {
                wizard.openURL("https://console.cloud.google.com/apis/credentials")
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)

            VStack(alignment: .leading, spacing: 6) {
                Text("Create OAuth client in Google Cloud")
                    .font(.headline)
                Text("1. Create Credentials -> OAuth client ID")
                    .font(.subheadline)
                Text("2. Application type: Desktop app")
                    .font(.subheadline)
                Text("3. Click Create, then Download JSON")
                    .font(.subheadline)
                Text("4. Save file and import it below")
                    .font(.subheadline)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            dropZone

            HStack(spacing: 10) {
                Button("Browse for JSON File") {
                    wizard.chooseCredentialFile()
                }
                .buttonStyle(.bordered)
                Button("Continue") {
                    wizard.continueFromCredentialStep()
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .disabled(!wizard.credentialImported)
            }

            if wizard.credentialImported {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Credential imported successfully", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if !wizard.importedCredentialClientID.isEmpty {
                        Text("Client ID: \(wizard.importedCredentialClientID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if !wizard.importedCredentialPath.isEmpty {
                        Text(wizard.importedCredentialPath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Validation requirements")
                        .font(.headline)
                    Text("• File must be JSON with `installed.client_id`, `installed.client_secret`, `installed.redirect_uris`")
                        .font(.subheadline)
                    Text("• Web-app credentials are not valid here; use Desktop app credentials")
                        .font(.subheadline)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text("""
[oauth]
client_secrets = "\(RuntimePaths.realUserHomePath())/.msgvault/client_secret.json"

[sync]
rate_limit_qps = 5
""")
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.84))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isDropTargeted ? accentColor : Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDropTargeted ? accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            )
            .frame(height: 128)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.title2)
                        .foregroundStyle(accentColor)
                    Text("Drop your client_secret.json here")
                        .font(.headline)
                    Text("or use Browse to select it manually")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            )
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                handleCredentialDrop(providers)
            }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Step 5 - Connect Your Gmail Account")
                .font(.title3.bold())
            Text("Click connect, complete Google sign-in in your browser, then return here.")
                .foregroundStyle(.secondary)

            TextField("Gmail address", text: $wizard.accountEmail)
                .textFieldStyle(.roundedBorder)
            TextField("Display name (optional)", text: $wizard.displayName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Expected flow")
                    .font(.headline)
                Text("1. Click Connect Account")
                    .font(.subheadline)
                Text("2. Browser opens Google OAuth")
                    .font(.subheadline)
                Text("3. Sign in and grant access")
                    .font(.subheadline)
                Text("4. Return to app; account appears automatically")
                    .font(.subheadline)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                Task { await wizard.connectAccount() }
            } label: {
                HStack(spacing: 8) {
                    if wizard.isRunningCommand {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "person.badge.plus.fill")
                    }
                    Text(wizard.isRunningCommand ? "Connecting..." : "Connect Account")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .disabled(wizard.isRunningCommand || wizard.accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !wizard.connectedEmail.isEmpty {
                Label("Connected: \(wizard.connectedEmail)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("If browser OAuth fails")
                    .font(.headline)
                Text("• Browser didn't open: run headless fallback manually")
                    .font(.subheadline)
                Text("• `access_denied`: ensure this Gmail is listed under Test users")
                    .font(.subheadline)
                Text("• Timeout: retry and complete sign-in within 3 minutes")
                    .font(.subheadline)
                HStack(spacing: 10) {
                    Text("msgvault add-account \(wizard.accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "<email>" : wizard.accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)) --headless")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Copy headless command") {
                        let email = wizard.accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                        let target = email.isEmpty ? "<email>" : email
                        copyToClipboard("msgvault add-account \(target) --headless")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button("Open OAuth Consent Screen") {
                    wizard.openURL("https://console.cloud.google.com/apis/credentials/consent")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var firstSyncStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Step 6 - First Sync Test")
                .font(.title3.bold())
            Text("Run a small sync first (100 messages), then optionally kick off full archive sync in background.")
                .foregroundStyle(.secondary)

            if !wizard.connectedEmail.isEmpty {
                Label("Account: \(wizard.connectedEmail)", systemImage: "person.crop.circle")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await wizard.startTestSync() }
                } label: {
                    HStack(spacing: 8) {
                        if wizard.isRunningCommand {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.circle.fill")
                        }
                        Text(wizard.isRunningCommand ? "Syncing..." : "Start Test Sync (100 messages)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .disabled(wizard.isRunningCommand)

                Button("Skip for now") {
                    wizard.skipForNow()
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What to expect")
                    .font(.headline)
                Text("• Typical speed is around 50 messages/second on fast internet")
                    .font(.subheadline)
                Text("• Large inboxes can take hours for full sync")
                    .font(.subheadline)
                Text("• Full sync is resumable if interrupted")
                    .font(.subheadline)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !wizard.syncLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    Text(wizard.syncLog)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 180)
                .background(Color.black.opacity(0.85))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if wizard.testSyncSucceeded {
                Button {
                    Task { await wizard.startFullSyncInBackground() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        Text("Sync Full Archive in Background")
                    }
                }
                .buttonStyle(.bordered)

                HStack(spacing: 10) {
                    Text("msgvault sync-full \(wizard.connectedEmail.isEmpty ? "<email>" : wizard.connectedEmail)")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Copy full sync command") {
                        let target = wizard.connectedEmail.isEmpty ? "<email>" : wizard.connectedEmail
                        copyToClipboard("msgvault sync-full \(target)")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var completionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Setup complete", systemImage: "checkmark.seal.fill")
                .font(.title3.bold())
                .foregroundStyle(.green)

            Text("Your setup is ready. You can now use Search, Accounts, and Stats normally.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Next steps")
                    .font(.headline)
                Text("• Accounts: connect additional Gmail accounts")
                    .font(.subheadline)
                Text("• Search: query across your synced archive")
                    .font(.subheadline)
                Text("• Stats: monitor message count and sync progress")
                    .font(.subheadline)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if wizard.fullSyncStarted {
                Label("Full sync started in background. Logs: /tmp/msgvault-sync-full.log", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("Open App") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func commandSnippet(_ command: String, textColor: Color = .white) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                copyToClipboard(command)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
            .help("Copy command")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func handleCredentialDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data,
                  let raw = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: raw) else {
                return
            }
            Task { await wizard.importCredential(from: url) }
        }
        return true
    }
}
