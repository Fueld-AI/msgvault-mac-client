import SwiftUI
import PDFKit
import QuickLookUI
import QuickLookThumbnailing

struct AttachmentsView: View {
    @EnvironmentObject private var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor

    @State private var keywords = ""
    @State private var filterFrom = ""
    @State private var filterTo = ""
    @State private var filterSubject = ""
    @State private var filterLabel = ""
    @State private var filterAfterDate: Date?
    @State private var filterBeforeDate: Date?
    @State private var filterRelativeDate: RelativeDatePreset = .none
    @State private var selectedAccountEmail = ""
    @State private var showFilters = false

    @State private var localFilenameFilter = ""
    @State private var localMimeFilter = ""
    @State private var resultSearchText = ""
    @State private var contextFromFilter = ""
    @State private var contextToFilter = ""
    @State private var contextCCFilter = ""
    @State private var contextBCCFilter = ""
    @State private var contextLabelFilter = ""
    @State private var showContextualFilterOptions = true
    @State private var showAdvancedQueryFilters = false
    @State private var localTypeFilter: AttachmentTypeFilter = .all
    @State private var localSizeFilter: AttachmentSizePreset = .none
    @State private var sortField: AttachmentSortField = .size
    @State private var sortDirection: SortDirection = .descending
    @State private var browseMode: BrowseMode = .list
    @State private var gridDensity: GridDensity = .compact
    @State private var selectionModeEnabled = false

    @State private var selectedAttachmentIDs: Set<String> = []
    @State private var primaryAttachmentID: String?
    @State private var showSourceEmail = false
    @State private var isPreviewPaneVisible = true
    @State private var lastPreviewAttachmentID: String?

    @State private var debounceTask: Task<Void, Never>?
    @State private var previewTask: Task<Void, Never>?
    @State private var selectionSyncTask: Task<Void, Never>?
    @State private var previewFileURL: URL?
    @State private var previewLoadError: String?
    @State private var isLoadingPreview = false

