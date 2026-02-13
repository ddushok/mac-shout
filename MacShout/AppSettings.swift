import Foundation
import SwiftUI
import Carbon

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    // Selected model
    @AppStorage("selectedModel") var selectedModelRawValue: String = WhisperModel.baseEn.rawValue
    
    var selectedModel: WhisperModel {
        get {
            WhisperModel(rawValue: selectedModelRawValue) ?? .baseEn
        }
        set {
            selectedModelRawValue = newValue.rawValue
        }
    }
    
    // Selected microphone
    @AppStorage("selectedMicrophoneID") var selectedMicrophoneID: String = ""
    
    // Hotkey settings
    @AppStorage("hotKeyCode") var hotKeyCode: Int = 61  // kVK_RightOption
    @AppStorage("hotKeyModifiers") var hotKeyModifiers: Int = 0
    
    var hotKey: HotKey {
        get {
            HotKey(keyCode: UInt16(hotKeyCode), modifiers: UInt32(hotKeyModifiers))
        }
        set {
            hotKeyCode = Int(newValue.keyCode)
            hotKeyModifiers = Int(newValue.modifiers)
        }
    }
    
    // Language
    @AppStorage("language") var language: String = "en"
    
    // Auto-start transcription after recording
    @AppStorage("autoTranscribe") var autoTranscribe: Bool = true
    
    // Show notifications
    @AppStorage("showNotifications") var showNotifications: Bool = false
    
    private init() {
        // Initialize with defaults if needed
    }
}
