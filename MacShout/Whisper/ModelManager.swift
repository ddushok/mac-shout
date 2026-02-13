import Foundation

enum WhisperModel: String, CaseIterable, Identifiable {
    case tinyEn = "tiny.en"
    case baseEn = "base.en"
    case smallEn = "small.en"
    case mediumEn = "medium.en"
    case largev3Turbo = "large-v3-turbo"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .tinyEn: return "Tiny (75 MB)"
        case .baseEn: return "Base (142 MB)"
        case .smallEn: return "Small (466 MB)"
        case .mediumEn: return "Medium (1.5 GB)"
        case .largev3Turbo: return "Large v3 Turbo (1.5 GB)"
        }
    }
    
    var fileSize: Int64 {
        switch self {
        case .tinyEn: return 75 * 1024 * 1024
        case .baseEn: return 142 * 1024 * 1024
        case .smallEn: return 466 * 1024 * 1024
        case .mediumEn: return 1536 * 1024 * 1024
        case .largev3Turbo: return 1536 * 1024 * 1024
        }
    }
    
    var downloadURL: URL {
        let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
        return URL(string: "\(baseURL)/ggml-\(rawValue).bin")!
    }
    
    var fileName: String {
        return "ggml-\(rawValue).bin"
    }
}

enum ModelManagerError: Error {
    case downloadFailed(String)
    case modelNotFound
    case directoryCreationFailed
}

class ModelManager: ObservableObject {
    static let shared = ModelManager()
    
    @Published var downloadingModels: Set<WhisperModel> = []
    @Published var downloadProgress: [WhisperModel: Double] = [:]
    
    private let modelsDirectory: URL
    private var downloadTasks: [WhisperModel: URLSessionDownloadTask] = [:]
    
    init() {
        // Store models in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        modelsDirectory = appSupport.appendingPathComponent("MacShout/Models")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Model Status
    
    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let modelPath = modelPath(for: model)
        return FileManager.default.fileExists(atPath: modelPath.path)
    }
    
    func modelPath(for model: WhisperModel) -> URL {
        return modelsDirectory.appendingPathComponent(model.fileName)
    }
    
    func downloadedModels() -> [WhisperModel] {
        return WhisperModel.allCases.filter { isModelDownloaded($0) }
    }
    
    // MARK: - Download
    
    func downloadModel(_ model: WhisperModel, completion: @escaping (Result<URL, Error>) -> Void) {
        // Check if already downloading
        guard !downloadingModels.contains(model) else {
            print("Model \(model.displayName) is already being downloaded")
            return
        }
        
        // Check if already downloaded
        if isModelDownloaded(model) {
            completion(.success(modelPath(for: model)))
            return
        }
        
        DispatchQueue.main.async {
            self.downloadingModels.insert(model)
            self.downloadProgress[model] = 0.0
        }
        
        let destinationURL = modelPath(for: model)
        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        
        let task = session.downloadTask(with: model.downloadURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }
            
            defer {
                DispatchQueue.main.async {
                    self.downloadingModels.remove(model)
                    self.downloadProgress.removeValue(forKey: model)
                    self.downloadTasks.removeValue(forKey: model)
                }
            }
            
            if let error = error {
                completion(.failure(ModelManagerError.downloadFailed(error.localizedDescription)))
                return
            }
            
            guard let tempURL = tempURL else {
                completion(.failure(ModelManagerError.downloadFailed("No temporary file")))
                return
            }
            
            do {
                // Remove existing file if present
                try? FileManager.default.removeItem(at: destinationURL)
                
                // Move downloaded file to destination
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                
                print("Model \(model.displayName) downloaded successfully to \(destinationURL.path)")
                completion(.success(destinationURL))
            } catch {
                completion(.failure(error))
            }
        }
        
        // Observe progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.downloadProgress[model] = progress.fractionCompleted
            }
        }
        
        downloadTasks[model] = task
        task.resume()
        
        // Keep observation alive
        objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)
    }
    
    func cancelDownload(_ model: WhisperModel) {
        downloadTasks[model]?.cancel()
        downloadTasks.removeValue(forKey: model)
        
        DispatchQueue.main.async {
            self.downloadingModels.remove(model)
            self.downloadProgress.removeValue(forKey: model)
        }
    }
    
    // MARK: - Delete
    
    func deleteModel(_ model: WhisperModel) throws {
        let modelPath = modelPath(for: model)
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ModelManagerError.modelNotFound
        }
        
        try FileManager.default.removeItem(at: modelPath)
    }
    
    // MARK: - Loading
    
    func loadContext(for model: WhisperModel) throws -> WhisperContext {
        guard isModelDownloaded(model) else {
            throw ModelManagerError.modelNotFound
        }
        
        let path = modelPath(for: model)
        let context = WhisperContext(modelPath: path.path)
        try context.initialize()
        
        return context
    }
}

// MARK: - Helper Extensions

extension ModelManager {
    func formattedFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
