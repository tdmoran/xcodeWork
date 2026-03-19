import Foundation

enum ExamStatus: String, Sendable, Equatable {
    case notStarted
    case askingQuestion
    case listeningForAnswer
    case evaluatingAnswer
    case transitioning
    case paused
    case finished
}

struct ExamTurn: Sendable, Equatable, Identifiable {
    let id: UUID
    let questionIndex: Int
    let topic: ExamTopic
    let question: String
    let userAnswer: String
    let evaluation: TurnEvaluation
    let timestamp: Date

    init(
        questionIndex: Int,
        topic: ExamTopic,
        question: String,
        userAnswer: String,
        evaluation: TurnEvaluation,
        timestamp: Date = .now
    ) {
        self.id = UUID()
        self.questionIndex = questionIndex
        self.topic = topic
        self.question = question
        self.userAnswer = userAnswer
        self.evaluation = evaluation
        self.timestamp = timestamp
    }
}

struct TurnEvaluation: Codable, Sendable, Equatable {
    let correctnessScore: Double
    let completenessScore: Double
    let clarityScore: Double
    let keyPointsCovered: [String]
    let keyPointsMissed: [String]
    let feedback: String
    let followUpSuggestion: FollowUpAction

    var compositeScore: Double {
        (correctnessScore * 0.5) + (completenessScore * 0.3) + (clarityScore * 0.2)
    }

    enum FollowUpAction: String, Codable, Sendable, Equatable {
        case deeperOnSameTopic
        case moveToNextTopic
        case clarifyMisunderstanding
        case congratulateAndAdvance
    }
}

struct ExamConfiguration: Sendable, Equatable {
    let model: ClaudeModel
    let maxQuestions: Int
    let voiceId: String?

    static let `default` = ExamConfiguration(
        model: .haiku,
        maxQuestions: 15,
        voiceId: nil
    )
}

struct ExamSummary: Sendable, Equatable {
    let turns: [ExamTurn]
    let overallScore: Double
    let topicScores: [TopicScore]
    let totalDuration: TimeInterval
    let documentTitle: String
    let modelUsed: ClaudeModel

    var questionCount: Int { turns.count }
    var averageScore: Double { overallScore }

    var grade: String {
        switch overallScore {
        case 0.9...: return "Excellent"
        case 0.75..<0.9: return "Good"
        case 0.6..<0.75: return "Satisfactory"
        case 0.4..<0.6: return "Needs Improvement"
        default: return "Unsatisfactory"
        }
    }
}
