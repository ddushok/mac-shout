import Foundation
import AppKit
import Carbon

enum TextInsertionError: Error {
    case accessibilityPermissionDenied
    case insertionFailed
}

class TextInserter {
    static let shared = TextInserter()
    
    private init() {}
    
    // MARK: - Permission Check
    
    func hasAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // MARK: - Text Insertion
    
    func insertText(_ text: String) throws {
        guard hasAccessibilityPermission() else {
            throw TextInsertionError.accessibilityPermissionDenied
        }
        
        // Primary method: Simulated paste
        do {
            try insertViaSimulatedPaste(text)
        } catch {
            print("Simulated paste failed: \(error), trying direct typing")
            // Fallback: Direct typing (slower but more compatible)
            try insertViaTyping(text)
        }
    }
    
    // MARK: - Simulated Paste (Fast)
    
    private func insertViaSimulatedPaste(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        
        // Save current clipboard text (NSPasteboardItem objects become
        // invalid after clearContents, so we copy the actual string)
        let previousText = pasteboard.string(forType: .string)
        
        // Write new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Small delay to ensure clipboard is updated
        usleep(10_000) // 10ms
        
        // Simulate Cmd+V
        let success = simulateKeyPress(keyCode: 9, commandKey: true) // V key
        
        // Wait for paste to complete
        usleep(50_000) // 50ms
        
        // Restore previous clipboard contents
        if let previousText = previousText {
            pasteboard.clearContents()
            pasteboard.setString(previousText, forType: .string)
        }
        
        if !success {
            throw TextInsertionError.insertionFailed
        }
    }
    
    // MARK: - Direct Typing (Fallback)
    
    private func insertViaTyping(_ text: String) throws {
        // Type each character
        for char in text {
            guard let keyCode = characterToKeyCode(char) else {
                continue
            }
            
            let needsShift = char.isUppercase || "~!@#$%^&*()_+{}|:\"<>?".contains(char)
            simulateKeyPress(keyCode: keyCode, shiftKey: needsShift)
            
            // Small delay between keystrokes
            usleep(5_000) // 5ms
        }
    }
    
    // MARK: - Key Event Simulation
    
    @discardableResult
    private func simulateKeyPress(keyCode: CGKeyCode, commandKey: Bool = false, shiftKey: Bool = false, controlKey: Bool = false, optionKey: Bool = false) -> Bool {
        var flags: CGEventFlags = []
        
        if commandKey {
            flags.insert(.maskCommand)
        }
        if shiftKey {
            flags.insert(.maskShift)
        }
        if controlKey {
            flags.insert(.maskControl)
        }
        if optionKey {
            flags.insert(.maskAlternate)
        }
        
        // Create key down event
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            return false
        }
        keyDownEvent.flags = flags
        
        // Create key up event
        guard let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        keyUpEvent.flags = flags
        
        // Post events
        keyDownEvent.post(tap: .cghidEventTap)
        usleep(10_000) // 10ms between down and up
        keyUpEvent.post(tap: .cghidEventTap)
        
        return true
    }
    
    // MARK: - Character to Key Code Mapping
    
    private func characterToKeyCode(_ char: Character) -> CGKeyCode? {
        let lowercaseChar = char.lowercased().first ?? char
        
        switch lowercaseChar {
        // Letters
        case "a": return 0
        case "b": return 11
        case "c": return 8
        case "d": return 2
        case "e": return 14
        case "f": return 3
        case "g": return 5
        case "h": return 4
        case "i": return 34
        case "j": return 38
        case "k": return 40
        case "l": return 37
        case "m": return 46
        case "n": return 45
        case "o": return 31
        case "p": return 35
        case "q": return 12
        case "r": return 15
        case "s": return 1
        case "t": return 17
        case "u": return 32
        case "v": return 9
        case "w": return 13
        case "x": return 7
        case "y": return 16
        case "z": return 6
        
        // Numbers
        case "0": return 29
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        
        // Special characters (unshifted)
        case "-": return 27
        case "=": return 24
        case "[": return 33
        case "]": return 30
        case "\\": return 42
        case ";": return 41
        case "'": return 39
        case ",": return 43
        case ".": return 47
        case "/": return 44
        case "`": return 50
        
        // Whitespace
        case " ": return 49
        case "\n": return 36
        case "\t": return 48
        
        default:
            return nil
        }
    }
}

// MARK: - Convenience Extensions

extension TextInserter {
    func insertTextAsync(_ text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.insertText(text)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
