import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appAccentColor) private var accentColor
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.teal.rawValue
    @State private var selectedTab: SidebarTab = .search
    
    enum SidebarTab: String, CaseIterable {
        case search = "Search"
        case senders = "Top Senders"
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
    @State private var searchScope: SearchScope = .everything
    @State private var aiAssistEnabled = true
    @State private var translatedQueryPreview: String?
    @State private var translatedQueryJSONPreview: String?
    @State private var recentQueries: [String] = Self.loadRecentQueries()
    @State private var debounceTask: Task<Void, Never>?
    @State private var isTranslatingQuery = false
    @State private var showFilters = false
    @State private var showTagPicker = false
    @State private var tagSearchText = ""
    @State private var sortOption: SearchSortOption = .defaultOrder
    @StateObject private var speechInput = SpeechInputManager()
    
    private var hasActiveFilters: Bool {
        !filterFrom.isEmpty || !filterTo.isEmpty || !filterCC.isEmpty || !filterBCC.isEmpty || !filterSubject.isEmpty ||
        filterAfterDate != nil || filterBeforeDate != nil || filterRelativeDate != .none || filterSizePreset != .none ||
        filterHasAttachment || !filterLabel.isEmpty
    }
    
    private var activeFilterCount: Int {
        [!filterFrom.isEmpty, !filterTo.isEmpty, !filterCC.isEmpty, !filterBCC.isEmpty, !filterSubject.isEmpty,
         filterAfterDate != nil, filterBeforeDate != nil, filterRelativeDate != .none,
         filterSizePreset != .none, filterHasAttachment, !filterLabel.isEmpty]
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
        let accountEmail: String?
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
            localFilter: localFilter,
            accountEmail: nil
        )
    }
    
    private func performSearch() {
        debounceTask?.cancel()
        Task { await runSearch(userInitiated: true) }
    }
    
    private func scheduleDebouncedSearch() {
        guard store.liveSearchEnabled else { return }
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
        
        if shouldUseAITranslation {
            isTranslatingQuery = true
            if let translated = await store.translateNaturalLanguageSearch(searchKeywords) {
                translatedQueryPreview = translated.query
                translatedQueryJSONPreview = translated.rawJSON
                plan = SearchPlan(
                    query: translated.query,
                    localFilter: SearchLocalFilter(),
                    accountEmail: plan.accountEmail
                )
            }
            isTranslatingQuery = false
        }
        
        await store.search(query: plan.query, localFilter: plan.localFilter, accountEmail: plan.accountEmail)
        if userInitiated {
            recordRecentQuery(searchKeywords.isEmpty ? plan.query : searchKeywords)
        }
    }
    
    private var shouldUseAITranslation: Bool {
        guard aiAssistEnabled, store.aiSearchEnabled else { return false }
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
        translatedQueryPreview = nil
        translatedQueryJSONPreview = nil
        store.searchResults = []
        store.errorMessage = nil
    }
    
    private var displayedResults: [EmailMessage] {
        sortMessages(store.searchResults, option: sortOption)
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

                    // Label picker button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showTagPicker.toggle()
                        }
                        if showTagPicker && store.availableLabels.isEmpty {
                            Task { await store.fetchLabels() }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(filterLabel.isEmpty ? "Label" : filterLabel)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: showTagPicker ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle((filterLabel.isEmpty && !showTagPicker) ? .primary : accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill((filterLabel.isEmpty && !showTagPicker)
                                      ? Color(NSColor.controlBackgroundColor)
                                      : accentColor.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder((filterLabel.isEmpty && !showTagPicker)
                                              ? Color.primary.opacity(0.08)
                                              : accentColor.opacity(0.30), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Filter by Gmail label")

                    if !filterLabel.isEmpty {
                        Button {
                            filterLabel = ""
                            withAnimation(.easeInOut(duration: 0.15)) { showTagPicker = false }
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
                    Button {
                        aiAssistEnabled.toggle()
                    } label: {
                        Label("AI", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(aiAssistEnabled && store.aiSearchEnabled ? .white : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(aiAssistEnabled && store.aiSearchEnabled
                                          ? LinearGradient(colors: [accentColor.opacity(0.9), accentColor.opacity(0.75)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                          : LinearGradient(colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(aiAssistEnabled && store.aiSearchEnabled
                                                  ? accentColor.opacity(0.30)
                                                  : Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.aiSearchEnabled)
                    .help(store.aiSearchEnabled ? "Translate natural-language queries to msgvault syntax" : "Enable AI in Settings > AI")

                    // Live toggle
                    Button {
                        store.liveSearchEnabled.toggle()
                    } label: {
                        Label("Live", systemImage: "bolt.horizontal.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(store.liveSearchEnabled ? .white : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(store.liveSearchEnabled
                                          ? LinearGradient(colors: [accentColor.opacity(0.9), accentColor.opacity(0.75)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                          : LinearGradient(colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(store.liveSearchEnabled
                                                  ? accentColor.opacity(0.30)
                                                  : Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Automatically run search as you type")

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

                // Label picker panel
                if showTagPicker {
                    VStack(spacing: 0) {
                        // Prominent search bar at the top
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("Filter labels…", text: $tagSearchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .medium))
                            if !tagSearchText.isEmpty {
                                Button { tagSearchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(NSColor.textBackgroundColor))

                        Divider()

                        if store.isLoadingLabels {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.75)
                                Text("Loading labels…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            let filteredLabels = tagSearchText.isEmpty
                                ? store.availableLabels
                                : store.availableLabels.filter {
                                    $0.key.localizedCaseInsensitiveContains(tagSearchText)
                                }

                            if filteredLabels.isEmpty {
                                Text("No labels match \"\(tagSearchText)\"")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        ForEach(filteredLabels) { label in
                                            Button {
                                                filterLabel = label.key
                                                tagSearchText = ""
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    showTagPicker = false
                                                }
                                                performSearch()
                                            } label: {
                                                HStack {
                                                    Text(label.key)
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(filterLabel == label.key ? accentColor : .primary)
                                                    Spacer()
                                                    Text("\(label.count)")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.secondary)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 2)
                                                        .background(Color.primary.opacity(0.06))
                                                        .clipShape(Capsule())
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(filterLabel == label.key
                                                            ? accentColor.opacity(0.08)
                                                            : Color.clear)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)

                                            Divider().opacity(0.4).padding(.leading, 12)
                                        }
                                    }
                                }
                                .frame(maxHeight: 220)
                            }
                        }
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(searchKeywords.isEmpty ? Color.secondary : accentColor)
                        
                        TextField("Search your emails...", text: $searchKeywords)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .onSubmit { performSearch() }
                        
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
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                searchKeywords.isEmpty ? Color.primary.opacity(0.12) : accentColor.opacity(0.50),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                
                if isTranslatingQuery || translatedQueryPreview != nil || speechInput.errorMessage != nil {
                    HStack(spacing: 8) {
                        if isTranslatingQuery {
                            ProgressView()
                                .controlSize(.small)
                            Text("Translating query with local AI...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let translatedQueryPreview {
                            Label("AI query:", systemImage: "sparkles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accentColor)
                            Text(translatedQueryPreview)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
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
                            FilterField(label: "Label", placeholder: "INBOX", text: $filterLabel, icon: "tag")
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
                        
                        HStack(alignment: .top, spacing: 14) {
                            DateFilterField(label: "After", date: $filterAfterDate, icon: "calendar")
                            DateRangeConnector()
                            DateFilterField(label: "Before", date: $filterBeforeDate, icon: "calendar.badge.clock")
                            AttachmentFilterField(isOn: $filterHasAttachment)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [accentColor.opacity(0.10), accentColor.opacity(0.03)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(accentColor.opacity(0.22), lineWidth: 1)
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
                    if store.isLoading {
                        Spacer()
                        ProgressView("Searching...")
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else if displayedResults.isEmpty {
                        Spacer()
                        if let error = store.errorMessage {
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
                                    Text("Type keywords above, or use filters to narrow results by sender, subject, date, and more.")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: 280)
                                }
                            }
                        }
                        Spacer()
                    } else {
                        // Sort / count bar — only visible with results
                        HStack(spacing: 10) {
                            Text("\(displayedResults.count) message\(displayedResults.count == 1 ? "" : "s")")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
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
        .onChange(of: store.searchForSenderRequest) { _, request in
            guard let req = request else { return }
            store.searchForSenderRequest = nil
            clearAll()
            filterFrom = req.senderEmail
            let kw = req.additionalKeywords.trimmingCharacters(in: .whitespacesAndNewlines)
            if !kw.isEmpty { searchKeywords = kw }
            showFilters = true
            performSearch()
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
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ dateStr: String) -> String {
        // Try to make the date more readable
        if dateStr.count > 10 {
            return String(dateStr.prefix(10))
        }
        return dateStr
    }
}

// MARK: - Message Detail

struct MessageDetailView: View {
    @EnvironmentObject var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor

    var body: some View {
        if let message = store.selectedMessage {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.subject)
                        .font(.title2.bold())
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("From")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.from)
                                .font(.body)
                        }
                        
                        if !message.to.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("To")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(message.to)
                                    .font(.body)
                                    .lineLimit(2)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Date")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.date)
                                .font(.body)
                        }
                    }
                    
                    if !message.labels.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(message.labels, id: \.self) { label in
                                Text(label)
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

    private var detailSender: SenderAggregate? { lockedSender ?? hoveredSender }

    var body: some View {
        HStack(spacing: 0) {
            // Left column: sender list
            VStack(spacing: 0) {
                HStack {
                    Text("Top Senders")
                        .font(.title2.bold())
                    Spacer()
                    Button("Refresh") {
                        Task { await store.loadTopSenders() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(.bar)

                Divider()

                if store.isLoading {
                    Spacer()
                    ProgressView("Loading senders...")
                    Spacer()
                } else if store.senders.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("Click Refresh to load top senders")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(store.senders) { sender in
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
                                    .fill(lockedSender?.id == sender.id
                                          ? accentColor.opacity(0.12)
                                          : Color.clear)
                            )
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
            if lockedSender?.id == sender.id {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(accentColor)
            }
        }
        .padding(.vertical, 5)
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

    private var filteredMessages: [EmailMessage] {
        let trimmed = detailFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return allMessages }
        return allMessages.filter { msg in
            msg.subject.lowercased().contains(trimmed) ||
            msg.snippet.lowercased().contains(trimmed) ||
            msg.date.lowercased().contains(trimmed)
        }
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
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(detailFilter.isEmpty ? Color.secondary : accentColor)
                    TextField("Filter by subject or keyword…", text: $detailFilter)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .onChange(of: detailFilter) { _, _ in
                            selectedMessage = nil
                            localMessageDetail = ""
                            localMessageDetailHTML = nil
                        }
                    if !detailFilter.isEmpty {
                        Button { detailFilter = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

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
                        Text(detailFilter.isEmpty ? "No emails found for this sender" : "No emails match the filter")
                            .foregroundStyle(.secondary)
                        if !detailFilter.isEmpty {
                            Button("Clear filter") { detailFilter = "" }
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
        }
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Archive Statistics")
                    .font(.title2.bold())
                Spacer()
                Button("Refresh") {
                    Task { await store.loadStats() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            .background(.bar)
            
            Divider()
            
            if store.isLoading {
                Spacer()
                ProgressView("Loading stats...")
                Spacer()
            } else if let stats = store.statsInfo {
                ScrollView {
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
        .task {
            if store.statsInfo == nil {
                await store.loadStats()
            }
        }
    }
    
    private func formatWholeNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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
    @State private var selectedTab: SettingsTab = .binary
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
        Form {
            Section("AI Search Translation") {
                Toggle("Enable AI query translation", isOn: Binding(
                    get: { store.aiSearchEnabled },
                    set: { store.setAISearchEnabled($0) }
                ))
                .tint(accentColor)

                HStack {
                    TextField("Ollama model name (e.g. qwen2.5:1.5b)", text: $aiModelDraft)
                    Button("Save Model") {
                        store.setAIModelName(aiModelDraft)
                    }
                    .buttonStyle(.bordered)
                }

                Toggle("Enable live search as you type", isOn: $store.liveSearchEnabled)
                    .tint(accentColor)
                
                Text(store.aiSearchStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("AI Translation Test") {
                TextField("Sample natural-language query", text: $aiTestInput, axis: .vertical)
                    .lineLimit(2...4)
                
                Button("Run Local Translation Test") {
                    Task {
                        if let result = await store.translateNaturalLanguageSearch(aiTestInput) {
                            aiTestOutput = result.query
                        } else {
                            aiTestOutput = "No translation output. Check AI status above."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)

                if !aiTestOutput.isEmpty {
                    Text(aiTestOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            
            Section("Search Syntax Help") {
                VStack(alignment: .leading, spacing: 6) {
                    syntaxRow("from:john@example.com", "Messages from a sender")
                    syntaxRow("to:jane@example.com", "Messages to a recipient")
                    syntaxRow("cc:team@example.com", "CC contains recipient")
                    syntaxRow("bcc:archive@example.com", "BCC contains recipient")
                    syntaxRow("subject:invoice", "Subject contains word")
                    syntaxRow("has:attachment", "Messages with attachments")
                    syntaxRow("after:2024-01-01", "Messages after date")
                    syntaxRow("before:2024-12-31", "Messages before date")
                    syntaxRow("newer_than:7d", "Messages from recent period")
                    syntaxRow("larger:5M", "Messages over size threshold")
                    syntaxRow("label:INBOX", "Messages with label")
                    syntaxRow("project update", "Full-text search")
                }
                .font(.system(.caption, design: .monospaced))
            }
        }
        .formStyle(.grouped)
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
