import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.entexaminer", category: "ContentView")

private func debugLog(_ message: String) {
    let url = URL(fileURLWithPath: "/tmp/entexaminer_debug.log")
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

struct ContentView: View {
    @Environment(AppState.self) private var appState

    init() {
        debugLog("ContentView initialized")
    }

    var body: some View {
        @Bindable var state = appState

        ZStack {
            NavigationSplitView {
                SidebarView()
            } detail: {
                detailView
            }
            .navigationSplitViewStyle(.balanced)

            if case .ingesting = appState.currentPhase {
                ProgressOverlayView()
            } else if case .analyzing = appState.currentPhase {
                ProgressOverlayView()
            }
        }
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
        #if os(macOS)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleFileDrop(providers)
        }
        #endif
    }

    @ViewBuilder
    private var detailView: some View {
        let _ = debugLog("detailView: selectedSection = \(appState.selectedSection)")
        Group {
            switch appState.selectedSection {
            case .library:
                DocumentLibraryView()
                    .environment(appState)
                    .id(AppSection.library)
            case .documentDetail:
                if let libraryDoc = appState.selectedLibraryDocument {
                    DocumentDetailView(document: libraryDoc)
                        .environment(appState)
                } else if appState.document != nil {
                    DocumentDropView()
                        .environment(appState)
                } else {
                    ContentUnavailableView(
                        "No Document Selected",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Select a document from your library to view details.")
                    )
                }
            case .cases:
                CaseBankView()
                    .environment(appState)
                    .id(AppSection.cases)
            case .examination:
                if let examState = appState.examinationState {
                    ExaminationView(sessionState: examState)
                        .environment(appState)
                } else {
                    ContentUnavailableView(
                        "No Active Examination",
                        systemImage: "waveform.circle",
                        description: Text("Select a document from your library and start an examination.")
                    )
                }
            case .results:
                if let dialogueSummary = appState.dialogueSummary {
                    ConversationSummaryView(summary: dialogueSummary)
                        .environment(appState)
                } else if let summary = appState.examSummary {
                    ResultsView(summary: summary)
                        .environment(appState)
                } else {
                    ContentUnavailableView(
                        "No Results Yet",
                        systemImage: "chart.bar",
                        description: Text("Complete an examination to see your results.")
                    )
                }
            case .archive:
                ArchiveView()
                    .environment(appState)
                    .id(AppSection.archive)
            }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        .animation(.easeInOut(duration: 0.25), value: appState.selectedSection)
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
            Task {
                if let randomCase = CaseBank.randomCase() {
                    await appState.startCaseExamination(randomCase)
                }
            }
        } label: {
            Label("Quick Start", systemImage: "play.fill")
        }

        Button {
            appState.showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
    }

    #if os(macOS)
    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                await appState.importDocument(from: url)
            }
        }

        return true
    }
    #endif

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    init() {
        debugLog("SidebarView initialized")
    }

    var body: some View {
        @Bindable var state = appState
        let _ = debugLog("SidebarView body computed")

        List {
            ForEach(AppSection.sidebarSections) { section in
                Button {
                    debugLog("Button clicked: \(section.title)")
                    if isSectionEnabled(section) {
                        debugLog("Setting selectedSection to: \(section)")
                        state.selectedSection = section
                    } else {
                        debugLog("Section disabled: \(section.title)")
                    }
                } label: {
                    HStack {
                        Label(section.title, systemImage: section.systemImage)
                            .foregroundStyle(isSectionEnabled(section) ? .primary : .secondary)
                        Spacer()
                        if badgeCount(for: section) > 0 {
                            Text("\(badgeCount(for: section))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2), in: Capsule())
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isSectionEnabled(section))
                .listRowBackground(state.selectedSection == section ? Color.accentColor.opacity(0.2) : Color.clear)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Examiner")
    }

    private func isSectionEnabled(_ section: AppSection) -> Bool {
        switch section {
        case .library: return true
        case .documentDetail: return appState.selectedLibraryDocument != nil || appState.document != nil
        case .cases: return true
        case .examination: return appState.examinationState != nil
        case .results: return appState.examSummary != nil || appState.dialogueSummary != nil
        case .archive: return true
        }
    }

    private func badgeCount(for section: AppSection) -> Int {
        switch section {
        case .library:
            return appState.libraryDocuments.filter { !$0.isArchived }.count
        case .archive:
            return appState.libraryDocuments.filter(\.isArchived).count
        default:
            return 0
        }
    }
}

// MARK: - Previews

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .environment(PreviewData.makePreviewAppState())
                .frame(width: 1000, height: 700)
                .previewDisplayName("Content View - Library")

            ContentView()
                .environment(PreviewData.makePreviewAppState(section: .results, withResults: true))
                .frame(width: 1000, height: 700)
                .previewDisplayName("Content View - Results")
        }
    }
}
#endif
