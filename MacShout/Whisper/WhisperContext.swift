import Foundation
import whisper

enum WhisperError: Error {
    case modelLoadFailed
    case transcriptionFailed
    case invalidAudioData
    case contextNotInitialized
}

struct WhisperSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

class WhisperContext {
    private var context: OpaquePointer?
    private let modelPath: String
    
    var isInitialized: Bool {
        return context != nil
    }
    
    init(modelPath: String) {
        self.modelPath = modelPath
    }
    
    deinit {
        cleanup()
    }
    
    func initialize() throws {
        guard context == nil else { return }
        
        var params = whisper_context_default_params()
        params.use_gpu = true  // Enable Metal on Apple Silicon
        
        context = whisper_init_from_file_with_params(modelPath, params)
        
        guard context != nil else {
            throw WhisperError.modelLoadFailed
        }
    }
    
    func transcribe(audioSamples: [Float], language: String = "en") throws -> [WhisperSegment] {
        guard let context = context else {
            throw WhisperError.contextNotInitialized
        }
        
        guard !audioSamples.isEmpty else {
            throw WhisperError.invalidAudioData
        }
        
        // Configure transcription parameters
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        
        // Set language
        let langCString = language.cString(using: .utf8)
        params.language = langCString?.withUnsafeBufferPointer { buffer in
            return buffer.baseAddress
        }
        
        // Performance settings
        params.n_threads = 4
        params.print_progress = false
        params.print_special = false
        params.print_realtime = false
        params.print_timestamps = false
        
        // Disable tokens/text output to console
        params.token_timestamps = false
        
        // Run transcription
        let result = audioSamples.withUnsafeBufferPointer { buffer in
            whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
        }
        
        guard result == 0 else {
            throw WhisperError.transcriptionFailed
        }
        
        // Extract segments
        let segmentCount = whisper_full_n_segments(context)
        var segments: [WhisperSegment] = []
        
        for i in 0..<segmentCount {
            guard let textCString = whisper_full_get_segment_text(context, i) else {
                continue
            }
            
            let text = String(cString: textCString).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty segments
            guard !text.isEmpty else { continue }
            
            let startTime = TimeInterval(whisper_full_get_segment_t0(context, i)) / 100.0
            let endTime = TimeInterval(whisper_full_get_segment_t1(context, i)) / 100.0
            
            segments.append(WhisperSegment(
                text: text,
                startTime: startTime,
                endTime: endTime
            ))
        }
        
        return segments
    }
    
    func cleanup() {
        if let context = context {
            whisper_free(context)
            self.context = nil
        }
    }
    
    // Get model information
    func getModelInfo() -> String? {
        guard let context = context else { return nil }
        // This would require additional whisper.cpp API calls
        // For now, return basic info
        return "Whisper model loaded from \(modelPath)"
    }
}

// MARK: - Audio Processing Helpers

extension WhisperContext {
    /// Convert PCM16 audio data to Float32 format required by whisper.cpp
    static func convertPCM16ToFloat(_ pcm16Data: Data) -> [Float] {
        let int16Array = pcm16Data.withUnsafeBytes { buffer -> [Int16] in
            Array(buffer.bindMemory(to: Int16.self))
        }
        
        return int16Array.map { Float($0) / Float(Int16.max) }
    }
    
    /// Resample audio to 16kHz if needed (basic implementation)
    /// For production use, consider using AVAudioConverter or vDSP
    static func resampleTo16kHz(samples: [Float], fromSampleRate: Double) -> [Float] {
        guard fromSampleRate != 16000 else { return samples }
        
        let ratio = fromSampleRate / 16000.0
        let outputLength = Int(Double(samples.count) / ratio)
        var output = [Float](repeating: 0, count: outputLength)
        
        for i in 0..<outputLength {
            let sourceIndex = Int(Double(i) * ratio)
            if sourceIndex < samples.count {
                output[i] = samples[sourceIndex]
            }
        }
        
        return output
    }
}
