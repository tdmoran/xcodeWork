import Foundation

// MARK: - Dialogue Message

/// A single utterance in the examination conversation.
/// Unlike ExamTurn (which captures a full Q&A cycle), a DialogueMessage
/// represents one person speaking — enabling natural back-and-forth flow.
struct DialogueMessage: Sendable, Equatable, Identifiable {
    let id: UUID
    let role: DialogueRole
    let content: String
    let intent: ExaminerIntent?
    let assessment: InlineAssessment?
    let timestamp: Date

    init(
        role: DialogueRole,
        content: String,
        intent: ExaminerIntent? = nil,
        assessment: InlineAssessment? = nil,
        timestamp: Date = .now
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.intent = intent
        self.assessment = assessment
        self.timestamp = timestamp
    }
}

enum DialogueRole: String, Sendable, Equatable, Codable {
    case examiner
    case trainee
}

// MARK: - Examiner Intent

/// What the examiner is trying to accomplish with their utterance.
/// Drives conversation flow decisions without the trainee seeing it.
enum ExaminerIntent: Sendable, Equatable {
    /// Opening question on a new topic area
    case openTopic(ExamTopic)
    /// Following up on what the trainee just said
    case followUp(aspect: String)
    /// Acknowledging a correct/good point before continuing
    case acknowledge
    /// Gently correcting or probing a misconception
    case clarify(misconception: String)
    /// Providing a hint or scaffolding to help the trainee get there
    case scaffold(hint: String)
    /// Transitioning to a related or new topic
    case transition(to: ExamTopic, bridge: String)
    /// Connecting multiple topics the trainee has discussed
    case synthesize(topics: [String])
    /// Wrapping up the conversation
    case closing
}

// MARK: - Inline Assessment

/// A hidden assessment computed from one or more exchanges.
/// These accumulate to form the overall picture of the trainee's understanding.
struct InlineAssessment: Sendable, Equatable, Codable {
    let topicName: String
    let understanding: Double
    let confidence: Double
    let signals: [KnowledgeSignal]
}

/// Observable signals of what the trainee knows, partially knows, or misunderstands.
struct KnowledgeSignal: Sendable, Equatable, Codable {
    let type: SignalType
    let concept: String
    let detail: String

    enum SignalType: String, Sendable, Equatable, Codable {
        /// Trainee clearly understands this concept
        case demonstrated
        /// Trainee has some understanding but is missing something
        case partial
        /// Trainee holds an incorrect belief
        case misconception
        /// Trainee expressed uncertainty or said "I don't know"
        case uncertain
        /// Trainee connected two concepts together unprompted
        case connection
    }
}

// MARK: - Conversation Context

/// Running state of the conversation that informs flow decisions.
/// Accumulated from the dialogue history — never mutated, always recomputed.
struct ConversationContext: Sendable, Equatable {
    let currentTopic: ExamTopic?
    let topicsDiscussed: [TopicDiscussion]
    let exchangeCount: Int
    let recentMood: TraineeMood
    let depthOnCurrentTopic: Int
    let totalDuration: TimeInterval

    static let empty = ConversationContext(
        currentTopic: nil,
        topicsDiscussed: [],
        exchangeCount: 0,
        recentMood: .neutral,
        depthOnCurrentTopic: 0,
        totalDuration: 0
    )
}

/// Summary of what was discussed on a particular topic.
struct TopicDiscussion: Sendable, Equatable {
    let topic: ExamTopic
    let exchangeCount: Int
    let assessments: [InlineAssessment]

    var averageUnderstanding: Double {
        guard !assessments.isEmpty else { return 0 }
        return assessments.map(\.understanding).reduce(0, +) / Double(assessments.count)
    }
}

/// Inferred emotional/engagement state of the trainee.
enum TraineeMood: String, Sendable, Equatable, Codable {
    case confident
    case engaged
    case neutral
    case hesitant
    case struggling
}

// MARK: - Examiner Response

/// The structured response from Claude acting as the examiner.
/// Contains both the spoken text and the hidden assessment.
struct ExaminerResponse: Sendable, Equatable, Codable {
    let spokenText: String
    let intent: String
    let assessment: InlineAssessment
    let mood: String
    let shouldContinueTopic: Bool
    let suggestedNextTopic: String?
}

// MARK: - Dialogue Configuration

/// Configuration for the conversational examination mode.
struct DialogueConfiguration: Sendable, Equatable {
    let model: ClaudeModel
    let voiceId: String?
    let maxExchanges: Int
    let targetDurationMinutes: Int
    let silenceTimeoutSeconds: TimeInterval
    let allowBargeIn: Bool

    static let `default` = DialogueConfiguration(
        model: .haiku,
        voiceId: nil,
        maxExchanges: 30,
        targetDurationMinutes: 15,
        silenceTimeoutSeconds: 5.0,
        allowBargeIn: true
    )

    /// Creates a DialogueConfiguration from a legacy ExamConfiguration.
    init(from legacy: ExamConfiguration) {
        self.model = legacy.model
        self.voiceId = legacy.voiceId
        self.maxExchanges = legacy.maxQuestions * 2
        self.targetDurationMinutes = 15
        self.silenceTimeoutSeconds = 5.0
        self.allowBargeIn = true
    }

    init(
        model: ClaudeModel,
        voiceId: String?,
        maxExchanges: Int,
        targetDurationMinutes: Int,
        silenceTimeoutSeconds: TimeInterval,
        allowBargeIn: Bool
    ) {
        self.model = model
        self.voiceId = voiceId
        self.maxExchanges = maxExchanges
        self.targetDurationMinutes = targetDurationMinutes
        self.silenceTimeoutSeconds = silenceTimeoutSeconds
        self.allowBargeIn = allowBargeIn
    }
}
