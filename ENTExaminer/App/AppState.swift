import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    var currentPhase: AppPhase = .idle
    var selectedSection: AppSection = .documents
    var document: ParsedDocument?
    var analysis: DocumentAnalysis?
    var examinationState: ExaminationSessionState?
    var examSummary: ExamSummary?
    var error: AppError?
    var showError: Bool = false
    var showSettings: Bool = false
    var showOnboarding: Bool = false

    // Settings
    var selectedModel: ClaudeModel = .haiku
    var selectedVoiceId: String?

    // Services
    private let documentParser = CompositeDocumentParser()
    private var documentAnalyzer: DocumentAnalyzer?
    private var examinationEngine: ExaminationEngine?

    init() {
        Task {
            let hasAnthropicKey = await KeychainManager.shared.hasKey(account: KeychainManager.anthropicAccount)
            let hasElevenLabsKey = await KeychainManager.shared.hasKey(account: KeychainManager.elevenLabsAccount)
            if !hasAnthropicKey || !hasElevenLabsKey {
                showOnboarding = true
            }
        }
    }

    // MARK: - Document Ingestion

    func loadDocument(from url: URL) async {
        currentPhase = .ingesting(progress: 0.3)
        error = nil

        do {
            let parsed = try await documentParser.parse(url: url)
            document = parsed
            currentPhase = .ingesting(progress: 1.0)

            // Brief pause to show completion
            try await Task.sleep(for: .milliseconds(300))
            currentPhase = .idle
            selectedSection = .documents
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
        guard let document, let analysis else { return }

        let sessionState = ExaminationSessionState()
        examinationState = sessionState
        selectedSection = .examination

        let config = ExamConfiguration(
            model: selectedModel,
            maxQuestions: analysis.suggestedQuestionCount,
            voiceId: selectedVoiceId
        )

        let engine = ExaminationEngine(
            state: sessionState,
            claudeClient: makeClaudeClient(),
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
            currentPhase = .complete
            selectedSection = .results
        } catch let appError as AppError {
            presentError(appError)
            currentPhase = .idle
        } catch {
            presentError(.examinationInterrupted(reason: error.localizedDescription))
            currentPhase = .idle
        }
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
            let summary = await engine.buildSummary()
            examSummary = summary
            currentPhase = .complete
            selectedSection = .results
        }
    }

    func resetForNewExamination() {
        document = nil
        analysis = nil
        examinationState = nil
        examSummary = nil
        examinationEngine = nil
        currentPhase = .idle
        selectedSection = .documents
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
    case documents
    case examination
    case results
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documents: return "Documents"
        case .examination: return "Examination"
        case .results: return "Results"
        case .history: return "History"
        }
    }

    var systemImage: String {
        switch self {
        case .documents: return "doc.text.fill"
        case .examination: return "waveform.circle.fill"
        case .results: return "chart.bar.fill"
        case .history: return "clock.arrow.circlepath"
        }
    }
}
