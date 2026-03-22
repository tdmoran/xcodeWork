import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct DocumentDetailView: View {
    @Environment(AppState.self) private var appState
    let document: LibraryDocument

    @State private var selectedExamMode: ExamMode = .conversational
    @State private var previousSessions: [ExamSessionRecord] = []
    #if os(iOS)
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                documentStatsSection
                contentPreviewSection
                analysisSection
                previousSessionsSection
                examHistorySection
                actionSection
            }
            #if os(iOS)
            .padding(16)
            #else
            .padding(32)
            #endif
        }
        .task {
            await loadPreviousSessions()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: document.formatIcon)
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 6) {
                Text(document.title)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 12) {
                    Label(document.format.displayName, systemImage: "doc")
                    Label(document.fileSizeFormatted, systemImage: "internaldrive")
                    if let pages = document.pageCount {
                        Label("\(pages) pages", systemImage: "book.pages")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label("Added \(document.addedDate, style: .date)", systemImage: "calendar")
                    if document.examCount > 0 {
                        Label("Examined \(document.examCount) time\(document.examCount == 1 ? "" : "s")", systemImage: "checkmark.circle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }

    // MARK: - Document Stats

    private var documentStatsSection: some View {
        Group {
            if let parsedDoc = appState.document {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Document Stats")
                        .font(.headline)

                    HStack(spacing: 24) {
                        statItem(
                            label: "Characters",
                            value: parsedDoc.characterCount.formatted(),
                            icon: "textformat.abc"
                        )
                        statItem(
                            label: "Est. Tokens",
                            value: parsedDoc.estimatedTokenCount.formatted(),
                            icon: "number"
                        )
                        statItem(
                            label: "Sections",
                            value: "\(parsedDoc.sections.count)",
                            icon: "list.bullet.rectangle"
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func statItem(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
    }

    // MARK: - Content Preview

    private var contentPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content Preview")
                .font(.headline)

            if let parsedDoc = appState.document, !parsedDoc.text.isEmpty {
                ScrollView {
                    Text(String(parsedDoc.text.prefix(2000)))
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else if !document.contentPreview.isEmpty {
                Text(document.contentPreview)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Analysis

    private var analysisSection: some View {
        Group {
            if case .analyzing = appState.currentPhase {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing document...")
                        .foregroundStyle(.secondary)
                }
            } else if let analysis = appState.analysis {
                VStack(alignment: .leading, spacing: 12) {
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
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Previous Sessions

    private var previousSessionsSection: some View {
        Group {
            if !previousSessions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Previous Sessions")
                        .font(.headline)

                    ForEach(previousSessions) { session in
                        sessionRow(session)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func sessionRow(_ session: ExamSessionRecord) -> some View {
        HStack(spacing: 12) {
            scoreCircle(session.overallScore)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.date, style: .date)
                    .font(.callout)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(formatDuration(session.duration))
                    Text("\(session.topicsCovered.count) topics")
                    Text(session.modelUsed)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(scoreLabel(session.overallScore))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(scoreColor(session.overallScore))
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func scoreCircle(_ score: Double) -> some View {
        ZStack {
            Circle()
                .stroke(scoreColor(score).opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: score)
                .stroke(scoreColor(score), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(score * 100))")
                .font(.caption2)
                .fontWeight(.bold)
        }
        .frame(width: 36, height: 36)
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 0.75...: return .green
        case 0.5..<0.75: return .orange
        default: return .red
        }
    }

    private func scoreLabel(_ score: Double) -> String {
        switch score {
        case 0.9...: return "Excellent"
        case 0.75..<0.9: return "Good"
        case 0.6..<0.75: return "Satisfactory"
        case 0.4..<0.6: return "Needs Work"
        default: return "Poor"
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Exam History

    private var examHistorySection: some View {
        Group {
            if document.examCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Examination History")
                        .font(.headline)

                    if let lastDate = document.lastExaminedDate {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                            Text("Last examined \(lastDate, style: .relative) ago")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("\(document.examCount) session\(document.examCount == 1 ? "" : "s") completed")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(spacing: 16) {
            if appState.analysis != nil {
                examModePicker
            }

            #if os(iOS)
            VStack(spacing: 10) {
                if appState.analysis == nil {
                    Button("Analyze Document") {
                        Task { await appState.analyzeDocument() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(appState.currentPhase == .analyzing)
                } else {
                    Button(examButtonTitle) {
                        Task { await startSelectedExam() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Examine")
                }

                HStack(spacing: 10) {
                    if hasExportableSummary {
                        Button {
                            if let url = appState.saveTranscriptToFile(asMarkdown: true) {
                                shareURL = url
                                showShareSheet = true
                            }
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Export transcript")
                    }

                    Button("Back to Library") {
                        appState.selectedSection = .library
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Back to Library")
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let shareURL {
                    ShareSheet(activityItems: [shareURL])
                }
            }
            #else
            HStack(spacing: 12) {
                if appState.analysis == nil {
                    Button("Analyze Document") {
                        Task { await appState.analyzeDocument() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appState.currentPhase == .analyzing)
                } else {
                    Button(examButtonTitle) {
                        Task { await startSelectedExam() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityLabel("Examine")
                }

                if hasExportableSummary {
                    Button {
                        if let url = appState.saveTranscriptToFile(asMarkdown: true) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityLabel("Export transcript")
                }

                Button("Back to Library") {
                    appState.selectedSection = .library
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Back to Library")
            }
            #endif
        }
    }

    private var examModePicker: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 8) {
            Text("Exam Mode:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Exam Mode", selection: $selectedExamMode) {
                ForEach(ExamMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        #else
        HStack(spacing: 16) {
            Text("Exam Mode:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Exam Mode", selection: $selectedExamMode) {
                ForEach(ExamMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
        }
        #endif
    }

    private var examButtonTitle: String {
        switch selectedExamMode {
        case .conversational:
            return "Begin Conversation"
        case .questionAndAnswer:
            return "Begin Q&A Exam"
        }
    }

    private var hasExportableSummary: Bool {
        appState.examSummary != nil || appState.dialogueSummary != nil
    }

    private func startSelectedExam() async {
        switch selectedExamMode {
        case .conversational:
            await appState.startConversation()
        case .questionAndAnswer:
            await appState.startExamination()
        }
    }

    // MARK: - Data Loading

    private func loadPreviousSessions() async {
        do {
            let allSessions = try await DocumentStore.shared.loadSessions()
            previousSessions = allSessions
                .filter { $0.documentId == document.id }
                .sorted { $0.date > $1.date }
        } catch {
            previousSessions = []
        }
    }
}

// MARK: - Exam Mode

enum ExamMode: String, CaseIterable, Identifiable {
    case conversational
    case questionAndAnswer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conversational: return "Conversational"
        case .questionAndAnswer: return "Q&A"
        }
    }

    var icon: String {
        switch self {
        case .conversational: return "bubble.left.and.bubble.right"
        case .questionAndAnswer: return "list.number"
        }
    }
}

// MARK: - Share Sheet

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
