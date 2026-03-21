import Foundation
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.examiner", category: "AppState")

private func debugLog(_ message: String) {
    let url = URL(fileURLWithPath: "/tmp/entexaminer_debug.log")
    let line = "\(Date()): \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: url)
        }
    }
}

@MainActor
@Observable
final class AppState {
    var currentPhase: AppPhase = .idle
    var selectedSection: AppSection = .library
    var error: AppError?
    var showError: Bool = false
    var showSettings: Bool = false
    var showOnboarding: Bool = false

    // Document library
    var libraryDocuments: [LibraryDocument] = []
    var selectedLibraryDocument: LibraryDocument?

    // Current examination context
    var document: ParsedDocument?
    var analysis: DocumentAnalysis?
    var examinationState: ExaminationSessionState?
    var examSummary: ExamSummary?
    var dialogueSummary: DialogueSummary?
    var selectedCase: ClinicalCase?

    // Settings
    var selectedModel: ClaudeModel = .haiku
    var selectedVoiceId: String?

    // Services
    private let documentParser = CompositeDocumentParser()
    private let webFetcher = WebDocumentFetcher()
    private let audioPipeline = AudioPipeline()
    private var documentAnalyzer: DocumentAnalyzer?
    private var examinationEngine: ExaminationEngine?

    init() {
        Task {
            let hasAnthropicKey = await KeychainManager.shared.hasKey(account: KeychainManager.anthropicAccount)
            let hasElevenLabsKey = await KeychainManager.shared.hasKey(account: KeychainManager.elevenLabsAccount)
            debugLog("init: hasAnthropicKey=\(hasAnthropicKey), hasElevenLabsKey=\(hasElevenLabsKey)")
            if !hasAnthropicKey || !hasElevenLabsKey {
                showOnboarding = true
                debugLog("init: showing onboarding because keys missing")
            } else {
                debugLog("init: keys found, skipping onboarding")
            }

            // Load persisted library
            await loadLibrary()
        }
    }

    // MARK: - Library Management

    private func loadLibrary() async {
        do {
            let docs = try await DocumentStore.shared.loadLibrary()
            libraryDocuments = docs
            logger.info("Loaded \(docs.count) documents from library")
        } catch {
            logger.warning("Failed to load library: \(error.localizedDescription)")
            libraryDocuments = []
        }
    }

    private func persistLibrary() {
        Task {
            do {
                try await DocumentStore.shared.saveLibrary(libraryDocuments)
            } catch {
                debugLog("Failed to persist library: \(error.localizedDescription)")
            }
        }
    }

    /// Imports a document from a file URL into the library.
    func importDocument(from url: URL) async {
        currentPhase = .ingesting(progress: 0.2)
        error = nil

        do {
            // Parse the document content
            let parsed = try await documentParser.parse(url: url)
            currentPhase = .ingesting(progress: 0.6)

            // Import file into library storage
            let docId = UUID()
            let storedName = try await DocumentStore.shared.importFile(from: url, documentId: docId)
            currentPhase = .ingesting(progress: 0.9)

            // Cache extracted text for future use
            await DocumentStore.shared.cacheText(parsed.text, for: parsed.contentHash)

            let title = parsed.metadata.title ?? url.deletingPathExtension().lastPathComponent
            let preview = String(parsed.text.prefix(500))

            let libraryDoc = LibraryDocument(
                id: docId,
                title: title,
                sourceFileName: storedName,
                format: parsed.metadata.format,
                fileSize: parsed.metadata.fileSize,
                pageCount: parsed.metadata.pageCount,
                addedDate: Date(),
                contentPreview: preview
            )

            libraryDocuments = libraryDocuments + [libraryDoc]
            persistLibrary()

            currentPhase = .idle
            logger.info("Imported document: \(title)")
        } catch let appError as AppError {
            presentError(appError)
            currentPhase = .idle
        } catch {
            presentError(.parseFailure(error.localizedDescription))
            currentPhase = .idle
        }
    }

