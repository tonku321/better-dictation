import Foundation
import Observation
import FluidAudio

/// Простой сервис транскрипции на базе NVIDIA Parakeet TDT v3
/// Накапливает аудио во время записи, транскрибирует при остановке
@Observable
final class ParakeetTranscriptionService {
    // MARK: - Состояние
    
    private var asrManager: AsrManager?
    private var asrModels: AsrModels?
    private(set) var isStreaming = false
    private(set) var isModelLoaded = false
    
    /// Накопленное аудио
    private var audioBuffer: [Float] = []
    
    // MARK: - Колбэки
    
    /// Вызывается когда текст готов для вставки
    var onConfirmedText: ((String) -> Void)?
    
    /// Колбэк прогресса загрузки
    var onDownloadProgress: ((Double) -> Void)?
    
    // MARK: - Управление моделями
    
    func downloadAndLoadModel() async throws {
        print("Скачивание модели Parakeet TDT v3...")
        
        await MainActor.run {
            self.onDownloadProgress?(0)
        }
        
        asrModels = try await AsrModels.downloadAndLoad(version: .v3)
        
        print("Модель скачана, инициализируем...")
        
        await MainActor.run {
            self.onDownloadProgress?(-1)
        }
        
        asrManager = AsrManager(config: .default)
        
        guard let manager = asrManager, let models = asrModels else {
            throw ParakeetError.modelNotLoaded
        }
        
        try await manager.initialize(models: models)
        isModelLoaded = true
        
        print("Parakeet готов к работе")
    }
    
    func loadModel() async throws {
        try await downloadAndLoadModel()
    }
    
    func unloadModel() {
        asrManager = nil
        asrModels = nil
        isModelLoaded = false
    }
    
    // MARK: - Запись
    
    func startStreaming() async throws {
        guard isModelLoaded else {
            throw ParakeetError.modelNotLoaded
        }
        
        audioBuffer = []
        isStreaming = true
        print("Запись начата")
    }
    
    func stopStreaming() {
        isStreaming = false
        print("Запись остановлена")
    }
    
    /// Добавить аудио в буфер
    func processAudioChunk(_ samples: [Float]) async {
        guard isStreaming else { return }
        audioBuffer.append(contentsOf: samples)
    }
    
    /// Транскрибировать накопленное аудио
    func finalize() async {
        guard !audioBuffer.isEmpty else {
            print("Буфер пустой, нечего транскрибировать")
            return
        }
        
        guard let manager = asrManager else {
            print("AsrManager не инициализирован")
            return
        }
        
        isStreaming = false
        
        print("Транскрибируем \(audioBuffer.count) сэмплов (~\(Double(audioBuffer.count) / 16000.0) сек)")
        
        do {
            let result = try await manager.transcribe(audioBuffer)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            print("Результат: '\(text)'")
            
            if !text.isEmpty {
                onConfirmedText?(text)
            }
        } catch {
            print("Ошибка транскрипции: \(error)")
        }
        
        audioBuffer = []
    }
}

// MARK: - Ошибки

enum ParakeetError: LocalizedError {
    case modelNotLoaded
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Модель Parakeet не загружена"
        }
    }
}
