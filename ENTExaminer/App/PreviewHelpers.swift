import SwiftUI

// MARK: - Preview Sample Data

enum PreviewData {
    static let sampleTopics: [ExamTopic] = [
        ExamTopic(
            name: "Otitis Media",
            importance: 0.9,
            keyConcepts: ["Acute vs Chronic", "Treatment protocols", "Complications"],
            difficulty: .intermediate,
            subtopics: ["AOM", "OME", "CSOM"]
        ),
        ExamTopic(
            name: "Sinusitis",
            importance: 0.8,
            keyConcepts: ["Diagnosis criteria", "Imaging indications", "Surgical options"],
            difficulty: .intermediate,
            subtopics: ["Acute", "Chronic", "Fungal"]
        ),
        ExamTopic(
            name: "Hearing Loss",
            importance: 0.85,
            keyConcepts: ["Conductive vs Sensorineural", "Audiometry", "Rehabilitation"],
            difficulty: .advanced,
            subtopics: ["Conductive", "Sensorineural", "Mixed"]
        ),
        ExamTopic(
            name: "Laryngology",
            importance: 0.7,
            keyConcepts: ["Vocal cord pathology", "Airway management"],
            difficulty: .advanced,
            subtopics: ["Dysphonia", "Stridor", "Laryngitis"]
        ),
        ExamTopic(
            name: "Head & Neck Anatomy",
            importance: 0.75,
            keyConcepts: ["Cranial nerves", "Fascial planes", "Lymphatic drainage"],
            difficulty: .foundational,
            subtopics: ["Triangles of neck", "Salivary glands"]
        ),
    ]

    static let sampleAnalysis = DocumentAnalysis(
        topics: sampleTopics,
        documentSummary: "Comprehensive ENT examination covering otology, rhinology, and laryngology with emphasis on clinical diagnosis and management.",
        suggestedQuestionCount: 15,
        estimatedDurationMinutes: 20,
        difficultyAssessment: "intermediate"
    )

    static let sampleEvaluation = TurnEvaluation(
        correctnessScore: 0.85,
        completenessScore: 0.7,
        clarityScore: 0.9,
        keyPointsCovered: ["Identified conductive hearing loss", "Correct treatment approach"],
        keyPointsMissed: ["Didn't mention tympanometry"],
        feedback: "Good understanding of conductive hearing loss pathways. Consider mentioning tympanometry for completeness.",
        followUpSuggestion: .moveToNextTopic
    )

    static let sampleTurns: [ExamTurn] = [
        ExamTurn(
            questionIndex: 0,
            topic: sampleTopics[0],
            question: "Describe the pathophysiology of acute otitis media and outline the first-line treatment approach.",
            userAnswer: "Acute otitis media involves bacterial infection of the middle ear space, commonly caused by Streptococcus pneumoniae. First-line treatment is amoxicillin for 7-10 days.",
            evaluation: sampleEvaluation
        ),
        ExamTurn(
            questionIndex: 1,
            topic: sampleTopics[2],
            question: "What are the key differences between conductive and sensorineural hearing loss?",
            userAnswer: "Conductive hearing loss involves the outer or middle ear blocking sound transmission. Sensorineural involves damage to the inner ear or auditory nerve.",
            evaluation: TurnEvaluation(
                correctnessScore: 0.9,
                completenessScore: 0.8,
                clarityScore: 0.85,
                keyPointsCovered: ["Correct distinction", "Mentioned key structures"],
                keyPointsMissed: ["Weber and Rinne test findings"],
                feedback: "Excellent differentiation. Adding tuning fork test results would strengthen your answer.",
                followUpSuggestion: .congratulateAndAdvance
            )
        ),
        ExamTurn(
            questionIndex: 2,
            topic: sampleTopics[1],
            question: "When is CT imaging indicated for sinusitis?",
            userAnswer: "CT is indicated when symptoms persist beyond 12 weeks despite medical therapy, or when complications are suspected.",
            evaluation: TurnEvaluation(
                correctnessScore: 0.6,
                completenessScore: 0.5,
                clarityScore: 0.8,
                keyPointsCovered: ["Chronic sinusitis indication"],
                keyPointsMissed: ["Pre-surgical planning", "Orbital or intracranial complications"],
                feedback: "Partially correct. Also important for pre-surgical planning and when orbital or intracranial complications are suspected.",
                followUpSuggestion: .deeperOnSameTopic
            )
        ),
    ]

    static let sampleTopicScores: [TopicScore] = [
        TopicScore(topicName: "Otitis Media", mastery: 0.82, questionsAsked: 3, questionsCorrect: 2, trend: .improving),
        TopicScore(topicName: "Sinusitis", mastery: 0.55, questionsAsked: 2, questionsCorrect: 1, trend: .declining),
        TopicScore(topicName: "Hearing Loss", mastery: 0.91, questionsAsked: 3, questionsCorrect: 3, trend: .improving),
        TopicScore(topicName: "Laryngology", mastery: 0.68, questionsAsked: 2, questionsCorrect: 1, trend: .stable),
        TopicScore(topicName: "Head & Neck", mastery: 0.75, questionsAsked: 2, questionsCorrect: 2, trend: .improving),
    ]

