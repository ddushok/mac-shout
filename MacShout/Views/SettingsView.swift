import SwiftUI
import AVFoundation
import Carbon

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var modelManager = ModelManager.shared
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var hotKeyMonitor: HotKeyMonitor
    
    @State private var isRecordingHotKey = false
    @State private var showingModelDownload = false
    @State private var selectedModelForDownload: WhisperModel?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Divider()
                
                // Model Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Speech Model")
                    .font(.headline)
                
                Picker("Model", selection: $settings.selectedModel) {
                    ForEach(modelManager.downloadedModels()) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .disabled(modelManager.downloadedModels().isEmpty)
                
                DisclosureGroup(isExpanded: $showingModelDownload) {
                    VStack(spacing: 8) {
                        Text("Larger models provide better accuracy but require more memory.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        ForEach(WhisperModel.allCases) { model in
                            ModelDownloadRow(model: model)
                        }
                    }
                    .padding(.vertical, 8)
                } label: {
                    Label("Manage Models", systemImage: "arrow.down.circle")
                }
            }
            
            Divider()
            
            // Microphone Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Microphone")
                    .font(.headline)
                
                Picker("Device", selection: $settings.selectedMicrophoneID) {
                    ForEach(audioRecorder.availableMicrophones, id: \.uniqueID) { device in
                        Text(device.displayName).tag(device.uniqueID)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.selectedMicrophoneID) { newValue in
                    audioRecorder.selectMicrophone(deviceID: newValue)
                }
                
                Button(action: {
                    audioRecorder.updateAvailableMicrophones()
                }) {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            // Hotkey Configuration
            VStack(alignment: .leading, spacing: 8) {
                Text("Push-to-Talk Hotkey")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if isRecordingHotKey {
                            Text("Press key combination...")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.blue)
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.blue, lineWidth: 2)
                                )
                        } else {
                            Text(settings.hotKey.displayString)
                                .font(.system(.body, design: .monospaced))
                                .padding(8)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(6)
                        }
                        
                        Button(isRecordingHotKey ? "Cancel" : "Record") {
                            if isRecordingHotKey {
                                cancelRecordingHotKey()
                            } else {
                                startRecordingHotKey()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hotKeyMonitor.hasAccessibilityPermission)
                    }
                    
                    if isRecordingHotKey {
                        Text("Tip: Use modifiers like ⌘ Cmd, ⌥ Option, ⌃ Control, ⇧ Shift")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !hotKeyMonitor.hasAccessibilityPermission {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Accessibility permission required")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Grant Permission") {
                            hotKeyMonitor.requestAccessibilityPermission()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
            
            Divider()
            
            // Additional Options
            VStack(alignment: .leading, spacing: 8) {
                Text("Options")
                    .font(.headline)
                
                Toggle("Auto-transcribe after recording", isOn: $settings.autoTranscribe)
                
                Toggle("Show notifications", isOn: $settings.showNotifications)
            }
            }
            .padding(20)
        }
        .frame(width: 400, height: 500)
    }
    
    // MARK: - Hotkey Recording
    
    private func cancelRecordingHotKey() {
        isRecordingHotKey = false
        hotKeyMonitor.start()
    }
    
    private func startRecordingHotKey() {
        isRecordingHotKey = true
        
        // Stop the hotkey monitor temporarily
        hotKeyMonitor.stop()
        
        // Listen for next key press
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard self.isRecordingHotKey else { return event }
            
            let keyCode = UInt16(event.keyCode)
            let flags = event.modifierFlags
            
            // Filter out function keys and special keys that are typically used as modifiers
            let isModifierKey = [
                kVK_Command, kVK_RightCommand,
                kVK_Option, kVK_RightOption,
                kVK_Control, kVK_RightControl,
                kVK_Shift, kVK_RightShift,
                kVK_CapsLock, kVK_Function
            ].contains(Int(keyCode))
            
            // Ignore if it's just a modifier key press
            guard !isModifierKey else { return nil }
            
            // Extract relevant modifiers
            var modifiers: UInt32 = 0
            if flags.contains(.command) {
                modifiers |= UInt32(CGEventFlags.maskCommand.rawValue)
            }
            if flags.contains(.option) {
                modifiers |= UInt32(CGEventFlags.maskAlternate.rawValue)
            }
            if flags.contains(.control) {
                modifiers |= UInt32(CGEventFlags.maskControl.rawValue)
            }
            if flags.contains(.shift) {
                modifiers |= UInt32(CGEventFlags.maskShift.rawValue)
            }
            
            // Create new hotkey
            let newHotKey = HotKey(keyCode: keyCode, modifiers: modifiers)
            
            // Update settings
            DispatchQueue.main.async {
                self.settings.hotKey = newHotKey
                self.hotKeyMonitor.hotKey = newHotKey
                
                // Resume monitoring
                self.isRecordingHotKey = false
                self.hotKeyMonitor.start()
            }
            
            // Consume the event
            return nil
        }
    }
}

// MARK: - Model Download Row

struct ModelDownloadRow: View {
    let model: WhisperModel
    @ObservedObject var modelManager = ModelManager.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.headline)
                
                if modelManager.isModelDownloaded(model) {
                    Text("Downloaded")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text(modelManager.formattedFileSize(model.fileSize))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if modelManager.downloadingModels.contains(model) {
                if let progress = modelManager.downloadProgress[model] {
                    ProgressView(value: progress)
                        .frame(width: 80)
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            } else if modelManager.isModelDownloaded(model) {
                Button {
                    deleteModel()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Delete model")
            } else {
                Button {
                    downloadModel()
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Download model")
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func downloadModel() {
        modelManager.downloadModel(model) { result in
            switch result {
            case .success(let url):
                print("Downloaded model to \(url)")
            case .failure(let error):
                print("Failed to download model: \(error)")
            }
        }
    }
    
    private func deleteModel() {
        do {
            try modelManager.deleteModel(model)
        } catch {
            print("Failed to delete model: \(error)")
        }
    }
}

#Preview {
    SettingsView(
        audioRecorder: AudioRecorder(),
        hotKeyMonitor: HotKeyMonitor()
    )
}
