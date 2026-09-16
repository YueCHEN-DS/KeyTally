import Foundation

struct KeyDefinition: Identifiable, Hashable, Sendable {
    let key: KeyID
    let label: String
    let width: CGFloat

    var id: String { key.storageKey }

    init(_ usageID: UInt16, _ label: String, width: CGFloat = 1) {
        self.key = KeyID(usagePage: KeyCatalog.keyboardPage, usageID: usageID)
        self.label = label
        self.width = width
    }
}

enum KeyCatalog {
    static let keyboardPage: UInt16 = 0x07

    static let labels: [UInt16: String] = {
        var result: [UInt16: String] = [:]
        for (offset, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            result[UInt16(4 + offset)] = String(letter)
        }

        let numberLabels = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        for (offset, label) in numberLabels.enumerated() {
            result[UInt16(30 + offset)] = label
        }

        result.merge([
            40: "Return", 41: "Esc", 42: "Delete", 43: "Tab", 44: "Space",
            45: "-", 46: "=", 47: "[", 48: "]", 49: "\\", 50: "Non-US #",
            51: ";", 52: "'", 53: "`", 54: ",", 55: ".", 56: "/", 57: "Caps Lock",
            70: "Print Screen", 71: "Scroll Lock", 72: "Pause", 73: "Insert",
            74: "Home", 75: "Page Up", 76: "Forward Delete", 77: "End", 78: "Page Down",
            79: "Right Arrow", 80: "Left Arrow", 81: "Down Arrow", 82: "Up Arrow",
            83: "Num Lock", 84: "Keypad /", 85: "Keypad *", 86: "Keypad -",
            87: "Keypad +", 88: "Keypad Enter", 89: "Keypad 1", 90: "Keypad 2",
            91: "Keypad 3", 92: "Keypad 4", 93: "Keypad 5", 94: "Keypad 6",
            95: "Keypad 7", 96: "Keypad 8", 97: "Keypad 9", 98: "Keypad 0",
            99: "Keypad .", 100: "Non-US \\" , 101: "Application", 103: "Keypad =",
            224: "Left Control", 225: "Left Shift", 226: "Left Option", 227: "Left Command",
            228: "Right Control", 229: "Right Shift", 230: "Right Option", 231: "Right Command"
        ], uniquingKeysWith: { _, new in new })

        for index in 1...12 {
            result[UInt16(57 + index)] = "F\(index)"
        }
        for index in 13...24 {
            result[UInt16(91 + index)] = "F\(index)"
        }
        return result
    }()

    static let buttonPage: UInt16 = 0x09
    static let genericDesktopPage: UInt16 = 0x01
    static let mouseLeftButton: UInt16 = 1
    static let mouseRightButton: UInt16 = 2
    static let mouseMiddleButton: UInt16 = 3
    static let mouseWheelScroll: UInt16 = 0x38

    static let countedUsageIDs = Set(labels.keys)

    static func label(for key: KeyID) -> String {
        if key.usagePage == buttonPage {
            switch key.usageID {
            case mouseLeftButton: return "Left Click"
            case mouseRightButton: return "Right Click"
            case mouseMiddleButton: return "Wheel Click"
            default: return "Button \(key.usageID)"
            }
        }
        if key.usagePage == genericDesktopPage && key.usageID == mouseWheelScroll {
            return "Wheel Scroll"
        }
        guard key.usagePage == keyboardPage else {
            return "Usage \(key.usagePage):\(key.usageID)"
        }
        return labels[key.usageID] ?? "Key \(key.usageID)"
    }

    static func isMouseClickKey(_ key: KeyID) -> Bool {
        key.usagePage == buttonPage
            && [mouseLeftButton, mouseRightButton, mouseMiddleButton].contains(key.usageID)
    }

    static func isWheelScrollKey(_ key: KeyID) -> Bool {
        key.usagePage == genericDesktopPage && key.usageID == mouseWheelScroll
    }

    /// Mouse section includes clicks and wheel scroll.
    static func isMouseKey(_ key: KeyID) -> Bool {
        isMouseClickKey(key) || isWheelScrollKey(key)
    }

