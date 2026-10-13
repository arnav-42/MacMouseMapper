# MacMouseMapper

MacMouseMapper is a native macOS menu-bar utility for remapping mouse side buttons 4 and 5. It uses AppKit and the public Quartz event-tap/event-injection APIs; it has no network access, analytics, Electron, or third-party runtime dependencies. The one-second AX/active-tap retry monitor starts only after an explicit access flow or when Accessibility is already trusted and capture remains unresolved; an untrusted normal launch stays passive.

## Requirements

- Accessibility / Device Control trust for the exact packaged application (required by the active `.defaultTap` filter, which suppresses/replaces mapped side-button events)
- HID post-event access is checked with `IOHIDCheckAccess(kIOHIDRequestTypePostEvent)` for generated actions; this is a runtime diagnostic, not a second user-facing permission flow
- Swift 5.9 or newer when building from source

The repository contains a Swift Package and a deterministic app-bundle script, so Xcode is not required for the command-line build. The packaged bundle identifier is `com.macmousemapper.app` and its `LSUIElement` flag keeps it out of the Dock.

## Build and launch

The primary developer command is:

```sh
./scripts/restart_app.sh
```

It gracefully closes exact `MacMouseMapper` processes, waits for them to exit, builds the current package, and launches this repository's canonical `build/MacMouseMapper.app` as a new process. It then sends a normal reopen request so the settings window is brought forward. The command prints the verified executable path and bundle version, and leaves that newly launched app running.

To build the app bundle without launching it:

```sh
./scripts/build_app.sh
```

The running packaged app shows `Version 1.3.0 (4)` in the settings footer, read from its bundle metadata. Use that footer to confirm that the current bundle is running. A SwiftPM direct execution has no packaged metadata and shows `Development build`; it cannot repair the packaged app's TCC record.

The build script prefers an available Apple Development or Developer ID identity and prints the resulting designated requirement. If no identity is installed, it signs ad hoc and labels the app accordingly: each rebuild can receive a new TCC identity even though the bundle identifier is unchanged. Use **Repair Access** in the current packaged app to reset only this app's Accessibility record and re-register the exact current executable.

The status item (computer-mouse icon) opens the configuration window. A normal double-click also brings the settings window forward immediately, before any permission interaction. The settings surface uses native AppKit visual-effect cards, semantic colors, SF Symbols, and a centered responsive column that remains scrollable at the minimum window size. Closing the window leaves the menu-bar utility running; a normal reopen request brings the settings window forward again.

For a repeatable launch smoke check that only terminates the process it launched:

```sh
./scripts/smoke_app.sh
```

To exercise the real settings window at minimum, default, and wide sizes:

```sh
./scripts/ui_smoke_app.sh
```

## System permissions

On first launch, MacMouseMapper silently reads Accessibility status and shows the **System Access** card before doing any permission work. The card exposes one user-facing capability: **Accessibility / Device Control** for the exact packaged app. Click **Request Access** to start the explicit flow; only then does the app call `AXIsProcessTrustedWithOptions(prompt: true)` for the current process and open Privacy & Security → Accessibility (`Privacy_Accessibility`) when access is not immediately trusted. **Open Settings** and **Repair Access** are also explicit user actions that may arm monitoring; simply launching the app does not create an active tap, run the HID post-access check, open System Settings, or request a prompt.

After an explicit flow starts, AX and active-tap status retry once per second while capture is unresolved or the grant remains pending. If Accessibility was already trusted at launch, the app automatically performs the HID post check and starts capture without a button click. The HID post check is performed off-thread rather than by every retry tick.

Capture readiness is operational: a successfully created and enabled `.defaultTap` reports **Capture: Running**, even if an old Core Graphics preflight value disagrees. HID post readiness is checked off the event-tap thread with `IOHIDCheckAccess(kIOHIDRequestTypePostEvent)` for generated actions. It is shown as a diagnostic, not as a separate button or user-facing gate. If that check is unknown or denied, physical mapped buttons pass through rather than being swallowed; a running tap with denied HID access is capture-capable but cannot perform generated remapping actions.

When an explicit request flow observes the transition from untrusted to trusted, the packaged app automatically restarts the exact current bundle once and reopens its settings window, preserving the saved configuration. A process that launched already trusted does not restart, and background status reads never trigger a restart.

