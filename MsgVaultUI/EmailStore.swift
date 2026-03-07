import Foundation
import SwiftUI

// MARK: - Models

struct EmailMessage: Identifiable, Hashable {
    let id: String
    let from: String
    let to: String
    let subject: String
    let date: String
    let snippet: String
    let labels: [String]
    let hasAttachment: Bool
    
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
        
        let fromEmail = json["from_email"] as? String ?? json["from"] as? String ?? json["sender"] as? String ?? "Unknown"
        let fromName = json["from_name"] as? String ?? ""
        let displayFrom = fromName.isEmpty ? fromEmail : "\(fromName) <\(fromEmail)>"
        
        let toValue: String
        if let toArray = json["to_emails"] as? [String] {
            toValue = toArray.joined(separator: ", ")
        } else {
            toValue = json["to"] as? String ?? json["recipients"] as? String ?? ""
        }
        
        let hasAttachment =
            (json["has_attachment"] as? Bool ?? false) ||
            (json["has_attachments"] as? Bool ?? false) ||
            ((json["attachment_count"] as? Int ?? 0) > 0)
        
        return EmailMessage(
            id: id,
            from: displayFrom,
            to: toValue,
            subject: json["subject"] as? String ?? "(no subject)",
            date: json["sent_at"] as? String ?? json["date"] as? String ?? json["internal_date"] as? String ?? "",
            snippet: json["snippet"] as? String ?? json["body_preview"] as? String ?? "",
            labels: json["labels"] as? [String] ?? [],
            hasAttachment: hasAttachment
        )
    }
}

struct SenderAggregate: Identifiable {
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
    @Published var senderEmailCache: [String: [EmailMessage]] = [:]
    @Published var isLoadingSenderEmails: Set<String> = []
    @Published var searchForSenderRequest: String? = nil
    @Published var isRefreshingEmail = false
    @Published var emailRefreshStatus = "Ready to refresh"
    @Published var emailRefreshError: String?
    @Published var accounts: [VaultAccount] = []
    @Published var isLoadingAccounts = false
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
    private static let defaultAIModelName = "qwen2.5:1.5b"
    
    init() {
        let defaults = UserDefaults.standard
        self.aiSearchEnabled = defaults.object(forKey: Self.aiSearchEnabledKey) as? Bool ?? false
        self.aiModelName = defaults.string(forKey: Self.aiModelNameKey) ?? Self.defaultAIModelName
        self.liveSearchEnabled = defaults.object(forKey: Self.liveSearchEnabledKey) as? Bool ?? true
        // Try to find msgvault
        findMsgvault()
        aiSearchStatus = aiSearchEnabled
            ? "AI query translation enabled (model: \(aiModelName))."
            : "AI query translation is disabled."
    }
    
    private func findMsgvault() {
        // Check common install locations
        let paths = [
            "/usr/local/bin/msgvault",
            "/opt/homebrew/bin/msgvault",
            "\(NSHomeDirectory())/.local/bin/msgvault",
            "\(NSHomeDirectory())/go/bin/msgvault"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                msgvaultPath = path
                return
            }
        }
        // Try which
        if let result = try? runCommand("/usr/bin/which", arguments: ["msgvault"]),
           !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            msgvaultPath = result.trimmingCharacters(in: .whitespacesAndNewlines)
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
        
