# DeviceMonitor

DeviceMonitor is an iOS demo app for monitoring network devices (for example cameras and sensors) with a clear online/offline overview, status history, filtering, and search.

This project is built as an exam/demo project with a modern iOS 26+ SwiftUI architecture and strict Swift 6 concurrency.

<p align="center">
  <img src="Documentation/Screenshots/device-monitor-dashboard.jpg" alt="DeviceMonitor dashboard showing online and offline network devices" width="360">
</p>

## Tech Stack

- Swift 6
- SwiftUI
- SwiftData
- iOS 26+
- Swift 6 strict concurrency (`async/await`, `actor`, `@MainActor`)
- Lean MVVM with a small service/storage boundary

## Current Features

- Dark-first device dashboard with a refined blue-black gradient theme
- Sticky status filter with native iOS 26 segmented picker behavior
- Network Overview summary card with live refresh control
- Integrated top search panel for device name and IPv4 filtering
- Full-screen add, overview, and detail modals with shared modal components
- Device detail view with metadata and status history
- Swipe-to-remove list rows during the current app session
- Toolbar action menu for add, search focus, and manual refresh
- Mock monitor service with stable device identities and simulated status changes

## Architecture

```text
DeviceMonitor-Examensarbete-AntonSmedberg/
  App/
    DeviceMonitor_Examensarbete_AntonSmedbergApp.swift
  Models/
    Device.swift
  Services/
    ServiceContracts.swift
    MockDeviceMonitor.swift
    LocalStorageService.swift
  ViewModels/
    DevicesViewModel.swift
  Views/
    ContentView.swift
    AppTheme.swift
    Devices/
      DevicesView.swift
      DevicesToolbarViews.swift
      DevicesFilterViews.swift
      DevicesContentViews.swift
      DeviceRowViews.swift
      AddAndSearchDeviceViews.swift
      DeviceModalSharedViews.swift
      DeviceOverviewAndDetailViews.swift
  Utilities/
    IPv4Validator.swift
```

## Build and Run

1. Open `DeviceMonitor-Examensarbete-AntonSmedberg.xcodeproj` in Xcode.
2. Select the `DeviceMonitor-Examensarbete-AntonSmedberg` scheme.
3. Run on an iPhone simulator.

### CLI build example

```bash
xcodebuild -project DeviceMonitor-Examensarbete-AntonSmedberg.xcodeproj \
  -scheme DeviceMonitor-Examensarbete-AntonSmedberg \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build-for-testing
```

## Tests

- Six unit tests cover storage reconciliation, status transitions, manually added devices, and view-model filtering.
- One UI smoke test covers launch and the main screen title.

```bash
xcodebuild test \
  -project DeviceMonitor-Examensarbete-AntonSmedberg.xcodeproj \
  -scheme DeviceMonitor-Examensarbete-AntonSmedberg \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:DeviceMonitor-Examensarbete-AntonSmedbergTests
```

The six unit tests were verified on an iPhone 17 Pro simulator with Xcode 26.6 on August 10, 2026.

## Limitations

- Device data comes from a deterministic mock service; the app does not discover or probe real network devices.
- This is a portfolio and exam project, not a production network-monitoring or security tool.
- The current deployment target is iOS 26.2, so it does not demonstrate backward compatibility with older iOS versions.
- Status history is local SwiftData state and has no cloud sync or multi-device reconciliation.

## Notes

- Previews use an in-memory SwiftData container so they stay isolated from the running app store.
- Liquid Glass is used on controls where it fits best, while scrolling content cards remain standard surfaces for readability and performance.
- The devices feature stays in one focused folder so routing, shared list UI, and modal flows remain easy to follow.
