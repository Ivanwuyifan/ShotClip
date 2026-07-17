import Foundation
import Carbon.HIToolbox
import AppKit

func shotLog(_ s: String) {
    let line = "[\(Date())] \(s)\n"
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ShotClip", isDirectory: true)
        .appendingPathComponent("debug.log")
    if let data = line.data(using: .utf8) {
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile(); fh.write(data); try? fh.close()
        } else {
            try? data.write(to: url)
        }
    }
    NSLog(s)
}

final class HotkeyManager {
    private var refs: [EventHotKeyRef?] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    static let shared = HotkeyManager()

    private init() {}

    func start() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
            mgr.handlers[hkID.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        handlers[id] = action
        let hotKeyID = EventHotKeyID(signature: OSType(0x53434C50), id: id) // 'SCLP'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
        shotLog("ShotClip: register hotkey id=\(id) status=\(status) ref=\(ref != nil ? "ok" : "nil")")
        return status == noErr && ref != nil
    }
}
