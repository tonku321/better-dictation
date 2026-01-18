import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Скрыть иконку в dock (приложение-агент)
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Очистка: остановить активную диктовку, освободить ресурсы
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Продолжать работу в menu bar даже если все окна закрыты
        return false
    }
}
