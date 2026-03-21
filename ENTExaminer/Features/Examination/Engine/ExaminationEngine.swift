import Foundation
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "ExaminationEngine")

private func engineLog(_ message: String) {
    let url = URL(fileURLWithPath: "/tmp/entexaminer_engine.log")
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

    // Conversational mode state
    private(set) var dialogueMessages: [DialogueMessage] = []
    private(set) var conversationContext: ConversationContext = .empty
    private(set) var isConversationalMode: Bool = false

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
        elapsedTime: TimeInterval? = nil,
        dialogueMessages: [DialogueMessage]? = nil,
        conversationContext: ConversationContext? = nil,
        isConversationalMode: Bool? = nil
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
        if let dialogueMessages { self.dialogueMessages = dialogueMessages }
        if let conversationContext { self.conversationContext = conversationContext }
        if let isConversationalMode { self.isConversationalMode = isConversationalMode }
    }
}

actor ExaminationEngine {
    private let state: ExaminationSessionState
    private let claudeClient: ClaudeAPIClient
    private let ttsService: TTSService
    private let sttService: STTService
    private let pipelinedSpeaker: PipelinedSpeaker
    private let flowController: FlowController
    private let dialogueFlowController: DialogueFlowController
    private let performanceCalculator: PerformanceCalculator
    private let document: ParsedDocument
    private let analysis: DocumentAnalysis
    private let config: ExamConfiguration

    // Legacy mode state
    private var conversationHistory: [ClaudeMessage] = []
    private var allTurns: [ExamTurn] = []

    // Conversational mode state
    private var dialogueMessages: [DialogueMessage] = []
    private var inlineAssessments: [InlineAssessment] = []
    private var currentTopicTracker: ExamTopic?
    private var depthOnCurrentTopic: Int = 0

    // Shared state
    private var timerTask: Task<Void, Never>?
    private var assessmentTask: Task<Void, Never>?
    private var speakingTask: Task<String, Error>?
    private var startTime: Date?
    private var lastBargeInText: String?

    private let voiceId: String

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
        self.voiceId = config.voiceId ?? "21m00Tcm4TlvDq8ikWAM"
        self.pipelinedSpeaker = PipelinedSpeaker(ttsService: ttsService, voiceId: config.voiceId ?? "21m00Tcm4TlvDq8ikWAM")
        self.flowController = FlowController()
        self.dialogueFlowController = DialogueFlowController()
        self.performanceCalculator = PerformanceCalculator()
        self.document = document
        self.analysis = analysis
        self.config = config
    }

    // MARK: - Legacy Examination Mode

    func startExamination() async throws {
        logger.info("Starting examination with \(self.config.model.displayName)")

        startTime = Date()
        startTimer()

        await state.update(status: .askingQuestion)

        try await speakIntroduction()

        while allTurns.count < config.maxQuestions {
            let currentPerformance = await state.performance
            let action = flowController.decideNextAction(
                analysis: analysis,
                completedTurns: allTurns,
                topicScores: currentPerformance.topicScores,
                maxQuestions: config.maxQuestions
            )

            guard case .wrapUp = action else {
                try await processAction(action)
                continue
            }

            break
        }

        timerTask?.cancel()
        await state.update(status: .finished)
        logger.info("Examination complete: \(self.allTurns.count) questions asked")
    }

    // MARK: - Conversational Examination Mode

    /// Starts a natural Socratic dialogue examination.
    /// Instead of rigid question→answer→evaluate cycles, this creates a flowing
    /// conversation where the examiner responds to what the trainee actually says.
    func startConversation() async throws {
        engineLog("startConversation called with model: \(self.config.model.rawValue)")
        logger.info("Starting conversational examination with \(self.config.model.displayName)")

        startTime = Date()
        startTimer()

        await state.update(
            status: .examinerSpeaking,
            isConversationalMode: true
        )

        // Speak a brief introduction about the topic before starting Q&A
        try await speakIntroductionForConversation()

        // The examiner opens the conversation
        let openingMove = dialogueFlowController.decideNextMove(
            analysis: analysis,
            messages: [],
            context: .empty,
            assessments: []
        )

        try await speakExaminerMove(openingMove)

        // Main conversation loop: listen → assess → think → respond
        while !Task.isCancelled {
            // 1. Listen for trainee's response (with barge-in detection)
            let traineeText = try await listenToTrainee()

            // 2. Check if trainee wants to end the conversation
            if isStopRequest(traineeText) {
                engineLog("Trainee requested stop: \(traineeText.prefix(40))")
                let closingText = "Grand, we'll leave it there. Well done — good session."
                let capturedState = state
                await capturedState.update(currentQuestion: .some(closingText), isSpeaking: true)
                try await ttsService.speak(
                    text: closingText,
                    voiceId: voiceId,
                    onAudioLevel: { @Sendable level in
                        Task { @MainActor in
                            let levels = Self.buildLevelsArray(from: level)
                            capturedState.update(examinerAudioLevels: levels)
                        }
                    }
                )
                await capturedState.update(isSpeaking: false)
                break
            }

            // 3. Record trainee message
            let traineeMessage = DialogueMessage(role: .trainee, content: traineeText)
            dialogueMessages = dialogueMessages + [traineeMessage]
            await updateDialogueState()

            // 4. Assess the exchange in background (non-blocking)
            launchBackgroundAssessment(traineeText: traineeText)

            // 5. Thinking pause — brief natural delay before responding
            await showThinkingPause()

            // 6. Decide the examiner's next conversational move
            let context = buildConversationContext()
            let responseMove = dialogueFlowController.decideNextMove(
                analysis: analysis,
                messages: dialogueMessages,
                context: context,
                assessments: inlineAssessments
            )

            // 7. Speak the response (or close)
            try await speakExaminerMove(responseMove)

            if case .closing = responseMove.intent {
                break
            }
        }

        // Wait for any pending assessment
        assessmentTask?.cancel()
        timerTask?.cancel()
        await state.update(status: .finished)

        logger.info("Conversation complete: \(self.dialogueMessages.count) exchanges")
    }

    // MARK: - Shared Controls

    func pause() async {
        timerTask?.cancel()
        await state.update(status: .paused)
    }

    func resume() async {
        startTimer()
        let isConversational = await state.isConversationalMode
        await state.update(status: isConversational ? .inConversation : .askingQuestion)
    }

    func stop() async {
        timerTask?.cancel()
        assessmentTask?.cancel()
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

    func buildDialogueSummary() async -> DialogueSummary {
        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let perf = await state.performance
        let context = buildConversationContext()

        return DialogueSummary(
            messages: dialogueMessages,
            assessments: inlineAssessments,
            topicDiscussions: context.topicsDiscussed,
            overallScore: perf.overallScore,
            topicScores: perf.topicScores,
            totalDuration: elapsed,
            documentTitle: document.metadata.title ?? document.metadata.url.lastPathComponent,
            modelUsed: config.model
        )
    }

    // MARK: - Conversational Mode: Core Methods

    /// Generates the examiner's spoken response and streams it through TTS.
    /// Supports barge-in: if the trainee starts speaking during examiner speech,
    /// TTS is stopped immediately and the full streamed text is still captured.
    private func speakExaminerMove(_ move: DialogueFlowController.NextMove) async throws {
        let capturedState = state

        // Update topic tracking
        switch move.intent {
        case .openTopic(let topic), .transition(let topic, _):
            currentTopicTracker = topic
            depthOnCurrentTopic = 0
            await capturedState.update(currentTopic: .some(topic))
        default:
            depthOnCurrentTopic += 1
        }

        await capturedState.update(isSpeaking: true, status: .examinerSpeaking)
        lastBargeInText = nil

        // Build the Claude prompt for this conversational move
        engineLog("speakExaminerMove: intent=\(move.intent)")
        let stream = generateConversationalStream(move: move)
        engineLog("Stream created, calling pipelinedSpeaker.speakStream")

        let examinerText = try await pipelinedSpeaker.speakStream(
            stream,
            onAudioLevel: { @Sendable level in
                Task { @MainActor in
                    let levels = Self.buildLevelsArray(from: level)
                    capturedState.update(examinerAudioLevels: levels)
                }
            }
        )

        engineLog("speakStream returned: \(examinerText.prefix(80))")
        let wasInterrupted = await pipelinedSpeaker.wasBargedIn

        await capturedState.update(
            currentQuestion: .some(examinerText),
            isSpeaking: false,
            status: .inConversation
        )

        // Record examiner message (full text even if barged in)
        let examinerMessage = DialogueMessage(
            role: .examiner,
            content: examinerText,
            intent: move.intent
        )
        dialogueMessages = dialogueMessages + [examinerMessage]

        // Update Claude conversation history for context continuity
        conversationHistory = conversationHistory + [
            ClaudeMessage(role: .assistant, content: [.text(examinerText)])
        ]

        await updateDialogueState()

        if wasInterrupted {
            logger.info("Examiner was interrupted by trainee barge-in")
        }
    }

    /// Triggers a barge-in, stopping the examiner's speech so the trainee can speak.
    func handleBargeIn() async {
        await pipelinedSpeaker.bargeIn()
        await state.update(isSpeaking: false)
    }

    /// Shows a brief "thinking" state before the examiner responds.
    /// Varies the delay to feel natural — shorter for follow-ups, longer for topic changes.
    private func showThinkingPause() async {
        await state.update(status: .thinking)

        // Brief pause: 0.3-0.7 seconds — just enough to feel natural
        let delaySeconds = 0.3 + Double.random(in: 0.0...0.4)
        try? await Task.sleep(for: .seconds(delaySeconds))
    }

    /// Listens for the trainee's response with live transcript updates.
    private func listenToTrainee() async throws -> String {
        engineLog("listenToTrainee: starting")
        let capturedState = state

        await capturedState.update(
            isListening: true,
            status: .inConversation,
            userTranscript: ""
        )

        let traineeText = try await sttService.listen(
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

        await capturedState.update(isListening: false, userTranscript: traineeText)
        engineLog("listenToTrainee: got text: \(traineeText.prefix(80))")

        // Record in Claude conversation history
        conversationHistory = conversationHistory + [
            ClaudeMessage(role: .user, content: [.text(traineeText)])
        ]

        return traineeText
    }

    /// Generates the examiner's conversational response as a stream.
    private func generateConversationalStream(
        move: DialogueFlowController.NextMove
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        let systemPrompt = buildConversationalSystemPrompt()

        // The move's prompt guidance tells Claude how to respond
        let guidance = ClaudeMessage(
            role: .user,
            content: [.text("""
                [EXAMINER GUIDANCE — not spoken aloud]
                \(move.promptGuidance)

                Respond naturally as the examiner. Speak directly to the trainee. \
                Do NOT include any metadata, JSON, or annotations. Just speak.
                """)]
        )

        return claudeClient.stream(
            model: config.model,
            system: systemPrompt,
            messages: conversationHistory + [guidance],
            maxTokens: 150
        )
    }

    /// Runs assessment in the background so it doesn't block the conversation flow.
    private func launchBackgroundAssessment(traineeText: String) {
        assessmentTask?.cancel()

        let messages = dialogueMessages
        let topic = currentTopicTracker
        let client = claudeClient
        let model = config.model
        let analysisTopics = analysis.topics

        assessmentTask = Task { [weak self] in
            guard let self else { return }

            do {
                let assessment = try await Self.assessExchange(
                    client: client,
                    model: model,
                    messages: messages,
                    currentTopic: topic,
                    analysisTopics: analysisTopics,
                    traineeText: traineeText
                )

                guard !Task.isCancelled else { return }

                await self.recordAssessment(assessment)
            } catch {
                logger.warning("Background assessment failed: \(error.localizedDescription)")
            }
        }
    }

    /// Calls Claude to assess the trainee's understanding from the latest exchange.
    private static func assessExchange(
        client: ClaudeAPIClient,
        model: ClaudeModel,
        messages: [DialogueMessage],
        currentTopic: ExamTopic?,
        analysisTopics: [ExamTopic],
        traineeText: String
    ) async throws -> InlineAssessment {
        let recentExchanges = messages.suffix(6).map { msg in
            "\(msg.role.rawValue.capitalized): \(msg.content)"
        }.joined(separator: "\n")

        let topicName = currentTopic?.name ?? "General"
        let keyConcepts = currentTopic?.keyConcepts.joined(separator: ", ") ?? ""

        let assessPrompt = """
        Assess the trainee's understanding from this recent conversation excerpt.

        Topic: \(topicName)
        Key concepts: \(keyConcepts)

        Recent conversation:
        \(recentExchanges)

        Trainee's latest response: \(traineeText)

        Respond with ONLY valid JSON:
        {
            "topicName": "\(topicName)",
            "understanding": 0.0-1.0,
            "confidence": 0.0-1.0,
            "signals": [
                {
                    "type": "demonstrated|partial|misconception|uncertain|connection",
                    "concept": "concept name",
                    "detail": "what specifically was demonstrated/missed/wrong"
                }
            ]
        }

        Assessment guidelines:
        - "understanding" reflects depth, not just correctness
        - A trainee who explains WHY scores higher than one who just states facts
        - Connecting concepts to clinical practice shows deep understanding
        - "I don't know" with good reasoning about related concepts still shows partial understanding
        - Short but accurate answers should score moderate (0.5-0.7), not low
        """

        let retryHandler = RetryHandler()
        let response = try await retryHandler.execute {
            try await client.complete(
                model: model,
                system: "You assess trainee understanding during oral examinations. Return only valid JSON.",
                messages: [ClaudeMessage(role: .user, content: [.text(assessPrompt)])],
                maxTokens: 512
            )
        }

        var cleaned = response.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw AppError.apiResponseInvalid(detail: "Could not parse assessment")
        }

        return try JSONDecoder().decode(InlineAssessment.self, from: data)
    }

    /// Records an assessment and updates performance metrics.
    private func recordAssessment(_ assessment: InlineAssessment) async {
        inlineAssessments = inlineAssessments + [assessment]

        // Convert inline assessments to performance snapshot for the dashboard
        let performance = computeDialoguePerformance()
        await state.update(performance: performance)
    }

    /// Computes a PerformanceSnapshot from accumulated inline assessments.
    private func computeDialoguePerformance() -> PerformanceSnapshot {
        guard !inlineAssessments.isEmpty else { return .empty }

        let alpha = 0.4

        // Group assessments by topic
        var topicMap: [String: (mastery: Double, asked: Int, correct: Int, scores: [Double])] = [:]

        for assessment in inlineAssessments {
            let existing = topicMap[assessment.topicName] ?? (mastery: 0, asked: 0, correct: 0, scores: [])
            let newMastery = alpha * assessment.understanding + (1 - alpha) * existing.mastery
            let newCorrect = existing.correct + (assessment.understanding >= 0.6 ? 1 : 0)

            topicMap[assessment.topicName] = (
                mastery: newMastery,
                asked: existing.asked + 1,
                correct: newCorrect,
                scores: existing.scores + [assessment.understanding]
            )
        }

        let topicScores = topicMap.map { name, data in
            let trend: TopicScore.Trend
            if data.scores.count < 2 {
                trend = .stable
            } else {
                let recent = data.scores.suffix(2)
                let diff = (recent.last ?? 0) - (recent.first ?? 0)
                if diff > 0.1 { trend = .improving }
                else if diff < -0.1 { trend = .declining }
                else { trend = .stable }
            }

            return TopicScore(
                topicName: name,
                mastery: data.mastery,
                questionsAsked: data.asked,
                questionsCorrect: data.correct,
                trend: trend
            )
        }

        // Overall weighted score
        let weightedSum = topicScores.reduce(0.0) { sum, ts in
            let importance = analysis.topics.first { $0.name == ts.topicName }?.importance ?? 0.5
            return sum + ts.mastery * importance
        }
        let totalWeight = topicScores.reduce(0.0) { sum, ts in
            let importance = analysis.topics.first { $0.name == ts.topicName }?.importance ?? 0.5
            return sum + importance
        }
        let overallScore = totalWeight > 0 ? weightedSum / totalWeight : 0

        let recentScores = inlineAssessments.suffix(5).map(\.understanding)
        let confidence = recentScores.isEmpty ? 0 : recentScores.reduce(0, +) / Double(recentScores.count)

        var streak = 0
        for assessment in inlineAssessments.reversed() {
            if assessment.understanding >= 0.7 { streak += 1 } else { break }
        }

        let turnScores = inlineAssessments.enumerated().map { index, assessment in
            TurnScore(
                questionIndex: index + 1,
                score: assessment.understanding,
                topicName: assessment.topicName
            )
        }

        let maxExchanges = config.maxQuestions * 2
        return PerformanceSnapshot(
            overallScore: overallScore,
            confidence: confidence,
            topicScores: topicScores,
            turnScores: turnScores,
            streak: streak,
            turnsCompleted: inlineAssessments.count,
            turnsRemaining: max(0, maxExchanges - dialogueMessages.count)
        )
    }

    // MARK: - Conversation Context

    private func buildConversationContext() -> ConversationContext {
        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0

        // Group assessments by topic
        var topicDiscussions: [String: TopicDiscussion] = [:]
        for assessment in inlineAssessments {
            let existing = topicDiscussions[assessment.topicName]
            let topic = analysis.topics.first { $0.name == assessment.topicName }
                ?? ExamTopic(
                    name: assessment.topicName,
                    importance: 0.5,
                    keyConcepts: [],
                    difficulty: .intermediate,
                    subtopics: []
                )

            topicDiscussions[assessment.topicName] = TopicDiscussion(
                topic: topic,
                exchangeCount: (existing?.exchangeCount ?? 0) + 1,
                assessments: (existing?.assessments ?? []) + [assessment]
            )
        }

        // Infer mood from recent assessments
        let recentMood: TraineeMood
        let recentScores = inlineAssessments.suffix(3).map(\.understanding)
        if recentScores.isEmpty {
            recentMood = .neutral
        } else {
            let avg = recentScores.reduce(0, +) / Double(recentScores.count)
            switch avg {
            case 0.8...: recentMood = .confident
            case 0.6..<0.8: recentMood = .engaged
            case 0.4..<0.6: recentMood = .neutral
            case 0.2..<0.4: recentMood = .hesitant
            default: recentMood = .struggling
            }
        }

        return ConversationContext(
            currentTopic: currentTopicTracker,
            topicsDiscussed: Array(topicDiscussions.values),
            exchangeCount: dialogueMessages.count,
            recentMood: recentMood,
            depthOnCurrentTopic: depthOnCurrentTopic,
            totalDuration: elapsed
        )
    }

    /// Pushes the current dialogue state to the observable UI state.
    private func updateDialogueState() async {
        let context = buildConversationContext()
        await state.update(
            dialogueMessages: dialogueMessages,
            conversationContext: context
        )
    }

    // MARK: - Conversational System Prompt

    private func buildConversationalSystemPrompt() -> String {
        let topicList = analysis.topics.map { topic in
            "- \(topic.name) (\(topic.difficulty.rawValue)): \(topic.keyConcepts.joined(separator: ", "))"
        }.joined(separator: "\n")

        let assessmentSummary: String
        if inlineAssessments.isEmpty {
            assessmentSummary = "No assessment data yet — this is the beginning of the conversation."
        } else {
            let topicSummaries = Dictionary(grouping: inlineAssessments, by: \.topicName)
                .map { name, assessments in
                    let avg = assessments.map(\.understanding).reduce(0, +) / Double(assessments.count)
                    return "  \(name): \(String(format: "%.0f%%", avg * 100)) understanding"
                }
                .joined(separator: "\n")
            assessmentSummary = "Running assessment:\n\(topicSummaries)"
        }

        return """
        You are Mr. Gogarty conducting a viva voce oral examination on a specific document. \
        You are warm, rigorous, and genuinely interested in how the trainee thinks through \
        the material.

        DOCUMENT CONTEXT:
        \(analysis.documentSummary)

        TOPICS TO EXPLORE:
        \(topicList)

        \(assessmentSummary)

        YOUR PERSONA:
        - You are Mr. Gogarty (Oliver St. John Gogarty), a distinguished examiner and polymath
        - You adapt your expertise to whatever subject matter the document covers
        - You are warm and encouraging but expect high standards from trainees
        - You have a dry wit and are fundamentally supportive — known for memorable insights
        - You use occasional Irish expressions naturally: "grand", "sure look", "not a bother"
        - You expect trainees to think on their feet and reason through problems
        - You speak with authority but never intimidate — you want trainees to succeed
        - You use practical scenarios and "what would you do" questions naturally
        - You ground abstract concepts with concrete examples from the document

        CONVERSATION RULES — BREVITY IS CRITICAL:
        - YOUR RESPONSES MUST BE 1-2 SENTENCES MAX. Never more. This is a rapid-fire viva.
        - Your job is to EXTRACT FACTS from the trainee, not to teach during the exam.
        - Acknowledge briefly ("Good", "Right", "Yes"), then immediately ask the next question.
        - If they're wrong, correct in ONE sentence, then move on: "Actually it's X. Now, what about Y?"
        - If they don't know, give a ONE sentence hint and re-ask, or move on.
        - Ask direct, specific questions that demand factual answers: "What nerve is at risk?" \
          "Name three causes." "What's the first investigation?"
        - Do NOT set long clinical scenarios. Get straight to the question.
        - Do NOT explain or teach at length — save that for after the exam.
        - Cover ground quickly. If they've answered well, move to the next point immediately.
        - Ask questions based on the DOCUMENT CONTENT, not general knowledge.

        SPEECH GUIDELINES:
        - Keep it SHORT. One to two sentences per response, maximum.
        - Natural spoken English, contractions fine.
        - No bullet points, lists, or formatting — this is spoken aloud.
        """
    }

    // MARK: - Legacy Mode: Private Methods

    /// Speaks a brief 2-3 sentence introduction about the topic and what's about
    /// to happen, before the conversational examination begins.
    private func speakIntroductionForConversation() async throws {
        let topicName = analysis.topics.first?.name ?? "the material"
        let intro = "Right, today we're covering \(topicName). " +
            "Structure your answers in clear points, like a real viva. Let's go."

        engineLog("speakIntroductionForConversation: \(intro.prefix(80))")
        let capturedState = state
        await capturedState.update(currentQuestion: .some(intro), isSpeaking: true)

        try await ttsService.speak(
            text: intro,
            voiceId: voiceId,
            onAudioLevel: { @Sendable level in
                Task { @MainActor in
                    let levels = Self.buildLevelsArray(from: level)
                    capturedState.update(examinerAudioLevels: levels)
                }
            }
        )

        await capturedState.update(isSpeaking: false)
        try await Task.sleep(for: .seconds(1))
    }

    private func speakIntroduction() async throws {
        let intro = "Welcome to your examination on \(analysis.documentSummary)."
        NSLog("[ExamEngine] speakIntroduction: %@", String(intro.prefix(80)))

        let capturedState = state
        await capturedState.update(currentQuestion: .some(intro), isSpeaking: true)

        try await ttsService.speak(
            text: intro,
            voiceId: voiceId,
            onAudioLevel: { @Sendable level in
                Task { @MainActor in
                    let levels = Self.buildLevelsArray(from: level)
                    capturedState.update(examinerAudioLevels: levels)
                }
            }
        )

        await capturedState.update(isSpeaking: false)

        try await Task.sleep(for: .seconds(1))
    }

    private func processAction(_ action: FlowController.NextAction) async throws {
        let (topic, questionPrompt) = buildQuestionPrompt(for: action)

        await state.update(currentTopic: .some(topic), status: .askingQuestion)

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

        let userMessage = ClaudeMessage(
            role: .user,
            content: [.text(questionPrompt)]
        )
        conversationHistory = conversationHistory + [
            userMessage,
            ClaudeMessage(role: .assistant, content: [.text(question)])
        ]

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

        await capturedState.update(status: .evaluatingAnswer)
        let evaluation = try await evaluateAnswer(question: question, answer: userAnswer, topic: topic)

        let turn = ExamTurn(
            questionIndex: allTurns.count,
            topic: topic,
            question: question,
            userAnswer: userAnswer,
            evaluation: evaluation
        )
        allTurns = allTurns + [turn]

        let performance = performanceCalculator.computeSnapshot(
            turns: allTurns,
            analysis: analysis,
            maxQuestions: config.maxQuestions
        )
        await capturedState.update(turns: allTurns, performance: performance, status: .transitioning)

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

        var cleaned = response.textContent.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            throw AppError.apiResponseInvalid(detail: "Empty evaluation response")
        }

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

    // MARK: - Shared Helpers

    private func startTimer() {
        let capturedStart = startTime ?? Date()
        timerTask = Task { [weak state] in
            guard let state else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let elapsed = Date().timeIntervalSince(capturedStart)
                await state.update(elapsedTime: elapsed)
            }
        }
    }

    /// Detects if the trainee is asking to end the examination.
    /// Only triggers on short utterances that are clearly stop requests,
    /// not on longer answers that happen to contain words like "stop".
    private func isStopRequest(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Only consider short utterances (under 60 chars) as potential stop requests.
        // A real answer that happens to contain "stop" will be longer.
        guard lower.count < 60 else { return false }

        let exactPhrases = [
            "stop", "stop please", "let's stop", "let's stop here",
            "that's enough", "wrap up", "let's wrap up",
            "finish", "let's finish", "i'm done", "done",
            "that's it", "we can stop", "can we stop",
            "i'd like to stop", "i want to stop", "leave it there",
            "thanks that's all", "thank you that's all",
            "end the exam", "end the examination"
        ]
        return exactPhrases.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasSuffix(" " + $0) })
    }

    static func buildLevelsArray(from level: Float) -> [Float] {
        let bandCount = 32
        let clamped = max(0, min(1, level))
        return (0..<bandCount).map { band in
            let variation = Float(sin(Double(band) * 0.4)) * 0.15
            return max(0, min(1, clamped + variation * clamped))
        }
    }
}
