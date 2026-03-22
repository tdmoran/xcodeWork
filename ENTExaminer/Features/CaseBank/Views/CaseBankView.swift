import SwiftUI

struct CaseBankView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSubspecialty: ENTSubspecialty?
    @State private var selectedDifficulty: CaseDifficulty?
    @State private var expandedCaseId: UUID?

    private var filteredCases: [ClinicalCase] {
        CaseBank.allCases.filter { clinicalCase in
            let matchesSubspecialty = selectedSubspecialty.map { clinicalCase.subspecialty == $0 } ?? true
            let matchesDifficulty = selectedDifficulty.map { clinicalCase.difficulty == $0 } ?? true
            return matchesSubspecialty && matchesDifficulty
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                filters
                caseGrid
            }
            .padding(24)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Sample Cases")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Pre-loaded clinical scenarios to try out the examiner")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Filters

    private var filters: some View {
        #if os(iOS)
        VStack(spacing: 12) {
            HStack {
                Picker("Subspecialty", selection: $selectedSubspecialty) {
                    Text("All Subspecialties").tag(nil as ENTSubspecialty?)
                    ForEach(ENTSubspecialty.allCases, id: \.self) { sub in
                        Text(sub.displayName).tag(sub as ENTSubspecialty?)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Picker("Difficulty", selection: $selectedDifficulty) {
                    Text("All Levels").tag(nil as CaseDifficulty?)
                    ForEach(CaseDifficulty.allCases, id: \.self) { diff in
                        Text(diff.displayName).tag(diff as CaseDifficulty?)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Text("\(filteredCases.count) cases")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    if let randomCase = CaseBank.randomCase(
                        subspecialty: selectedSubspecialty,
                        difficulty: selectedDifficulty
                    ) {
                        Task { await appState.startCaseExamination(randomCase) }
                    }
                } label: {
                    Label("Random Case", systemImage: "dice.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(filteredCases.isEmpty)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        #else
        HStack(spacing: 16) {
            Picker("Subspecialty", selection: $selectedSubspecialty) {
                Text("All Subspecialties").tag(nil as ENTSubspecialty?)
                ForEach(ENTSubspecialty.allCases, id: \.self) { sub in
                    Text(sub.displayName).tag(sub as ENTSubspecialty?)
                }
            }
            .frame(width: 200)

            Picker("Difficulty", selection: $selectedDifficulty) {
                Text("All Levels").tag(nil as CaseDifficulty?)
                ForEach(CaseDifficulty.allCases, id: \.self) { diff in
                    Text(diff.displayName).tag(diff as CaseDifficulty?)
                }
            }
            .frame(width: 160)

            Spacer()

            Text("\(filteredCases.count) cases")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                if let randomCase = CaseBank.randomCase(
                    subspecialty: selectedSubspecialty,
                    difficulty: selectedDifficulty
                ) {
                    Task { await appState.startCaseExamination(randomCase) }
                }
            } label: {
                Label("Random Case", systemImage: "dice.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(filteredCases.isEmpty)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        #endif
    }

    // MARK: - Case Grid

    private var caseGrid: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredCases) { clinicalCase in
                caseCard(clinicalCase)
            }
        }
    }

    private func caseCard(_ clinicalCase: ClinicalCase) -> some View {
        let isExpanded = expandedCaseId == clinicalCase.id

        return VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clinicalCase.title)
                        .font(.headline)

                    HStack(spacing: 8) {
                        subspecialtyBadge(clinicalCase.subspecialty)
                        difficultyBadge(clinicalCase.difficulty)
                    }
                }

                Spacer()

                Button {
                    Task { await appState.startCaseExamination(clinicalCase) }
                } label: {
                    Label("Start Viva", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Vignette
            Text(clinicalCase.clinicalVignette)
                .font(.callout)
                .foregroundStyle(.secondary)

            // Expand/collapse details
            if isExpanded {
                expandedDetails(clinicalCase)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedCaseId = isExpanded ? nil : clinicalCase.id
                }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Hide Details" : "Show Details")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func expandedDetails(_ clinicalCase: ClinicalCase) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            detailSection("Key History Points", items: clinicalCase.keyHistoryPoints, icon: "list.clipboard", color: .blue)
            detailSection("Examination Findings", items: clinicalCase.examinationFindings, icon: "stethoscope", color: .green)
            detailSection("Investigations", items: clinicalCase.investigations, icon: "flask", color: .purple)
            detailSection("Management Plan", items: clinicalCase.managementPlan, icon: "cross.circle", color: .orange)

            if !clinicalCase.criticalPoints.isEmpty {
                detailSection("Must Not Miss", items: clinicalCase.criticalPoints, icon: "exclamationmark.triangle.fill", color: .red)
            }

            if !clinicalCase.teachingNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Teaching Pearl", systemImage: "lightbulb.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.yellow)

                    Text(clinicalCase.teachingNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
                .padding(10)
                .background(Color.yellow.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func detailSection(_ title: String, items: [String], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("\u{2022}")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Badges

    private func subspecialtyBadge(_ subspecialty: ENTSubspecialty) -> some View {
        Text(subspecialty.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(subspecialty.color.opacity(0.12), in: Capsule())
            .foregroundStyle(subspecialty.color)
    }

    private func difficultyBadge(_ difficulty: CaseDifficulty) -> some View {
        Text(difficulty.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(difficulty.color.opacity(0.12), in: Capsule())
            .foregroundStyle(difficulty.color)
    }
}

// MARK: - Display Helpers

extension ENTSubspecialty {
    var displayName: String { rawValue }

    var color: Color {
        switch self {
        case .headAndNeck: return .red
        case .otology: return .blue
        case .rhinology: return .green
        case .pediatricENT: return .orange
        case .laryngology: return .purple
        }
    }
}

extension CaseDifficulty {
    var color: Color {
        switch self {
        case .straightforward: return .green
        case .intermediate: return .orange
        case .challenging: return .red
        }
    }
}
