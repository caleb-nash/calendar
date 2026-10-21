import Carbon.HIToolbox

/// System-wide shortcut via Carbon. Unlike event taps, this needs no Accessibility permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private(set) var installStatus: OSStatus = noErr
    private(set) var registerStatus: OSStatus = noErr

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            // If this line never appears when you press the shortcut, the system delivered the
            // keystroke to the frontmost app instead (that app's beep is the audible symptom).
            Log.hotKey.info("Hotkey event received")
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x434C4D4E), id: 1) // "CLMN"
        registerStatus = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)

        Log.hotKey.info("Registration: InstallEventHandler=\(self.installStatus) RegisterEventHotKey=\(self.registerStatus) keyCode=\(keyCode) modifiers=\(modifiers)")
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
