import SwiftUI
import UniformTypeIdentifiers

struct DocumentLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var showFilePicker = false
    @State private var isDropTargeted = false
    @State private var sortOrder: SortOrder = .dateAdded
    @State private var showImportProgress = false

    enum SortOrder: String, CaseIterable {
        case dateAdded = "Date Added"
        case lastExamined = "Last Examined"
        case title = "Title"
    }

    private var activeDocuments: [LibraryDocument] {
        appState.libraryDocuments
            .filter { !$0.isArchived }
            .filter { doc in
                searchText.isEmpty ||
                doc.title.localizedCaseInsensitiveContains(searchText) ||
                doc.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
            .sorted { lhs, rhs in
                switch sortOrder {
                case .dateAdded:
                    return lhs.addedDate > rhs.addedDate
                case .lastExamined:
                    return (lhs.lastExaminedDate ?? .distantPast) > (rhs.lastExaminedDate ?? .distantPast)
                case .title:
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            if activeDocuments.isEmpty && searchText.isEmpty {
                emptyLibraryView
            } else {
                libraryContent
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileImportResult(result)
        }
        #if os(iOS)
        .sheet(isPresented: $showImportProgress) {
            ImportProgressView()
                .environment(appState)
        }
        .onChange(of: appState.isImporting) { _, newValue in
            if newValue {
                showImportProgress = true
            }
        }
        #endif
        #if os(macOS)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        #endif
    }

    // MARK: - File Import Handling

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        if urls.count == 1 {
            Task { await appState.importDocument(from: urls[0]) }
        } else if urls.count > 1 {
            Task { await appState.importDocuments(from: urls) }
        }
    }

    // MARK: - Empty State

    private var emptyLibraryView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 56))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, value: isDropTargeted)

                Text("Your Document Library")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Drop documents here or browse to add study material.\nMr. Gogarty will examine you on whatever you upload.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("PDF, DOCX, TXT, Markdown, or Image")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            #if os(iOS)
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Browse Files", systemImage: "folder.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityLabel("Browse files to import")

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Import from Cloud", systemImage: "cloud.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityLabel("Import documents from cloud storage")
                }

                if !appState.libraryDocuments.contains(where: { $0.isPreloaded }) {
                    Button("Load Sample Cases") {
                        Task { await appState.loadSampleDocuments() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityLabel("Load sample clinical cases")
                }
            }
            #else
            HStack(spacing: 12) {
                Button("Browse Files") {
                    showFilePicker = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if !appState.libraryDocuments.contains(where: { $0.isPreloaded }) {
                    Button("Load Sample Cases") {
                        Task { await appState.loadSampleDocuments() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            #endif

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .padding(16)
        )
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        VStack(spacing: 0) {
            // Toolbar
            #if os(iOS)
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search documents...", text: $searchText)
                        .textFieldStyle(.plain)
                }

                HStack {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Cloud", systemImage: "cloud.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Import from cloud storage")

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Add Document", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Add Document")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            #else
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search documents...", text: $searchText)
                    .textFieldStyle(.plain)

                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .frame(width: 150)

                Button {
                    showFilePicker = true
                } label: {
                    Label("Add Document", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Add Document")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            #endif

            Divider()

            // Document grid
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: gridMinWidth, maximum: 400), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(activeDocuments) { doc in
                        DocumentCard(document: doc)
                            .environment(appState)
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Helpers

    #if os(macOS)
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await appState.importDocument(from: url)
                }
            }
        }
        return true
    }
    #endif

    private var gridMinWidth: CGFloat {
        #if os(iOS)
        200
        #else
        280
        #endif
    }

    private var supportedTypes: [UTType] {
        [.pdf, .plainText, .png, .jpeg, .tiff,
         UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
         UTType("net.daringfireball.markdown") ?? .plainText]
    }
}

// MARK: - Import Progress View

struct ImportProgressView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var completedCount: Int {
        appState.importingFiles.filter { $0.status == .done }.count
    }

    private var totalCount: Int {
        appState.importingFiles.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Overall progress header
                VStack(spacing: 8) {
                    Text("Importing Documents")
                        .font(.headline)

                    if totalCount > 0 {
                        ProgressView(value: Double(completedCount), total: Double(totalCount))
                            .progressViewStyle(.linear)
                            .accessibilityLabel("Import progress: \(completedCount) of \(totalCount) documents")

                        Text("\(completedCount) of \(totalCount)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // File list
                List {
                    ForEach(appState.importingFiles) { entry in
                        HStack(spacing: 12) {
                            importStatusIcon(for: entry.status)

                            Text(entry.name)
                                .font(.body)
                                .lineLimit(1)

                            Spacer()

                            if case .importing = entry.status {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .accessibilityLabel("\(entry.name), \(accessibilityStatusText(for: entry.status))")
                    }
                }
                .listStyle(.plain)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .disabled(appState.isImporting)
                    .accessibilityLabel("Dismiss import progress")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(appState.isImporting)
    }

    @ViewBuilder
    private func importStatusIcon(for status: ImportFileStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .importing:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func accessibilityStatusText(for status: ImportFileStatus) -> String {
        switch status {
        case .pending: return "pending"
        case .importing: return "importing"
        case .done: return "completed"
        case .failed(let msg): return "failed: \(msg)"
        }
    }
}

// MARK: - Document Card

struct DocumentCard: View {
    @Environment(AppState.self) private var appState
    let document: LibraryDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: document.formatIcon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title)
                        .font(.headline)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(document.format.displayName)
                        Text("\u{00B7}")
                        Text(document.fileSizeFormatted)
                        if let pages = document.pageCount {
                            Text("\u{00B7}")
                            Text("\(pages) pages")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Preview
            if !document.contentPreview.isEmpty {
                Text(document.contentPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // Tags
            if !document.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(document.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }
                    if document.tags.count > 3 {
                        Text("+\(document.tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                if let lastExam = document.lastExaminedDate {
                    Label("Last: \(lastExam, style: .relative) ago", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Not yet examined", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if document.examCount > 0 {
                    Text("\u{00B7} \(document.examCount)x")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Examine") {
                    Task { await appState.selectAndExamine(document) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Examine \(document.title)")
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document: \(document.title)")
        .contextMenu {
            Button("Examine") {
                Task { await appState.selectAndExamine(document) }
            }

            Divider()

            Button("Archive") {
                Task { await appState.archiveDocument(document) }
            }

            Button("Delete", role: .destructive) {
                Task { await appState.deleteDocument(document) }
            }
        }
    }
}
