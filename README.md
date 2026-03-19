# ENTExaminer

AI-powered oral examination simulator for ENT (Ear, Nose, and Throat) medical education. Drop in a document, and ENTExaminer conducts a voice-based viva voce, evaluating your answers in real time.

## Features

- **Document Ingestion** — Drop PDF, DOCX, TXT, Markdown, or image files. OCR support for scanned documents via Apple Vision.
- **AI-Powered Questioning** — Claude analyzes your document, identifies key topics, and generates contextual examination questions.
- **Voice Interaction** — Real-time speech-to-text (Apple Speech) and text-to-speech (ElevenLabs) for natural conversational flow.
- **Live Performance Tracking** — Radar chart for topic mastery, score timeline, streak tracking, and per-question evaluation.
- **Adaptive Flow** — The examiner adjusts questions based on your performance — probing weak areas and advancing past mastered topics.

## Architecture

```
ENTExaminer/
├── App/                        # App entry point, state management, previews
├── Core/
│   ├── Errors/                 # Typed error hierarchy with recovery suggestions
│   ├── Keychain/               # Secure API key storage
│   └── Networking/             # HTTP client, SSE streaming, retry handler
├── Features/
│   ├── DocumentIngestion/      # File parsing, drop zone UI
│   ├── Examination/            # Engine, flow control, exam views
│   ├── Performance/            # Scoring models, dashboard, radar chart
│   └── Settings/               # Preferences, onboarding, API key management
└── Services/
    ├── Audio/                  # Real-time audio pipeline, lock-free primitives
    ├── Claude/                 # API client, models, document analyzer
    └── Voice/                  # TTS (ElevenLabs), STT (Apple Speech), VAD
```

**Key design decisions:**
- **Actor isolation** throughout — `AudioPipeline`, `ExaminationEngine`, `ElevenLabsTTSService`, and `AppleSpeechSTTService` are all actors, preventing data races by construction.
- **Lock-free audio primitives** — SPSC ring buffer and atomic float arrays ensure glitch-free real-time audio without blocking the render thread.
- **Pipelined TTS** — Sentences stream from Claude to ElevenLabs as they arrive, minimizing perceived latency.
- **Immutable data models** — All domain types (`ExamTurn`, `PerformanceSnapshot`, `TopicScore`) are `Sendable` structs.

## Requirements

- macOS 14.0+ (Sonoma)
- Swift 5.10+
- Xcode 16.0+ (for Xcode builds) or Swift toolchain (for SPM builds)

### API Keys

| Service | Purpose | Required |
|---------|---------|----------|
| [Anthropic](https://console.anthropic.com/) | Document analysis and question generation | Yes |
| [ElevenLabs](https://elevenlabs.io/) | Text-to-speech voice synthesis | Yes |

Keys are stored securely in a local file (sandboxed) — never transmitted except to their respective APIs.

## Getting Started

### Build with Swift Package Manager

```bash
swift build
swift run ENTExaminer
```

### Build with Xcode

1. Open `ENTExaminer.xcodeproj` (or regenerate it with `xcodegen generate`)
2. Select the **ENTExaminer** scheme
3. Build and run (Cmd+R)

The project includes Debug and Release configurations with appropriate optimization settings.

### First Run

On first launch, the onboarding flow will prompt you to:
1. Enter your Anthropic API key
2. Enter your ElevenLabs API key
3. Select your preferred Claude model

You can change these later in **Settings** (Cmd+,).

## Usage

1. **Drop a document** onto the app (or click Browse Files)
2. Click **Analyze Document** — Claude identifies topics and prepares questions
3. Click **Begin Examination** — the AI examiner asks you questions via voice
4. **Speak your answers** — your speech is transcribed in real time
5. After each answer, Claude evaluates correctness, completeness, and clarity
6. View your **Results** with per-topic breakdown when the examination ends

## Development

### Regenerate Xcode Project

```bash
# Requires: brew install xcodegen
xcodegen generate
```

### Regenerate App Icon

```bash
swift scripts/generate_icon.swift
```

### Run Tests

```bash
swift test
```

### Project Structure

| File | Purpose |
|------|---------|
| `Package.swift` | SPM build configuration |
| `project.yml` | XcodeGen project specification |
| `ENTExaminer.entitlements` | App sandbox, network, microphone, file access |

### SwiftUI Previews

All major views include `PreviewProvider` implementations with realistic sample data. Preview helpers are in `ENTExaminer/App/PreviewHelpers.swift`.

Available previews:
- `ContentView_Previews` — Main app with sidebar navigation
- `DocumentDropView_Previews` — Empty drop zone and loaded document states
- `ExaminationView_Previews` — Listening and speaking states
- `PerformanceDashboard_Previews` — Populated and empty dashboards
- `RadarChartView_Previews` — Topic mastery visualization
- `ResultsView_Previews` — Post-examination results with animated score
- `OnboardingView_Previews` — First-run setup flow
- `SettingsView_Previews` — Settings tabs
- `WaveformView_Previews` — Active and idle waveform states

## License

All rights reserved.