    static let sampleTurnScores: [TurnScore] = [
        TurnScore(questionIndex: 1, score: 0.72, topicName: "Otitis Media"),
        TurnScore(questionIndex: 2, score: 0.85, topicName: "Hearing Loss"),
        TurnScore(questionIndex: 3, score: 0.55, topicName: "Sinusitis"),
        TurnScore(questionIndex: 4, score: 0.78, topicName: "Laryngology"),
        TurnScore(questionIndex: 5, score: 0.91, topicName: "Hearing Loss"),
    ]

    static let samplePerformance = PerformanceSnapshot(
        overallScore: 0.74,
        confidence: 0.78,
        topicScores: sampleTopicScores,
        turnScores: sampleTurnScores,
        streak: 2,
        turnsCompleted: 5,
        turnsRemaining: 10
    )

    static let sampleExamSummary = ExamSummary(
        turns: sampleTurns,
        overallScore: 0.78,
        topicScores: sampleTopicScores,
        totalDuration: 720,
        documentTitle: "ENT Clinical Examination Guide",
        modelUsed: .haiku
    )

    static let sampleDocument = ParsedDocument(
        text: """
        Chapter 1: Otology

        The ear is divided into three parts: the outer ear, the middle ear, and the inner ear. \
        Each plays a crucial role in the hearing process. Understanding the anatomy and physiology \
        of each component is essential for diagnosing and managing ear disorders.

        Acute Otitis Media (AOM) is one of the most common childhood infections. It presents with \
        ear pain, fever, and a bulging tympanic membrane on otoscopy...
        """,
        sections: [
            DocumentSection(title: "Otology", content: "The ear is divided into three parts...", pageNumber: 1),
            DocumentSection(title: "Rhinology", content: "The nasal cavity and paranasal sinuses...", pageNumber: 15),
        ],
        metadata: FileMetadata(
            url: URL(fileURLWithPath: "/Users/student/Documents/ENT-Guide.pdf"),
            title: "ENT Clinical Examination Guide",
            fileSize: 2_450_000,
            pageCount: 42,
            format: .pdf
        ),
        contentHash: "abc123"
    )

    @MainActor
    static func makePreviewAppState(
        phase: AppPhase = .idle,
        section: AppSection = .documents,
        withDocument: Bool = false,
        withAnalysis: Bool = false,
        withExamination: Bool = false,
        withResults: Bool = false
    ) -> AppState {
        let state = AppState()
        state.currentPhase = phase
        state.selectedSection = section
        state.showOnboarding = false

        if withDocument {
            state.document = sampleDocument
        }
        if withAnalysis {
            state.document = sampleDocument
            state.analysis = sampleAnalysis
        }
        if withExamination {
            let sessionState = ExaminationSessionState()
            sessionState.update(
                turns: sampleTurns,
                currentQuestion: "What is the differential diagnosis for unilateral sensorineural hearing loss?",
                currentTopic: sampleTopics[2],
                isListening: true,
                isSpeaking: false,
                performance: samplePerformance,
                status: .listeningForAnswer,
                userTranscript: "The differential includes acoustic neuroma, Meniere's disease, sudden sensorineural hearing loss...",
                examinerAudioLevels: Array(repeating: Float(0), count: 32),
                userAudioLevels: (0..<32).map { _ in Float.random(in: 0.1...0.6) },
                elapsedTime: 345
            )
            state.examinationState = sessionState
        }
        if withResults {
            state.examSummary = sampleExamSummary
        }

        return state
    }

    /// Creates a session state populated with sample data for previews.
    @MainActor
    static func makePreviewSessionState(
        status: ExamStatus = .listeningForAnswer,
        isListening: Bool = true,
        isSpeaking: Bool = false
    ) -> ExaminationSessionState {
        let sessionState = ExaminationSessionState()
        sessionState.update(
            turns: sampleTurns,
            currentQuestion: "Describe the management of a peritonsillar abscess.",
            currentTopic: sampleTopics[3],
            isListening: isListening,
            isSpeaking: isSpeaking,
            performance: samplePerformance,
            status: status,
            userTranscript: isListening ? "Needle aspiration or incision and drainage..." : "",
            examinerAudioLevels: isSpeaking
                ? (0..<32).map { _ in Float.random(in: 0.2...0.8) }
                : Array(repeating: 0, count: 32),
            userAudioLevels: isListening
                ? (0..<32).map { _ in Float.random(in: 0.1...0.5) }
                : Array(repeating: 0, count: 32),
            elapsedTime: 234
        )
        return sessionState
    }
}
