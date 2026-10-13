import Foundation

/// The two physical side buttons handled by MacMouseMapper. Quartz numbers them
/// as 3 and 4, while users generally call them buttons 4 and 5.
public enum SideButton: String, CaseIterable, Codable, Sendable {
    case button4
    case button5

    public var displayName: String {
        switch self {
        case .button4: return "Button 4"
        case .button5: return "Button 5"
        }
    }

    public var quartzButtonNumber: UInt32 {
        switch self {
        case .button4: return 3
        case .button5: return 4
        }
    }

    public init?(quartzButtonNumber: UInt32) {
        switch quartzButtonNumber {
        case 3: self = .button4
        case 4: self = .button5
        default: return nil
        }
    }
}

/// Modifier flags stored in a platform-neutral, stable form.
public struct ModifierMask: OptionSet, Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = ModifierMask(rawValue: 1 << 0)
    public static let option = ModifierMask(rawValue: 1 << 1)
    public static let control = ModifierMask(rawValue: 1 << 2)
    public static let shift = ModifierMask(rawValue: 1 << 3)
    public static let function = ModifierMask(rawValue: 1 << 4)

    /// Converts the platform's event modifier bit field into the modifiers that
    /// can be persisted in a keyboard shortcut. AppKit's raw values are kept
    /// here as constants so capture validation remains testable without AppKit.
    public init(eventModifierRawValue rawValue: UInt) {
        var result: ModifierMask = []
        if rawValue & (1 << 20) != 0 { result.insert(.command) }
        if rawValue & (1 << 19) != 0 { result.insert(.option) }
        if rawValue & (1 << 18) != 0 { result.insert(.control) }
        if rawValue & (1 << 17) != 0 { result.insert(.shift) }
        if rawValue & (1 << 23) != 0 { result.insert(.function) }
        self = result
    }

    public static let allowed: ModifierMask = [.command, .option, .control, .shift, .function]


    public var isValid: Bool {
        intersection(Self.allowed) == self
    }

    public var displayName: String {
        var names: [String] = []
        if contains(.command) { names.append("⌘") }
        if contains(.option) { names.append("⌥") }
        if contains(.control) { names.append("⌃") }
        if contains(.shift) { names.append("⇧") }
        if contains(.function) { names.append("fn") }
        return names.joined()
    }
}

/// Key codes are virtual-key values from the public Quartz keyboard-event API.
/// Keeping this catalog in the core target lets the UI and tests share validation.
public enum KeyCatalog {
    public struct Entry: Equatable, Sendable {
        public let keyCode: UInt16
        public let name: String
        public let shortName: String

        public init(keyCode: UInt16, name: String, shortName: String) {
            self.keyCode = keyCode
            self.name = name
            self.shortName = shortName
        }
    }