    /// Selects a library document for examination.
    func selectAndExamine(_ libraryDoc: LibraryDocument) async {
        selectedLibraryDocument = libraryDoc
        currentPhase = .ingesting(progress: 0.3)

        do {
            // Load and parse the file from the store
            let fileURL = await DocumentStore.shared.fileURL(for: libraryDoc)
            let parsed = try await documentParser.parse(url: fileURL)
            document = parsed
            currentPhase = .ingesting(progress: 0.7)

            // Auto-analyze
            currentPhase = .analyzing
            let client = makeClaudeClient()
            let analyzer = DocumentAnalyzer(client: client)
            documentAnalyzer = analyzer
            let result = try await analyzer.analyze(document: parsed, model: selectedModel)
            analysis = result

            currentPhase = .idle
            selectedSection = .documentDetail
        } catch let appError as AppError {
            presentError(appError)
            currentPhase = .idle
        } catch {
            presentError(.apiResponseInvalid(detail: error.localizedDescription))
            currentPhase = .idle
        }
    }

    /// Archives a document (moves to archive folder).
    func archiveDocument(_ libraryDoc: LibraryDocument) async {
        do {
            try await DocumentStore.shared.archiveFile(for: libraryDoc)

            libraryDocuments = libraryDocuments.map { doc in
                doc.id == libraryDoc.id ? doc.withArchiveStatus(true) : doc
            }
            persistLibrary()
        } catch {
            presentError(.parseFailure("Failed to archive: \(error.localizedDescription)"))
        }
    }

    /// Restores a document from archive.
    func restoreDocument(_ libraryDoc: LibraryDocument) async {
        do {
            try await DocumentStore.shared.restoreFile(for: libraryDoc)

            libraryDocuments = libraryDocuments.map { doc in
                doc.id == libraryDoc.id ? doc.withArchiveStatus(false) : doc
            }
            persistLibrary()
        } catch {
            presentError(.parseFailure("Failed to restore: \(error.localizedDescription)"))
        }
    }

    /// Permanently deletes a document.
    func deleteDocument(_ libraryDoc: LibraryDocument) async {
        do {
            try await DocumentStore.shared.deleteFile(for: libraryDoc)
            libraryDocuments = libraryDocuments.filter { $0.id != libraryDoc.id }
            persistLibrary()
        } catch {
            presentError(.parseFailure("Failed to delete: \(error.localizedDescription)"))
        }
    }

    /// Loads pre-built ENT cases as sample documents into the library.
    func loadSampleDocuments() async {
        let cases = CaseBank.allCases

        for clinicalCase in cases {
            let content = buildCaseContent(clinicalCase)
            let docId = clinicalCase.id

            let libraryDoc = LibraryDocument(
                id: docId,
                title: clinicalCase.title,
                sourceFileName: "\(docId.uuidString).txt",
                format: .plainText,
                fileSize: Int64(content.utf8.count),
                pageCount: 1,
                tags: clinicalCase.tags,
                addedDate: Date(),
                isPreloaded: true,
                contentPreview: String(content.prefix(500))
            )

            // Write content to library storage
            let fileURL = await DocumentStore.shared.fileURL(for: libraryDoc)

            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                logger.warning("Failed to write sample case \(clinicalCase.title): \(error.localizedDescription)")
                continue
            }

            libraryDocuments = libraryDocuments + [libraryDoc]
        }

