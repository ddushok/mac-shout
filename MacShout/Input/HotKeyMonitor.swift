import Foundation
import Carbon
import AppKit

struct HotKey: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt32
    
    static let defaultHotKey = HotKey(
        keyCode: UInt16(kVK_RightOption),
        modifiers: 0
    )
    
    var displayString: String {
        var parts: [String] = []
        
        // Modifiers
        if modifiers & UInt32(CGEventFlags.maskControl.rawValue) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt32(CGEventFlags.maskAlternate.rawValue) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(CGEventFlags.maskShift.rawValue) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(CGEventFlags.maskCommand.rawValue) != 0 {
            parts.append("⌘")
        }
        
        // Key name
        if let keyName = keyCodeToString(keyCode) {
            parts.append(keyName)
        } else {
            parts.append("Key \(keyCode)")
        }
        
        return parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case UInt16(kVK_RightOption): return "Right Option"
        case UInt16(kVK_Option): return "Left Option"
        case UInt16(kVK_RightCommand): return "Right Command"
        case UInt16(kVK_Command): return "Left Command"
        case UInt16(kVK_RightControl): return "Right Control"
        case UInt16(kVK_Control): return "Left Control"
        case UInt16(kVK_RightShift): return "Right Shift"
        case UInt16(kVK_Shift): return "Left Shift"
        case UInt16(kVK_Space): return "Space"
        case UInt16(kVK_Return): return "Return"
        case UInt16(kVK_Tab): return "Tab"
        case UInt16(kVK_Delete): return "Delete"
        case UInt16(kVK_Escape): return "Escape"
        case UInt16(kVK_F1): return "F1"
        case UInt16(kVK_F2): return "F2"
        case UInt16(kVK_F3): return "F3"
        case UInt16(kVK_F4): return "F4"
        case UInt16(kVK_F5): return "F5"
        case UInt16(kVK_F6): return "F6"
        case UInt16(kVK_F7): return "F7"
        case UInt16(kVK_F8): return "F8"
        case UInt16(kVK_F9): return "F9"
        case UInt16(kVK_F10): return "F10"
        case UInt16(kVK_F11): return "F11"
        case UInt16(kVK_F12): return "F12"
        case UInt16(kVK_F13): return "F13"
        case UInt16(kVK_F14): return "F14"
        case UInt16(kVK_F15): return "F15"
        case UInt16(kVK_F16): return "F16"
        case UInt16(kVK_F17): return "F17"
        case UInt16(kVK_F18): return "F18"
        case UInt16(kVK_F19): return "F19"
        case UInt16(kVK_F20): return "F20"
        default:
            return nil
        }
    }
}

class HotKeyMonitor: ObservableObject {
    @Published var isEnabled = false
    @Published var hasAccessibilityPermission = false
    
    var hotKey: HotKey {
        didSet {
            if isEnabled {
                stop()
                start()
            }
        }
    }
    
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyCurrentlyPressed = false
    
    init(hotKey: HotKey = .defaultHotKey) {
        self.hotKey = hotKey
        checkAccessibilityPermission()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Permission Management
    
    func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let hasPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = hasPermission
        }
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let hasPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = hasPermission
        }
        
        if !hasPermission {
            // Show alert to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "MacShout needs Accessibility permissions to capture global keyboard shortcuts. Please enable it in System Settings > Privacy & Security > Accessibility."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
    }
    
    // MARK: - Event Tap Management
    
    func start() {
        guard !isEnabled else { return }
        
        checkAccessibilityPermission()
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            return
        }
        
        // Create event tap
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap")
            return
        }
        
        eventTap = tap
        
        // Create run loop source
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)
        
        DispatchQueue.main.async {
            self.isEnabled = true
        }
        
        print("HotKey monitor started for \(hotKey.displayString)")
    }
    
    func stop() {
        guard isEnabled else { return }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        
        isKeyCurrentlyPressed = false
        
        DispatchQueue.main.async {
            self.isEnabled = false
        }
        
        print("HotKey monitor stopped")
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Check if this is our hotkey
        if keyCode == hotKey.keyCode {
            // Check modifiers match (if any configured)
            let currentModifiers = flags.rawValue & (
                CGEventFlags.maskControl.rawValue |
                CGEventFlags.maskAlternate.rawValue |
                CGEventFlags.maskShift.rawValue |
                CGEventFlags.maskCommand.rawValue
            )
            
            let matchesModifiers = (hotKey.modifiers == 0) || (currentModifiers == UInt64(hotKey.modifiers))
            
            if matchesModifiers {
                if type == .keyDown && !isKeyCurrentlyPressed {
                    isKeyCurrentlyPressed = true
                    DispatchQueue.main.async {
                        self.onKeyDown?()
                    }
                    // Consume the event
                    return nil
                } else if type == .keyUp && isKeyCurrentlyPressed {
                    isKeyCurrentlyPressed = false
                    DispatchQueue.main.async {
                        self.onKeyUp?()
                    }
                    // Consume the event
                    return nil
                }
            }
        }
        
        // Pass through other events
        return Unmanaged.passRetained(event)
    }
}

// MARK: - Key Code Constants

extension HotKeyMonitor {
    static let commonKeyCodes: [(String, UInt16)] = [
        ("Space", UInt16(kVK_Space)),
        ("Right Option", UInt16(kVK_RightOption)),
        ("Left Option", UInt16(kVK_Option)),
        ("Right Command", UInt16(kVK_RightCommand)),
        ("Left Command", UInt16(kVK_Command)),
        ("Right Control", UInt16(kVK_RightControl)),
        ("Left Control", UInt16(kVK_Control)),
        ("Right Shift", UInt16(kVK_RightShift)),
        ("Left Shift", UInt16(kVK_Shift)),
        ("F13", UInt16(kVK_F13)),
        ("F14", UInt16(kVK_F14)),
        ("F15", UInt16(kVK_F15)),
        ("F16", UInt16(kVK_F16)),
        ("F17", UInt16(kVK_F17)),
        ("F18", UInt16(kVK_F18)),
    ]
}