        // Pass through environment including HOME for msgvault config
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = NSHomeDirectory()
        process.environment = env
        
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
        // Force local mode so UI still works when remote REST server is unavailable.
        try runCommand(msgvaultPath, arguments: ["--local"] + arguments)
    }
    
    private func runMsgvaultAsync(
        arguments: [String],
        timeoutSeconds: TimeInterval? = nil,
        accountEmail: String? = nil
    ) async throws -> String {
        let path = msgvaultPath
        var args = ["--local"]
        if let accountEmail, !accountEmail.isEmpty {
            args += ["--account", accountEmail]
        }
        args += arguments
        return try await Self.executeCommand(path: path, arguments: args, timeoutSeconds: timeoutSeconds)
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
            
            var env = ProcessInfo.processInfo.environment
            env["HOME"] = NSHomeDirectory()
            process.environment = env
            
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
        aiSearchStatus = enabled
            ? "AI query translation enabled (model: \(aiModelName))."
            : "AI query translation is disabled."
    }
    
    func setAIModelName(_ modelName: String) {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        aiModelName = trimmed
        if aiSearchEnabled {
            aiSearchStatus = "AI query translation enabled (model: \(aiModelName))."
        }
    }
    
    func translateNaturalLanguageSearch(_ request: String) async -> AISearchTranslation? {
        let prompt = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard aiSearchEnabled, !prompt.isEmpty else { return nil }
        
        guard let ollamaPath = findOllamaBinaryPath() else {
            aiSearchStatus = "AI search is enabled but Ollama was not found. Install Ollama to use local query translation."
            return nil
        }
        
        do {
            let today = Self.translationDateFormatter.string(from: Date())
            let translatorPrompt = """
            You convert natural-language email search requests into strict JSON.
            Today's date: \(today).
            Use only these keys:
            {
              "keywords": string|null,
              "from": string|null,
              "to": string|null,
              "cc": string|null,
              "bcc": string|null,
              "subject": string|null,
              "label": string|null,
              "after": string|null,
              "before": string|null,
              "newer_than": string|null,
              "older_than": string|null,
              "larger": string|null,
              "smaller": string|null,
              "has_attachment": boolean
            }
            Rules:
            - Output valid JSON only.
            - Use null for unknown fields.
            - Dates must be YYYY-MM-DD.
            - newer_than/older_than must use d,w,m,y suffixes like 7d.
            
            Request: \(prompt)
            """
            let output = try await Self.executeCommand(
                path: ollamaPath,
                arguments: ["run", aiModelName, translatorPrompt],
                timeoutSeconds: 25
            )
            guard let payload = parseTranslationPayload(from: output) else {
                aiSearchStatus = "AI model ran, but output was not valid structured JSON."
                return nil
            }
            
            let translatedQuery = buildTranslatedQuery(from: payload)
            guard !translatedQuery.isEmpty else {
                aiSearchStatus = "AI translation returned no usable filters."
                return nil
            }
            
            aiSearchStatus = "AI query translation active (\(aiModelName))."
            return AISearchTranslation(query: translatedQuery, rawJSON: payload.rawJSON)
        } catch {
            let message = Self.cleanErrorMessage(error.localizedDescription)
            aiSearchStatus = "AI query translation failed: \(message)"
            return nil
        }
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
        let paths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "\(NSHomeDirectory())/.local/bin/ollama"
        ]
        for path in paths where FileManager.default.fileExists(atPath: path) {
            return path
        }
        if let resolved = try? runCommand("/usr/bin/which", arguments: ["ollama"]) {
            let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
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
        
        appendToken(from: json, key: "from", prefix: "from:", into: &parts)
        appendToken(from: json, key: "to", prefix: "to:", into: &parts)
        appendToken(from: json, key: "cc", prefix: "cc:", into: &parts)
        appendToken(from: json, key: "bcc", prefix: "bcc:", into: &parts)
        appendToken(from: json, key: "subject", prefix: "subject:", into: &parts)
        appendToken(from: json, key: "label", prefix: "label:", into: &parts)
        appendToken(from: json, key: "after", prefix: "after:", into: &parts)
        appendToken(from: json, key: "before", prefix: "before:", into: &parts)
        appendToken(from: json, key: "newer_than", prefix: "newer_than:", into: &parts)
        appendToken(from: json, key: "older_than", prefix: "older_than:", into: &parts)
        appendToken(from: json, key: "larger", prefix: "larger:", into: &parts)
        appendToken(from: json, key: "smaller", prefix: "smaller:", into: &parts)
        
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
        localFilter: SearchLocalFilter = SearchLocalFilter(),
        accountEmail: String? = nil
    ) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        let queryCandidates = buildSearchQueryCandidates(from: query)
        
        isLoading = true
        errorMessage = nil
        
        var mergedMessages: [EmailMessage] = []
        var seenMessageIDs = Set<String>()
        var lastError: Error?
        
        for candidate in queryCandidates {
            do {
                let output = try await runMsgvaultAsync(
                    arguments: ["search", candidate, "--json", "-n", "100"],
                    accountEmail: accountEmail
                )
                let messages = parseSearchResults(output)
                for message in messages where seenMessageIDs.insert(message.id).inserted {
                    mergedMessages.append(message)
                }
            } catch {
                if let fallbackQuery = fallbackQueryForSpecialCharacters(query: candidate, error: error) {
                    do {
                        let output = try await runMsgvaultAsync(
                            arguments: ["search", fallbackQuery, "--json", "-n", "100"],
                            accountEmail: accountEmail
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
            searchResults = applyLocalFilter(mergedMessages, filter: localFilter)
            errorMessage = nil
        }
        
        isLoading = false
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
        } catch {
            errorMessage = "Failed to load senders: \(error.localizedDescription)"
        }
        isLoading = false
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
    
    // MARK: - Message Detail
    
    func loadMessageDetail(id: String) async {
        messageDetail = ""
        messageDetailHTML = nil
        
        do {
            let output = try await runMsgvaultAsync(arguments: ["show-message", id, "--json"])
            if let detail = parseMessageDetail(output) {
                messageDetail = detail.bodyText
                messageDetailHTML = detail.bodyHTML
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
                from: extractField(from: trimmed, field: "From:") ?? "",
                to: extractField(from: trimmed, field: "To:") ?? "",
                subject: extractField(from: trimmed, field: "Subject:") ?? trimmed,
                date: extractDatePrefix(from: trimmed) ?? "",
                snippet: trimmed,
                labels: [],
                hasAttachment: false
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
    }
    
    private func parseMessageDetail(_ output: String) -> MessageDetailPayload? {
        let cleanedOutput = extractJSONObjectString(from: output) ?? output
        guard let data = cleanedOutput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        let bodyText = (json["body_text"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawHTML = (json["body_html"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let bodyHTML = (rawHTML?.isEmpty == false) ? rawHTML : nil
        
        // When text is absent, keep a lightweight placeholder so the UI doesn't look empty.
        let effectiveText = bodyText.isEmpty
            ? (bodyHTML == nil ? "No message body available." : "")
            : bodyText
        
        return MessageDetailPayload(bodyText: effectiveText, bodyHTML: bodyHTML)
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
        case .commandTimedOut(let seconds): return "Timed out waiting for OAuth after \(seconds)s"
        case .notFound: return "msgvault binary not found"
        }
    }
}