        persistLibrary()
        logger.info("Loaded \(cases.count) sample documents")
    }

    private func buildCaseContent(_ clinicalCase: ClinicalCase) -> String {
        var sections: [String] = []
        sections.append("# \(clinicalCase.title)")
        sections.append("")
        sections.append("## Clinical Vignette")
        sections.append(clinicalCase.clinicalVignette)
        sections.append("")

        if !clinicalCase.keyHistoryPoints.isEmpty {
            sections.append("## Key History Points")
            for point in clinicalCase.keyHistoryPoints {
                sections.append("- \(point)")
            }
            sections.append("")
        }

        if !clinicalCase.examinationFindings.isEmpty {
            sections.append("## Examination Findings")
            for finding in clinicalCase.examinationFindings {
                sections.append("- \(finding)")
            }
            sections.append("")
        }

        if !clinicalCase.investigations.isEmpty {
            sections.append("## Investigations")
            for investigation in clinicalCase.investigations {
                sections.append("- \(investigation)")
            }
            sections.append("")
        }

        if !clinicalCase.managementPlan.isEmpty {
            sections.append("## Management Plan")
            for step in clinicalCase.managementPlan {
                sections.append("- \(step)")
            }
            sections.append("")
        }

        if !clinicalCase.criticalPoints.isEmpty {
            sections.append("## Critical Points")
            for point in clinicalCase.criticalPoints {
                sections.append("- \(point)")
            }
            sections.append("")
        }

        if !clinicalCase.teachingNotes.isEmpty {
            sections.append("## Teaching Notes")
            sections.append(clinicalCase.teachingNotes)
        }

        return sections.joined(separator: "\n")
    }

    // MARK: - Web URL Import

    func importWebURL(_ urlString: String) async {
        currentPhase = .ingesting(progress: 0.2)
        error = nil

        do {
            let parsed = try await webFetcher.fetch(urlString: urlString)
            currentPhase = .ingesting(progress: 0.7)

            // Cache extracted text
            await DocumentStore.shared.cacheText(parsed.text, for: parsed.contentHash)

            let docId = UUID()
            let title = parsed.metadata.title ?? urlString
            let preview = String(parsed.text.prefix(500))

            // Save web content as a text file in the library
            let storedName = "\(docId.uuidString).txt"
            let libraryDoc = LibraryDocument(
                id: docId,
                title: title,
                sourceFileName: storedName,
                format: .webURL,
                fileSize: parsed.metadata.fileSize,
                pageCount: nil,
                addedDate: Date(),
                contentPreview: preview
            )

            let fileURL = await DocumentStore.shared.fileURL(for: libraryDoc)
            try parsed.text.write(to: fileURL, atomically: true, encoding: .utf8)

            libraryDocuments = libraryDocuments + [libraryDoc]
            persistLibrary()

            currentPhase = .idle
            logger.info("Imported web document: \(title)")
        } catch let appError as AppError {
            presentError(appError)
            currentPhase = .idle
        } catch {
            presentError(.parseFailure(error.localizedDescription))
            currentPhase = .idle
        }
    }

    // MARK: - Transcript Export

    func exportTranscript(asMarkdown: Bool = false) -> String? {
        if let dSummary = dialogueSummary {
            return asMarkdown
                ? TranscriptExporter.exportAsMarkdown(from: dSummary)
                : TranscriptExporter.exportAsText(from: dSummary)
        } else if let summary = examSummary {
            return asMarkdown
                ? TranscriptExporter.exportAsMarkdown(from: summary)
                : TranscriptExporter.exportAsText(from: summary)
        }
        return nil
    }

    func saveTranscriptToFile(asMarkdown: Bool = false) -> URL? {
        guard let content = exportTranscript(asMarkdown: asMarkdown) else { return nil }
        let ext = asMarkdown ? "md" : "txt"
        let title = selectedLibraryDocument?.title ?? "Examination"
        let sanitized = title.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let filename = "\(sanitized)_transcript.\(ext)"
        return try? TranscriptExporter.saveToFile(content: content, filename: filename)
    }

    // MARK: - Document Ingestion (legacy — still used by drag-and-drop on ContentView)

    func loadDocument(from url: URL) async {
        currentPhase = .ingesting(progress: 0.3)
        error = nil

        do {
            let parsed = try await documentParser.parse(url: url)
            document = parsed
            currentPhase = .ingesting(progress: 1.0)

            try await Task.sleep(for: .milliseconds(300))
            currentPhase = .idle
            selectedSection = .documentDetail
        } catch let appError as AppError {
            presentError(appError)
            currentPhase = .idle
        } catch {
            presentError(.parseFailure(error.localizedDescription))
            currentPhase = .idle
        }
    }

    // MARK: - Document Analysis

    func analyzeDocument() async {
        guard let document else { return }

        currentPhase = .analyzing

        let client = makeClaudeClient()
        let analyzer = DocumentAnalyzer(client: client)
        self.documentAnalyzer = analyzer

        do {
            let result = try await analyzer.analyze(document: document, model: selectedModel)
            analysis = result
            currentPhase = .idle
        } catch let appError as AppError {
            presentError(appError)
            currentPhase = .idle
        } catch {
            presentError(.apiResponseInvalid(detail: error.localizedDescription))
            currentPhase = .idle
        }
    }

    // MARK: - Examination

    func startExamination() async {
        guard let document, let analysis else {
            debugLog("startExamination: document or analysis is nil, returning")
            return
        }
        debugLog("startExamination: starting with document")

        let sessionState = ExaminationSessionState()
        examinationState = sessionState
        selectedSection = .examination

        let config = ExamConfiguration(
            model: selectedModel,
            maxQuestions: analysis.suggestedQuestionCount,
            voiceId: selectedVoiceId
        )

        let ttsService = ElevenLabsTTSService(
            apiKeyProvider: { @Sendable in
                try? await KeychainManager.shared.retrieve(account: KeychainManager.elevenLabsAccount)
            },
            audioPipeline: audioPipeline
        )

        let sttService = AppleSpeechSTTService(audioPipeline: audioPipeline)

        let engine = ExaminationEngine(
            state: sessionState,
            claudeClient: makeClaudeClient(),
            ttsService: ttsService,
            sttService: sttService,
            document: document,
            analysis: analysis,
            config: config
        )
        examinationEngine = engine

        currentPhase = .examining

        do {
            try await engine.startExamination()
            let summary = await engine.buildSummary()
            examSummary = summary
            recordExamSession(score: summary.overallScore, topics: summary.topicScores.map(\.topicName), duration: summary.totalDuration)
            currentPhase = .complete
            selectedSection = .results
        } catch let appError as AppError {
            debugLog("startExamination error: \(appError.localizedDescription)")
            presentError(appError)
            currentPhase = .idle
        } catch {
            debugLog("startExamination unexpected error: \(error.localizedDescription)")
            presentError(.examinationInterrupted(reason: error.localizedDescription))
            currentPhase = .idle
        }
    }

    /// Starts a conversational Socratic examination using the current document.
    func startConversation() async {
        guard let document, let analysis else {
            debugLog("startConversation: document or analysis is nil, returning")
            return
        }
        debugLog("startConversation: starting with document")

        let sessionState = ExaminationSessionState()
        examinationState = sessionState
        selectedSection = .examination

        let config = ExamConfiguration(
            model: selectedModel,
            maxQuestions: analysis.suggestedQuestionCount,
            voiceId: selectedVoiceId
        )

        let ttsService = ElevenLabsTTSService(
            apiKeyProvider: { @Sendable in
                try? await KeychainManager.shared.retrieve(account: KeychainManager.elevenLabsAccount)
            },
            audioPipeline: audioPipeline
        )

        let sttService = AppleSpeechSTTService(audioPipeline: audioPipeline)

        let engine = ExaminationEngine(
            state: sessionState,
            claudeClient: makeClaudeClient(),
            ttsService: ttsService,
            sttService: sttService,
            document: document,
            analysis: analysis,
            config: config
        )
        examinationEngine = engine

        currentPhase = .examining

        do {
            debugLog("calling engine.startConversation()")
            try await engine.startConversation()
            debugLog("engine.startConversation() completed")
            let summary = await engine.buildDialogueSummary()
            dialogueSummary = summary
            examSummary = summary.asLegacySummary()
            recordExamSession(score: summary.overallScore, topics: summary.topicScores.map(\.topicName), duration: summary.totalDuration)
            currentPhase = .complete
            selectedSection = .results
        } catch let appError as AppError {
            debugLog("startConversation AppError: \(appError.localizedDescription)")
            presentError(appError)
            currentPhase = .idle
        } catch {
            debugLog("startConversation error: \(error.localizedDescription)")
            presentError(.examinationInterrupted(reason: error.localizedDescription))
            currentPhase = .idle
        }
    }

    /// Starts a conversational examination from a pre-built clinical case.
    func startCaseExamination(_ clinicalCase: ClinicalCase) async {
        debugLog("startCaseExamination: \(clinicalCase.title)")
        let caseAnalysis = clinicalCase.toAnalysis()
        let caseParsedDoc = ParsedDocument(
            text: clinicalCase.clinicalVignette,
            sections: [],
            metadata: FileMetadata(
                url: URL(fileURLWithPath: "/cases/\(clinicalCase.id).txt"),
                title: clinicalCase.title,
                fileSize: Int64(clinicalCase.clinicalVignette.utf8.count),
                pageCount: 1,
                format: .plainText
            ),
            contentHash: clinicalCase.id.uuidString
        )

        selectedCase = clinicalCase
        document = caseParsedDoc
        analysis = caseAnalysis
        await startConversation()
    }

    func handleBargeIn() async {
        await examinationEngine?.handleBargeIn()
    }

    func pauseExamination() async {
        await examinationEngine?.pause()
    }

    func resumeExamination() async {
        await examinationEngine?.resume()
    }

    func stopExamination() async {
        await examinationEngine?.stop()
        if let engine = examinationEngine {
            if let examState = examinationState, examState.isConversationalMode {
                let dSummary = await engine.buildDialogueSummary()
                dialogueSummary = dSummary
                examSummary = dSummary.asLegacySummary()
            } else {
                let summary = await engine.buildSummary()
                examSummary = summary
            }
            currentPhase = .complete
            selectedSection = .results
        }
    }

    func resetForNewExamination() {
        document = nil
        analysis = nil
        examinationState = nil
        examSummary = nil
        dialogueSummary = nil
        selectedCase = nil
        selectedLibraryDocument = nil
        examinationEngine = nil
        currentPhase = .idle
        selectedSection = .library
    }

    // MARK: - Exam Session Recording

    private func recordExamSession(score: Double, topics: [String], duration: TimeInterval) {
        guard let docId = selectedLibraryDocument?.id else { return }

        // Update document exam count
        libraryDocuments = libraryDocuments.map { doc in
            doc.id == docId ? doc.withExamRecorded() : doc
        }
        persistLibrary()

        // Save session record
        let record = ExamSessionRecord(
            id: UUID(),
            documentId: docId,
            date: Date(),
            duration: duration,
            overallScore: score,
            topicsCovered: topics,
            modelUsed: selectedModel.displayName
        )
        Task {
            try? await DocumentStore.shared.addSession(record)
        }
    }

    // MARK: - Helpers

    private func makeClaudeClient() -> ClaudeAPIClient {
        ClaudeAPIClient(apiKeyProvider: {
            try? await KeychainManager.shared.retrieve(account: KeychainManager.anthropicAccount)
        })
    }

    private func presentError(_ appError: AppError) {
        error = appError
        showError = true
    }
}

// MARK: - App Phase

enum AppPhase: Equatable {
    case idle
    case ingesting(progress: Double)
    case analyzing
    case examining
    case complete
}

// MARK: - Sidebar Sections

enum AppSection: String, CaseIterable, Identifiable {
    case library
    case documentDetail
    case cases
    case examination
    case results
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .documentDetail: return "Document"
        case .cases: return "Sample Cases"
        case .examination: return "Examination"
        case .results: return "Results"
        case .archive: return "Archive"
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .documentDetail: return "doc.text.magnifyingglass"
        case .cases: return "cross.case.fill"
        case .examination: return "waveform.circle.fill"
        case .results: return "chart.bar.fill"
        case .archive: return "archivebox.fill"
        }
    }

    /// Sections shown in the sidebar.
    static var sidebarSections: [AppSection] {
        [.library, .cases, .examination, .results, .archive]
    }
}
