import Carbon.HIToolbox

/// System-wide shortcut via Carbon. Unlike event taps, this needs no Accessibility permission.
///
/// All shortcuts share one Carbon event handler that looks up the pressed shortcut by its ID.
/// (Installing a separate handler per shortcut meant only the most recently installed one ever
/// saw the presses, so only the last shortcut worked.)
final class HotKey {
    private static var registered: [UInt32: HotKey] = [:]
    private static var sharedHandler: EventHandlerRef?

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32
    private let action: () -> Void
    private(set) var installStatus: OSStatus = noErr
    private(set) var registerStatus: OSStatus = noErr

    /// `id` must be unique per shortcut.
    init?(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.id = id
        self.action = action

        installStatus = Self.installSharedHandler()

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4D4E), id: id) // "CLMN"
        registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        Log.hotKey.info("Registration id=\(id): InstallEventHandler=\(self.installStatus) RegisterEventHotKey=\(self.registerStatus) keyCode=\(keyCode) modifiers=\(modifiers)")
        if installStatus != noErr || registerStatus != noErr {
            Log.hotKey.error("Hotkey registration failed (eventHotKeyExistsErr=\(eventHotKeyExistsErr) means another app owns this combo)")
            return nil
        }
        Self.registered[id] = self
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    }

    private static func installSharedHandler() -> OSStatus {
        guard sharedHandler == nil else { return noErr }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        return InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            // If this line never appears when you press the shortcut, the system delivered the
            // keystroke to the frontmost app instead (that app's beep is the audible symptom).
            Log.hotKey.info("Hotkey event received id=\(pressed.id) status=\(status)")
            guard status == noErr, let hotKey = HotKey.registered[pressed.id] else {
                Log.hotKey.error("No shortcut registered for id=\(pressed.id)")
                return OSStatus(eventNotHandledErr)
            }
            hotKey.action()
            return noErr
        }, 1, &eventType, nil, &sharedHandler)
    }
}
