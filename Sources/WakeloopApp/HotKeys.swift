import Carbon.HIToolbox

/// Global shortcuts via Carbon's RegisterEventHotKey, which needs no Accessibility permission.
enum HotKeys {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    static let modifiers = UInt32(controlKey | optionKey | cmdKey)

    @discardableResult
    static func register(keyCode: Int, id: UInt32, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        actions[id] = action
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x574C4F50) /* 'WLOP' */, id: id)
        return RegisterEventHotKey(UInt32(keyCode), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async { HotKeys.actions[hk.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
