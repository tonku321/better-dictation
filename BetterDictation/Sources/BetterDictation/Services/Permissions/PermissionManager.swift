import AVFoundation
import ApplicationServices
import AppKit
import Observation

@Observable
final class PermissionManager {
    private(set) var microphoneStatus: PermissionStatus = .notDetermined
    private(set) var accessibilityStatus: PermissionStatus = .notDetermined
    
    enum PermissionStatus: Equatable {
        case notDetermined
        case granted
        case denied
    }
    
    var allPermissionsGranted: Bool {
        microphoneStatus == .granted && accessibilityStatus == .granted
    }
    
    init() {
        checkAllPermissions()
    }
    
    // MARK: - Проверка разрешений
    
    func checkAllPermissions() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
    }
    
    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .granted
        case .denied, .restricted:
            microphoneStatus = .denied
        case .notDetermined:
            microphoneStatus = .notDetermined
        @unknown default:
            microphoneStatus = .notDetermined
        }
    }
    
    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        accessibilityStatus = trusted ? .granted : .denied
    }
    
    // MARK: - Запрос разрешений
    
    func requestAllPermissions() async {
        await requestMicrophonePermission()
        requestAccessibilityPermission()
    }
    
    @discardableResult
    func requestMicrophonePermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            microphoneStatus = granted ? .granted : .denied
        }
        return granted
    }
    
    func requestAccessibilityPermission() {
        // Это покажет диалог пользователю, если ещё не доверено
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibilityStatus = trusted ? .granted : .denied
    }
    
    // MARK: - Открытие системных настроек
    
    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Опрос изменений
    
    func startPollingAccessibilityStatus() {
        // Опрашиваем каждую секунду для обнаружения выдачи разрешения пользователем
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            
            let wasGranted = self.accessibilityStatus == .granted
            self.checkAccessibilityPermission()
            
            if !wasGranted && self.accessibilityStatus == .granted {
                // Разрешение только что выдано
                timer.invalidate()
            }
        }
    }
}
