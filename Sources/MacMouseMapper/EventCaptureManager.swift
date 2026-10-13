import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hid
import MacMouseMapperCore

enum CaptureStatus: Equatable {
    case waitingForPermissions
    case running
    case tapUnavailable
}

/// Owns the single global active event tap and its run-loop source.
///
/// The active tap is the operational capture proof. AX is the user-facing
/// device-control signal, while the off-thread HID post check only controls
/// whether a mapped physical event may be suppressed and replaced.
final class EventCaptureManager {
    var onPermissionSnapshotChanged: ((PermissionSnapshot) -> Void)?
    var onCaptureStatusChanged: ((CaptureStatus) -> Void)?
    var onSideButtonDetected: ((SideButton) -> Void)?
    var onAuthorizationGranted: (() -> Void)?

    private let lock = NSLock()
    private let injector = ActionInjector()
    private let hidAccessQueue = DispatchQueue(
        label: "com.macmousemapper.hid-access-check",
        qos: .utility
    )
    private var resolver: MappingResolver
    private var pressTracker = PressTracker()
    private var activeBundleIdentifier: String?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workspaceObserver: NSObjectProtocol?
    private var permissionMonitor: DispatchSourceTimer?
    private var lastPermissionSnapshot: PermissionSnapshot?
    private var lastCaptureStatus: CaptureStatus?
    private var hidPostEventAccess: HIDPostEventAccess = .unknown
    private var hidAccessCheckInFlight = false
    private var authorizationRestartPolicy: AuthorizationRestartPolicy
    private var explicitGrantFlowActive = false
    private var isRunning = false

    init(configuration: AppConfiguration, launchedForRepair: Bool = false) {
        resolver = MappingResolver(configuration: configuration)
        activeBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        authorizationRestartPolicy = AuthorizationRestartPolicy(launchedForRepair: launchedForRepair)
    }

    deinit {
        stop()
    }

    func update(configuration: AppConfiguration) {
        lock.lock()
        resolver = MappingResolver(configuration: configuration)
        lock.unlock()
    }

    /// Requests Accessibility/device-control access for this exact process.
    ///
    /// A failed immediate result is expected when the user must enable the
    /// packaged app in System Settings. The caller opens the Accessibility
    /// pane, while the explicit flow's monitor observes a later grant.
    @discardableResult
    func requestAccessibilityAccess() -> Bool {
        let wasTrusted = AXIsProcessTrusted()
        if !wasTrusted {
            authorizationRestartPolicy.beginExplicitGrant(currentlyTrusted: false)
            explicitGrantFlowActive = authorizationRestartPolicy.isAwaitingGrant
        }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        refreshPermissionsAndStartIfPossible()
        return trusted
    }

    /// Registers a fresh packaged process before its repair flow opens
    /// System Settings. The repair process keeps its one-shot restart
    /// available until the explicit false-to-true grant transition is
    /// observed.
    @discardableResult
    func registerFreshProcessForRepair() -> Bool {
        requestAccessibilityAccess()
    }

