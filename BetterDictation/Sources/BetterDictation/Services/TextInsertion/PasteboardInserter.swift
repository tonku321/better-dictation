import AppKit
import CoreGraphics

/// Вставляет текст через NSPasteboard и эмуляцию нажатия Cmd+V
/// Это запасной вариант, когда Accessibility API не работает
final class PasteboardInserter {
    
    /// Восстанавливать ли исходное содержимое буфера обмена после вставки
    var restoreOriginalPasteboard = true
    
    /// Задержка перед восстановлением буфера (чтобы вставка успела завершиться)
    var restoreDelay: TimeInterval = 0.3
    
    // MARK: - Вставка текста
    
    /// Вставить текст копированием в буфер обмена и эмуляцией Cmd+V
    /// - Parameter text: Текст для вставки
    /// - Returns: Завершилась ли операция (примечание: может всё равно не сработать в целевом приложении)
    func insertText(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        
        // Сохраняем текущее содержимое буфера обмена
        let previousContents = restoreOriginalPasteboard ? pasteboard.string(forType: .string) : nil
        
        // Устанавливаем наш текст
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Эмулируем Cmd+V
        let success = simulatePaste()
        
        // Восстанавливаем исходное содержимое после задержки
        if let previous = previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
        
        return success
    }
    
    // MARK: - Эмуляция клавиатуры
    
    /// Эмулировать нажатие Cmd+V
    private func simulatePaste() -> Bool {
        // Виртуальный код клавиши 'V' = 9
        let vKeyCode: CGKeyCode = 9
        
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("PasteboardInserter: Не удалось создать источник событий")
            return false
        }
        
        // Создаём событие нажатия клавиши
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            print("PasteboardInserter: Не удалось создать событие нажатия")
            return false
        }
        
        // Создаём событие отпускания клавиши
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            print("PasteboardInserter: Не удалось создать событие отпускания")
            return false
        }
        
        // Добавляем модификатор Command
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        // Отправляем события
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        
        return true
    }
    
    /// Эмулировать набор текста посимвольно (медленнее, но более совместимо)
    func typeText(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }
        
        for char in text {
            // Создаём событие клавиатуры
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            
            // Устанавливаем Unicode символ
            var unicodeChar = Array(String(char).utf16)
            keyDown.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)
            keyUp.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)
            
            // Отправляем события
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
            
            // Небольшая задержка между символами
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        return true
    }
}
