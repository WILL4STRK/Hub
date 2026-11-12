/// A global shortcut in Carbon terms (virtual key code + Carbon modifier mask).
public struct HotKeySpec: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var key: String

    // Carbon modifier bits (Events.h): cmdKey, shiftKey, optionKey, controlKey.
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public static func modifiers(command: Bool, option: Bool, control: Bool, shift: Bool) -> UInt32 {
        (command ? Self.command : 0) | (option ? Self.option : 0)
            | (control ? Self.control : 0) | (shift ? Self.shift : 0)
    }

    /// A global shortcut needs at least one of ⌘ ⌥ ⌃ so it does not eat typing.
    public var isValid: Bool {
        modifiers & (Self.command | Self.option | Self.control) != 0 && !key.isEmpty
    }

    /// Display string in macOS order: ⌃⌥⇧⌘ then key.
    public var display: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return s + key
    }
}
