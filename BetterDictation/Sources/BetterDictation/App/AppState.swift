import SwiftUI
import Observation

@Observable
final class AppState {
    // MARK: - Сервисы
    let permissionManager: PermissionManager
    let hotkeyMonitor: ModifierKeyMonitor
    let modelManager: ModelManager
    var transcriptionService: ParakeetTranscriptionService?
    var dictationManager: DictationManager?
    
    // MARK: - Состояние
    private(set) var isRecording = false
    private(set) var lastTranscription: String = ""
    private(set) var modelState: ModelState = .notLoaded
    
    /// Прогресс загрузки в процентах (0-100)
    private(set) var downloadProgress: Double = 0
    
    /// Задача загрузки модели (для поддержки отмены)
    private var downloadTask: Task<Void, Never>?
    
    enum ModelState: Equatable {
        case notLoaded
        case downloading
        case loading  // Загрузка в память после скачивания
        case loaded
        case error(String)
    }
    
    /// Проверка, полностью ли настроено приложение и готово к использованию
    var isFullySetUp: Bool {
        permissionManager.allPermissionsGranted && modelState == .loaded
    }
    
    /// Форматированная строка прогресса загрузки
    var downloadProgressText: String {
        return String(format: "%.0f%%", downloadProgress)
    }
    
    // MARK: - Инициализация
    init() {
        self.permissionManager = PermissionManager()
        self.hotkeyMonitor = ModifierKeyMonitor()
        self.modelManager = ModelManager()
        
        setupHotkeyHandler()
        checkExistingModel()
    }
    
    private func setupHotkeyHandler() {
        hotkeyMonitor.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleDictation()
            }
        }
    }
    
    /// Проверка, была ли модель уже скачана
    private func checkExistingModel() {
        Task {
            // Если модель уже была скачана - загружаем её
            if modelManager.isModelDownloaded {
                print("Модель Parakeet уже скачана, загружаем...")
                await loadExistingModel()
            } else {
                print("Модель Parakeet ещё не скачана")
            }
        }
    }
    
    // MARK: - Управление моделями
    
    /// Скачать модель Parakeet TDT v3
    @MainActor
    func downloadModel() async {
        // Не скачиваем, если уже идёт загрузка
        guard modelState != .downloading else { return }
        
        // Выгружаем текущую модель, если загружена
        if modelState == .loaded {
            transcriptionService?.unloadModel()
            transcriptionService = nil
            dictationManager = nil
        }
        
        // Отменяем существующую загрузку
        downloadTask?.cancel()
        modelState = .downloading
        downloadProgress = 0
        
        downloadTask = Task {
            do {
                // Создаём сервис транскрипции
                let service = ParakeetTranscriptionService()
                
                // Настраиваем колбэк прогресса
                service.onDownloadProgress = { [weak self] percentage in
                    Task { @MainActor in
                        if percentage < 0 {
                            // Сигнал: загрузка завершена, теперь загрузка модели в память
                            self?.downloadProgress = 100
                            self?.modelState = .loading
                        } else {
                            self?.downloadProgress = percentage
                        }
                    }
                }
                
                // Скачиваем и загружаем модель
                try await service.downloadAndLoadModel()
                
                // Отмечаем модель как скачанную
                await MainActor.run {
                    self.modelManager.markAsDownloaded()
                    self.transcriptionService = service
                    self.modelState = .loaded
                    self.setupDictationManager()
                }
                
                print("Модель Parakeet успешно загружена и готова к работе")
                
            } catch {
                print("Ошибка загрузки: \(error)")
                if Task.isCancelled {
                    print("Загрузка была отменена")
                    await MainActor.run {
                        self.modelState = .notLoaded
                        self.downloadProgress = 0
                    }
                } else {
                    print("Загрузка не удалась: \(error.localizedDescription)")
                    await MainActor.run {
                        self.modelState = .error(error.localizedDescription)
                    }
                }
            }
        }
    }
    
    /// Отменить текущую загрузку модели
    @MainActor
    func cancelModelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        modelState = .notLoaded
        downloadProgress = 0
    }
    
    /// Загрузить существующую модель (уже скачанную)
    private func loadExistingModel() async {
        await MainActor.run {
            modelState = .loading
        }
        
        do {
            let service = ParakeetTranscriptionService()
            try await service.loadModel()
            
            await MainActor.run {
                self.transcriptionService = service
                self.modelState = .loaded
                self.setupDictationManager()
            }
            
            print("Модель Parakeet загружена из кэша")
            
        } catch {
            await MainActor.run {
                self.modelState = .error(error.localizedDescription)
            }
        }
    }
    
    /// Настроить менеджер диктовки после загрузки модели
    private func setupDictationManager() {
        guard let transcriptionService else { return }
        
        let audioService = AudioCaptureService()
        let textInsertionService = TextInsertionService()
        
        dictationManager = DictationManager(
            audioService: audioService,
            transcriptionService: transcriptionService,
            textInsertionService: textInsertionService
        )
        
        // Запускаем мониторинг горячих клавиш
        _ = hotkeyMonitor.start()
    }
    
    // MARK: - Управление диктовкой
    
    @MainActor
    func toggleDictation() {
        if isRecording {
            stopDictation()
        } else {
            startDictation()
        }
    }
    
    @MainActor
    func startDictation() {
        guard isFullySetUp else {
            print("Приложение не настроено - разрешения: \(permissionManager.allPermissionsGranted), модель: \(modelState)")
            return
        }
        
        isRecording = true
        dictationManager?.startDictation()
    }
    
    @MainActor
    func stopDictation() {
        isRecording = false
        dictationManager?.stopDictation()
    }
    
    // MARK: - Разрешения
    func requestPermissions() async {
        await permissionManager.requestAllPermissions()
    }
}