    public static let entries: [Entry] = [
        // ANSI letters and digits.
        Entry(keyCode: 0x00, name: "A", shortName: "A"),
        Entry(keyCode: 0x01, name: "S", shortName: "S"),
        Entry(keyCode: 0x02, name: "D", shortName: "D"),
        Entry(keyCode: 0x03, name: "F", shortName: "F"),
        Entry(keyCode: 0x04, name: "H", shortName: "H"),
        Entry(keyCode: 0x05, name: "G", shortName: "G"),
        Entry(keyCode: 0x06, name: "Z", shortName: "Z"),
        Entry(keyCode: 0x07, name: "X", shortName: "X"),
        Entry(keyCode: 0x08, name: "C", shortName: "C"),
        Entry(keyCode: 0x09, name: "V", shortName: "V"),
        Entry(keyCode: 0x0B, name: "B", shortName: "B"),
        Entry(keyCode: 0x0C, name: "Q", shortName: "Q"),
        Entry(keyCode: 0x0D, name: "W", shortName: "W"),
        Entry(keyCode: 0x0E, name: "E", shortName: "E"),
        Entry(keyCode: 0x0F, name: "R", shortName: "R"),
        Entry(keyCode: 0x10, name: "Y", shortName: "Y"),
        Entry(keyCode: 0x11, name: "T", shortName: "T"),
        Entry(keyCode: 0x12, name: "1", shortName: "1"),
        Entry(keyCode: 0x13, name: "2", shortName: "2"),
        Entry(keyCode: 0x14, name: "3", shortName: "3"),
        Entry(keyCode: 0x15, name: "4", shortName: "4"),
        Entry(keyCode: 0x16, name: "6", shortName: "6"),
        Entry(keyCode: 0x17, name: "5", shortName: "5"),
        Entry(keyCode: 0x18, name: "Equal", shortName: "="),
        Entry(keyCode: 0x19, name: "9", shortName: "9"),
        Entry(keyCode: 0x1A, name: "7", shortName: "7"),
        Entry(keyCode: 0x1B, name: "Minus", shortName: "-"),
        Entry(keyCode: 0x1C, name: "8", shortName: "8"),
        Entry(keyCode: 0x1D, name: "0", shortName: "0"),
        Entry(keyCode: 0x1F, name: "O", shortName: "O"),
        Entry(keyCode: 0x20, name: "U", shortName: "U"),
        Entry(keyCode: 0x22, name: "I", shortName: "I"),
        Entry(keyCode: 0x23, name: "P", shortName: "P"),
        Entry(keyCode: 0x25, name: "L", shortName: "L"),
        Entry(keyCode: 0x26, name: "J", shortName: "J"),
        Entry(keyCode: 0x28, name: "K", shortName: "K"),
        Entry(keyCode: 0x2D, name: "N", shortName: "N"),
        Entry(keyCode: 0x2E, name: "M", shortName: "M"),

        // ANSI punctuation; modifier virtual keys are intentionally omitted.
        Entry(keyCode: 0x1E, name: "Right Bracket", shortName: "]"),
        Entry(keyCode: 0x21, name: "Left Bracket", shortName: "["),
        Entry(keyCode: 0x27, name: "Quote", shortName: "'"),
        Entry(keyCode: 0x29, name: "Semicolon", shortName: ";"),
        Entry(keyCode: 0x2A, name: "Backslash", shortName: "\\"),
        Entry(keyCode: 0x2B, name: "Comma", shortName: ","),
        Entry(keyCode: 0x2C, name: "Slash", shortName: "/"),
        Entry(keyCode: 0x2F, name: "Period", shortName: "."),
        Entry(keyCode: 0x32, name: "Grave Accent", shortName: "`"),

        // Editing and navigation.
        Entry(keyCode: 0x24, name: "Return", shortName: "↩"),
        Entry(keyCode: 0x30, name: "Tab", shortName: "⇥"),
        Entry(keyCode: 0x31, name: "Space", shortName: "Space"),
        Entry(keyCode: 0x33, name: "Delete", shortName: "⌫"),
        Entry(keyCode: 0x35, name: "Escape", shortName: "⎋"),
        Entry(keyCode: 0x72, name: "Help", shortName: "Help"),
        Entry(keyCode: 0x73, name: "Home", shortName: "Home"),
        Entry(keyCode: 0x74, name: "Page Up", shortName: "Page Up"),
        Entry(keyCode: 0x75, name: "Forward Delete", shortName: "⌦"),
        Entry(keyCode: 0x77, name: "End", shortName: "End"),
        Entry(keyCode: 0x79, name: "Page Down", shortName: "Page Down"),
        Entry(keyCode: 0x7B, name: "Left Arrow", shortName: "←"),
        Entry(keyCode: 0x7C, name: "Right Arrow", shortName: "→"),
        Entry(keyCode: 0x7E, name: "Up Arrow", shortName: "↑"),
        Entry(keyCode: 0x7D, name: "Down Arrow", shortName: "↓"),

        // Standard function row, including the F13-F20 keys.
        Entry(keyCode: 0x7A, name: "F1", shortName: "F1"),
        Entry(keyCode: 0x78, name: "F2", shortName: "F2"),
        Entry(keyCode: 0x63, name: "F3", shortName: "F3"),
        Entry(keyCode: 0x76, name: "F4", shortName: "F4"),
        Entry(keyCode: 0x60, name: "F5", shortName: "F5"),
        Entry(keyCode: 0x61, name: "F6", shortName: "F6"),
        Entry(keyCode: 0x62, name: "F7", shortName: "F7"),
        Entry(keyCode: 0x64, name: "F8", shortName: "F8"),
        Entry(keyCode: 0x65, name: "F9", shortName: "F9"),
        Entry(keyCode: 0x6D, name: "F10", shortName: "F10"),
        Entry(keyCode: 0x67, name: "F11", shortName: "F11"),
        Entry(keyCode: 0x6F, name: "F12", shortName: "F12"),
        Entry(keyCode: 0x69, name: "F13", shortName: "F13"),
        Entry(keyCode: 0x6B, name: "F14", shortName: "F14"),
        Entry(keyCode: 0x71, name: "F15", shortName: "F15"),
        Entry(keyCode: 0x6A, name: "F16", shortName: "F16"),
        Entry(keyCode: 0x40, name: "F17", shortName: "F17"),
        Entry(keyCode: 0x4F, name: "F18", shortName: "F18"),
        Entry(keyCode: 0x50, name: "F19", shortName: "F19"),
        Entry(keyCode: 0x5A, name: "F20", shortName: "F20"),

        // Numeric keypad keys and operators.
        Entry(keyCode: 0x52, name: "Keypad 0", shortName: "Num 0"),
        Entry(keyCode: 0x53, name: "Keypad 1", shortName: "Num 1"),
        Entry(keyCode: 0x54, name: "Keypad 2", shortName: "Num 2"),
        Entry(keyCode: 0x55, name: "Keypad 3", shortName: "Num 3"),
        Entry(keyCode: 0x56, name: "Keypad 4", shortName: "Num 4"),
        Entry(keyCode: 0x57, name: "Keypad 5", shortName: "Num 5"),
        Entry(keyCode: 0x58, name: "Keypad 6", shortName: "Num 6"),
        Entry(keyCode: 0x59, name: "Keypad 7", shortName: "Num 7"),
        Entry(keyCode: 0x5B, name: "Keypad 8", shortName: "Num 8"),
        Entry(keyCode: 0x5C, name: "Keypad 9", shortName: "Num 9"),
        Entry(keyCode: 0x41, name: "Keypad Decimal", shortName: "Num ."),
        Entry(keyCode: 0x43, name: "Keypad Multiply", shortName: "Num ×"),
        Entry(keyCode: 0x45, name: "Keypad Plus", shortName: "Num +"),
        Entry(keyCode: 0x47, name: "Keypad Clear", shortName: "Num Clear"),
        Entry(keyCode: 0x4B, name: "Keypad Divide", shortName: "Num ÷"),
        Entry(keyCode: 0x4C, name: "Keypad Enter", shortName: "Num ↩"),
        Entry(keyCode: 0x4E, name: "Keypad Minus", shortName: "Num −"),
        Entry(keyCode: 0x51, name: "Keypad Equals", shortName: "Num ="),

        // Consumer volume controls represented by Quartz virtual key codes.
        Entry(keyCode: 0x48, name: "Volume Up", shortName: "Vol +"),
        Entry(keyCode: 0x49, name: "Volume Down", shortName: "Vol −"),
        Entry(keyCode: 0x4A, name: "Mute", shortName: "Mute")
    ]

