# Changelog

## Unreleased

- Redesigned settings around one selected side button at a time, pairing default and application-specific behavior with a dynamic vector mouse illustration, stable application selection, and live button detection guidance.
- Polished the settings layout with a slimmer integrated mouse illustration, collapsed System Access attention summary, and stable centered controls across mapping states and window widths.
- Reworked System Access into a compact disclosure card that starts collapsed, keeps an orange attention summary when unhealthy, and may expand automatically when a healthy session later needs attention while retaining user disclosure choices through unrelated rebuilds.
- Added a packaged MacMouseMapper mouse `.icns` icon and validated its Finder/Spotlight metadata during smoke packaging.
- First launch is now passive: the settings window appears before permission interaction, silently publishes Accessibility status, and waits for a user-initiated Request Access, Open Settings, or Repair Access action before active-tap/HID work.
- Trusted launches retain automatic HID diagnostics and capture startup; explicit grant flows still monitor the user action and perform exactly one clean packaged restart with visible settings.
- Clarified that a live tap with denied HID post access can capture and pass through physical events but cannot generate remapped actions; Repair Access and recovery guidance remain visible until HID access is granted.
- Replaced the stale Core Graphics permission model with one Accessibility / Device Control flow, operational active-tap proof, and an off-thread `IOHIDCheckAccess(kIOHIDRequestTypePostEvent)` diagnostic for generated actions.
- Added idempotent disabled/invalid tap recovery, conservative mapped-event pass-through when HID injection is unknown or denied, `.hidSystemState` injection sources, and one-time restart after an explicit untrusted-to-trusted grant transition.
- Added visible **Repair Access** for stale prior-build records. It resets only `Accessibility` for `com.macmousemapper.app`, launches the exact packaged bundle with a one-shot fresh-process AX prompt, then performs one clean post-grant restart without the repair argument and reopens the settings window. It reports failures and preserves saved configuration.
- Build output now prefers an installed Apple Development or Developer ID identity, otherwise clearly labels ad-hoc TCC identity risk and prints the resulting designated requirement. The settings UI identifies the same risk.
- Updated behavior-focused permission/restart tests, packaged metadata, README guidance, and launch diagnostics; removed obsolete listen/post-preflight controls and documentation.

## 1.0.0 — 2026-10-12

- Added the native menu-bar MacMouseMapper application with a stable app bundle identifier and `LSUIElement` packaging.
- Added Quartz global side-button capture for conventional mouse buttons 4 and 5, including recursion protection and coherent mouse down/up handling.
- Added deterministic global and per-application mapping resolution for keyboard shortcuts, mouse buttons, and public-API pixel-scroll gesture choices.
- Added Codable versioned persistence with safe defaults and invalid-setting sanitization.
- Added Accessibility permission status/recovery UI, a focused keyboard shortcut recorder with modifier controls, application bundle selection, and focused core behavior tests.
- Rechecked Accessibility and resumed capture when the accessory app becomes active after permission changes.
- Expanded the controlled key catalog through punctuation, navigation/editing, F1–F20, keypad, and volume controls; the UI now exposes all validated mouse buttons 0–15.
- Clarified that **Enable remapping** disables both global and application-specific mapping resolution.
