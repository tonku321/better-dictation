import Carbon
import CoreGraphics
import Foundation

/// Мониторит нажатия одиночных клавиш-модификаторов через CGEvent tap.
/// По умолчанию: правый Option (keyCode 61)
final class ModifierKeyMonitor {
    // Коды клавиш-модификаторов
    static let leftOption: CGKeyCode = 58
    static let rightOption: CGKeyCode = 61
    static let leftCommand: CGKeyCode = 55
    static let rightCommand: CGKeyCode = 54
    static let leftShift: CGKeyCode = 56
    static let rightShift: CGKeyCode = 60
    static let leftControl: CGKeyCode = 59
    static let rightControl: CGKeyCode = 62
    static let fn: CGKeyCode = 63
    
    /// Код клавиши для мониторинга переключения
    var monitoredKeyCode: CGKeyCode = rightOption
    
    /// Вызывается при нажатии отслеживаемой клавиши (переключение)
    var onToggle: (() -> Void)?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    
    init() {}
    
    deinit {
        stop()
    }
    
    // MARK: - Запуск/Остановка мониторинга
    
    func start() -> Bool {
        guard eventTap == nil else { return true }
        
        // Нам нужно перехватывать события flagsChanged для клавиш-модификаторов
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        
        // Создаём event tap
        // Примечание: требуется разрешение Accessibility
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                
                let monitor = Unmanaged<ModifierKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap else {
            print("Не удалось создать event tap. Возможно, требуется разрешение Accessibility.")
            return false
        }
        
        // Создаём источник run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        
        guard let runLoopSource else {
            self.eventTap = nil
            return false
        }
        
        // Добавляем в run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Включаем tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        print("ModifierKeyMonitor запущен, отслеживается keyCode: \(monitoredKeyCode)")
        return true
    }
    
    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
        }
        
        eventTap = nil
        runLoopSource = nil
        isKeyDown = false
        
        print("ModifierKeyMonitor остановлен")
    }
    
    // MARK: - Обработка событий
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Обработка событий отключения tap (система может отключать taps при высокой нагрузке)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        guard type == .flagsChanged else {
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        
        // Обрабатываем только нашу отслеживаемую клавишу
        guard keyCode == monitoredKeyCode else {
            return Unmanaged.passRetained(event)
        }
        
        // Определяем, нажата клавиша или отпущена, проверяя флаги модификаторов
        let flags = event.flags
        let isNowDown = isModifierKeyDown(keyCode: keyCode, flags: flags)
        
        // Детектируем переход из отпущенного в нажатое (триггер переключения)
        if isNowDown && !isKeyDown {
            isKeyDown = true
            
            // Вызываем переключение в главном потоке
            DispatchQueue.main.async { [weak self] in
                self?.onToggle?()
            }
        } else if !isNowDown && isKeyDown {
            isKeyDown = false
        }
        
        // Пропускаем событие дальше (не поглощаем его)
        return Unmanaged.passRetained(event)
    }
    
    private func isModifierKeyDown(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case Self.leftOption, Self.rightOption:
            return flags.contains(.maskAlternate)
        case Self.leftCommand, Self.rightCommand:
            return flags.contains(.maskCommand)
        case Self.leftShift, Self.rightShift:
            return flags.contains(.maskShift)
        case Self.leftControl, Self.rightControl:
            return flags.contains(.maskControl)
        default:
            return false
        }
    }
}
