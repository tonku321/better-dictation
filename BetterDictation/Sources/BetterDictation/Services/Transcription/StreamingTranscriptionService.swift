import Foundation
import Observation
import WhisperKit

@Observable
final class StreamingTranscriptionService {
    // MARK: - Состояние

    private var whisperKit: WhisperKit?
    private(set) var isStreaming = false
    private(set) var isModelLoaded = false

    /// Накопленное аудио для текущего окна транскрипции
    private var audioBuffer: [Float] = []

    /// Предыдущая транскрипция для сравнения
    private var previousHypothesis: String = ""

    /// Подтверждённый текст, который уже был отправлен
    private var confirmedText: String = ""
    
    /// Отслеживание, идёт ли транскрипция в данный момент
    private var isTranscribing = false
    
    /// Аудио, пришедшее во время транскрипции
    private var pendingAudio: [Float] = []
    
    /// Количество последних подтверждённых слов для eager streaming
    private var lastConfirmedWordCount: Int = 0
    
    /// Порог энергии для детекции голосовой активности
    /// ОЧЕНЬ низкий порог, чтобы не пропускать тихую речь
    private let energyThreshold: Float = 0.00001

    // MARK: - Конфигурация

    /// Минимальная длина аудио перед попыткой транскрипции (в сэмплах при 16kHz)
    /// ~0.3 секунды - очень агрессивно для ощущения реального времени
    private let minAudioLength: Int = 4800

    /// Максимальное окно аудио для хранения (в сэмплах, ~5 секунд - очень короткое для скорости)
    private let maxAudioWindow: Int = 80000

    // MARK: - Колбэки

    /// Вызывается когда текст подтверждён и готов для вставки
    var onConfirmedText: ((String) -> Void)?

    /// Вызывается с гипотезой текста (для превью в UI, может меняться)
    var onHypothesisText: ((String) -> Void)?

    // MARK: - Управление моделями

