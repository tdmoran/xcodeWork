import Foundation
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "ExaminationEngine")

@MainActor
@Observable
final class ExaminationSessionState {
    private(set) var turns: [ExamTurn] = []
    private(set) var currentQuestion: String?
    private(set) var currentTopic: ExamTopic?
    private(set) var isListening: Bool = false
    private(set) var isSpeaking: Bool = false
    private(set) var performance: PerformanceSnapshot = .empty
    private(set) var topicScores: [TopicScore] = []
    private(set) var status: ExamStatus = .notStarted
    private(set) var userTranscript: String = ""
    private(set) var examinerAudioLevels: [Float] = Array(repeating: 0, count: 32)
    private(set) var userAudioLevels: [Float] = Array(repeating: 0, count: 32)
    private(set) var elapsedTime: TimeInterval = 0

    func update(
        turns: [ExamTurn]? = nil,
        currentQuestion: String?? = nil,
        currentTopic: ExamTopic?? = nil,
        isListening: Bool? = nil,
        isSpeaking: Bool? = nil,
        performance: PerformanceSnapshot? = nil,
        status: ExamStatus? = nil,
        userTranscript: String? = nil,
        examinerAudioLevels: [Float]? = nil,
        userAudioLevels: [Float]? = nil,
        elapsedTime: TimeInterval? = nil
    ) {
        if let turns { self.turns = turns }
        if let currentQuestion { self.currentQuestion = currentQuestion }
        if let currentTopic { self.currentTopic = currentTopic }
        if let isListening { self.isListening = isListening }
        if let isSpeaking { self.isSpeaking = isSpeaking }
        if let performance {
            self.performance = performance
            self.topicScores = performance.topicScores
        }
        if let status { self.status = status }
        if let userTranscript { self.userTranscript = userTranscript }
        if let examinerAudioLevels { self.examinerAudioLevels = examinerAudioLevels }
        if let userAudioLevels { self.userAudioLevels = userAudioLevels }
        if let elapsedTime { self.elapsedTime = elapsedTime }
    }
}

