import Foundation
import XCTest
@testable import KeyTally

final class StorageAndModelTests: XCTestCase {
    func testJSONRoundTrip() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = JSONStore(fileURL: fileURL)
        let state = StoredState(
            version: 1,
            keyboards: [
                KeyboardRecord(id: "kbd-a", reportedName: "Keyboard A", customName: nil, isBuiltIn: true)
            ],
            days: [
                DayRecord(date: "2026-09-12", devices: [
                    DeviceCounts(deviceID: "kbd-a", keys: ["7:4": 2])
                ])
            ]
        )

        try await store.save(state)
        let result = await store.load()

        guard case .loaded(let loaded) = result else {
            return XCTFail("Expected stored state to load")
        }
        XCTAssertEqual(loaded, state)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
    }

    func testUnreadableJSONIsPreserved() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("not-json".utf8)
        try original.write(to: fileURL)
        let store = JSONStore(fileURL: fileURL)

        guard case .unreadable = await store.load() else {
            return XCTFail("Expected unreadable result")
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    @MainActor
    func testCombinedTotalsAreDerivedFromDevices() {
        let model = AppModel(store: JSONStore(fileURL: temporaryFileURL()))
        let keyA = KeyID(usagePage: 7, usageID: 4)
        let keyB = KeyID(usagePage: 7, usageID: 5)
        let day = "2026-09-12"

        model.recordForTesting(stableID: "keyboard-a", key: keyA, date: day)
        model.recordForTesting(stableID: "keyboard-a", key: keyA, date: day)
        model.recordForTesting(stableID: "keyboard-b", key: keyA, date: day)
        model.recordForTesting(stableID: "keyboard-b", key: keyB, date: day)

        XCTAssertEqual(model.countsFor(date: day, keyboardID: "keyboard-a")["7:4"], 2)
        XCTAssertEqual(model.countsFor(date: day, keyboardID: "keyboard-b")["7:4"], 1)
        XCTAssertEqual(model.countsFor(date: day, keyboardID: nil)["7:4"], 3)
        XCTAssertEqual(model.countsFor(date: day, keyboardID: nil).values.reduce(0, +), 4)
    }

    @MainActor
    func testLifetimeAndDailyTotalsAreDerivedFromDailyDeviceCounts() {
        let model = AppModel(store: JSONStore(fileURL: temporaryFileURL()))
        let key = KeyID(usagePage: 7, usageID: 4)

        model.recordForTesting(stableID: "keyboard-a", key: key, date: "2026-09-11")
        model.recordForTesting(stableID: "keyboard-a", key: key, date: "2026-09-12")
        model.recordForTesting(stableID: "keyboard-b", key: key, date: "2026-09-12")

        XCTAssertEqual(model.lifetimeTotal, 3)
        XCTAssertEqual(model.lifetimeTotal(keyboardID: "keyboard-a"), 2)
        XCTAssertEqual(model.totalFor(date: "2026-09-12", keyboardID: nil), 2)
        XCTAssertEqual(
            model.selectedDailyHistory.first { $0.date == "2026-09-12" },
            DailyTotal(date: "2026-09-12", total: 2)
        )
    }

    @MainActor
    func testCoreHIDElementsAreTheEffectiveInputAccessSignal() {
        let model = AppModel(store: JSONStore(fileURL: temporaryFileURL()))

        model.handleForTesting(.keyboardConnected(KeyboardDescriptor(
            runtimeID: 1,
            stableID: "inaccessible",
            reportedName: "No Elements",
            isBuiltIn: true,
            elementCount: 0
        )))
        XCTAssertFalse(model.hasInputAccess)

        model.handleForTesting(.keyboardConnected(KeyboardDescriptor(
            runtimeID: 2,
            stableID: "accessible",
            reportedName: "Working Keyboard",
            isBuiltIn: false,
            elementCount: 42
        )))
        XCTAssertTrue(model.hasInputAccess)

        model.handleForTesting(.keyboardDisconnected(stableID: "accessible"))
        XCTAssertFalse(model.hasInputAccess)
    }

    @MainActor
    func testCSVContainsAggregateRowsOnly() {
        let model = AppModel(store: JSONStore(fileURL: temporaryFileURL()))
        model.registerForTesting(KeyboardDescriptor(
            runtimeID: 1,
            stableID: "keyboard-a",
            reportedName: "Keyboard A",
            isBuiltIn: true,
            elementCount: 1
        ))
        model.recordForTesting(
            stableID: "keyboard-a",
            key: KeyID(usagePage: 7, usageID: 4),
            date: "2026-09-12"
        )

        let csv = model.csvString()
        XCTAssertTrue(csv.contains("date,keyboard_name,keyboard_id,usage_page,usage_id,key_label,count"))
        XCTAssertTrue(csv.contains("\"Keyboard A\",\"keyboard-a\",7,4,\"A\",1"))
        XCTAssertFalse(csv.lowercased().contains("timestamp"))
        XCTAssertFalse(csv.lowercased().contains("application"))
    }

    @MainActor
    func testDaysRemainSeparateAndRenameDoesNotChangeIdentity() {
        let model = AppModel(store: JSONStore(fileURL: temporaryFileURL()))
        let descriptor = KeyboardDescriptor(
            runtimeID: 1,
            stableID: "keyboard-a",
            reportedName: "Reported Keyboard",
            isBuiltIn: false,
            elementCount: 1
        )
        let key = KeyID(usagePage: 7, usageID: 4)
        model.registerForTesting(descriptor)
        model.recordForTesting(stableID: descriptor.stableID, key: key, date: "2026-09-11")
        model.recordForTesting(stableID: descriptor.stableID, key: key, date: "2026-09-12")
        model.renameKeyboard(id: descriptor.stableID, to: "Desk Keyboard")

        XCTAssertEqual(model.countsFor(date: "2026-09-11", keyboardID: nil)["7:4"], 1)
        XCTAssertEqual(model.countsFor(date: "2026-09-12", keyboardID: nil)["7:4"], 1)
        XCTAssertEqual(model.keyboards[descriptor.stableID]?.displayName, "Desk Keyboard")
        XCTAssertEqual(model.keyboards[descriptor.stableID]?.id, descriptor.stableID)
    }

    @MainActor
    func testResetClearsCountsButPreservesKeyboardName() async {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let model = AppModel(store: JSONStore(fileURL: fileURL))
        let descriptor = KeyboardDescriptor(
            runtimeID: 1,
            stableID: "keyboard-a",
            reportedName: "Keyboard A",
            isBuiltIn: true,
            elementCount: 1
        )
        model.registerForTesting(descriptor)
        model.renameKeyboard(id: descriptor.stableID, to: "Laptop")
        model.recordForTesting(
            stableID: descriptor.stableID,
            key: KeyID(usagePage: 7, usageID: 4),
            date: "2026-09-12"
        )

        await model.resetCounts()

        XCTAssertTrue(model.counts.isEmpty)
        XCTAssertEqual(model.keyboards[descriptor.stableID]?.displayName, "Laptop")
    }

    func testDeviceIdentityUsesReportedModelAndStableMetadata() {
        let first = DeviceIdentity.make(
            runtimeID: 1,
            isBuiltIn: false,
            manufacturer: "Example",
            product: "Keyboard",
            modelNumber: "K1",
            vendorID: 100,
            productID: 200,
            transport: "USB",
            uniqueID: "persistent-id",
            serialNumber: nil,
            locationID: 1
        )
        let reconnected = DeviceIdentity.make(
            runtimeID: 99,
            isBuiltIn: false,
            manufacturer: "Example",
            product: "Keyboard",
            modelNumber: "K1",
            vendorID: 100,
            productID: 200,
            transport: "USB",
            uniqueID: "persistent-id",
            serialNumber: nil,
            locationID: 9
        )

        XCTAssertEqual(first.stableID, reconnected.stableID)
        XCTAssertEqual(first.reportedName, "Example K1")
        XCTAssertFalse(first.stableID.contains("persistent-id"))
    }

    @MainActor
    func testLifetimeCountsAggregatesAcrossDaysAndKeyboards() {
        let model = AppModel(store: JSONStore(fileURL: temporaryFileURL()))
        let keyA = KeyID(usagePage: 7, usageID: 4)
        let keyB = KeyID(usagePage: 7, usageID: 5)

        model.recordForTesting(stableID: "keyboard-a", key: keyA, date: "2026-09-10")
        model.recordForTesting(stableID: "keyboard-a", key: keyA, date: "2026-09-11")
        model.recordForTesting(stableID: "keyboard-b", key: keyA, date: "2026-09-11")
        model.recordForTesting(stableID: "keyboard-b", key: keyB, date: "2026-09-12")

        let allCounts = model.lifetimeCounts(keyboardID: nil)
        XCTAssertEqual(allCounts["7:4"], 3)
        XCTAssertEqual(allCounts["7:5"], 1)
        XCTAssertEqual(allCounts.values.reduce(0, +), model.lifetimeTotal)

        let kbdACounts = model.lifetimeCounts(keyboardID: "keyboard-a")
        XCTAssertEqual(kbdACounts["7:4"], 2)
        XCTAssertNil(kbdACounts["7:5"])

        let kbdBCounts = model.lifetimeCounts(keyboardID: "keyboard-b")
        XCTAssertEqual(kbdBCounts["7:4"], 1)
        XCTAssertEqual(kbdBCounts["7:5"], 1)
    }

    @MainActor
    func testTotalAggregatedUsageSelectionMode() {
        let model = AppModel(store: JSONStore(fileURL: temporaryFileURL()))
        let keyA = KeyID(usagePage: 7, usageID: 4)
        let keyB = KeyID(usagePage: 7, usageID: 5)

        model.recordForTesting(stableID: "keyboard-a", key: keyA, date: "2026-09-10")
        model.recordForTesting(stableID: "keyboard-a", key: keyB, date: "2026-09-11")

        // Daily view
        model.selectedDate = "2026-09-10"
        model.isAllTime = false
        XCTAssertEqual(model.selectedTotal, 1)
        XCTAssertEqual(model.selectedCounts["7:4"], 1)
        XCTAssertNil(model.selectedCounts["7:5"])

        // All-Time Total Aggregated view
        model.isAllTime = true
        XCTAssertEqual(model.selectedTotal, 2)
        XCTAssertEqual(model.selectedCounts["7:4"], 1)
        XCTAssertEqual(model.selectedCounts["7:5"], 1)
        XCTAssertEqual(model.selectedTotals.keyboard, 2)
        XCTAssertEqual(model.selectedTotals.mouseClicks, 0)

        // Switching back to day view
        model.isAllTime = false
        XCTAssertEqual(model.selectedTotal, 1)
    }

    @MainActor
    func testRecentDailyHistoryLimitsToThreeDays() {
        let model = AppModel(store: JSONStore(fileURL: temporaryFileURL()))
        let key = KeyID(usagePage: 7, usageID: 4)

        model.recordForTesting(stableID: "kbd", key: key, date: "2026-09-01")
        model.recordForTesting(stableID: "kbd", key: key, date: "2026-09-02")
        model.recordForTesting(stableID: "kbd", key: key, date: "2026-09-03")
        model.recordForTesting(stableID: "kbd", key: key, date: "2026-09-04")
        model.recordForTesting(stableID: "kbd", key: key, date: "2026-09-05")

        XCTAssertEqual(model.selectedDailyHistory.count, 5)
        XCTAssertEqual(Array(model.selectedDailyHistory.prefix(3)).map(\.date), [
            "2026-09-05", "2026-09-04", "2026-09-03"
        ])
    }

    @MainActor
    func testMouseClicksAndWheelRecordingAndSeparation() {
        let model = AppModel(store: JSONStore(fileURL: temporaryFileURL()))
        let mouseDescriptor = KeyboardDescriptor(
            runtimeID: 42,
            stableID: "mouse-logi",
            reportedName: "Logitech Mouse",
            isBuiltIn: false,
            elementCount: 4,
            isMouse: true
        )
        let kbdDescriptor = KeyboardDescriptor(
            runtimeID: 1,
            stableID: "kbd-apple",
            reportedName: "Apple Keyboard",
            isBuiltIn: true,
            elementCount: 78,
            isMouse: false
        )

        model.registerForTesting(mouseDescriptor)
        model.registerForTesting(kbdDescriptor)

        let leftClick = KeyID(usagePage: KeyCatalog.buttonPage, usageID: KeyCatalog.mouseLeftButton)
        let rightClick = KeyID(usagePage: KeyCatalog.buttonPage, usageID: KeyCatalog.mouseRightButton)
        let wheelClick = KeyID(usagePage: KeyCatalog.buttonPage, usageID: KeyCatalog.mouseMiddleButton)
        let wheelScroll = KeyID(usagePage: KeyCatalog.genericDesktopPage, usageID: KeyCatalog.mouseWheelScroll)
        let spaceKey = KeyID(usagePage: 7, usageID: 44)

        let today = model.today
        model.recordForTesting(stableID: "mouse-logi", key: leftClick, date: today)
        model.recordForTesting(stableID: "mouse-logi", key: leftClick, date: today)
        model.recordForTesting(stableID: "mouse-logi", key: rightClick, date: today)
        model.recordForTesting(stableID: "mouse-logi", key: wheelClick, date: today)
        model.recordForTesting(stableID: "mouse-logi", key: wheelScroll, date: today)
        model.recordForTesting(stableID: "kbd-apple", key: spaceKey, date: today)

        // Verify device records
        XCTAssertEqual(model.keyboards["mouse-logi"]?.isMouseDevice, true)
        XCTAssertEqual(model.keyboards["kbd-apple"]?.isMouseDevice, false)

        // Mouse counts (raw storage still includes wheel scroll)
        let mouseCounts = model.countsFor(date: today, keyboardID: "mouse-logi")
        XCTAssertEqual(mouseCounts["9:1"], 2) // Left
        XCTAssertEqual(mouseCounts["9:2"], 1) // Right
        XCTAssertEqual(mouseCounts["9:3"], 1) // Wheel Click
        XCTAssertEqual(mouseCounts["1:56"], 1) // Wheel Scroll

        // Headline mouse total = clicks only (2+1+1), scroll excluded
        let mouseHeadline = InputKindTotals(counts: mouseCounts)
        XCTAssertEqual(mouseHeadline.mouseClicks, 4)
        XCTAssertEqual(mouseHeadline.wheelScroll, 1)
        XCTAssertEqual(mouseHeadline.headline, 4)
        XCTAssertEqual(model.totalFor(date: today, keyboardID: "mouse-logi"), 4)

        // Keyboard counts
        let kbdCounts = model.countsFor(date: today, keyboardID: "kbd-apple")
        XCTAssertEqual(kbdCounts["7:44"], 1)
        XCTAssertEqual(model.totalFor(date: today, keyboardID: "kbd-apple"), 1)

        // Split today/lifetime for all devices
        let todaySplit = InputKindTotals(counts: model.countsFor(date: today, keyboardID: nil))
        XCTAssertEqual(todaySplit.keyboard, 1)
        XCTAssertEqual(todaySplit.mouseClicks, 4)
        XCTAssertEqual(todaySplit.wheelScroll, 1)
        XCTAssertEqual(todaySplit.headline, 5)
        XCTAssertEqual(model.totalFor(date: today, keyboardID: nil), 5)
        XCTAssertEqual(model.lifetimeTotal, 5)
        XCTAssertEqual(model.lifetimeSplit.keyboard, 1)
        XCTAssertEqual(model.lifetimeSplit.mouseClicks, 4)

        // Labels
        XCTAssertEqual(KeyCatalog.label(for: leftClick), "Left Click")
        XCTAssertEqual(KeyCatalog.label(for: rightClick), "Right Click")
        XCTAssertEqual(KeyCatalog.label(for: wheelClick), "Wheel Click")
        XCTAssertEqual(KeyCatalog.label(for: wheelScroll), "Wheel Scroll")

        // CSV export includes mouse labels
        let csv = model.csvString()
        XCTAssertTrue(csv.contains("Left Click"))
        XCTAssertTrue(csv.contains("Right Click"))
        XCTAssertTrue(csv.contains("Wheel Click"))
        XCTAssertTrue(csv.contains("Wheel Scroll"))
    }

    @MainActor
    func testTodayAndLifetimeSplitKeyboardMouseAndExcludeWheelScroll() {
        let model = AppModel(store: JSONStore(fileURL: temporaryFileURL()))
        let today = model.today
        let left = KeyID(usagePage: KeyCatalog.buttonPage, usageID: KeyCatalog.mouseLeftButton)
        let scroll = KeyID(usagePage: KeyCatalog.genericDesktopPage, usageID: KeyCatalog.mouseWheelScroll)
        let space = KeyID(usagePage: 7, usageID: 44)

        model.recordForTesting(stableID: "kbd", key: space, date: today)
        model.recordForTesting(stableID: "kbd", key: space, date: today)
        model.recordForTesting(stableID: "mouse", key: left, date: today)
        model.recordForTesting(stableID: "mouse", key: scroll, date: today)
        model.recordForTesting(stableID: "mouse", key: scroll, date: "2026-09-01")

        let todaySplit = model.todayTotals
        XCTAssertEqual(todaySplit.keyboard, 2)
        XCTAssertEqual(todaySplit.mouseClicks, 1)
        XCTAssertEqual(todaySplit.wheelScroll, 1)
        XCTAssertEqual(todaySplit.headline, 3)
        XCTAssertEqual(model.todayTotal, 3)

        let lifetime = model.lifetimeSplit
        XCTAssertEqual(lifetime.keyboard, 2)
        XCTAssertEqual(lifetime.mouseClicks, 1)
        XCTAssertEqual(lifetime.wheelScroll, 2)
        XCTAssertEqual(lifetime.headline, 3)
        XCTAssertEqual(model.lifetimeTotal, 3)

        // Mouse panel still sees scroll; headline does not.
        model.selectedDate = today
        model.isAllTime = false
        XCTAssertEqual(model.selectedMouseCounts.values.reduce(0, +), 2)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyTallyTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("counts.json")
    }
}
