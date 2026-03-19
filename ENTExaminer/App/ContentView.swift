import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarContent
            }
        }
        .sheet(isPresented: $state.showOnboarding) {
            OnboardingView()
                .environment(appState)
        }
        .sheet(isPresented: $state.showSettings) {
            SettingsView()
                .environment(appState)
        }
        .alert("Error", isPresented: $state.showError, presenting: appState.error) { _ in
            Button("OK") { appState.showError = false }
        } message: { error in
            VStack {
                Text(error.localizedDescription)
                if let recovery = error.recoverySuggestion {
                    Text(recovery)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleFileDrop(providers)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedSection {
        case .documents:
            DocumentDropView()
                .environment(appState)
        case .examination:
            if let examState = appState.examinationState {
                ExaminationView(sessionState: examState)
                    .environment(appState)
            } else {
                ContentUnavailableView(
                    "No Active Examination",
                    systemImage: "waveform.circle",
                    description: Text("Load a document and start an examination.")
                )
            }
        case .results:
            if let summary = appState.examSummary {
                ResultsView(summary: summary)
                    .environment(appState)
            } else {
                ContentUnavailableView(
                    "No Results Yet",
                    systemImage: "chart.bar",
                    description: Text("Complete an examination to see your results.")
                )
            }
        case .history:
            ContentUnavailableView(
                "History",
                systemImage: "clock.arrow.circlepath",
                description: Text("Past examinations will appear here.")
            )
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        if case .examining = appState.currentPhase,
           let examState = appState.examinationState {
            Text(formatTime(examState.elapsedTime))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                Task {
                    if examState.status == .paused {
                        await appState.resumeExamination()
                    } else {
                        await appState.pauseExamination()
                    }
                }
            } label: {
                Image(systemName: examState.status == .paused ? "play.circle.fill" : "pause.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }

            Button {
                Task { await appState.stopExamination() }
            } label: {
                Image(systemName: "stop.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
            }
        }

        Button {
            appState.showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                await appState.loadDocument(from: url)
            }
        }

        return true
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedSection) {
            ForEach(AppSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
                    .foregroundStyle(isSectionEnabled(section) ? .primary : .secondary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ENTExaminer")
    }

    private func isSectionEnabled(_ section: AppSection) -> Bool {
        switch section {
        case .documents: return true
        case .examination: return appState.examinationState != nil
        case .results: return appState.examSummary != nil
        case .history: return true
        }
    }
}
