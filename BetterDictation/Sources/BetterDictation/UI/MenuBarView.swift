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
            
            // Выбор модели (всегда видим)
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
    
    // MARK: - Секция модели
    
    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            modelRow()
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
    
    // MARK: - Строка модели
    
    private func modelRow() -> some View {
        modelSelector()
    }
    
    @ViewBuilder
    private func modelSelector() -> some View {
        HStack(spacing: 8) {
            // Выбор модели (слева)
            Picker("", selection: Binding(
                get: { appState.modelManager.selectedModel },
                set: { newModel in
                    // Отменяем текущую загрузку, если есть
                    if appState.modelState == .downloading {
                        appState.cancelModelDownload()
                    }
                    
                    appState.modelManager.selectedModel = newModel
                    
                    // Автозагрузка, если уже скачана
                    if appState.modelManager.downloadedModels.contains(newModel) {
                        Task {
                            await appState.loadSelectedModel()
                        }
                    }
                }
            )) {
                // Пустой вариант всегда доступен
                Text("—").tag("")
                
                ForEach(ModelInfo.all) { model in
                    if appState.modelManager.downloadedModels.contains(model.name) {
                        Text("\(model.displayName) ✓")
                            .tag(model.name)
                    } else {
                        Text("\(model.displayName) (\(model.size))")
                            .tag(model.name)
                    }
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(appState.modelState == .loading)
            
            // Прогресс или действие (справа от выбора)
            if appState.modelState == .downloading {
                ProgressView()
                    .controlSize(.small)
                Text(appState.downloadProgressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if appState.modelState == .loading {
                ProgressView()
                    .controlSize(.small)
            } else if !appState.modelManager.selectedModel.isEmpty && appState.modelManager.downloadedModels.contains(appState.modelManager.selectedModel) {
                // Скачана: кнопка удаления
                Button {
                    Task {
                        await appState.deleteModel(appState.modelManager.selectedModel)
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Удалить модель")
            } else if !appState.modelManager.selectedModel.isEmpty {
                // Не скачана: кнопка загрузки
                Button {
                    Task {
                        await appState.downloadModel()
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Скачать модель")
            }
            
            Spacer()
        }
    }
}