    /// Headline Today/Lifetime totals count key presses and mouse clicks only.
    /// Continuous wheel scroll is shown in the mouse section but not summed here.
    static func contributesToHeadlineTotal(_ key: KeyID) -> Bool {
        !isWheelScrollKey(key)
    }

    static let heatmapRows: [[KeyDefinition]] = [
        [
            KeyDefinition(41, "Esc", width: 1.25),
            KeyDefinition(58, "F1"), KeyDefinition(59, "F2"), KeyDefinition(60, "F3"),
            KeyDefinition(61, "F4"), KeyDefinition(62, "F5"), KeyDefinition(63, "F6"),
            KeyDefinition(64, "F7"), KeyDefinition(65, "F8"), KeyDefinition(66, "F9"),
            KeyDefinition(67, "F10"), KeyDefinition(68, "F11"), KeyDefinition(69, "F12")
        ],
        [
            KeyDefinition(53, "`"), KeyDefinition(30, "1"), KeyDefinition(31, "2"),
            KeyDefinition(32, "3"), KeyDefinition(33, "4"), KeyDefinition(34, "5"),
            KeyDefinition(35, "6"), KeyDefinition(36, "7"), KeyDefinition(37, "8"),
            KeyDefinition(38, "9"), KeyDefinition(39, "0"), KeyDefinition(45, "-"),
            KeyDefinition(46, "="), KeyDefinition(42, "Delete", width: 1.7)
        ],
        [
            KeyDefinition(43, "Tab", width: 1.45),
            KeyDefinition(20, "Q"), KeyDefinition(26, "W"), KeyDefinition(8, "E"),
            KeyDefinition(21, "R"), KeyDefinition(23, "T"), KeyDefinition(28, "Y"),
            KeyDefinition(24, "U"), KeyDefinition(12, "I"), KeyDefinition(18, "O"),
            KeyDefinition(19, "P"), KeyDefinition(47, "["), KeyDefinition(48, "]"),
            KeyDefinition(49, "\\", width: 1.3)
        ],
        [
            KeyDefinition(57, "Caps", width: 1.75),
            KeyDefinition(4, "A"), KeyDefinition(22, "S"), KeyDefinition(7, "D"),
            KeyDefinition(9, "F"), KeyDefinition(10, "G"), KeyDefinition(11, "H"),
            KeyDefinition(13, "J"), KeyDefinition(14, "K"), KeyDefinition(15, "L"),
            KeyDefinition(51, ";"), KeyDefinition(52, "'"),
            KeyDefinition(40, "Return", width: 2.2)
        ],
        [
            KeyDefinition(225, "Shift", width: 2.25),
            KeyDefinition(29, "Z"), KeyDefinition(27, "X"), KeyDefinition(6, "C"),
            KeyDefinition(25, "V"), KeyDefinition(5, "B"), KeyDefinition(17, "N"),
            KeyDefinition(16, "M"), KeyDefinition(54, ","), KeyDefinition(55, "."),
            KeyDefinition(56, "/"), KeyDefinition(229, "Shift", width: 2.65)
        ],
        [
            KeyDefinition(224, "⌃", width: 1.25), KeyDefinition(226, "⌥", width: 1.25),
            KeyDefinition(227, "⌘", width: 1.5), KeyDefinition(44, "Space", width: 6.1),
            KeyDefinition(231, "⌘", width: 1.5), KeyDefinition(230, "⌥", width: 1.25),
            KeyDefinition(228, "⌃", width: 1.25), KeyDefinition(80, "←"),
            KeyDefinition(81, "↓"), KeyDefinition(82, "↑"), KeyDefinition(79, "→")
        ]
    ]

    static let heatmapStorageKeys = Set(heatmapRows.flatMap { $0 }.map(\.id))

    static var nonHeatmapKeys: [KeyDefinition] {
        labels.keys
            .filter { !heatmapStorageKeys.contains(KeyID(usagePage: keyboardPage, usageID: $0).storageKey) }
            .sorted()
            .map { KeyDefinition($0, labels[$0] ?? "Key \($0)") }
    }
}
