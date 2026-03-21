import SwiftUI
import UniformTypeIdentifiers

struct DocumentLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var showFilePicker = false
    @State private var isDropTargeted = false
    @State private var sortOrder: SortOrder = .dateAdded

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
            if case .success(let urls) = result {
                for url in urls {
                    Task { await appState.importDocument(from: url) }
                }
            }
        }
        #if os(macOS)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        #endif
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // Document grid
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)],
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

    private var supportedTypes: [UTType] {
        [.pdf, .plainText, .png, .jpeg, .tiff,
         UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
         UTType("net.daringfireball.markdown") ?? .plainText]
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
                        Text("·")
                        Text(document.fileSizeFormatted)
                        if let pages = document.pageCount {
                            Text("·")
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
                    Text("· \(document.examCount)x")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Examine") {
                    Task { await appState.selectAndExamine(document) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
