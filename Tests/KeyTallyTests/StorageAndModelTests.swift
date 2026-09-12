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

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyTallyTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("counts.json")
    }
}
