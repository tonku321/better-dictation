import SwiftUI
import Observation

@Observable
final class AppState {
    // MARK: - Сервисы
    let permissionManager: PermissionManager
    let hotkeyMonitor: ModifierKeyMonitor
    var transcriptionService: SimpleWhisperService?
    var dictationManager: DictationManager?
    
    // MARK: - Состояние
    private(set) var isRecording = false
    private(set) var modelState: ModelState = .notLoaded
    
    /// Прогресс загрузки в процентах (0-100)
    private(set) var downloadProgress: Double = 0
    
    /// Задача загрузки модели
    private var downloadTask: Task<Void, Never>?
    
    enum ModelState: Equatable {
        case notLoaded
        case downloading
        case loading
        case loaded
        case error(String)
    }
    
    /// Проверка, полностью ли настроено приложение
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
        
        setupHotkeyHandler()
    }
    
    private func setupHotkeyHandler() {
        hotkeyMonitor.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleDictation()
            }
        }
    }
    
    // MARK: - Управление моделью
    
    /// Скачать модель Whisper large-v3-turbo
    @MainActor
    func downloadModel() async {
        guard modelState != .downloading else { return }
        
        downloadTask?.cancel()
        modelState = .downloading
        downloadProgress = 0
        
        downloadTask = Task {
            do {
                let service = SimpleWhisperService()
                
                service.onDownloadProgress = { [weak self] percentage in
                    Task { @MainActor in
                        if percentage < 0 {
                            self?.downloadProgress = 100
                            self?.modelState = .loading
                        } else {
                            self?.downloadProgress = percentage
                        }
                    }
                }
                
                try await service.downloadAndLoadModel()
                
                await MainActor.run {
                    self.transcriptionService = service
                    self.modelState = .loaded
                    self.setupDictationManager()
                }
                
            } catch {
                print("Ошибка загрузки: \(error)")
                await MainActor.run {
                    if Task.isCancelled {
                        self.modelState = .notLoaded
                        self.downloadProgress = 0
                    } else {
                        self.modelState = .error(error.localizedDescription)
                    }
                }
            }
        }
    }
    
    /// Отменить загрузку
    @MainActor
    func cancelModelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        modelState = .notLoaded
        downloadProgress = 0
    }
    
    /// Настроить менеджер диктовки
    private func setupDictationManager() {
        guard let transcriptionService else { return }
        
        let audioService = AudioCaptureService()
        let textInsertionService = TextInsertionService()
        
        dictationManager = DictationManager(
            audioService: audioService,
            transcriptionService: transcriptionService,
            textInsertionService: textInsertionService
        )
        
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
            print("Приложение не настроено")
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