    @State private var isRunningAttachmentAction = false
    @State private var attachmentActionError: String?

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
    private static let attachmentDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEE, dd-MMM-yy HH:mm"
        return formatter
    }()

    private enum BrowseMode: String, CaseIterable, Identifiable {
        case list
        case grid
        var id: String { rawValue }

        var label: String {
            switch self {
            case .list: return "List"
            case .grid: return "Grid"
            }
        }

        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .grid: return "square.grid.2x2"
            }
        }
    }

    enum GridDensity: String, CaseIterable, Identifiable {
        case compact
        case comfortable

        var id: String { rawValue }

        var label: String {
            switch self {
            case .compact: return "Dense"
            case .comfortable: return "Comfort"
            }
        }

        var minimumCardWidth: CGFloat {
            switch self {
            case .compact: return 172
            case .comfortable: return 220
            }
        }

        var gridSpacing: CGFloat {
            switch self {
            case .compact: return 8
            case .comfortable: return 12
            }
        }

        var cardPadding: CGFloat {
            switch self {
            case .compact: return 8
            case .comfortable: return 10
            }
        }

        var previewHeight: CGFloat {
            switch self {
            case .compact: return 94
            case .comfortable: return 120
            }
        }

        var thumbnailSize: CGSize {
            switch self {
            case .compact: return CGSize(width: 148, height: 86)
            case .comfortable: return CGSize(width: 180, height: 110)
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

    private enum AttachmentSortField: String, CaseIterable, Identifiable {
        case filename
        case size
        case date

        var id: String { rawValue }

        var shortLabel: String {
            switch self {
            case .filename: return "Filename"
            case .size: return "Size"
            case .date: return "Date"
            }
        }
    }

    private enum SortDirection {
        case ascending
        case descending

        mutating func toggle() {
            self = self == .ascending ? .descending : .ascending
        }

        var icon: String {
            switch self {
            case .ascending: return "arrow.up"
            case .descending: return "arrow.down"
            }
        }
    }

    private enum AttachmentTypeFilter: String, CaseIterable, Identifiable {
        case all
        case documents
        case images
        case media
        case archives
        case other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All file types"
            case .documents: return "Documents"
            case .images: return "Images"
            case .media: return "Audio/Video"
            case .archives: return "Archives"
            case .other: return "Other"
            }
        }

        func matches(mimeType: String, filename: String) -> Bool {
            if self == .all { return true }
            let mime = mimeType.lowercased()
            let ext = (filename as NSString).pathExtension.lowercased()
            switch self {
            case .all:
                return true
            case .documents:
                return mime.contains("pdf") ||
                mime.contains("msword") ||
                mime.contains("officedocument") ||
                mime.contains("text/") ||
                ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv"].contains(ext)
            case .images:
                return mime.hasPrefix("image/") ||
                ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg"].contains(ext)
            case .media:
                return mime.hasPrefix("audio/") || mime.hasPrefix("video/") ||
                ["mp3", "wav", "aac", "m4a", "mp4", "mov", "avi", "mkv"].contains(ext)
            case .archives:
                return mime.contains("zip") || mime.contains("tar") || mime.contains("gzip") ||
                ["zip", "tar", "gz", "tgz", "rar", "7z"].contains(ext)
            case .other:
                return !AttachmentTypeFilter.documents.matches(mimeType: mimeType, filename: filename) &&
                !AttachmentTypeFilter.images.matches(mimeType: mimeType, filename: filename) &&
                !AttachmentTypeFilter.media.matches(mimeType: mimeType, filename: filename) &&
                !AttachmentTypeFilter.archives.matches(mimeType: mimeType, filename: filename)
            }
        }
    }

    private enum AttachmentSizePreset: String, CaseIterable, Identifiable {
        case none
        case largerThan1MB
        case largerThan5MB
        case largerThan10MB
        case smallerThan500KB

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "Any attachment size"
            case .largerThan1MB: return "Larger than 1 MB"
            case .largerThan5MB: return "Larger than 5 MB"
            case .largerThan10MB: return "Larger than 10 MB"
            case .smallerThan500KB: return "Smaller than 500 KB"
            }
        }

        func matches(_ bytes: Int) -> Bool {
            switch self {
            case .none: return true
            case .largerThan1MB: return bytes >= 1_000_000
            case .largerThan5MB: return bytes >= 5_000_000
            case .largerThan10MB: return bytes >= 10_000_000
            case .smallerThan500KB: return bytes > 0 && bytes <= 500_000
            }
        }
    }

    enum AttachmentPreviewKind {
        case pdf
        case image
        case quickLook

        init(attachment: AttachmentRecord) {
            let lowerMIME = attachment.mimeType.lowercased()
            let ext = (attachment.filename as NSString).pathExtension.lowercased()
            if lowerMIME.contains("pdf") || ext == "pdf" {
                self = .pdf
            } else if lowerMIME.hasPrefix("image/") ||
                        ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tif", "tiff", "svg"].contains(ext) {
                self = .image
            } else {
                self = .quickLook
            }
        }
    }

    private var activeFilterCount: Int {
        [
            !keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !filterFrom.isEmpty,
            !filterTo.isEmpty,
            !filterSubject.isEmpty,
            !filterLabel.isEmpty,
            !selectedAccountEmail.isEmpty,
            filterAfterDate != nil,
            filterBeforeDate != nil,
            filterRelativeDate != .none,
            !resultSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !contextFromFilter.isEmpty,
            !contextToFilter.isEmpty,
            !contextCCFilter.isEmpty,
            !contextBCCFilter.isEmpty,
            !contextLabelFilter.isEmpty,
            !localFilenameFilter.isEmpty,
            !localMimeFilter.isEmpty,
            localTypeFilter != .all,
            localSizeFilter != .none
        ]
            .filter { $0 }.count
    }

    private var hasActiveServerFilters: Bool {
        !keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !filterFrom.isEmpty ||
        !filterTo.isEmpty ||
        !filterSubject.isEmpty ||
        !filterLabel.isEmpty ||
        !selectedAccountEmail.isEmpty ||
        filterAfterDate != nil ||
        filterBeforeDate != nil ||
        filterRelativeDate != .none
    }

    private var hasActiveLocalFilters: Bool {
        !resultSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !contextFromFilter.isEmpty ||
        !contextToFilter.isEmpty ||
        !contextCCFilter.isEmpty ||
        !contextBCCFilter.isEmpty ||
        !contextLabelFilter.isEmpty ||
        !localFilenameFilter.isEmpty ||
        !localMimeFilter.isEmpty ||
        localTypeFilter != .all ||
        localSizeFilter != .none
    }

    private var localActiveFilterCount: Int {
        [
            !resultSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !contextFromFilter.isEmpty,
            !contextToFilter.isEmpty,
            !contextCCFilter.isEmpty,
            !contextBCCFilter.isEmpty,
            !contextLabelFilter.isEmpty,
            !localFilenameFilter.isEmpty,
            !localMimeFilter.isEmpty,
            localTypeFilter != .all,
            localSizeFilter != .none
        ]
            .filter { $0 }.count
    }

    private var labelsFromAttachmentResults: [LabelInfo] {
        var counts: [String: Int] = [:]
        for record in store.attachmentResults {
            for label in record.message.labels {
                counts[label, default: 0] += 1
            }
        }
        return counts
            .map { LabelInfo(key: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var senderOptionsFromAttachmentResults: [LabelInfo] {
        countsAsLabelInfo(from: store.attachmentResults.map(\.message.from))
    }

    private var toOptionsFromAttachmentResults: [LabelInfo] {
        countsAsLabelInfo(from: store.attachmentResults.flatMap { splitAddressList($0.message.to) })
    }

    private var ccOptionsFromAttachmentResults: [LabelInfo] {
        countsAsLabelInfo(from: store.attachmentResults.flatMap { splitAddressList($0.message.cc) })
    }

    private var bccOptionsFromAttachmentResults: [LabelInfo] {
        countsAsLabelInfo(from: store.attachmentResults.flatMap { splitAddressList($0.message.bcc) })
    }

    private func splitAddressList(_ raw: String) -> [String] {
        raw
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func countsAsLabelInfo(from values: [String]) -> [LabelInfo] {
        var counts: [String: Int] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            counts[trimmed, default: 0] += 1
        }
        return counts
            .map { LabelInfo(key: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }
    }

    private var displayedAttachments: [AttachmentRecord] {
        var items = store.attachmentResults

        let inResultsTerms = resultSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if !inResultsTerms.isEmpty {
            items = items.filter { record in
                let haystack = [
                    record.filename,
                    record.mimeType,
                    record.message.subject,
                    record.message.from,
                    record.message.to,
                    record.message.cc,
                    record.message.bcc,
                    record.message.snippet
                ]
                    .joined(separator: " ")
                    .lowercased()
                return inResultsTerms.allSatisfy { haystack.contains($0) }
            }
        }

        let contextFrom = contextFromFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !contextFrom.isEmpty {
            items = items.filter { $0.message.from.lowercased().contains(contextFrom) }
        }

        let contextTo = contextToFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !contextTo.isEmpty {
            items = items.filter { $0.message.to.lowercased().contains(contextTo) }
        }

        let contextCC = contextCCFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !contextCC.isEmpty {
            items = items.filter { $0.message.cc.lowercased().contains(contextCC) }
        }

        let contextBCC = contextBCCFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !contextBCC.isEmpty {
            items = items.filter { $0.message.bcc.lowercased().contains(contextBCC) }
        }

        let contextLabel = contextLabelFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !contextLabel.isEmpty {
            items = items.filter { record in
                record.message.labels.contains { $0.lowercased() == contextLabel }
            }
        }

        let filenameTerms = localFilenameFilter
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if !filenameTerms.isEmpty {
            items = items.filter { record in
                let haystack = record.filename.lowercased()
                return filenameTerms.allSatisfy { haystack.contains($0) }
            }
        }

        let mimeTerm = localMimeFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !mimeTerm.isEmpty {
            items = items.filter { $0.mimeType.lowercased().contains(mimeTerm) }
        }

        if localTypeFilter != .all {
            items = items.filter {
                localTypeFilter.matches(mimeType: $0.mimeType, filename: $0.filename)
            }
        }

        if localSizeFilter != .none {
            items = items.filter { localSizeFilter.matches($0.sizeBytes) }
        }

        items.sort(by: compareAttachments)
        return items
    }

    private var selectedAttachment: AttachmentRecord? {
        if let primaryAttachmentID {
            return displayedAttachments.first(where: { $0.id == primaryAttachmentID })
        }
        if let anySelected = selectedAttachmentIDs.first {
            return displayedAttachments.first(where: { $0.id == anySelected })
        }
        return nil
    }

    private var selectedAttachments: [AttachmentRecord] {
        let selectedIDs = selectedAttachmentIDs
        if selectedIDs.isEmpty {
            if let selectedAttachment { return [selectedAttachment] }
            return []
        }
        return displayedAttachments.filter { selectedIDs.contains($0.id) }
    }

    private var searchSignature: String {
        buildQuery()
    }

    private var localFilterSignature: String {
        "\(resultSearchText)|\(contextFromFilter)|\(contextToFilter)|\(contextCCFilter)|\(contextBCCFilter)|\(contextLabelFilter)|\(localFilenameFilter)|\(localMimeFilter)|\(localTypeFilter.rawValue)|\(localSizeFilter.rawValue)|\(sortField.rawValue)|\(sortDirection == .ascending ? "asc" : "desc")"
    }

    private func compareAttachments(_ lhs: AttachmentRecord, _ rhs: AttachmentRecord) -> Bool {
        switch sortField {
        case .filename:
            let comparison = lhs.filename.localizedCaseInsensitiveCompare(rhs.filename)
            if comparison != .orderedSame {
                return sortDirection == .ascending
                    ? (comparison == .orderedAscending)
                    : (comparison == .orderedDescending)
            }
        case .size:
            if lhs.sizeBytes != rhs.sizeBytes {
                return sortDirection == .ascending ? (lhs.sizeBytes < rhs.sizeBytes) : (lhs.sizeBytes > rhs.sizeBytes)
            }
        case .date:
            let leftDate = sortableDate(lhs.message.date)
            let rightDate = sortableDate(rhs.message.date)
            if leftDate != rightDate {
                return sortDirection == .ascending ? (leftDate < rightDate) : (leftDate > rightDate)
            }
        }

        let filenameComparison = lhs.filename.localizedCaseInsensitiveCompare(rhs.filename)
        if filenameComparison != .orderedSame {
            return filenameComparison == .orderedAscending
        }
        return sortableDate(lhs.message.date) > sortableDate(rhs.message.date)
    }

    private func queryDateString(_ date: Date) -> String {
        Self.queryDateFormatter.string(from: date)
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

    private func formattedAttachmentDate(_ value: String) -> String {
        let parsed = sortableDate(value)
        if parsed == .distantPast {
            return value
        }
        return Self.attachmentDisplayFormatter.string(from: parsed)
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

    private func buildQuery() -> String {
        var parts: [String] = []

        let accountFilter = selectedAccountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !accountFilter.isEmpty {
            parts.append(makeOperatorToken(prefix: "to:", value: accountFilter))
        }

        let from = filterFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !from.isEmpty {
            if isLikelyExactEmailAddress(from) {
                parts.append(makeOperatorToken(prefix: "from:", value: from))
            } else {
                parts.append(makeKeywordToken(from))
            }
        }

        let to = filterTo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !to.isEmpty {
            if isLikelyExactEmailAddress(to) {
                parts.append(makeOperatorToken(prefix: "to:", value: to))
            } else {
                parts.append(makeKeywordToken(to))
            }
        }

        let subject = filterSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subject.isEmpty {
            parts.append(makeOperatorToken(prefix: "subject:", value: subject))
        }

        if let filterAfterDate {
            parts.append("after:\(queryDateString(filterAfterDate))")
        }
        if let filterBeforeDate {
            parts.append("before:\(queryDateString(filterBeforeDate))")
        }
        if filterAfterDate == nil, filterBeforeDate == nil, let relativeToken = filterRelativeDate.queryToken {
            parts.append(relativeToken)
        }

        let label = filterLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty {
            parts.append(makeOperatorToken(prefix: "label:", value: label))
        }

        let kw = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kw.isEmpty {
            parts.append(kw)
        }

        parts.append("has:attachment")
        return parts.joined(separator: " ")
    }

    private func runSearch() {
        debounceTask?.cancel()
        previewTask?.cancel()
        selectedAttachmentIDs.removeAll()
        primaryAttachmentID = nil
        previewFileURL = nil
        previewLoadError = nil
        attachmentActionError = nil
        store.selectedMessage = nil
        store.messageDetail = ""
        store.messageDetailHTML = nil
        Task { await store.searchAttachments(query: buildQuery(), limit: 180) }
    }

    private func scheduleDebouncedSearch() {
        guard store.liveSearchEnabled else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            runSearch()
        }
    }

    private func clearAllFilters() {
        keywords = ""
        filterFrom = ""
        filterTo = ""
        filterSubject = ""
        filterLabel = ""
        selectedAccountEmail = ""
        filterAfterDate = nil
        filterBeforeDate = nil
        filterRelativeDate = .none
        resultSearchText = ""
        contextFromFilter = ""
        contextToFilter = ""
        contextCCFilter = ""
        contextBCCFilter = ""
        contextLabelFilter = ""
        localFilenameFilter = ""
        localMimeFilter = ""
        localTypeFilter = .all
        localSizeFilter = .none
    }

    private func toggleSort(for field: AttachmentSortField) {
        if sortField == field {
            sortDirection.toggle()
        } else {
            sortField = field
            switch field {
            case .filename: sortDirection = .ascending
            case .size, .date: sortDirection = .descending
            }
        }
    }

    private func applySort(field: AttachmentSortField, direction: SortDirection) {
        sortField = field
        sortDirection = direction
    }

    private var sortSummaryText: String {
        switch (sortField, sortDirection) {
        case (.filename, .ascending): return "Filename A-Z"
        case (.filename, .descending): return "Filename Z-A"
        case (.size, .ascending): return "Size Small-Large"
        case (.size, .descending): return "Size Large-Small"
        case (.date, .ascending): return "Date Old-New"
        case (.date, .descending): return "Date New-Old"
        }
    }

    private func syncSelectionWithVisibleResults() {
        let visibleIDs = Set(displayedAttachments.map(\.id))
        selectedAttachmentIDs = selectedAttachmentIDs.filter { visibleIDs.contains($0) }

        if let primaryAttachmentID, !visibleIDs.contains(primaryAttachmentID) {
            self.primaryAttachmentID = nil
        }
        if self.primaryAttachmentID == nil {
            self.primaryAttachmentID = selectedAttachmentIDs.first ?? displayedAttachments.first?.id
        }
        if !selectionModeEnabled, let primaryAttachmentID {
            selectedAttachmentIDs = [primaryAttachmentID]
        }
    }

    private func queueSelectionSync() {
        selectionSyncTask?.cancel()
        selectionSyncTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            handleSelectionChanged()
        }
    }

    private func handleSelectionChanged() {
        if !selectionModeEnabled && selectedAttachmentIDs.count > 1 {
            if let primaryAttachmentID, selectedAttachmentIDs.contains(primaryAttachmentID) {
                selectedAttachmentIDs = [primaryAttachmentID]
            } else if let first = selectedAttachmentIDs.first {
                primaryAttachmentID = first
                selectedAttachmentIDs = [first]
            }
        }

        if let primaryAttachmentID, !selectedAttachmentIDs.contains(primaryAttachmentID) {
            self.primaryAttachmentID = selectedAttachmentIDs.first
        } else if self.primaryAttachmentID == nil {
            self.primaryAttachmentID = selectedAttachmentIDs.first
        }

        guard let selectedAttachment else {
            previewTask?.cancel()
            previewFileURL = nil
            previewLoadError = nil
            lastPreviewAttachmentID = nil
            store.selectedMessage = nil
            store.messageDetail = ""
            store.messageDetailHTML = nil
            return
        }

        guard isPreviewPaneVisible else { return }

        guard lastPreviewAttachmentID != selectedAttachment.id else { return }
        lastPreviewAttachmentID = selectedAttachment.id
        store.selectedMessage = selectedAttachment.message
        Task { await store.loadMessageDetail(id: selectedAttachment.message.id) }
        loadPreview(for: selectedAttachment)
    }

    private func loadPreview(for attachment: AttachmentRecord) {
        previewTask?.cancel()
        previewFileURL = nil
        previewLoadError = nil

        guard !attachment.contentHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            previewLoadError = "Preview unavailable: missing attachment hash metadata."
            return
        }

        isLoadingPreview = true
        previewTask = Task {
            defer { isLoadingPreview = false }
            do {
                let url = try await store.materializeAttachmentForOpen(attachment)
                guard !Task.isCancelled else { return }
                previewFileURL = url
            } catch {
                guard !Task.isCancelled else { return }
                previewLoadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func runAttachmentAction(_ operation: @escaping () async throws -> Void) {
        attachmentActionError = nil
        isRunningAttachmentAction = true
        Task {
            defer { isRunningAttachmentAction = false }
            do {
                try await operation()
            } catch {
                attachmentActionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func openSelectedAttachment() {
        guard let attachment = selectedAttachment else { return }
        runAttachmentAction {
            let url = try await store.materializeAttachmentForOpen(attachment)
            NSWorkspace.shared.open(url)
        }
    }

    private func revealSelectedAttachmentInFinder() {
        guard let attachment = selectedAttachment else { return }
        runAttachmentAction {
            let url = try await store.materializeAttachmentForOpen(attachment)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func saveSelectedAttachmentAs() {
        guard let attachment = selectedAttachment else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = attachment.filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "attachment.bin"
            : attachment.filename
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        runAttachmentAction {
            try await store.exportAttachment(attachment, to: destinationURL)
        }
    }

    private func openSelectedAttachments() {
        let selected = selectedAttachments
        guard !selected.isEmpty else { return }
        runAttachmentAction {
            let result = await store.materializeAttachmentsForOpen(selected)
            for url in result.urls {
                NSWorkspace.shared.open(url)
            }
            if !result.failures.isEmpty {
                throw MsgVaultError.commandFailed(result.failures.joined(separator: "\n"))
            }
        }
    }

    private func revealSelectedAttachmentsInFinder() {
        let selected = selectedAttachments
        guard !selected.isEmpty else { return }
        runAttachmentAction {
            let result = await store.materializeAttachmentsForOpen(selected)
            if !result.urls.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(result.urls)
            }
            if !result.failures.isEmpty {
                throw MsgVaultError.commandFailed(result.failures.joined(separator: "\n"))
            }
        }
    }

    private func saveSelectedAttachmentsToFolder() {
        let selected = selectedAttachments
        guard !selected.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Here"
        panel.message = "Choose folder for \(selected.count) attachment\(selected.count == 1 ? "" : "s")."
        guard panel.runModal() == .OK, let destinationDirectory = panel.url else { return }

        runAttachmentAction {
            let result = await store.exportAttachments(selected, to: destinationDirectory)
            if !result.failures.isEmpty {
                throw MsgVaultError.commandFailed(result.failures.joined(separator: "\n"))
            }
        }
    }

    private func toggleGridSelection(for attachment: AttachmentRecord) {
        let id = attachment.id
        if selectionModeEnabled {
            if selectedAttachmentIDs.contains(id) {
                selectedAttachmentIDs.remove(id)
                if primaryAttachmentID == id {
                    primaryAttachmentID = selectedAttachmentIDs.first
                }
            } else {
                selectedAttachmentIDs.insert(id)
                primaryAttachmentID = primaryAttachmentID ?? id
            }
        } else {
            if !isPreviewPaneVisible {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPreviewPaneVisible = true
                }
            }
            selectedAttachmentIDs = [id]
            primaryAttachmentID = id
        }
        queueSelectionSync()
    }

    private func sizeText(for attachment: AttachmentRecord) -> String {
        guard attachment.sizeBytes > 0 else { return "Unknown size" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(attachment.sizeBytes))
    }

    private var topControlsSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(keywords.isEmpty ? .secondary : accentColor)
                    TextField("Search files, sender, or subject…", text: $keywords)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .onSubmit { runSearch() }
                    if !keywords.isEmpty {
                        Button {
                            keywords = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(keywords.isEmpty ? Color.primary.opacity(0.10) : accentColor.opacity(0.45), lineWidth: 1)
                )

                if !store.accounts.isEmpty {
                    accountMenu
                }

                labelMenu

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
                    .foregroundStyle(showFilters || hasActiveServerFilters || hasActiveLocalFilters ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(showFilters || hasActiveServerFilters || hasActiveLocalFilters
                                  ? LinearGradient(colors: [accentColor.opacity(0.9), accentColor.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                  : LinearGradient(colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(showFilters || hasActiveServerFilters || hasActiveLocalFilters
                                          ? accentColor.opacity(0.30)
                                          : Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button("Search") { runSearch() }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(LinearGradient(colors: [accentColor.opacity(0.95), accentColor.opacity(0.80)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.bar)
    }

    private var accountMenu: some View {
        Menu {
            Button("All accounts") { selectedAccountEmail = "" }
            Divider()
            ForEach(store.accounts) { account in
                Button(account.email) { selectedAccountEmail = account.email }
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
                    .fill(selectedAccountEmail.isEmpty ? Color(NSColor.controlBackgroundColor) : accentColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selectedAccountEmail.isEmpty ? Color.primary.opacity(0.08) : accentColor.opacity(0.30), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var labelMenu: some View {
        Menu {
            Button("Any label") { filterLabel = "" }
            Divider()
            ForEach(labelsFromAttachmentResults.prefix(40)) { label in
                Button(label.key) { filterLabel = label.key }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.system(size: 11, weight: .medium))
                Text(filterLabel.isEmpty ? "Label" : formatLabel(filterLabel))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(filterLabel.isEmpty ? .primary : accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(filterLabel.isEmpty ? Color(NSColor.controlBackgroundColor) : accentColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(filterLabel.isEmpty ? Color.primary.opacity(0.08) : accentColor.opacity(0.30), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text("Attachment filters")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if hasActiveServerFilters || hasActiveLocalFilters {
                    Button("Clear filters") { clearAllFilters() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(accentColor)
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(resultSearchText.isEmpty ? .secondary : accentColor)
                    TextField("Search these results…", text: $resultSearchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                    if !resultSearchText.isEmpty {
                        Button {
                            resultSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(resultSearchText.isEmpty ? Color.primary.opacity(0.10) : accentColor.opacity(0.45), lineWidth: 1)
                )

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showContextualFilterOptions.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .medium))
                        if hasActiveLocalFilters {
                            Text("\(localActiveFilterCount)")
                                .font(.caption.bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.white.opacity(0.25))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(showContextualFilterOptions ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(showContextualFilterOptions
                                  ? LinearGradient(colors: [accentColor.opacity(0.92), accentColor.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                  : LinearGradient(colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(showContextualFilterOptions ? accentColor.opacity(0.30) : Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if showContextualFilterOptions {
                HStack(spacing: 12) {
                    contextualAutocompleteField(
                        title: "From",
                        icon: "person",
                        selection: $contextFromFilter,
                        options: senderOptionsFromAttachmentResults,
                        emptyText: "Any sender"
                    )
                    contextualAutocompleteField(
                        title: "To",
                        icon: "person.2",
                        selection: $contextToFilter,
                        options: toOptionsFromAttachmentResults,
                        emptyText: "Any recipient"
                    )
                }

                HStack(spacing: 12) {
                    contextualAutocompleteField(
                        title: "CC",
                        icon: "person.3",
                        selection: $contextCCFilter,
                        options: ccOptionsFromAttachmentResults,
                        emptyText: "Any CC"
                    )
                    contextualAutocompleteField(
                        title: "BCC",
                        icon: "person.crop.circle.badge.checkmark",
                        selection: $contextBCCFilter,
                        options: bccOptionsFromAttachmentResults,
                        emptyText: "Any BCC"
                    )
                }

                HStack(spacing: 12) {
                    contextualAutocompleteField(
                        title: "Label",
                        icon: "tag",
                        selection: $contextLabelFilter,
                        options: labelsFromAttachmentResults,
                        emptyText: "Any label",
                        labelFormatter: { formatLabel($0) }
                    )
                    Spacer(minLength: 0)
                }
            }

            DisclosureGroup(isExpanded: $showAdvancedQueryFilters) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        FilterField(label: "From", placeholder: "sender@example.com", text: $filterFrom, icon: "person")
                        FilterField(label: "To", placeholder: "recipient@example.com", text: $filterTo, icon: "person.2")
                    }

                    HStack(spacing: 12) {
                        FilterField(label: "Subject", placeholder: "invoice, statement", text: $filterSubject, icon: "text.alignleft")
                        FilterFieldLabelPicker(
                            selectedLabel: $filterLabel,
                            onSelect: { scheduleDebouncedSearch() },
                            resultLabels: labelsFromAttachmentResults.isEmpty ? nil : labelsFromAttachmentResults
                        )
                    }

                    HStack(spacing: 12) {
                        Picker("Quick date", selection: $filterRelativeDate) {
                            ForEach(RelativeDatePreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Picker("Type", selection: $localTypeFilter) {
                            ForEach(AttachmentTypeFilter.allCases) { filter in
                                Text(filter.label).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Picker("Size", selection: $localSizeFilter) {
                            ForEach(AttachmentSizePreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 12) {
                        DateFilterField(label: "After", date: $filterAfterDate, icon: "calendar")
                        DateRangeConnector()
                        DateFilterField(label: "Before", date: $filterBeforeDate, icon: "calendar")
                    }

                    HStack(spacing: 12) {
                        FilterField(label: "Filename", placeholder: "invoice.pdf", text: $localFilenameFilter, icon: "doc")
                        FilterField(label: "MIME", placeholder: "application/pdf", text: $localMimeFilter, icon: "tag")
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 6) {
                    Text("Advanced query filters")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("runs attachment search")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func contextualAutocompleteField(
        title: String,
        icon: String,
        selection: Binding<String>,
        options: [LabelInfo],
        emptyText: String,
        labelFormatter: @escaping (String) -> String = { $0 }
    ) -> some View {
        let text = selection.wrappedValue
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestions = contextualSuggestions(for: trimmed, options: options)

        return VStack(alignment: .leading, spacing: 6) {
            FilterField(
                label: title,
                placeholder: emptyText,
                text: selection,
                icon: icon
            )

            if !trimmed.isEmpty && !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions.prefix(7)) { option in
                        Button {
                            selection.wrappedValue = option.key
                        } label: {
                            HStack(spacing: 8) {
                                Text(labelFormatter(option.key))
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(option.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(title)
    }

    private func contextualSuggestions(for input: String, options: [LabelInfo]) -> [LabelInfo] {
        let term = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return [] }
        return options.filter { option in
            option.key.lowercased().contains(term)
        }
    }

    private func toolbarToggleButton(
        icon: String,
        isActive: Bool,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? .white : accentColor)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            isActive
                                ? LinearGradient(colors: [accentColor.opacity(0.95), accentColor.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.clear, Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var listHeader: some View {
        HStack(spacing: 10) {
            Text("\(displayedAttachments.count) file\(displayedAttachments.count == 1 ? "" : "s")")
                .font(.caption.weight(.medium))
                .foregroundStyle((hasActiveLocalFilters || hasActiveServerFilters) ? accentColor : .secondary)

            if !selectedAttachmentIDs.isEmpty {
                Text("• \(selectedAttachmentIDs.count) selected")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accentColor)
            }

            Spacer()

            HStack(spacing: 4) {
                toolbarToggleButton(
                    icon: "list.bullet.rectangle",
                    isActive: browseMode == .list,
                    helpText: "List view"
                ) { browseMode = .list }
                toolbarToggleButton(
                    icon: "square.grid.2x2",
                    isActive: browseMode == .grid,
                    helpText: "Grid view"
                ) { browseMode = .grid }
            }
            .padding(3)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            if browseMode == .grid {
                HStack(spacing: 4) {
                    toolbarToggleButton(
                        icon: "square.grid.3x3.fill",
                        isActive: gridDensity == .compact,
                        helpText: "Dense grid"
                    ) { gridDensity = .compact }
                    toolbarToggleButton(
                        icon: "rectangle.grid.2x2",
                        isActive: gridDensity == .comfortable,
                        helpText: "Comfortable grid"
                    ) { gridDensity = .comfortable }
                }
                .padding(3)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }

            Button(selectionModeEnabled ? "Done" : "Select") {
                selectionModeEnabled.toggle()
                if !selectionModeEnabled, let primaryAttachmentID {
                    selectedAttachmentIDs = [primaryAttachmentID]
                } else if selectionModeEnabled, let primaryAttachmentID {
                    selectedAttachmentIDs.insert(primaryAttachmentID)
                }
                queueSelectionSync()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(selectionModeEnabled ? .white : accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        selectionModeEnabled
                            ? LinearGradient(colors: [accentColor.opacity(0.95), accentColor.opacity(0.80)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [accentColor.opacity(0.12), accentColor.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selectionModeEnabled ? accentColor.opacity(0.30) : accentColor.opacity(0.24), lineWidth: 1)
            )
            .controlSize(.small)

            if selectionModeEnabled {
                Button("Open") { openSelectedAttachments() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(accentColor)
                    .disabled(isRunningAttachmentAction || selectedAttachments.isEmpty)

                Button("Reveal") { revealSelectedAttachmentsInFinder() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRunningAttachmentAction || selectedAttachments.isEmpty)

                Button("Save") { saveSelectedAttachmentsToFolder() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRunningAttachmentAction || selectedAttachments.isEmpty)
            }

            Menu {
                Button("Filename (A-Z)") { applySort(field: .filename, direction: .ascending) }
                Button("Filename (Z-A)") { applySort(field: .filename, direction: .descending) }
                Divider()
                Button("Size (Largest first)") { applySort(field: .size, direction: .descending) }
                Button("Size (Smallest first)") { applySort(field: .size, direction: .ascending) }
                Divider()
                Button("Date (Newest first)") { applySort(field: .date, direction: .descending) }
                Button("Date (Oldest first)") { applySort(field: .date, direction: .ascending) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                    Text(sortSummaryText)
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.30), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .frame(minWidth: 128, alignment: .trailing)
            .help("Choose sort order")

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPreviewPaneVisible.toggle()
                }
                if isPreviewPaneVisible {
                    queueSelectionSync()
                }
            } label: {
                Image(systemName: isPreviewPaneVisible ? "sidebar.right" : "sidebar.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isPreviewPaneVisible ? .white : accentColor)
                    .padding(7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isPreviewPaneVisible ? accentColor.opacity(0.9) : accentColor.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isPreviewPaneVisible ? accentColor.opacity(0.30) : accentColor.opacity(0.24), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(isPreviewPaneVisible ? "Hide preview panel" : "Show preview panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var listColumnHeader: some View {
        HStack(spacing: 8) {
            Button {
                toggleSort(for: .filename)
            } label: {
                HStack(spacing: 4) {
                    Text("Filename")
                        .font(.caption2.weight(.semibold))
                    if sortField == .filename {
                        Image(systemName: sortDirection.icon)
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .foregroundStyle(sortField == .filename ? accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button {
                toggleSort(for: .size)
            } label: {
                HStack(spacing: 4) {
                    Text("Size")
                        .font(.caption2.weight(.semibold))
                    if sortField == .size {
                        Image(systemName: sortDirection.icon)
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(sortField == .size ? accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                toggleSort(for: .date)
            } label: {
                HStack(spacing: 4) {
                    Text("Date")
                        .font(.caption2.weight(.semibold))
                    if sortField == .date {
                        Image(systemName: sortDirection.icon)
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .frame(width: 116, alignment: .trailing)
                .foregroundStyle(sortField == .date ? accentColor : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private var leftPane: some View {
        VStack(spacing: 0) {
            if store.isLoadingAttachments {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView()
                    Text(store.attachmentsStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if let error = store.attachmentsError {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("Attachment Search Error")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                Spacer()
            } else if displayedAttachments.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 42))
                        .foregroundStyle(.tertiary)
                    Text(store.attachmentResults.isEmpty ? "Search your file archive" : "No files match these filters")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(store.attachmentResults.isEmpty
                         ? "Files appear here once the attachment index is ready."
                         : "Try broader filters or clear type/size restrictions.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                Spacer()
            } else {
                listHeader

                if let attachmentActionError, !attachmentActionError.isEmpty {
                    HStack {
                        Label(attachmentActionError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .background(.bar)
                }

                Divider()

                if browseMode == .list {
                    VStack(spacing: 0) {
                        listColumnHeader
                        Divider()
                        List(displayedAttachments, selection: $selectedAttachmentIDs) { attachment in
                            AttachmentListRowView(attachment: attachment)
                                .tag(attachment.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if !selectionModeEnabled {
                                        if !isPreviewPaneVisible {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                isPreviewPaneVisible = true
                                            }
                                        }
                                        selectedAttachmentIDs = [attachment.id]
                                        primaryAttachmentID = attachment.id
                                        queueSelectionSync()
                                    } else {
                                        primaryAttachmentID = attachment.id
                                    }
                                }
                        }
                        .listStyle(.inset)
                        .environment(\.defaultMinListRowHeight, 34)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: gridDensity.minimumCardWidth), spacing: gridDensity.gridSpacing)],
                            spacing: gridDensity.gridSpacing
                        ) {
                            ForEach(displayedAttachments) { attachment in
                                AttachmentGridCardView(
                                    attachment: attachment,
                                    isSelected: selectedAttachmentIDs.contains(attachment.id),
                                    selectionModeEnabled: selectionModeEnabled,
                                    density: gridDensity
                                ) {
                                    toggleGridSelection(for: attachment)
                                } onOpen: {
                                    if !isPreviewPaneVisible {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isPreviewPaneVisible = true
                                        }
                                    }
                                    selectedAttachmentIDs = [attachment.id]
                                    primaryAttachmentID = attachment.id
                                    queueSelectionSync()
                                    openSelectedAttachment()
                                }
                            }
                        }
                        .padding(gridDensity.gridSpacing)
                    }
                }
            }

            HStack {
                Spacer()
                Text(buildQuery())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help(buildQuery())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var leftColumn: some View {
        if showFilters {
            VSplitView {
                filterPanel
                    .frame(minHeight: 180, idealHeight: 300)
                leftPane
            }
        } else {
            leftPane
        }
    }

    @ViewBuilder
    private var rightPane: some View {
        VStack(spacing: 0) {
            if let selectedAttachment {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "paperclip.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(accentColor)
                        Text(selectedAttachment.filename)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text(formattedAttachmentDate(selectedAttachment.message.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button("Open Attachment") { openSelectedAttachment() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(accentColor)
                            .disabled(isRunningAttachmentAction || selectedAttachment.contentHash.isEmpty)

                        Button("Reveal in Finder") { revealSelectedAttachmentInFinder() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isRunningAttachmentAction || selectedAttachment.contentHash.isEmpty)

                        Button("Save As…") { saveSelectedAttachmentAs() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isRunningAttachmentAction || selectedAttachment.contentHash.isEmpty)

                        if isRunningAttachmentAction {
                            ProgressView().controlSize(.small)
                        }

                        Spacer()

                        Text(sizeText(for: selectedAttachment))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)

                Divider()

                AttachmentPreviewPane(
                    fileURL: previewFileURL,
                    isLoading: isLoadingPreview,
                    errorText: previewLoadError,
                    kind: AttachmentPreviewKind(attachment: selectedAttachment)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                DisclosureGroup(isExpanded: $showSourceEmail) {
                    ScrollView(.vertical, showsIndicators: true) {
                        MessageDetailView()
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                } label: {
                    HStack {
                        Text("Source Email")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(selectedAttachment.message.from)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(12)
                .background(.bar)
            } else {
                AttachmentPreviewPane(
                    fileURL: nil,
                    isLoading: false,
                    errorText: nil,
                    kind: .quickLook
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topControlsSection
            Divider()
            if isPreviewPaneVisible {
                HSplitView {
                    leftColumn
                        .frame(minWidth: 360, idealWidth: 560)
                    rightPane
                        .frame(minWidth: 360, idealWidth: 520)
                }
            } else {
                leftColumn
            }
        }
        .task {
            if store.accounts.isEmpty {
                await store.loadAccounts()
            }
            store.prewarmAttachmentsIfNeeded()
            if store.attachmentResults.isEmpty && !store.isLoadingAttachments {
                runSearch()
            } else {
                syncSelectionWithVisibleResults()
                queueSelectionSync()
            }
        }
        .onChange(of: selectedAttachmentIDs) { _, _ in queueSelectionSync() }
        .onChange(of: store.attachmentResults) { _, _ in
            syncSelectionWithVisibleResults()
            queueSelectionSync()
        }
        .onChange(of: searchSignature) { _, _ in scheduleDebouncedSearch() }
        .onChange(of: localFilterSignature) { _, _ in
            syncSelectionWithVisibleResults()
            queueSelectionSync()
        }
        .onChange(of: isPreviewPaneVisible) { _, isVisible in
            if isVisible {
                queueSelectionSync()
            } else {
                previewTask?.cancel()
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            previewTask?.cancel()
            selectionSyncTask?.cancel()
        }
    }
}

private struct AttachmentListRowView: View {
    @EnvironmentObject private var store: EmailStore
    let attachment: AttachmentRecord

    private static let isoFull = ISO8601DateFormatter()
    private static let isoFrac: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEE, dd-MMM-yy HH:mm"
        return formatter
    }()
    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private var sizeText: String {
        guard attachment.sizeBytes > 0 else { return "Unknown size" }
        return Self.bytesFormatter.string(fromByteCount: Int64(attachment.sizeBytes))
    }

    private func dateText(_ raw: String) -> String {
        if let date = Self.isoFrac.date(from: raw) { return Self.displayFormatter.string(from: date) }
        if let date = Self.isoFull.date(from: raw) { return Self.displayFormatter.string(from: date) }
        return raw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                AttachmentThumbnailImage(attachment: attachment, size: CGSize(width: 18, height: 18))
                    .environmentObject(store)
                Text(attachment.filename)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 10) {
                    Text(sizeText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .trailing)
                    Text(dateText(attachment.message.date))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 116, alignment: .trailing)
                }
            }
            Text(attachment.message.from)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

private struct AttachmentGridCardView: View {
    @EnvironmentObject private var store: EmailStore
    @Environment(\.appAccentColor) private var accentColor

    let attachment: AttachmentRecord
    let isSelected: Bool
    let selectionModeEnabled: Bool
    let density: AttachmentsView.GridDensity
    var onSelect: () -> Void
    var onOpen: () -> Void

    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private var sizeText: String {
        guard attachment.sizeBytes > 0 else { return "Unknown size" }
        return Self.bytesFormatter.string(fromByteCount: Int64(attachment.sizeBytes))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .frame(height: density.previewHeight)
                    .overlay {
                        AttachmentThumbnailImage(attachment: attachment, size: density.thumbnailSize)
                            .environmentObject(store)
                    }

                if selectionModeEnabled {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? accentColor : .secondary)
                        .padding(8)
                }
            }

            Text(attachment.filename)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text(attachment.message.from)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(sizeText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(density.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? accentColor.opacity(0.45) : Color.primary.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onTapGesture(count: 2) { onOpen() }
    }
}

private struct AttachmentPreviewPane: View {
    let fileURL: URL?
    let isLoading: Bool
    let errorText: String?
    let kind: AttachmentsView.AttachmentPreviewKind

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Preparing file preview...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText, !errorText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34))
                        .foregroundStyle(.orange)
                    Text("Preview unavailable")
                        .font(.headline)
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let fileURL {
                switch kind {
                case .pdf:
                    PDFPreviewView(fileURL: fileURL)
                case .image:
                    ImageFilePreview(fileURL: fileURL)
                case .quickLook:
                    QuickLookFilePreview(fileURL: fileURL)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 42))
                        .foregroundStyle(.tertiary)
                    Text("Select a file to preview")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
        .background(Color(NSColor.textBackgroundColor))
    }
}

private struct PDFPreviewView: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = PDFDocument(url: fileURL)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != fileURL {
            nsView.document = PDFDocument(url: fileURL)
        }
    }
}

private final class QuickLookPreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?

    init(url: URL) {
        self.previewItemURL = url
        super.init()
    }
}

private struct QuickLookFilePreview: NSViewRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        let item = QuickLookPreviewItem(url: fileURL)
        context.coordinator.previewItem = item
        view.previewItem = item
        view.autostarts = true
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        let item = QuickLookPreviewItem(url: fileURL)
        context.coordinator.previewItem = item
        nsView.previewItem = item
    }

    final class Coordinator {
        var previewItem: QuickLookPreviewItem?
    }
}

private struct ImageFilePreview: View {
    let fileURL: URL
    @State private var image: NSImage?
    @State private var failedToLoad = false

    var body: some View {
        Group {
            if let image {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            } else if failedToLoad {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("Image preview unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: fileURL.path) {
            if let loaded = NSImage(contentsOf: fileURL) {
                image = loaded
                failedToLoad = false
            } else {
                image = nil
                failedToLoad = true
            }
        }
    }
}

@MainActor
private final class AttachmentThumbnailService {
    static let shared = AttachmentThumbnailService()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func image(
        for attachment: AttachmentRecord,
        size: CGSize,
        store: EmailStore
    ) async -> NSImage? {
        let hash = attachment.contentHash.trimmingCharacters(in: .whitespacesAndNewlines)
        let keySeed = hash.isEmpty ? attachment.id : hash
        let cacheKey = "\(keySeed)#\(Int(size.width))x\(Int(size.height))"

        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }
        if let existing = inFlight[cacheKey] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            do {
                let localURL = try await store.materializeAttachmentForOpen(attachment)
                guard !Task.isCancelled else { return nil }
                let image = await Self.generateThumbnail(fileURL: localURL, size: size)
                    ?? Self.fallbackImage(fileURL: localURL, attachment: attachment)
                if let image {
                    await MainActor.run { [weak self] in
                        self?.cache.setObject(image, forKey: cacheKey as NSString)
                    }
                }
                return image
            } catch {
                return nil
            }
        }

        inFlight[cacheKey] = task
        let result = await task.value
        inFlight[cacheKey] = nil
        return result
    }

    nonisolated
    private static func generateThumbnail(fileURL: URL, size: CGSize) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }

    nonisolated
    private static func fallbackImage(fileURL: URL, attachment: AttachmentRecord) -> NSImage? {
        let mime = attachment.mimeType.lowercased()
        let ext = (attachment.filename as NSString).pathExtension.lowercased()
        guard mime.hasPrefix("image/") ||
                ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tif", "tiff", "svg"].contains(ext) else {
            return nil
        }
        return NSImage(contentsOf: fileURL)
    }
}

private struct AttachmentThumbnailImage: View {
    @EnvironmentObject private var store: EmailStore
    let attachment: AttachmentRecord
    let size: CGSize

    private let thumbnailService = AttachmentThumbnailService.shared
    @State private var image: NSImage?

    private var placeholderIcon: String {
        let lowerMIME = attachment.mimeType.lowercased()
        let ext = (attachment.filename as NSString).pathExtension.lowercased()
        if lowerMIME.contains("pdf") || ext == "pdf" { return "doc.richtext" }
        if lowerMIME.hasPrefix("image/") { return "photo" }
        if lowerMIME.hasPrefix("audio/") || lowerMIME.hasPrefix("video/") { return "film" }
        if lowerMIME.contains("zip") || ["zip", "tar", "gz", "rar", "7z"].contains(ext) { return "archivebox" }
        return "doc"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: placeholderIcon)
                    .font(.system(size: min(size.width, size.height) * 0.44, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: "\(attachment.id)#\(Int(size.width))x\(Int(size.height))") {
            image = await thumbnailService.image(
                for: attachment,
                size: size,
                store: store
            )
        }
    }
}
