import CryptoKit
import Darwin
import Foundation

struct KeyID: Hashable, Codable, Sendable, Comparable {
    let usagePage: UInt16
    let usageID: UInt16

    var storageKey: String { "\(usagePage):\(usageID)" }

    init(usagePage: UInt16, usageID: UInt16) {
        self.usagePage = usagePage
        self.usageID = usageID
    }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let page = UInt16(parts[0]),
              let usage = UInt16(parts[1]) else {
            return nil
        }
        self.init(usagePage: page, usageID: usage)
    }

    static func < (lhs: KeyID, rhs: KeyID) -> Bool {
        (lhs.usagePage, lhs.usageID) < (rhs.usagePage, rhs.usageID)
    }
}

struct KeyboardDescriptor: Hashable, Sendable {
    let runtimeID: UInt64
    let stableID: String
    let reportedName: String
    let isBuiltIn: Bool
    let elementCount: Int
}

struct KeyboardRecord: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var reportedName: String
    var customName: String?
    let isBuiltIn: Bool

    var displayName: String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? reportedName : trimmed
    }
}

struct StoredState: Codable, Equatable, Sendable {
    var version = 1
    var keyboards: [KeyboardRecord] = []
    var days: [DayRecord] = []
}

struct DayRecord: Codable, Equatable, Sendable {
    let date: String
    var devices: [DeviceCounts]
}

struct DeviceCounts: Codable, Equatable, Sendable {
    let deviceID: String
    var keys: [String: UInt64]
}

struct DailyTotal: Identifiable, Equatable, Sendable {
    let date: String
    let total: UInt64

    var id: String { date }
}

enum InputPermissionState: String, Sendable {
    case granted
    case denied
    case unknown
}

enum CaptureEvent: Sendable {
    case keyboardConnected(KeyboardDescriptor)
    case keyboardDisconnected(stableID: String)
    case keyPressed(stableID: String, key: KeyID)
    case problem(String)
}

enum LocalDay {
    static func string(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

enum DeviceIdentity {
    static func make(
        runtimeID: UInt64,
        isBuiltIn: Bool,
        manufacturer: String?,
        product: String?,
        modelNumber: String?,
        vendorID: UInt32,
        productID: UInt32,
        transport: String?,
        uniqueID: String?,
        serialNumber: String?,
        locationID: UInt64?
    ) -> (stableID: String, reportedName: String) {
        let manufacturer = clean(manufacturer)
        let product = clean(product)
        let modelNumber = clean(modelNumber)
        let transport = clean(transport)

        let source: String
        if isBuiltIn {
            source = "built-in|\(systemModelIdentifier())"
        } else if let uniqueID = clean(uniqueID) {
            source = "unique|\(uniqueID)"
        } else if let serialNumber = clean(serialNumber) {
            source = "serial|\(serialNumber)"
        } else if vendorID != 0 || productID != 0 || product != nil || locationID != nil {
            source = [
                "hardware",
                String(vendorID),
                String(productID),
                product ?? "",
                transport ?? "",
                locationID.map(String.init) ?? ""
            ].joined(separator: "|")
        } else {
            source = "runtime|\(runtimeID)"
        }

        let reportedName: String
        if isBuiltIn {
            reportedName = "Built-in Keyboard"
        } else if let modelNumber {
            reportedName = joinedName(manufacturer, modelNumber)
        } else if let product {
            if let manufacturer,
               product.localizedCaseInsensitiveContains(manufacturer) {
                reportedName = product
            } else {
                reportedName = joinedName(manufacturer, product)
            }
        } else if vendorID != 0 || productID != 0 {
            reportedName = String(format: "External Keyboard %04X:%04X", vendorID, productID)
        } else {
            reportedName = "Unknown Keyboard"
        }

        return ("kbd-\(sha256(source))", reportedName)
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func joinedName(_ first: String?, _ second: String) -> String {
        [first, second].compactMap { $0 }.joined(separator: " ")
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func systemModelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            return "Mac"
        }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &value, &size, nil, 0) == 0 else {
            return "Mac"
        }
        return String(cString: value)
    }
}
