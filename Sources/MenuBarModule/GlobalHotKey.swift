import Carbon
import ShelfCore

/// One system-wide shortcut via Carbon RegisterEventHotKey.
/// Needs no Accessibility or Input Monitoring permission.
/// Each instance has its own id, so several shortcuts can coexist.
final class GlobalHotKey {
    var onPress: (() -> Void)?
    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(id: UInt32) {
        self.id = id
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                // Not ours: let the next handler (another GlobalHotKey) take it.
                guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async { hotKey.onPress?() }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }

    /// Replaces the current shortcut. Returns false if macOS refused it
    /// (for example, another app already owns that combination).
    @discardableResult
    func register(_ spec: HotKeySpec?) -> Bool {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard let spec, spec.isValid else { return true }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5348_4C46), id: id) // "SHLF"
        return RegisterEventHotKey(spec.keyCode, spec.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }
}
