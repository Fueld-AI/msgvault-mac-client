import SwiftUI
import WebKit

// MARK: - Label formatting helper
/// Converts Gmail-style label keys to readable sentence case.
/// "CATEGORY_UPDATES" → "Category updates", "INBOX" → "Inbox"
func formatLabel(_ key: String) -> String {
    let spaced = key.replacingOccurrences(of: "_", with: " ")
    guard let first = spaced.first else { return spaced }
    return first.uppercased() + spaced.dropFirst().lowercased()
}

struct ContentView: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appAccentColor) private var accentColor
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.teal.rawValue
    @State private var selectedTab: SidebarTab = .search
    
    enum SidebarTab: String, CaseIterable {
        case search = "Search"
        case senders = "Sender Search"
        case stats = "Stats"
        case accounts = "Accounts"
        case settings = "Settings"
        
        var icon: String {
            switch self {
            case .search: return "magnifyingglass"
            case .senders: return "person.2"
            case .stats: return "chart.bar"
            case .accounts: return "person.crop.circle.badge.plus"
            case .settings: return "gear"
            }
        }
    }
    
    @AppStorage("appearanceMode") private var appearanceModeRawValue = AppearanceMode.system.rawValue

    private var appTheme: AppTheme {
        AppTheme.from(rawValue: appThemeRawValue)
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode.from(rawValue: appearanceModeRawValue)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 0) {
                // Brand header
                HStack(spacing: 8) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.title2)
                        .foregroundStyle(accentColor)
                    Text("MsgVault")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 16)
                .padding(.horizontal)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SidebarTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Label(tab.rawValue, systemImage: tab.icon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            selectedTab == tab
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [accentColor.opacity(0.85), accentColor.opacity(0.65)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(Color.clear)
                        )
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                
                Spacer()
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        store.refreshEmailInBackground()
                    } label: {
                        HStack(spacing: 6) {
                            if store.isRefreshingEmail {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(store.isRefreshingEmail ? "Refreshing..." : "Refresh Email")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(accentColor)
                    .disabled(store.isRefreshingEmail)
                    .help("Sync emails from server in background")
                    
                    Text(store.emailRefreshError ?? store.emailRefreshStatus)
                        .font(.caption2)
                        .foregroundColor(store.emailRefreshError == nil ? .secondary : .red)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
            }
            .frame(width: 180)
            .background(.bar)
            
            Divider()
            
            // Main content
            switch selectedTab {
            case .search:
                SearchView()
            case .senders:
                SendersView()
            case .stats:
                StatsView()
            case .accounts:
                AccountsView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: store.searchForSenderRequest) { _, request in
            if request != nil {
                selectedTab = .search
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appearanceModeRawValue = (colorScheme == .light ? AppearanceMode.dark : AppearanceMode.light).rawValue
                } label: {
                    Image(systemName: colorScheme == .light ? "moon.fill" : "sun.max.fill")
                }
                .help(colorScheme == .light ? "Switch to Dark Mode" : "Switch to Light Mode")
            }
        }
    }
}

// MARK: - Search View

