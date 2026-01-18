import Foundation
import Observation
import WhisperKit

@Observable
final class ModelManager {
    // MARK: - Состояние
    
    private(set) var availableModels: [String] = []
    private(set) var downloadedModels: [String] = []
    private(set) var currentModel: String?
    private(set) var downloadProgress: Double = 0
    private(set) var isDownloading = false
    
    // MARK: - Пути
    
    /// Директория моделей в Application Support
    let modelsDirectory: URL
    
    // MARK: - Ключи UserDefaults
    private let selectedModelKey = "selectedModel"
    
    /// Текущая выбранная модель (сохраняется и наблюдаема)
    /// Пустая строка означает, что модель ещё не выбрана
    var selectedModel: String = "" {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: selectedModelKey)
        }
    }
    
    // MARK: - Инициализация
    
    init() {
        // Храним модели в ~/Library/Application Support/BetterDictation/Models/
        // Стандартный паттерн macOS для данных приложения
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelsDirectory = appSupport.appendingPathComponent("BetterDictation/Models", isDirectory: true)
        
        // Загружаем сохранённый выбор из UserDefaults
        self.selectedModel = UserDefaults.standard.string(forKey: selectedModelKey) ?? ""
        
        // Создаём директорию, если нужно
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        
        // Загружаем список доступных моделей
        Task {
            await refreshAvailableModels()
        }
    }
    
    // MARK: - Обнаружение моделей
    
    func refreshAvailableModels() async {
        // Модели WhisperKit, доступные в репозитории HuggingFace argmaxinc/whisperkit-coreml
        // Названия должны точно соответствовать именам папок в репозитории
        // distil-large-v3 в 6 раз быстрее с похожим качеством!
        availableModels = [
            "tiny",
            "tiny.en",
            "base",
            "base.en",
            "small",
            "small.en",
            "medium",
            "medium.en",
            "large-v3",
            "large-v3-turbo",
            "large-v3-v20240930",
            "large-v3-v20240930_turbo",
            "distil-large-v3",          // distil-whisper_distil-large-v3
            "distil-large-v3_turbo"     // distil-whisper_distil-large-v3_turbo
        ]
        
        // Проверяем, какие модели уже скачаны
        await refreshDownloadedModels()
    }
    
    @MainActor
    func refreshDownloadedModels() async {
        do {
            // WhisperKit хранит модели в: downloadBase/models/argmaxinc/whisperkit-coreml/openai_whisper-{model}
            let whisperKitPath = modelsDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            
            guard FileManager.default.fileExists(atPath: whisperKitPath.path) else {
                downloadedModels = []
                return
            }
            
            let contents = try FileManager.default.contentsOfDirectory(
                at: whisperKitPath,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
            
            let models = contents
                .filter { url in
                    // Проверяем, что это директория
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue else {
                        return false
                    }
                    
                    // Проверяем, содержит ли она необходимые файлы модели (config.json означает завершённую загрузку)
                    let configPath = url.appendingPathComponent("config.json")
                    return FileManager.default.fileExists(atPath: configPath.path)
                }
                .compactMap { url -> String? in
                    // Извлекаем имя модели из имени папки
                    let folderName = url.lastPathComponent
                    
                    // OpenAI модели: "openai_whisper-base" -> "base"
                    if folderName.hasPrefix("openai_whisper-") {
                        return String(folderName.dropFirst("openai_whisper-".count))
                    }
                    
                    // Distil модели: "distil-whisper_distil-large-v3" -> "distil-large-v3"
                    if folderName.hasPrefix("distil-whisper_") {
                        return String(folderName.dropFirst("distil-whisper_".count))
                    }
                    
                    return nil
                }
            
            downloadedModels = models
        } catch {
            downloadedModels = []
        }
    }
    
    // MARK: - Загрузка моделей
    
    func downloadModel(_ modelName: String, progress: @escaping (Double) -> Void) async throws {
        guard !isDownloading else {
            throw ModelError.downloadInProgress
        }
        
        isDownloading = true
        downloadProgress = 0
        
        defer {
            isDownloading = false
        }
        
        print("Скачивание модели: \(modelName) в \(modelsDirectory.path)")
        
        do {
            // Скачиваем модель в нашу кастомную директорию
            let config = WhisperKitConfig(
                model: modelName,
                downloadBase: modelsDirectory,
                verbose: true,
                logLevel: .info
            )
            
            _ = try await WhisperKit(config)
            
            downloadProgress = 1.0
            progress(1.0)
            
            await refreshDownloadedModels()
            
            print("Модель \(modelName) успешно скачана в \(modelsDirectory.path)")
        } catch {
            print("Загрузка модели не удалась: \(error)")
            throw ModelError.downloadFailed(underlying: error)
        }
    }
    
    // MARK: - Загрузка моделей в память
    
    /// Загрузить модель из нашей кастомной директории
    func loadModel(_ modelName: String) async throws -> WhisperKit {
        let modelPath = modelsDirectory.appendingPathComponent(modelName)
        
        // Проверяем, существует ли модель локально
        if FileManager.default.fileExists(atPath: modelPath.path) {
            // Загружаем из локального пути
            let config = WhisperKitConfig(
                modelFolder: modelPath.path,
                verbose: false,
                logLevel: .error
            )
            return try await WhisperKit(config)
        } else {
            // Сначала скачиваем в нашу директорию
            let config = WhisperKitConfig(
                model: modelName,
                downloadBase: modelsDirectory,
                verbose: true,
                logLevel: .info
            )
            return try await WhisperKit(config)
        }
    }
    
    // MARK: - Выбор модели
    
    func selectModel(_ modelName: String) {
        currentModel = modelName
    }
    
    /// Получить рекомендуемую модель - возвращает выбранную пользователем или дефолтную
    func recommendedModel() -> String {
        return selectedModel
    }
    
    // MARK: - Очистка
    
    /// Удалить скачанную модель
    func deleteModel(_ modelName: String) throws {
        // WhisperKit хранит модели в: downloadBase/models/argmaxinc/whisperkit-coreml/
        // OpenAI модели: openai_whisper-{model}
        // Distil модели: distil-whisper_{model}
        let basePath = modelsDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
        
        let modelPath: URL
        if modelName.hasPrefix("distil-") {
            modelPath = basePath.appendingPathComponent("distil-whisper_\(modelName)")
        } else {
            modelPath = basePath.appendingPathComponent("openai_whisper-\(modelName)")
        }
        
        try FileManager.default.removeItem(at: modelPath)
    }
    
    /// Удалить все скачанные модели
    func deleteAllModels() throws {
        try FileManager.default.removeItem(at: modelsDirectory)
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        downloadedModels = []
    }
}

