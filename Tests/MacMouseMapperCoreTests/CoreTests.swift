import Foundation
import MacMouseMapperCore

private struct TestRunner {
    private var failures = 0
    private var checks = 0

    mutating func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() {
            failures += 1
            fputs("FAIL: \(message)\n", stderr)
        }
    }

    mutating func run() {
        mappingResolverTests()
        pressTrackerTests()
        keyCatalogTests()
        permissionStateTests()
        persistenceTests()
        print("MacMouseMapperCoreTests: \(checks) checks, \(failures) failures")
        if failures != 0 {
            exit(1)
        }
    }

    private mutating func mappingResolverTests() {
        let global = ButtonMapping(action: .keyboard(KeyboardShortcut(keyCode: 0)))
        let app = ButtonMapping(action: .mouse(MouseButton(number: 2)))
        let configuration = AppConfiguration(
            globalMappings: ButtonMappings(button4: global),
            appOverrides: [AppOverride(bundleIdentifier: "com.example.Editor", displayName: "Editor", mappings: ButtonMappings(button4: app))]
        )
        let resolver = MappingResolver(configuration: configuration)
        expect(resolver.resolve(button: .button4, activeBundleIdentifier: "com.example.Editor") == app, "enabled app override takes precedence")

        let disabledOverride = ButtonMapping(action: .mouse(MouseButton(number: 1)), isEnabled: false)
        let fallbackConfiguration = AppConfiguration(
            globalMappings: ButtonMappings(button5: global),
            appOverrides: [AppOverride(bundleIdentifier: "com.example.Terminal", displayName: "Terminal", mappings: ButtonMappings(button5: disabledOverride))]
        )
        let fallbackResolver = MappingResolver(configuration: fallbackConfiguration)
        expect(fallbackResolver.resolve(button: .button5, activeBundleIdentifier: "com.example.Terminal") == global, "disabled override falls through to global")
        expect(fallbackResolver.resolve(button: .button4, activeBundleIdentifier: nil) == nil, "missing optional mapping passes through")

        let disabled = AppConfiguration(isEnabled: false, globalMappings: ButtonMappings(button4: global))
        expect(MappingResolver(configuration: disabled).resolve(button: .button4, activeBundleIdentifier: nil) == nil, "disabled capture passes through")
    }

    private mutating func pressTrackerTests() {
        let keyboard = ButtonMapping(action: .keyboard(KeyboardShortcut(keyCode: 0)))
        var tracker = PressTracker()
        let first = tracker.handle(button: .button4, phase: .down, resolvedMapping: keyboard)
        expect(first == .execute(keyboard, phase: .down), "first physical down executes")
        expect(tracker.handle(button: .button4, phase: .down, resolvedMapping: keyboard) == .suppress, "repeated down is suppressed without a second action")
        expect(tracker.handle(button: .button4, phase: .up, resolvedMapping: nil) == .execute(keyboard, phase: .up), "release uses captured mapping")
        expect(tracker.handle(button: .button4, phase: .up, resolvedMapping: keyboard) == .passThrough, "unmatched release passes through")

        let mouse = ButtonMapping(action: .mouse(MouseButton(number: 0)))
        var mouseTracker = PressTracker()
        expect(mouseTracker.handle(button: .button5, phase: .down, resolvedMapping: mouse) == .execute(mouse, phase: .down), "mouse down is generated")
        expect(mouseTracker.handle(button: .button5, phase: .up, resolvedMapping: nil) == .execute(mouse, phase: .up), "mouse up remains coherent")
        expect(mouseTracker.activePressCount == 0, "press state is released")

        expect(SideButton(quartzButtonNumber: 3) == .button4, "Quartz 3 is conventional button 4")
        expect(SideButton(quartzButtonNumber: 4) == .button5, "Quartz 4 is conventional button 5")
        expect(SideButton(quartzButtonNumber: 2) == nil, "unhandled mouse button is ignored")
    }
    private mutating func keyCatalogTests() {
        expect(KeyboardShortcut(keyCode: 0x2F).isValid, "period punctuation key is valid")
        expect(KeyCatalog.entry(for: 0x2A)?.name == "Backslash", "backslash punctuation has a clear name")
        expect(KeyboardShortcut(keyCode: 0x74).isValid, "page-up navigation key is valid")
        expect(KeyCatalog.entry(for: 0x7B)?.name == "Left Arrow", "navigation key has a clear name")
        expect(KeyboardShortcut(keyCode: 0x52).isValid, "keypad zero is valid")
        expect(KeyCatalog.entry(for: 0x4B)?.name == "Keypad Divide", "keypad operator has a clear name")
        expect(KeyboardShortcut(keyCode: 0x6A).isValid, "F16 is valid")
        expect(KeyboardShortcut(keyCode: 0x5A).isValid, "F20 is valid")
        expect(KeyCatalog.entry(for: 0x37) == nil, "Command virtual key remains a modifier")
        expect(KeyCatalog.entry(for: 0x3F) == nil, "fn virtual key remains a modifier")
        let eventFlags = (UInt(1) << 20) | (UInt(1) << 19) | (UInt(1) << 18) | (UInt(1) << 16)
        let convertedModifiers = ModifierMask(eventModifierRawValue: eventFlags)
        expect(convertedModifiers == [.command, .option, .control], "event modifier bits convert to persisted modifiers")
        let captured = KeyboardShortcut(capturedKeyCode: 0x2F, eventModifierRawValue: (UInt(1) << 17) | (UInt(1) << 23))
        expect(captured?.modifiers == [.shift, .function], "captured key preserves shift and fn modifiers")
        expect(KeyboardShortcut(capturedKeyCode: 0x37, eventModifierRawValue: 0) == nil, "modifier-only key events are rejected")
        expect(KeyboardShortcut(capturedKeyCode: 0xFFFF, eventModifierRawValue: 0) == nil, "unsupported captured keys are rejected")
        let unknownModifier = ModifierMask(rawValue: 1 << 5)
        expect(unknownModifier.isValid == false, "unknown modifier bits are invalid")
        expect(KeyboardShortcut(keyCode: 0, modifiers: unknownModifier).isValid == false, "unknown modifier combination is invalid")
        expect(MouseButton(number: 15).isValid, "highest supported mouse button is valid")
    }


    private mutating func permissionStateTests() {
        let missing = PermissionSnapshot(
            accessibilityTrusted: false,
            hidPostEventAccess: .unknown
        )
        expect(!missing.hasActiveEventTapAccess, "missing AX trust cannot authorize the active filtering tap")
        expect(missing.hidPostEventAccess == .unknown, "unknown HID state remains observable")
        expect(!missing.hasHIDPostEventAccess, "unknown HID state is not reported as granted")
        expect(!missing.isHIDPostEventAccessDenied, "unknown HID state is not reported as denied")

        let axOnly = PermissionSnapshot(
            accessibilityTrusted: true,
            hidPostEventAccess: .unknown
        )
        expect(axOnly.hasActiveEventTapAccess, "AX trust authorizes an active tap attempt without a stale HID preflight")
        expect(axOnly.hidPostEventAccess == .unknown, "AX trust does not imply HID authorization")

        let denied = PermissionSnapshot(
            accessibilityTrusted: true,
            hidPostEventAccess: .denied
        )
        expect(denied.hasActiveEventTapAccess, "known HID denial does not block capture")
        expect(denied.isHIDPostEventAccessDenied, "known HID denial is observable for suppression policy")
        expect(!denied.hasHIDPostEventAccess, "known HID denial is not injection authorization")

        let granted = PermissionSnapshot(
            accessibilityTrusted: true,
            hidPostEventAccess: .granted
        )
        expect(granted.hasActiveEventTapAccess, "AX trust remains the active filtering gate")
        expect(granted.hasHIDPostEventAccess, "granted HID check authorizes generated actions")

        let hidOnly = PermissionSnapshot(
            accessibilityTrusted: false,
            hidPostEventAccess: .granted
        )
        expect(!hidOnly.hasActiveEventTapAccess, "HID post access alone cannot authorize active filtering")
        expect(hidOnly.hasHIDPostEventAccess, "granted HID access remains independently observable")

        var policy = AuthorizationRestartPolicy()
        policy.beginExplicitGrant(currentlyTrusted: false)
        expect(policy.isAwaitingGrant, "an explicit flow records an initially untrusted process")
        expect(!policy.observe(accessibilityTrusted: false), "untrusted polling does not restart")
        expect(policy.observe(accessibilityTrusted: true), "the first grant transition requests one restart")
        expect(policy.restartConsumed, "the restart transition is consumed")
        expect(!policy.observe(accessibilityTrusted: true), "a grant transition cannot restart twice")

        var alreadyTrusted = AuthorizationRestartPolicy()
        alreadyTrusted.beginExplicitGrant(currentlyTrusted: true)
        expect(!alreadyTrusted.isAwaitingGrant, "a launch that starts trusted does not arm a restart")
        expect(!alreadyTrusted.observe(accessibilityTrusted: true), "background trusted state does not restart")
        var backgroundPoll = AuthorizationRestartPolicy()
        expect(!backgroundPoll.observe(accessibilityTrusted: true), "background polling alone never requests a restart")

        var repairPolicy = AuthorizationRestartPolicy(launchedForRepair: true)
        expect(!repairPolicy.restartConsumed, "repair-launched process leaves its restart available for the grant")
        repairPolicy.beginExplicitGrant(currentlyTrusted: false)
        expect(repairPolicy.isAwaitingGrant, "repair-launched process arms the explicit grant transition")
        expect(!repairPolicy.observe(accessibilityTrusted: false), "repair remains waiting while AX is untrusted")
        expect(repairPolicy.observe(accessibilityTrusted: true), "repair grant transition requests one clean restart")
        expect(repairPolicy.restartConsumed, "repair consumes its one restart after the grant")
        expect(!repairPolicy.observe(accessibilityTrusted: true), "repair cannot restart again after the clean launch")
    }

    private mutating func persistenceTests() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacMouseMapperTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("configuration.json")
        let store = ConfigurationStore(fileURL: url)
        defer { try? FileManager.default.removeItem(at: directory) }

        expect(store.load() == .default, "missing configuration uses defaults")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: url)
            expect(store.load() == .default, "corrupt configuration uses defaults")

            let configuration = AppConfiguration(
                globalMappings: ButtonMappings(button4: ButtonMapping(action: .keyboard(KeyboardShortcut(keyCode: 12, modifiers: [.command, .shift])))),
                appOverrides: [AppOverride(bundleIdentifier: "com.example.Reader", displayName: "Reader")]
            )
            try store.save(configuration)
            expect(store.load() == configuration, "save/load preserves versioned configuration")

            let invalid = AppConfiguration(
                globalMappings: ButtonMappings(
                    button4: ButtonMapping(action: .keyboard(KeyboardShortcut(keyCode: 999))),
                    button5: ButtonMapping(action: .mouse(MouseButton(number: 99)))
                ),
                appOverrides: [
                    AppOverride(bundleIdentifier: "bad id", displayName: "Bad"),
                    AppOverride(bundleIdentifier: "com.example.Good", displayName: "")
                ]
            )
            try store.save(invalid)
            let sanitized = store.load()
            expect(sanitized.globalMappings.button4 == nil, "invalid keyboard mapping is dropped")
            expect(sanitized.globalMappings.button5 == nil, "invalid mouse mapping is dropped")
            expect(sanitized.appOverrides.map(\.bundleIdentifier) == ["com.example.Good"], "invalid app identity is dropped")
            expect(sanitized.appOverrides.first?.displayName == "com.example.Good", "empty display name falls back to identity")

            let unsupported = try JSONEncoder().encode(PersistedConfiguration(version: 999, configuration: configuration))
            try unsupported.write(to: url)
            expect(store.load() == .default, "unsupported schema version uses defaults")
        } catch {
            failures += 1
            fputs("FAIL: persistence test threw \(error)\n", stderr)
        }
    }
}

@main
private enum Main {
    static func main() {
        var runner = TestRunner()
        runner.run()
    }
}
