import SwiftUI

struct ExaminationView: View {
    @Environment(AppState.self) private var appState
    let sessionState: ExaminationSessionState

    var body: some View {
        HSplitView {
            // Left: Voice interaction
            voiceInteractionPanel
                .frame(minWidth: 400)

            // Right: Performance dashboard
            PerformanceDashboard(
                performance: sessionState.performance,
                topicScores: sessionState.topicScores,
                turnScores: sessionState.performance.turnScores
            )
            .frame(minWidth: 300, idealWidth: 350)
        }
        .padding()
    }

    // MARK: - Voice Interaction Panel

    private var voiceInteractionPanel: some View {
        VStack(spacing: 20) {
            // Examiner waveform
            VStack(spacing: 8) {
                Label("ENTExaminer", systemImage: "person.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                WaveformView(
                    levels: sessionState.examinerAudioLevels,
                    color: .blue,
                    accentColor: .cyan,
                    isActive: sessionState.isSpeaking
                )
                .frame(height: 48)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Current question
            if let question = sessionState.currentQuestion {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Q\(sessionState.turns.count + 1)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.accent.opacity(0.15), in: Capsule())

                        if let topic = sessionState.currentTopic {
                            Text(topic.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(question)
                        .font(.title3)
                        .fontWeight(.medium)
                        .transition(.push(from: .bottom))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .animation(.easeInOut(duration: 0.4), value: question)
            }

            // User waveform
            VStack(spacing: 8) {
                WaveformView(
                    levels: sessionState.userAudioLevels,
                    color: .green,
                    accentColor: .mint,
                    isActive: sessionState.isListening
                )
                .frame(height: 48)

                HStack(spacing: 6) {
                    Circle()
                        .fill(sessionState.isListening ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)

                    Label(
                        sessionState.isListening ? "Listening..." : "Waiting",
                        systemImage: sessionState.isListening ? "mic.fill" : "mic.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Status
            statusBadge

            // Conversation history
            conversationHistory

            Spacer()
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            switch sessionState.status {
            case .askingQuestion:
                ProgressView()
                    .controlSize(.small)
                Text("Generating question...")
            case .listeningForAnswer:
                Image(systemName: "ear.fill")
                    .foregroundStyle(.green)
                Text("Your turn to answer")
            case .evaluatingAnswer:
                ProgressView()
                    .controlSize(.small)
                Text("Evaluating response...")
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
                Text("Paused")
            case .finished:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Examination complete")
            default:
                EmptyView()
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var conversationHistory: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sessionState.turns) { turn in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                scoreIndicator(turn.evaluation.compositeScore)
                                Text("Q\(turn.questionIndex + 1): \(turn.topic.name)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                            }

                            Text(turn.question)
                                .font(.callout)
                                .fontWeight(.medium)

                            Text(turn.userAnswer)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .id(turn.id)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: sessionState.turns.count) {
                if let lastId = sessionState.turns.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func scoreIndicator(_ score: Double) -> some View {
        Image(systemName: score >= 0.7 ? "checkmark.circle.fill" :
                score >= 0.4 ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
            .foregroundStyle(score >= 0.7 ? .green : score >= 0.4 ? .orange : .red)
            .font(.caption)
    }
}