// MARK: - Информация о модели

struct ModelInfo: Identifiable {
    let name: String
    let displayName: String
    let size: String
    let description: String
    
    var id: String { name }
    
    /// Имена должны соответствовать репозиторию WhisperKit: argmaxinc/whisperkit-coreml
    /// distil-large-v3 в 6 раз быстрее с ~1% потерей качества - лучшая для реального времени!
    static let all: [ModelInfo] = [
        // Быстрые модели
        ModelInfo(name: "tiny", displayName: "Tiny", size: "~40 MB", description: "Самая быстрая, базовое качество"),
        ModelInfo(name: "tiny.en", displayName: "Tiny (EN)", size: "~40 MB", description: "Только English, чуть лучше качество"),
        ModelInfo(name: "base", displayName: "Base", size: "~140 MB", description: "Быстрая, хорошее качество"),
        ModelInfo(name: "base.en", displayName: "Base (EN)", size: "~140 MB", description: "Только English"),
        ModelInfo(name: "small", displayName: "Small", size: "~460 MB", description: "Хороший баланс скорость/качество"),
        ModelInfo(name: "small.en", displayName: "Small (EN)", size: "~460 MB", description: "Только English"),
        
        // Средние модели
        ModelInfo(name: "medium", displayName: "Medium", size: "~1.4 GB", description: "Высокое качество"),
        ModelInfo(name: "medium.en", displayName: "Medium (EN)", size: "~1.4 GB", description: "Только English"),
        
        // Distil модели - РЕКОМЕНДУЮТСЯ для реального времени! В 6 раз быстрее
        ModelInfo(name: "distil-large-v3", displayName: "⚡ Distil Large V3", size: "~600 MB", description: "🔥 ЛУЧШАЯ: 6x быстрее, качество Large!"),
        ModelInfo(name: "distil-large-v3_turbo", displayName: "⚡ Distil Large V3 Turbo", size: "~600 MB", description: "🔥 Ещё быстрее с turbo оптимизацией"),
        
        // Large модели - высочайшее качество
        ModelInfo(name: "large-v3", displayName: "Large V3", size: "~3 GB", description: "Максимальное качество, медленная"),
        ModelInfo(name: "large-v3-turbo", displayName: "Large V3 Turbo", size: "~1.5 GB", description: "Turbo оптимизация"),
        ModelInfo(name: "large-v3-v20240930", displayName: "Large V3 (2024)", size: "~600 MB", description: "Новая версия, компактнее"),
        ModelInfo(name: "large-v3-v20240930_turbo", displayName: "Large V3 (2024) Turbo", size: "~630 MB", description: "Новая версия + turbo"),
    ]
    
    static func info(for name: String) -> ModelInfo? {
        all.first { $0.name == name }
    }
}

// MARK: - Ошибки

enum ModelError: LocalizedError {
    case downloadInProgress
    case downloadFailed(underlying: Error)
    case modelNotFound
    
    var errorDescription: String? {
        switch self {
        case .downloadInProgress:
            return "Загрузка модели уже выполняется"
        case .downloadFailed(let error):
            return "Загрузка модели не удалась: \(error.localizedDescription)"
        case .modelNotFound:
            return "Модель не найдена"
        }
    }
}
