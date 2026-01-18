import Foundation
import Observation

/// Менеджер моделей для Parakeet TDT
/// Parakeet v3 - единственная модель, но она поддерживает 25 языков
@Observable
final class ModelManager {
    // MARK: - Состояние
    
    private(set) var isModelDownloaded = false
    private(set) var downloadProgress: Double = 0
    private(set) var isDownloading = false
    
    // MARK: - Ключи UserDefaults
    private let modelDownloadedKey = "parakeetModelDownloaded"
    
    // MARK: - Инициализация
    
    init() {
        // Проверяем, была ли модель уже скачана
        // FluidAudio сам управляет кэшированием, но мы отслеживаем состояние
        self.isModelDownloaded = UserDefaults.standard.bool(forKey: modelDownloadedKey)
    }
    
    // MARK: - Информация о модели
    
    /// Информация о модели Parakeet TDT v3
    static let modelInfo = ParakeetModelInfo(
        name: "Parakeet TDT v3",
        size: "~600 MB",
        description: "NVIDIA Parakeet - сверхбыстрая multilingual модель",
        languages: [
            "🇷🇺 Русский", "🇬🇧 English", "🇺🇦 Українська",
            "🇩🇪 Deutsch", "🇫🇷 Français", "🇪🇸 Español",
            "🇮🇹 Italiano", "🇵🇱 Polski", "🇳🇱 Nederlands",
            "и ещё 16 европейских языков"
        ],
        features: [
            "⚡ В 10x быстрее Whisper Large V3",
            "🌍 Автоопределение языка",
            "🔀 Code-switching (русский + английский)",
            "🎯 WER 3-5% для русского",
            "🧠 Оптимизирован для Apple Neural Engine"
        ]
    )
    
    // MARK: - Управление загрузкой
    
    func markAsDownloaded() {
        isModelDownloaded = true
        UserDefaults.standard.set(true, forKey: modelDownloadedKey)
    }
    
    func resetDownloadState() {
        isModelDownloaded = false
        UserDefaults.standard.set(false, forKey: modelDownloadedKey)
    }
}

// MARK: - Информация о модели Parakeet

struct ParakeetModelInfo {
    let name: String
    let size: String
    let description: String
    let languages: [String]
    let features: [String]
}