    public static func entry(for keyCode: UInt16) -> Entry? {
        entries.first { $0.keyCode == keyCode }
    }

    public static var validKeyCodes: Set<UInt16> {
        Set(entries.map(\.keyCode))
    }
}

public struct KeyboardShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: ModifierMask

    public init(keyCode: UInt16, modifiers: ModifierMask = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    /// Builds a shortcut from a physical key event only when both the key and
    /// its supported modifier set are valid. Modifier-only and unknown keys
    /// therefore fail before they can reach persistence.
    public init?(capturedKeyCode keyCode: UInt16, eventModifierRawValue rawValue: UInt) {
        let modifiers = ModifierMask(eventModifierRawValue: rawValue)
        self.init(keyCode: keyCode, modifiers: modifiers)
        guard isValid else { return nil }
    }
    public var isValid: Bool {
        KeyCatalog.validKeyCodes.contains(keyCode) && modifiers.isValid
    }

    public var displayName: String {
        let key = KeyCatalog.entry(for: keyCode)?.shortName ?? "Invalid key"
        return modifiers.displayName + key
    }
}

public struct MouseButton: Codable, Equatable, Sendable {
    public var number: UInt32

    public init(number: UInt32) {
        self.number = number
    }

    public var isValid: Bool {
        number <= 15
    }

    public var displayName: String {
        switch number {
        case 0: return "Left click"
        case 1: return "Right click"
        case 2: return "Middle click"
        default: return "Button \(number + 1)"
        }
    }
}

public enum GestureKind: String, Codable, CaseIterable, Sendable {
    case smoothScrollUp
    case smoothScrollDown
    case smoothScrollLeft
    case smoothScrollRight
    case smoothSwipeUp
    case smoothSwipeDown
    case smoothSwipeLeft
    case smoothSwipeRight

    public var displayName: String {
        switch self {
        case .smoothScrollUp: return "Smooth scroll up"
        case .smoothScrollDown: return "Smooth scroll down"
        case .smoothScrollLeft: return "Smooth scroll left"
        case .smoothScrollRight: return "Smooth scroll right"
        case .smoothSwipeUp: return "Smooth swipe up"
        case .smoothSwipeDown: return "Smooth swipe down"
        case .smoothSwipeLeft: return "Smooth swipe left"
        case .smoothSwipeRight: return "Smooth swipe right"
        }
    }
}

public enum MappingAction: Codable, Equatable, Sendable {
    case keyboard(KeyboardShortcut)
    case mouse(MouseButton)
    case gesture(GestureKind)

