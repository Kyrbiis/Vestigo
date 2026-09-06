import SwiftUI
import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct SettingsAboutSection: View {
    @ObservedObject var model: VestigoModel
    @Binding var selectedCategory: SettingsView.SettingsCategory
    @AppStorage("Vestigo.devMode") private var devMode: Bool = false

    var body: some View {
        if selectedCategory == .about {
            Text("About")
                .sectionTitle()
                .padding(.top, 6)

            AboutInfoView()

            AttributionFooter()
        }

        if selectedCategory == .dev {
            Text("Developer")
                .sectionTitle()
                .padding(.top, 6)

            DevToolsPanel(model: model)

            Button("Hide developer tab") {
                selectedCategory = .about
                devMode = false
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()
            .padding(.top, 4)
        }
    }
}

// MARK: - Dev Tools (private)

private struct DevToolsPanel: View {
    @ObservedObject var model: VestigoModel
    @State private var isCheckingBackend = false
    @State private var backendResult: String = ""
    @State private var iCloudPushResult: String = ""

    @State private var showLibraryImportPicker = false
    @State private var showSettingsImportPicker = false
    @State private var importResult: String = ""

    @State private var isRestartingConnection = false
    @State private var restartResult: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // MARK: Snapshots
            devSectionLabel("Snapshots")

            VStack(alignment: .leading, spacing: 8) {
                monoBlock("Library", librarySummary)
                Divider().opacity(0.3)
                monoBlock("Caches", cacheSummary)
                Divider().opacity(0.3)
                monoBlock("iCloud", iCloudSummary)
            }
            .settingBubble()

            // MARK: Clipboard
            devSectionLabel("Clipboard")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button("Copy library JSON") { copyJSON(model.library) }
                    Spacer()
                    Button("Import") { showLibraryImportPicker = true }
                        .foregroundStyle(model.settings.accentColor)
                }
                HStack {
                    Button("Copy settings JSON") { copyJSON(model.settings) }
                    Spacer()
                    Button("Import") { showSettingsImportPicker = true }
                        .foregroundStyle(model.settings.accentColor)
                }
                if !importResult.isEmpty {
                    Text(importResult)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()

            // MARK: Caches
            devSectionLabel("Caches")

            VStack(alignment: .leading, spacing: 10) {
                cacheRow("Ratings",           count: model.externalRatingsCache.count)  { model.clearExternalRatingsCache() }
                cacheRow("Details",           count: model.detailsCache.count)           { model.detailsCache = [:] }
                cacheRow("Streaming",         count: model.providerCache.count)          { model.providerCache = [:] }
                cacheRow("Related media",     count: model.relatedMediaCache.count)      { model.relatedMediaCache = [:] }
                cacheRow("Person credits",    count: model.personCreditsCache.count)     { model.personCreditsCache = [:] }
                cacheRow("Person details",    count: model.personDetails.count)          { model.personDetails = [:] }
                cacheRow("Collection recs",   count: model.collectionRecommendations.count) { model.collectionRecommendations = [:] }
                cacheRow("Home feed",         count: MediaFilter.allCases.filter { UserDefaults.standard.data(forKey: "Vestigo.homeFeedCaches.\($0.rawValue)") != nil }.count) { model.clearHomeFeedCache() }
                cacheRow("Poster images",     count: ImageCache.shared.count)            { ImageCache.shared.clear() }
                Divider().opacity(0.3)
                Button("Clear all caches") {
                    model.clearAllCaches()
                    model.clearExternalRatingsCache()
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .settingBubble()

            // MARK: Features
            devSectionLabel("Features")

            Toggle("Show cinema showtimes (beta)", isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "Vestigo.showCinemas") },
                set: { UserDefaults.standard.set($0, forKey: "Vestigo.showCinemas") }
            ))
            .font(.headline.bold())
            .tint(model.settings.accentColor)
            .settingBubble()

            // MARK: Actions
            devSectionLabel("Actions")

            Button("Reset OMDb counters") {
                model.resetOMDbCounters()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()

            VStack(alignment: .leading, spacing: 6) {
                Button("Force iCloud push") {
                    iCloudPushResult = model.forceICloudPush()
                }
                if !iCloudPushResult.isEmpty {
                    Text(iCloudPushResult)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()

            Button("Simulate first launch") {
                model.simulateFirstLaunch()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()

            Button("Simulate OMDb limit alert") {
                model.showOMDbLimitAlert = true
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()



            // MARK: Diagnostics
            devSectionLabel("Diagnostics")

            VStack(alignment: .leading, spacing: 6) {
                Button(isRestartingConnection ? "Restarting…" : "Restart backend connection") {
                    restartBackendConnection()
                }
                .disabled(isRestartingConnection)

                if !restartResult.isEmpty {
                    Text(restartResult)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()

            VStack(alignment: .leading, spacing: 6) {
                Button(isCheckingBackend ? "Checking…" : "Check backend secrets") {
                    checkBackend()
                }
                .disabled(isCheckingBackend)

                if !backendResult.isEmpty {
                    Text(backendResult)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(isPresented: $showLibraryImportPicker, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            importJSON(result: result, as: UserLibrary.self) { model.library = $0 }
        }
        .fileImporter(isPresented: $showSettingsImportPicker, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            importJSON(result: result, as: AppSettings.self) { model.settings = $0 }
        }
    }

    // MARK: Computed summaries

    private var librarySummary: String {
        let l = model.library
        return """
        items:       \(l.items.count)
        watchlist:   \(l.watchlist.count)
        watched:     \(l.watched.count)
        favourites:  \(l.favouriteKeys.count)
        collections: \(l.collections.count)
        neverShow:   \(l.neverShowAgain.count)
        notInterest: \(l.notInterested.count)
        ratings:     \(l.ratings.count)
        """
    }

    private var cacheSummary: String {
        """
        ratings:     \(model.externalRatingsCache.count)
        details:     \(model.detailsCache.count)
        streaming:   \(model.providerCache.count)
        related:     \(model.relatedMediaCache.count)
        people:      \(model.personCreditsCache.count)
        """
    }

    private var iCloudSummary: String {
        let snapshot = Storage.loadKVSnapshot()
        guard let snapshot else { return "No snapshot found" }
        let encoder = JSONEncoder()
        let sizeKB: String
        if let data = try? encoder.encode(snapshot) {
            sizeKB = "\(data.count / 1024) KB"
        } else {
            sizeKB = "unknown"
        }
        let dateStr = snapshot.modifiedAt.formatted(date: .abbreviated, time: .shortened)
        return "Last push: \(dateStr)\nSize:      ~\(sizeKB)"
    }

    // MARK: Helpers

    @ViewBuilder
    private func cacheRow(_ name: String, count: Int?, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let count {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button("Clear") { clear() }
                .font(.caption.bold())
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func devSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func monoBlock(_ label: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.primary)
            Text(content)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyJSON<T: Encodable>(_ value: T) {
#if canImport(UIKit)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value),
           let text = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = text
        }
#endif
    }

    private func importJSON<T: Decodable>(result: Result<[URL], Error>, as type: T.Type, apply: @escaping (T) -> Void) {
        switch result {
        case .failure(let error):
            importResult = "✗ \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(type, from: data)
                apply(decoded)
                importResult = "✓ Imported \(String(describing: type)) at \(Date().formatted(date: .omitted, time: .standard))"
            } catch {
                importResult = "✗ \(error.localizedDescription)"
            }
        }
    }

    private func restartBackendConnection() {
        isRestartingConnection = true
        restartResult = ""
        URLCache.shared.removeAllCachedResponses()
        model.clearAllCaches()
        Task {
            let urlString = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api/health"
            guard let url = URL(string: urlString) else {
                await MainActor.run { isRestartingConnection = false }
                return
            }
            let start = Date()
            do {
                var req = URLRequest(url: url)
                req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let (_, response) = try await URLSession.shared.data(for: req)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                await MainActor.run {
                    restartResult = status == 200 ? "✓ Reconnected (\(ms)ms)" : "⚠ HTTP \(status) (\(ms)ms)"
                    isRestartingConnection = false
                }
            } catch {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                await MainActor.run {
                    restartResult = "✗ \(error.localizedDescription) (\(ms)ms)"
                    isRestartingConnection = false
                }
            }
        }
    }


    private func checkBackend() {
        let urlString = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api/secrets-check"
        guard let url = URL(string: urlString) else { return }

        isCheckingBackend = true
        backendResult = ""
        Task {
            defer { Task { @MainActor in isCheckingBackend = false } }
            let start = Date()
            do {
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    await MainActor.run {
                        backendResult = "⚠ HTTP \(status) (\(ms)ms)"
                    }
                    return
                }
                let lines = json.sorted(by: { $0.key < $1.key }).compactMap { key, val -> String? in
                    if let dict = val as? [String: Any] {
                        if let present = dict["exists"] as? Bool {
                            return present ? "✓  \(key)" : "✗  \(key)  ← missing"
                        }
                        let inner = dict.sorted(by: { $0.key < $1.key })
                            .map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                        return "\(key): { \(inner) }"
                    } else if let b = val as? Bool {
                        return "\(key): \(b)"
                    } else {
                        return "\(key): \(val)"
                    }
                }
                await MainActor.run {
                    backendResult = lines.joined(separator: "\n") + "\n(\(ms)ms)"
                }
            } catch {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                await MainActor.run {
                    backendResult = "✗ \(error.localizedDescription) (\(ms)ms)"
                }
            }
        }
    }
}
