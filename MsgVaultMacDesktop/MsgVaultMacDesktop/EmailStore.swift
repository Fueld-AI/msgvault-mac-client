import Foundation
import SwiftUI
import Combine

// MARK: - Models

struct EmailMessage: Identifiable, Hashable {
    let id: String
    let gmailMessageID: String?
    let from: String
    let to: String
    let cc: String
    let bcc: String
    let subject: String
    let date: String
    let snippet: String
    let labels: [String]
    let hasAttachment: Bool
    let threadID: String?
    let sizeEstimate: Int

    // Parse from msgvault search --json output
    static func parse(from json: [String: Any]) -> EmailMessage? {
        let id: String?
        if let idString = json["id"] as? String {
            id = idString
        } else if let idInt = json["id"] as? Int {
            id = String(idInt)
        } else if let messageId = json["message_id"] as? String {
            id = messageId
        } else if let sourceId = json["source_message_id"] as? String {
            id = sourceId
        } else {
            id = nil
        }
        
        guard let id else { return nil }
        let sourceMessageID = normalizedString(json["source_message_id"])
        let gmailMessageID = sourceMessageID
            ?? normalizedString(json["gmail_id"])
            ?? normalizedString(json["gmailId"])
            ?? {
                if let messageId = normalizedString(json["message_id"]),
                   looksLikeGmailMessageID(messageId) {
                    return messageId
                }
                if looksLikeGmailMessageID(id) {
                    return id
                }
                return nil
            }()
        
        let fromEmail = json["from_email"] as? String ?? json["from"] as? String ?? json["sender"] as? String ?? "Unknown"
        let fromName = json["from_name"] as? String ?? ""
        let displayFrom = fromName.isEmpty ? fromEmail : "\(fromName) <\(fromEmail)>"
        
        let toValue: String
        if let toArray = json["to_emails"] as? [String] {
            toValue = toArray.joined(separator: ", ")
        } else {
            toValue = json["to"] as? String ?? json["recipients"] as? String ?? ""
        }

        let ccValue: String
        if let ccArray = json["cc_emails"] as? [String] {
            ccValue = ccArray.joined(separator: ", ")
        } else {
            ccValue = json["cc"] as? String ?? ""
        }

        let bccValue: String
        if let bccArray = json["bcc_emails"] as? [String] {
            bccValue = bccArray.joined(separator: ", ")
        } else {
            bccValue = json["bcc"] as? String ?? ""
        }

        let hasAttachment =
            (json["has_attachment"] as? Bool ?? false) ||
            (json["has_attachments"] as? Bool ?? false) ||
            ((json["attachment_count"] as? Int ?? 0) > 0)
        let threadID = json["thread_id"] as? String
            ?? json["threadId"] as? String
            ?? json["conversation_id"] as? String
        
        let sizeEstimate = json["size_estimate"] as? Int ?? 0

        return EmailMessage(
            id: id,
            gmailMessageID: gmailMessageID,
            from: displayFrom,
            to: toValue,
            cc: ccValue,
            bcc: bccValue,
            subject: json["subject"] as? String ?? "(no subject)",
            date: json["sent_at"] as? String ?? json["date"] as? String ?? json["internal_date"] as? String ?? "",
            snippet: json["snippet"] as? String ?? json["body_preview"] as? String ?? "",
            labels: json["labels"] as? [String] ?? [],
            hasAttachment: hasAttachment,
            threadID: threadID,
            sizeEstimate: sizeEstimate
        )
    }

    static func looksLikeGmailMessageID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.hasPrefix("text-") else { return false }
        guard Int(trimmed) == nil else { return false }
        let allowed = CharacterSet.alphanumerics
        return trimmed.rangeOfCharacter(from: allowed.inverted) == nil
    }

    private static func normalizedString(_ raw: Any?) -> String? {
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = raw as? Int {
            return String(value)
        }
        return nil
    }
}

struct SenderAggregate: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let email: String
    let count: Int
    let totalSize: String
}

struct StatsInfo {
    let totalMessages: Int
    let totalAccounts: Int
    let totalAttachments: Int
    let dbSize: String
    let lastSync: String
}

struct LabelInfo: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let count: Int
}

struct SearchLocalFilter {
    var fromContains: String = ""
    var toContains: String = ""
    var subjectContains: String = ""
    var senderOrRecipientContains: String = ""
    