    /// Директория моделей в Application Support
    var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BetterDictation/Models", isDirectory: true)
    }

    /// Колбэк прогресса загрузки (процент 0-100)
    var onDownloadProgress: ((Double) -> Void)?

    /// Скачать и загрузить модель с отчётом о прогрессе
    func downloadAndLoadModel(_ modelName: String = "base") async throws {
        print("Скачивание модели WhisperKit: \(modelName) в \(modelsDirectory.path)")

        // Создаём директорию моделей, если нужно
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        // Скачиваем модель с колбэком прогресса
        print("Запуск WhisperKit.download для варианта: \(modelName)")
        let modelFolder = try await WhisperKit.download(
            variant: modelName,
            downloadBase: modelsDirectory,
            useBackgroundSession: false,
            progressCallback: { [weak self] progress in
                let percentage = progress.fractionCompleted * 100
                print("Прогресс загрузки: \(String(format: "%.1f", percentage))%")

                DispatchQueue.main.async {
                    self?.onDownloadProgress?(percentage)
                }
            }
        )

        print("Модель скачана в: \(modelFolder.path)")

        // Сигнал о завершении загрузки, теперь загрузка в память
        DispatchQueue.main.async {
            self.onDownloadProgress?(-1)  // Сигнал: фаза загрузки в память
        }

        // Загружаем скачанную модель
        try await loadModelFromFolder(modelFolder.path)
    }

    /// Загрузить модель из локальной папки (уже скачанную)
    func loadModelFromFolder(_ folderPath: String) async throws {
        print("Загрузка модели WhisperKit из: \(folderPath)")

        let config = WhisperKitConfig(
            modelFolder: folderPath,
            verbose: false,
            logLevel: .error
        )

        whisperKit = try await WhisperKit(config)
        isModelLoaded = true

        print("Модель WhisperKit успешно загружена")
    }

    /// Загрузить модель - скачивает, если отсутствует
    func loadModel(_ modelName: String = "base") async throws {
        print("Загрузка модели WhisperKit: \(modelName) из \(modelsDirectory.path)")

        // Создаём директорию моделей, если нужно
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        // Проверяем, существует ли модель локально
        let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        )

        // Ищем папку, содержащую имя модели
        if let existingFolder = contents?.first(where: { $0.lastPathComponent.contains(modelName) }) {
            try await loadModelFromFolder(existingFolder.path)
            return
        }

        // Модель не найдена, нужно скачать
        try await downloadAndLoadModel(modelName)
    }

    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
    }

    // MARK: - Управление стримингом

    func startStreaming() async throws {
        guard isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }

        guard !isStreaming else { return }

        audioBuffer = []
        pendingAudio = []
        previousHypothesis = ""
        confirmedText = ""
        lastConfirmedWordCount = 0
        isTranscribing = false
        isStreaming = true

        print("Стриминговая транскрипция запущена")
    }

    func stopStreaming() {
        isStreaming = false
        print("Стриминговая транскрипция остановлена")
    }

    /// Финализировать и вернуть оставшийся текст
    func finalize() async {
        guard isStreaming else { return }

        isStreaming = false

        // Обрабатываем оставшееся аудио
        if audioBuffer.count >= minAudioLength {
            await processCurrentBuffer(isFinal: true)
        }

        audioBuffer = []
        previousHypothesis = ""
        confirmedText = ""

        print("Стриминговая транскрипция финализирована")
    }

    // MARK: - Обработка аудио
    
    /// Простая детекция голосовой активности на основе энергии
    private func hasVoiceActivity(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        let energy = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
        return energy > energyThreshold
    }

    func processAudioChunk(_ samples: [Float]) async {
        guard isStreaming else { 
            print("[DEBUG] processAudioChunk: не в режиме стриминга")
            return 
        }

        // Если уже идёт транскрипция, откладываем аудио на потом
        if isTranscribing {
            pendingAudio.append(contentsOf: samples)
            print("[DEBUG] Транскрипция идёт, добавлено в pending: \(samples.count) сэмплов")
            return
        }
        
        // Проверяем голосовую активность (но всегда добавляем, если буфер не пустой)
        let hasVoice = hasVoiceActivity(samples)
        if !hasVoice && audioBuffer.isEmpty {
            // Пропускаем только если тишина И буфер пустой
            return
        }
        
        if hasVoice {
            print("[DEBUG] Обнаружена голосовая активность, сэмплов: \(samples.count)")
        }

        // Добавляем сэмплы в буфер
        audioBuffer.append(contentsOf: samples)
        print("[DEBUG] Буфер аудио: \(audioBuffer.count) сэмплов")

        // Обрезаем буфер, если слишком длинный (скользящее окно) - более агрессивно
        if audioBuffer.count > maxAudioWindow {
            // Оставляем только недавнее аудио, отбрасываем старое
            let keepSamples = maxAudioWindow / 2
            audioBuffer = Array(audioBuffer.suffix(keepSamples))
            // Сбрасываем подтверждённый текст, так как потеряли контекст
            confirmedText = ""
            previousHypothesis = ""
            lastConfirmedWordCount = 0
        }

        // Обрабатываем, если достаточно аудио
        if audioBuffer.count >= minAudioLength {
            print("[DEBUG] Достаточно аудио (\(audioBuffer.count) >= \(minAudioLength)), запускаем транскрипцию")
            await processCurrentBuffer(isFinal: false)
            
            // Обрабатываем аудио, пришедшее во время транскрипции
            if !pendingAudio.isEmpty {
                print("[DEBUG] Добавляем pending аудио: \(pendingAudio.count) сэмплов")
                audioBuffer.append(contentsOf: pendingAudio)
                pendingAudio = []
            }
        }
    }

    private func processCurrentBuffer(isFinal: Bool) async {
        guard let whisper = whisperKit else { 
            print("[DEBUG] processCurrentBuffer: WhisperKit не загружен!")
            return 
        }
        guard !isTranscribing else { 
            print("[DEBUG] processCurrentBuffer: уже идёт транскрипция")
            return 
        }
        
        isTranscribing = true
        defer { isTranscribing = false }
        
        print("[DEBUG] Начинаем транскрипцию буфера: \(audioBuffer.count) сэмплов, isFinal: \(isFinal)")

        do {
            // Оптимизированные параметры декодирования для стриминга в реальном времени
            // Язык НЕ указываем - модель определит автоматически
            // Важно: distil модели поддерживают только английский!
            let options = DecodingOptions(
                task: .transcribe,
                temperature: 0.0,
                temperatureFallbackCount: 0,  // Без повторных попыток - быстрее
                sampleLength: 224,  // Короткая длина сэмпла для быстрого декодирования
                usePrefillPrompt: false,  // Без предзаполнения - быстрее
                usePrefillCache: true,  // Используем кэш для скорости
                skipSpecialTokens: true,  // Пропускаем специальные токены
                withoutTimestamps: true,  // Без временных меток - быстрее
                clipTimestamps: []
            )

            print("[DEBUG] Вызываем whisper.transcribe...")
            let results = try await whisper.transcribe(
                audioArray: audioBuffer,
                decodeOptions: options
            )
            print("[DEBUG] Транскрипция завершена, результатов: \(results.count)")

            // Извлекаем текст
            let hypothesis = results
                .compactMap { $0.text }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "  ", with: " ")
            
            print("[DEBUG] Гипотеза: '\(hypothesis)'")
            
            guard !hypothesis.isEmpty else { 
                print("[DEBUG] Гипотеза пустая, пропускаем")
                return 
            }

            // Eager streaming: немедленно выводим новые слова
            let currentWords = hypothesis.split(separator: " ").map(String.init)
            let previousWords = previousHypothesis.split(separator: " ").map(String.init)
            
            print("[DEBUG] Текущие слова: \(currentWords.count), предыдущие: \(previousWords.count)")
            print("[DEBUG] lastConfirmedWordCount: \(lastConfirmedWordCount)")
            
            if isFinal {
                // При финализации выводим всё, что ещё не подтверждено
                let remaining = getUnconfirmedText(from: hypothesis)
                print("[DEBUG] FINAL - оставшийся текст: '\(remaining)'")
                if !remaining.isEmpty {
                    onConfirmedText?(remaining)
                }
            } else {
                // Находим стабильный префикс (слова, совпадающие с предыдущей транскрипцией)
                let stableWords = findStablePrefix(current: currentWords, previous: previousWords)
                print("[DEBUG] Стабильных слов: \(stableWords.count)")
                
                // Выводим новые стабильные слова немедленно
                if stableWords.count > lastConfirmedWordCount {
                    let newWords = Array(stableWords.dropFirst(lastConfirmedWordCount))
                    let newText = newWords.joined(separator: " ")
                    let prefix = lastConfirmedWordCount > 0 ? " " : ""
                    
                    print("[DEBUG] ПОДТВЕРЖДАЕМ ТЕКСТ: '\(prefix + newText)'")
                    onConfirmedText?(prefix + newText)
                    confirmedText += prefix + newText
                    lastConfirmedWordCount = stableWords.count
                    
                    // Агрессивно обрезаем аудио после подтверждения
                    trimConfirmedAudio(wordCount: stableWords.count)
                } else {
                    print("[DEBUG] Нет новых стабильных слов (stableWords: \(stableWords.count), lastConfirmed: \(lastConfirmedWordCount))")
                }
                
                // Показываем неподтверждённую гипотезу
                if currentWords.count > stableWords.count {
                    let unconfirmed = currentWords.dropFirst(stableWords.count).joined(separator: " ")
                    onHypothesisText?(unconfirmed)
                } else {
                    onHypothesisText?("")
                }
            }

            previousHypothesis = hypothesis

        } catch {
            print("Ошибка транскрипции: \(error)")
        }
    }
    
    private func findStablePrefix(current: [String], previous: [String]) -> [String] {
        var stable: [String] = []
        let minLen = min(current.count, previous.count)
        
        for i in 0..<minLen {
            // Регистронезависимое сравнение для стабильности
            if current[i].lowercased() == previous[i].lowercased() {
                stable.append(current[i])
            } else {
                break
            }
        }
        
        return stable
    }
    
    private func getUnconfirmedText(from hypothesis: String) -> String {
        let hypWords = hypothesis.split(separator: " ").map(String.init)
        if hypWords.count > lastConfirmedWordCount {
            let newWords = Array(hypWords.dropFirst(lastConfirmedWordCount))
            let prefix = lastConfirmedWordCount > 0 ? " " : ""
            return prefix + newWords.joined(separator: " ")
        }
        return ""
    }
    
    /// Агрессивно обрезаем буфер аудио после подтверждения слов
    private func trimConfirmedAudio(wordCount: Int) {
        // ~3.5 слова в секунду при нормальной речи = ~4500 сэмплов на слово
        let estimatedSamples = wordCount * 4500
        // Оставляем минимальный overlap (0.3 сек) для контекста
        let keepOverlap = 4800
        let samplesToRemove = max(0, estimatedSamples - keepOverlap)
        
        if samplesToRemove > 0 && samplesToRemove < audioBuffer.count {
            audioBuffer.removeFirst(samplesToRemove)
        }
    }

}

// MARK: - Ошибки

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Модель распознавания речи не загружена"
        case .transcriptionFailed(let error):
            return "Ошибка транскрипции: \(error.localizedDescription)"
        }
    }
}
