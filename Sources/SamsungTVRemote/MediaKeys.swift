import AppKit
import ApplicationServices

/// Redirects the Mac's volume up, down and mute keys to the TV while it is connected.
/// Needs Accessibility permission, because the tap swallows the keys so the Mac volume stays put.
@MainActor final class MediaKeys {
    static let defaultsKey = "macVolumeKeys"
    /// Whether the TV can take the keys right now; otherwise they go to macOS as usual.
    var active: () -> Bool = { false }
    var send: (TVKey) -> Void = { _ in }
    fileprivate var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var poll: Timer?

    static var enabled: Bool { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    func update(prompt: Bool) {
        if Self.enabled { start(prompt: prompt) } else { stop() }
    }

    private func start(prompt: Bool) {
        guard tap == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            // Permission is granted in System Settings; pick it up without a relaunch.
            if poll == nil {
                poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, Self.trusted else { return }
                        self.poll?.invalidate(); self.poll = nil
                        self.start(prompt: false)
                    }
                }
            }
            return
        }
        let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.systemDefined.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: mediaKeyCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        poll?.invalidate(); poll = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }

    fileprivate func handle(_ key: TVKey, down: Bool, repeating: Bool) -> Bool {
        guard Self.enabled, active() else { return false }
        // Swallow key-up too, so macOS never sees half of a press it would otherwise act on.
        if down && !(key == .mute && repeating) { send(key) }
        return true
    }
}

// NX_KEYTYPE_SOUND_UP, NX_KEYTYPE_SOUND_DOWN and NX_KEYTYPE_MUTE from IOKit's ev_keymap.h.
private let mediaKeyCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let keys = Unmanaged<MediaKeys>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { if let tap = keys.tap { CGEvent.tapEnable(tap: tap, enable: true) } }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == UInt32(NSEvent.EventType.systemDefined.rawValue),
          let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
    let code = (ns.data1 & 0xFFFF0000) >> 16
    let state = (ns.data1 & 0xFF00) >> 8
    let key: TVKey
    switch code {
    case 0: key = .volumeUp
    case 1: key = .volumeDown
    case 7: key = .mute
    default: return Unmanaged.passUnretained(event)
    }
    let consumed = MainActor.assumeIsolated {
        keys.handle(key, down: state == 0xA, repeating: ns.data1 & 0x1 != 0)
    }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
