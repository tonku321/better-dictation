import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack(spacing: 12) {
            // Разрешения (только если не выданы)
            if !appState.permissionManager.allPermissionsGranted {
                permissionsSection
                Divider()
            }
            
            // Модель Parakeet
            modelSection
            
            Divider()
            
            // Подвал: горячая клавиша слева, выход справа
            HStack {
                Text("Правый ⌥")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Выход") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 340)
    }
    
    // MARK: - Секция разрешений
    
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Разрешения")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Разрешение микрофона
            permissionRow(
                title: "Микрофон",
                status: appState.permissionManager.microphoneStatus,
                action: {
                    Task {
                        await appState.permissionManager.requestMicrophonePermission()
                    }
                },
                openSettings: { appState.permissionManager.openMicrophoneSettings() }
            )
            
            // Разрешение accessibility
            accessibilityPermissionRow()
        }
    }
    
    // MARK: - Секция модели Parakeet
    
    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Заголовок
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.blue)
                Text("Parakeet TDT v3")
                    .font(.headline)
                Spacer()
            }
            
            // Статус и кнопка действия
            HStack {
                modelStatusView
                Spacer()
                modelActionButton
            }
            
            // Краткое описание
            Text("🇷🇺 Русский + 🇬🇧 English • Автоопределение языка")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var modelStatusView: some View {
        switch appState.modelState {
        case .notLoaded:
            Label("Не загружена", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .downloading:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text(appState.downloadProgressText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            }
        case .loading:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Загрузка...")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        case .loaded:
            Label("Готова", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(1)
        }
    }
    
    @ViewBuilder
    private var modelActionButton: some View {
        switch appState.modelState {
        case .notLoaded, .error:
            Button("Скачать") {
                Task {
                    await appState.downloadModel()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
        case .downloading:
            Button("Отмена") {
                appState.cancelModelDownload()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
        case .loading, .loaded:
            EmptyView()
        }
    }
    
    private func permissionRow(
        title: String,
        status: PermissionManager.PermissionStatus,
        action: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(status == .granted ? .green : .orange)
            
            Text(title)
            
            Spacer()
            
            if status != .granted {
                if status == .notDetermined {
                    Button("Разрешить") {
                        action()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Настройки") {
                        openSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
    
    private func accessibilityPermissionRow() -> some View {
        let status = appState.permissionManager.accessibilityStatus
        
        return HStack {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(status == .granted ? .green : .orange)
            
            Text("Универсальный доступ")
            
            Spacer()
            
            if status != .granted {
                Button("Разрешить") {
                    appState.permissionManager.requestAccessibilityPermission()
                    appState.permissionManager.startPollingAccessibilityStatus()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
