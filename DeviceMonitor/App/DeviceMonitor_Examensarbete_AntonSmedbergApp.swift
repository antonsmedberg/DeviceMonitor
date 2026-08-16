//
//  DeviceMonitorApp.swift
//  DeviceMonitor-Examensarbete-AntonSmedberg
//
//  Created by Anton Smedberg on 2025-12-28.
//

import SwiftUI
import SwiftData

enum AppModelFactory {
    static let schema = Schema([Device.self, StatusEvent.self])

    static var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @MainActor
    static let previewContainerResult: Result<ModelContainer, Error> = Result {
        let container = try makeInMemoryModelContainer()
        try seedPreviewDevicesIfNeeded(in: container)
        return container
    }

    @MainActor
    static func makePersistentModelContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    static func makeInMemoryModelContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    static func seedPreviewDevicesIfNeeded(in container: ModelContainer) throws {
        let storage = LocalStorageService(modelContext: container.mainContext)

        if try storage.fetchDevices().isEmpty {
            try storage.apply(devices: MockDeviceMonitor.sampleDevices())
        }
    }
}

@main
struct DeviceMonitorApp: App {
    let modelContainer: ModelContainer?
    let deviceService: any DeviceServiceProtocol
    let startupError: String?

    @MainActor
    init() {
        self.deviceService = MockDeviceMonitor()
        let containerResult: Result<ModelContainer, Error>

        if AppModelFactory.isRunningForPreviews {
            containerResult = AppModelFactory.previewContainerResult
        } else {
            containerResult = Result {
                try AppModelFactory.makePersistentModelContainer()
            }
        }

        switch containerResult {
            case .success(let container):
                self.modelContainer = container
                self.startupError = nil

            case .failure(let error):
                self.modelContainer = nil
                self.startupError = "Unable to initialize local storage. \(error.localizedDescription)"
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let modelContainer {
                    ContentView(
                        modelContext: modelContainer.mainContext,
                        deviceService: deviceService
                    )
                    .modelContainer(modelContainer)
                } else {
                    AppStartupFailureView(
                        message: startupError ?? "Unable to start the app."
                    )
                }
            }
            .tint(AppTheme.accent)
            .preferredColorScheme(.dark)
        }
    }
}

private struct AppStartupFailureView: View {
    let message: String

    var body: some View {
        ZStack {
            AppScreenBackground()

            VStack(alignment: .leading, spacing: 16) {
                Label("Startup Problem", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)

                Text("Try relaunching the app or clearing derived data if previews were running during a schema change.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(20)
            .appCardStyle(
                cornerRadius: AppTheme.Layout.cardCornerRadius,
                fill: AppTheme.cardFill,
                stroke: AppTheme.strongStroke,
                shadowRadius: 18,
                shadowY: 12
            )
            .padding(20)
        }
    }
}
