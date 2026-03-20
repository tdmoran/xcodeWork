import SwiftUI

/// A reusable overlay that displays progress during document processing phases.
/// Visible only during `.ingesting` and `.analyzing` phases.
struct ProgressOverlayView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.currentPhase {
            case .ingesting(let progress):
                overlayCard(
                    title: phaseTitle,
                    subtitle: phaseSubtitle,
                    progress: .determinate(progress),
                    showCancel: true
                )
            case .analyzing:
                overlayCard(
                    title: phaseTitle,
                    subtitle: phaseSubtitle,
                    progress: .indeterminate,
                    showCancel: false
                )
            default:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isVisible)
    }

    private var isVisible: Bool {
        switch appState.currentPhase {
        case .ingesting, .analyzing:
            return true
        default:
            return false
        }
    }

    private var phaseTitle: String {
        switch appState.currentPhase {
        case .ingesting:
            return "Importing Document..."
        case .analyzing:
            return "Analyzing Topics..."
        default:
            return ""
        }
    }

    private var phaseSubtitle: String {
        switch appState.currentPhase {
        case .ingesting(let progress):
            return progressDescription(progress)
        case .analyzing:
            if let doc = appState.document {
                return "Processing \(doc.characterCount.formatted()) characters"
            }
            return "Extracting topics and key concepts"
        default:
            return ""
        }
    }

    private func progressDescription(_ progress: Double) -> String {
        switch progress {
        case ..<0.3:
            return "Reading file contents"
        case 0.3..<0.7:
            if let pages = appState.document?.metadata.pageCount {
                return "Extracting text from \(pages) pages"
            }
            return "Parsing document structure"
        case 0.7...:
            return "Preparing for analysis"
        default:
            return "Processing..."
        }
    }

    // MARK: - Overlay Card

    private func overlayCard(
        title: String,
        subtitle: String,
        progress: ProgressType,
        showCancel: Bool
    ) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                progressIndicator(progress)

                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if showCancel {
                    Button("Cancel") {
                        appState.resetForNewExamination()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(32)
            .frame(minWidth: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20, y: 8)
        }
    }

    @ViewBuilder
    private func progressIndicator(_ type: ProgressType) -> some View {
        switch type {
        case .determinate(let value):
            ProgressView(value: value, total: 1.0)
                .progressViewStyle(.linear)
                .frame(width: 200)
        case .indeterminate:
            ProgressView()
                .controlSize(.large)
        }
    }
}

// MARK: - Progress Type

private enum ProgressType {
    case determinate(Double)
    case indeterminate
}
