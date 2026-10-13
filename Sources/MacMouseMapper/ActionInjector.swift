import AppKit
import CoreGraphics
import MacMouseMapperCore

/// Posts keyboard, mouse, and pixel-scroll events for resolved mappings. Every
/// generated event carries a private source marker so the input tap cannot
/// recursively remap its own output.
final class ActionInjector {
    static let generatedEventMarker: Int64 = 0x4D4D_4D41_4354_494F

    private let eventSource: CGEventSource?

    init() {
        eventSource = CGEventSource(stateID: .hidSystemState)
    }

    func perform(mapping: ButtonMapping, phase: PressPhase, sourceEvent: CGEvent) {
        guard mapping.isUsable else { return }
        switch mapping.action {
        case .keyboard(let shortcut):
            guard phase == .down, shortcut.isValid else { return }
            postKeyboard(shortcut)
        case .mouse(let button):
            guard button.isValid else { return }
            postMouse(button: button, phase: phase, location: sourceEvent.location)
        case .gesture(let gesture):
            guard phase == .down else { return }
            postGesture(gesture, location: sourceEvent.location)
        }
    }

    private func postKeyboard(_ shortcut: KeyboardShortcut) {
        guard let eventSource else { return }
        let flags = quartzFlags(for: shortcut.modifiers)
        guard let keyDown = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: shortcut.keyCode,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: shortcut.keyCode,
            keyDown: false
        ) else { return }

        keyDown.flags = flags
        keyUp.flags = flags
        mark(keyDown)
        mark(keyUp)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func postMouse(button: MouseButton, phase: PressPhase, location: CGPoint) {
        guard let eventSource else { return }
        let isDown = phase == .down
        guard let mouseButton = CGMouseButton(rawValue: button.number) else { return }
        let eventType: CGEventType
        switch (button.number, isDown) {
        case (0, true): eventType = .leftMouseDown
        case (0, false): eventType = .leftMouseUp
        case (1, true): eventType = .rightMouseDown
        case (1, false): eventType = .rightMouseUp
        case (_, true): eventType = .otherMouseDown
        case (_, false): eventType = .otherMouseUp
        }
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: eventType,
            mouseCursorPosition: location,
            mouseButton: mouseButton
        ) else { return }
        mark(event)
        event.post(tap: .cghidEventTap)
    }

    private func postGesture(_ gesture: GestureKind, location: CGPoint) {
        guard let eventSource else { return }
        let components = gesture.scrollComponents
        let count = gesture.isSwipe ? 12 : 8
        let step = gesture.isSwipe ? 28 : 12

        for _ in 0..<count {
            guard let event = CGEvent(
                scrollWheelEvent2Source: eventSource,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(components.vertical * step),
                wheel2: Int32(components.horizontal * step),
                wheel3: 0
            ) else { continue }
            event.location = location
            mark(event)
            event.post(tap: .cghidEventTap)
        }
    }

    private func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.generatedEventMarker)
    }

    private func quartzFlags(for modifiers: ModifierMask) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}

private extension GestureKind {
    var isSwipe: Bool {
        switch self {
        case .smoothSwipeUp, .smoothSwipeDown, .smoothSwipeLeft, .smoothSwipeRight:
            return true
        case .smoothScrollUp, .smoothScrollDown, .smoothScrollLeft, .smoothScrollRight:
            return false
        }
    }

    var scrollComponents: (vertical: Int, horizontal: Int) {
        switch self {
        case .smoothScrollUp, .smoothSwipeUp: return (1, 0)
        case .smoothScrollDown, .smoothSwipeDown: return (-1, 0)
        case .smoothScrollLeft, .smoothSwipeLeft: return (0, 1)
        case .smoothScrollRight, .smoothSwipeRight: return (0, -1)
        }
    }
}
