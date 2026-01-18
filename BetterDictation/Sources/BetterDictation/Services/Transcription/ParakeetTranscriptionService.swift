import Foundation
import Observation
import FluidAudio

/// Сервис транскрипции на базе NVIDIA Parakeet TDT v3
/// Поддерживает 25 европейских языков включая русский и английский
/// Автоматически определяет язык - идеально для code-switching (русский + английский)
@Observable
final class ParakeetTranscriptionService {
    // MARK: - Состояние
    
    private var asrManager: AsrManager?
    private var asrModels: AsrModels?
    private(set) var isStreaming = false
    private(set) var isModelLoaded = false
    
    /// Накопленное аудио для текущего окна транскрипции
    private var audioBuffer: [Float] = []
    
    /// Подтверждённый текст, который уже был отправлен
    private var confirmedText: String = ""
    
    /// Отслеживание, идёт ли транскрипция в данный момент
    private var isTranscribing = false
    
    /// Аудио, пришедшее во время транскрипции
    private var pendingAudio: [Float] = []
    
    /// Порог энергии для детекции голосовой активности
    private let energyThreshold: Float = 0.00001
    
    // MARK: - Конфигурация
    
    /// Минимальная длина аудио перед попыткой транскрипции (в сэмплах при 16kHz)
    /// Parakeet очень быстрый, можно обрабатывать чаще
    private let minAudioLength: Int = 8000  // ~0.5 секунды
    
    /// Максимальное окно аудио для хранения (в сэмплах, ~10 секунд)
    private let maxAudioWindow: Int = 160000
    
    // MARK: - Колбэки
    
    /// Вызывается когда текст подтверждён и готов для вставки
    var onConfirmedText: ((String) -> Void)?
    
    /// Вызывается с гипотезой текста (для превью в UI)
    var onHypothesisText: ((String) -> Void)?
    
    /// Колбэк прогресса загрузки (процент 0-100, -1 = загрузка в память)
    var onDownloadProgress: ((Double) -> Void)?
    
    // MARK: - Управление моделями
    
    /// Скачать и загрузить модель Parakeet v3
    func downloadAndLoadModel() async throws {
        print("Скачивание модели Parakeet TDT v3...")
        
        // Сообщаем о начале загрузки
        await MainActor.run {
            self.onDownloadProgress?(0)
        }
        
        // Скачиваем модель
        // FluidAudio сам управляет кэшированием моделей
        asrModels = try await AsrModels.downloadAndLoad(version: .v3)
        
        print("Модель скачана, инициализируем AsrManager...")
        
        // Сигнал о завершении загрузки, теперь загрузка в память
        await MainActor.run {
            self.onDownloadProgress?(-1)
        }
        
        // Создаём и инициализируем менеджер
        asrManager = AsrManager(config: .default)
        
        guard let manager = asrManager, let models = asrModels else {
            throw ParakeetError.modelNotLoaded
        }
        
        try await manager.initialize(models: models)
        isModelLoaded = true
        
        print("Parakeet TDT v3 успешно загружен и готов к работе")
    }
    
    /// Загрузить модель (скачает если нужно)
    func loadModel() async throws {
        try await downloadAndLoadModel()
    }
    
    func unloadModel() {
        asrManager = nil
        asrModels = nil
        isModelLoaded = false
    }
    
    // MARK: - Управление стримингом
    
    func startStreaming() async throws {
        guard isModelLoaded else {
            throw ParakeetError.modelNotLoaded
        }
        
        guard !isStreaming else { return }
        
        audioBuffer = []
        pendingAudio = []
        confirmedText = ""
        isTranscribing = false
        isStreaming = true
        
        print("Parakeet стриминговая транскрипция запущена")
    }
    
    func stopStreaming() {
        isStreaming = false
        print("Parakeet стриминговая транскрипция остановлена")
    }
    
    /// Финализировать и вернуть оставшийся текст
    func finalize() async {
        guard isStreaming else { return }
        
        isStreaming = false
        
        // Обрабатываем оставшееся аудио
        if audioBuffer.count >= minAudioLength / 2 {
            await processCurrentBuffer(isFinal: true)
        }
        
        audioBuffer = []
        confirmedText = ""
        
        print("Parakeet транскрипция финализирована")
    }
    
    // MARK: - Обработка аудио
    
    /// Простая детекция голосовой активности на основе энергии
    private func hasVoiceActivity(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        let energy = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
        return energy > energyThreshold
    }
    
    func processAudioChunk(_ samples: [Float]) async {
        guard isStreaming else { return }
        
        // Если уже идёт транскрипция, откладываем аудио на потом
        if isTranscribing {
            pendingAudio.append(contentsOf: samples)
            return
        }
        
        // Проверяем голосовую активность
        let hasVoice = hasVoiceActivity(samples)
        if !hasVoice && audioBuffer.isEmpty {
            return
        }
        
        // Добавляем сэмплы в буфер
        audioBuffer.append(contentsOf: samples)
        
        // Обрезаем буфер, если слишком длинный
        if audioBuffer.count > maxAudioWindow {
            let keepSamples = maxAudioWindow / 2
            audioBuffer = Array(audioBuffer.suffix(keepSamples))
            confirmedText = ""
        }
        
        // Обрабатываем, если достаточно аудио
        if audioBuffer.count >= minAudioLength {
            await processCurrentBuffer(isFinal: false)
            
            // Обрабатываем аудио, пришедшее во время транскрипции
            if !pendingAudio.isEmpty {
                audioBuffer.append(contentsOf: pendingAudio)
                pendingAudio = []
            }
        }
    }
    
    private func processCurrentBuffer(isFinal: Bool) async {
        guard let manager = asrManager else {
            print("[Parakeet] AsrManager не инициализирован!")
            return
        }
        guard !isTranscribing else { return }
        
        isTranscribing = true
        defer { isTranscribing = false }
        
        do {
            // Parakeet принимает [Float] напрямую - 16kHz моно PCM
            let result = try await manager.transcribe(audioBuffer)
            
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !text.isEmpty else { return }
            
            if isFinal {
                // При финализации выводим весь новый текст
                let newText = getNewText(from: text)
                if !newText.isEmpty {
                    onConfirmedText?(newText)
                }
            } else {
                // Сравниваем с предыдущим подтверждённым текстом
                let newText = getNewText(from: text)
                
                if !newText.isEmpty {
                    // Parakeet очень стабильный, можно сразу выводить
                    onConfirmedText?(newText)
                    confirmedText = text
                    
                    // Очищаем буфер после успешной транскрипции
                    // Оставляем небольшой overlap для контекста
                    let overlapSamples = 8000  // 0.5 сек
                    if audioBuffer.count > overlapSamples {
                        audioBuffer = Array(audioBuffer.suffix(overlapSamples))
                    }
                }
            }
            
        } catch {
            print("Ошибка транскрипции Parakeet: \(error)")
        }
    }
    
    /// Получить новый текст, который ещё не был подтверждён
    private func getNewText(from fullText: String) -> String {
        if confirmedText.isEmpty {
            return fullText
        }
        
        // Если новый текст начинается с подтверждённого - возвращаем разницу
        if fullText.hasPrefix(confirmedText) {
            let newPart = String(fullText.dropFirst(confirmedText.count))
            return newPart.trimmingCharacters(in: .whitespaces)
        }
        
        // Если текст изменился полностью - возвращаем весь новый
        return fullText
    }
}

// MARK: - Ошибки

enum ParakeetError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Модель Parakeet не загружена"
        case .transcriptionFailed(let error):
            return "Ошибка транскрипции: \(error.localizedDescription)"
        }
    }
}
