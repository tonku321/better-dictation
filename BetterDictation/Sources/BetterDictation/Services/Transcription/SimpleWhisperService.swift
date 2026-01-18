import Foundation
import Observation
import WhisperKit

/// Простой сервис транскрипции на базе Whisper large-v3-turbo
/// Накапливает аудио во время записи, транскрибирует при остановке
/// Поддерживает code-switching (русский + английский в одном аудио)
@Observable
final class SimpleWhisperService {
    // MARK: - Состояние
    
    private var whisperKit: WhisperKit?
    private(set) var isStreaming = false
    private(set) var isModelLoaded = false
    
    /// Накопленное аудио
    private var audioBuffer: [Float] = []
    
    // MARK: - Колбэки
    
    /// Вызывается когда текст готов для вставки
    var onConfirmedText: ((String) -> Void)?
    
    /// Колбэк прогресса загрузки
    var onDownloadProgress: ((Double) -> Void)?
    
    // MARK: - Пути
    
    /// Директория моделей
    var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BetterDictation/Models", isDirectory: true)
    }
    
    // MARK: - Управление моделями
    
    func downloadAndLoadModel() async throws {
        print("Скачивание модели Whisper large-v3-turbo...")
        
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        
        await MainActor.run {
            self.onDownloadProgress?(0)
        }
        
        // Скачиваем модель large-v3_turbo (с подчёркиванием!)
        let modelFolder = try await WhisperKit.download(
            variant: "large-v3_turbo",
            downloadBase: modelsDirectory,
            useBackgroundSession: false,
            progressCallback: { [weak self] progress in
                let percentage = progress.fractionCompleted * 100
                print("Прогресс: \(String(format: "%.1f", percentage))%")
                DispatchQueue.main.async {
                    self?.onDownloadProgress?(percentage)
                }
            }
        )
        
        print("Модель скачана: \(modelFolder.path)")
        
        await MainActor.run {
            self.onDownloadProgress?(-1)  // Сигнал: загрузка в память
        }
        
        // Загружаем модель
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            verbose: false,
            logLevel: .error
        )
        
        whisperKit = try await WhisperKit(config)
        isModelLoaded = true
        
        print("Whisper large-v3-turbo готов к работе")
    }
    
    func loadModel() async throws {
        try await downloadAndLoadModel()
    }
    
    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
    }
    
    // MARK: - Запись
    
    func startStreaming() async throws {
        guard isModelLoaded else {
            throw WhisperError.modelNotLoaded
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
        
        guard let whisper = whisperKit else {
            print("WhisperKit не инициализирован")
            return
        }
        
        isStreaming = false
        
        let duration = Double(audioBuffer.count) / 16000.0
        print("Транскрибируем \(audioBuffer.count) сэмплов (~\(String(format: "%.1f", duration)) сек)")
        
        do {
            // Настройки для multilingual с автоопределением языка
            let options = DecodingOptions(
                task: .transcribe,
                // Не указываем язык - Whisper сам определит и поддержит code-switching
                temperature: 0.0,
                temperatureFallbackCount: 3,
                sampleLength: 224,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: true
            )
            
            let results = try await whisper.transcribe(
                audioArray: audioBuffer,
                decodeOptions: options
            )
            
            let text = results
                .compactMap { $0.text }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "  ", with: " ")
            
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

enum WhisperError: LocalizedError {
    case modelNotLoaded
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Модель Whisper не загружена"
        }
    }
}
