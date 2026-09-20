import AppKit
import Carbon

final class GlobalShortcuts {
    var onRecenter: (() -> Void)?
    var onEscape: (() -> Void)?
    private var recenterRef: EventHotKeyRef?
    private var escapeRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let signature: OSType = 0x51474C53 // QGLS

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            if identifier.id == 1 { owner.onRecenter?() }
            if identifier.id == 2 { owner.onEscape?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    @discardableResult
    func setRecenter(keyCode: UInt32, modifiers: UInt32) -> Bool {
        var newRef: EventHotKeyRef?
        let result = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: signature, id: 1), GetApplicationEventTarget(), 0, &newRef)
        guard result == noErr else { return false }
        if let recenterRef { UnregisterEventHotKey(recenterRef) }
        recenterRef = newRef
        return true
    }

    @discardableResult
    func armEscape(_ active: Bool) -> Bool {
        if active && escapeRef == nil {
            return RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: signature, id: 2), GetApplicationEventTarget(), 0, &escapeRef) == noErr
        } else if !active, let escapeRef {
            UnregisterEventHotKey(escapeRef)
            self.escapeRef = nil
        }
        return true
    }

    deinit {
        if let recenterRef { UnregisterEventHotKey(recenterRef) }
        if let escapeRef { UnregisterEventHotKey(escapeRef) }
        if let handler { RemoveEventHandler(handler) }
    }
}
