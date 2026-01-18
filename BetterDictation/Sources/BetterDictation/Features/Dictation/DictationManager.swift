import Foundation
import Observation

@Observable
final class DictationManager {
    // MARK: - Зависимости
    private let audioService: AudioCaptureService
    private let transcriptionService: SimpleWhisperService
    private let textInsertionService: TextInsertionService
    
    // MARK: - Состояние
    private(set) var isActive = false
    private(set) var currentTranscription = ""
    
    // MARK: - Колбэки
    var onTranscriptionUpdate: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    
    // MARK: - Инициализация
    
    init(
        audioService: AudioCaptureService,
        transcriptionService: SimpleWhisperService,
        textInsertionService: TextInsertionService
    ) {
        self.audioService = audioService
        self.transcriptionService = transcriptionService
        self.textInsertionService = textInsertionService
        
        setupTranscriptionCallback()
    }
    
    private func setupTranscriptionCallback() {
        transcriptionService.onConfirmedText = { [weak self] text in
            self?.handleConfirmedText(text)
        }
    }
    
    // MARK: - Управление диктовкой
    
    func startDictation() {
        guard !isActive else { return }
        
        isActive = true
        currentTranscription = ""
        
        Task {
            do {
                // Запускаем захват аудио
                try await audioService.startCapture()
                
                // Запускаем сервис транскрипции
                try await transcriptionService.startStreaming()
                
                // Передаём аудио в транскрипцию
                audioService.onAudioChunk = { [weak self] samples in
                    Task {
                        await self?.transcriptionService.processAudioChunk(samples)
                    }
                }
                
                print("Диктовка запущена")
            } catch {
                await MainActor.run {
                    self.isActive = false
                    self.onError?(error)
                }
            }
        }
    }
    
    func stopDictation() {
        guard isActive else { return }
        
        isActive = false
        
        // Останавливаем захват аудио
        audioService.stopCapture()
        
        // Финализируем транскрипцию
        Task {
            await transcriptionService.finalize()
        }
        
        print("Диктовка остановлена")
    }
    
    // MARK: - Обработка текста
    
    private func handleConfirmedText(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Обновляем текущую транскрипцию
        currentTranscription += text
        onTranscriptionUpdate?(text)
        
        // Вставляем текст немедленно
        Task { @MainActor in
            textInsertionService.insertText(text)
        }
    }
}

// MARK: - Ошибки

enum DictationError: LocalizedError {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case audioCaptureFailed(underlying: Error)
    case modelNotLoaded
    case transcriptionFailed(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Для диктовки требуется разрешение на использование микрофона"
        case .accessibilityPermissionDenied:
            return "Для вставки текста требуется разрешение Accessibility"
        case .audioCaptureFailed(let error):
            return "Не удалось захватить аудио: \(error.localizedDescription)"
        case .modelNotLoaded:
            return "Модель распознавания речи не загружена"
        case .transcriptionFailed(let error):
            return "Ошибка транскрипции: \(error.localizedDescription)"
        }
    }
}