actor ExaminationEngine {
    private let state: ExaminationSessionState
    private let claudeClient: ClaudeAPIClient
    private let ttsService: TTSService
    private let sttService: STTService
    private let pipelinedSpeaker: PipelinedSpeaker
    private let flowController: FlowController
    private let performanceCalculator: PerformanceCalculator
    private let document: ParsedDocument
    private let analysis: DocumentAnalysis
    private let config: ExamConfiguration

    private var conversationHistory: [ClaudeMessage] = []
    private var allTurns: [ExamTurn] = []
    private var timerTask: Task<Void, Never>?
    private var startTime: Date?

    init(
        state: ExaminationSessionState,
        claudeClient: ClaudeAPIClient,
        ttsService: TTSService,
        sttService: STTService,
        document: ParsedDocument,
        analysis: DocumentAnalysis,
        config: ExamConfiguration
    ) {
        self.state = state
        self.claudeClient = claudeClient
        self.ttsService = ttsService
        self.sttService = sttService
        // ElevenLabs voice: "Rachel" (clear, professional female voice)
        self.pipelinedSpeaker = PipelinedSpeaker(ttsService: ttsService, voiceId: config.voiceId ?? "21m00Tcm4TlvDq8ikWAM")
        self.flowController = FlowController()
        self.performanceCalculator = PerformanceCalculator()
        self.document = document
        self.analysis = analysis
        self.config = config
    }

    func startExamination() async throws {
        logger.info("Starting examination with \(self.config.model.displayName)")

        startTime = Date()
        startTimer()

        await state.update(status: .askingQuestion)

        // Speak introduction
        try await speakIntroduction()

        // Run the examination loop
        while allTurns.count < config.maxQuestions {
            let currentPerformance = await state.performance
            let action = flowController.decideNextAction(
                analysis: analysis,
                completedTurns: allTurns,
                topicScores: currentPerformance.topicScores,
                maxQuestions: config.maxQuestions
            )

            guard case .wrapUp = action else {
                // Generate and ask question, then process answer
                try await processAction(action)
                continue
            }

            break
        }

        timerTask?.cancel()
        await state.update(status: .finished)
        logger.info("Examination complete: \(self.allTurns.count) questions asked")
    }

    func pause() async {
        timerTask?.cancel()
        await state.update(status: .paused)
    }

    func resume() async {
        startTimer()
        await state.update(status: .askingQuestion)
    }

    func stop() async {
        timerTask?.cancel()
        await ttsService.stopSpeaking()
        await sttService.stopListening()
        await state.update(status: .finished)
    }

    func buildSummary() async -> ExamSummary {
        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let perf = await state.performance

        return ExamSummary(
            turns: allTurns,
            overallScore: perf.overallScore,
            topicScores: perf.topicScores,
            totalDuration: elapsed,
            documentTitle: document.metadata.title ?? document.metadata.url.lastPathComponent,
            modelUsed: config.model
        )
    }

    // MARK: - Private

    private func speakIntroduction() async throws {
        let intro = "Welcome to your examination on \(analysis.documentSummary)."

        let capturedState = state
        await capturedState.update(currentQuestion: .some(intro), isSpeaking: true)

        try await ttsService.speak(
            text: intro,
            voiceId: config.voiceId ?? "21m00Tcm4TlvDq8ikWAM",
            onAudioLevel: { @Sendable level in
                Task { @MainActor in
                    let levels = Self.buildLevelsArray(from: level)
                    capturedState.update(examinerAudioLevels: levels)
                }
            }
        )

        await capturedState.update(isSpeaking: false)

        // Brief pause before first question
        try await Task.sleep(for: .seconds(1))
    }

    private func processAction(_ action: FlowController.NextAction) async throws {
        let (topic, questionPrompt) = buildQuestionPrompt(for: action)

        await state.update(currentTopic: .some(topic), status: .askingQuestion)

        // Generate question stream via Claude and pipe through TTS sentence-by-sentence
        let stream = generateQuestionStream(prompt: questionPrompt)

        let capturedState = state

        await capturedState.update(isSpeaking: true)

        let question = try await pipelinedSpeaker.speakStream(
            stream,
            onAudioLevel: { @Sendable level in
                Task { @MainActor in
                    let levels = Self.buildLevelsArray(from: level)
                    capturedState.update(examinerAudioLevels: levels)
                }
            }
        )

        await capturedState.update(currentQuestion: .some(question), isSpeaking: false)

        // Record the assistant message in conversation history
        let userMessage = ClaudeMessage(
            role: .user,
            content: [.text(questionPrompt)]
        )
        conversationHistory = conversationHistory + [
            userMessage,
            ClaudeMessage(role: .assistant, content: [.text(question)])
        ]

        // Listen for user answer via STT
        await capturedState.update(isListening: true, status: .listeningForAnswer)

        let userAnswer = try await sttService.listen(
            onPartialTranscript: { @Sendable partial in
                Task { @MainActor in
                    capturedState.update(userTranscript: partial)
                }
            },
            onAudioLevel: { @Sendable level in
                Task { @MainActor in
                    let levels = Self.buildLevelsArray(from: level)
                    capturedState.update(userAudioLevels: levels)
                }
            }
        )

        await capturedState.update(isListening: false, userTranscript: userAnswer)

        // Evaluate the answer
        await capturedState.update(status: .evaluatingAnswer)
        let evaluation = try await evaluateAnswer(question: question, answer: userAnswer, topic: topic)

        // Record the turn
        let turn = ExamTurn(
            questionIndex: allTurns.count,
            topic: topic,
            question: question,
            userAnswer: userAnswer,
            evaluation: evaluation
        )
        allTurns = allTurns + [turn]

        // Update performance
        let performance = performanceCalculator.computeSnapshot(
            turns: allTurns,
            analysis: analysis,
            maxQuestions: config.maxQuestions
        )
        await capturedState.update(turns: allTurns, performance: performance, status: .transitioning)

        // Brief pause between turns
        try await Task.sleep(for: .milliseconds(800))
    }

    private func buildQuestionPrompt(for action: FlowController.NextAction) -> (ExamTopic, String) {
        switch action {
        case .askQuestion(let topic, let difficulty, let context):
            return (topic, """
                Ask a \(difficulty.rawValue)-level question about "\(topic.name)".
                Key concepts to test: \(topic.keyConcepts.joined(separator: ", ")).
                Context: \(context)
                """)

        case .clarifyMisunderstanding(let topic, let misconception):
            return (topic, """
                The examinee seems to have misunderstood something about "\(topic.name)".
                They missed: \(misconception).
                Ask a gentle clarifying question to help them reconsider.
                """)

        case .deeperDive(let topic, let subtopic):
            return (topic, """
                The examinee is doing well on "\(topic.name)".
                Ask a deeper question specifically about the subtopic: "\(subtopic)".
                """)

        case .transitionTopic(_, let to):
            return (to, """
                Transition to a new topic: "\(to.name)".
                Briefly acknowledge the previous topic, then ask an opening question about \(to.name).
                Key concepts: \(to.keyConcepts.joined(separator: ", ")).
                """)

        case .wrapUp:
            let topic = analysis.topics.first ?? ExamTopic(
                name: "General",
                importance: 1.0,
                keyConcepts: [],
                difficulty: .intermediate,
                subtopics: []
            )
            return (topic, "Provide a brief summary and a final comprehensive question spanning multiple topics.")
        }
    }

    /// Returns the Claude streaming response as an `AsyncThrowingStream` so that
    /// `PipelinedSpeaker` can consume text deltas sentence-by-sentence for TTS.
    private func generateQuestionStream(
        prompt: String
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        let systemPrompt = buildSystemPrompt()

        let userMessage = ClaudeMessage(
            role: .user,
            content: [.text(prompt)]
        )

        return claudeClient.stream(
            model: config.model,
            system: systemPrompt,
            messages: conversationHistory + [userMessage],
            maxTokens: 512
        )
    }

    private func evaluateAnswer(question: String, answer: String, topic: ExamTopic) async throws -> TurnEvaluation {
        let evalPrompt = """
        Evaluate this examination answer.

        Question: \(question)
        Topic: \(topic.name)
        Key concepts: \(topic.keyConcepts.joined(separator: ", "))
        Examinee's answer: \(answer)

        Respond with ONLY valid JSON matching this structure:
        {
            "correctnessScore": 0.0-1.0,
            "completenessScore": 0.0-1.0,
            "clarityScore": 0.0-1.0,
            "keyPointsCovered": ["point1"],
            "keyPointsMissed": ["point1"],
            "feedback": "Brief natural feedback",
            "followUpSuggestion": "moveToNextTopic"
        }

        followUpSuggestion must be one of: deeperOnSameTopic, moveToNextTopic, clarifyMisunderstanding, congratulateAndAdvance
        """

        let retryHandler = RetryHandler()
        let response = try await retryHandler.execute {
            try await claudeClient.complete(
                model: config.model,
                system: "You are a fair examination evaluator. Return only valid JSON.",
                messages: [ClaudeMessage(role: .user, content: [.text(evalPrompt)])],
                maxTokens: 1024
            )
        }

        guard let jsonText = response.textContent.data(using: .utf8) else {
            throw AppError.apiResponseInvalid(detail: "Empty evaluation response")
        }

        // Extract JSON from potential code blocks
        var cleaned = response.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")
        }

        guard let cleanData = cleaned.data(using: .utf8) else {
            throw AppError.apiResponseInvalid(detail: "Could not parse evaluation")
        }

        return try JSONDecoder().decode(TurnEvaluation.self, from: cleanData)
    }

    private func buildSystemPrompt() -> String {
        """
        You are an expert document examiner conducting a spoken oral examination. \
        You are examining someone on the following document:

        Document Summary: \(analysis.documentSummary)

        Topics covered: \(analysis.topics.map(\.name).joined(separator: ", "))

        Rules:
        - Ask clear, conversational questions — this is a spoken exam, not a written quiz
        - One question at a time
        - Keep questions concise (1-3 sentences max)
        - Be encouraging but rigorous
        - Adapt difficulty based on performance
        - Sound natural and professional, like an experienced oral examiner
        """
    }

    private func startTimer() {
        timerTask = Task { [weak state] in
            guard let state else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let elapsed = Date().timeIntervalSince(self.startTime ?? Date())
                await state.update(elapsedTime: elapsed)
            }
        }
    }

    /// Builds a 32-element audio level array from a single scalar level value.
    /// The scalar is distributed across bands with slight variation to produce
    /// a natural-looking waveform visualization.
    private static func buildLevelsArray(from level: Float) -> [Float] {
        let bandCount = 32
        let clamped = max(0, min(1, level))
        return (0..<bandCount).map { band in
            // Slight sinusoidal variation per band for a natural waveform look
            let variation = Float(sin(Double(band) * 0.4)) * 0.15
            return max(0, min(1, clamped + variation * clamped))
        }
    }
}
