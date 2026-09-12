import CoreHID
import Foundation

struct PressStateTracker: Sendable {
    private(set) var pressedByDevice: [UInt64: Set<KeyID>] = [:]

    mutating func process(
        deviceID: UInt64,
        key: KeyID,
        isPressed: Bool,
        countingEnabled: Bool = true
    ) -> Bool {
        var pressed = pressedByDevice[deviceID, default: []]
        let wasPressed = pressed.contains(key)

        if isPressed {
            pressed.insert(key)
        } else {
            pressed.remove(key)
        }

        if pressed.isEmpty {
            pressedByDevice.removeValue(forKey: deviceID)
        } else {
            pressedByDevice[deviceID] = pressed
        }
        return countingEnabled && isPressed && !wasPressed
    }

    mutating func seed(deviceID: UInt64, key: KeyID, isPressed: Bool) {
        _ = process(
            deviceID: deviceID,
            key: key,
            isPressed: isPressed,
            countingEnabled: false
        )
    }

    mutating func removeDevice(_ deviceID: UInt64) {
        pressedByDevice.removeValue(forKey: deviceID)
    }
}

actor CoreHIDCapture {
    typealias EventHandler = @Sendable (CaptureEvent) -> Void

    private let onEvent: EventHandler
    private var manager: HIDDeviceManager?
    private var managerTask: Task<Void, Never>?
    private var deviceTasks: [UInt64: Task<Void, Never>] = [:]
    private var clients: [UInt64: HIDDeviceClient] = [:]
    private var descriptors: [UInt64: KeyboardDescriptor] = [:]
    private var tracker = PressStateTracker()
    private var paused = false

    init(onEvent: @escaping EventHandler) {
        self.onEvent = onEvent
    }

    func start() {
        guard managerTask == nil else { return }

        let manager = HIDDeviceManager()
        self.manager = manager
        managerTask = Task { [weak self] in
            do {
                let criteria = HIDDeviceManager.DeviceMatchingCriteria(
                    primaryUsage: .genericDesktop(.keyboard)
                )
                let notifications = await manager.monitorNotifications(
                    matchingCriteria: [criteria]
                )

                for try await notification in notifications {
                    guard !Task.isCancelled else { break }
                    switch notification {
                    case .deviceMatched(let reference):
                        await self?.attach(reference)
                    case .deviceRemoved(let reference):
                        await self?.detach(runtimeID: reference.deviceID)
                    @unknown default:
                        continue
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self?.onEvent(.problem("CoreHID discovery failed: \(error.localizedDescription)"))
            }
        }
    }

    func stop() {
        managerTask?.cancel()
        managerTask = nil
        manager = nil
        for task in deviceTasks.values {
            task.cancel()
        }
        deviceTasks.removeAll()
        clients.removeAll()
        descriptors.removeAll()
        tracker = PressStateTracker()
    }

    func restart() {
        stop()
        start()
    }

    func setPaused(_ value: Bool) {
        paused = value
    }

    private func attach(_ reference: HIDDeviceClient.DeviceReference) async {
        let runtimeID = reference.deviceID
        guard clients[runtimeID] == nil,
              let client = HIDDeviceClient(deviceReference: reference) else {
            return
        }

        let transport = await client.transport
        if transport == .virtual {
            return
        }

        let allElements = await client.elements
        let keyboardElements = allElements.filter { element in
            guard case .input = element.type,
                  case .keyboardOrKeypad(let usage?) = element.usage else {
                return false
            }
            return KeyCatalog.countedUsageIDs.contains(usage.rawValue)
        }

        let manufacturer = await client.manufacturer
        let product = await client.product
        let modelNumber = await client.modelNumber
        let vendorID = await client.vendorID
        let productID = await client.productID
        let uniqueID = await client.uniqueID
        let serialNumber = await client.serialNumber
        let locationID = await client.locationID
        let isBuiltIn = await client.isBuiltIn
        let transportName = Self.transportName(transport)
        let identity = DeviceIdentity.make(
            runtimeID: runtimeID,
            isBuiltIn: isBuiltIn,
            manufacturer: manufacturer,
            product: product,
            modelNumber: modelNumber,
            vendorID: vendorID,
            productID: productID,
            transport: transportName,
            uniqueID: uniqueID,
            serialNumber: serialNumber,
            locationID: locationID
        )
        let descriptor = KeyboardDescriptor(
            runtimeID: runtimeID,
            stableID: identity.stableID,
            reportedName: identity.reportedName,
            isBuiltIn: isBuiltIn,
            elementCount: keyboardElements.count
        )

        clients[runtimeID] = client
        descriptors[runtimeID] = descriptor
        onEvent(.keyboardConnected(descriptor))

        guard !keyboardElements.isEmpty else {
            onEvent(.problem(
                "\(descriptor.reportedName) has no accessible keyboard elements yet. Enable Input Monitoring for this build."
            ))
            return
        }

        await seedCurrentState(
            client: client,
            runtimeID: runtimeID,
            elements: keyboardElements
        )

        deviceTasks[runtimeID] = Task { [weak self] in
            do {
                let notifications = await client.monitorNotifications(
                    reportIDsToMonitor: [],
                    elementsToMonitor: keyboardElements
                )
                for try await notification in notifications {
                    guard !Task.isCancelled else { break }
                    switch notification {
                    case .elementUpdates(let values):
                        await self?.handle(values, runtimeID: runtimeID, stableID: identity.stableID)
                    case .deviceRemoved:
                        await self?.detach(runtimeID: runtimeID)
                        return
                    default:
                        continue
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self?.onEvent(.problem(
                    "Keyboard monitoring failed for \(descriptor.reportedName): \(error.localizedDescription)"
                ))
            }
        }
    }

    private func seedCurrentState(
        client: HIDDeviceClient,
        runtimeID: UInt64,
        elements: [HIDElement]
    ) async {
        let request = HIDDeviceClient.RequestElementUpdate(elements: elements)
        let results = await client.updateElements([request])
        guard let result = results[request],
              let values = try? result.get() else {
            return
        }
        for value in values {
            guard let key = Self.keyID(for: value.element) else { continue }
            let isPressed = value.integerValue(asTypeTruncatingIfNeeded: UInt64.self) != 0
            tracker.seed(deviceID: runtimeID, key: key, isPressed: isPressed)
        }
    }

    private func handle(
        _ values: [HIDElement.Value],
        runtimeID: UInt64,
        stableID: String
    ) {
        for value in values {
            guard let key = Self.keyID(for: value.element) else { continue }
            let isPressed = value.integerValue(asTypeTruncatingIfNeeded: UInt64.self) != 0
            let isNewPress = tracker.process(
                deviceID: runtimeID,
                key: key,
                isPressed: isPressed,
                countingEnabled: !paused
            )
            if isNewPress {
                onEvent(.keyPressed(stableID: stableID, key: key))
            }
        }
    }

    private func detach(runtimeID: UInt64) {
        deviceTasks[runtimeID]?.cancel()
        deviceTasks.removeValue(forKey: runtimeID)
        clients.removeValue(forKey: runtimeID)
        tracker.removeDevice(runtimeID)
        if let descriptor = descriptors.removeValue(forKey: runtimeID) {
            onEvent(.keyboardDisconnected(stableID: descriptor.stableID))
        }
    }

    private static func keyID(for element: HIDElement) -> KeyID? {
        guard case .keyboardOrKeypad(let usage?) = element.usage,
              KeyCatalog.countedUsageIDs.contains(usage.rawValue) else {
            return nil
        }
        return KeyID(usagePage: KeyCatalog.keyboardPage, usageID: usage.rawValue)
    }

    private static func transportName(_ transport: HIDDeviceTransport?) -> String? {
        // CoreHID has added transport enum cases in newer SDKs. Matching the
        // stable textual names keeps a macOS 15 SDK build compatible with newer
        // development SDKs without making V1 depend on a newer case.
        guard let transport else { return nil }
        switch String(describing: transport) {
        case "usb": return "USB"
        case "bluetooth": return "Bluetooth"
        case "bluetoothLowEnergy": return "Bluetooth Low Energy"
        case "bluetoothAACP": return "Bluetooth AACP"
        case "i2c": return "I2C"
        case "spi": return "SPI"
        case "serial": return "Serial"
        case "spu": return "SPU"
        case "fifo": return "FIFO"
        case "virtual": return "Virtual"
        case "aid": return "AID"
        case "iap": return "iAP"
        case "airPlay": return "AirPlay"
        case "inductiveInBand": return "Inductive In-Band"
        default: return String(describing: transport)
        }
    }
}
