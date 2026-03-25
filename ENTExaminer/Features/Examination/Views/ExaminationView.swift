import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ExaminationView: View {
    @Environment(AppState.self) private var appState
    let sessionState: ExaminationSessionState
    @State private var showSpeechVisualizer = true
    @State private var showTurnIndicator = true

    var body: some View {
        #if os(macOS)
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
        #else
        TabView {
            // Voice interaction (adapts based on mode)
            Group {
                if sessionState.isConversationalMode {
                    conversationalPanel
                } else {
                    legacyVoiceInteractionPanel
                }
            }
            .tabItem {
                Label("Examination", systemImage: "waveform.circle")
            }

            // Performance dashboard
            PerformanceDashboard(
                performance: sessionState.performance,
                topicScores: sessionState.topicScores,
                turnScores: sessionState.performance.turnScores
            )
            .tabItem {
                Label("Performance", systemImage: "chart.bar")
            }
        }
        .padding()
        #endif
    }

    // MARK: - Performance Bar

    private var performanceBar: some View {
        let score = sessionState.performance.overallScore
        let completed = sessionState.performance.turnsCompleted
        let total = completed + sessionState.performance.turnsRemaining
        let streak = sessionState.performance.streak
        let scorePercent = Int(score * 100)
        let barColor: Color = score < 0.4 ? .red : score < 0.7 ? .orange : .green

        return HStack(spacing: 12) {
            // Score progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(barColor.opacity(0.18))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * score))
                        .animation(.easeInOut(duration: 0.4), value: score)
                }
            }
            .frame(height: 6)
            .frame(maxWidth: .infinity)

            // Score percentage
            Text("\(scorePercent)%")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(barColor)
                .monospacedDigit()

            // Question counter
            Text("Q \(completed)/\(total)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            // Streak indicator
            if streak > 0 {
                HStack(spacing: 2) {
                    Text("\u{1F525}")
                        .font(.caption2)
                    Text("\(streak)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 40)
        .background(.ultraThinMaterial)
    }

    // MARK: - Conversational Mode Panel

    private var conversationalPanel: some View {
        VStack(spacing: 0) {
            // Document context header
            documentContextHeader

            // Real-time performance bar
            performanceBar

            // Topic indicator bar
            topicBar

            // Dialogue thread — the heart of the conversational UI
            dialogueThread
                .frame(maxHeight: .infinity)

            // Speech Turn Indicator (separate, collapsible)
            if showTurnIndicator {
                SpeechTurnIndicator(
                    status: sessionState.status,
                    isListening: sessionState.isListening,
                    isSpeaking: sessionState.isSpeaking,
                    listeningStartTime: sessionState.listeningStartTime,
                    lastSpeechTime: sessionState.lastSpeechTime,
                    silenceTimeout: sessionState.silenceTimeout,
                    maxSpeakingDuration: sessionState.maxAnswerLength
                )
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Turn Indicator toggle button
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showTurnIndicator.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showTurnIndicator ? "gauge.open.with.lines.needle.84percent.exclamation" : "gauge.open.with.lines.needle.33percent")
                        .font(.body)
                    Text(showTurnIndicator ? "Hide Turn Indicator" : "Show Turn Indicator")
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(showTurnIndicator ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.08))
                )
            }
            .buttonStyle(.borderless)
            .foregroundStyle(showTurnIndicator ? .blue : .secondary)
            .padding(.horizontal)
            .padding(.top, 4)

            // Voice visualizer (waveforms, collapsible)
            if showSpeechVisualizer {
                activeSpeechArea
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Waveform toggle
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSpeechVisualizer.toggle()
                    }
                } label: {
                    Label(
                        showSpeechVisualizer ? "Hide Waveforms" : "Show Waveforms",
                        systemImage: showSpeechVisualizer ? "waveform.slash" : "waveform"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 2)

            // Controls
            controlBar
        }
        #if os(iOS)
        .onChange(of: sessionState.isSpeaking) { _, newValue in
            if newValue {
                triggerHaptic(.light)
            }
        }
        .onChange(of: sessionState.isListening) { _, newValue in
            if newValue {
                triggerHaptic(.medium)
            }
        }
        .onChange(of: sessionState.status) { _, newValue in
            if newValue == .finished {
                triggerNotificationHaptic(.success)
            }
        }
        #endif
    }

    private var documentContextHeader: some View {
        Group {
            if let doc = appState.selectedLibraryDocument {
                documentBanner(title: doc.title, icon: doc.formatIcon)
            } else if let docTitle = appState.document?.metadata.title {
                documentBanner(title: docTitle, icon: "doc.text.fill")
            }
        }
    }

    private func documentBanner(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .font(.caption)
            Text("Examining: \(title)")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.06))
    }

    private var topicBar: some View {
        HStack(spacing: 8) {
            if sessionState.isTeachingMode {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)

                Text("Teaching Mode")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
            } else if let topic = sessionState.currentTopic {
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

                    // Thinking indicator
                    if sessionState.status == .thinking {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "stethoscope")
                                .font(.callout)
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.blue.gradient, in: Circle())

                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("\(sessionState.personaName) is thinking...")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Color.blue.opacity(0.08), in: ChatBubbleShape(isFromUser: false))

                            Spacer(minLength: 60)
                        }
                        .transition(.opacity)
                        .id("thinking-indicator")
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

                    Text("Mr. Gogarty")
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
                Text("Mr. Gogarty is speaking...")

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
                Text("\(sessionState.personaName) is thinking...")
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
        HStack(spacing: 16) {
            if sessionState.status == .paused {
                Button {
                    Task { await appState.resumeExamination() }
                } label: {
                    #if os(iOS)
                    Label("Resume", systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                    #else
                    Label("Resume", systemImage: "play.fill")
                    #endif
                }
                .buttonStyle(.borderedProminent)
            } else if sessionState.status != .finished && sessionState.status != .notStarted {
                Button {
                    Task { await appState.pauseExamination() }
                } label: {
                    #if os(iOS)
                    Image(systemName: "pause.fill")
                    #else
                    Label("Pause", systemImage: "pause.fill")
                    #endif
                }
                .buttonStyle(.bordered)
            }

            Button {
                Task { await appState.toggleTeachingMode() }
            } label: {
                #if os(iOS)
                Image(systemName: sessionState.isTeachingMode ? "graduationcap.fill" : "lightbulb.fill")
                #else
                if sessionState.isTeachingMode {
                    Label("Resume Exam", systemImage: "graduationcap.fill")
                } else {
                    Label("Teach Me", systemImage: "lightbulb.fill")
                }
                #endif
            }
            .buttonStyle(.bordered)
            .tint(sessionState.isTeachingMode ? .blue : .orange)

            // Skip button — visible while examiner is speaking or listening for response
            if sessionState.isSpeaking || sessionState.isListening {
                Button {
                    #if os(iOS)
                    triggerHaptic(.light)
                    #endif
                    Task { await appState.skipCurrentTurn() }
                } label: {
                    #if os(iOS)
                    Image(systemName: "forward.fill")
                    #else
                    Label("Skip", systemImage: "forward.fill")
                    #endif
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button {
                Task { await appState.stopExamination() }
            } label: {
                #if os(iOS)
                Image(systemName: "stop.fill")
                    .foregroundStyle(.red)
                #else
                Label("End Conversation", systemImage: "stop.fill")
                    .foregroundStyle(.red)
                #endif
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
            documentContextHeader

            VStack(spacing: 8) {
                Label("Examiner", systemImage: "person.wave.2.fill")
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

                // Skip button for legacy mode
                if sessionState.isSpeaking || sessionState.isListening {
                    Button {
                        Task { await appState.skipCurrentTurn() }
                    } label: {
                        #if os(iOS)
                        Image(systemName: "forward.fill")
                        #else
                        Label("Skip", systemImage: "forward.fill")
                        #endif
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

    #if os(iOS)
    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    private func triggerNotificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
    #endif

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
