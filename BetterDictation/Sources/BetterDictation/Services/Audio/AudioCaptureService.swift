import AVFoundation
import Observation

@Observable
final class AudioCaptureService {
    // MARK: - Константы
    
    /// Whisper требует частоту дискретизации 16kHz
    static let targetSampleRate: Double = 16000.0
    
    /// Размер буфера для audio tap
    static let bufferSize: AVAudioFrameCount = 1024
    
    /// Размер чанка для отправки в транскрипцию (в сэмплах, ~0.3 секунды)
    /// Маленькие чанки для более отзывчивого стриминга
    static let chunkSize: Int = 4800
    
    // MARK: - Состояние
    
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var accumulatedSamples: [Float] = []
    
    private(set) var isCapturing = false
    
    /// Вызывается когда чанк аудио готов для транскрипции
    var onAudioChunk: (([Float]) -> Void)?
    
    // MARK: - Управление захватом
    
    func startCapture() async throws {
        guard !isCapturing else { return }
        
        // Создаём audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw AudioCaptureError.engineCreationFailed
        }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Проверяем формат входа
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioCaptureError.invalidInputFormat
        }
        
        // Создаём целевой формат для Whisper (16kHz, моно, float)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatCreationFailed
        }
        
        // Создаём конвертер, если частоты дискретизации отличаются
        if inputFormat.sampleRate != Self.targetSampleRate || inputFormat.channelCount != 1 {
            audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
            guard audioConverter != nil else {
                throw AudioCaptureError.converterCreationFailed
            }
        }
        
        accumulatedSamples = []
        
        // Устанавливаем tap на входной узел
        inputNode.installTap(
            onBus: 0,
            bufferSize: Self.bufferSize,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, outputFormat: outputFormat)
        }
        
        // Запускаем engine
        engine.prepare()
        try engine.start()
        
        isCapturing = true
        print("Захват аудио запущен (вход: \(inputFormat.sampleRate)Hz, выход: \(Self.targetSampleRate)Hz)")
    }
    
    func stopCapture() {
        guard isCapturing else { return }
        
        // Удаляем tap
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        // Останавливаем engine
        audioEngine?.stop()
        audioEngine = nil
        audioConverter = nil
        
        // Отправляем оставшиеся сэмплы
        if !accumulatedSamples.isEmpty {
            onAudioChunk?(accumulatedSamples)
            accumulatedSamples = []
        }
        
        isCapturing = false
        print("Захват аудио остановлен")
    }
    
    // MARK: - Обработка аудио
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) {
        let samples: [Float]
        
        if let converter = audioConverter {
            // Нужна конвертация формата
            guard let convertedBuffer = convertBuffer(buffer, using: converter, to: outputFormat) else {
                return
            }
            samples = extractSamples(from: convertedBuffer)
        } else {
            // Уже в правильном формате
            samples = extractSamples(from: buffer)
        }
        
        // Накапливаем сэмплы
        accumulatedSamples.append(contentsOf: samples)
        
        // Отправляем чанк, если накопилось достаточно
        while accumulatedSamples.count >= Self.chunkSize {
            let chunk = Array(accumulatedSamples.prefix(Self.chunkSize))
            accumulatedSamples.removeFirst(Self.chunkSize)
            onAudioChunk?(chunk)
        }
    }
    
    private func convertBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        // Вычисляем ёмкость выходных фреймов
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        guard status != .error, error == nil else {
            print("Ошибка конвертации аудио: \(error?.localizedDescription ?? "неизвестно")")
            return nil
        }
        
        return outputBuffer
    }
    
    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }
        
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        
        return samples
    }
}

// MARK: - Ошибки

enum AudioCaptureError: LocalizedError {
    case engineCreationFailed
    case invalidInputFormat
    case formatCreationFailed
    case converterCreationFailed
    case captureFailed(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .engineCreationFailed:
            return "Не удалось создать audio engine"
        case .invalidInputFormat:
            return "Неверный формат аудио входа"
        case .formatCreationFailed:
            return "Не удалось создать формат аудио"
        case .converterCreationFailed:
            return "Не удалось создать конвертер аудио"
        case .captureFailed(let error):
            return "Захват аудио не удался: \(error.localizedDescription)"
        }
    }
}
