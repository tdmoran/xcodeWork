import SwiftUI
import UniformTypeIdentifiers

struct DocumentDropView: View {
    @Environment(AppState.self) private var appState
    @State private var isDropTargeted = false
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 24) {
            if let document = appState.document {
                documentPreview(document)
            } else {
                dropZone
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await appState.loadDocument(from: url) }
            }
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.arrow.down.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, value: isDropTargeted)

            Text("Drop your document here")
                .font(.title2)
                .fontWeight(.medium)

            Text("PDF, DOCX, TXT, Markdown, or Image")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)
                .padding(.vertical, 4)

            Button("Browse Files") {
                showFilePicker = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(48)
        .frame(maxWidth: 500)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: isDropTargeted ? StrokeStyle(lineWidth: 2) : StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDropTargeted ? .thickMaterial : .ultraThinMaterial)
        )
        .scaleEffect(isDropTargeted ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Document Preview

    private func documentPreview(_ document: ParsedDocument) -> some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: iconForFormat(document.metadata.format))
                    .font(.title)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.metadata.title ?? document.metadata.url.lastPathComponent)
                        .font(.title3)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        if let pages = document.metadata.pageCount {
                            Text("\(pages) pages")
                        }
                        Text(document.metadata.fileSizeFormatted)
                        Text("\(document.estimatedTokenCount.formatted()) tokens est.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Text preview
            ScrollView {
                Text(String(document.text.prefix(1000)))
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(15)
            }
            .frame(height: 200)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            // Analysis status
            if case .analyzing = appState.currentPhase {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing document...")
                        .foregroundStyle(.secondary)
                }
            } else if let analysis = appState.analysis {
                analysisCard(analysis)
            }

            // Actions
            HStack(spacing: 12) {
                Button("Change Document") {
                    appState.resetForNewExamination()
                }
                .buttonStyle(.bordered)

                if appState.analysis == nil {
                    Button("Analyze Document") {
                        Task { await appState.analyzeDocument() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appState.currentPhase == .analyzing)
                } else {
                    Button("Begin Examination") {
                        Task { await appState.startExamination() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: 600)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func analysisCard(_ analysis: DocumentAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Analysis Complete", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)

            Text(analysis.documentSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 16) {
                Label("\(analysis.topics.count) topics", systemImage: "list.bullet")
                Label("~\(analysis.suggestedQuestionCount) questions", systemImage: "questionmark.circle")
                Label("~\(analysis.estimatedDurationMinutes) min", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(analysis.topics) { topic in
                    Text(topic.name)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                await appState.loadDocument(from: url)
            }
        }

        return true
    }

    private func iconForFormat(_ format: DocumentFormat) -> String {
        switch format {
        case .pdf: return "doc.richtext.fill"
        case .docx: return "doc.fill"
        case .plainText: return "doc.text.fill"
        case .markdown: return "doc.text.fill"
        case .image: return "photo.fill"
        }
    }

    private var supportedTypes: [UTType] {
        [.pdf, .plainText, .png, .jpeg, .tiff,
         UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
         UTType("net.daringfireball.markdown") ?? .plainText]
    }
}

// MARK: - Previews

#if DEBUG
struct DocumentDropView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DocumentDropView()
                .environment(PreviewData.makePreviewAppState())
                .frame(width: 700, height: 500)
                .previewDisplayName("Drop Zone - Empty")

            DocumentDropView()
                .environment(PreviewData.makePreviewAppState(withAnalysis: true))
                .frame(width: 700, height: 600)
                .previewDisplayName("Drop Zone - Document Loaded")
        }
    }
}
#endif

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        let size: CGSize
        let origins: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            origins.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            totalHeight = currentY + rowHeight
        }

        return LayoutResult(size: CGSize(width: maxWidth, height: totalHeight), origins: origins)
    }
}