    private enum CodingKeys: String, CodingKey {
        case type
        case shortcut
        case mouse
        case gesture
    }

    private enum ActionType: String, Codable {
        case keyboard
        case mouse
        case gesture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)
        switch type {
        case .keyboard:
            self = .keyboard(try container.decode(KeyboardShortcut.self, forKey: .shortcut))
        case .mouse:
            self = .mouse(try container.decode(MouseButton.self, forKey: .mouse))
        case .gesture:
            self = .gesture(try container.decode(GestureKind.self, forKey: .gesture))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keyboard(let shortcut):
            try container.encode(ActionType.keyboard, forKey: .type)
            try container.encode(shortcut, forKey: .shortcut)
        case .mouse(let button):
            try container.encode(ActionType.mouse, forKey: .type)
            try container.encode(button, forKey: .mouse)
        case .gesture(let gesture):
            try container.encode(ActionType.gesture, forKey: .type)
            try container.encode(gesture, forKey: .gesture)
        }
    }

    public var isValid: Bool {
        switch self {
        case .keyboard(let shortcut): return shortcut.isValid
        case .mouse(let button): return button.isValid
        case .gesture: return true
        }
    }

    public var displayName: String {
        switch self {
        case .keyboard(let shortcut): return shortcut.displayName
        case .mouse(let button): return button.displayName
        case .gesture(let gesture): return gesture.displayName
        }
    }
}

public struct ButtonMapping: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var action: MappingAction

    public init(action: MappingAction, isEnabled: Bool = true) {
        self.action = action
        self.isEnabled = isEnabled
    }

    public var isValid: Bool {
        action.isValid
    }

    public var isUsable: Bool {
        isEnabled && isValid
    }
}

public struct ButtonMappings: Codable, Equatable, Sendable {
    public var button4: ButtonMapping?
    public var button5: ButtonMapping?

    public init(button4: ButtonMapping? = nil, button5: ButtonMapping? = nil) {
        self.button4 = button4
        self.button5 = button5
    }

    public func mapping(for button: SideButton) -> ButtonMapping? {
        switch button {
        case .button4: return button4
        case .button5: return button5
        }
    }

    public mutating func setMapping(_ mapping: ButtonMapping?, for button: SideButton) {
        switch button {
        case .button4: button4 = mapping
        case .button5: button5 = mapping
        }
    }
}

public struct AppOverride: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var displayName: String
    public var mappings: ButtonMappings

    public init(bundleIdentifier: String, displayName: String, mappings: ButtonMappings = ButtonMappings()) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.mappings = mappings
    }

    public var isValid: Bool {
        Self.isValidBundleIdentifier(bundleIdentifier)
    }

    public static func isValidBundleIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 255 else { return false }
        let alphanumerics = CharacterSet.alphanumerics
        return trimmed.unicodeScalars.allSatisfy { scalar in
            scalar == "." || scalar == "-" || scalar == "_" || alphanumerics.contains(scalar)
        }
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var globalMappings: ButtonMappings
    public var appOverrides: [AppOverride]

    public init(
        isEnabled: Bool = true,
        globalMappings: ButtonMappings = ButtonMappings(),
        appOverrides: [AppOverride] = []
    ) {
        self.isEnabled = isEnabled
        self.globalMappings = globalMappings
        self.appOverrides = appOverrides
    }

    public static let `default` = AppConfiguration()

    /// Drops invalid individual mappings and duplicate/invalid app identities while
    /// preserving every valid setting that can be recovered from disk.
    public func sanitized() -> AppConfiguration {
        var result = self
        result.globalMappings.button4 = globalMappings.button4?.isValid == true ? globalMappings.button4 : nil
        result.globalMappings.button5 = globalMappings.button5?.isValid == true ? globalMappings.button5 : nil

        var seenBundleIdentifiers = Set<String>()
        result.appOverrides = appOverrides.compactMap { override in
            guard override.isValid else { return nil }
            let bundleIdentifier = override.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard seenBundleIdentifiers.insert(bundleIdentifier).inserted else { return nil }
            let displayName = override.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return AppOverride(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName.isEmpty ? bundleIdentifier : displayName,
                mappings: ButtonMappings(
                    button4: override.mappings.button4?.isValid == true ? override.mappings.button4 : nil,
                    button5: override.mappings.button5?.isValid == true ? override.mappings.button5 : nil
                )
            )
        }
        return result
    }
}

public struct PersistedConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var configuration: AppConfiguration

    public init(version: Int = PersistedConfiguration.currentVersion, configuration: AppConfiguration) {
        self.version = version
        self.configuration = configuration
    }
}