    /// Called after the Accessibility pane is opened. This is an explicit
    /// flow, unlike background watchdog checks, so a newly observed grant can
    /// consume the one-time restart policy.
    func accessibilitySettingsOpened() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            authorizationRestartPolicy.beginExplicitGrant(currentlyTrusted: false)
            explicitGrantFlowActive = authorizationRestartPolicy.isAwaitingGrant
        }
        refreshPermissionsAndStartIfPossible()
        schedulePermissionMonitorIfNeeded()
    }

    /// Rechecks AX and the cached HID access result, then attempts the active
    /// tap only after Accessibility is trusted. An untrusted normal launch
    /// publishes its silent status and remains passive until an explicit
    /// request or settings/repair flow arms monitoring.
    func refreshPermissionsAndStartIfPossible() {
        refreshPermissionsAndStartIfPossible(checkHIDAccess: true)
    }

    /// Public lifecycle entry point. Normal startup is deliberately passive
    /// when Accessibility is not already trusted.
    func start() {
        refreshPermissionsAndStartIfPossible()
    }

    /// Stops all capture resources and the unresolved monitor. PressTracker is
    /// retained so a later up event can release a generated action if trust is
    /// revoked during a physical mapped press.
    func stop() {
        cancelPermissionMonitor()
        removeCaptureResources()
        let snapshot = readPermissionSnapshot()
        publishPermissionSnapshot(snapshot)
        notifyCapture(captureStatus(for: snapshot))
    }


    private func refreshPermissionsAndStartIfPossible(checkHIDAccess: Bool) {
        let snapshot = readPermissionSnapshot()
        publishPermissionSnapshot(snapshot)
        observeExplicitGrant(snapshot)

        guard snapshot.accessibilityTrusted else {
            // A normal untrusted launch is intentionally passive. Do not
            // perform HID TCC IPC, create an active tap, or keep a retry
            // timer alive until the user starts an explicit access flow.
            if isRunning || eventTap != nil || runLoopSource != nil {
                removeCaptureResources()
            }
            notifyCapture(.waitingForPermissions)
            if explicitGrantFlowActive {
                if checkHIDAccess {
                    requestHIDPostEventAccessCheckIfNeeded()
                }
                schedulePermissionMonitorIfNeeded()
            } else {
                cancelPermissionMonitor()
            }
            return
        }

        if checkHIDAccess {
            requestHIDPostEventAccessCheckIfNeeded()
        }
        if isRunning {
            verifyRunningTap(using: snapshot)
        } else {
            startCaptureIfPossible(using: snapshot)
        }

        if explicitGrantFlowActive {
            schedulePermissionMonitorIfNeeded()
        }
    }

    private func readPermissionSnapshot() -> PermissionSnapshot {
        let hidAccess: HIDPostEventAccess
        lock.lock()
        hidAccess = hidPostEventAccess
        lock.unlock()
        return PermissionSnapshot(
            accessibilityTrusted: AXIsProcessTrusted(),
            hidPostEventAccess: hidAccess
        )
    }

    private func requestHIDPostEventAccessCheckIfNeeded() {
        lock.lock()
        guard !hidAccessCheckInFlight else {
            lock.unlock()
            return
        }
        hidAccessCheckInFlight = true
        lock.unlock()

        hidAccessQueue.async { [weak self] in
            let access = IOHIDCheckAccess(kIOHIDRequestTypePostEvent)
            let state: HIDPostEventAccess
            switch access {
            case kIOHIDAccessTypeGranted:
                state = .granted
            case kIOHIDAccessTypeDenied:
                state = .denied
            default:
                state = .unknown
            }
            DispatchQueue.main.async {
                self?.applyHIDPostEventAccess(state)
            }
        }
    }

    private func applyHIDPostEventAccess(_ access: HIDPostEventAccess) {
        lock.lock()
        let changed = hidPostEventAccess != access
        hidPostEventAccess = access
        hidAccessCheckInFlight = false
        lock.unlock()
        guard changed else { return }
        refreshPermissionsAndStartIfPossible(checkHIDAccess: false)
    }

    private func observeExplicitGrant(_ snapshot: PermissionSnapshot) {
        guard explicitGrantFlowActive else { return }
        if authorizationRestartPolicy.observe(accessibilityTrusted: snapshot.accessibilityTrusted) {
            explicitGrantFlowActive = false
            cancelPermissionMonitor()
            DispatchQueue.main.async { [weak self] in
                self?.onAuthorizationGranted?()
            }
        } else if !authorizationRestartPolicy.isAwaitingGrant {
            explicitGrantFlowActive = false
        }
    }

    private func startCaptureIfPossible(using snapshot: PermissionSnapshot) {
        guard snapshot.accessibilityTrusted else {
            removeCaptureResources()
            notifyCapture(.waitingForPermissions)
            schedulePermissionMonitorIfNeeded()
            return
        }

        if let tap = eventTap,
           let source = runLoopSource,
           CFMachPortIsValid(tap) {
            _ = source
            CGEvent.tapEnable(tap: tap, enable: true)
            guard CGEvent.tapIsEnabled(tap: tap) else {
                removeCaptureResources()
                notifyCapture(.tapUnavailable)
                schedulePermissionMonitorIfNeeded()
                return
            }
            isRunning = true
            installWorkspaceObserver()
            notifyCapture(.running)
            schedulePermissionMonitorIfNeeded()
            return
        }

        // A previous partial or invalid attempt must never leave a source,
        // tap, or observer around for the next attempt.
        removeCaptureResources()
        lock.lock()
        activeBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        lock.unlock()

        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: context
        ) else {
            notifyCapture(captureStatus(for: snapshot))
            schedulePermissionMonitorIfNeeded()
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            notifyCapture(.tapUnavailable)
            schedulePermissionMonitorIfNeeded()
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            removeCaptureResources()
            notifyCapture(.tapUnavailable)
            schedulePermissionMonitorIfNeeded()
            return
        }

        installWorkspaceObserver()
        isRunning = true
        notifyCapture(.running)
        schedulePermissionMonitorIfNeeded()
    }

    private func verifyRunningTap(using snapshot: PermissionSnapshot) {
        guard snapshot.accessibilityTrusted else {
            removeCaptureResources()
            notifyCapture(.waitingForPermissions)
            schedulePermissionMonitorIfNeeded()
            return
        }

        guard let tap = eventTap,
              let source = runLoopSource,
              CFMachPortIsValid(tap) else {
            removeCaptureResources()
            notifyCapture(captureStatus(for: snapshot))
            schedulePermissionMonitorIfNeeded()
            startCaptureIfPossible(using: snapshot)
            return
        }
        _ = source
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            removeCaptureResources()
            notifyCapture(.tapUnavailable)
            schedulePermissionMonitorIfNeeded()
            startCaptureIfPossible(using: snapshot)
            return
        }
        isRunning = true
        notifyCapture(.running)
        schedulePermissionMonitorIfNeeded()
    }

    private func captureStatus(for snapshot: PermissionSnapshot) -> CaptureStatus {
        snapshot.accessibilityTrusted ? .tapUnavailable : .waitingForPermissions
    }

    private func schedulePermissionMonitorIfNeeded() {
        guard !isRunning || explicitGrantFlowActive else {
            cancelPermissionMonitor()
            return
        }
        guard permissionMonitor == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .seconds(1),
            repeating: .seconds(1),
            leeway: .milliseconds(250)
        )
        timer.setEventHandler { [weak self] in
            self?.checkPermissionsFromMonitor()
        }
        permissionMonitor = timer
        timer.resume()
    }

    private func cancelPermissionMonitor() {
        guard let monitor = permissionMonitor else { return }
        monitor.setEventHandler {}
        monitor.cancel()
        permissionMonitor = nil
    }

    private func checkPermissionsFromMonitor() {
        // The one-second retry reads AX and retries the tap, but deliberately
        // does not invoke potentially blocking HID TCC IPC on every tick.
        refreshPermissionsAndStartIfPossible(checkHIDAccess: false)
    }
    private func removeCaptureResources() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        isRunning = false
    }

    private func installWorkspaceObserver() {
        guard workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.lock.lock()
            self.activeBundleIdentifier = app?.bundleIdentifier
            self.lock.unlock()
        }
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            let snapshot = readPermissionSnapshot()
            publishPermissionSnapshot(snapshot)
            guard let eventTap, CFMachPortIsValid(eventTap) else {
                removeCaptureResources()
                notifyCapture(captureStatus(for: snapshot))
                schedulePermissionMonitorIfNeeded()
                DispatchQueue.main.async { [weak self] in
                    self?.refreshPermissionsAndStartIfPossible()
                }
                return Unmanaged.passUnretained(event)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            if CGEvent.tapIsEnabled(tap: eventTap) {
                isRunning = true
                notifyCapture(.running)
                schedulePermissionMonitorIfNeeded()
            } else {
                removeCaptureResources()
                notifyCapture(.tapUnavailable)
                schedulePermissionMonitorIfNeeded()
                DispatchQueue.main.async { [weak self] in
                    self?.refreshPermissionsAndStartIfPossible()
                }
            }
            return Unmanaged.passUnretained(event)
        case .otherMouseDown, .otherMouseUp:
            let snapshot = readPermissionSnapshot()
            publishPermissionSnapshot(snapshot)
            if snapshot.hidPostEventAccess != .granted {
                // Unknown is not authorization, and known denial cannot be
                // replaced by the injector. Preserve the physical event in
                // both states until the off-thread check is explicitly
                // granted.
                lock.lock()
                pressTracker = PressTracker()
                lock.unlock()
                return Unmanaged.passUnretained(event)
            }
        default:
            return Unmanaged.passUnretained(event)
        }

        // Generated mouse down/up events carry the marker and must never be
        // fed back through PressTracker.
        if event.getIntegerValueField(.eventSourceUserData) == ActionInjector.generatedEventMarker {
            return Unmanaged.passUnretained(event)
        }

        let rawButton = event.getIntegerValueField(.mouseEventButtonNumber)
        guard rawButton >= 0, let sideButton = SideButton(quartzButtonNumber: UInt32(rawButton)) else {
            return Unmanaged.passUnretained(event)
        }
        if type == .otherMouseDown {
            notifySideButton(sideButton)
        }
        let phase: PressPhase = type == .otherMouseDown ? .down : .up

        lock.lock()
        let mapping = resolver.resolve(button: sideButton, activeBundleIdentifier: activeBundleIdentifier)
        let result = pressTracker.handle(button: sideButton, phase: phase, resolvedMapping: mapping)
        lock.unlock()

        switch result {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .suppress:
            return nil
        case .execute(let action, let actionPhase):
            injector.perform(mapping: action, phase: actionPhase, sourceEvent: event)
            return nil
        }
    }

    private func publishPermissionSnapshot(_ snapshot: PermissionSnapshot) {
        guard lastPermissionSnapshot != snapshot else { return }
        lastPermissionSnapshot = snapshot
        DispatchQueue.main.async { [weak self] in
            self?.onPermissionSnapshotChanged?(snapshot)
        }
    }

    private func notifyCapture(_ status: CaptureStatus) {
        guard lastCaptureStatus != status else { return }
        lastCaptureStatus = status
        DispatchQueue.main.async { [weak self] in
            self?.onCaptureStatusChanged?(status)
        }
    }

    private func notifySideButton(_ button: SideButton) {
        DispatchQueue.main.async { [weak self] in
            self?.onSideButtonDetected?(button)
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let manager = Unmanaged<EventCaptureManager>.fromOpaque(userInfo).takeUnretainedValue()
        return manager.handle(proxy: proxy, type: type, event: event)
    }
}
