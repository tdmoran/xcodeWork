import SwiftUI

struct ExaminationView: View {
    @Environment(AppState.self) private var appState
    let sessionState: ExaminationSessionState

    var body: some View {
        HSplitView {
            // Left: Voice interaction (adapts based on mode)
            if sessionState.isConversationalMode {
                conversationalPanel
                    .frame(minWidth: 450)
            } else {
                legacyVoiceInteractionPanel
                    .frame(minWidth: 400)
            }

            // Right: Performance dashboard (shared)
            PerformanceDashboard(
                performance: sessionState.performance,
                topicScores: sessionState.topicScores,
                turnScores: sessionState.performance.turnScores
            )
            .frame(minWidth: 300, idealWidth: 350)
        }
        .padding()
    }

    // MARK: - Conversational Mode Panel

    private var conversationalPanel: some View {
        VStack(spacing: 0) {
            // Topic indicator bar
            topicBar

            // Dialogue thread — the heart of the conversational UI
            dialogueThread
                .frame(maxHeight: .infinity)

            // Active speech area
            activeSpeechArea
                .padding(.horizontal)

            // Controls
            controlBar
        }
    }

    private var topicBar: some View {
        HStack(spacing: 8) {
            if let topic = sessionState.currentTopic {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)

                Text("Discussing: \(topic.name)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Elapsed time
            Text(formatDuration(sessionState.elapsedTime))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var dialogueThread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(sessionState.dialogueMessages) { message in
                        DialogueBubble(message: message)
                            .id(message.id)
                    }

                    // Live transcript while listening
                    if sessionState.isListening && !sessionState.userTranscript.isEmpty {
                        DialogueBubble(
                            message: DialogueMessage(
                                role: .trainee,
                                content: sessionState.userTranscript
                            )
                        )
                        .opacity(0.6)
                        .id("live-transcript")
                    }
                }
                .padding(16)
            }
            .onChange(of: sessionState.dialogueMessages.count) {
                scrollToLatest(proxy: proxy)
            }
            .onChange(of: sessionState.userTranscript) {
                if sessionState.isListening {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("live-transcript", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var activeSpeechArea: some View {
        VStack(spacing: 10) {
            // Waveform — shows whoever is currently speaking
            HStack(spacing: 12) {
                // Examiner waveform
                VStack(spacing: 4) {
                    WaveformView(
                        levels: sessionState.examinerAudioLevels,
                        color: .blue,
                        accentColor: .cyan,
                        isActive: sessionState.isSpeaking
                    )
                    .frame(height: 36)

                    Text("Dr. Campbell")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(sessionState.isSpeaking ? 1 : 0.5)
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1, height: 36)

                // User waveform
                VStack(spacing: 4) {
                    WaveformView(
                        levels: sessionState.userAudioLevels,
                        color: .green,
                        accentColor: .mint,
                        isActive: sessionState.isListening
                    )
                    .frame(height: 36)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(sessionState.isListening ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                            .opacity(sessionState.isListening ? 1 : 0)
                            .animation(
                                sessionState.isListening
                                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                    : .default,
                                value: sessionState.isListening
                            )

                        Text("You")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .opacity(sessionState.isListening ? 1 : 0.5)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            // Conversational status
            conversationalStatusBadge
        }
        .padding(.vertical, 8)
    }

    private var conversationalStatusBadge: some View {
        HStack(spacing: 6) {
            switch sessionState.status {
            case .examinerSpeaking:
                Image(systemName: "person.wave.2.fill")
                    .foregroundStyle(.blue)
                Text("Dr. Campbell is speaking...")

                // Barge-in button — trainee can interrupt
                Button {
                    Task { await appState.handleBargeIn() }
                } label: {
                    Label("Interrupt", systemImage: "hand.raised.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
            case .inConversation where sessionState.isListening:
                Image(systemName: "ear.fill")
                    .foregroundStyle(.green)
                Text("Listening...")
            case .inConversation:
                Image(systemName: "ellipsis.bubble.fill")
                    .foregroundStyle(.blue)
                Text("In conversation")
            case .thinking:
                ProgressView()
                    .controlSize(.small)
                Text("Dr. Campbell is thinking...")
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
                Text("Paused")
            case .finished:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Conversation complete")
            default:
                EmptyView()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            if sessionState.status == .paused {
                Button {
                    Task { await appState.resumeExamination() }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            } else if sessionState.status != .finished && sessionState.status != .notStarted {
                Button {
                    Task { await appState.pauseExamination() }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)
            }

            Button {
                Task { await appState.stopExamination() }
            } label: {
                Label("End Conversation", systemImage: "stop.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    // MARK: - Dialogue Bubble

    private struct DialogueBubble: View {
        let message: DialogueMessage

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                if message.role == .examiner {
                    examinerAvatar
                    examinerBubble
                    Spacer(minLength: 60)
                } else {
                    Spacer(minLength: 60)
                    traineeBubble
                    traineeAvatar
                }
            }
        }

        private var examinerAvatar: some View {
            Image(systemName: "stethoscope")
                .font(.callout)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.blue.gradient, in: Circle())
        }

        private var traineeAvatar: some View {
            Image(systemName: "person.fill")
                .font(.callout)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.green.gradient, in: Circle())
        }

        private var examinerBubble: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(message.content)
                    .font(.callout)
                    .textSelection(.enabled)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .padding(10)
            .background(Color.blue.opacity(0.08), in: ChatBubbleShape(isFromUser: false))
        }

        private var traineeBubble: some View {
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.content)
                    .font(.callout)
                    .textSelection(.enabled)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .padding(10)
            .background(Color.green.opacity(0.08), in: ChatBubbleShape(isFromUser: true))
        }
    }

    // MARK: - Chat Bubble Shape

    private struct ChatBubbleShape: Shape {
        let isFromUser: Bool

        func path(in rect: CGRect) -> Path {
            let radius: CGFloat = 12
            let tailSize: CGFloat = 6

            var path = Path()

            if isFromUser {
                // Rounded rect with tail on bottom-right
                path.addRoundedRect(
                    in: CGRect(x: rect.minX, y: rect.minY, width: rect.width - tailSize, height: rect.height),
                    cornerSize: CGSize(width: radius, height: radius)
                )
            } else {
                // Rounded rect with tail on bottom-left
                path.addRoundedRect(
                    in: CGRect(x: rect.minX + tailSize, y: rect.minY, width: rect.width - tailSize, height: rect.height),
                    cornerSize: CGSize(width: radius, height: radius)
                )
            }

            return path
        }
    }

    // MARK: - Legacy Voice Interaction Panel

    private var legacyVoiceInteractionPanel: some View {
        VStack(spacing: 20) {
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

            if let question = sessionState.currentQuestion {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Q\(sessionState.turns.count + 1)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())

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
                        .shadow(color: sessionState.isListening ? .green.opacity(0.5) : .clear, radius: 4)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: sessionState.isListening)

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

            if sessionState.isListening || !sessionState.userTranscript.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                        .foregroundStyle(.green)
                        .font(.callout)

                    Text(sessionState.userTranscript.isEmpty ? "Speak your answer..." : sessionState.userTranscript)
                        .font(.callout)
                        .foregroundStyle(sessionState.userTranscript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeInOut(duration: 0.2), value: sessionState.userTranscript)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .transition(.opacity)
            }

            legacyStatusBadge

            legacyConversationHistory

            Spacer()

            HStack(spacing: 12) {
                if sessionState.status == .paused {
                    Button {
                        Task { await appState.resumeExamination() }
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else if sessionState.status != .finished && sessionState.status != .notStarted {
                    Button {
                        Task { await appState.pauseExamination() }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    Task { await appState.stopExamination() }
                } label: {
                    Label("Stop Examination", systemImage: "stop.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
    }

    private var legacyStatusBadge: some View {
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

    private var legacyConversationHistory: some View {
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

    // MARK: - Helpers

    private func scoreIndicator(_ score: Double) -> some View {
        Image(systemName: score >= 0.7 ? "checkmark.circle.fill" :
                score >= 0.4 ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
            .foregroundStyle(score >= 0.7 ? .green : score >= 0.4 ? .orange : .red)
            .font(.caption)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func scrollToLatest(proxy: ScrollViewProxy) {
        if let lastId = sessionState.dialogueMessages.last?.id {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
struct ExaminationView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ExaminationView(sessionState: PreviewData.makePreviewSessionState(status: .listeningForAnswer))
                .environment(PreviewData.makePreviewAppState(phase: .examining, section: .examination, withExamination: true))
                .frame(width: 900, height: 650)
                .previewDisplayName("Legacy - Listening")

            ExaminationView(sessionState: PreviewData.makePreviewSessionState(status: .askingQuestion, isListening: false, isSpeaking: true))
                .environment(PreviewData.makePreviewAppState(phase: .examining, section: .examination, withExamination: true))
                .frame(width: 900, height: 650)
                .previewDisplayName("Legacy - Speaking")
        }
    }
}
#endif
