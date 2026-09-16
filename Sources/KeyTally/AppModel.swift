import AppKit
import CoreGraphics
import Foundation
import IOKit.hid
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var keyboards: [String: KeyboardRecord] = [:]
    private(set) var counts: [String: [String: [String: UInt64]]] = [:]
    private(set) var connectedKeyboardIDs: Set<String> = []
    private(set) var usableKeyboardIDs: Set<String> = []
    private(set) var permissionState: InputPermissionState = .unknown
    private(set) var captureMessage: String?
    private(set) var storageError: String?

    var selectedDate = LocalDay.string()
    var selectedKeyboardID: String?
    var isPaused = false
    var isAllTime = false

    @ObservationIgnored private let store: JSONStore
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var captureStarted = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var capture: CoreHIDCapture!
    @ObservationIgnored private var lastCaptureRetry = Date.distantPast

    init(store: JSONStore = JSONStore()) {
        self.store = store
        self.capture = CoreHIDCapture { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
    }

    var today: String { LocalDay.string() }

    var availableDates: [String] {
        Array(Set(counts.keys).union([today])).sorted(by: >)
    }

    var sortedKeyboards: [KeyboardRecord] {
        keyboards.values.sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return $0.isBuiltIn }
            if $0.isMouseDevice != $1.isMouseDevice {
                return !$0.isMouseDevice
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var isSelectedDeviceMouse: Bool {
        guard let id = selectedKeyboardID else { return false }
        return keyboards[id]?.isMouseDevice == true
    }

    var hasMouseActivity: Bool {
        selectedCounts.keys.contains { keyStr in
            guard let key = KeyID(storageKey: keyStr) else { return false }
            return KeyCatalog.isMouseKey(key)
        }
    }

    var selectedMouseCounts: [String: UInt64] {
        selectedCounts.filter { keyStr, _ in
            guard let key = KeyID(storageKey: keyStr) else { return false }
            return KeyCatalog.isMouseKey(key)
        }
    }

    var selectedKeyboardCounts: [String: UInt64] {
        selectedCounts.filter { keyStr, _ in
            guard let key = KeyID(storageKey: keyStr) else { return false }
            return !KeyCatalog.isMouseKey(key)
        }
    }

    var selectedCounts: [String: UInt64] {
        if isAllTime {
            return lifetimeCounts(keyboardID: selectedKeyboardID)
        }
        return countsFor(date: selectedDate, keyboardID: selectedKeyboardID)
    }

    var selectedTotals: InputKindTotals {
        InputKindTotals(counts: selectedCounts)
    }

    var selectedTotal: UInt64 {
        selectedTotals.headline
    }

    var selectedLifetimeTotal: UInt64 {
        selectedLifetimeTotals.headline
    }

    var selectedLifetimeTotals: InputKindTotals {
        lifetimeTotals(keyboardID: selectedKeyboardID)
    }

    var selectedDailyHistory: [DailyTotal] {
        counts.keys.sorted(by: >).map { date in
            DailyTotal(date: date, total: totalFor(date: date, keyboardID: selectedKeyboardID))
        }
    }

    var todayTotals: InputKindTotals {
        InputKindTotals(counts: countsFor(date: today, keyboardID: selectedKeyboardID))
    }

    var lifetimeSplit: InputKindTotals {
        lifetimeTotals(keyboardID: selectedKeyboardID)
    }

    /// All-devices headline total (keyboard presses + mouse clicks, no wheel scroll).
    var todayTotal: UInt64 {
        InputKindTotals(counts: countsFor(date: today, keyboardID: nil)).headline
    }

    var lifetimeTotal: UInt64 {
        lifetimeTotals(keyboardID: nil).headline
    }

    var hasInputAccess: Bool {
        !usableKeyboardIDs.isEmpty
    }

    var isRecording: Bool {
        hasInputAccess && !isPaused && storageError == nil && captureStarted
    }

    var statusText: String {
        if let storageError { return storageError }
        if !hasInputAccess {
            if let captureMessage { return captureMessage }
            // Permission APIs can be stale after an ad-hoc rebuild. Prefer
            // explaining the re-grant path over a generic waiting message.
            if permissionState == .granted {
                return "Input Monitoring is on, but this build still cannot open keyboards. Toggle KeyTally off/on in Settings, then Recheck."
            }
            return "Input Monitoring permission required"
        }
        if isPaused { return "Paused" }
        if captureStarted { return "Recording physical key presses" }
        return "Starting CoreHID…"
    }

    var statusSymbol: String {
        if storageError != nil { return "exclamationmark.triangle.fill" }
        if !hasInputAccess { return "lock.trianglebadge.exclamationmark.fill" }
        if isPaused { return "pause.circle.fill" }
        return "keyboard.fill"
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        switch await store.load() {
        case .loaded(let state):
            apply(state)
        case .missing:
            break
        case .unreadable(let message):
            storageError = message
            isPaused = true
        }

        // Always start CoreHID. A stale IOHIDCheckAccess/CGPreflight result must
        // not block capture: usable element access is the source of truth.
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshPermission()
        ensureCaptureStarted()
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let previousPermission = self.permissionState
                self.refreshPermission()
                // Immediate rebuild when permission flips either direction.
                let permissionChanged = previousPermission != self.permissionState
                self.retryCaptureIfNeeded(force: permissionChanged)
                // Soft retry while Input Monitoring is on but clients still
                // have zero usable elements (stale ad-hoc TCC, BLE lag).
                if !self.hasInputAccess && self.permissionState == .granted {
                    self.retryCaptureIfNeeded(force: false)
                }
            }
        }
    }

    func togglePause() {
        isPaused.toggle()
        let paused = isPaused
        Task {
            await capture.setPaused(paused)
            if paused {
                await flushNow()
            }
        }
    }

    func requestInputMonitoring() {
        // Register this exact build with TCC, then rebuild clients.
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        _ = CGRequestListenEventAccess()
        refreshPermission()
        retryCaptureIfNeeded(force: true)
    }

    func openInputMonitoringSettings() {
        // Register the current app build with TCC before opening the list. This is
        // important for local ad-hoc builds, which can disappear after a rebuild.
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshPermission()
        retryCaptureIfNeeded(force: true)
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func recheckInputMonitoring() {
        refreshPermission()
        retryCaptureIfNeeded(force: true)
    }

    func renameKeyboard(id: String, to name: String) {
        guard var keyboard = keyboards[id] else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        keyboard.customName = trimmed.isEmpty ? nil : trimmed
        keyboards[id] = keyboard
        scheduleSave()
    }

    func resetCounts() async {
        counts.removeAll()
        selectedDate = today
        isAllTime = false
        storageError = nil
        do {
            try await store.save(snapshot())
            isPaused = false
            await capture.setPaused(false)
            refreshPermission()
            ensureCaptureStarted()
            retryCaptureIfNeeded(force: true)
        } catch {
            storageError = "Could not reset storage: \(error.localizedDescription)"
            isPaused = true
        }
    }

    func flushNow() async {
        saveTask?.cancel()
        saveTask = nil
        guard storageError == nil else { return }
        do {
            try await store.save(snapshot())
        } catch {
            storageError = "Could not save counts: \(error.localizedDescription)"
            isPaused = true
            await capture.setPaused(true)
        }
    }

    func shutdown() async {
        permissionTask?.cancel()
        permissionTask = nil
        captureStarted = false
        await capture.stop()
        await flushNow()
    }

    func csvString() -> String {
        var rows = ["date,keyboard_name,keyboard_id,usage_page,usage_id,key_label,count"]
        for date in counts.keys.sorted() {
            guard let devices = counts[date] else { continue }
            for deviceID in devices.keys.sorted() {
                let name = keyboards[deviceID]?.displayName ?? "Unknown Keyboard"
                guard let keyCounts = devices[deviceID] else { continue }
                for storageKey in keyCounts.keys.sorted(by: keyStorageOrder) {
                    guard let key = KeyID(storageKey: storageKey),
                          let count = keyCounts[storageKey] else { continue }
                    rows.append([
                        csvCell(date),
                        csvCell(name),
                        csvCell(deviceID),
                        String(key.usagePage),
                        String(key.usageID),
                        csvCell(KeyCatalog.label(for: key)),
                        String(count)
                    ].joined(separator: ","))
                }
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    func countsFor(date: String, keyboardID: String?) -> [String: UInt64] {
        guard let devices = counts[date] else { return [:] }
        if let keyboardID {
            return devices[keyboardID] ?? [:]
        }

        var combined: [String: UInt64] = [:]
        for keyCounts in devices.values {
            for (key, count) in keyCounts {
                combined[key, default: 0] += count
            }
        }
        return combined
    }

    func totalFor(date: String, keyboardID: String?) -> UInt64 {
        InputKindTotals(counts: countsFor(date: date, keyboardID: keyboardID)).headline
    }

    func lifetimeTotal(keyboardID: String?) -> UInt64 {
        lifetimeTotals(keyboardID: keyboardID).headline
    }

    func lifetimeTotals(keyboardID: String?) -> InputKindTotals {
        InputKindTotals(counts: lifetimeCounts(keyboardID: keyboardID))
    }

    func lifetimeCounts(keyboardID: String?) -> [String: UInt64] {
        var combined: [String: UInt64] = [:]
        for devices in counts.values {
            let keyCounts: [String: UInt64]
            if let keyboardID {
                keyCounts = devices[keyboardID] ?? [:]
            } else {
                keyCounts = devices.values.reduce(into: [:]) { result, deviceKeys in
                    for (key, count) in deviceKeys {
                        result[key, default: 0] += count
                    }
                }
            }
            for (key, count) in keyCounts {
                combined[key, default: 0] += count
            }
        }
        return combined
    }

    func registerForTesting(_ descriptor: KeyboardDescriptor) {
        register(descriptor)
    }

    func recordForTesting(stableID: String, key: KeyID, date: String) {
        record(stableID: stableID, key: key, date: date)
    }

    func handleForTesting(_ event: CaptureEvent) {
        handle(event)
    }

    private func handle(_ event: CaptureEvent) {
        switch event {
        case .keyboardConnected(let descriptor):
            register(descriptor)
            connectedKeyboardIDs.insert(descriptor.stableID)
            if descriptor.elementCount > 0 {
                usableKeyboardIDs.insert(descriptor.stableID)
                captureMessage = nil
            }
        case .keyboardDisconnected(let stableID):
            connectedKeyboardIDs.remove(stableID)
            usableKeyboardIDs.remove(stableID)
        case .keyPressed(let stableID, let key):
            guard !isPaused, storageError == nil else { return }
            record(stableID: stableID, key: key, date: today)
        case .problem(let message):
            if usableKeyboardIDs.isEmpty {
                captureMessage = message
            }
        }
    }

    private func register(_ descriptor: KeyboardDescriptor) {
        var changed = false
        if var existing = keyboards[descriptor.stableID] {
            if existing.reportedName != descriptor.reportedName || existing.isMouse != descriptor.isMouse {
                existing.reportedName = descriptor.reportedName
                existing.isMouse = descriptor.isMouse
                keyboards[descriptor.stableID] = existing
                changed = true
            }
        } else {
            keyboards[descriptor.stableID] = KeyboardRecord(
                id: descriptor.stableID,
                reportedName: descriptor.reportedName,
                customName: nil,
                isBuiltIn: descriptor.isBuiltIn,
                isMouse: descriptor.isMouse
            )
            changed = true
        }
        if changed {
            scheduleSave()
        }
    }

    private func record(stableID: String, key: KeyID, date: String) {
        counts[date, default: [:]][stableID, default: [:]][key.storageKey, default: 0] += 1
        if !isAllTime {
            selectedDate = date
        }
        scheduleSave()
    }

    private func refreshPermission() {
        // Never let a stale negative result disable capture. If CoreHID later
        // yields usable elements, hasInputAccess becomes the UI authority.
        let hidAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let cgGranted = CGPreflightListenEventAccess()
        let newState: InputPermissionState
        if hidAccess == kIOHIDAccessTypeGranted || cgGranted {
            newState = .granted
        } else if hasInputAccess {
            // Elements already open for this process — treat as granted.
            newState = .granted
        } else if hidAccess == kIOHIDAccessTypeDenied && !cgGranted {
            newState = .denied
        } else {
            newState = .unknown
        }

        permissionState = newState
    }

    private func ensureCaptureStarted() {
        guard !captureStarted, storageError == nil else { return }
        captureStarted = true
        lastCaptureRetry = Date()
        Task {
            await capture.setPaused(isPaused)
            await capture.start()
        }
    }

    private func retryCaptureIfNeeded(force: Bool) {
        guard storageError == nil else { return }
        let now = Date()
        guard force || (!hasInputAccess && now.timeIntervalSince(lastCaptureRetry) >= 5) else {
            return
        }

        lastCaptureRetry = now
        captureStarted = true
        connectedKeyboardIDs.removeAll()
        usableKeyboardIDs.removeAll()
        captureMessage = nil
        Task {
            await capture.setPaused(isPaused)
            await capture.restart()
        }
    }

    private func scheduleSave() {
        guard storageError == nil, saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            await self.flushNow()
        }
    }

    private func snapshot() -> StoredState {
        let keyboardRecords = keyboards.values.sorted { $0.id < $1.id }
        let dayRecords = counts.keys.sorted().compactMap { date -> DayRecord? in
            guard let devices = counts[date] else { return nil }
            let deviceRecords = devices.keys.sorted().compactMap { deviceID -> DeviceCounts? in
                guard let keys = devices[deviceID] else { return nil }
                return DeviceCounts(deviceID: deviceID, keys: keys)
            }
            return DayRecord(date: date, devices: deviceRecords)
        }
        return StoredState(version: 1, keyboards: keyboardRecords, days: dayRecords)
    }

    private func apply(_ state: StoredState) {
        keyboards = Dictionary(uniqueKeysWithValues: state.keyboards.map { ($0.id, $0) })
        counts = Dictionary(uniqueKeysWithValues: state.days.map { day in
            let devices = Dictionary(uniqueKeysWithValues: day.devices.map { ($0.deviceID, $0.keys) })
            return (day.date, devices)
        })
        selectedDate = availableDates.first ?? today
        isAllTime = false
    }

    private func csvCell(_ value: String) -> String {
        var safeValue = value
        if let first = safeValue.first, "=+-@".contains(first) {
            safeValue = "'" + safeValue
        }
        return "\"\(safeValue.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func keyStorageOrder(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = KeyID(storageKey: lhs), let right = KeyID(storageKey: rhs) else {
            return lhs < rhs
        }
        return left < right
    }
}