If System Settings already shows this app enabled but the current executable remains untrusted or its tap cannot be created, click **Repair Access**. Repair runs only `tccutil reset Accessibility com.macmousemapper.app`, launches the exact current packaged bundle with a one-shot fresh-process prompt argument, and terminates the old process only after the relaunch command succeeds. After the fresh process observes the grant transition, it performs the same single clean restart without the repair argument and reopens this app's settings window. Failures are shown in the card. Repair is unavailable from direct SwiftPM execution because it cannot safely identify the packaged bundle.

For troubleshooting, confirm the footer says `Version 1.3.0 (4)`, then click a physical side button and check **Last side button**. A changed last-button value proves the event tap is receiving a side-button event; an unchanged value means the mouse or macOS is not delivering the expected Quartz side-button event. Conventional side buttons remain Quartz buttons 3 and 4 (user-facing buttons 4 and 5).

## Configure mappings

Each side-button row has an independent optional mapping:

- **Pass through** clears the mapping and leaves the physical event unchanged.
- **Keyboard shortcut** uses a focused native recorder and independent Command, Option, Control, Shift, and fn modifiers. Click the key button, press a supported physical key, and the exact key code plus held modifiers are captured. Clicking again or moving focus away cancels and restores the prior label. Modifier-only or unknown key combinations are rejected rather than silently saved.
- **Another mouse button** emits a coherent down/up pair for the selected Quartz mouse-button number.
- **Gesture** emits a short burst of smooth pixel-scroll events in the selected direction. The UI deliberately calls these scroll/swipe-style events rather than pretending to create a physical trackpad gesture.

The **Enable remapping** switch disables all mapping resolution—including application overrides—while retaining the saved mappings.

### Application overrides

Click **Add Application...** and choose an `.app` bundle. MacMouseMapper stores its bundle identifier and a useful display name, not a fragile path. Each override has independent optional mappings for buttons 4 and 5. For the active application, resolution is deterministic:

1. enabled override mapping for the active bundle identifier;
2. otherwise enabled global mapping;
3. otherwise pass the source event through unchanged.

A disabled or absent override mapping therefore falls back to the global mapping. The active application is tracked through `NSWorkspace.didActivateApplicationNotification`; MacMouseMapper does not poll the foreground application.

## Persistence

Configuration is stored as versioned, pretty-printed JSON at:

`~/Library/Application Support/MacMouseMapper/configuration.json`

The loader safely returns defaults for missing, corrupt, unsupported-version, or invalid data. Invalid individual mappings and app identities are dropped while valid settings are retained. Writes create the directory and use an atomic replacement.

## Development checks

Build the executable:

```sh
swift build --product MacMouseMapper
```

Run the behavior suite (it is a small executable because the installed Command Line Tools do not ship the XCTest module):

```sh
swift run MacMouseMapperCoreTests
```

The suite exercises the AX-only capture readiness policy, tri-state HID injection policy, one-time explicit-grant restart state, precedence and optional fallthrough, Quartz side-button numbering, once-per-press/down-up invariants, physical-key modifier conversion and capture validation, persistence corruption/default behavior, schema-version fallback, and invalid-setting sanitization. After implementation is complete, run `./scripts/smoke_app.sh` and `./scripts/ui_smoke_app.sh` to validate packaged resources, launch/reopen behavior, and resize-safe settings layout.

## Public API limitations

Quartz can create keyboard, mouse, and pixel-scroll events, but macOS does not expose a public API for synthetic multi-touch contacts. Consequently gesture mappings cannot honestly implement Mission Control, pinch, or arbitrary three-finger gestures. “Swipe” choices are smooth pixel-scroll bursts that applications may interpret as horizontal or vertical swipes; behavior depends on the receiving application. No private framework is used to bypass this limitation.

Global active filtering/injection starts automatically only when Accessibility is already trusted or after the user begins an explicit access flow; a live enabled active tap is the capture proof. Accessibility / Device Control is the only user-facing permission flow. Generated keyboard, mouse, and scroll events use a `.hidSystemState` source and post at `.cghidEventTap`, with a private Quartz source marker ignored by the tap to prevent recursive remapping. When a mapping is absent, disabled, or not safely injectable, the original physical event is returned unchanged.
