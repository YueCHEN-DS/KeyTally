import XCTest
@testable import KeyTally

final class PressStateTrackerTests: XCTestCase {
    private let aKey = KeyID(usagePage: 0x07, usageID: 0x04)
    private let bKey = KeyID(usagePage: 0x07, usageID: 0x05)

    func testCountsOnlyZeroToOneTransitions() {
        var tracker = PressStateTracker()

        XCTAssertTrue(tracker.process(deviceID: 1, key: aKey, isPressed: true))
        XCTAssertFalse(tracker.process(deviceID: 1, key: aKey, isPressed: true))
        XCTAssertFalse(tracker.process(deviceID: 1, key: aKey, isPressed: false))
        XCTAssertTrue(tracker.process(deviceID: 1, key: aKey, isPressed: true))
    }

    func testSameKeyIsIndependentAcrossKeyboards() {
        var tracker = PressStateTracker()

        XCTAssertTrue(tracker.process(deviceID: 1, key: aKey, isPressed: true))
        XCTAssertTrue(tracker.process(deviceID: 2, key: aKey, isPressed: true))
        XCTAssertFalse(tracker.process(deviceID: 1, key: aKey, isPressed: true))
        XCTAssertFalse(tracker.process(deviceID: 2, key: aKey, isPressed: true))
    }

    func testSimultaneousKeysAreIndependent() {
        var tracker = PressStateTracker()

        XCTAssertTrue(tracker.process(deviceID: 1, key: aKey, isPressed: true))
        XCTAssertTrue(tracker.process(deviceID: 1, key: bKey, isPressed: true))
        XCTAssertFalse(tracker.process(deviceID: 1, key: aKey, isPressed: false))
        XCTAssertFalse(tracker.process(deviceID: 1, key: bKey, isPressed: false))
    }

    func testSeededHeldKeyDoesNotCountUntilReleased() {
        var tracker = PressStateTracker()
        tracker.seed(deviceID: 1, key: aKey, isPressed: true)

        XCTAssertFalse(tracker.process(deviceID: 1, key: aKey, isPressed: true))
        XCTAssertFalse(tracker.process(deviceID: 1, key: aKey, isPressed: false))
        XCTAssertTrue(tracker.process(deviceID: 1, key: aKey, isPressed: true))
    }

    func testRemovingOneDeviceDoesNotChangeAnother() {
        var tracker = PressStateTracker()
        _ = tracker.process(deviceID: 1, key: aKey, isPressed: true)
        _ = tracker.process(deviceID: 2, key: aKey, isPressed: true)

        tracker.removeDevice(1)

        XCTAssertTrue(tracker.process(deviceID: 1, key: aKey, isPressed: true))
        XCTAssertFalse(tracker.process(deviceID: 2, key: aKey, isPressed: true))
    }

    func testPausedPressUpdatesStateWithoutCountingOnResume() {
        var tracker = PressStateTracker()

        XCTAssertFalse(tracker.process(
            deviceID: 1,
            key: aKey,
            isPressed: true,
            countingEnabled: false
        ))
        XCTAssertFalse(tracker.process(
            deviceID: 1,
            key: aKey,
            isPressed: true,
            countingEnabled: true
        ))
        XCTAssertFalse(tracker.process(deviceID: 1, key: aKey, isPressed: false))
        XCTAssertTrue(tracker.process(deviceID: 1, key: aKey, isPressed: true))
    }

    func testMouseButtonsTransitions() {
        var tracker = PressStateTracker()
        let leftButton = KeyID(usagePage: KeyCatalog.buttonPage, usageID: KeyCatalog.mouseLeftButton)
        let rightButton = KeyID(usagePage: KeyCatalog.buttonPage, usageID: KeyCatalog.mouseRightButton)
        let wheelButton = KeyID(usagePage: KeyCatalog.buttonPage, usageID: KeyCatalog.mouseMiddleButton)

        // Left click 0 -> 1
        XCTAssertTrue(tracker.process(deviceID: 10, key: leftButton, isPressed: true))
        // Held left click does not count again
        XCTAssertFalse(tracker.process(deviceID: 10, key: leftButton, isPressed: true))
        // Simultaneous right click counts
        XCTAssertTrue(tracker.process(deviceID: 10, key: rightButton, isPressed: true))
        // Wheel click counts
        XCTAssertTrue(tracker.process(deviceID: 10, key: wheelButton, isPressed: true))

        // Release buttons
        XCTAssertFalse(tracker.process(deviceID: 10, key: leftButton, isPressed: false))
        XCTAssertFalse(tracker.process(deviceID: 10, key: rightButton, isPressed: false))
        XCTAssertFalse(tracker.process(deviceID: 10, key: wheelButton, isPressed: false))

        // New left click counts again
        XCTAssertTrue(tracker.process(deviceID: 10, key: leftButton, isPressed: true))
    }
}
