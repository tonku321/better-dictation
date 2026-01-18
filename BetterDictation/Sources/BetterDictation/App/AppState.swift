import SwiftUI
import Observation

@Observable
final class AppState {
    // MARK: - Сервисы
    let permissionManager: PermissionManager
    let hotkeyMonitor: ModifierKeyMonitor
    let modelManager: ModelManager
    var transcriptionService: StreamingTranscriptionService?
    var dictationManager: DictationManager?
    
    // MARK: - Состояние
    private(set) var isRecording = false
    private(set) var lastTranscription: String = ""
    private(set) var modelState: ModelState = .notLoaded
    
    /// Имя текущей загруженной модели
    private(set) var loadedModelName: String?
    
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
    
    /// Человекочитаемый путь к директории моделей
    var modelsPathDescription: String {
        let service = StreamingTranscriptionService()
        let path = service.modelsDirectory.path
        // Заменяем домашнюю директорию на ~
        if let home = FileManager.default.homeDirectoryForCurrentUser.path as String? {
            return path.replacingOccurrences(of: home, with: "~")
        }
        return path
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
    
    /// Проверка, была ли модель уже скачана (например, в предыдущей сессии)
    private func checkExistingModel() {
        Task {
            await modelManager.refreshDownloadedModels()
            
            print("Найдены скачанные модели: \(modelManager.downloadedModels)")
            
            let selected = modelManager.selectedModel
            
            // Если модель ещё не выбрана, не загружаем автоматически
            guard !selected.isEmpty else {
                print("Модель ещё не выбрана")
                return
            }
            
            // Проверяем, существует ли выбранная пользователем модель
            if modelManager.downloadedModels.contains(selected) {
                // Выбранная модель существует, загружаем её
                print("Загрузка выбранной модели: \(selected)")
                await loadExistingModel(selected)
            } else if !modelManager.downloadedModels.isEmpty {
                // Выбранная модель не скачана, но есть другие
                // Загружаем первую доступную и обновляем выбор
                if let firstModel = modelManager.downloadedModels.first {
                    print("Выбранная модель не найдена, загружаем: \(firstModel)")
                    modelManager.selectedModel = firstModel
                    await loadExistingModel(firstModel)
                }
            } else {
                print("Выбранная модель не скачана")
            }
            // Иначе остаёмся в состоянии .notLoaded
        }
    }
    
    // MARK: - Управление моделями
    
    /// Скачать выбранную модель
    @MainActor
    func downloadModel() async {
        let modelName = modelManager.selectedModel
        
        // Не скачиваем, если модель не выбрана
        guard !modelName.isEmpty else { return }
        
        // Не скачиваем, если уже идёт загрузка
        guard modelState != .downloading else { return }
        
        // Выгружаем текущую модель, если загружена
        if modelState == .loaded {
            transcriptionService?.unloadModel()
            transcriptionService = nil
            dictationManager = nil
            loadedModelName = nil
        }
        
        // Отменяем существующую загрузку
        downloadTask?.cancel()
        modelState = .downloading
        downloadProgress = 0
        
        downloadTask = Task {
            do {
                // Создаём сервис транскрипции
                let service = StreamingTranscriptionService()
                
                // Настраиваем колбэк прогресса
                service.onDownloadProgress = { [weak self] percentage in
                    if percentage < 0 {
                        // Сигнал: загрузка завершена, теперь загрузка модели в память
                        self?.downloadProgress = 100
                        self?.modelState = .loading
                    } else {
                        self?.downloadProgress = percentage
                    }
                }
                
                // Скачиваем и загружаем модель
                try await service.downloadAndLoadModel(modelName)
                
                // Обновляем список скачанных моделей
                await modelManager.refreshDownloadedModels()
                
                await MainActor.run {
                    self.transcriptionService = service
                    self.modelState = .loaded
                    self.loadedModelName = modelName
                    self.setupDictationManager()
                }
                
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
        
        print("downloadModel() завершила настройку задачи")
    }
    
    /// Отменить текущую загрузку модели
    @MainActor
    func cancelModelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        modelState = .notLoaded
        downloadProgress = 0
    }
    
    /// Удалить скачанную модель
    @MainActor
    func deleteModel(_ modelName: String) async {
        // Выгружаем, если сейчас загружена
        if loadedModelName == modelName {
            transcriptionService?.unloadModel()
            transcriptionService = nil
            dictationManager = nil
            loadedModelName = nil
            modelState = .notLoaded
        }
        
        // Удаляем с диска
        do {
            try modelManager.deleteModel(modelName)
            await modelManager.refreshDownloadedModels()
        } catch {
            print("Не удалось удалить модель: \(error)")
        }
    }
    
    /// Загрузить существующую модель (уже скачанную)
    private func loadExistingModel(_ modelName: String) async {
        await MainActor.run {
            modelState = .loading
        }
        
        do {
            let service = StreamingTranscriptionService()
            try await service.loadModel(modelName)
            
            await MainActor.run {
                self.transcriptionService = service
                self.modelState = .loaded
                self.loadedModelName = modelName
                self.setupDictationManager()
            }
        } catch {
            await MainActor.run {
                self.modelState = .error(error.localizedDescription)
            }
        }
    }
    
    /// Загрузить текущую выбранную модель (пользователь переключил модель)
    @MainActor
    func loadSelectedModel() async {
        let modelName = modelManager.selectedModel
        
        // Проверяем, не загружена ли уже
        if loadedModelName == modelName && modelState == .loaded {
            return
        }
        
        // Выгружаем текущую модель
        transcriptionService?.unloadModel()
        transcriptionService = nil
        dictationManager = nil
        
        await loadExistingModel(modelName)
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
