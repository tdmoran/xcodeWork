import SwiftUI
import Charts

struct ResultsView: View {
    @Environment(AppState.self) private var appState
    let summary: ExamSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)

                    Text("Examination Complete")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(summary.documentTitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Score card
                HStack(spacing: 32) {
                    scoreCircle

                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary.grade)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(gradeColor)

                        Group {
                            Label("\(summary.questionCount) questions", systemImage: "questionmark.circle")
                            Label(formatDuration(summary.totalDuration), systemImage: "clock")
                            Label(summary.modelUsed.displayName, systemImage: "cpu")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                // Topic breakdown
                if !summary.topicScores.isEmpty {
                    topicBreakdown
                }

                // Question-by-question
                questionBreakdown

                // Actions
                HStack(spacing: 16) {
                    Button("New Examination") {
                        appState.resetForNewExamination()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(32)
        }
    }

    private var scoreCircle: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 10)

            Circle()
                .trim(from: 0, to: summary.overallScore)
                .stroke(gradeColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(summary.overallScore * 100))%")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 120, height: 120)
    }

    private var topicBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Topic Performance")
                .font(.headline)

            ForEach(summary.topicScores) { topic in
                HStack {
                    Text(topic.topicName)
                        .font(.callout)
                        .frame(width: 120, alignment: .leading)

                    ProgressView(value: topic.mastery)
                        .tint(scoreColor(topic.mastery))

                    Text("\(Int(topic.mastery * 100))%")
                        .font(.callout)
                        .monospacedDigit()
                        .frame(width: 45, alignment: .trailing)

                    trendIcon(topic.trend)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var questionBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Question Details")
                .font(.headline)

            ForEach(summary.turns) { turn in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(turn.question)
                            .font(.callout)

                        Text("Your answer: \(turn.userAnswer)")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Text(turn.evaluation.feedback)
                            .font(.callout)
                            .italic()

                        HStack(spacing: 12) {
                            scorePill("Accuracy", turn.evaluation.correctnessScore)
                            scorePill("Completeness", turn.evaluation.completenessScore)
                            scorePill("Clarity", turn.evaluation.clarityScore)
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    HStack(spacing: 8) {
                        scoreIndicator(turn.evaluation.compositeScore)
                        Text("Q\(turn.questionIndex + 1): \(turn.topic.name)")
                            .font(.callout)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(turn.evaluation.compositeScore * 100))%")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func scorePill(_ label: String, _ score: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(score * 100))%")
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(scoreColor(score).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func scoreIndicator(_ score: Double) -> some View {
        Image(systemName: score >= 0.7 ? "checkmark.circle.fill" :
                score >= 0.4 ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
            .foregroundStyle(scoreColor(score))
    }

    private func trendIcon(_ trend: TopicScore.Trend) -> some View {
        Image(systemName: trend == .improving ? "arrow.up.right" :
                trend == .declining ? "arrow.down.right" : "arrow.right")
            .font(.caption)
            .foregroundStyle(trend == .improving ? .green : trend == .declining ? .red : .secondary)
    }

    private var gradeColor: Color {
        scoreColor(summary.overallScore)
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 0.75...: return .green
        case 0.6..<0.75: return .yellow
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }
}

// MARK: - Previews

#if DEBUG
struct ResultsView_Previews: PreviewProvider {
    static var previews: some View {
        ResultsView(summary: PreviewData.sampleExamSummary)
            .environment(PreviewData.makePreviewAppState(withResults: true))
            .frame(width: 700, height: 800)
            .previewDisplayName("Results View")
    }
}
#endif
