import Carbon.HIToolbox

/// System-wide shortcut via Carbon. Unlike event taps, this needs no Accessibility permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void
    private(set) var installStatus: OSStatus = noErr
    private(set) var registerStatus: OSStatus = noErr

    /// `id` must be unique per shortcut: every handler sees every hotkey press and uses it to
    /// pick out its own.
    init?(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.id = id
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            // Not ours: let the next handler in the chain take it.
            guard status == noErr, pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            // If this line never appears when you press the shortcut, the system delivered the
            // keystroke to the frontmost app instead (that app's beep is the audible symptom).
            Log.hotKey.info("Hotkey event received id=\(pressed.id)")
            hotKey.action()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4D4E), id: id) // "CLMN"
        registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        Log.hotKey.info("Registration id=\(id): InstallEventHandler=\(self.installStatus) RegisterEventHotKey=\(self.registerStatus) keyCode=\(keyCode) modifiers=\(modifiers)")
        if installStatus != noErr || registerStatus != noErr {
            Log.hotKey.error("Hotkey registration failed (eventHotKeyExistsErr=\(eventHotKeyExistsErr) means another app owns this combo)")
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
