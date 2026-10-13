import AppKit
import MacMouseMapperCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let packagedBundleIdentifier = "com.macmousemapper.app"
    private static let repairAccessArgument = "--macmousemapper-repair-access"
    private static let showSettingsArgument = "--macmousemapper-show-settings"

    private let store = ConfigurationStore()
    private var configuration = AppConfiguration.default
    private var statusItem: NSStatusItem!
    private var windowController: NSWindowController!
    private var configurationViewController: ConfigurationViewController!
    private var eventCapture: EventCaptureManager!
    private var applicationLifecycleObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configuration = store.load()
        buildStatusItem()
        buildConfigurationWindow()

        let repairArgumentPresent = CommandLine.arguments.contains(Self.repairAccessArgument)
        let launchedForRepair = repairArgumentPresent && packagedBundleURL() != nil
        if repairArgumentPresent && !launchedForRepair {
            reportAccessFlow(
                "Repair Access arguments are honored only by build/MacMouseMapper.app; " +
                "this direct SwiftPM process cannot repair the packaged bundle."
            )
        }
        eventCapture = EventCaptureManager(
            configuration: configuration,
            launchedForRepair: launchedForRepair
        )
        eventCapture.onPermissionSnapshotChanged = { [weak self] snapshot in
            self?.configurationViewController.setPermissionSnapshot(snapshot)
        }
        eventCapture.onCaptureStatusChanged = { [weak self] status in
            self?.configurationViewController.setCaptureStatus(status)
        }
        eventCapture.onSideButtonDetected = { [weak self] button in
            self?.configurationViewController.setSideButtonDetected(button)
        }
        eventCapture.onAuthorizationGranted = { [weak self] in
            self?.restartAfterAuthorizationGrant()
        }
        // LSUIElement apps do not receive a normal Dock activation on a
        // double-click. Show the settings window before any explicit
        // permission interaction so an untrusted first launch is visible.
        showConfigurationWindow()

        if launchedForRepair {
            // AX registration must happen in this fresh process before the
            // pane is opened. Neither one-shot argument is propagated.
            let trusted = eventCapture.registerFreshProcessForRepair()
            if !trusted {
                openAccessibilitySettings()
            }
        }
        eventCapture.start()
        applicationLifecycleObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.eventCapture?.refreshPermissionsAndStartIfPossible()
        }

    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = applicationLifecycleObserver {
            NotificationCenter.default.removeObserver(observer)
            applicationLifecycleObserver = nil
        }
        eventCapture?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        eventCapture?.refreshPermissionsAndStartIfPossible()
        showConfigurationWindow()
        return true
    }

    @objc private func toggleConfigurationWindow(_ sender: Any?) {
        guard let window = windowController.window else { return }
        if window.isVisible {
            window.orderOut(nil)
            return
        }
        showConfigurationWindow()
    }

    private func showConfigurationWindow() {
        guard let window = windowController.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(toggleConfigurationWindow(_:))
        if let image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MacMouseMapper") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "MM"
        }
        button.toolTip = "MacMouseMapper"
    }

    private func buildConfigurationWindow() {
        configurationViewController = ConfigurationViewController(configuration: configuration)
        configurationViewController.onConfigurationChanged = { [weak self] updated in
            guard let self else { return }
            self.configuration = updated.sanitized()
            try? self.store.save(self.configuration)
            self.eventCapture?.update(configuration: self.configuration)
        }
        configurationViewController.onAccessibilityRequested = { [weak self] in
            guard let self, let eventCapture = self.eventCapture else { return }
            if !eventCapture.requestAccessibilityAccess() {
                self.openAccessibilitySettings()
            }
        }
        configurationViewController.onAccessibilitySettingsRequested = { [weak self] in
            self?.openAccessibilitySettings()
        }
        configurationViewController.onRepairAccessRequested = { [weak self] in
            self?.repairAccess()
        }
        configurationViewController.onQuit = { _ in
            NSApp.terminate(nil)
        }

        let window = NSWindow(contentViewController: configurationViewController)
        window.title = "MacMouseMapper"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 760, height: 720))
        window.center()
        window.minSize = NSSize(width: 620, height: 500)
        windowController = NSWindowController(window: window)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            reportAccessFlow("Unable to construct the Accessibility settings URL.")
            return
        }
        eventCapture?.accessibilitySettingsOpened()
        if !NSWorkspace.shared.open(url) {
            reportAccessFlow("Unable to open Privacy & Security → Accessibility.")
        }
    }

    private func restartAfterAuthorizationGrant() {
        guard let bundleURL = packagedBundleURL() else {
            reportAccessFlow(
                "Accessibility was granted, but automatic restart requires the packaged .app. " +
                "Run Repair Access from build/MacMouseMapper.app."
            )
            return
        }
        launchBundle(bundleURL, arguments: [Self.showSettingsArgument]) { [weak self] success, detail in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    NSApp.terminate(nil)
                } else {
                    self.reportAccessFlow("Automatic restart failed: \(detail)")
                }
            }
        }
    }

    private func repairAccess() {
        guard let bundleURL = packagedBundleURL(),
              let bundleIdentifier = Bundle.main.bundleIdentifier else {
            reportAccessFlow(
                "Repair Access is available only from the exact packaged " +
                "build/MacMouseMapper.app; SwiftPM execution cannot repair its bundle."
            )
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let resetResult = Self.runCommand(
                executable: "/usr/bin/tccutil",
                arguments: ["reset", "Accessibility", bundleIdentifier]
            )
            guard resetResult.success else {
                self?.reportAccessFlow("Repair Access failed to reset this app's record: \(resetResult.detail)")
                return
            }

            self?.launchBundle(
                bundleURL,
                arguments: [Self.repairAccessArgument]
            ) { [weak self] success, detail in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard success else {
                        self.reportAccessFlow("Repair Access relaunched the app unsuccessfully: \(detail)")
                        return
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func packagedBundleURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension.lowercased() == "app",
              Bundle.main.bundleIdentifier == Self.packagedBundleIdentifier,
              let executableURL = Bundle.main.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return nil
        }
        return bundleURL
    }

    private func launchBundle(
        _ bundleURL: URL,
        arguments: [String],
        completion: @escaping (Bool, String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            var openArguments = ["-n", bundleURL.path]
            if !arguments.isEmpty {
                openArguments += ["--args"] + arguments
            }
            let result = Self.runCommand(
                executable: "/usr/bin/open",
                arguments: openArguments
            )
            guard result.success else {
                completion(false, result.detail)
                return
            }
            guard Self.waitForNewPackagedProcess(at: bundleURL) else {
                completion(false, "the exact packaged process did not appear after open")
                return
            }
            completion(true, result.detail)
        }
    }

    private static func waitForNewPackagedProcess(at bundleURL: URL) -> Bool {
        let expectedPath = bundleURL.standardizedFileURL.path
        let currentPID = ProcessInfo.processInfo.processIdentifier
        for _ in 0..<40 {
            let launched = NSWorkspace.shared.runningApplications.contains { application in
                guard application.processIdentifier != currentPID,
                      let runningBundleURL = application.bundleURL else {
                    return false
                }
                return runningBundleURL.standardizedFileURL.path == expectedPath
            }
            if launched {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private static func runCommand(
        executable: String,
        arguments: [String]
    ) -> (success: Bool, detail: String) {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            return (false, stderr.isEmpty ? "exit status \(process.terminationStatus)" : stderr)
        }
        return (true, stderr)
    }

    private func reportAccessFlow(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.configurationViewController?.setAccessFlowMessage(message)
        }
    }
}
