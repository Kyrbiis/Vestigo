import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct SettingsDataSection: View {
    @ObservedObject var model: VestigoModel
    @State private var clearPresses = 0
    @State private var showClearConfirm = false
    @State private var importText = ""
    @State private var importNotFound: [String] = []
    @State private var showImportNotFoundAlert = false
    @State private var pendingImportText: String?
    @State private var importWarningMessage = ""
    @State private var showImportWarningAlert = false
    @State private var showImportFilePicker = false
    @State private var isImporting = false
    @State private var importAmbiguities: [ImportAmbiguity] = []
    @State private var currentAmbiguitySelections: [MediaKey] = []
    @State private var pendingImportFormat: WatchedImportEntry.ImportFormat = .automatic
    @State private var showDuplicateWarningAlert = false
    @State private var duplicateWarningCount = 0
    @State private var importPlaceholderIndex = 0

    private var importPlaceholderText: String {
        let examples = [
            "Star Wars m 1977 5 f 1997-05-19\nThe Bear s 2022 5 2023/06/28\nThe Flash s\nThe Italian Job m 2003 4",
            "Star Wars m 1977 5 f 1997-05-19, The Bear s 2022 5 2023/06/28, The Flash s, The Italian Job m 2003 4"
        ]
        return examples[importPlaceholderIndex % examples.count]
    }

    var body: some View {
        Text("Data")
            .sectionTitle()
            .padding(.top, 6)

        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Format")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("title  m/s  year  rating  f  date")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 3) {
                    ImportFormatHelpRow(bullet: "m / s", detail: "movie or series — required")
                    ImportFormatHelpRow(bullet: "year", detail: "4-digit - optional. Resolves ambiguous titles.")
                    ImportFormatHelpRow(bullet: "rating", detail: "0–5 - optional")
                    ImportFormatHelpRow(bullet: "f", detail: "optional, marks as favourite")
                    ImportFormatHelpRow(bullet: "date", detail: "watched date - optional. Separators: - / . in any mix.")
                }
                Text("Accepts .txt (one per line or comma-separated) or .csv. Letterboxd's watched.csv is auto-detected — movies and series both supported.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)


                ZStack(alignment: .topLeading) {
                    if importText.isEmpty {
                        Text(importPlaceholderText)
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $importText)
                        .frame(minHeight: 72, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 18)

                Button {
                    importWatchedData(importText)
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 24, height: 22, alignment: .center)

                        Text(isImporting ? "Importing..." : "Import pasted data")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .frame(height: 22, alignment: .center)

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 32, alignment: .center)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isImporting || importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    showImportFilePicker = true
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 24, height: 22, alignment: .center)

                        Text("Import .txt or .csv file")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .frame(height: 22, alignment: .center)

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 32, alignment: .center)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isImporting)

                Text("If a title already exists in your library, its rating and favourite status will be overwritten with the imported data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .liquidGlass(cornerRadius: 22)

            HStack(spacing: 10) {
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        model.prepareExport(format: format)
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 22, height: 22, alignment: .center)

                            Text("Export \(format.title)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .frame(height: 22, alignment: .center)

                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 48, alignment: .center)
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .liquidGlass(cornerRadius: 18)
                }
            }
            .fileExporter(isPresented: $model.showExporter, document: model.exportDocument, contentType: model.exportFormat.contentType, defaultFilename: model.exportFormat.filename) { _ in }

            NavigationLink {
                HiddenItemsReviewView(model: model)
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "eye.slash.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 22, height: 22, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Review hidden items")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Restore \"Never show\" or \"Not interested\" items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .settingBubble()

            Button("Reset settings") {
                model.settings = AppSettings()
                model.searchFilter = model.settings.defaultSearchFilter
                model.searchFilter = model.settings.defaultSearchFilter
                model.mediaFilter = model.settings.defaultHomeFilter
                model.genreResults.removeAll()
                model.updateSearch()
                Task { await model.loadHome() }
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()

            Button(clearPresses < 3 ? "Clear all data (press \(3 - clearPresses) more)" : "Confirm clear all data") {
                clearPresses += 1
                if clearPresses >= 3 { showClearConfirm = true }
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                importPlaceholderIndex = (importPlaceholderIndex + 1) % 2
            }
        }
        .alert("Delete all Vestigo data?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) { clearPresses = 0 }
            Button("Delete", role: .destructive) {
                model.clearAllData()
                clearPresses = 0
            }
        } message: {
            Text("This removes watched items, ratings, watchlist, collections, episode progress, and settings from local storage.")
        }
        .alert("Some items couldn't be imported", isPresented: $showImportNotFoundAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importNotFound.joined(separator: "\n"))
        }
        .alert("Double-check import formatting", isPresented: $showImportWarningAlert) {
            Button("Cancel", role: .cancel) {
                pendingImportText = nil
            }
            Button("Continue") {
                if let pendingImportText {
                    let textToImport = pendingImportText
                    let formatToImport = pendingImportFormat
                    self.pendingImportText = nil
                    importWatchedData(textToImport, format: formatToImport, skipsWarnings: true)
                }
            }
        } message: {
            Text(importWarningMessage)
        }
        .alert("Duplicate entries detected", isPresented: $showDuplicateWarningAlert) {
            Button("Skip") {
                if let pendingImportText {
                    let textToImport = deduplicated(pendingImportText, format: pendingImportFormat)
                    let formatToImport = pendingImportFormat
                    self.pendingImportText = nil
                    importWatchedData(textToImport, format: formatToImport, skipsWarnings: true, skipsDuplicateWarning: true)
                }
            }
            Button("Continue") {
                if let pendingImportText {
                    let textToImport = pendingImportText
                    let formatToImport = pendingImportFormat
                    self.pendingImportText = nil
                    importWatchedData(textToImport, format: formatToImport, skipsWarnings: true, skipsDuplicateWarning: true)
                }
            }
        } message: {
            Text("Your list contains titles that appear more than once. Skip to only use the first occurrence of each, or Continue to be prompted for each duplicate.")
        }
        .fileImporter(isPresented: $showImportFilePicker, allowedContentTypes: [.plainText, .commaSeparatedText], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importWatchedFile(url)
            case .failure:
                break
            }
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.5)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isImporting)
            } else if let current = importAmbiguities.first {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { }

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ambiguous match")
                                .font(.title3.bold())
                            Text(ambiguitySubtitle(for: current))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        let maxSelectable = min(current.occurrenceCount, current.candidates.count)
                        let rowHeight: CGFloat = 74
                        let visibleRows = min(CGFloat(current.candidates.count), 4.5)
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(current.candidates) { candidate in
                                    let selectionIdx = currentAmbiguitySelections.firstIndex(of: candidate.key)
                                    let entryRating: Double? = selectionIdx.map { current.entries[min($0, current.entries.count - 1)].rating } ?? nil
                                    let badge: (number: Int, rating: Double)? = (maxSelectable > 1 && selectionIdx != nil && entryRating != nil)
                                        ? (number: selectionIdx! + 1, rating: entryRating!)
                                        : nil
                                    ImportCandidateRow(
                                        item: candidate,
                                        isSelected: currentAmbiguitySelections.contains(candidate.key),
                                        accentColor: model.settings.accentColor,
                                        badge: badge
                                    ) {
                                        if let idx = currentAmbiguitySelections.firstIndex(of: candidate.key) {
                                            // Deselect
                                            currentAmbiguitySelections.remove(at: idx)
                                        } else if currentAmbiguitySelections.count < maxSelectable {
                                            currentAmbiguitySelections.append(candidate.key)
                                        } else {
                                            // At max — replace oldest selection
                                            currentAmbiguitySelections.removeFirst()
                                            currentAmbiguitySelections.append(candidate.key)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: rowHeight * visibleRows)
                        .scrollIndicators(.hidden)

                        HStack(spacing: 10) {
                            Button {
                                advanceAmbiguity()
                            } label: {
                                Text("Skip")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .contentShape(Rectangle())
                                    .liquidGlass(cornerRadius: 22)
                            }
                            .buttonStyle(.plain)

                            Button {
                                // Preserve tap order so entry[0]'s rating goes to the first-tapped candidate
                                let choices = currentAmbiguitySelections.compactMap { key in
                                    current.candidates.first { $0.key == key }
                                }
                                if !choices.isEmpty {
                                    model.commitAmbiguousImport(current, choices: choices)
                                    advanceAmbiguity()
                                }
                            } label: {
                                let confirmLabel = maxSelectable > 1
                                    ? "Confirm (\(currentAmbiguitySelections.count)/\(maxSelectable))"
                                    : "Confirm"
                                Text(confirmLabel)
                                    .font(.headline.bold())
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .contentShape(Rectangle())
                                    .liquidGlass(cornerRadius: 22)
                            }
                            .buttonStyle(.plain)
                            .disabled(currentAmbiguitySelections.isEmpty)
                            .opacity(currentAmbiguitySelections.isEmpty ? 0.4 : 1)
                        }
                    }
                    .padding(20)
                    .liquidGlass(cornerRadius: 28)
                    .padding(.horizontal, 20)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: importAmbiguities.first?.id)
            }
        }
    }

    // MARK: - Import logic

    private func importWatchedData(_ text: String, format: WatchedImportEntry.ImportFormat = .automatic, skipsWarnings: Bool = false, skipsDuplicateWarning: Bool = false) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        // Letterboxd CSV bypasses all format/duplicate warnings and goes straight to import
        if WatchedImportEntry.isLetterboxdCSV(trimmedText) {
            isImporting = true
            Task {
                let result = await model.importLetterboxdText(trimmedText)
                await MainActor.run {
                    importNotFound = result.notFound
                    showImportNotFoundAlert = !result.notFound.isEmpty
                    importText = result.notFound.joined(separator: "\n")
                    importAmbiguities = result.ambiguous
                    currentAmbiguitySelections = []
                    isImporting = false
                }
            }
            return
        }

        let report = WatchedImportEntry.report(for: trimmedText, format: format)
        if !skipsWarnings, let warningMessage = WatchedImportEntry.warningMessage(for: report) {
            pendingImportText = trimmedText
            pendingImportFormat = format
            importWarningMessage = warningMessage
            showImportWarningAlert = true
            return
        }

        if !skipsDuplicateWarning && hasDuplicates(in: report.entries) {
            pendingImportText = trimmedText
            pendingImportFormat = format
            showDuplicateWarningAlert = true
            return
        }

        isImporting = true
        Task {
            let result = await model.importWatchedText(trimmedText, format: format)
            let malformed = WatchedImportEntry.report(for: trimmedText, format: format).malformed
            let leftBehind = result.notFound + malformed
            await MainActor.run {
                importNotFound = leftBehind
                showImportNotFoundAlert = !leftBehind.isEmpty
                importText = leftBehind.joined(separator: "\n")
                importAmbiguities = result.ambiguous
                currentAmbiguitySelections = []
                isImporting = false
            }
        }
    }

    private func importWatchedFile(_ url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        importText = text
        if WatchedImportEntry.isLetterboxdCSV(text) {
            importWatchedData(text, skipsWarnings: true, skipsDuplicateWarning: true)
        } else {
            let fileExtension = url.pathExtension.lowercased()
            let format: WatchedImportEntry.ImportFormat = fileExtension == "csv" ? .commaSeparated : .automatic
            importWatchedData(text, format: format)
        }
    }

    private func advanceAmbiguity() {
        importAmbiguities.removeFirst()
        currentAmbiguitySelections = []
    }

    private func ambiguitySubtitle(for ambiguity: ImportAmbiguity) -> String {
        if ambiguity.yearNotFound, let year = ambiguity.primaryEntry.year {
            return "No \(year) release found — pick the right one manually."
        }
        if ambiguity.occurrenceCount > 1 {
            let allSameRating = ambiguity.entries.allSatisfy { $0.rating == ambiguity.primaryEntry.rating }
            if allSameRating {
                return "You added this \(ambiguity.occurrenceCount) times — tap to pick which versions you meant."
            }
            let ratingList = ambiguity.entries.map { entry -> String in
                if let r = entry.rating { return "★\(r.formatted(.number.precision(.fractionLength(0...1))))" }
                return "unrated"
            }.joined(separator: ", then ")
            return "Tap in order: 1st pick gets \(ratingList)"
        }
        return "Which \u{201C}\(ambiguity.primaryEntry.title)\u{201D} did you mean?"
    }

    private func hasDuplicates(in entries: [WatchedImportEntry]) -> Bool {
        var seen: Set<String> = []
        for entry in entries {
            let norm = WatchedImportEntry.normalizedTitle(entry.title)
            let typeKey = entry.mediaFilter == .movie ? "m" : "s"
            let key = norm + ":" + typeKey
            if seen.contains(key) { return true }
            seen.insert(key)
        }
        return false
    }

    private func deduplicated(_ text: String, format: WatchedImportEntry.ImportFormat) -> String {
        let report = WatchedImportEntry.report(for: text, format: format)
        var seen: Set<String> = []
        var kept: [String] = []
        for entry in report.entries {
            let norm = WatchedImportEntry.normalizedTitle(entry.title)
            let typeKey = entry.mediaFilter == .movie ? "m" : "s"
            let key = norm + ":" + typeKey
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            kept.append(entry.rawText)
        }
        return kept.joined(separator: "\n")
    }
}

// MARK: - Private helpers (only used by SettingsDataSection)

private struct ImportFormatHelpRow: View {
    let bullet: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text("•")
            Text(bullet).bold()
            Text("— \(detail)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct ImportCandidateRow: View {
    let item: MediaItem
    let isSelected: Bool
    let accentColor: Color
    var badge: (number: Int, rating: Double)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AsyncImage(url: item.posterURL(displayWidth: 40)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.12))
                    }
                }
                .frame(width: 36, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text("\(item.releaseYearText) · \(item.kind == .tv ? "Series" : "Movie")")
                        if item.voteAverage > 0 {
                            Text("·")
                            Text("TMDb \(item.voteAverage.formatted(.number.precision(.fractionLength(1))))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let badge {
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 24, height: 24)
                            Text("\(badge.number)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        Text("★\(badge.rating.formatted(.number.precision(.fractionLength(0...1))))")
                            .font(.caption2.bold())
                            .foregroundStyle(accentColor)
                    }
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.body.bold())
                        .foregroundStyle(isSelected ? AnyShapeStyle(accentColor) : AnyShapeStyle(.tertiary))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? accentColor.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accentColor, lineWidth: 1.5)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
