import ApplicationServices
import AppKit

/// Вставляет текст используя macOS Accessibility API (AXUIElement)
final class AccessibilityInserter {
    
    // MARK: - Вставка текста
    
    /// Вставить текст в текущее сфокусированное текстовое поле
    /// - Parameter text: Текст для вставки
    /// - Returns: Успешна ли вставка
    func insertText(_ text: String) -> Bool {
        // Получаем системный accessibility элемент
        let systemWide = AXUIElementCreateSystemWide()
        
        // Получаем сфокусированный UI элемент
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard focusResult == .success, let element = focusedElement else {
            print("AccessibilityInserter: Сфокусированный элемент не найден")
            return false
        }
        
        let axElement = element as! AXUIElement
        
        // Пробуем разные стратегии вставки
        
        // Стратегия 1: Вставка в позицию выделенного текста (лучшая для позиции курсора)
        if insertAtSelection(axElement, text: text) {
            return true
        }
        
        // Стратегия 2: Добавление к существующему значению
        if appendToValue(axElement, text: text) {
            return true
        }
        
        // Стратегия 3: Установка всего значения (запасной вариант)
        if setValue(axElement, text: text) {
            return true
        }
        
        return false
    }
    
    /// Проверить, можем ли вставить текст (есть разрешение accessibility)
    func canInsertText() -> Bool {
        return AXIsProcessTrusted()
    }
    
    // MARK: - Стратегии вставки
    
    /// Вставить текст в текущую позицию выделения/курсора
    private func insertAtSelection(_ element: AXUIElement, text: String) -> Bool {
        // Устанавливаем выделенный текст на наш новый текст (заменяет выделение или вставляет в курсор)
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        
        if result == .success {
            return true
        }
        
        return false
    }
    
    /// Добавить текст к существующему значению
    private func appendToValue(_ element: AXUIElement, text: String) -> Bool {
        // Получаем текущее значение
        var currentValue: CFTypeRef?
        let getResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &currentValue
        )
        
        guard getResult == .success, let value = currentValue as? String else {
            return false
        }
        
        // Получаем текущую позицию курсора (диапазон выделенного текста)
        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )
        
        var newValue: String
        var newCursorPosition: Int
        
        if rangeResult == .success,
           let range = selectedRange,
           CFGetTypeID(range) == AXValueGetTypeID(),
           let cfRange = extractRange(from: range as! AXValue) {
            // Вставляем в позицию курсора
            let insertIndex = value.index(value.startIndex, offsetBy: cfRange.location, limitedBy: value.endIndex) ?? value.endIndex
            newValue = value
            newValue.insert(contentsOf: text, at: insertIndex)
            newCursorPosition = cfRange.location + text.count
        } else {
            // Добавляем в конец
            newValue = value + text
            newCursorPosition = newValue.count
        }
        
        // Устанавливаем новое значение
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            newValue as CFTypeRef
        )
        
        guard setResult == .success else {
            return false
        }
        
        // Перемещаем курсор в конец вставленного текста
        setCursorPosition(element, position: newCursorPosition)
        
        return true
    }
    
    /// Установить всё значение элемента
    private func setValue(_ element: AXUIElement, text: String) -> Bool {
        // Сначала получаем текущее значение
        var currentValue: CFTypeRef?
        let getResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &currentValue
        )
        
        let existingText = (getResult == .success) ? (currentValue as? String ?? "") : ""
        let newValue = existingText + text
        
        let result = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            newValue as CFTypeRef
        )
        
        return result == .success
    }
    
    // MARK: - Вспомогательные методы
    
    private func extractRange(from axValue: AXValue) -> CFRange? {
        var range = CFRange(location: 0, length: 0)
        let success = AXValueGetValue(axValue, .cfRange, &range)
        return success ? range : nil
    }
    
    private func setCursorPosition(_ element: AXUIElement, position: Int) {
        var range = CFRange(location: position, length: 0)
        if let axValue = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                axValue
            )
        }
    }
}
