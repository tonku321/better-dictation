import Foundation

/// Фасад для вставки текста, пробующий несколько стратегий
final class TextInsertionService {
    private let accessibilityInserter = AccessibilityInserter()
    private let pasteboardInserter = PasteboardInserter()
    
    /// Отслеживание, находимся ли мы в начале ввода (для логики пробелов)
    private var isStartOfInput = true
    
    // MARK: - Вставка текста
    
    /// Вставить текст используя лучший доступный метод
    /// - Parameter text: Текст для вставки (может быть словом или несколькими словами)
    /// - Returns: Успешна ли вставка
    @discardableResult
    func insertText(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        
        // Сначала пробуем accessibility (наиболее надёжный, когда доступен)
        if accessibilityInserter.insertText(text) {
            isStartOfInput = false
            return true
        }
        
        // Откатываемся на метод через буфер обмена
        if pasteboardInserter.insertText(text) {
            isStartOfInput = false
            return true
        }
        
        print("Не удалось вставить текст: \(text)")
        return false
    }
    
    /// Сбросить состояние для новой сессии диктовки
    func reset() {
        isStartOfInput = true
    }
    
    /// Проверить, сможет ли вставка текста работать
    func canInsertText() -> Bool {
        return accessibilityInserter.canInsertText() || true // буфер обмена всегда "работает"
    }
}