struct SearchView: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor
    @State private var selectedMessageId: String?
    
    // Structured filter fields
    @State private var searchKeywords = ""
    @State private var filterFrom = ""
    @State private var filterTo = ""
    @State private var filterCC = ""
    @State private var filterBCC = ""
    @State private var filterSubject = ""
    @State private var filterAfterDate: Date?
    @State private var filterBeforeDate: Date?
    @State private var filterRelativeDate: RelativeDatePreset = .none
    @State private var filterSizePreset: SizePreset = .none
    @State private var filterHasAttachment = false
    @State private var filterLabel = ""
    @State private var selectedAccountEmail = ""
    @State private var searchScope: SearchScope = .everything
    @State private var aiAssistEnabled = true
    @State private var translatedQueryPreview: String?
    @State private var translatedQueryJSONPreview: String?
    @State private var recentQueries: [String] = Self.loadRecentQueries()
    @State private var debounceTask: Task<Void, Never>?
    @State private var isTranslatingQuery = false
    @State private var showFilters = false
    @State private var showLabelPickerPopover = false
    @State private var labelPickerSearchText = ""
    @State private var sortOption: SearchSortOption = .defaultOrder
    @State private var resultFilter = ""
    @State private var showResultFilters = false
    @State private var resultFilterTo = ""
    @State private var resultFilterCC = ""
    @State private var resultFilterBCC = ""
    @State private var resultFilterSubject = ""
    @State private var resultFilterLabel = ""
    @State private var resultFilterRelativeDate: RelativeDatePreset = .none
    @State private var resultFilterSizePreset: SizePreset = .none
    @State private var resultFilterAfterDate: Date?
    @State private var resultFilterBeforeDate: Date?
    @State private var resultFilterHasAttachment = false
    @StateObject private var speechInput = SpeechInputManager()
    
    private var hasActiveFilters: Bool {
        !filterFrom.isEmpty || !filterTo.isEmpty || !filterCC.isEmpty || !filterBCC.isEmpty || !filterSubject.isEmpty ||
        filterAfterDate != nil || filterBeforeDate != nil || filterRelativeDate != .none || filterSizePreset != .none ||
        filterHasAttachment || !filterLabel.isEmpty || !selectedAccountEmail.isEmpty
    }
    
    private var activeFilterCount: Int {
        [!filterFrom.isEmpty, !filterTo.isEmpty, !filterCC.isEmpty, !filterBCC.isEmpty, !filterSubject.isEmpty,
         filterAfterDate != nil, filterBeforeDate != nil, filterRelativeDate != .none,
         filterSizePreset != .none, filterHasAttachment, !filterLabel.isEmpty, !selectedAccountEmail.isEmpty]
            .filter { $0 }.count
    }
    
    private static let queryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    private static let isoDateFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private enum SearchSortOption: String, CaseIterable, Identifiable {
        case defaultOrder
        case dateNewest
        case dateOldest
        case senderAZ
        case senderZA
        case subjectAZ
        case subjectZA
        
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .defaultOrder: return "Default (MsgVault)"
            case .dateNewest:   return "Date: Newest first"
            case .dateOldest:   return "Date: Oldest first"
            case .senderAZ:     return "Sender: A to Z"
            case .senderZA:     return "Sender: Z to A"
            case .subjectAZ:    return "Subject: A to Z"
            case .subjectZA:    return "Subject: Z to A"
            }
        }

        var shortLabel: String {
            switch self {
            case .defaultOrder: return "Sort"
            case .dateNewest:   return "Newest"
            case .dateOldest:   return "Oldest"
            case .senderAZ:     return "Sender A–Z"
            case .senderZA:     return "Sender Z–A"
            case .subjectAZ:    return "Subject A–Z"
            case .subjectZA:    return "Subject Z–A"
            }
        }
    }
    
    private enum SearchScope: String, CaseIterable, Identifiable {
        case everything
        case subjectOnly
        case senderRecipient
        
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .everything: return "Everything"
            case .subjectOnly: return "Subject"
            case .senderRecipient: return "From/To"
            }
        }
    }
    
    private enum RelativeDatePreset: String, CaseIterable, Identifiable {
        case none
        case lastDay
        case lastWeek
        case lastMonth
        case lastThreeMonths
        case lastYear
        
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .none: return "Any time"
            case .lastDay: return "Last 24 hours"
            case .lastWeek: return "Last 7 days"
            case .lastMonth: return "Last 30 days"
            case .lastThreeMonths: return "Last 3 months"
            case .lastYear: return "Last year"
            }
        }
        
        var queryToken: String? {
            switch self {
            case .none: return nil
            case .lastDay: return "newer_than:1d"
            case .lastWeek: return "newer_than:7d"
            case .lastMonth: return "newer_than:30d"
            case .lastThreeMonths: return "newer_than:90d"
            case .lastYear: return "newer_than:365d"
            }
        }
    }
    
    private enum SizePreset: String, CaseIterable, Identifiable {
        case none
        case largerThan1MB
        case largerThan5MB
        case largerThan10MB
        case smallerThan500KB
        
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .none: return "Any size"
            case .largerThan1MB: return "Larger than 1 MB"
            case .largerThan5MB: return "Larger than 5 MB"
            case .largerThan10MB: return "Larger than 10 MB"
            case .smallerThan500KB: return "Smaller than 500 KB"
            }
        }
        
        var queryToken: String? {
            switch self {
            case .none: return nil
            case .largerThan1MB: return "larger:1M"
            case .largerThan5MB: return "larger:5M"
            case .largerThan10MB: return "larger:10M"
            case .smallerThan500KB: return "smaller:500K"
            }
        }
    }
    
    private struct SearchPlan {
        let query: String
        let localFilter: SearchLocalFilter
    }
    
    private static let recentQueriesKey = "search.recent.queries"
    private static let maxRecentQueries = 12
    
    private func queryDateString(_ date: Date) -> String {
        Self.queryDateFormatter.string(from: date)
    }
    
    private func buildQuery() -> String {
        buildSearchPlan().query
    }
    
    private func buildSearchPlan(keywordOverride: String? = nil) -> SearchPlan {
        var parts: [String] = []
        var localFilter = SearchLocalFilter()
        let accountFilter = selectedAccountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !accountFilter.isEmpty {
            // Account selection is treated as "recipient mailbox" filtering.
            parts.append(makeOperatorToken(prefix: "to:", value: accountFilter))
        }
        let fromFilter = filterFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromFilter.isEmpty {
            localFilter.fromContains = fromFilter
            if isLikelyExactEmailAddress(fromFilter) {
                parts.append(makeOperatorToken(prefix: "from:", value: fromFilter))
            } else {
                parts.append(makeKeywordToken(fromFilter))
            }
        }
        
        let toFilter = filterTo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !toFilter.isEmpty {
            localFilter.toContains = toFilter
            if isLikelyExactEmailAddress(toFilter) {
                parts.append(makeOperatorToken(prefix: "to:", value: toFilter))
            } else {
                parts.append(makeKeywordToken(toFilter))
            }
        }
        
        let ccFilter = filterCC.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ccFilter.isEmpty {
            if isLikelyExactEmailAddress(ccFilter) {
                parts.append(makeOperatorToken(prefix: "cc:", value: ccFilter))
            } else {
                parts.append(makeKeywordToken(ccFilter))
            }
        }
        
        let bccFilter = filterBCC.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bccFilter.isEmpty {
            if isLikelyExactEmailAddress(bccFilter) {
                parts.append(makeOperatorToken(prefix: "bcc:", value: bccFilter))
            } else {
                parts.append(makeKeywordToken(bccFilter))
            }
        }
        
        let subjectFilter = filterSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subjectFilter.isEmpty {
            localFilter.subjectContains = subjectFilter
            parts.append(makeOperatorToken(prefix: "subject:", value: subjectFilter))
        }
        
        if let filterAfterDate { parts.append("after:\(queryDateString(filterAfterDate))") }
        if let filterBeforeDate { parts.append("before:\(queryDateString(filterBeforeDate))") }
        if filterAfterDate == nil, filterBeforeDate == nil, let relativeToken = filterRelativeDate.queryToken {
            parts.append(relativeToken)
        }
        if let sizeToken = filterSizePreset.queryToken {
            parts.append(sizeToken)
        }
        if filterHasAttachment { parts.append("has:attachment") }
        
        let labelFilter = filterLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !labelFilter.isEmpty {
            parts.append(makeOperatorToken(prefix: "label:", value: labelFilter))
        }
        
        let keywordFilter = (keywordOverride ?? searchKeywords).trimmingCharacters(in: .whitespacesAndNewlines)
        if !keywordFilter.isEmpty {
            switch searchScope {
            case .everything:
                parts.append(keywordFilter)
            case .subjectOnly:
                parts.append(makeOperatorToken(prefix: "subject:", value: keywordFilter))
            case .senderRecipient:
                parts.append(makeKeywordToken(keywordFilter))
                localFilter.senderOrRecipientContains = keywordFilter
            }
        }
        
        return SearchPlan(
            query: parts.joined(separator: " "),
            localFilter: localFilter
        )
    }
    
    private func performSearch() {
        debounceTask?.cancel()
        Task { await runSearch(userInitiated: true) }
    }

    private func consumePendingSenderSearchRequestIfNeeded() {
        guard let req = store.searchForSenderRequest else { return }
        store.searchForSenderRequest = nil
        clearAll()
        filterFrom = req.senderEmail
        let kw = req.additionalKeywords.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kw.isEmpty { searchKeywords = kw }
        showFilters = true
        performSearch()
    }
    
    private var isAISearchActive: Bool {
        aiAssistEnabled && store.aiModelReady
    }
    
    private func scheduleDebouncedSearch() {
        // AI mode is intentional/confirm-first: do not auto-run while typing.
        // Users explicitly submit with Enter or the Search button.
        guard store.liveSearchEnabled, !isAISearchActive else { return }
        let plan = buildSearchPlan()
        guard !plan.query.isEmpty else { return }
        
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await runSearch(userInitiated: false)
        }
    }
    
    private func runSearch(userInitiated: Bool) async {
        var plan = buildSearchPlan()
        guard !plan.query.isEmpty else { return }

        translatedQueryPreview = nil
        translatedQueryJSONPreview = nil
        store.aiTranslationMessage = nil
        
        if shouldUseAITranslation {
            isTranslatingQuery = true
            if let translated = await store.translateNaturalLanguageSearch(searchKeywords) {
                translatedQueryPreview = translated.query
                translatedQueryJSONPreview = translated.rawJSON
                plan = SearchPlan(
                    query: translated.query,
                    localFilter: SearchLocalFilter()
                )
            } else {
                // AI translation failed or returned empty — do NOT fall through to raw keyword
                // search since that gives misleading unrelated results. Surface the error.
                isTranslatingQuery = false
                return
            }
            isTranslatingQuery = false
        }

        await store.search(query: plan.query, localFilter: plan.localFilter)
        if userInitiated {
            recordRecentQuery(searchKeywords.isEmpty ? plan.query : searchKeywords)
        }
    }
    
    private var shouldUseAITranslation: Bool {
        guard isAISearchActive else { return false }
        guard searchScope == .everything else { return false }
        
        let keywords = searchKeywords.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keywords.isEmpty else { return false }
        
        // Skip translation if the user already typed explicit query operators.
        if keywords.contains(":") { return false }
        
        // Translation is most reliable when no structured controls are active.
        let hasStructuredFilters =
            !filterFrom.isEmpty || !filterTo.isEmpty || !filterCC.isEmpty || !filterBCC.isEmpty ||
            !filterSubject.isEmpty || !filterLabel.isEmpty || filterAfterDate != nil || filterBeforeDate != nil ||
            filterRelativeDate != .none || filterSizePreset != .none || filterHasAttachment
        return !hasStructuredFilters
    }
    
    private func clearAll() {
        debounceTask?.cancel()
        speechInput.stopListening()
        searchKeywords = ""
        filterFrom = ""
        filterTo = ""
        filterCC = ""
        filterBCC = ""
        filterSubject = ""
        filterAfterDate = nil
        filterBeforeDate = nil
        filterRelativeDate = .none
        filterSizePreset = .none
        filterHasAttachment = false
        filterLabel = ""
        selectedAccountEmail = ""
        translatedQueryPreview = nil
        translatedQueryJSONPreview = nil
        resultFilter = ""
        resultFilterTo = ""
        resultFilterCC = ""
        resultFilterBCC = ""
        resultFilterSubject = ""
        resultFilterLabel = ""
        resultFilterRelativeDate = .none
        resultFilterSizePreset = .none
        resultFilterAfterDate = nil
        resultFilterBeforeDate = nil
        resultFilterHasAttachment = false
        showResultFilters = false
        store.searchResults = []
        store.errorMessage = nil
    }
    
    private static let resultFilterDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let resultFilterIsoFull = ISO8601DateFormatter()
    private static let resultFilterIsoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func resultFilterMessageDate(_ raw: String) -> Date {
        if let d = Self.resultFilterIsoFrac.date(from: raw) { return d }
        if let d = Self.resultFilterIsoFull.date(from: raw) { return d }
        if let d = Self.resultFilterDateFormatter.date(from: raw) { return d }
        return .distantPast
    }

    private var displayedResults: [EmailMessage] {
        var results = sortMessages(store.searchResults, option: sortOption)

        let term = resultFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            let terms = term.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            results = results.filter { msg in
                let haystack = "\(msg.from) \(msg.to) \(msg.subject) \(msg.snippet) \(msg.labels.joined(separator: " "))".lowercased()
                return terms.allSatisfy { haystack.contains($0) }
            }
        }

        let to = resultFilterTo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !to.isEmpty { results = results.filter { $0.to.lowercased().contains(to) } }

        let cc = resultFilterCC.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !cc.isEmpty { results = results.filter { $0.cc.lowercased().contains(cc) } }

        let bcc = resultFilterBCC.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !bcc.isEmpty { results = results.filter { $0.bcc.lowercased().contains(bcc) } }

        let subj = resultFilterSubject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !subj.isEmpty { results = results.filter { $0.subject.lowercased().contains(subj) } }

        let lbl = resultFilterLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !lbl.isEmpty { results = results.filter { $0.labels.contains { $0.lowercased() == lbl } } }

        if let token = resultFilterRelativeDate.queryToken {
            // e.g. "newer_than:7d" → compute cutoff date
            let parts = token.replacingOccurrences(of: "newer_than:", with: "").lowercased()
            let num = Int(parts.dropLast()) ?? 0
            let unit = parts.last ?? "d"
            var comps = DateComponents()
            switch unit {
            case "d": comps.day   = -num
            case "w": comps.day   = -num * 7
            case "m": comps.month = -num
            case "y": comps.year  = -num
            default: break
            }
            if let cutoff = Calendar.current.date(byAdding: comps, to: Date()) {
                results = results.filter { resultFilterMessageDate($0.date) >= cutoff }
            }
        }

        if let token = resultFilterSizePreset.queryToken {
            // Parse larger:/smaller: token against sizeEstimate
            let isLarger = token.hasPrefix("larger:")
            let valueStr = token.replacingOccurrences(of: "larger:", with: "").replacingOccurrences(of: "smaller:", with: "").uppercased()
            let multiplier: Int = valueStr.hasSuffix("M") ? 1_000_000 : 1_000
            if let num = Int(valueStr.dropLast()) {
                let bytes = num * multiplier
                results = results.filter { isLarger ? $0.sizeEstimate >= bytes : $0.sizeEstimate <= bytes }
            }
        }

        if let after = resultFilterAfterDate {
            results = results.filter { resultFilterMessageDate($0.date) >= after }
        }
        if let before = resultFilterBeforeDate {
            results = results.filter { resultFilterMessageDate($0.date) <= before }
        }
        if resultFilterHasAttachment {
            results = results.filter { $0.hasAttachment }
        }

        return results
    }

    private var resultFilterIsActive: Bool {
        !resultFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        resultFilterAdvancedActive
    }

    private var resultFilterAdvancedActive: Bool {
        !resultFilterTo.isEmpty || !resultFilterCC.isEmpty || !resultFilterBCC.isEmpty ||
        !resultFilterSubject.isEmpty || !resultFilterLabel.isEmpty ||
        resultFilterRelativeDate != .none || resultFilterSizePreset != .none ||
        resultFilterAfterDate != nil || resultFilterBeforeDate != nil ||
        resultFilterHasAttachment
    }

    /// Labels derived from the current search result set, sorted by frequency.
    /// Used to populate the label picker with only labels present in results.
    private var labelsFromResults: [LabelInfo] {
        var counts: [String: Int] = [:]
        for msg in store.searchResults {
            for label in msg.labels {
                counts[label, default: 0] += 1
            }
        }
        return counts
            .map { LabelInfo(key: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    private static func loadRecentQueries() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentQueriesKey) ?? []
    }
    
    private func recordRecentQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var updated = recentQueries.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        if updated.count > Self.maxRecentQueries {
            updated = Array(updated.prefix(Self.maxRecentQueries))
        }
        recentQueries = updated
        UserDefaults.standard.set(updated, forKey: Self.recentQueriesKey)
    }
    
    private func clearRecentQueries() {
        recentQueries = []
        UserDefaults.standard.removeObject(forKey: Self.recentQueriesKey)
    }
    
    private func clearStructuredFilters() {
        filterFrom = ""
        filterTo = ""
        filterCC = ""
        filterBCC = ""
        filterSubject = ""
        filterAfterDate = nil
        filterBeforeDate = nil
        filterRelativeDate = .none
        filterSizePreset = .none
        filterHasAttachment = false
        filterLabel = ""
        selectedAccountEmail = ""
    }
    
    private func makeOperatorToken(prefix: String, value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.contains(where: \.isWhitespace) else {
            return "\(prefix)\(cleaned)"
        }
        let escaped = cleaned.replacingOccurrences(of: "\"", with: "\\\"")
        return "\(prefix)\"\(escaped)\""
    }
    
    private func makeKeywordToken(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.contains(where: \.isWhitespace) else { return cleaned }
        let escaped = cleaned.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
    
    private func isLikelyExactEmailAddress(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        guard !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        return parts[1].contains(".")
    }
    
    private func sortMessages(_ messages: [EmailMessage], option: SearchSortOption) -> [EmailMessage] {
        switch option {
        case .defaultOrder:
            return messages
        case .dateNewest:
            return messages.sorted { sortableDate($0.date) > sortableDate($1.date) }
        case .dateOldest:
            return messages.sorted { sortableDate($0.date) < sortableDate($1.date) }
        case .senderAZ:
            return messages.sorted {
                let comparison = $0.from.localizedCaseInsensitiveCompare($1.from)
                if comparison == .orderedSame { return sortableDate($0.date) > sortableDate($1.date) }
                return comparison == .orderedAscending
            }
        case .senderZA:
            return messages.sorted {
                let comparison = $0.from.localizedCaseInsensitiveCompare($1.from)
                if comparison == .orderedSame { return sortableDate($0.date) > sortableDate($1.date) }
                return comparison == .orderedDescending
            }
        case .subjectAZ:
            return messages.sorted {
                let comparison = $0.subject.localizedCaseInsensitiveCompare($1.subject)
                if comparison == .orderedSame { return sortableDate($0.date) > sortableDate($1.date) }
                return comparison == .orderedAscending
            }
        case .subjectZA:
            return messages.sorted {
                let comparison = $0.subject.localizedCaseInsensitiveCompare($1.subject)
                if comparison == .orderedSame { return sortableDate($0.date) > sortableDate($1.date) }
                return comparison == .orderedDescending
            }
        }
    }
    
    private func sortableDate(_ value: String) -> Date {
        if let parsed = Self.isoDateFormatterFractional.date(from: value) {
            return parsed
        }
        if let parsed = Self.isoDateFormatter.date(from: value) {
            return parsed
        }
        if let parsed = Self.queryDateFormatter.date(from: value) {
            return parsed
        }
        return .distantPast
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main search bar
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    // Scope label + pill buttons
                    Text("Scope")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 2) {
                        ForEach(SearchScope.allCases) { scope in
                            Button {
                                searchScope = scope
                            } label: {
                                Text(scope.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(searchScope == scope ? .white : .primary)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(searchScope == scope
                                                  ? LinearGradient(colors: [accentColor.opacity(0.9), accentColor.opacity(0.75)],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                                  : LinearGradient(colors: [Color.clear, Color.clear],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Search in \(scope.label)")
                        }
                    }
                    .padding(3)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .help("Limit the top search bar to specific fields")
                    
                    if !store.accounts.isEmpty {
                        Menu {
                            Button("All accounts") {
                                selectedAccountEmail = ""
                            }
                            Divider()
                            ForEach(store.accounts) { account in
                                Button(account.email) {
                                    selectedAccountEmail = account.email
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedAccountEmail.isEmpty ? "Account: All" : selectedAccountEmail)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundStyle(selectedAccountEmail.isEmpty ? .primary : accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(selectedAccountEmail.isEmpty
                                          ? Color(NSColor.controlBackgroundColor)
                                          : accentColor.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(selectedAccountEmail.isEmpty
                                                  ? Color.primary.opacity(0.08)
                                                  : accentColor.opacity(0.30), lineWidth: 1)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Search all accounts or one selected account")
                    }

                    // Label picker button
                    Button {
                        if store.availableLabels.isEmpty {
                            Task { await store.fetchLabels() }
                        }
                        showLabelPickerPopover.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text(filterLabel.isEmpty ? "Label" : filterLabel)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: showLabelPickerPopover ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle((filterLabel.isEmpty && !showLabelPickerPopover) ? .primary : accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill((filterLabel.isEmpty && !showLabelPickerPopover)
                                      ? Color(NSColor.controlBackgroundColor)
                                      : accentColor.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder((filterLabel.isEmpty && !showLabelPickerPopover)
                                              ? Color.primary.opacity(0.08)
                                              : accentColor.opacity(0.30), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showLabelPickerPopover, arrowEdge: .bottom) {
                        LabelPickerPopoverContent(
                            selectedLabel: $filterLabel,
                            searchText: $labelPickerSearchText,
                            onSelect: { _ in
                                labelPickerSearchText = ""
                                showLabelPickerPopover = false
                                performSearch()
                            }
                        )
                    }
                    .help("Filter by Gmail label")

                    if !filterLabel.isEmpty {
                        Button {
                            filterLabel = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear label filter")
                    }

                    Spacer()

                    // AI toggle
                    let aiActive = aiAssistEnabled && store.aiModelReady
                    Button {
                        if store.aiModelReady {
                            aiAssistEnabled.toggle()
                        }
                    } label: {
                        Label("AI", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(aiActive ? .white : store.aiModelReady ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(aiActive
                                          ? LinearGradient(
                                              colors: [Color.purple.opacity(0.85), Color.indigo.opacity(0.75)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
                                          : LinearGradient(
                                              colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        aiActive ? Color.purple.opacity(0.50) : Color.primary.opacity(0.08),
                                        lineWidth: aiActive ? 1.5 : 1
                                    )
                            )
                            .shadow(
                                color: aiActive ? Color.purple.opacity(0.45) : .clear,
                                radius: 6, x: 0, y: 0
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.aiModelReady)
                    .help(
                        store.aiModelReady
                            ? (aiActive ? "AI search is ON — queries are translated to operators" : "Enable AI-powered natural language search")
                            : "No AI model ready. Go to Settings → AI Setup to install a model."
                    )

                    // Recent searches menu
                    Menu {
                        if recentQueries.isEmpty {
                            Text("No recent searches")
                        } else {
                            ForEach(recentQueries, id: \.self) { query in
                                Button(query) {
                                    searchKeywords = query
                                    performSearch()
                                }
                            }
                            Divider()
                            Button("Clear Recent Searches", role: .destructive) {
                                clearRecentQueries()
                            }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Open recent searches")

                    // Filters button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFilters.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .medium))
                            if activeFilterCount > 0 {
                                Text("\(activeFilterCount)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.white.opacity(0.25))
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundStyle(showFilters || hasActiveFilters ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(showFilters || hasActiveFilters
                                      ? LinearGradient(colors: [accentColor.opacity(0.9), accentColor.opacity(0.75)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                                      : LinearGradient(colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(showFilters || hasActiveFilters
                                              ? accentColor.opacity(0.30)
                                              : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Toggle advanced filters")

                    // Search button
                    Button("Search") { performSearch() }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(LinearGradient(colors: [accentColor.opacity(0.95), accentColor.opacity(0.80)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .keyboardShortcut(.return, modifiers: [])
                        .help("Run search")
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(searchKeywords.isEmpty ? Color.secondary : accentColor)
                        
                        TextField("Search your emails...", text: $searchKeywords)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .onSubmit { performSearch() }
                        
                        if !isAISearchActive {
                            Button {
                                store.liveSearchEnabled.toggle()
                            } label: {
                                Label("Live", systemImage: "bolt.horizontal.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(store.liveSearchEnabled ? .white : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(
                                                store.liveSearchEnabled
                                                    ? LinearGradient(
                                                        colors: [accentColor.opacity(0.9), accentColor.opacity(0.75)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                    : LinearGradient(
                                                        colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                            )
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(
                                                store.liveSearchEnabled
                                                    ? accentColor.opacity(0.35)
                                                    : Color.primary.opacity(0.12),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Automatically run search as you type")
                        }
                        
                        Button {
                            speechInput.toggleListening { transcript in
                                searchKeywords = transcript
                                scheduleDebouncedSearch()
                            }
                        } label: {
                            Image(systemName: speechInput.isListening ? "waveform.circle.fill" : "mic.circle")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(speechInput.isListening ? accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(speechInput.isListening ? "Stop voice input" : "Start voice input")
                        
                        if !searchKeywords.isEmpty {
                            Button { searchKeywords = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear search text")
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isAISearchActive
                                  ? Color.purple.opacity(0.04)
                                  : Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isAISearchActive
                                    ? Color.purple.opacity(0.55)
                                    : (searchKeywords.isEmpty ? Color.primary.opacity(0.12) : accentColor.opacity(0.50)),
                                lineWidth: isAISearchActive ? 1.5 : 1
                            )
                    )
                    .shadow(
                        color: isAISearchActive
                            ? Color.purple.opacity(0.22)
                            : .black.opacity(0.06),
                        radius: isAISearchActive ? 10 : 8,
                        x: 0, y: 3
                    )
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                
                if isTranslatingQuery || translatedQueryPreview != nil || store.aiTranslationMessage != nil || speechInput.errorMessage != nil {
                    HStack(spacing: 8) {
                        if isTranslatingQuery {
                            ProgressView().controlSize(.small)
                            Text("AI translating…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let translatedQueryPreview {
                            Image(systemName: "sparkles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.purple)
                            Text(translatedQueryPreview)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        } else if let aiMsg = store.aiTranslationMessage {
                            Image(systemName: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text(aiMsg)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        } else if let speechError = speechInput.errorMessage {
                            Label(speechError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                
                // Expandable filter panel
                if showFilters {
                    VStack(spacing: 12) {
                        Divider().opacity(0.5)
                        
                        HStack(spacing: 12) {
                            FilterField(label: "From", placeholder: "sender@example.com", text: $filterFrom, icon: "person")
                            FilterField(label: "To", placeholder: "recipient@example.com", text: $filterTo, icon: "person.2")
                        }
                        
                        HStack(spacing: 12) {
                            FilterField(label: "CC", placeholder: "team@example.com", text: $filterCC, icon: "person.3")
                            FilterField(label: "BCC", placeholder: "archive@example.com", text: $filterBCC, icon: "person.crop.circle.badge.checkmark")
                        }
                        
                        HStack(spacing: 12) {
                            FilterField(label: "Subject", placeholder: "meeting notes", text: $filterSubject, icon: "text.alignleft")
                            FilterFieldLabelPicker(
                                selectedLabel: $filterLabel,
                                onSelect: { scheduleDebouncedSearch() },
                                resultLabels: store.searchResults.isEmpty ? nil : labelsFromResults
                            )
                        }
                        
                        HStack(spacing: 12) {
                            Picker("Quick Date", selection: $filterRelativeDate) {
                                ForEach(RelativeDatePreset.allCases) { preset in
                                    Text(preset.label).tag(preset)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Picker("Size", selection: $filterSizePreset) {
                                ForEach(SizePreset.allCases) { preset in
                                    Text(preset.label).tag(preset)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        Text("From/To/CC/BCC/Subject support partial matching. Date presets map to newer_than operators.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        CompactDateAttachmentBar(
                            afterDate: $filterAfterDate,
                            beforeDate: $filterBeforeDate,
                            hasAttachment: $filterHasAttachment
                        )
                        
                        if hasActiveFilters {
                            HStack {
                                activeFilterChips
                                Spacer()
                                Button("Clear filters") {
                                    clearStructuredFilters()
                                }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(accentColor)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(.bar)
            
            Divider()
            
            // Results + Detail side by side
            HStack(spacing: 0) {
                // Message list
                VStack(spacing: 0) {
                    if store.isLoading || isTranslatingQuery {
                        Spacer()
                        if isTranslatingQuery {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("Translating with AI…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Pass 1: understanding your request")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            ProgressView("Searching...")
                                .frame(maxWidth: .infinity)
                        }
                        Spacer()
                    } else if displayedResults.isEmpty {
                        Spacer()
                        if let aiMsg = store.aiTranslationMessage {
                            VStack(spacing: 14) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.purple.opacity(0.7))
                                Text("AI search couldn't translate that")
                                    .font(.headline)
                                Text(aiMsg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 300)
                                Text("Try rephrasing, or use the filter panel for structured searches.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 260)
                            }
                        } else if let error = store.errorMessage {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.orange)
                                Text("Search Error")
                                    .font(.headline)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 300)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "envelope.open")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.tertiary)
                                Text(buildQuery().isEmpty ? "Search your email archive" : "No results found")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                if buildQuery().isEmpty {
                                    Text(shouldUseAITranslation
                                         ? "Describe what you're looking for in plain English, then press Enter."
                                         : "Type keywords above, or use filters to narrow results by sender, subject, date, and more.")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: 280)
                                }
                            }
                        }
                        Spacer()
                    } else {
                        // ── Secondary in-results filter bar ──────────────────
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(resultFilterIsActive ? accentColor : .secondary)
                                TextField("Filter these results…", text: $resultFilter)
                                    .textFieldStyle(.plain)
                                    .font(.callout)
                                if resultFilterIsActive {
                                    Button {
                                        resultFilter = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                // Advanced filter toggle
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        showResultFilters.toggle()
                                    }
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: showResultFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle((showResultFilters || resultFilterAdvancedActive) ? accentColor : .secondary)
                                        if resultFilterAdvancedActive {
                                            Circle()
                                                .fill(accentColor)
                                                .frame(width: 6, height: 6)
                                                .offset(x: 4, y: -4)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .help("Advanced result filters — CC, BCC, Label")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)

                            // Advanced filter panel — mirrors Sender Search filter panel
                            if showResultFilters {
                                VStack(spacing: 12) {
                                    Divider().opacity(0.5)

                                    HStack(spacing: 12) {
                                        FilterField(label: "To", placeholder: "recipient@example.com", text: $resultFilterTo, icon: "person.2")
                                        FilterField(label: "CC", placeholder: "team@example.com", text: $resultFilterCC, icon: "person.3")
                                    }

                                    HStack(spacing: 12) {
                                        FilterField(label: "BCC", placeholder: "archive@example.com", text: $resultFilterBCC, icon: "person.crop.circle.badge.checkmark")
                                        FilterField(label: "Subject", placeholder: "meeting notes", text: $resultFilterSubject, icon: "text.alignleft")
                                    }

                                    HStack(spacing: 12) {
                                        FilterFieldLabelPicker(
                                            selectedLabel: $resultFilterLabel,
                                            resultLabels: labelsFromResults.isEmpty ? nil : labelsFromResults
                                        )
                                        Picker("Quick Date", selection: $resultFilterRelativeDate) {
                                            ForEach(RelativeDatePreset.allCases) { preset in
                                                Text(preset.label).tag(preset)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    HStack(spacing: 12) {
                                        Picker("Size", selection: $resultFilterSizePreset) {
                                            ForEach(SizePreset.allCases) { preset in
                                                Text(preset.label).tag(preset)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Spacer()
                                    }

                                    CompactDateAttachmentBar(
                                        afterDate: $resultFilterAfterDate,
                                        beforeDate: $resultFilterBeforeDate,
                                        hasAttachment: $resultFilterHasAttachment
                                    )

                                    if resultFilterAdvancedActive {
                                        HStack {
                                            Spacer()
                                            Button("Clear filters") {
                                                resultFilterTo = ""
                                                resultFilterCC = ""
                                                resultFilterBCC = ""
                                                resultFilterSubject = ""
                                                resultFilterLabel = ""
                                                resultFilterRelativeDate = .none
                                                resultFilterSizePreset = .none
                                                resultFilterAfterDate = nil
                                                resultFilterBeforeDate = nil
                                                resultFilterHasAttachment = false
                                            }
                                            .font(.caption)
                                            .buttonStyle(.plain)
                                            .foregroundStyle(accentColor)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // Quick-access label chips from result set
                            if !labelsFromResults.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(labelsFromResults.prefix(20)) { label in
                                            let isActive = resultFilterLabel.lowercased() == label.key.lowercased()
                                            Button {
                                                resultFilterLabel = isActive ? "" : label.key
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Text(formatLabel(label.key))
                                                        .font(.system(size: 10, weight: .semibold))
                                                    Text("\(label.count)")
                                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                        .foregroundStyle(isActive ? .white.opacity(0.8) : accentColor.opacity(0.7))
                                                }
                                                .foregroundStyle(isActive ? .white : accentColor)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(Capsule().fill(isActive ? accentColor.opacity(0.85) : accentColor.opacity(0.10)))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 7)
                                }
                            }
                        }
                        .background(resultFilterIsActive ? accentColor.opacity(0.06) : Color(NSColor.controlBackgroundColor))
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(resultFilterIsActive ? accentColor.opacity(0.25) : Color.primary.opacity(0.06)),
                            alignment: .bottom
                        )

                        // Sort / count bar — only visible with results
                        HStack(spacing: 10) {
                            Group {
                                if resultFilterIsActive {
                                    Text("\(displayedResults.count) of \(store.searchResults.count)")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(accentColor)
                                } else {
                                    Text("\(displayedResults.count) message\(displayedResults.count == 1 ? "" : "s")")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Menu {
                                Picker("Sort", selection: $sortOption) {
                                    ForEach(SearchSortOption.allCases) { option in
                                        Text(option.label).tag(option)
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: sortOption == .defaultOrder ? "arrow.up.arrow.down" :
                                          (sortOption == .dateNewest || sortOption == .dateOldest) ? "calendar" :
                                          (sortOption == .senderAZ || sortOption == .senderZA) ? "person" : "text.alignleft")
                                        .font(.caption.weight(.semibold))
                                    Text(sortOption.shortLabel)
                                        .font(.caption.weight(.semibold))
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 8, weight: .semibold))
                                }
                                .foregroundStyle(sortOption == .defaultOrder ? .secondary : accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(sortOption == .defaultOrder
                                              ? Color(NSColor.controlBackgroundColor)
                                              : accentColor.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(sortOption == .defaultOrder
                                                      ? Color.primary.opacity(0.10)
                                                      : accentColor.opacity(0.30),
                                                      lineWidth: 1)
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Sort search results")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.bar)

                        Divider()

                        if displayedResults.isEmpty && resultFilterIsActive {
                            Spacer()
                            VStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.tertiary)
                                Text("No matches in these results")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Text("Try different filter words, or clear the filter to see all \(store.searchResults.count) results.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 240)
                                Button("Clear filter") { resultFilter = "" }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(accentColor)
                            }
                            Spacer()
                        } else {
                            List(displayedResults, selection: $selectedMessageId) { message in
                                MessageRowView(message: message)
                                    .tag(message.id)
                            }
                            .listStyle(.inset)
                            .onChange(of: selectedMessageId) { _, newId in
                                if let id = newId {
                                    store.selectedMessage = displayedResults.first(where: { $0.id == id })
                                    Task { await store.loadMessageDetail(id: id) }
                                }
                            }
                        }
                    }

                    // Status bar
                    HStack {
                        Spacer()
                        let displayedQuery = translatedQueryPreview ?? buildQuery()
                        if !displayedQuery.isEmpty {
                            Text(displayedQuery)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .help(translatedQueryJSONPreview ?? displayedQuery)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.bar)
                }
                .frame(minWidth: 350, idealWidth: 450, maxWidth: 500)
                
                Divider()
                
                // Detail pane
                MessageDetailView()
                    .frame(minWidth: 350, idealWidth: 500, maxWidth: .infinity)
            }
        }
        .task {
            if store.accounts.isEmpty {
                await store.loadAccounts()
            }
            consumePendingSenderSearchRequestIfNeeded()
        }
        .onChange(of: searchKeywords) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: searchScope) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: filterFrom) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: filterTo) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: filterCC) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: filterBCC) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: filterSubject) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: filterAfterDate) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: filterBeforeDate) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: filterRelativeDate) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: filterSizePreset) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: filterHasAttachment) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: filterLabel) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: selectedAccountEmail) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: store.searchForSenderRequest) { _, _ in
            consumePendingSenderSearchRequestIfNeeded()
        }
        .onDisappear {
            debounceTask?.cancel()
            speechInput.stopListening()
        }
    }
    
    @ViewBuilder
    private var activeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !filterFrom.isEmpty {
                    let prefix = isLikelyExactEmailAddress(filterFrom) ? "from:" : "from~:"
                    filterChip("\(prefix)\(filterFrom)") { filterFrom = "" }
                }
                if !filterTo.isEmpty {
                    let prefix = isLikelyExactEmailAddress(filterTo) ? "to:" : "to~:"
                    filterChip("\(prefix)\(filterTo)") { filterTo = "" }
                }
                if !filterCC.isEmpty {
                    let prefix = isLikelyExactEmailAddress(filterCC) ? "cc:" : "cc~:"
                    filterChip("\(prefix)\(filterCC)") { filterCC = "" }
                }
                if !filterBCC.isEmpty {
                    let prefix = isLikelyExactEmailAddress(filterBCC) ? "bcc:" : "bcc~:"
                    filterChip("\(prefix)\(filterBCC)") { filterBCC = "" }
                }
                if !filterSubject.isEmpty { filterChip("subject~:\(filterSubject)") { filterSubject = "" } }
                if let filterAfterDate {
                    filterChip("after:\(queryDateString(filterAfterDate))") { self.filterAfterDate = nil }
                }
                if let filterBeforeDate {
                    filterChip("before:\(queryDateString(filterBeforeDate))") { self.filterBeforeDate = nil }
                }
                if let relativeDateToken = filterRelativeDate.queryToken {
                    filterChip(relativeDateToken) { filterRelativeDate = .none }
                }
                if let sizeToken = filterSizePreset.queryToken {
                    filterChip(sizeToken) { filterSizePreset = .none }
                }
                if filterHasAttachment { filterChip("has:attachment") { filterHasAttachment = false } }
                if !filterLabel.isEmpty { filterChip("label:\(filterLabel)") { filterLabel = "" } }
                if !selectedAccountEmail.isEmpty { filterChip("account:\(selectedAccountEmail)") { selectedAccountEmail = "" } }
            }
        }
    }
    
    private func filterChip(_ text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption2.monospaced())
            Button { onRemove() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(accentColor.opacity(0.12))
        .foregroundStyle(accentColor)
        .clipShape(Capsule())
    }
}

private struct FilterField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appAccentColor) private var accentColor
    @FocusState private var isFocused: Bool

    private var isActive: Bool { !text.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(isActive ? accentColor : Color.secondary)

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? accentColor : Color.secondary)
                    .frame(width: 16)

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($isFocused)

                if isActive {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? accentColor.opacity(0.05) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isFocused ? accentColor.opacity(0.55) : (isActive ? accentColor.opacity(0.35) : Color.primary.opacity(0.12)),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.05), radius: 6, x: 0, y: 2)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DateFilterField: View {
    let label: String
    @Binding var date: Date?
    let icon: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appAccentColor) private var accentColor
    @State private var showDatePicker = false
    
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        return formatter
    }()
    
    private var fieldText: String {
        guard let date else { return "Select date" }
        return Self.displayFormatter.string(from: date)
    }
    
    private var popoverTopColor: Color {
        colorScheme == .dark
            ? Color(red: 0.04, green: 0.17, blue: 0.22)
            : Color(red: 0.93, green: 0.98, blue: 0.99)
    }
    
    private var popoverBottomColor: Color {
        colorScheme == .dark
            ? Color(red: 0.06, green: 0.13, blue: 0.23)
            : Color(red: 0.88, green: 0.96, blue: 0.98)
    }
    
    private var popoverBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }
    
    private var popoverPrimaryTextColor: Color {
        colorScheme == .dark ? .white : .primary
    }
    
    private var calendarSurfaceFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.03)
    }
    
    private var calendarSurfaceBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    
    private var todayButtonTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
    
    private var todayButtonForeground: Color {
        colorScheme == .dark ? .white : .primary
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            fieldControl
                .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                    popoverContent
                }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var fieldControl: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(date == nil ? Color.primary.opacity(0.07) : accentColor.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(date == nil ? Color.secondary : accentColor)
            }
            .frame(width: 28, height: 28)
            
            Button {
                showDatePicker = true
            } label: {
                HStack(spacing: 8) {
                    Text(fieldText)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(date == nil ? .secondary : .primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if date != nil {
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear date")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(minHeight: 48)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(date == nil ? Color(NSColor.controlBackgroundColor) : accentColor.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(date == nil ? Color.primary.opacity(0.12) : accentColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
    
    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            popoverHeader
            popoverCalendar
            popoverActions
        }
        .padding(16)
        .frame(width: 430)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [popoverTopColor, popoverBottomColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(popoverBorderColor, lineWidth: 1)
        )
    }
    
    private var popoverHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor.opacity(0.85))
                    .textCase(.uppercase)
                Text(fieldText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(popoverPrimaryTextColor)
            }
            
            Spacer()
            
            if date != nil {
                Button("Clear") {
                    date = nil
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentColor.opacity(0.90))
            }
        }
    }
    
    private var popoverCalendar: some View {
        ExpandedCalendarView(selectedDate: $date)
            .frame(maxWidth: .infinity)
            .frame(height: 346)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(calendarSurfaceFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(calendarSurfaceBorderColor, lineWidth: 1)
        )
    }
    
    private var popoverActions: some View {
        HStack {
            Spacer()
            
            Button("Done") {
                showDatePicker = false
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor.opacity(0.90))
        }
    }
}

private struct ExpandedCalendarView: View {
    @Binding var selectedDate: Date?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appAccentColor) private var accentColor
    
    @State private var displayedMonthStart: Date
    @State private var showMonthYearPicker = false
    @State private var draftMonth: Int
    @State private var draftYear: Int
    
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale.current
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }()
    
    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
    
    private static let yearFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    
    init(selectedDate: Binding<Date?>) {
        _selectedDate = selectedDate
        let calendar = ExpandedCalendarView.makeCalendar()
        let base = selectedDate.wrappedValue ?? Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: base)) ?? base
        _displayedMonthStart = State(initialValue: monthStart)
        _draftMonth = State(initialValue: calendar.component(.month, from: monthStart))
        _draftYear = State(initialValue: calendar.component(.year, from: monthStart))
    }
    
    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayHeader
            monthGrid
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }
    
    private var header: some View {
        HStack(spacing: 8) {
            monthNavigationCluster
            Spacer()
            
            Button {
                let today = calendar.startOfDay(for: Date())
                selectedDate = today
                displayedMonthStart = monthStart(for: today)
                syncDraftWithDisplayedMonth()
            } label: {
                Label("Today", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
            .controlSize(.small)
        }
    }
    
    private var monthNavigationCluster: some View {
        HStack(spacing: 8) {
            monthNavButton(systemName: "chevron.left") {
                moveMonth(by: -1)
            }
            
            Button {
                syncDraftWithDisplayedMonth()
                showMonthYearPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(displayedMonthYearTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 196)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(colorScheme == .dark ? 0.16 : 0.12))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showMonthYearPicker, arrowEdge: .bottom) {
                monthYearChooser
            }
            
            monthNavButton(systemName: "chevron.right") {
                moveMonth(by: 1)
            }
        }
    }
    
    private func monthNavButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .background(Circle().fill(accentColor.opacity(0.16)))
        .foregroundStyle(accentColor)
    }
    
    private var monthYearChooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jump to month and year")
                .font(.headline)
            
            HStack(spacing: 10) {
                Picker("Month", selection: $draftMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(monthName(for: month)).tag(month)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                
                Picker("Year", selection: $draftYear) {
                    ForEach(yearOptions, id: \.self) { year in
                        Text("\(year)").tag(year)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 118)
            }
            
            HStack {
                Button("Cancel") {
                    showMonthYearPicker = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Go") {
                    jumpToMonthYear(month: draftMonth, year: draftYear)
                    showMonthYearPicker = false
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
    
    private var weekdayHeader: some View {
        let symbols = orderedWeekdaySymbols()
        return HStack(spacing: 6) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var monthGrid: some View {
        let dates = monthGridDates()
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 24, maximum: .infinity), spacing: 6), count: 7),
            spacing: 6
        ) {
            ForEach(dates, id: \.self) { date in
                dayCell(for: date)
            }
        }
    }
    
    private func dayCell(for date: Date) -> some View {
        let isInDisplayedMonth = calendar.isDate(date, equalTo: displayedMonthStart, toGranularity: .month)
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isToday = calendar.isDateInToday(date)
        
        return Button {
            let selected = calendar.startOfDay(for: date)
            selectedDate = selected
            displayedMonthStart = monthStart(for: selected)
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 16, weight: isSelected ? .bold : .semibold))
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(dayForegroundColor(isInDisplayedMonth: isInDisplayedMonth, isSelected: isSelected))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? accentColor.opacity(colorScheme == .dark ? 0.95 : 0.88) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isToday && !isSelected ? accentColor.opacity(0.7) : Color.clear, lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
        .opacity(isInDisplayedMonth ? 1.0 : 0.42)
    }
    
    private func dayForegroundColor(isInDisplayedMonth: Bool, isSelected: Bool) -> Color {
        if isSelected { return .white }
        if isInDisplayedMonth { return colorScheme == .dark ? .white : .primary }
        return .secondary
    }
    
    private func moveMonth(by delta: Int) {
        guard let moved = calendar.date(byAdding: .month, value: delta, to: displayedMonthStart) else { return }
        displayedMonthStart = monthStart(for: moved)
        syncDraftWithDisplayedMonth()
    }
    
    private func syncDraftWithDisplayedMonth() {
        draftMonth = calendar.component(.month, from: displayedMonthStart)
        draftYear = calendar.component(.year, from: displayedMonthStart)
    }
    
    private func jumpToMonthYear(month: Int, year: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        if let jumped = calendar.date(from: components) {
            displayedMonthStart = monthStart(for: jumped)
        }
    }
    
    private func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
    
    private func monthGridDates() -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonthStart) else { return [] }
        let firstDay = monthInterval.start
        let weekday = calendar.component(.weekday, from: firstDay)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: firstDay) else { return [] }
        
        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }
    
    private func orderedWeekdaySymbols() -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let shift = max(0, calendar.firstWeekday - 1)
        let reordered = Array(symbols[shift...]) + Array(symbols[..<shift])
        return reordered.map { String($0.prefix(2)) }
    }
    
    private func monthName(for month: Int) -> String {
        let monthSymbols = calendar.monthSymbols
        guard monthSymbols.indices.contains(month - 1) else { return "\(month)" }
        return monthSymbols[month - 1]
    }
    
    private var displayedMonthYearTitle: String {
        let month = monthName(for: calendar.component(.month, from: displayedMonthStart))
        let year = formattedYear(calendar.component(.year, from: displayedMonthStart))
        return "\(month) \(year)"
    }
    
    private func formattedYear(_ year: Int) -> String {
        Self.yearFormatter.string(from: NSNumber(value: year)) ?? "\(year)"
    }
    
    private var yearOptions: [Int] {
        let currentYear = calendar.component(.year, from: Date())
        let lowerBound = max(1900, currentYear - 80)
        let upperBound = currentYear
        return Array((lowerBound...upperBound).reversed())
    }
    
    private static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale.current
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }
}

private struct DateRangeConnector: View {
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Text("to")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .padding(.top, 23)
            Spacer(minLength: 0)
        }
        .frame(width: 28)
    }
}

private struct AttachmentFilterField: View {
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appAccentColor) private var accentColor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Attachments")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOn ? accentColor : .secondary)
                .textCase(.uppercase)
            
            HStack(spacing: 10) {
                Image(systemName: "paperclip.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isOn ? accentColor : Color.secondary)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Has attachment")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Only messages with files")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: 8)
                
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isOn
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [accentColor.opacity(0.20), accentColor.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(
                            LinearGradient(
                                colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor).opacity(0.86)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isOn ? accentColor.opacity(0.40) : Color.primary.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.10), radius: 14, x: 0, y: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Label Picker Popover

/// Accent-coloured floating label picker, shared by toolbar + filter panels.
private struct LabelPickerPopoverContent: View {
    @Binding var selectedLabel: String
    @Binding var searchText: String
    var onSelect: (String) -> Void
    /// When non-nil, shows only these labels (derived from current result set).
    /// When nil, falls back to the full store.availableLabels archive list.
    var resultLabels: [LabelInfo]? = nil

    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor
    @Environment(\.colorScheme) private var colorScheme

    private let visibleRows = 10
    private let rowHeight: CGFloat = 34

    private var sourceLabels: [LabelInfo] {
        resultLabels ?? store.availableLabels
    }

    private var filteredLabels: [LabelInfo] {
        searchText.isEmpty
            ? sourceLabels
            : sourceLabels.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
    }

    private var isUsingResultScope: Bool { resultLabels != nil }

    private var listViewportHeight: CGFloat {
        CGFloat(visibleRows) * rowHeight + 8
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                TextField("", text: $searchText, prompt: Text("Filter labels…").foregroundStyle(.white.opacity(0.70)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.80))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.14))

            Divider().overlay(Color.white.opacity(0.18))

            if !isUsingResultScope && store.isLoadingLabels {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .frame(height: listViewportHeight)
            } else if filteredLabels.isEmpty {
                Text(searchText.isEmpty
                     ? (isUsingResultScope ? "No labels in these results" : "No labels found")
                     : "No match for \"\(searchText)\"")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .frame(height: listViewportHeight)
                    .multilineTextAlignment(.center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredLabels) { label in
                            Button {
                                selectedLabel = label.key
                                onSelect(label.key)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: selectedLabel == label.key ? "checkmark" : "tag")
                                        .font(.system(size: 11, weight: selectedLabel == label.key ? .bold : .regular))
                                        .foregroundStyle(.white.opacity(selectedLabel == label.key ? 1.0 : 0.68))
                                        .frame(width: 14)
                                    Text(formatLabel(label.key))
                                        .font(.system(size: 12, weight: selectedLabel == label.key ? .semibold : .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer(minLength: 12)
                                    Text(label.count.formatted())
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.88))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(0.22))
                                        .clipShape(Capsule())
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: rowHeight)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(selectedLabel == label.key ? .white.opacity(0.22) : Color.black.opacity(0.16))
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .frame(height: listViewportHeight)
            }
        }
        .frame(width: 344)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.96), accentColor.opacity(0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
    }
}

/// Drop-in replacement for FilterField that opens the label picker popover.
private struct FilterFieldLabelPicker: View {
    @Binding var selectedLabel: String
    var onSelect: (() -> Void)? = nil
    /// When provided, the picker shows only labels present in the current result set.
    var resultLabels: [LabelInfo]? = nil

    @EnvironmentObject var store: EmailStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appAccentColor) private var accentColor
    @State private var showPicker = false
    @State private var searchText = ""

    private var isActive: Bool { !selectedLabel.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Label")
                .font(.caption)
                .foregroundStyle(isActive ? accentColor : Color.secondary)

            Button {
                if store.availableLabels.isEmpty {
                    Task { await store.fetchLabels() }
                }
                showPicker.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tag")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isActive ? accentColor : Color.secondary)
                        .frame(width: 16)
                    if isActive {
                        Text(selectedLabel)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } else {
                        Text("INBOX")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    if isActive {
                        Button {
                            selectedLabel = ""
                            onSelect?()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? accentColor.opacity(0.05) : Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            showPicker ? accentColor.opacity(0.55) : (isActive ? accentColor.opacity(0.35) : Color.primary.opacity(0.12)),
                            lineWidth: showPicker ? 1.5 : 1
                        )
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.05), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                LabelPickerPopoverContent(
                    selectedLabel: $selectedLabel,
                    searchText: $searchText,
                    onSelect: { _ in
                        searchText = ""
                        showPicker = false
                        onSelect?()
                    },
                    resultLabels: resultLabels
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Compact Date + Attachment Bar

/// Compact single-row date range + attachment toggle for filter panels.
private struct CompactDateAttachmentBar: View {
    @Binding var afterDate: Date?
    @Binding var beforeDate: Date?
    @Binding var hasAttachment: Bool
    @Environment(\.appAccentColor) private var accentColor

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CompactDateChip(label: "After", date: $afterDate)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            CompactDateChip(label: "Before", date: $beforeDate)

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                Image(systemName: "paperclip")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hasAttachment ? accentColor : .secondary)
                Text("Attachment")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(hasAttachment ? .primary : .secondary)
                Toggle("", isOn: $hasAttachment)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.09), accentColor.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accentColor.opacity(0.20), lineWidth: 1)
        )
    }
}

private struct CompactDateChip: View {
    let label: String
    @Binding var date: Date?
    @Environment(\.appAccentColor) private var accentColor
    @State private var showPicker = false

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateStyle = .medium
        return f
    }()

    private static let queryFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var displayText: String {
        guard let date else { return label }
        return Self.displayFormatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button { showPicker = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(date == nil ? .secondary : accentColor)
                    Text(displayText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(date == nil ? .secondary : .primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(date == nil ? Color.primary.opacity(0.07) : accentColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            date == nil ? Color.primary.opacity(0.12) : accentColor.opacity(0.40),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                datePickerPopover
            }
            if date != nil {
                Button { date = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var datePickerPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor.opacity(0.85))
                    Text(displayText)
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                if date != nil {
                    Button("Clear") { date = nil }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor.opacity(0.90))
                }
            }
            ExpandedCalendarView(selectedDate: $date)
                .frame(maxWidth: .infinity)
                .frame(height: 346)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            HStack {
                Spacer()
                Button("Done") { showPicker = false }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
            }
        }
        .padding(16)
        .frame(width: 430)
    }
}

// MARK: - Message Row

struct MessageRowView: View {
    let message: EmailMessage
    @Environment(\.appAccentColor) private var accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.from)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(formatDate(message.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(message.subject)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            if !message.snippet.isEmpty {
                Text(message.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            HStack(spacing: 4) {
                if message.hasAttachment {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(accentColor)
                }
                ForEach(message.labels.prefix(3), id: \.self) { label in
                    Text(formatLabel(label))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.12))
                        .foregroundStyle(accentColor)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private static let isoFull = ISO8601DateFormatter()
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE, dd-MMM-yy HH:mm"  // e.g. Sat, 08-Mar-26 14:30
        return f
    }()

    private func formatDate(_ dateStr: String) -> String {
        if let d = Self.isoFrac.date(from: dateStr) { return Self.displayFormatter.string(from: d) }
        if let d = Self.isoFull.date(from: dateStr) { return Self.displayFormatter.string(from: d) }
        return dateStr
    }
}

// MARK: - Message Detail

struct MessageDetailView: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor

    private static let isoFull = ISO8601DateFormatter()
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE, dd-MMM-yy HH:mm"
        return f
    }()

    private func formatDate(_ raw: String) -> String {
        if let d = Self.isoFrac.date(from: raw) { return Self.displayFormatter.string(from: d) }
        if let d = Self.isoFull.date(from: raw) { return Self.displayFormatter.string(from: d) }
        return raw
    }

    var body: some View {
        if let message = store.selectedMessage {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    Text(message.subject)
                        .font(.title2.bold())

                    // From + Date row
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("From")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.from)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Date")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatDate(message.date))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                    }

                    // To / CC / BCC grid
                    if !message.to.isEmpty || !message.cc.isEmpty || !message.bcc.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            if !message.to.isEmpty {
                                HStack(alignment: .top, spacing: 6) {
                                    Text("To")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, alignment: .trailing)
                                    Text(message.to)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                }
                            }
                            if !message.cc.isEmpty {
                                HStack(alignment: .top, spacing: 6) {
                                    Text("CC")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, alignment: .trailing)
                                    Text(message.cc)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                }
                            }
                            if !message.bcc.isEmpty {
                                HStack(alignment: .top, spacing: 6) {
                                    Text("BCC")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, alignment: .trailing)
                                    Text(message.bcc)
                                        .font(.caption)
                                        .foregroundStyle(accentColor.opacity(0.85))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    if !message.labels.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(message.labels, id: \.self) { label in
                                    Text(formatLabel(label))
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(accentColor.opacity(0.12))
                                        .foregroundStyle(accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Body
                if let html = store.messageDetailHTML, !html.isEmpty {
                    MessageHTMLView(html: html)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                } else if !store.messageDetail.isEmpty {
                    ScrollView {
                        Text(store.messageDetail)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Select a message to view details")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MessageHTMLView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        // Always white — email HTML is authored for white surfaces.
        // Using underPageBackgroundColor avoids the flash on load.
        webView.underPageBackgroundColor = .white
        webView.loadHTMLString(wrapHTML(html), baseURL: nil)
        context.coordinator.lastRenderedHTML = html

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastRenderedHTML != html else { return }
        context.coordinator.lastRenderedHTML = html
        webView.loadHTMLString(wrapHTML(html), baseURL: nil)
    }

    // Always render on white by owning the document shell.
    // For full HTML emails we extract the <style> blocks and body content
    // so the email's element-level CSS is preserved while we control the background.
    private func wrapHTML(_ value: String) -> String {
        var emailStyles = ""
        var bodyContent = value

        if value.localizedCaseInsensitiveContains("<html") {
            // Grab any <style> blocks from the original head
            if let regex = try? NSRegularExpression(
                pattern: #"<style[^>]*>[\s\S]*?</style>"#,
                options: .caseInsensitive
            ) {
                let ns = value as NSString
                emailStyles = regex.matches(in: value, range: NSRange(location: 0, length: ns.length))
                    .map { ns.substring(with: $0.range) }
                    .joined(separator: "\n")
            }

            // Extract body inner HTML
            if let openTag  = value.range(of: "<body", options: .caseInsensitive),
               let closeAngle = value[openTag.upperBound...].range(of: ">"),
               let closeTag  = value.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
                bodyContent = String(value[closeAngle.upperBound ..< closeTag.lowerBound])
            }
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                html, body {
                    background-color: #ffffff !important;
                    margin: 0;
                    padding: 14px;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                    font-size: 14px;
                    line-height: 1.6;
                    color: #111111;
                }
                img { max-width: 100% !important; height: auto !important; }
                table { max-width: 100% !important; }
                a { color: #0077cc; }
            </style>
            \(emailStyles)
        </head>
        <body>\(bodyContent)</body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastRenderedHTML: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - Senders View

struct SendersView: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor

    @State private var hoveredSender: SenderAggregate?
    @State private var lockedSender: SenderAggregate?
    @State private var detailFilter: String = ""
    @State private var senderSearchText: String = ""

    private var detailSender: SenderAggregate? { lockedSender ?? hoveredSender }
    private var normalizedSenderQuery: String {
        senderSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var isSearchingAllSenders: Bool { !normalizedSenderQuery.isEmpty }
    private var senderSource: [SenderAggregate] {
        if isSearchingAllSenders {
            return store.allSenders.isEmpty ? store.senders : store.allSenders
        }
        return store.senders
    }
    private var filteredSenders: [SenderAggregate] {
        guard isSearchingAllSenders else { return senderSource }
        return senderSource.filter { sender in
            sender.name.lowercased().contains(normalizedSenderQuery) || sender.email.lowercased().contains(normalizedSenderQuery)
        }
    }

    private var displayedSenders: [SenderAggregate] {
        filteredSenders
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left column: sender list
            VStack(spacing: 0) {
                HStack {
                    Text("Sender Search")
                        .font(.title2.bold())
                    Spacer()
                    Button("Refresh") {
                        Task {
                            await store.loadTopSenders()
                            if isSearchingAllSenders {
                                await store.loadAllSendersIfNeeded(forceRefresh: true)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(.bar)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search senders...", text: $senderSearchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.secondary.opacity(0.10))
                )
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)

                if isSearchingAllSenders && store.isLoadingAllSenders && store.allSenders.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching all senders...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(.bar)
                }

                Divider()

                if store.isLoading {
                    Spacer()
                    ProgressView("Loading senders...")
                    Spacer()
                } else if !isSearchingAllSenders && store.senders.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("Click Refresh to load senders")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else if isSearchingAllSenders && store.isLoadingAllSenders && store.allSenders.isEmpty {
                    Spacer()
                    ProgressView("Searching all senders...")
                    Spacer()
                } else if displayedSenders.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 34))
                            .foregroundStyle(.tertiary)
                        Text("No senders match your search")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(displayedSenders) { sender in
                        senderRow(for: sender)
                            .contentShape(Rectangle())
                            .onHover { isHovering in
                                if isHovering {
                                    hoveredSender = sender
                                    Task { await store.loadEmailsForSender(sender.email) }
                                } else if hoveredSender?.id == sender.id {
                                    hoveredSender = nil
                                }
                            }
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    if lockedSender?.id == sender.id {
                                        lockedSender = nil
                                    } else {
                                        lockedSender = sender
                                        detailFilter = ""
                                        Task { await store.loadEmailsForSender(sender.email) }
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(
                                        lockedSender?.id == sender.id
                                        ? accentColor.opacity(0.50)
                                        : (hoveredSender?.id == sender.id ? accentColor.opacity(0.30) : Color.clear)
                                    )
                            )
                            .overlay(alignment: .topTrailing) {
                                if lockedSender?.id == sender.id {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(accentColor)
                                        .rotationEffect(.degrees(24))
                                        .padding(4)
                                        .background(
                                            Circle()
                                                .fill(.regularMaterial)
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(accentColor.opacity(0.35), lineWidth: 1)
                                        )
                                        .shadow(color: accentColor.opacity(0.25), radius: 3, y: 1)
                                        .offset(x: 14, y: -12)
                                }
                            }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 240, maxWidth: 300)

            Divider()

            // Right column: email detail for selected/hovered sender
            if let sender = detailSender {
                SenderDetailPanel(sender: sender, detailFilter: $detailFilter, isLocked: lockedSender != nil)
                    .transition(.opacity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Hover over a sender to preview their emails")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Click to lock the selection")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if store.senders.isEmpty {
                await store.loadTopSenders()
            }
            if isSearchingAllSenders {
                await store.loadAllSendersIfNeeded()
            }
        }
        .onChange(of: senderSearchText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Task { await store.loadAllSendersIfNeeded() }
            }
            syncSelectionToVisibleSenders()
        }
        .onChange(of: store.senders) { _, _ in
            syncSelectionToVisibleSenders()
        }
        .onChange(of: store.allSenders) { _, _ in
            syncSelectionToVisibleSenders()
        }
    }

    @ViewBuilder
    private func senderRow(for sender: SenderAggregate) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sender.name)
                    .font(.headline)
                    .lineLimit(1)
                if sender.email != sender.name {
                    Text(sender.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(sender.count)")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(accentColor)
                if !sender.totalSize.isEmpty {
                    Text(sender.totalSize)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func syncSelectionToVisibleSenders() {
        let visibleEmails = Set(displayedSenders.map(\.email))
        if let locked = lockedSender, !visibleEmails.contains(locked.email) {
            lockedSender = nil
            detailFilter = ""
        }
        if let hovered = hoveredSender, !visibleEmails.contains(hovered.email) {
            hoveredSender = nil
        }
    }
}

// MARK: - Sender Detail Panel

struct SenderDetailPanel: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor

    let sender: SenderAggregate
    @Binding var detailFilter: String
    let isLocked: Bool

    // Local selected-message state (independent of the shared SearchView state)
    @State private var selectedMessage: EmailMessage?
    @State private var localMessageDetail: String = ""
    @State private var localMessageDetailHTML: String?
    @State private var isLoadingDetail = false
    @State private var showAdvancedFilters = false
    @State private var filterTo = ""
    @State private var filterCC = ""
    @State private var filterBCC = ""
    @State private var filterSubject = ""
    @State private var filterAfterDate: Date?
    @State private var filterBeforeDate: Date?
    @State private var filterRelativeDate: SenderRelativeDatePreset = .none
    @State private var filterSizePreset: SenderSizePreset = .none
    @State private var filterHasAttachment = false
    @State private var filterLabel = ""
    @State private var remoteFilteredMessages: [EmailMessage] = []
    @State private var isRunningRemoteFilterSearch = false
    @State private var remoteFilterError: String?
    @State private var remoteFilterTask: Task<Void, Never>?

    private enum SenderRelativeDatePreset: String, CaseIterable, Identifiable {
        case none
        case lastDay
        case lastWeek
        case lastMonth
        case lastThreeMonths
        case lastYear

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "Any time"
            case .lastDay: return "Last 24 hours"
            case .lastWeek: return "Last 7 days"
            case .lastMonth: return "Last 30 days"
            case .lastThreeMonths: return "Last 3 months"
            case .lastYear: return "Last year"
            }
        }

        var queryToken: String? {
            switch self {
            case .none: return nil
            case .lastDay: return "newer_than:1d"
            case .lastWeek: return "newer_than:7d"
            case .lastMonth: return "newer_than:30d"
            case .lastThreeMonths: return "newer_than:90d"
            case .lastYear: return "newer_than:365d"
            }
        }
    }

    private enum SenderSizePreset: String, CaseIterable, Identifiable {
        case none
        case largerThan1MB
        case largerThan5MB
        case largerThan10MB
        case smallerThan500KB

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "Any size"
            case .largerThan1MB: return "Larger than 1 MB"
            case .largerThan5MB: return "Larger than 5 MB"
            case .largerThan10MB: return "Larger than 10 MB"
            case .smallerThan500KB: return "Smaller than 500 KB"
            }
        }

        var queryToken: String? {
            switch self {
            case .none: return nil
            case .largerThan1MB: return "larger:1M"
            case .largerThan5MB: return "larger:5M"
            case .largerThan10MB: return "larger:10M"
            case .smallerThan500KB: return "smaller:500K"
            }
        }
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoDateFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let queryDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func sortableDate(_ value: String) -> Date {
        if let d = Self.isoDateFormatterFractional.date(from: value) { return d }
        if let d = Self.isoDateFormatter.date(from: value) { return d }
        if let d = Self.queryDateFormatter.date(from: value) { return d }
        return .distantPast
    }

    private func displayDate(_ value: String) -> String {
        let date = sortableDate(value)
        guard date != .distantPast else { return value }
        return Self.displayDateFormatter.string(from: date)
    }

    private var isLoadingMessages: Bool {
        store.isLoadingSenderEmails.contains(sender.email)
    }

    private var allMessages: [EmailMessage] {
        (store.senderEmailCache[sender.email] ?? [])
            .sorted { sortableDate($0.date) > sortableDate($1.date) }
    }

    private var hasAdvancedFilters: Bool {
        !filterTo.isEmpty || !filterCC.isEmpty || !filterBCC.isEmpty || !filterSubject.isEmpty ||
        filterAfterDate != nil || filterBeforeDate != nil || filterRelativeDate != .none ||
        filterSizePreset != .none || filterHasAttachment || !filterLabel.isEmpty
    }

    private var activeAdvancedFilterCount: Int {
        [!filterTo.isEmpty, !filterCC.isEmpty, !filterBCC.isEmpty, !filterSubject.isEmpty,
         filterAfterDate != nil, filterBeforeDate != nil, filterRelativeDate != .none,
         filterSizePreset != .none, filterHasAttachment, !filterLabel.isEmpty]
            .filter { $0 }.count
    }

    private var sourceMessages: [EmailMessage] {
        hasAdvancedFilters
            ? remoteFilteredMessages.sorted { sortableDate($0.date) > sortableDate($1.date) }
            : allMessages
    }

    private var filteredMessages: [EmailMessage] {
        if hasAdvancedFilters {
            return sourceMessages
        }

        let trimmed = detailFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return sourceMessages }
        return sourceMessages.filter { msg in
            msg.subject.lowercased().contains(trimmed) ||
            msg.snippet.lowercased().contains(trimmed) ||
            msg.date.lowercased().contains(trimmed)
        }
    }

    /// Labels present in the current visible message set, sorted by frequency.
    /// Used to scope the label picker to only what's relevant for this sender/filter combo.
    private var labelsFromCurrentMessages: [LabelInfo] {
        var counts: [String: Int] = [:]
        for msg in sourceMessages {
            for label in msg.labels {
                counts[label, default: 0] += 1
            }
        }
        return counts
            .map { LabelInfo(key: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Returns an `AttributedString` with every occurrence of `keyword` highlighted.
    private func highlighted(
        _ text: String,
        keyword: String,
        baseFontSize: CGFloat = 13,
        bold: Bool = false
    ) -> AttributedString {
        var result = AttributedString(text)
        var baseFont = Font.system(size: baseFontSize)
        if bold { baseFont = baseFont.bold() }
        result.font = baseFont

        let lowText = text.lowercased()
        let lowKW   = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowKW.isEmpty else { return result }

        var searchFrom = lowText.startIndex
        while let range = lowText.range(of: lowKW, range: searchFrom..<lowText.endIndex) {
            let startOffset = lowText.distance(from: lowText.startIndex, to: range.lowerBound)
            let endOffset   = lowText.distance(from: lowText.startIndex, to: range.upperBound)
            let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
            let attrEnd   = result.index(result.startIndex, offsetByCharacters: endOffset)
            result[attrStart..<attrEnd].backgroundColor = .yellow.opacity(0.45)
            result[attrStart..<attrEnd].foregroundColor = .primary
            result[attrStart..<attrEnd].font = bold
                ? .system(size: baseFontSize, weight: .bold)
                : .system(size: baseFontSize, weight: .semibold)
            searchFrom = range.upperBound
        }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left column: header + filter bar + email list
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(sender.name)
                                .font(.title3.bold())
                                .lineLimit(1)
                            if !isLocked {
                                Text("(preview)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        if sender.email != sender.name {
                            Text(sender.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !allMessages.isEmpty {
                        Text("\(filteredMessages.count == allMessages.count ? "\(allMessages.count)" : "\(filteredMessages.count)/\(allMessages.count)") msgs")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    // Move to Search button — carries sender + any active filter keyword
                    Button {
                        store.searchForSenderRequest = SenderSearchRequest(
                            senderEmail: sender.email,
                            additionalKeywords: detailFilter.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    } label: {
                        Label("Search in Search", systemImage: "magnifyingglass")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(LinearGradient(
                                        colors: [accentColor.opacity(0.9), accentColor.opacity(0.75)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Go to Search tab with from:\(sender.email)\(detailFilter.isEmpty ? "" : " \(detailFilter)")")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.bar)

                Divider()

                // Filter bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(detailFilter.isEmpty ? Color.secondary : accentColor)
                    TextField("Filter by subject or keyword…", text: $detailFilter)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .onChange(of: detailFilter) { _, _ in
                            selectedMessage = nil
                            localMessageDetail = ""
                            localMessageDetailHTML = nil
                            scheduleRemoteFilterSearchIfNeeded()
                        }
                    if !detailFilter.isEmpty {
                        Button { detailFilter = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showAdvancedFilters.toggle()
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: showAdvancedFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle((showAdvancedFilters || hasAdvancedFilters) ? accentColor : .secondary)
                            if activeAdvancedFilterCount > 0 {
                                Text("\(activeAdvancedFilterCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(accentColor)
                                    .clipShape(Capsule())
                                    .offset(x: 7, y: -8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Show advanced filters")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

                if showAdvancedFilters {
                    VStack(spacing: 12) {
                        Divider().opacity(0.5)

                        HStack(spacing: 12) {
                            FilterField(label: "To", placeholder: "recipient@example.com", text: $filterTo, icon: "person.2")
                            FilterField(label: "CC", placeholder: "team@example.com", text: $filterCC, icon: "person.3")
                        }

                        HStack(spacing: 12) {
                            FilterField(label: "BCC", placeholder: "archive@example.com", text: $filterBCC, icon: "person.crop.circle.badge.checkmark")
                            FilterField(label: "Subject", placeholder: "meeting notes", text: $filterSubject, icon: "text.alignleft")
                        }

                        HStack(spacing: 12) {
                            FilterFieldLabelPicker(
                                selectedLabel: $filterLabel,
                                onSelect: { scheduleRemoteFilterSearchIfNeeded() },
                                resultLabels: allMessages.isEmpty ? nil : labelsFromCurrentMessages
                            )

                            Picker("Quick Date", selection: $filterRelativeDate) {
                                ForEach(SenderRelativeDatePreset.allCases) { preset in
                                    Text(preset.label).tag(preset)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 12) {
                            Picker("Size", selection: $filterSizePreset) {
                                ForEach(SenderSizePreset.allCases) { preset in
                                    Text(preset.label).tag(preset)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Spacer()
                        }

                        Text("To/CC/BCC/Subject support partial matching. Sender is fixed to \(sender.email).")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        CompactDateAttachmentBar(
                            afterDate: $filterAfterDate,
                            beforeDate: $filterBeforeDate,
                            hasAttachment: $filterHasAttachment
                        )

                        if hasAdvancedFilters {
                            HStack {
                                activeAdvancedFilterChips
                                Spacer()
                                Button("Clear filters") {
                                    clearAdvancedFilters()
                                }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(accentColor)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .background(.bar.opacity(0.25))
                }

                if hasAdvancedFilters && (isRunningRemoteFilterSearch || remoteFilterError != nil) {
                    HStack(spacing: 8) {
                        if isRunningRemoteFilterSearch {
                            ProgressView()
                                .controlSize(.small)
                            Text("Applying sender filters…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let remoteFilterError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text(remoteFilterError)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.bar.opacity(0.25))
                }

                Divider()

                // Email list
                if isLoadingMessages && allMessages.isEmpty {
                    Spacer()
                    ProgressView("Loading emails…")
                    Spacer()
                } else if filteredMessages.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text(emptyStateMessage)
                            .foregroundStyle(.secondary)
                        if hasAdvancedFilters || !detailFilter.isEmpty {
                            Button("Clear filters") {
                                detailFilter = ""
                                clearAdvancedFilters()
                            }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    Spacer()
                } else {
                    List(filteredMessages, id: \.id, selection: Binding(
                        get: { selectedMessage?.id },
                        set: { id in
                            if let id, let msg = filteredMessages.first(where: { $0.id == id }) {
                                selectMessage(msg)
                            }
                        }
                    )) { message in
                        senderMessageRow(message)
                            .tag(message.id)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)

            Divider()

            // Right column: message detail
            if let message = selectedMessage {
                VStack(alignment: .leading, spacing: 0) {
                    // Detail header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                            .font(.headline)
                            .lineLimit(3)
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("From").font(.caption).foregroundStyle(.secondary)
                                Text(message.from).font(.subheadline).lineLimit(1)
                            }
                            if !message.to.isEmpty {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("To").font(.caption).foregroundStyle(.secondary)
                                    Text(message.to).font(.subheadline).lineLimit(1)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("Date").font(.caption).foregroundStyle(.secondary)
                                Text(displayDate(message.date)).font(.subheadline)
                            }
                        }
                        if !message.labels.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(message.labels, id: \.self) { label in
                                    Text(label)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(accentColor.opacity(0.12))
                                        .foregroundStyle(accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            selectedMessage = nil
                            localMessageDetail = ""
                            localMessageDetailHTML = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                    }

                    Divider()

                    // Detail body
                    if isLoadingDetail {
                        Spacer()
                        ProgressView("Loading message…")
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else if let html = localMessageDetailHTML, !html.isEmpty {
                        MessageHTMLView(html: html)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !localMessageDetail.isEmpty {
                        ScrollView {
                            Text(localMessageDetail)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Spacer()
                        Text("No message body available.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "envelope.open")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Select an email to read it")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: sender.email) { _, _ in
            selectedMessage = nil
            localMessageDetail = ""
            localMessageDetailHTML = nil
            remoteFilteredMessages = []
            remoteFilterError = nil
            scheduleRemoteFilterSearchIfNeeded()
        }
        .onChange(of: filterTo) { _, _ in scheduleRemoteFilterSearchIfNeeded() }
        .onChange(of: filterCC) { _, _ in scheduleRemoteFilterSearchIfNeeded() }
        .onChange(of: filterBCC) { _, _ in scheduleRemoteFilterSearchIfNeeded() }
        .onChange(of: filterSubject) { _, _ in scheduleRemoteFilterSearchIfNeeded() }
        .onChange(of: filterAfterDate) { _, _ in scheduleRemoteFilterSearchIfNeeded() }
        .onChange(of: filterBeforeDate) { _, _ in scheduleRemoteFilterSearchIfNeeded() }
        .onChange(of: filterRelativeDate) { _, _ in scheduleRemoteFilterSearchIfNeeded() }
        .onChange(of: filterSizePreset) { _, _ in scheduleRemoteFilterSearchIfNeeded() }
        .onChange(of: filterHasAttachment) { _, _ in scheduleRemoteFilterSearchIfNeeded() }
        .onChange(of: filterLabel) { _, _ in scheduleRemoteFilterSearchIfNeeded() }
        .onDisappear {
            remoteFilterTask?.cancel()
        }
    }

    private var emptyStateMessage: String {
        if hasAdvancedFilters {
            return "No emails match these sender filters"
        }
        if detailFilter.isEmpty {
            return "No emails found for this sender"
        }
        return "No emails match the filter"
    }

    private var activeAdvancedFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !filterTo.isEmpty {
                    let prefix = isLikelyExactEmailAddress(filterTo) ? "to:" : "to~:"
                    filterChip("\(prefix)\(filterTo)") { filterTo = "" }
                }
                if !filterCC.isEmpty {
                    let prefix = isLikelyExactEmailAddress(filterCC) ? "cc:" : "cc~:"
                    filterChip("\(prefix)\(filterCC)") { filterCC = "" }
                }
                if !filterBCC.isEmpty {
                    let prefix = isLikelyExactEmailAddress(filterBCC) ? "bcc:" : "bcc~:"
                    filterChip("\(prefix)\(filterBCC)") { filterBCC = "" }
                }
                if !filterSubject.isEmpty { filterChip("subject~:\(filterSubject)") { filterSubject = "" } }
                if let filterAfterDate {
                    filterChip("after:\(queryDateString(filterAfterDate))") { self.filterAfterDate = nil }
                }
                if let filterBeforeDate {
                    filterChip("before:\(queryDateString(filterBeforeDate))") { self.filterBeforeDate = nil }
                }
                if let relativeDateToken = filterRelativeDate.queryToken {
                    filterChip(relativeDateToken) { filterRelativeDate = .none }
                }
                if let sizeToken = filterSizePreset.queryToken {
                    filterChip(sizeToken) { filterSizePreset = .none }
                }
                if filterHasAttachment { filterChip("has:attachment") { filterHasAttachment = false } }
                if !filterLabel.isEmpty { filterChip("label:\(filterLabel)") { filterLabel = "" } }
            }
        }
    }

    private func filterChip(_ text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption2.monospaced())
            Button { onRemove() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(accentColor.opacity(0.12))
        .foregroundStyle(accentColor)
        .clipShape(Capsule())
    }

    private func clearAdvancedFilters() {
        filterTo = ""
        filterCC = ""
        filterBCC = ""
        filterSubject = ""
        filterAfterDate = nil
        filterBeforeDate = nil
        filterRelativeDate = .none
        filterSizePreset = .none
        filterHasAttachment = false
        filterLabel = ""
    }

    private func scheduleRemoteFilterSearchIfNeeded() {
        remoteFilterTask?.cancel()

        guard hasAdvancedFilters else {
            remoteFilteredMessages = []
            remoteFilterError = nil
            isRunningRemoteFilterSearch = false
            return
        }

        let query = buildSenderFilterQuery()
        guard !query.isEmpty else {
            remoteFilteredMessages = []
            remoteFilterError = nil
            isRunningRemoteFilterSearch = false
            return
        }

        isRunningRemoteFilterSearch = true
        remoteFilterError = nil

        remoteFilterTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            do {
                let messages = try await store.searchRawMessages(query: query, limit: 200)
                guard !Task.isCancelled else { return }
                remoteFilteredMessages = messages
                if let selectedMessage, !messages.contains(where: { $0.id == selectedMessage.id }) {
                    self.selectedMessage = nil
                    localMessageDetail = ""
                    localMessageDetailHTML = nil
                }
                remoteFilterError = nil
            } catch {
                guard !Task.isCancelled else { return }
                remoteFilteredMessages = []
                remoteFilterError = "Failed to apply filters. Please try again."
            }
            isRunningRemoteFilterSearch = false
        }
    }

    private func buildSenderFilterQuery() -> String {
        var parts: [String] = [makeOperatorToken(prefix: "from:", value: sender.email)]

        let toFilter = filterTo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !toFilter.isEmpty {
            if isLikelyExactEmailAddress(toFilter) {
                parts.append(makeOperatorToken(prefix: "to:", value: toFilter))
            } else {
                parts.append(makeKeywordToken(toFilter))
            }
        }

        let ccFilter = filterCC.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ccFilter.isEmpty {
            if isLikelyExactEmailAddress(ccFilter) {
                parts.append(makeOperatorToken(prefix: "cc:", value: ccFilter))
            } else {
                parts.append(makeKeywordToken(ccFilter))
            }
        }

        let bccFilter = filterBCC.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bccFilter.isEmpty {
            if isLikelyExactEmailAddress(bccFilter) {
                parts.append(makeOperatorToken(prefix: "bcc:", value: bccFilter))
            } else {
                parts.append(makeKeywordToken(bccFilter))
            }
        }

        let subjectFilter = filterSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subjectFilter.isEmpty {
            parts.append(makeOperatorToken(prefix: "subject:", value: subjectFilter))
        }

        if let filterAfterDate { parts.append("after:\(queryDateString(filterAfterDate))") }
        if let filterBeforeDate { parts.append("before:\(queryDateString(filterBeforeDate))") }
        if filterAfterDate == nil, filterBeforeDate == nil, let relativeToken = filterRelativeDate.queryToken {
            parts.append(relativeToken)
        }
        if let sizeToken = filterSizePreset.queryToken {
            parts.append(sizeToken)
        }
        if filterHasAttachment {
            parts.append("has:attachment")
        }

        let labelFilter = filterLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !labelFilter.isEmpty {
            parts.append(makeOperatorToken(prefix: "label:", value: labelFilter))
        }

        let keywordFilter = detailFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keywordFilter.isEmpty {
            parts.append(makeKeywordToken(keywordFilter))
        }

        return parts.joined(separator: " ")
    }

    private func queryDateString(_ date: Date) -> String {
        Self.queryDateFormatter.string(from: date)
    }

    private func makeOperatorToken(prefix: String, value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.contains(where: \.isWhitespace) else {
            return "\(prefix)\(cleaned)"
        }
        let escaped = cleaned.replacingOccurrences(of: "\"", with: "\\\"")
        return "\(prefix)\"\(escaped)\""
    }

    private func makeKeywordToken(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.contains(where: \.isWhitespace) else { return cleaned }
        let escaped = cleaned.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func isLikelyExactEmailAddress(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        guard !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        return parts[1].contains(".")
    }

    private func selectMessage(_ message: EmailMessage) {
        selectedMessage = message
        localMessageDetail = ""
        localMessageDetailHTML = nil
        isLoadingDetail = true
        Task {
            let (text, html) = await store.fetchMessageDetail(id: message.id)
            localMessageDetail = text
            localMessageDetailHTML = html
            isLoadingDetail = false
        }
    }

    @ViewBuilder
    private func senderMessageRow(_ message: EmailMessage) -> some View {
        let keyword = detailFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSelected = selectedMessage?.id == message.id
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if keyword.isEmpty {
                    Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                        .font(.subheadline.weight(isSelected ? .bold : .medium))
                        .lineLimit(1)
                } else {
                    Text(highlighted(
                        message.subject.isEmpty ? "(no subject)" : message.subject,
                        keyword: keyword,
                        baseFontSize: 13,
                        bold: isSelected
                    ))
                    .lineLimit(1)
                }
                Spacer()
                Text(displayDate(message.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                if message.hasAttachment {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if !message.snippet.isEmpty {
                if keyword.isEmpty {
                    Text(message.snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(highlighted(message.snippet, keyword: keyword, baseFontSize: 11))
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Stats View

struct StatsView: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor
    @State private var selectedMailActionTab: MailActionTab = .topUnopened
    @State private var mailActionSearchText = ""
    @State private var attachmentAccountFilter: String = ""
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    
    private enum MailActionTab: String, CaseIterable, Identifiable {
        case topUnopened
        case unreadMomentum
        case attachmentCleanup
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .topUnopened: return "Top Unopened Candidates"
            case .unreadMomentum: return "Unread Momentum"
            case .attachmentCleanup: return "Attachment Cleanup Candidates"
            }
        }
        
        var subtitle: String {
            switch self {
            case .topUnopened: return "Best unsubscribe targets based on unread chain volume."
            case .unreadMomentum: return "Senders creating fresh unread traffic in the last 30 days."
            case .attachmentCleanup: return "Senders driving the largest attachment storage build-up."
            }
        }
        
        var icon: String {
            switch self {
            case .topUnopened: return "bell.slash"
            case .unreadMomentum: return "clock.badge.exclamationmark"
            case .attachmentCleanup: return "paperclip.badge.ellipsis"
            }
        }
        
        var teaser: String {
            switch self {
            case .topUnopened: return "• Unopened chains • Unread load • Unsubscribe targets"
            case .unreadMomentum: return "• Last 30d trend • Fresh unread build-up"
            case .attachmentCleanup: return "• Total attachment size • Storage build-up"
            }
        }
        
        var primaryActionTitle: String {
            switch self {
            case .topUnopened: return "Review unread"
            case .unreadMomentum: return "Open 30d unread"
            case .attachmentCleanup: return "Review attachments"
            }
        }
        
        var secondaryActionTitle: String {
            switch self {
            case .topUnopened: return "Find unsubscribe links"
            case .unreadMomentum: return "Open sender in Search"
            case .attachmentCleanup: return "Find large files"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            statsHeader
            Divider()
            statsContent
        }
        .task {
            if store.statsInfo == nil {
                await store.loadStats()
            }
            if store.mailActionInsights == nil {
                await store.loadMailActionInsights(toAccount: attachmentAccountFilter)
            }
        }
        .onChange(of: attachmentAccountFilter) { _, _ in
            Task { await store.loadMailActionInsights(toAccount: attachmentAccountFilter) }
        }
    }

    private var statsHeader: some View {
        HStack {
            Text("Archive Statistics")
                .font(.title2.bold())
            Spacer()
            Button("Refresh") {
                Task { await refreshAll() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.isLoading || store.isLoadingMailActionInsights)
        }
        .padding()
        .background(.bar)
    }

    @ViewBuilder
    private var statsContent: some View {
        if store.isLoading {
            Spacer()
            ProgressView("Loading stats...")
            Spacer()
        } else if let stats = store.statsInfo {
            ScrollView {
                statsOverviewGrid(stats)

                if !stats.lastSync.isEmpty {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                        Text("Last sync: \(stats.lastSync)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }

                mailActionsPanel
                    .padding()
            }
        } else {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Click Refresh to load archive statistics")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func statsOverviewGrid(_ stats: StatsInfo) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 16) {
            StatCard(title: "Total Messages", value: formatWholeNumber(stats.totalMessages), icon: "envelope.fill", color: accentColor)
            StatCard(title: "Accounts", value: formatWholeNumber(stats.totalAccounts), icon: "person.crop.circle", color: .blue)
            StatCard(title: "Attachments", value: formatWholeNumber(stats.totalAttachments), icon: "paperclip", color: .orange)
            StatCard(title: "Database Size", value: stats.dbSize, icon: "internaldrive", color: .purple)
        }
        .padding()
    }

    private var mailActionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mail Actions")
                    .font(.title3.bold())
                Spacer()
                if store.isLoadingMailActionInsights {
                    ProgressView()
                        .controlSize(.small)
                } else if let insights = store.mailActionInsights {
                    Text("Updated \(relativeTime(for: insights.generatedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Actionable cleanup suggestions based on senders, unopened chains, and attachment-heavy traffic.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let insightsError = store.mailActionInsightsError, !insightsError.isEmpty {
                Label(insightsError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                ForEach(MailActionTab.allCases) { tab in
                    Button {
                        selectedMailActionTab = tab
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                    .font(.caption.weight(.semibold))
                                Text(tab.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            Text(tab.teaser)
                                .font(.caption2)
                                .foregroundStyle(selectedMailActionTab == tab ? .white.opacity(0.9) : .secondary)
                                .lineLimit(2)
                            HStack {
                                Text("\(formatWholeNumber(items(for: tab).count)) candidates")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(selectedMailActionTab == tab ? .white.opacity(0.9) : .secondary)
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    selectedMailActionTab == tab
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [accentColor.opacity(0.9), accentColor.opacity(0.65)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    : AnyShapeStyle(Color(NSColor.controlBackgroundColor))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    selectedMailActionTab == tab ? Color.clear : Color.primary.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                        .foregroundStyle(selectedMailActionTab == tab ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: selectedMailActionTab.icon)
                        .foregroundStyle(accentColor)
                    Text(selectedMailActionTab.title)
                        .font(.headline)
                    Spacer(minLength: 0)
                    if selectedMailActionTab == .attachmentCleanup && !store.accounts.isEmpty {
                        Menu {
                            Button("All accounts") { attachmentAccountFilter = "" }
                            Divider()
                            ForEach(store.accounts) { account in
                                Button(account.email) { attachmentAccountFilter = account.email }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(attachmentAccountFilter.isEmpty ? "Account: All" : attachmentAccountFilter)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundStyle(attachmentAccountFilter.isEmpty ? .primary : accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(attachmentAccountFilter.isEmpty
                                          ? Color(NSColor.controlBackgroundColor)
                                          : accentColor.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(attachmentAccountFilter.isEmpty
                                                  ? Color.primary.opacity(0.08)
                                                  : accentColor.opacity(0.30), lineWidth: 1)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Filter attachment candidates by recipient account")
                    }
                    Text("\(formatWholeNumber(filteredItemsForSelectedTab().count)) shown")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(selectedMailActionTab.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search this section (sender or email)", text: $mailActionSearchText)
                        .textFieldStyle(.plain)
                    if !mailActionSearchText.isEmpty {
                        Button {
                            mailActionSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if filteredItemsForSelectedTab().isEmpty {
                    Text(emptyStateText(for: selectedMailActionTab))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } else {
                    mailActionItemList(
                        items: filteredItemsForSelectedTab(),
                        tab: selectedMailActionTab
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func formatWholeNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func refreshAll() async {
        async let statsTask: Void = store.loadStats()
        async let actionsTask: Void = store.loadMailActionInsights(toAccount: attachmentAccountFilter)
        _ = await (statsTask, actionsTask)
    }

    private func relativeTime(for date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func items(for tab: MailActionTab) -> [MailActionInsightItem] {
        guard let insights = store.mailActionInsights else { return [] }
        switch tab {
        case .topUnopened:
            return insights.unsubscribeCandidates
        case .unreadMomentum:
            return insights.unreadMomentum
        case .attachmentCleanup:
            return insights.attachmentHeavySenders
        }
    }
    
    private func filteredItemsForSelectedTab() -> [MailActionInsightItem] {
        let source = items(for: selectedMailActionTab)
        let search = mailActionSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !search.isEmpty else { return source }
        return source.filter { item in
            item.senderName.lowercased().contains(search) ||
            item.senderEmail.lowercased().contains(search)
        }
    }
    
    private func emptyStateText(for tab: MailActionTab) -> String {
        switch tab {
        case .topUnopened:
            return "No strong unsubscribe candidates right now."
        case .unreadMomentum:
            return "No recent unread momentum detected."
        case .attachmentCleanup:
            return "No attachment-heavy senders found in the sample."
        }
    }
    
    private func primaryActionKeywords(for tab: MailActionTab) -> String {
        switch tab {
        case .topUnopened:
            return "label:UNREAD"
        case .unreadMomentum:
            return "label:UNREAD newer_than:30d"
        case .attachmentCleanup:
            return "has:attachment"
        }
    }
    
    private func secondaryActionKeywords(for tab: MailActionTab) -> String {
        switch tab {
        case .topUnopened:
            return "unsubscribe"
        case .unreadMomentum:
            return ""
        case .attachmentCleanup:
            return "has:attachment larger:5M"
        }
    }

    @ViewBuilder
    private func mailActionItemList(items: [MailActionInsightItem], tab: MailActionTab) -> some View {
        let maxSize = items.map(\.totalAttachmentSizeBytes).max() ?? 1
        ForEach(items) { item in
            MailActionInsightRow(
                item: item,
                isAttachmentTab: tab == .attachmentCleanup,
                maxAttachmentSizeBytes: maxSize,
                primaryActionTitle: tab.primaryActionTitle,
                secondaryActionTitle: tab.secondaryActionTitle,
                primaryKeywords: primaryActionKeywords(for: tab),
                secondaryKeywords: secondaryActionKeywords(for: tab),
                accentColor: accentColor
            )
        }
    }

    private func formatAttachmentSize(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1000 {
            return String(format: "%.1f GB", mb / 1024)
        } else if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%d KB", max(bytes / 1024, 1))
        }
    }

    private func attachmentSizeColor(_ bytes: Int) -> Color {
        let mb = Double(bytes) / 1_048_576
        if mb >= 100 { return .red }
        if mb >= 25  { return .orange }
        return .secondary
    }

    private func statPill(_ value: String) -> some View {
        Text(value)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.background.tertiary)
            .clipShape(Capsule())
    }
}

// MARK: - Mail Action Insight Row

private struct MailActionInsightRow: View {
    @EnvironmentObject var store: EmailStore
    let item: MailActionInsightItem
    let isAttachmentTab: Bool
    let maxAttachmentSizeBytes: Int
    let primaryActionTitle: String
    let secondaryActionTitle: String
    let primaryKeywords: String
    let secondaryKeywords: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.senderName.isEmpty ? item.senderEmail : item.senderName)
                        .font(.subheadline.weight(.semibold))
                    Text(item.senderEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isAttachmentTab {
                    Text(formattedSize)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(sizeColor)
                } else {
                    Text("\(item.unopenedChains) unopened chains")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if isAttachmentTab {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(sizeColor.opacity(0.75))
                            .frame(
                                width: geo.size.width * CGFloat(item.totalAttachmentSizeBytes) / CGFloat(max(maxAttachmentSizeBytes, 1)),
                                height: 5
                            )
                    }
                }
                .frame(height: 5)
            }

            HStack(spacing: 8) {
                if isAttachmentTab {
                    statPill("\(item.messagesWithAttachments) w/attachments")
                } else {
                    statPill("\(item.unreadMessages) unread")
                    statPill("\(item.unreadInLast30Days) in 30d")
                    statPill("\(item.messagesWithAttachments) w/attachments")
                }
                Spacer(minLength: 0)
                Button(primaryActionTitle) {
                    store.searchForSenderRequest = SenderSearchRequest(
                        senderEmail: item.senderEmail,
                        additionalKeywords: primaryKeywords
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .controlSize(.mini)

                Button(secondaryActionTitle) {
                    store.searchForSenderRequest = SenderSearchRequest(
                        senderEmail: item.senderEmail,
                        additionalKeywords: secondaryKeywords
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(12)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var formattedSize: String {
        let mb = Double(item.totalAttachmentSizeBytes) / 1_048_576
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1024) }
        if mb >= 1    { return String(format: "%.1f MB", mb) }
        return String(format: "%d KB", max(item.totalAttachmentSizeBytes / 1024, 1))
    }

    private var sizeColor: Color {
        let mb = Double(item.totalAttachmentSizeBytes) / 1_048_576
        if mb >= 100 { return .red }
        if mb >= 25  { return .orange }
        return .secondary
    }

    private func statPill(_ value: String) -> some View {
        Text(value)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.background.tertiary)
            .clipShape(Capsule())
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Text(value)
                .font(.title.bold().monospacedDigit())
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Accounts View

struct AccountsView: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor
    @State private var accountEmail = ""
    @State private var displayName = ""
    @State private var useHeadlessFlow = false
    @State private var forceReauthorize = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Accounts")
                    .font(.title2.bold())
                Spacer()
                Button("Refresh") {
                    Task { await store.loadAccounts() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isLoadingAccounts || store.isPerformingAccountAction)
            }
            .padding()
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Add account")
                            .font(.headline)

                        Text("Add another Gmail account to msgvault. This command usually opens your browser for OAuth.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FilterField(label: "Email address", placeholder: "e.g. work@company.com", text: $accountEmail, icon: "envelope")
                            .disableAutocorrection(true)

                        FilterField(label: "Display name", placeholder: "Optional", text: $displayName, icon: "person")

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Advanced: Server/SSH setup (headless OAuth)", isOn: $useHeadlessFlow)
                                .toggleStyle(.checkbox)
                                .tint(accentColor)
                                .font(.caption)
                            Text("Use this when running without a normal browser session, like a remote server or SSH environment.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Advanced: Reset saved login token", isOn: $forceReauthorize)
                                .toggleStyle(.checkbox)
                                .tint(accentColor)
                                .font(.caption)
                            Text("Use this only if account login is broken or permissions changed. It forces a fresh Google sign-in.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            Task {
                                let success = await store.addAccount(
                                    email: accountEmail,
                                    displayName: displayName,
                                    headless: useHeadlessFlow,
                                    force: forceReauthorize
                                )
                                if success {
                                    accountEmail = ""
                                    displayName = ""
                                    forceReauthorize = false
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if store.isPerformingAccountAction {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                }
                                Text(store.isPerformingAccountAction ? "Adding account..." : "Add account")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentColor)
                        .disabled(
                            store.isPerformingAccountAction ||
                            accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let accountsError = store.accountsError, !accountsError.isEmpty {
                        Label(accountsError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 2)
                    } else if !store.accountActionStatus.isEmpty {
                        Label(store.accountActionStatus, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connected accounts")
                            .font(.headline)

                        if store.isLoadingAccounts {
                            ProgressView("Loading accounts...")
                                .font(.caption)
                        } else if store.accounts.isEmpty {
                            Text("No accounts found. Add your first account above.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.accounts) { account in
                                AccountRow(account: account)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Multi-account behavior")
                            .font(.headline)
                        Text("Search and stats run across all accounts by default. Sync all accounts by running `sync` or `sync-full` without an email.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
        }
        .task {
            if store.accounts.isEmpty {
                await store.loadAccounts()
            }
        }
    }
}

private struct AccountRow: View {
    let account: VaultAccount
    @Environment(\.appAccentColor) private var accentColor

    private static let isoFormatter = ISO8601DateFormatter()
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 5) {
                Text(account.displayName.isEmpty ? account.email : account.displayName)
                    .font(.headline)
                if !account.displayName.isEmpty {
                    Text(account.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Label("\(account.messageCount.formatted())", systemImage: "envelope")
                    Text(account.type.uppercased())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.12))
                        .foregroundStyle(accentColor)
                        .clipShape(Capsule())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Last sync")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(formattedLastSync(account.lastSync))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    private func formattedLastSync(_ raw: String) -> String {
        guard !raw.isEmpty else { return "Never" }
        if let date = Self.isoFormatter.date(from: raw) {
            return Self.displayFormatter.string(from: date)
        }
        return raw
    }
}

// MARK: - Settings View

// MARK: - Theme Swatch

private struct ThemeSwatch: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.accentColor.opacity(0.15))
                        .frame(height: 72)

                    VStack(spacing: 6) {
                        Image(systemName: theme.iconName)
                            .font(.title2)
                            .foregroundStyle(theme.accentColor)

                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.accentColor)
                                .frame(width: 20, height: 7)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.accentColor.opacity(0.40))
                                .frame(width: 28, height: 7)
                        }
                    }
                }

                Text(theme.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? theme.accentColor : .primary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? theme.accentColor.opacity(0.10) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.accentColor : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor
    @State private var binaryPath: String = ""
    @State private var testResult: String = ""
    @State private var selectedTab: SettingsTab = .ai
    @State private var aiModelDraft = ""
    @State private var aiTestInput = "emails from mckinsey last week about strategy with attachments"
    @State private var aiTestOutput = ""
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.teal.rawValue
    @AppStorage("appearanceMode") private var appearanceModeRawValue = AppearanceMode.system.rawValue

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case binary = "Vault Setup"
        case theme = "Theme"
        case ai = "AI Setup"

        var id: String { rawValue }
    }
    
    struct ModelCatalogEntry: Identifiable {
        let id: String
        let tag: String
        let provider: String
        let providerColor: Color
        let displayName: String
        let size: String
        let note: String
        let recommended: Bool
    }

    private let modelCatalog: [ModelCatalogEntry] = [
        // Qwen (Alibaba)
        ModelCatalogEntry(id: "q-0.8b", tag: "qwen3.5:0.8b",  provider: "Qwen",      providerColor: .teal,                                       displayName: "Qwen 3.5 0.8B",  size: "~1.0 GB",  note: "Ultra-fast, minimal RAM",        recommended: false),
        ModelCatalogEntry(id: "q-2b",   tag: "qwen3.5:2b",    provider: "Qwen",      providerColor: .teal,                                       displayName: "Qwen 3.5 2B",    size: "~2.7 GB",  note: "Best balance — recommended",     recommended: true),
        ModelCatalogEntry(id: "q-4b",   tag: "qwen3.5:4b",    provider: "Qwen",      providerColor: .teal,                                       displayName: "Qwen 3.5 4B",    size: "~3.4 GB",  note: "Higher accuracy parsing",        recommended: false),
        // Phi (Microsoft)
        ModelCatalogEntry(id: "phi-mini",tag: "phi4-mini",    provider: "Microsoft", providerColor: Color(red: 0.0,  green: 0.47, blue: 0.84),   displayName: "Phi-4 Mini 3.8B", size: "~2.5 GB", note: "Excellent structured output",    recommended: false),
        ModelCatalogEntry(id: "phi4",    tag: "phi4",          provider: "Microsoft", providerColor: Color(red: 0.0,  green: 0.47, blue: 0.84),   displayName: "Phi-4 14B",       size: "~9.1 GB", note: "High accuracy, larger RAM",      recommended: false),
        // Gemma (Google)
        ModelCatalogEntry(id: "g-1b",   tag: "gemma3:1b",     provider: "Google",    providerColor: Color(red: 0.89, green: 0.19, blue: 0.17),   displayName: "Gemma 3 1B",      size: "~0.8 GB", note: "Tiny and fast",                  recommended: false),
        ModelCatalogEntry(id: "g-4b",   tag: "gemma3:4b",     provider: "Google",    providerColor: Color(red: 0.89, green: 0.19, blue: 0.17),   displayName: "Gemma 3 4B",      size: "~3.3 GB", note: "Strong multilingual capability", recommended: false),
        // Llama (Meta)
        ModelCatalogEntry(id: "ll-1b",  tag: "llama3.2:1b",   provider: "Meta",      providerColor: Color(red: 0.24, green: 0.35, blue: 0.67),   displayName: "Llama 3.2 1B",    size: "~1.3 GB", note: "Fast and open",                  recommended: false),
        ModelCatalogEntry(id: "ll-3b",  tag: "llama3.2:3b",   provider: "Meta",      providerColor: Color(red: 0.24, green: 0.35, blue: 0.67),   displayName: "Llama 3.2 3B",    size: "~2.0 GB", note: "Good balance",                   recommended: false),
        // DeepSeek (reasoning — chain-of-thought distilled, MIT)
        ModelCatalogEntry(id: "ds-r1-1.5b", tag: "deepseek-r1:1.5b", provider: "DeepSeek", providerColor: Color(red: 0.45, green: 0.20, blue: 0.80), displayName: "DeepSeek-R1 1.5B", size: "~1.1 GB", note: "Tiny reasoning model",           recommended: false),
        ModelCatalogEntry(id: "ds-r1-7b",   tag: "deepseek-r1:7b",   provider: "DeepSeek", providerColor: Color(red: 0.45, green: 0.20, blue: 0.80), displayName: "DeepSeek-R1 7B",   size: "~5.2 GB", note: "Strong reasoning, heavier model", recommended: false),
    ]

    private var catalogByProvider: [(provider: String, color: Color, entries: [ModelCatalogEntry])] {
        let providers: [(String, Color)] = [
            ("Qwen",      .teal),
            ("DeepSeek",  Color(red: 0.45, green: 0.20, blue: 0.80)),
            ("Microsoft", Color(red: 0.0,  green: 0.47, blue: 0.84)),
            ("Google",    Color(red: 0.89, green: 0.19, blue: 0.17)),
            ("Meta",      Color(red: 0.24, green: 0.35, blue: 0.67)),
        ]
        return providers.compactMap { (name, color) in
            let entries = modelCatalog.filter { $0.provider == name }
            guard !entries.isEmpty else { return nil }
            return (provider: name, color: color, entries: entries)
        }
    }

    private var appTheme: AppTheme {
        AppTheme.from(rawValue: appThemeRawValue)
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode.from(rawValue: appearanceModeRawValue)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2.bold())
                Spacer()
            }
            .padding()
            .background(.bar)
            
            Divider()
            
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(selectedTab == tab
                                          ? LinearGradient(colors: [accentColor.opacity(0.9), accentColor.opacity(0.75)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                          : LinearGradient(colors: [Color.clear, Color.clear],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            Divider()
            
            Group {
                switch selectedTab {
                case .binary:
                    binaryTab
                case .theme:
                    themeTab
                case .ai:
                    aiTab
                }
            }
        }
        .onAppear {
            binaryPath = store.msgvaultPath
            aiModelDraft = store.aiModelName
        }
    }
    
    private var binaryTab: some View {
        Form {
            Section("msgvault Binary") {
                TextField("Path to msgvault", text: $binaryPath)
                
                HStack {
                    Button("Test Connection") {
                        store.msgvaultPath = binaryPath
                        Task {
                            do {
                                let output = try store.runTestCommand()
                                testResult = "✅ Connected — \(output.prefix(200))"
                            } catch {
                                testResult = "❌ Error: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)

                    Button("Save") {
                        store.msgvaultPath = binaryPath
                        testResult = "Path saved."
                    }
                    .buttonStyle(.bordered)
                }

                if !testResult.isEmpty {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(testResult.hasPrefix("✅") ? .green : .red)
                        .textSelection(.enabled)
                }
            }
            
            Section("Info") {
                LabeledContent("Config location") {
                    Text("~/.msgvault/config.toml")
                        .textSelection(.enabled)
                }
                LabeledContent("Data directory") {
                    Text("~/.msgvault/")
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private var themeTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // Appearance section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Appearance")
                        .font(.headline)

                    HStack(spacing: 0) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Button {
                                appearanceModeRawValue = mode.rawValue
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: mode.iconName)
                                        .font(.subheadline)
                                    Text(mode.label)
                                        .font(.subheadline.weight(appearanceMode == mode ? .semibold : .regular))
                                }
                                .foregroundStyle(appearanceMode == mode ? accentColor : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(appearanceMode == mode ? accentColor.opacity(0.12) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }

                Divider()

                // Colour section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Colour")
                        .font(.headline)

                    Text("Sets the accent colour used throughout the app. Changes apply immediately.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120, maximum: 150))],
                        spacing: 12
                    ) {
                        ForEach(AppTheme.allCases) { theme in
                            ThemeSwatch(
                                theme: theme,
                                isSelected: appTheme == theme
                            ) {
                                appThemeRawValue = theme.rawValue
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private var aiTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AIRuntimeBanner()
                    .environmentObject(store)
                AIModelPicker(aiModelDraft: $aiModelDraft, modelCatalog: modelCatalog)
                    .environmentObject(store)
                Divider()
                AIModelCatalog(aiModelDraft: $aiModelDraft, catalogByProvider: catalogByProvider)
                    .environmentObject(store)
                Divider()
                AITranslationTest(aiTestInput: $aiTestInput, aiTestOutput: $aiTestOutput)
                    .environmentObject(store)
            }
            .padding()
        }
        .task { await store.refreshAIRuntimeStatus() }
    }
    
    private func syntaxRow(_ syntax: String, _ description: String) -> some View {
        HStack {
            Text(syntax)
                .foregroundStyle(accentColor)
                .frame(width: 200, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AI Settings sub-views (extracted to avoid type-check timeout)

private struct AIRuntimeBanner: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: store.ollamaReachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(store.ollamaReachable ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.ollamaReachable ? "Ollama running" : "Ollama not reachable")
                        .font(.subheadline.weight(.semibold))
                    Text(store.aiRuntimeStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { Task { await store.refreshAIRuntimeStatus() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(store.ollamaReachable ? Color.green.opacity(0.25) : Color.orange.opacity(0.25), lineWidth: 1))

            if store.isInstallingAIModel {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(store.aiModelInstallStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(accentColor.opacity(0.20), lineWidth: 1))
            } else if !store.aiModelInstallStatus.isEmpty {
                let isError = store.aiModelInstallStatus.hasPrefix("Install failed")
                HStack(spacing: 8) {
                    Image(systemName: isError ? "xmark.circle" : "checkmark.circle")
                        .foregroundStyle(isError ? .red : .green)
                    Text(store.aiModelInstallStatus)
                        .font(.caption)
                        .foregroundStyle(isError ? .red : .secondary)
                    Spacer()
                }
                .padding(12)
                .background((isError ? Color.red : Color.green).opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

private struct AIModelPicker: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor
    @Binding var aiModelDraft: String
    let modelCatalog: [SettingsView.ModelCatalogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Model")
                .font(.headline)

            if store.ollamaInstalledModels.isEmpty {
                Text(store.ollamaReachable
                     ? "No models installed yet. Pull one from the catalog below."
                     : "Start Ollama to see installed models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(store.ollamaInstalledModels, id: \.self) { model in
                        AIInstalledModelCard(
                            model: model,
                            isActive: store.aiModelName == model,
                            catalogEntry: modelCatalog.first { $0.tag == model }
                        ) {
                            store.setAIModelName(model)
                            aiModelDraft = model
                        }
                    }
                }
            }

            Toggle("Enable AI query translation", isOn: Binding(
                get: { store.aiSearchEnabled },
                set: { store.setAISearchEnabled($0) }
            ))
            .tint(accentColor)

            Text(store.aiSearchStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AIInstalledModelCard: View {
    @Environment(\.appAccentColor) private var accentColor
    let model: String
    let isActive: Bool
    let catalogEntry: SettingsView.ModelCatalogEntry?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let provider = catalogEntry?.provider, let color = catalogEntry?.providerColor {
                        Text(provider)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.15))
                            .foregroundStyle(color)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(accentColor)
                    }
                }
                Text(catalogEntry?.displayName ?? model)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isActive ? accentColor : .primary)
                    .lineLimit(1)
                Text(model)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? accentColor.opacity(0.10) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isActive ? accentColor.opacity(0.45) : Color.primary.opacity(0.10),
                                  lineWidth: isActive ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AIModelCatalog: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor
    @Binding var aiModelDraft: String
    let catalogByProvider: [(provider: String, color: Color, entries: [SettingsView.ModelCatalogEntry])]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Model Catalog")
                .font(.headline)
            Text("Pull models from Ollama. Small models (0.8B – 4B) work well for query translation with minimal RAM.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(catalogByProvider, id: \.provider) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(group.color)
                            .frame(width: 4, height: 16)
                        Text(group.provider)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(group.color)
                    }
                    ForEach(group.entries) { entry in
                        AICatalogRow(entry: entry, aiModelDraft: $aiModelDraft)
                            .environmentObject(store)
                    }
                }
            }
        }
    }
}

private struct AICatalogRow: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor
    let entry: SettingsView.ModelCatalogEntry
    @Binding var aiModelDraft: String

    var body: some View {
        let isInstalled = store.ollamaInstalledModels.contains(entry.tag)
        let isActive    = store.aiModelName == entry.tag
        let isPulling   = store.isInstallingAIModel && store.installingAIModelName == entry.tag

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.subheadline.weight(.medium))
                    if entry.recommended {
                        Text("Recommended")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(accentColor.opacity(0.15))
                            .foregroundStyle(accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text("\(entry.size)  ·  \(entry.note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.tag)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isPulling {
                ProgressView().controlSize(.small).padding(.trailing, 4)
            } else if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Installed")
            } else {
                Button("Install") { Task { _ = await store.installAIModel(entry.tag) } }
                    .buttonStyle(.bordered)
                    .disabled(store.isInstallingAIModel)
                    .controlSize(.small)
            }

            if isActive {
                Button("Active") {}
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                    .disabled(true)
                    .controlSize(.small)
            } else {
                Button("Use") {
                    store.setAIModelName(entry.tag)
                    aiModelDraft = entry.tag
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isActive ? accentColor.opacity(0.35) : Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct AITranslationTest: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor
    @Binding var aiTestInput: String
    @Binding var aiTestOutput: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Translation Test")
                .font(.headline)
            TextField("Type a natural-language query to test...", text: $aiTestInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            HStack {
                Button("Run Test") {
                    Task {
                        if let result = await store.translateNaturalLanguageSearch(aiTestInput) {
                            aiTestOutput = result.query
                        } else {
                            aiTestOutput = "No output — check runtime status above."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .disabled(!store.ollamaReachable || !store.aiSearchEnabled || store.isInstallingAIModel)

                if !aiTestOutput.isEmpty {
                    Button("Clear") { aiTestOutput = "" }.buttonStyle(.bordered)
                }
            }
            if !aiTestOutput.isEmpty {
                Text(aiTestOutput)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accentColor.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// Add a test method to the store
extension EmailStore {
    func runTestCommand() throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: msgvaultPath)
        process.arguments = ["stats"]
        process.standardOutput = pipe
        process.standardError = pipe
        
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = NSHomeDirectory()
        process.environment = env
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "No output"
    }
}

#Preview {
    ContentView()
        .environmentObject(EmailStore())
}