    var isEmpty: Bool {
        fromContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        toContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        subjectContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        senderOrRecipientContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct VaultAccount: Identifiable, Hashable {
    let id: String
    let email: String
    let displayName: String
    let type: String
    let messageCount: Int
    let lastSync: String
}

struct AISearchTranslation: Equatable {
    let query: String
    let rawJSON: String
}

struct SenderSearchRequest: Equatable {
    let senderEmail: String
    let additionalKeywords: String
}

struct MailActionInsightItem: Identifiable, Hashable {
    var id: String { senderEmail.lowercased() }
    let senderName: String
    let senderEmail: String
    let totalMessages: Int
    let unreadMessages: Int
    let unopenedChains: Int
    let unreadInLast30Days: Int
    let messagesWithAttachments: Int
    let totalAttachmentSizeBytes: Int
}

struct MailActionInsights {
    let generatedAt: Date
    let unsubscribeCandidates: [MailActionInsightItem]
    let unreadMomentum: [MailActionInsightItem]
    let attachmentHeavySenders: [MailActionInsightItem]
}

// MARK: - Email Store

@MainActor
class EmailStore: ObservableObject {
    @Published var searchResults: [EmailMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statsInfo: StatsInfo?
    @Published var selectedMessage: EmailMessage?
    @Published var messageDetail: String = ""
    @Published var messageDetailHTML: String?
    @Published var senders: [SenderAggregate] = []
    @Published var allSenders: [SenderAggregate] = []
    @Published var isLoadingAllSenders = false
    @Published var senderEmailCache: [String: [EmailMessage]] = [:]
    @Published var isLoadingSenderEmails: Set<String> = []
    @Published var searchForSenderRequest: SenderSearchRequest? = nil
    @Published var mailActionInsights: MailActionInsights?
    @Published var isLoadingMailActionInsights = false
    @Published var mailActionInsightsError: String?
    @Published var isRefreshingEmail = false
    @Published var emailRefreshStatus = "Ready to refresh"
    @Published var emailRefreshError: String?
    @Published var accounts: [VaultAccount] = []
    @Published var isLoadingAccounts = false
    @Published var availableLabels: [LabelInfo] = []
    @Published var isLoadingLabels = false
    @Published var isPerformingAccountAction = false
    @Published var accountsError: String?
    @Published var accountActionStatus = ""
    @Published var aiSearchEnabled: Bool {
        didSet { UserDefaults.standard.set(aiSearchEnabled, forKey: Self.aiSearchEnabledKey) }
    }
    @Published var aiModelName: String {
        didSet { UserDefaults.standard.set(aiModelName, forKey: Self.aiModelNameKey) }
    }
    @Published var liveSearchEnabled: Bool {
        didSet { UserDefaults.standard.set(liveSearchEnabled, forKey: Self.liveSearchEnabledKey) }
    }
    @Published var aiSearchStatus = "AI query translation is disabled."
    @Published var aiTranslationMessage: String?  // shown in results column when AI fails

    var aiModelReady: Bool {
        aiSearchEnabled && ollamaReachable &&
        !ollamaInstalledModels.isEmpty &&
        ollamaInstalledModels.contains(aiModelName)
    }
    @Published var aiRuntimeStatus = "Checking AI runtime..."
    @Published var ollamaInstalled = false
    @Published var ollamaReachable = false
    @Published var ollamaBinaryPath: String?
    @Published var ollamaInstalledModels: [String] = []
    @Published var isInstallingAIModel = false
    @Published var installingAIModelName: String?
    @Published var aiModelInstallStatus = ""
    
    // Path to msgvault binary - adjust if needed
    var msgvaultPath: String = "/usr/local/bin/msgvault"
    
    private static let refreshStatusFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    private static let aiSearchEnabledKey = "search.ai.enabled"
    private static let aiModelNameKey = "search.ai.model"
    private static let liveSearchEnabledKey = "search.live.enabled"
    private static let defaultAIModelName = "qwen3.5:2b"
    private static let isoDateFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let fallbackDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    init() {
        let defaults = UserDefaults.standard
        self.aiSearchEnabled = defaults.object(forKey: Self.aiSearchEnabledKey) as? Bool ?? false
        self.aiModelName = defaults.string(forKey: Self.aiModelNameKey) ?? Self.defaultAIModelName
        self.liveSearchEnabled = defaults.object(forKey: Self.liveSearchEnabledKey) as? Bool ?? true
        // Try to find msgvault
        findMsgvault()
        Task { [weak self] in
            guard let self else { return }
            await self.refreshAIRuntimeStatus()
            self.updateAISearchStatus()
        }
    }
    
    private func findMsgvault() {
        if let resolved = RuntimePaths.resolveBinaryPath("msgvault") {
            msgvaultPath = resolved
        }
    }
    
    // MARK: - Command Runner
    
    private func runCommand(_ command: String, arguments: [String] = []) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        // Pass through environment including HOME/PATH for msgvault config.
        process.environment = RuntimePaths.processEnvironmentForUserHome()
        
        try process.run()
        
        // Drain output while the process is running to avoid pipe-buffer deadlocks.
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MsgVaultError.commandFailed(errorString)
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private func runMsgvault(arguments: [String]) throws -> String {
        var lastError: Error?
        for executable in msgvaultExecutableCandidates() {
            do {
                let output = try runCommand(
                    executable,
                    arguments: msgvaultInvocationArguments(for: executable, commandArguments: arguments)
                )
                if executable != "/usr/bin/env" {
                    msgvaultPath = executable
                }
                return output
            } catch {
                lastError = error
            }
        }
        throw lastError ?? MsgVaultError.notFound
    }
    
    private func runMsgvaultAsync(
        arguments: [String],
        timeoutSeconds: TimeInterval? = nil
    ) async throws -> String {
        var lastError: Error?
        for executable in msgvaultExecutableCandidates() {
            do {
                let output = try await Self.executeCommand(
                    path: executable,
                    arguments: msgvaultInvocationArguments(for: executable, commandArguments: arguments),
                    timeoutSeconds: timeoutSeconds
                )
                if executable != "/usr/bin/env" {
                    msgvaultPath = executable
                }
                return output
            } catch {
                lastError = error
            }
        }
        throw lastError ?? MsgVaultError.notFound
    }

    private func msgvaultExecutableCandidates() -> [String] {
        var candidates: [String] = []
        let trimmedStored = msgvaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStored.isEmpty {
            candidates.append(trimmedStored)
        }
        if let resolved = RuntimePaths.resolveBinaryPath("msgvault"),
           !resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(resolved)
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
    
    nonisolated private static func executeCommand(
        path: String,
        arguments: [String],
        timeoutSeconds: TimeInterval? = nil
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            process.environment = RuntimePaths.processEnvironmentForUserHome()
            
            try process.run()
            
            // Read command output concurrently while the process runs to prevent
            // deadlocks when search emits large payloads.
            let readOutputTask = Task.detached(priority: .utility) {
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            }
            
            if let timeoutSeconds {
                let deadline = Date().addingTimeInterval(timeoutSeconds)
                while process.isRunning {
                    if Date() >= deadline {
                        process.terminate()
                        try await Task.sleep(nanoseconds: 150_000_000)
                        if process.isRunning {
                            process.interrupt()
                        }
                        throw MsgVaultError.commandTimedOut(seconds: Int(timeoutSeconds.rounded()))
                    }
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            } else {
                process.waitUntilExit()
            }
            
            let data = await readOutputTask.value
            
            if process.terminationStatus != 0 {
                let mergedOutput = String(data: data, encoding: .utf8) ?? ""
                let errorString = Self.cleanErrorMessage(
                    mergedOutput.isEmpty ? "Unknown error" : mergedOutput
                )
                throw MsgVaultError.commandFailed(errorString)
            }
            
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
    
    nonisolated private static func cleanErrorMessage(_ raw: String) -> String {
        let lines = raw
            .replacingOccurrences(of: "Searching...", with: "")
            .replacingOccurrences(of: "Loading...", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("Usage:") }
            .filter { !$0.hasPrefix("Flags:") }
            .filter { !$0.hasPrefix("Global Flags:") }
            .filter { !$0.hasPrefix("msgvault ") }
            .filter { !$0.hasPrefix("-h,") && !$0.hasPrefix("--json") && !$0.hasPrefix("-n,") && !$0.hasPrefix("--offset") }
            .filter { !$0.hasPrefix("--config") && !$0.hasPrefix("--home") && !$0.hasPrefix("--local") && !$0.hasPrefix("-v,") }
        
        guard let first = lines.first else { return "Unknown error" }
        return first.replacingOccurrences(of: "Error: ", with: "")
    }
    
    func setAISearchEnabled(_ enabled: Bool) {
        aiSearchEnabled = enabled
        updateAISearchStatus()
    }
    
    func setAIModelName(_ modelName: String) {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        aiModelName = trimmed
        updateAISearchStatus()
    }
    
    func refreshAIRuntimeStatus() async {
        // Check if the binary exists (needed for install operations)
        let maybePath = findOllamaBinaryPath()
        ollamaBinaryPath = maybePath
        ollamaInstalled = maybePath != nil

        // Probe the HTTP API directly — confirms the daemon is running
        // and returns the accurate installed model list in one shot.
        do {
            let models = try await fetchOllamaInstalledModels()
            ollamaInstalledModels = models
            ollamaReachable = true
            aiRuntimeStatus = models.isEmpty
                ? "Ollama is running (no models pulled yet)."
                : "Ollama is running · \(models.count) model\(models.count == 1 ? "" : "s") installed."
            print("[AI Runtime] Models available: \(models.joined(separator: ", "))")
        } catch {
            ollamaReachable = false
            ollamaInstalledModels = []
            if ollamaInstalled {
                aiRuntimeStatus = "Ollama found but server is not running. Open Ollama.app or run `ollama serve`."
            } else {
                aiRuntimeStatus = "Ollama not found. Install from ollama.com to enable AI search."
            }
            print("[AI Runtime] Server probe failed: \(error.localizedDescription)")
        }
        updateAISearchStatus()
    }

    private func fetchOllamaInstalledModels(baseURL: String = "http://localhost:11434") async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return models.compactMap { $0["name"] as? String }.sorted()
    }
    
    @discardableResult
    func installAIModel(_ modelName: String) async -> Bool {
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            aiModelInstallStatus = "Choose a model tag before installing."
            return false
        }
        guard !isInstallingAIModel else {
            aiModelInstallStatus = "A model install is already in progress."
            return false
        }
        
        guard let ollamaPath = findOllamaBinaryPath() else {
            aiModelInstallStatus = "Ollama is not installed. Install Ollama first."
            await refreshAIRuntimeStatus()
            return false
        }
        
        isInstallingAIModel = true
        installingAIModelName = model
        aiModelInstallStatus = "Downloading \(model)... This can take a few minutes."
        
        defer {
            isInstallingAIModel = false
            installingAIModelName = nil
        }
        
        do {
            _ = try await Self.executeCommand(
                path: ollamaPath,
                arguments: ["pull", model],
                timeoutSeconds: nil
            )
            await refreshAIRuntimeStatus()
            aiModelInstallStatus = "Installed \(model) successfully."
            return true
        } catch {
            let message = Self.cleanErrorMessage(error.localizedDescription)
            aiModelInstallStatus = "Install failed for \(model): \(message)"
            await refreshAIRuntimeStatus()
            return false
        }
    }
    
    private func updateAISearchStatus() {
        guard aiSearchEnabled else {
            aiSearchStatus = "AI query translation is disabled."
            return
        }
        
        guard ollamaInstalled else {
            aiSearchStatus = "AI search is enabled, but Ollama is not installed."
            return
        }
        
        guard ollamaReachable else {
            aiSearchStatus = "AI search is enabled, but Ollama is not reachable."
            return
        }
        
        if !ollamaInstalledModels.isEmpty && !ollamaInstalledModels.contains(aiModelName) {
            aiSearchStatus = "Selected model \(aiModelName) is not pulled yet. Run `ollama pull \(aiModelName)`."
            return
        }
        
        aiSearchStatus = "AI query translation enabled (model: \(aiModelName))."
    }
    
    private func parseOllamaListModels(from output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .dropFirst() // header row
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let columns = trimmed.split(whereSeparator: \.isWhitespace)
                guard let first = columns.first else { return nil }
                return String(first)
            }
    }
    
    func translateNaturalLanguageSearch(_ request: String) async -> AISearchTranslation? {
        let prompt = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard aiSearchEnabled, !prompt.isEmpty else { return nil }

        aiTranslationMessage = nil

        if !ollamaInstalled || !ollamaReachable {
            await refreshAIRuntimeStatus()
            updateAISearchStatus()
        }

        guard ollamaReachable else {
            let msg = "AI search is unavailable — Ollama server is not running."
            aiSearchStatus = msg
            aiTranslationMessage = msg
            return nil
        }

        if !ollamaInstalledModels.isEmpty && !ollamaInstalledModels.contains(aiModelName) {
            let msg = "Model \"\(aiModelName)\" is not installed. Go to Settings → AI Setup to pull it."
            aiSearchStatus = msg
            aiTranslationMessage = msg
            return nil
        }

        let today = Self.translationDateFormatter.string(from: Date())

        // ── Pass 1: Natural language → structured JSON parameters ────────────
        //
        // IMPORTANT PROMPT DESIGN NOTE:
        // - Use ALL-NULL template so the model starts from null, fills only what's mentioned
        // - Never use type names ("string", "email") as schema values — models copy them literally
        // - Use concrete filled examples to show expected output format
        let currentYear = Int(today.prefix(4)) ?? 2026
        let lastYear = currentYear - 1

        let pass1System = """
        Extract email search parameters from the user's request. Output ONLY a JSON object. No markdown, no explanation, no extra text.

        Start from this all-null template and fill ONLY the fields directly mentioned in the request. Leave everything else null:
        {
          "keywords": null,
          "from": null,
          "to": null,
          "cc": null,
          "bcc": null,
          "subject": null,
          "label": null,
          "after": null,
          "before": null,
          "newer_than": null,
          "older_than": null,
          "larger": null,
          "smaller": null,
          "has_attachment": false
        }

        FIELD RULES:
        - "from": sender name or email address actually mentioned. If user says "from McKinsey", use "McKinsey". If a full email like "alice@co.com", use that.
        - "to": recipient name or address actually mentioned.
        - "subject": subject words actually mentioned. Only fill this if the user specifically says "subject" or "about [topic]".
        - "keywords": any free-text topic words not covered by other fields.
        - DO NOT invent values. If not mentioned, the field stays null.

        DATE RULES — choose exactly ONE approach, never mix:

        A) Specific month/year mentioned → use "after" + "before" only (never newer_than/older_than):
           "August last year" (today is \(today)) → after: "\(lastYear)-08-01", before: "\(lastYear)-09-01"
           "in March \(currentYear)" → after: "\(currentYear)-03-01", before: "\(currentYear)-04-01"
           "in \(lastYear)" → after: "\(lastYear)-01-01", before: "\(currentYear)-01-01"
           "last December" → after: "\(lastYear)-12-01", before: "\(currentYear)-01-01"
           "last September" → after: "\(lastYear)-09-01", before: "\(lastYear)-10-01"
           Rule: "before" = first day of the month AFTER the target month. Same year unless month is December.

        B) Vague/relative recency → use "newer_than" or "older_than" only (never after/before):
           "last week" → newer_than: "7d"
           "past month" (no specific month) → newer_than: "30d"
           "recently" → newer_than: "14d"

        EXAMPLES:

        Request: "find me emails from Tony Solon"
        Output: {"keywords":null,"from":"Tony Solon","to":null,"cc":null,"bcc":null,"subject":null,"label":null,"after":null,"before":null,"newer_than":null,"older_than":null,"larger":null,"smaller":null,"has_attachment":false}

        Request: "emails from McKinsey in August last year"
        Output: {"keywords":null,"from":"McKinsey","to":null,"cc":null,"bcc":null,"subject":null,"label":null,"after":"\(lastYear)-08-01","before":"\(lastYear)-09-01","newer_than":null,"older_than":null,"larger":null,"smaller":null,"has_attachment":false}

        Request: "invoices from HSBC with attachments"
        Output: {"keywords":"invoices","from":"HSBC","to":null,"cc":null,"bcc":null,"subject":null,"label":null,"after":null,"before":null,"newer_than":null,"older_than":null,"larger":null,"smaller":null,"has_attachment":true}

        Request: "emails from alice@company.com last week about the budget"
        Output: {"keywords":"budget","from":"alice@company.com","to":null,"cc":null,"bcc":null,"subject":null,"label":null,"after":null,"before":null,"newer_than":"7d","older_than":null,"larger":null,"smaller":null,"has_attachment":false}

        Request: "show me emails sent to John Smith last month"
        Output: {"keywords":null,"from":null,"to":"John Smith","cc":null,"bcc":null,"subject":null,"label":null,"after":null,"before":null,"newer_than":"30d","older_than":null,"larger":null,"smaller":null,"has_attachment":false}

        Request: "large attachments sent to the team this year"
        Output: {"keywords":null,"from":null,"to":null,"cc":null,"bcc":null,"subject":null,"label":null,"after":"\(currentYear)-01-01","before":null,"newer_than":null,"older_than":null,"larger":"1M","smaller":null,"has_attachment":true}
        """

        print("""

        ╔═══════════════════════════════════════════════╗
        ║ [AI Pass 1] NL→JSON   model=\(aiModelName)
        ╚═══════════════════════════════════════════════╝
        SYSTEM PROMPT:
        \(pass1System)

        USER MESSAGE:
        \(prompt)
        ───────────────────────────────────────────────
        """)

        do {
            let pass1Raw = try await callOllamaAPI(
                model: aiModelName,
                system: pass1System,
                userMessage: prompt
            )
            print("[AI Pass 1] Raw model content:\n>>>\(pass1Raw)<<<")

            let pass1Cleaned = stripThinkingTags(from: pass1Raw)

            guard let payload = parseTranslationPayload(from: pass1Cleaned) else {
                print("[AI Pass 1] ⚠️ JSON parse failed. Cleaned:\n\(pass1Cleaned)")
                let msg = "I couldn't understand that search request — try rephrasing it."
                aiSearchStatus = msg
                aiTranslationMessage = msg
                return nil
            }
            print("[AI Pass 1] ✅ JSON: \(payload.rawJSON)")

            var draft = buildTranslatedQuery(from: payload)
            // Deterministic fix: strip relative date tokens if absolute dates are present.
            // The model can hallucinate both simultaneously; this catches it before Pass 2.
            draft = resolveAbsoluteRelativeDateConflict(in: draft)
            print("[AI Pass 1] ✅ Draft query (after conflict resolution): \(draft)")

            guard !draft.isEmpty else {
                let msg = "Your request didn't produce any search filters — try adding more detail."
                aiSearchStatus = msg
                aiTranslationMessage = msg
                return nil
            }

            // ── Pass 2: Deterministic Swift validation ────────────────────────
            // LLM-based validation with a 2B model actively corrupts correct
            // queries by hallucinating operator names from its own prompt text.
            // All structural rules are enforced here in Swift instead.
            // A reasoning model (7B+) can be re-enabled as Pass 2 in a future build.
            draft = applyDeterministicQueryFixes(to: draft)
            print("[AI Validation] Final query: \(draft)")

            aiSearchStatus = "AI query translation active (\(aiModelName))."
            aiTranslationMessage = nil
            return AISearchTranslation(query: draft, rawJSON: payload.rawJSON)

        } catch {
            print("[AI Search] ❌ \(error)")
            let msg = "AI search failed: \(error.localizedDescription)"
            aiSearchStatus = msg
            aiTranslationMessage = msg
            return nil
        }
    }

    // Call the Ollama REST API directly.
    // - Reasoning models (deepseek-r1, qwq): thinking is ENABLED — their reasoning chain
    //   significantly improves extraction quality. We strip <think> tags from the output.
    // - Hybrid models (qwen3): thinking is disabled via think:false because Qwen3 with
    //   thinking sends the answer only in message.thinking, leaving content empty.
    private func callOllamaAPI(
        model: String,
        system: String,
        userMessage: String,
        baseURL: String = "http://localhost:11434"
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw URLError(.badURL)
        }

        // Detect whether this is a model that benefits from thinking being suppressed.
        // Qwen3/Qwen3.5 hybrid: disabling think avoids empty content field.
        // DeepSeek-R1 and other dedicated reasoning models: let them think.
        let modelLower = model.lowercased()
        let suppressThinking = modelLower.contains("qwen3") || modelLower.contains("qwen3.5")
        print("[AI API] Model: \(model) — thinking \(suppressThinking ? "suppressed" : "enabled")")

        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userMessage]
            ],
            "options": [
                "temperature": 0.0,
                "num_predict": 1024    // increased for reasoning models that output more tokens
            ]
        ]
        if suppressThinking {
            body["think"] = false
        }

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        // Log the full raw response so we can see exactly what the model returned
        let rawResponseString = String(data: data, encoding: .utf8) ?? "(could not decode)"
        print("[AI API] Full response JSON:\n\(rawResponseString)")

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "Ollama returned HTTP \(http.statusCode): \(rawResponseString)"
            ])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any] else {
            print("[AI API] ⚠️ Could not parse message from response")
            throw URLError(.cannotParseResponse)
        }

        let content = (message["content"] as? String) ?? ""
        let thinking = (message["thinking"] as? String) ?? ""

        print("[AI API] content field: >>>\(content)<<<")
        print("[AI API] thinking field length: \(thinking.count) chars")

        // Qwen3 thinking models may leave content empty and put everything in thinking.
        // If content is empty/whitespace, fall back to the thinking field so at minimum
        // we can debug what the model intended. The caller strips <think> tags.
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !thinking.isEmpty {
            print("[AI API] ⚠️ content was empty — falling back to thinking field")
            return thinking
        }

        return content
    }
    
    private struct TranslationPayload {
        let values: [String: Any]
        let rawJSON: String
    }
    
    private static let translationDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private func findOllamaBinaryPath() -> String? {
        RuntimePaths.resolveBinaryPath("ollama")
    }

    func runTestCommand() throws -> String {
        var lastError: Error?
        for executable in msgvaultExecutableCandidates() {
            do {
                let output = try runCommand(
                    executable,
                    arguments: msgvaultInvocationArguments(
                        for: executable,
                        commandArguments: ["list-accounts", "--json"]
                    )
                )
                if executable != "/usr/bin/env" {
                    msgvaultPath = executable
                } else if let resolved = RuntimePaths.resolveBinaryPath("msgvault") {
                    msgvaultPath = resolved
                }

                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                let shownPath = msgvaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return "Connected (\(shownPath))"
                }
                return "Connected (\(shownPath)) \(trimmed)"
            } catch {
                lastError = error
            }
        }

        throw lastError ?? MsgVaultError.notFound
    }
    
    // All structural rules applied deterministically after Pass 1.
    // This replaces the LLM Pass 2 validator, which a 2B model cannot
    // perform reliably without hallucinating values from its own prompt.
    private func applyDeterministicQueryFixes(to query: String) -> String {
        var q = resolveAbsoluteRelativeDateConflict(in: query)
        q = removeSpuriousOperatorLiterals(from: q)
        q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        return q
    }

    // Remove any tokens where the operator value is a known placeholder/type literal
    // that a model might copy from its own prompt (e.g. "from:email", "to:email",
    // "subject:text", "label:TEXT", "has:attachment" when not explicitly asked).
    private func removeSpuriousOperatorLiterals(from query: String) -> String {
        let spurious = [
            "from:email", "to:email", "cc:email", "bcc:email",
            "subject:text", "subject:string", "label:TEXT", "label:text",
            "larger:NM", "smaller:NM", "larger:NK", "smaller:NK"
        ]
        var tokens = query.split(separator: " ").map(String.init)
        let before = tokens
        tokens = tokens.filter { token in
            !spurious.contains(token.lowercased())
        }
        if tokens != before {
            print("[AI Validation] Removed spurious literals: \(Set(before).subtracting(Set(tokens)))")
        }
        return tokens.joined(separator: " ")
    }

    // If a query contains both absolute (after:/before:) and relative (newer_than:/older_than:)
    // date operators, remove the relative ones — absolute is always more specific.
    private func resolveAbsoluteRelativeDateConflict(in query: String) -> String {
        let hasAbsolute = query.contains("after:") || query.contains("before:")
        guard hasAbsolute else { return query }

        let relativePattern = try? NSRegularExpression(
            pattern: #"(newer_than|older_than):\S+"#,
            options: .caseInsensitive
        )
        let range = NSRange(query.startIndex..., in: query)
        var cleaned = relativePattern?.stringByReplacingMatches(
            in: query, range: range, withTemplate: ""
        ) ?? query

        // Collapse any double-spaces left behind
        while cleaned.contains("  ") { cleaned = cleaned.replacingOccurrences(of: "  ", with: " ") }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned != query {
            print("[AI Conflict Fix] Removed relative date tokens from: \(query)")
            print("[AI Conflict Fix] Result: \(cleaned)")
        }
        return cleaned
    }

    private func stripThinkingTags(from text: String) -> String {
        var result = text
        while let openRange = result.range(of: "<think>", options: .caseInsensitive),
              let closeRange = result.range(of: "</think>", options: .caseInsensitive),
              openRange.lowerBound < closeRange.upperBound {
            result.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        }
        // Also strip any stray <think> without closing tag
        if let openRange = result.range(of: "<think>", options: .caseInsensitive) {
            result.removeSubrange(openRange.lowerBound...)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseTranslationPayload(from output: String) -> TranslationPayload? {
        var jsonString = extractJSONObjectString(from: output)
        if jsonString == nil {
            jsonString = output.components(separatedBy: "```")
                .first(where: { $0.contains("{") && $0.contains("}") })
                .flatMap { extractJSONObjectString(from: $0) }
        }
        
        guard let jsonString,
              let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return TranslationPayload(values: parsed, rawJSON: jsonString)
    }
    
    private func buildTranslatedQuery(from payload: TranslationPayload) -> String {
        var parts: [String] = []
        let json = payload.values

        // Address fields: only use the operator if the value looks like an actual email address.
        // Company names ("McKinsey"), people names ("John Smith"), and domains without @
        // get added as free-text keywords so msgvault does a broader fuzzy match.
        appendAddressToken(from: json, key: "from",  prefix: "from:",  into: &parts)
        appendAddressToken(from: json, key: "to",    prefix: "to:",    into: &parts)
        appendAddressToken(from: json, key: "cc",    prefix: "cc:",    into: &parts)
        appendAddressToken(from: json, key: "bcc",   prefix: "bcc:",   into: &parts)

        appendToken(from: json, key: "subject",    prefix: "subject:",    into: &parts)
        appendToken(from: json, key: "label",      prefix: "label:",      into: &parts)
        appendToken(from: json, key: "after",      prefix: "after:",      into: &parts)

        // Deterministic before-date logic:
        // When after: is the 1st of a month, the correct before: is ALWAYS the 1st
        // of the next month. The model frequently defaults to 2026-01-01 regardless
        // of which month after: is — we override whenever it's wrong.
        let afterValue = (json["after"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let beforeValue = (json["before"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !afterValue.isEmpty {
            let correctBefore = inferBeforeDate(from: afterValue)
            if let correctBefore {
                // Use the correctly computed next-month boundary.
                // If the model already gave the right value, no change.
                // If it gave the wrong value (e.g. always Jan 1), override it.
                if !beforeValue.isEmpty && beforeValue != correctBefore {
                    print("[AI Date Fix] Overriding wrong before:\(beforeValue) → before:\(correctBefore) (after:\(afterValue))")
                }
                parts.append("before:\(correctBefore)")
            } else if !beforeValue.isEmpty {
                // after: is not the 1st of a month — use model's value as-is
                parts.append("before:\(beforeValue)")
            }
        } else if !beforeValue.isEmpty {
            // No after: at all — use model's before: directly
            appendToken(from: json, key: "before", prefix: "before:", into: &parts)
        }

        appendToken(from: json, key: "newer_than", prefix: "newer_than:", into: &parts)
        appendToken(from: json, key: "older_than",  prefix: "older_than:",  into: &parts)
        appendToken(from: json, key: "larger",      prefix: "larger:",      into: &parts)
        appendToken(from: json, key: "smaller",     prefix: "smaller:",     into: &parts)

        if let hasAttachment = json["has_attachment"] as? Bool, hasAttachment {
            parts.append("has:attachment")
        }

        if let keywords = json["keywords"] as? String {
            let trimmed = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(makeQuotedToken(trimmed))
            }
        }

        return parts.joined(separator: " ")
    }

    // Address fields: use operator only for proper email addresses (contains @).
    // Plain names and company names ("McKinsey", "Alice") become free-text keywords
    // so msgvault's full-text search finds them in From/To headers broadly.
    private func appendAddressToken(from json: [String: Any], key: String, prefix: String, into parts: inout [String]) {
        guard let value = json[key] as? String else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.contains("@") {
            // Proper email address — use the operator for exact match
            parts.append("\(prefix)\(makeOperatorValue(trimmed))")
        } else {
            // Name or company — add as keyword so FTS searches across all header fields
            parts.append(makeQuotedToken(trimmed))
            print("[AI Address Fix] '\(trimmed)' is not an email, using as keyword instead of \(prefix)")
        }
    }

    // If the model gives after:YYYY-MM-DD with no before:, and the date is the first
    // of a month, infer before: as the first of the *next* month — closing the range.
    private func inferBeforeDate(from afterDate: String) -> String? {
        let parts = afterDate.split(separator: "-")
        guard parts.count == 3,
              let year  = Int(parts[0]),
              let month = Int(parts[1]),
              let day   = Int(parts[2]),
              day == 1 else { return nil }

        let nextMonth = month == 12 ? 1  : month + 1
        let nextYear  = month == 12 ? year + 1 : year
        return String(format: "%04d-%02d-01", nextYear, nextMonth)
    }

    private func appendToken(from json: [String: Any], key: String, prefix: String, into parts: inout [String]) {
        guard let value = json[key] as? String else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        parts.append("\(prefix)\(makeOperatorValue(trimmed))")
    }
    
    private func makeOperatorValue(_ value: String) -> String {
        guard value.contains(where: \.isWhitespace) else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
    
    private func makeQuotedToken(_ value: String) -> String {
        guard value.contains(where: \.isWhitespace) else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
    
    // MARK: - Search
    
    func refreshEmailInBackground() {
        guard !isRefreshingEmail else { return }
        
        isRefreshingEmail = true
        emailRefreshError = nil
        emailRefreshStatus = "Refreshing archive in background..."
        
        Task {
            do {
                _ = try await runMsgvaultAsync(arguments: ["sync"])
                let completedAt = Date()
                emailRefreshStatus = "Last refresh: \(Self.refreshStatusFormatter.string(from: completedAt))"
                
                // Refresh stats after sync so users immediately see updated archive info.
                if let latestStats = try? await runMsgvaultAsync(arguments: ["stats"]) {
                    statsInfo = parseStats(latestStats)
                }
            } catch {
                let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let cleanedMessage = Self.cleanErrorMessage(rawMessage)
                emailRefreshError = cleanedMessage
                emailRefreshStatus = "Refresh failed"
            }
            
            isRefreshingEmail = false
        }
    }
    
    func search(
        query: String,
        localFilter: SearchLocalFilter? = nil
    ) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        let effectiveLocalFilter = localFilter ?? SearchLocalFilter()
        
        let queryCandidates = buildSearchQueryCandidates(from: query)
        
        isLoading = true
        errorMessage = nil
        
        var mergedMessages: [EmailMessage] = []
        var seenMessageIDs = Set<String>()
        var lastError: Error?
        
        for candidate in queryCandidates {
            do {
                let output = try await runMsgvaultAsync(
                    arguments: ["search", candidate, "--json", "-n", "100"]
                )
                let messages = parseSearchResults(output)
                for message in messages where seenMessageIDs.insert(message.id).inserted {
                    mergedMessages.append(message)
                }
            } catch {
                if let fallbackQuery = fallbackQueryForSpecialCharacters(query: candidate, error: error) {
                    do {
                        let output = try await runMsgvaultAsync(
                            arguments: ["search", fallbackQuery, "--json", "-n", "100"]
                        )
                        let messages = parseSearchResults(output)
                        for message in messages where seenMessageIDs.insert(message.id).inserted {
                            mergedMessages.append(message)
                        }
                    } catch {
                        lastError = error
                    }
                } else {
                    lastError = error
                }
            }
        }
        
        if mergedMessages.isEmpty {
            searchResults = []
            if let lastError {
                errorMessage = "Search failed: \(lastError.localizedDescription)"
            } else {
                errorMessage = nil
            }
        } else {
            searchResults = applyLocalFilter(mergedMessages, filter: effectiveLocalFilter)
            errorMessage = nil
        }
        
        isLoading = false
    }

    func searchRawMessages(
        query: String,
        limit: Int = 100
    ) async throws -> [EmailMessage] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let queryCandidates = buildSearchQueryCandidates(from: trimmedQuery)
        var mergedMessages: [EmailMessage] = []
        var seenMessageIDs = Set<String>()
        var lastError: Error?

        for candidate in queryCandidates {
            do {
                let output = try await runMsgvaultAsync(
                    arguments: ["search", candidate, "--json", "-n", "\(limit)"]
                )
                let messages = parseSearchResults(output)
                for message in messages where seenMessageIDs.insert(message.id).inserted {
                    mergedMessages.append(message)
                }
            } catch {
                if let fallbackQuery = fallbackQueryForSpecialCharacters(query: candidate, error: error) {
                    do {
                        let output = try await runMsgvaultAsync(
                            arguments: ["search", fallbackQuery, "--json", "-n", "\(limit)"]
                        )
                        let messages = parseSearchResults(output)
                        for message in messages where seenMessageIDs.insert(message.id).inserted {
                            mergedMessages.append(message)
                        }
                    } catch {
                        lastError = error
                    }
                } else {
                    lastError = error
                }
            }
        }

        if mergedMessages.isEmpty, let lastError {
            throw lastError
        }

        return mergedMessages
    }
    
    // MARK: - Stats
    
    func loadStats() async {
        isLoading = true
        do {
            let output = try await runMsgvaultAsync(arguments: ["stats"])
            statsInfo = parseStats(output)
        } catch {
            errorMessage = "Failed to load stats: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Accounts

    func loadAccounts() async {
        isLoadingAccounts = true
        accountsError = nil
        do {
            let output = try await runMsgvaultAsync(arguments: ["list-accounts", "--json"])
            accounts = parseAccounts(output)
            if accountActionStatus.isEmpty {
                accountActionStatus = accounts.isEmpty ? "No accounts found yet." : "Loaded \(accounts.count) account(s)."
            }
        } catch {
            let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            accountsError = Self.cleanErrorMessage(rawMessage)
            accounts = []
        }
        isLoadingAccounts = false
    }

    func fetchLabels() async {
        guard !isLoadingLabels else { return }
        isLoadingLabels = true
        defer { isLoadingLabels = false }
        do {
            let output = try await runMsgvaultAsync(arguments: ["list-labels", "--json", "-n", "500"])
            guard let data = output.data(using: .utf8),
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            availableLabels = jsonArray.compactMap { dict in
                guard let key = dict["key"] as? String else { return nil }
                return LabelInfo(key: key, count: dict["count"] as? Int ?? 0)
            }.sorted { $0.count > $1.count }
        } catch {
            // Labels are optional; silently ignore errors
        }
    }

    @discardableResult
    func addAccount(
        email: String,
        displayName: String,
        headless: Bool,
        force: Bool
    ) async -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else {
            accountsError = "Please enter an email address."
            return false
        }

        isPerformingAccountAction = true
        accountsError = nil
        accountActionStatus = "Starting OAuth flow for \(normalizedEmail)..."

        var arguments = ["add-account", normalizedEmail]
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDisplayName.isEmpty {
            arguments += ["--display-name", trimmedDisplayName]
        }
        if headless {
            arguments.append("--headless")
        }
        if force {
            arguments.append("--force")
        }

        defer { isPerformingAccountAction = false }

        do {
            let output = try await runMsgvaultAsync(arguments: arguments, timeoutSeconds: 180)
            accountActionStatus = firstMeaningfulLine(in: output) ?? "Account added: \(normalizedEmail)"
            await loadAccounts()
            if let latestStats = try? await runMsgvaultAsync(arguments: ["stats"]) {
                statsInfo = parseStats(latestStats)
            }
            return true
        } catch {
            let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let cleaned = Self.cleanErrorMessage(rawMessage)
            accountsError = Self.friendlyAddAccountError(raw: rawMessage, cleaned: cleaned)
            accountActionStatus = "Add account failed"
            return false
        }
    }
    
    // MARK: - Senders
    
    func loadTopSenders() async {
        isLoading = true
        do {
            let output = try await runMsgvaultAsync(arguments: ["list-senders", "--json", "-n", "50"])
            senders = parseSenders(output)
            // Keep top-senders fast by default; full sender search is loaded lazily on demand.
            allSenders = []
        } catch {
            errorMessage = "Failed to load senders: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func loadAllSendersIfNeeded(forceRefresh: Bool = false) async {
        guard !isLoadingAllSenders else { return }
        guard forceRefresh || allSenders.isEmpty else { return }

        isLoadingAllSenders = true
        defer { isLoadingAllSenders = false }

        do {
            // msgvault list-senders defaults to -n 50; use a high limit to get all senders
            // across all boxes (including low-volume personal contacts), not just top senders.
            let output = try await runMsgvaultAsync(arguments: ["list-senders", "--json", "-n", "100000"])
            allSenders = parseSenders(output)
        } catch {
            errorMessage = "Failed to load full sender list: \(error.localizedDescription)"
        }
    }
    
    func loadEmailsForSender(_ email: String) async {
        guard !email.isEmpty, !isLoadingSenderEmails.contains(email) else { return }
        isLoadingSenderEmails.insert(email)
        defer { isLoadingSenderEmails.remove(email) }
        do {
            let output = try await runMsgvaultAsync(
                arguments: ["search", "from:\(email)", "--json", "-n", "200"]
            )
            let messages = parseSearchResults(output)
            senderEmailCache[email] = messages
        } catch {
            if senderEmailCache[email] == nil {
                senderEmailCache[email] = []
            }
        }
    }

    func loadMailActionInsights(toAccount: String = "") async {
        guard !isLoadingMailActionInsights else { return }
        isLoadingMailActionInsights = true
        mailActionInsightsError = nil
        defer { isLoadingMailActionInsights = false }

        do {
            // Keep this work bounded so we do not fire too many automatic searches.
            let senderSampleLimit = 14
            let senderOutput = try await runMsgvaultAsync(arguments: ["list-senders", "--json", "-n", "\(senderSampleLimit)"])
            let topSenders = parseSenders(senderOutput)

            let accountClause = toAccount.trimmingCharacters(in: .whitespacesAndNewlines)
            let accountSuffix = accountClause.isEmpty ? "" : " to:\(makeOperatorValue(accountClause))"

            var bySenderEmail: [String: MailActionInsightItem] = [:]

            for sender in topSenders {
                let normalizedSenderEmail = normalizedSenderFilterValue(sender.email)
                guard !normalizedSenderEmail.isEmpty else { continue }

                do {
                    async let unreadAllTask = mailActionSearchMessages(
                        senderEmail: normalizedSenderEmail,
                        filters: "label:UNREAD",
                        limit: 180
                    )
                    async let unreadRecentTask = mailActionSearchMessages(
                        senderEmail: normalizedSenderEmail,
                        filters: "label:UNREAD newer_than:30d",
                        limit: 120
                    )
                    async let attachmentsTask = mailActionSearchMessages(
                        senderEmail: normalizedSenderEmail,
                        filters: "has:attachment\(accountSuffix)",
                        limit: 160
                    )

                    let unreadMessages = try await unreadAllTask
                    let unreadRecentMessages = try await unreadRecentTask
                    let attachmentMessages = try await attachmentsTask
                    let unreadChains = Set(unreadMessages.map { chainKey(for: $0) }).count
                    let totalMessages = max(sender.count, unreadMessages.count, attachmentMessages.count)
                    let totalAttachmentSizeBytes = attachmentMessages.reduce(0) { $0 + $1.sizeEstimate }

                    let item = MailActionInsightItem(
                        senderName: sender.name,
                        senderEmail: normalizedSenderEmail,
                        totalMessages: totalMessages,
                        unreadMessages: unreadMessages.count,
                        unopenedChains: unreadChains,
                        unreadInLast30Days: unreadRecentMessages.count,
                        messagesWithAttachments: attachmentMessages.count,
                        totalAttachmentSizeBytes: totalAttachmentSizeBytes
                    )
                    bySenderEmail[item.id] = item
                } catch {
                    // Skip individual sender failures so one bad sender doesn't hide all insights.
                    continue
                }
            }

            let allInsights = bySenderEmail.values.filter { $0.totalMessages >= 4 }

            let unsubscribeCandidates = allInsights
                .filter {
                    let unreadRate = Double($0.unreadMessages) / Double(max($0.totalMessages, 1))
                    return $0.unopenedChains >= 3 || ($0.unreadMessages >= 6 && unreadRate >= 0.55)
                }
                .sorted {
                    if $0.unopenedChains != $1.unopenedChains { return $0.unopenedChains > $1.unopenedChains }
                    if $0.unreadMessages != $1.unreadMessages { return $0.unreadMessages > $1.unreadMessages }
                    return $0.totalMessages > $1.totalMessages
                }

            let unreadMomentum = allInsights
                .filter { $0.unreadInLast30Days >= 2 }
                .sorted {
                    if $0.unreadInLast30Days != $1.unreadInLast30Days { return $0.unreadInLast30Days > $1.unreadInLast30Days }
                    return $0.unreadMessages > $1.unreadMessages
                }

            let attachmentHeavySenders = allInsights
                .filter { $0.messagesWithAttachments >= 2 }
                .sorted {
                    if $0.totalAttachmentSizeBytes != $1.totalAttachmentSizeBytes {
                        return $0.totalAttachmentSizeBytes > $1.totalAttachmentSizeBytes
                    }
                    return $0.messagesWithAttachments > $1.messagesWithAttachments
                }

            mailActionInsights = MailActionInsights(
                generatedAt: Date(),
                unsubscribeCandidates: Array(unsubscribeCandidates.prefix(8)),
                unreadMomentum: Array(unreadMomentum.prefix(8)),
                attachmentHeavySenders: Array(attachmentHeavySenders.prefix(8))
            )
        } catch {
            let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            mailActionInsightsError = Self.cleanErrorMessage(rawMessage)
        }
    }

    private func mailActionSearchMessages(
        senderEmail: String,
        filters: String,
        limit: Int
    ) async throws -> [EmailMessage] {
        let senderToken = "from:\(makeOperatorValue(senderEmail))"
        let trimmedFilters = filters.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmedFilters.isEmpty ? senderToken : "\(senderToken) \(trimmedFilters)"
        let output = try await runMsgvaultAsync(
            arguments: ["search", query, "--json", "-n", "\(limit)"]
        )
        return parseSearchResults(output)
    }
    
    // MARK: - Message Detail
    
    func loadMessageDetail(id: String) async {
        messageDetail = ""
        messageDetailHTML = nil
        
        do {
            let output = try await runMsgvaultAsync(arguments: ["show-message", id, "--json"])
            if let detail = parseMessageDetail(output) {
                messageDetail = detail.bodyText
                messageDetailHTML = detail.bodyHTML
                if let current = selectedMessage, current.id == id {
                    selectedMessage = mergedMessage(current, with: detail)
                }
            } else {
                // Fallback for older/atypical output formats.
                messageDetail = output
                messageDetailHTML = nil
            }
        } catch {
            do {
                // Compatibility fallback if --json isn't supported.
                let legacyOutput = try await runMsgvaultAsync(arguments: ["show-message", id])
                messageDetail = legacyOutput
                messageDetailHTML = nil
            } catch {
                messageDetail = "Failed to load message: \(error.localizedDescription)"
                messageDetailHTML = nil
            }
        }
    }
    
    func fetchMessageDetail(for message: EmailMessage) async -> (
        message: EmailMessage,
        bodyText: String,
        bodyHTML: String?
    ) {
        do {
            let output = try await runMsgvaultAsync(arguments: ["show-message", message.id, "--json"])
            if let detail = parseMessageDetail(output) {
                return (mergedMessage(message, with: detail), detail.bodyText, detail.bodyHTML)
            }
            return (message, output, nil)
        } catch {
            do {
                let legacyOutput = try await runMsgvaultAsync(arguments: ["show-message", message.id])
                return (message, legacyOutput, nil)
            } catch {
                return (message, "Failed to load message: \(error.localizedDescription)", nil)
            }
        }
    }

    // MARK: - Parsers
    
    private func parseSearchResults(_ output: String) -> [EmailMessage] {
        // Strip progress text (e.g. "Searching...") and keep only JSON payload if present.
        let cleanedOutput = extractJSONArrayString(from: output) ?? output
        
        // msgvault search --json can output either an array or JSONL.
        var messages: [EmailMessage] = []
        
        // First try parsing as a JSON array
        if let data = cleanedOutput.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for json in jsonArray {
                if let msg = EmailMessage.parse(from: json) {
                    messages.append(msg)
                }
            }
            return messages
        }
        
        // Otherwise try JSONL (one object per line)
        let lines = cleanedOutput.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = EmailMessage.parse(from: json) {
                messages.append(msg)
            }
        }
        
        // If JSON parsing fails entirely, try parsing the text output
        if messages.isEmpty && !cleanedOutput.isEmpty {
            messages = parseTextSearchResults(cleanedOutput)
        }
        
        return messages
    }
    
    private func parseTextSearchResults(_ output: String) -> [EmailMessage] {
        // Fallback: parse the non-JSON text output
        // msgvault search typically shows results like:
        // [date] From: sender Subject: subject
        var messages: [EmailMessage] = []
        let lines = output.components(separatedBy: .newlines)
        var currentId = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Try to extract basic info from each result line
            currentId += 1
            messages.append(EmailMessage(
                id: "text-\(currentId)",
                gmailMessageID: nil,
                from: extractField(from: trimmed, field: "From:") ?? "",
                to: extractField(from: trimmed, field: "To:") ?? "",
                cc: extractField(from: trimmed, field: "CC:") ?? "",
                bcc: extractField(from: trimmed, field: "BCC:") ?? "",
                subject: extractField(from: trimmed, field: "Subject:") ?? trimmed,
                date: extractDatePrefix(from: trimmed) ?? "",
                snippet: trimmed,
                labels: [],
                hasAttachment: false,
                threadID: nil,
                sizeEstimate: 0
            ))
        }
        return messages
    }
    
    private func extractField(from line: String, field: String) -> String? {
        guard let range = line.range(of: field) else { return nil }
        let after = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        // Take until next known field or end of line
        let nextFields = ["From:", "To:", "Subject:", "Date:"]
        for next in nextFields where next != field {
            if let nextRange = after.range(of: next) {
                return String(after[..<nextRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return String(after)
    }
    
    private func extractDatePrefix(from line: String) -> String? {
        // Try to match a date at the start like [2024-01-15] or 2024-01-15
        let pattern = #"^\[?(\d{4}-\d{2}-\d{2}[T\s]?\d{0,2}:?\d{0,2}:?\d{0,2})\]?"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            return String(line[range])
        }
        return nil
    }
    
    private func parseStats(_ output: String) -> StatsInfo {
        // Parse the text output from msgvault stats
        var total = 0
        var accounts = 0
        var attachments = 0
        var dbSize = ""
        var lastSync = ""
        
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("message") {
                total = extractNumber(from: line) ?? 0
            } else if lower.contains("account") {
                accounts = extractNumber(from: line) ?? 0
            } else if lower.contains("attachment") {
                attachments = extractNumber(from: line) ?? 0
            } else if lower.contains("size") && !lower.contains("attachment") {
                dbSize = formatDatabaseSize(extractValue(from: line) ?? "")
            } else if lower.contains("sync") || lower.contains("last") {
                lastSync = extractValue(from: line) ?? ""
            }
        }
        
        return StatsInfo(
            totalMessages: total,
            totalAccounts: accounts,
            totalAttachments: attachments,
            dbSize: dbSize,
            lastSync: lastSync
        )
    }
    
    private func parseSenders(_ output: String) -> [SenderAggregate] {
        let cleanedOutput = extractJSONArrayString(from: output) ?? output
        
        if let data = cleanedOutput.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.compactMap { json in
                guard let count = json["count"] as? Int else { return nil }
                let key = (json["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
                let totalSizeBytes = json["total_size"] as? Int ?? 0
                return SenderAggregate(
                    name: key,
                    email: key,
                    count: count,
                    totalSize: formatBytes(totalSizeBytes)
                )
            }
        }
        
        var result: [SenderAggregate] = []
        let lines = cleanedOutput.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Typical format: count  email/name  size
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            
            // Try to parse - first or last element might be the count
            if let count = Int(parts[0]) {
                let name = parts.dropFirst().dropLast().joined(separator: " ")
                let size = parts.last ?? ""
                result.append(SenderAggregate(
                    name: name,
                    email: name,
                    count: count,
                    totalSize: size
                ))
            }
        }
        return result
    }

    private func parseAccounts(_ output: String) -> [VaultAccount] {
        let cleanedOutput = extractJSONArrayString(from: output) ?? output

        guard let data = cleanedOutput.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return jsonArray.compactMap { json in
            guard let email = json["email"] as? String, !email.isEmpty else { return nil }
            let type = json["type"] as? String ?? "gmail"
            return VaultAccount(
                id: "\(type):\(email.lowercased())",
                email: email,
                displayName: json["display_name"] as? String ?? "",
                type: type,
                messageCount: json["message_count"] as? Int ?? 0,
                lastSync: json["last_sync"] as? String ?? ""
            )
        }
        .sorted { left, right in
            left.email.localizedCaseInsensitiveCompare(right.email) == .orderedAscending
        }
    }
    
    private struct MessageDetailPayload {
        let bodyText: String
        let bodyHTML: String?
        let gmailMessageID: String?
        let from: String
        let to: String
        let cc: String
        let bcc: String
        let subject: String
        let date: String
        let labels: [String]
        let hasAttachment: Bool
        let threadID: String?
        let sizeEstimate: Int
    }
    
    private func parseMessageDetail(_ output: String) -> MessageDetailPayload? {
        let cleanedOutput = extractJSONObjectString(from: output) ?? output
        guard let data = cleanedOutput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let normalize: (Any?) -> String? = { raw in
            if let value = raw as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let value = raw as? Int {
                return String(value)
            }
            return nil
        }
        
        let bodyText = (json["body_text"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawHTML = (json["body_html"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let fromValue = parseAddressList(json["from"] ?? json["from_email"] ?? json["sender"])
        let toValue = parseAddressList(json["to"] ?? json["to_emails"] ?? json["recipients"])
        let ccValue = parseAddressList(json["cc"] ?? json["cc_emails"])
        let bccValue = parseAddressList(json["bcc"] ?? json["bcc_emails"])
        let subjectValue = (json["subject"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dateValue = (json["sent_at"] as? String
            ?? json["date"] as? String
            ?? json["internal_date"] as? String
            ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let labelsValue = json["labels"] as? [String] ?? []
        let gmailMessageIDValue: String? =
            normalize(json["source_message_id"])
            ?? normalize(json["gmail_id"])
            ?? normalize(json["gmailId"])
            ?? {
                if let messageID = normalize(json["message_id"]),
                   EmailMessage.looksLikeGmailMessageID(messageID) {
                    return messageID
                }
                if let idValue = normalize(json["id"]),
                   EmailMessage.looksLikeGmailMessageID(idValue) {
                    return idValue
                }
                return nil
            }()
        let hasAttachmentValue =
            (json["has_attachment"] as? Bool ?? false) ||
            (json["has_attachments"] as? Bool ?? false) ||
            ((json["attachment_count"] as? Int ?? 0) > 0) ||
            ((json["attachments"] as? [[String: Any]])?.isEmpty == false)
        let threadIDValue: String? =
            (json["thread_id"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (json["threadId"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (json["conversation_id"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (json["conversation_id"] as? Int).map(String.init)
        let sizeEstimateValue = json["size_estimate"] as? Int ?? 0

        let bodyHTML = (rawHTML?.isEmpty == false) ? rawHTML : nil
        
        // When text is absent, keep a lightweight placeholder so the UI doesn't look empty.
        let effectiveText = bodyText.isEmpty
            ? (bodyHTML == nil ? "No message body available." : "")
            : bodyText
        
        return MessageDetailPayload(
            bodyText: effectiveText,
            bodyHTML: bodyHTML,
            gmailMessageID: gmailMessageIDValue,
            from: fromValue,
            to: toValue,
            cc: ccValue,
            bcc: bccValue,
            subject: subjectValue,
            date: dateValue,
            labels: labelsValue,
            hasAttachment: hasAttachmentValue,
            threadID: threadIDValue,
            sizeEstimate: sizeEstimateValue
        )
    }

    private func mergedMessage(_ base: EmailMessage, with detail: MessageDetailPayload) -> EmailMessage {
        let from = detail.from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? base.from : detail.from
        let to = detail.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? base.to : detail.to
        let cc = detail.cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? base.cc : detail.cc
        let bcc = detail.bcc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? base.bcc : detail.bcc
        let subject = detail.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? base.subject : detail.subject
        let date = detail.date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? base.date : detail.date
        let labels = detail.labels.isEmpty ? base.labels : detail.labels
        let gmailMessageID = detail.gmailMessageID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? detail.gmailMessageID
            : base.gmailMessageID
        let threadID = detail.threadID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? detail.threadID
            : base.threadID
        let sizeEstimate = detail.sizeEstimate > 0 ? detail.sizeEstimate : base.sizeEstimate

        return EmailMessage(
            id: base.id,
            gmailMessageID: gmailMessageID,
            from: from,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            date: date,
            snippet: base.snippet,
            labels: labels,
            hasAttachment: base.hasAttachment || detail.hasAttachment,
            threadID: threadID,
            sizeEstimate: sizeEstimate
        )
    }

    private func parseAddressList(_ raw: Any?) -> String {
        guard let raw else { return "" }

        if let value = raw as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let values = raw as? [String] {
            return values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }

        if let value = raw as? [String: Any] {
            return parseAddressEntry(value)
        }

        if let values = raw as? [[String: Any]] {
            return values
                .map(parseAddressEntry)
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }

        if let values = raw as? [Any] {
            return values
                .compactMap(parseAddressEntry(from:))
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }

        return ""
    }

    private func parseAddressEntry(from raw: Any) -> String? {
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = raw as? [String: Any] {
            let parsed = parseAddressEntry(value)
            return parsed.isEmpty ? nil : parsed
        }
        return nil
    }

    private func parseAddressEntry(_ raw: [String: Any]) -> String {
        let email = (raw["email"] as? String
            ?? raw["address"] as? String
            ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (raw["name"] as? String
            ?? raw["display_name"] as? String
            ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !name.isEmpty && !email.isEmpty && name.caseInsensitiveCompare(email) != .orderedSame {
            return "\(name) <\(email)>"
        }
        if !email.isEmpty { return email }
        return name
    }
    
    private func extractNumber(from line: String) -> Int? {
        let pattern = #"[\d,]+"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range, in: line) {
            let numStr = String(line[range]).replacingOccurrences(of: ",", with: "")
            return Int(numStr)
        }
        return nil
    }
    
    private func extractValue(from line: String) -> String? {
        if let colonIndex = line.firstIndex(of: ":") {
            return String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
    
    private func extractJSONArrayString(from output: String) -> String? {
        guard let start = output.firstIndex(of: "["), let end = output.lastIndex(of: "]"), start <= end else {
            return nil
        }
        return String(output[start...end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractJSONObjectString(from output: String) -> String? {
        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(output[start...end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatDatabaseSize(_ raw: String) -> String {
        let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first, let value = Double(first) else { return raw }
        
        let unit = parts.count > 1 ? String(parts[1]) : ""
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        
        if value < 10 {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        } else if value < 100 {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        } else {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        }
        
        let formattedNumber = formatter.string(from: NSNumber(value: value)) ?? raw
        return unit.isEmpty ? formattedNumber : "\(formattedNumber) \(unit)"
    }

    private func isUnreadMessage(_ message: EmailMessage) -> Bool {
        message.labels.contains { label in
            label.localizedCaseInsensitiveContains("unread")
        }
    }

    private func parseMessageDate(_ value: String) -> Date? {
        if let date = Self.isoDateFormatterFractional.date(from: value) { return date }
        if let date = Self.isoDateFormatter.date(from: value) { return date }
        if let date = Self.fallbackDateFormatter.date(from: value) { return date }
        return nil
    }

    private func chainKey(for message: EmailMessage) -> String {
        if let thread = message.threadID?.trimmingCharacters(in: .whitespacesAndNewlines), !thread.isEmpty {
            return "thread:\(thread)"
        }
        var normalized = message.subject.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasPrefix("re:") || normalized.hasPrefix("fw:") || normalized.hasPrefix("fwd:") {
            if let separator = normalized.firstIndex(of: ":") {
                normalized = normalized[normalized.index(after: separator)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                break
            }
        }
        return normalized.isEmpty ? "msg:\(message.id)" : "subject:\(normalized)"
    }

    private func normalizedSenderFilterValue(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let start = trimmed.firstIndex(of: "<"),
           let end = trimmed[start...].firstIndex(of: ">"),
           start < end {
            let extracted = String(trimmed[trimmed.index(after: start)..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if extracted.contains("@") {
                return extracted
            }
        }

        if trimmed.contains("@") {
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ",;()[]<>\"' "))
        }
        return trimmed
    }
    
    private func fallbackQueryForSpecialCharacters(query: String, error: Error) -> String? {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        guard message.lowercased().contains("fts5: syntax error") else { return nil }
        
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let emailToken = tokens.first { $0.contains("@") }?.trimmingCharacters(in: CharacterSet(charactersIn: ",;()[]<>\"'."))
        guard let emailToken, !emailToken.isEmpty else { return nil }
        
        let keywordTokens = tokens.filter { !$0.contains("@") && !$0.hasSuffix(":") }
        if keywordTokens.isEmpty {
            return "from:\(emailToken)"
        }
        
        return "from:\(emailToken) \(keywordTokens.joined(separator: " "))"
    }
    
    private func buildSearchQueryCandidates(from query: String) -> [String] {
        let hasBareEmail = containsBareEmailToken(in: query)
        let operators = hasBareEmail ? ["from:", "to:", "cc:", "bcc:"] : ["from:"]
        
        var candidates: [String] = []
        var seen = Set<String>()
        for op in operators {
            let normalized = normalizeSearchQuery(query, defaultEmailOperator: op)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                candidates.append(normalized)
            }
        }
        return candidates
    }
    
    private func containsBareEmailToken(in query: String) -> Bool {
        let rawTokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !rawTokens.isEmpty else { return false }
        
        let operatorPrefixes = ["from:", "to:", "cc:", "bcc:", "subject:", "label:", "has:", "before:", "after:", "older_than:", "newer_than:", "larger:", "smaller:"]
        
        var i = 0
        while i < rawTokens.count {
            let token = rawTokens[i]
            
            // Handle "from: email@domain.com" style tokens.
            if token.hasSuffix(":"), i + 1 < rawTokens.count {
                let next = rawTokens[i + 1]
                if next.contains("@"), ["from:", "to:", "cc:", "bcc:"].contains(token.lowercased()) {
                    i += 2
                    continue
                }
            }
            
            if token.contains("@") {
                let tokenLower = token.lowercased()
                let hasKnownPrefix = operatorPrefixes.contains { tokenLower.hasPrefix($0) }
                if !hasKnownPrefix {
                    return true
                }
            }
            
            i += 1
        }
        
        return false
    }
    
    private func normalizeSearchQuery(_ query: String, defaultEmailOperator: String = "from:") -> String {
        let rawTokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !rawTokens.isEmpty else { return query }
        
        let operatorPrefixes = ["from:", "to:", "cc:", "bcc:", "subject:", "label:", "has:", "before:", "after:", "older_than:", "newer_than:", "larger:", "smaller:"]
        
        var normalized: [String] = []
        var i = 0
        while i < rawTokens.count {
            var token = rawTokens[i]
            
            // Handle patterns like: "from: hello@domain.com"
            if token.hasSuffix(":"), i + 1 < rawTokens.count {
                let next = rawTokens[i + 1]
                if next.contains("@"),
                   ["from:", "to:", "cc:", "bcc:"].contains(token.lowercased()) {
                    normalized.append("\(token)\(next)")
                    i += 2
                    continue
                }
            }
            
            // Bare email token without an operator causes FTS errors. Convert to sender filter.
            if token.contains("@") {
                let tokenLower = token.lowercased()
                let hasKnownPrefix = operatorPrefixes.contains { tokenLower.hasPrefix($0) }
                if !hasKnownPrefix {
                    token = token.trimmingCharacters(in: CharacterSet(charactersIn: ",;()[]<>\"'."))
                    normalized.append("\(defaultEmailOperator)\(token)")
                    i += 1
                    continue
                }
            }
            
            normalized.append(token)
            i += 1
        }
        
        return normalized.joined(separator: " ")
    }
    
    private func applyLocalFilter(_ messages: [EmailMessage], filter: SearchLocalFilter) -> [EmailMessage] {
        guard !filter.isEmpty else { return messages }
        
        return messages.filter { message in
            let senderOrRecipientMatch: Bool
            let senderOrRecipientFilter = filter.senderOrRecipientContains
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if senderOrRecipientFilter.isEmpty {
                senderOrRecipientMatch = true
            } else {
                senderOrRecipientMatch =
                    matchesContainsFilter(value: message.from, filter: senderOrRecipientFilter) ||
                    matchesContainsFilter(value: message.to, filter: senderOrRecipientFilter)
            }
            
            return matchesContainsFilter(value: message.from, filter: filter.fromContains) &&
            matchesContainsFilter(value: message.to, filter: filter.toContains) &&
            matchesContainsFilter(value: message.subject, filter: filter.subjectContains) &&
            senderOrRecipientMatch
        }
    }
    
    private func matchesContainsFilter(value: String, filter: String) -> Bool {
        let normalizedFilter = filter
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedFilter.isEmpty else { return true }
        
        let terms = normalizedFilter
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return true }
        
        let haystack = value.lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }

    private func firstMeaningfulLine(in output: String) -> String? {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    nonisolated private static func friendlyAddAccountError(raw: String, cleaned: String) -> String {
        let combined = "\(raw)\n\(cleaned)".lowercased()

        if combined.contains("address already in use") ||
            (combined.contains("listen tcp") && combined.contains("8089")) {
            return "Local OAuth callback port 8089 is already in use. Close any other add-account/auth attempts or apps using port 8089, then try again."
        }

        if combined.contains("state mismatch") {
            return "OAuth callback state mismatch. Close old localhost callback tabs, then start Add account again from the app and complete the newest Google sign-in tab only."
        }

        if combined.contains("access_denied") ||
            combined.contains("google verification process") ||
            combined.contains("developer-approved testers") ||
            (combined.contains("403") && combined.contains("access")) {
            return "Google denied sign-in (403 access_denied). Ask the admin to add this email as an OAuth test user in Google Cloud, then try Add account again."
        }

        if combined.contains("timed out") {
            return "Timed out waiting for Google sign-in. If your browser showed 403 access_denied, this email likely is not added as an OAuth test user."
        }

        return cleaned
    }
}

// MARK: - Errors

enum MsgVaultError: LocalizedError {
    case commandFailed(String)
    case commandTimedOut(seconds: Int)
    case notFound
    
    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        case .commandTimedOut(let seconds): return "Command timed out after \(seconds)s"
        case .notFound: return "msgvault binary not found"
        }
    }
}
