import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("Основные", systemImage: "gear")
                }
            
            HotkeySettingsView()
                .tabItem {
                    Label("Горячие клавиши", systemImage: "keyboard")
                }
            
            ModelSettingsView()
                .tabItem {
                    Label("Модель", systemImage: "cpu")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - Основные настройки

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    var body: some View {
        Form {
            Toggle("Запускать при входе", isOn: $launchAtLogin)
            
            // TODO: Добавить больше общих настроек
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Настройки горячих клавиш

struct HotkeySettingsView: View {
    @State private var selectedKey: HotkeyOption = .rightOption
    
    enum HotkeyOption: String, CaseIterable {
        case rightOption = "Правый Option (⌥)"
        case leftOption = "Левый Option (⌥)"
        case rightCommand = "Правый Command (⌘)"
        case fn = "Fn"
        
        var keyCode: CGKeyCode {
            switch self {
            case .rightOption: return ModifierKeyMonitor.rightOption
            case .leftOption: return ModifierKeyMonitor.leftOption
            case .rightCommand: return ModifierKeyMonitor.rightCommand
            case .fn: return ModifierKeyMonitor.fn
            }
        }
    }
    
    var body: some View {
        Form {
            Picker("Клавиша диктовки", selection: $selectedKey) {
                ForEach(HotkeyOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            
            Text("Нажмите выбранную клавишу для включения/выключения диктовки")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Настройки модели

struct ModelSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedModel: WhisperModel = .base
    
    enum WhisperModel: String, CaseIterable {
        case tiny = "tiny"
        case base = "base"
        case small = "small"
        case medium = "medium"
        case large = "large-v3"
        
        var displayName: String {
            switch self {
            case .tiny: return "Tiny (~75MB, самая быстрая)"
            case .base: return "Base (~140MB, быстрая)"
            case .small: return "Small (~460MB, баланс)"
            case .medium: return "Medium (~1.4GB, точная)"
            case .large: return "Large V3 (~3GB, самая точная)"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Модель Whisper", selection: $selectedModel) {
                ForEach(WhisperModel.allCases, id: \.self) { model in
                    Text(model.displayName).tag(model)
                }
            }
            
            Text("Большие модели точнее, но требуют больше памяти и работают медленнее.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Статус модели
            HStack {
                Text("Статус:")
                Spacer()
                modelStatusText
            }
            
            Button("Скачать / Загрузить модель") {
                Task {
                    await appState.downloadModel()
                }
            }
            .disabled(appState.modelState == .loaded || appState.modelState == .downloading)
        }
        .padding()
    }
    
    @ViewBuilder
    private var modelStatusText: some View {
        switch appState.modelState {
        case .notLoaded:
            Text("Не загружена")
                .foregroundStyle(.secondary)
        case .downloading:
            Text("Скачивание...")
                .foregroundStyle(.blue)
        case .loading:
            Text("Загрузка...")
                .foregroundStyle(.blue)
        case .loaded:
            Text("Готова")
                .foregroundStyle(.green)
        case .error(let message):
            Text(message)
                .foregroundStyle(.red)
        }
    }
}
