// Clinton Imaro was here 20/09/2026.

import AppKit
import Carbon

final class GlobalShortcuts {
    var onRecenter: (() -> Void)?
    var onEscape: (() -> Void)?
    var onPrivacy: (() -> Void)?
    var onPeek: ((Bool) -> Void)?
    private var recenterRef: EventHotKeyRef?
    private var escapeRef: EventHotKeyRef?
    private var privacyRef: EventHotKeyRef?
    private var peekRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let signature: OSType = 0x51474C53

    init() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            let pressed = GetEventKind(event) == kEventHotKeyPressed
            if pressed, identifier.id == 1 { owner.onRecenter?() }
            if pressed, identifier.id == 2 { owner.onEscape?() }
            if pressed, identifier.id == 3 { owner.onPrivacy?() }
            if identifier.id == 4 { owner.onPeek?(pressed) }
            return noErr
        }, 2, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    @discardableResult
    func setPrivacyShortcut() -> Bool {
        if privacyRef != nil { return true }
        return RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: signature, id: 3), GetApplicationEventTarget(), 0, &privacyRef) == noErr
    }

    @discardableResult
    func armPeek(_ active: Bool) -> Bool {
        if active && peekRef == nil {
            return RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: signature, id: 4), GetApplicationEventTarget(), 0, &peekRef) == noErr
        } else if !active, let peekRef {
            UnregisterEventHotKey(peekRef)
            self.peekRef = nil
        }
        return true
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
        if let privacyRef { UnregisterEventHotKey(privacyRef) }
        if let peekRef { UnregisterEventHotKey(peekRef) }
        if let handler { RemoveEventHandler(handler) }
    }
}
