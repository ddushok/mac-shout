import Foundation
import AVFoundation
import Accelerate

enum AudioRecorderError: Error {
    case engineNotAvailable
    case inputNodeNotAvailable
    case microphonePermissionDenied
    case recordingFailed
}

class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var availableMicrophones: [AVCaptureDevice] = []
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    
    // Target format for whisper.cpp
    private let targetSampleRate: Double = 16000
    private let targetChannels: UInt32 = 1
    
    var selectedMicrophoneID: String? {
        didSet {
            if isRecording {
                _ = stopRecording()
            }
            setupAudioEngine()
        }
    }
    
    init() {
        updateAvailableMicrophones()
        setupAudioEngine()
    }
    
    deinit {
        stopRecording()
    }
    
    // MARK: - Microphone Management
    
    func updateAvailableMicrophones() {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInMicrophone]
        
        if #available(macOS 14.0, *) {
            deviceTypes.append(.microphone)
        }
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        )
        
        availableMicrophones = discoverySession.devices
        
        // Set default microphone if none selected
        if selectedMicrophoneID == nil, let defaultMic = availableMicrophones.first {
            selectedMicrophoneID = defaultMic.uniqueID
        }
    }
    
    func selectMicrophone(deviceID: String) {
        selectedMicrophoneID = deviceID
    }
    
    // MARK: - Audio Engine Setup
    
    private func setupAudioEngine() {
        audioEngine?.stop()
        audioEngine = AVAudioEngine()
        
        guard let engine = audioEngine else { return }
        inputNode = engine.inputNode
        
        // Configure input node with selected microphone
        if let micID = selectedMicrophoneID,
           let devices = AVCaptureDevice.devices(for: .audio) as? [AVCaptureDevice],
           let selectedDevice = devices.first(where: { $0.uniqueID == micID }) {
            
            do {
                try engine.inputNode.setDeviceID(selectedDevice.uniqueID)
            } catch {
                print("Failed to set microphone device: \(error)")
            }
        }
    }
    
    // MARK: - Recording Control
    
    func startRecording() throws {
        guard !isRecording else { return }
        
        // Check microphone permission
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            if status == .notDetermined {
                // Request permission
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    if granted {
                        try? self.startRecording()
                    }
                }
                return
            }
            throw AudioRecorderError.microphonePermissionDenied
        }
        
        guard let engine = audioEngine, let inputNode = inputNode else {
            throw AudioRecorderError.engineNotAvailable
        }
        
        // Clear previous buffer
        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()
        
        // Get input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, inputFormat: inputFormat)
        }
        
        // Start the engine
        do {
            try engine.start()
            DispatchQueue.main.async {
                self.isRecording = true
            }
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.recordingFailed
        }
    }
    
    func stopRecording() -> [Float] {
        guard isRecording else { return [] }
        
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()
        
        return samples
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(inputFormat.channelCount)
        
        // Convert to mono if needed
        var monoSamples: [Float]
        if channelCount == 1 {
            monoSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        } else {
            // Average all channels to create mono
            monoSamples = [Float](repeating: 0, count: frameLength)
            for frame in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channelData[channel][frame]
                }
                monoSamples[frame] = sum / Float(channelCount)
            }
        }
        
        // Resample to 16kHz if needed
        let inputSampleRate = inputFormat.sampleRate
        let resampledSamples: [Float]
        
        if inputSampleRate != targetSampleRate {
            resampledSamples = resample(
                samples: monoSamples,
                fromRate: inputSampleRate,
                toRate: targetSampleRate
            )
        } else {
            resampledSamples = monoSamples
        }
        
        // Add to buffer
        bufferLock.lock()
        audioBuffer.append(contentsOf: resampledSamples)
        bufferLock.unlock()
    }
    
    // MARK: - Resampling
    
    private func resample(samples: [Float], fromRate: Double, toRate: Double) -> [Float] {
        guard fromRate != toRate else { return samples }
        
        let ratio = fromRate / toRate
        let outputLength = Int(Double(samples.count) / ratio)
        
        guard outputLength > 0 else { return [] }
        
        var output = [Float](repeating: 0, count: outputLength)
        
        // Simple linear interpolation
        for i in 0..<outputLength {
            let sourcePosition = Double(i) * ratio
            let sourceIndex = Int(sourcePosition)
            let fraction = Float(sourcePosition - Double(sourceIndex))
            
            if sourceIndex + 1 < samples.count {
                let sample1 = samples[sourceIndex]
                let sample2 = samples[sourceIndex + 1]
                output[i] = sample1 + (sample2 - sample1) * fraction
            } else if sourceIndex < samples.count {
                output[i] = samples[sourceIndex]
            }
        }
        
        return output
    }
}

// MARK: - AVCaptureDevice Extension

extension AVCaptureDevice {
    var displayName: String {
        return localizedName
    }
}

// MARK: - AVAudioInputNode Extension

extension AVAudioInputNode {
    func setDeviceID(_ deviceID: String) throws {
        // Set the audio device UID for the input node
        var deviceUID = deviceID as CFString
        let propertySize = UInt32(MemoryLayout<CFString>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Find the audio device ID from UID
        var deviceID: AudioDeviceID = 0
        var deviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var translation = AudioValueTranslation(
            mInputData: &deviceUID,
            mInputDataSize: UInt32(MemoryLayout<CFString>.size),
            mOutputData: &deviceID,
            mOutputDataSize: deviceIDSize
        )
        
        propertyAddress.mSelector = kAudioHardwarePropertyDeviceForUID
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &deviceIDSize,
            &translation
        )
        
        if status != noErr {
            throw AudioRecorderError.engineNotAvailable
        }
        
        // Set the device
        try self.setInputDeviceID(deviceID)
    }
    
    private func setInputDeviceID(_ deviceID: AudioDeviceID) throws {
        var deviceID = deviceID
        let propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            propertySize,
            &deviceID
        )
        
        guard status == noErr else {
            throw AudioRecorderError.engineNotAvailable
        }
    }
}
