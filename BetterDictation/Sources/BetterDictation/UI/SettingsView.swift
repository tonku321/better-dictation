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
        .frame(width: 450, height: 350)
    }
}

// MARK: - Основные настройки

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    var body: some View {
        Form {
            Toggle("Запускать при входе", isOn: $launchAtLogin)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Заголовок
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading) {
                        Text("Whisper large-v3-turbo")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("~1.5 GB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text("OpenAI Whisper с поддержкой code-switching")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Особенности
            VStack(alignment: .leading, spacing: 6) {
                Text("Особенности:")
                    .font(.headline)
                
                Text("🌍 99+ языков с автоопределением")
                    .font(.caption)
                Text("🔀 Code-switching (русский + английский)")
                    .font(.caption)
                Text("⚡ Turbo версия - в 3x быстрее large-v3")
                    .font(.caption)
                Text("🎯 Высокое качество транскрипции")
                    .font(.caption)
            }
            
            Divider()
            
            // Статус и кнопка
            HStack {
                VStack(alignment: .leading) {
                    Text("Статус:")
                        .font(.subheadline)
                    modelStatusView
                }
                
                Spacer()
                
                downloadButton
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var modelStatusView: some View {
        switch appState.modelState {
        case .notLoaded:
            Label("Не загружена", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        case .downloading:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Скачивание \(appState.downloadProgressText)")
                    .foregroundStyle(.blue)
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Загрузка в память...")
                    .foregroundStyle(.blue)
            }
        case .loaded:
            Label("Готова к работе", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
    
    @ViewBuilder
    private var downloadButton: some View {
        switch appState.modelState {
        case .notLoaded, .error:
            Button("Скачать модель") {
                Task {
                    await appState.downloadModel()
                }
            }
            .buttonStyle(.borderedProminent)
            
        case .downloading:
            Button("Отменить") {
                appState.cancelModelDownload()
            }
            .buttonStyle(.bordered)
            
        case .loading, .loaded:
            EmptyView()
        }
    }
}
