import SwiftUI
import Combine

enum AppState: Equatable {
    case idle
    case recording
    case transcribing
    case inserting
    case error(String)
    
    var displayText: String {
        switch self {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording..."
        case .transcribing:
            return "Transcribing..."
        case .inserting:
            return "Inserting text..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var statusColor: Color {
        switch self {
        case .idle:
            return .green
        case .recording:
            return .red
        case .transcribing, .inserting:
            return .blue
        case .error:
            return .orange
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var appState: AppStateManager
    @State private var showingSettings = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                Text("MacShout")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingSettings) {
                    SettingsView(
                        audioRecorder: appState.audioRecorder,
                        hotKeyMonitor: appState.hotKeyMonitor
                    )
                }
            }
            
            Divider()
            
            // Status
            HStack {
                Circle()
                    .fill(appState.state.statusColor)
                    .frame(width: 8, height: 8)
                
                Text(appState.state.displayText)
                    .font(.body)
                
                Spacer()
                
                // Show reload button if there's an error
                if case .error = appState.state {
                    Button(action: {
                        appState.loadModel()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Reload model")
                }
            }
            
            // Last transcription
            if !appState.lastTranscription.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Transcription:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        Text(appState.lastTranscription)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 60)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                    
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appState.lastTranscription, forType: .string)
                    }) {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            Divider()
            
            // Model info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Model:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(AppSettings.shared.selectedModel.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Hotkey:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(AppSettings.shared.hotKey.displayString)
                        .font(.caption)
                        .fontWeight(.medium)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            
            Divider()
            
            // Actions
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit MacShout", systemImage: "power")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - App State Manager

class AppStateManager: ObservableObject {
    @Published var state: AppState = .idle
    @Published var lastTranscription: String = ""
    
    let audioRecorder: AudioRecorder
    let hotKeyMonitor: HotKeyMonitor
    private var whisperContext: WhisperContext?
    private var modelObserver: AnyCancellable?
    private var settingsObserver: AnyCancellable?
    
    init() {
        self.audioRecorder = AudioRecorder()
        self.hotKeyMonitor = HotKeyMonitor(hotKey: AppSettings.shared.hotKey)
        
        setupCallbacks()
        loadModel()
        startHotKeyMonitoring()
        observeModelChanges()
        observeSelectedModelChanges()
    }
    
    private func setupCallbacks() {
        // Set up hotkey callbacks
        hotKeyMonitor.onKeyDown = { [weak self] in
            self?.handleRecordingStart()
        }
        
        hotKeyMonitor.onKeyUp = { [weak self] in
            self?.handleRecordingStop()
        }
    }
    
    func loadModel() {
        let modelManager = ModelManager.shared
        let selectedModel = AppSettings.shared.selectedModel
        
        // Clean up existing context
        whisperContext?.cleanup()
        whisperContext = nil
        
        // Check if model is downloaded
        guard modelManager.isModelDownloaded(selectedModel) else {
            DispatchQueue.main.async {
                self.state = .error("Model not downloaded")
            }
            return
        }
        
        DispatchQueue.main.async {
            self.state = .idle
        }
        
        // Load model in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let context = try modelManager.loadContext(for: selectedModel)
                self?.whisperContext = context
                
                DispatchQueue.main.async {
                    self?.state = .idle
                }
            } catch {
                DispatchQueue.main.async {
                    self?.state = .error("Failed to load model")
                }
            }
        }
    }
    
    private func observeModelChanges() {
        // Observe model manager's downloading models to reload when downloads complete
        modelObserver = ModelManager.shared.$downloadingModels
            .sink { [weak self] downloadingModels in
                // When no models are downloading, check if we need to reload
                if downloadingModels.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if case .error = self?.state {
                            self?.loadModel()
                        }
                    }
                }
            }
    }
    
    private func observeSelectedModelChanges() {
        // Observe when user changes the selected model in settings
        var lastModel = AppSettings.shared.selectedModel
        settingsObserver = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                let currentModel = AppSettings.shared.selectedModel
                if currentModel != lastModel {
                    lastModel = currentModel
                    self?.loadModel()
                }
            }
    }
    
    private func startHotKeyMonitoring() {
        hotKeyMonitor.start()
    }
    
    // MARK: - Recording Handlers
    
    private func handleRecordingStart() {
        DispatchQueue.main.async {
            self.state = .recording
        }
        
        do {
            try audioRecorder.startRecording()
        } catch {
            DispatchQueue.main.async {
                self.state = .error("Failed to start recording")
            }
        }
    }
    
    private func handleRecordingStop() {
        let audioSamples = audioRecorder.stopRecording()
        
        guard !audioSamples.isEmpty else {
            DispatchQueue.main.async {
                self.state = .idle
            }
            return
        }
        
        DispatchQueue.main.async {
            self.state = .transcribing
        }
        
        // Transcribe in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.transcribeAndInsert(audioSamples)
        }
    }
    
    // MARK: - Transcription
    
    private func transcribeAndInsert(_ audioSamples: [Float]) {
        guard let context = whisperContext else {
            DispatchQueue.main.async {
                self.state = .error("Model not loaded")
            }
            return
        }
        
        do {
            let segments = try context.transcribe(
                audioSamples: audioSamples,
                language: AppSettings.shared.language
            )
            
            let text = segments.map { $0.text }.joined(separator: " ")
            
            guard !text.isEmpty else {
                DispatchQueue.main.async {
                    self.state = .idle
                }
                return
            }
            
            DispatchQueue.main.async {
                self.lastTranscription = text
                self.state = .inserting
            }
            
            // Insert text into active app
            TextInserter.shared.insertTextAsync(text) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.state = .idle
                        
                        // Show notification if enabled
                        if AppSettings.shared.showNotifications {
                            self.showNotification(text: text)
                        }
                        
                    case .failure(let error):
                        self.state = .error("Failed to insert text: \(error.localizedDescription)")
                    }
                }
            }
            
        } catch {
            DispatchQueue.main.async {
                self.state = .error("Transcription failed")
            }
        }
    }
    
    // MARK: - Notifications
    
    private func showNotification(text: String) {
        let notification = NSUserNotification()
        notification.title = "MacShout"
        notification.informativeText = text
        notification.soundName = nil
        
        NSUserNotificationCenter.default.deliver(notification)
    }
}

#Preview {
    MenuBarView(appState: AppStateManager())
}
