import AppKit
import UniformTypeIdentifiers
import MacMouseMapperCore

final class ConfigurationViewController: NSViewController {
    var onConfigurationChanged: ((AppConfiguration) -> Void)?
    var onAccessibilityRequested: (() -> Void)?
    var onAccessibilitySettingsRequested: (() -> Void)?
    var onRepairAccessRequested: (() -> Void)?
    var onQuit: ((Any?) -> Void)?

    private var configuration: AppConfiguration
    private var scrollView: NSScrollView!
    private var contentColumn: NSStackView!
    private var accessibilityStatusLabel: NSTextField!
    private var hidStatusLabel: NSTextField!
    private var accessFlowStatusLabel: NSTextField!
    private var captureStatusLabel: NSTextField!
    private var sideButtonStatusLabel: NSTextField!
    private var remappingStatusLabel: NSTextField!
    private var accessSummaryLabel: NSTextField!
    private var liveDetectionLabel: NSTextField!
    private var selectedSideButton: SideButton = .button4
    private var selectedBundleIdentifier: String?
    private var systemAccessDisclosureExpanded = false
    private var didDisplayInitialSystemAccess = false
    private var permissionSnapshot = PermissionSnapshot(
        accessibilityTrusted: false,
        hidPostEventAccess: .unknown
    )
    private var captureStatus: CaptureStatus = .waitingForPermissions
    private var lastDetectedSideButton: SideButton?
    private var accessFlowMessage = ""
    private var isAccessibilityOperational: Bool {
        captureStatus == .running || permissionSnapshot.accessibilityTrusted
    }
    private var systemAccessIsHealthy: Bool {
        captureStatus == .running
            && permissionSnapshot.hidPostEventAccess == .granted
            && accessFlowMessage.isEmpty
    }
    private var systemAccessNeedsAttention: Bool {
        !systemAccessIsHealthy
    }
    private var isSystemAccessExpanded: Bool {
        systemAccessDisclosureExpanded
    }

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildShell()
        rebuildContent()
    }

    func setConfiguration(_ configuration: AppConfiguration) {
        self.configuration = configuration
        if let selectedBundleIdentifier,
           !configuration.appOverrides.contains(where: { $0.bundleIdentifier == selectedBundleIdentifier }) {
            self.selectedBundleIdentifier = nil
        }
        if isViewLoaded {
            rebuildContent()
        }
    }

    func setPermissionSnapshot(_ snapshot: PermissionSnapshot) {
        let changed = permissionSnapshot != snapshot
        let wasHealthy = systemAccessIsHealthy
        permissionSnapshot = snapshot
        updateSystemAccessDisclosure(previouslyHealthy: wasHealthy)
        guard isViewLoaded else { return }
        if changed {
            rebuildContent()
        } else {
            updateStatusLabels()
        }
    }

    func setCaptureStatus(_ status: CaptureStatus) {
        let changed = captureStatus != status
        let wasHealthy = systemAccessIsHealthy
        captureStatus = status
        updateSystemAccessDisclosure(previouslyHealthy: wasHealthy)
        guard isViewLoaded else { return }
        if changed {
            rebuildContent()
        } else {
            updateStatusLabels()
        }
    }

    func setSideButtonDetected(_ button: SideButton) {
        lastDetectedSideButton = button
        guard isViewLoaded else { return }
        updateStatusLabels()
    }

    func setAccessFlowMessage(_ message: String) {
        guard message != accessFlowMessage else { return }
        let wasHealthy = systemAccessIsHealthy
        accessFlowMessage = message
        updateSystemAccessDisclosure(previouslyHealthy: wasHealthy)
        guard isViewLoaded else { return }
        if wasHealthy != systemAccessIsHealthy {
            rebuildContent()
        } else {
            updateStatusLabels()
        }
    }
    private func updateSystemAccessDisclosure(previouslyHealthy: Bool) {
        guard didDisplayInitialSystemAccess,
              previouslyHealthy,
              systemAccessNeedsAttention else {
            return
        }
        systemAccessDisclosureExpanded = true
    }



    private func buildShell() {
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.bottomAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.bottomAnchor)
        ])

        contentColumn = NSStackView()
        contentColumn.orientation = .vertical
        contentColumn.alignment = .width
        contentColumn.distribution = .fill
        contentColumn.spacing = 18
        contentColumn.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentColumn)

        let preferredWidth = contentColumn.widthAnchor.constraint(equalTo: documentView.widthAnchor, constant: -48)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            contentColumn.leadingAnchor.constraint(greaterThanOrEqualTo: documentView.leadingAnchor, constant: 24),
            contentColumn.trailingAnchor.constraint(lessThanOrEqualTo: documentView.trailingAnchor, constant: -24),
            contentColumn.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            contentColumn.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            contentColumn.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -28),
            contentColumn.widthAnchor.constraint(lessThanOrEqualToConstant: 760),
            contentColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            preferredWidth
        ])
    }

    private func rebuildContent() {
        guard contentColumn != nil else { return }
        contentColumn.arrangedSubviews.forEach {
            contentColumn.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        addSection(makeHeaderCard())
        addSection(makeSystemAccessCard())
        addSection(makeButtonMappingsCard())
        addSection(makeFooter())
        updateStatusLabels()
        didDisplayInitialSystemAccess = true
    }

    /// Every top-level section shares the centered column's exact width. Keeping
    /// this constraint in one place prevents cards and the footer from drifting
    /// to different margins as the window is resized.
    private func addSection(_ section: NSView) {
        section.translatesAutoresizingMaskIntoConstraints = false
        contentColumn.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: contentColumn.widthAnchor).isActive = true
    }

    private func makeCard() -> NSVisualEffectView {
        let card = GlassCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.material = .underWindowBackground
        card.blendingMode = .withinWindow
        card.state = .followsWindowActiveState
        card.wantsLayer = true
        card.layer?.cornerRadius = 16
        card.layer?.cornerCurve = .continuous
        card.updateAppearance()
        return card
    }

    private func cardBody(_ card: NSView, padding: CGFloat = 20) -> NSStackView {
        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .width
        body.distribution = .fill
        body.spacing = 12
        body.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: padding),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -padding),
            body.topAnchor.constraint(equalTo: card.topAnchor, constant: padding),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -padding)
        ])
        return body
    }

    private func makeHeaderCard() -> NSView {
        let card = makeCard()
        let body = cardBody(card, padding: 22)
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = iconView("computermouse.fill", description: "MacMouseMapper", size: 40)
        icon.contentTintColor = .controlAccentColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        let identity = NSStackView()
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 4
        identity.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "MacMouseMapper")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        title.textColor = .labelColor
        let subtitle = wrappingLabel("A focused, native way to remap mouse side buttons.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        identity.addArrangedSubview(title)
        identity.addArrangedSubview(subtitle)

        let remappingStack = NSStackView()
        remappingStack.orientation = .vertical
        remappingStack.alignment = .trailing
        remappingStack.spacing = 5
        remappingStack.setContentHuggingPriority(.required, for: .horizontal)
        let switchControl = NSSwitch()
        switchControl.state = configuration.isEnabled ? .on : .off
        switchControl.target = self
        switchControl.action = #selector(toggleEnabled(_:))
        switchControl.setAccessibilityLabel("Enable all remapping")
        switchControl.toolTip = "Enable or pause global and per-app mappings"
        remappingStatusLabel = NSTextField(labelWithString: "")
        remappingStatusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        remappingStatusLabel.alignment = .right
        remappingStack.addArrangedSubview(switchControl)
        remappingStack.addArrangedSubview(remappingStatusLabel)

        row.addArrangedSubview(icon)
        row.addArrangedSubview(identity)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(remappingStack)
        body.addArrangedSubview(row)

        let note = wrappingLabel("Remapping stays in the menu bar and uses only public macOS event APIs. Turn it off at any time without losing your saved mappings.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        body.addArrangedSubview(note)
        return card
    }

    private func makeSystemAccessCard() -> NSView {
        accessibilityStatusLabel = nil
        hidStatusLabel = nil
        accessFlowStatusLabel = nil
        captureStatusLabel = nil
        sideButtonStatusLabel = nil
        accessSummaryLabel = nil

        let card = makeCard()
        let body = cardBody(card, padding: isSystemAccessExpanded ? 20 : 14)
        if !isSystemAccessExpanded {
            body.addArrangedSubview(makeSystemAccessSummaryRow())
            return card
        }

        let headingRow = NSStackView()
        headingRow.orientation = .horizontal
        headingRow.alignment = .centerY
        headingRow.distribution = .fill
        headingRow.spacing = 10
        headingRow.translatesAutoresizingMaskIntoConstraints = false
        let heading = sectionHeading(
            icon: "lock.shield.fill",
            title: "System Access",
            subtitle: systemAccessSubtitle(),
            iconTint: systemAccessIsHealthy ? .systemGreen : .systemOrange
        )
        headingRow.addArrangedSubview(heading)
        headingRow.addArrangedSubview(NSView())
        headingRow.addArrangedSubview(makeSystemAccessDisclosureButton(expanded: true))
        body.addArrangedSubview(headingRow)

        let statusStack = NSStackView()
        statusStack.orientation = .vertical
        statusStack.alignment = .width
        statusStack.spacing = 8

        accessibilityStatusLabel = wrappingLabel("")
        accessibilityStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusStack.addArrangedSubview(makePermissionRow(
            title: "Accessibility / Device Control",
            statusLabel: accessibilityStatusLabel,
            allowed: isAccessibilityOperational,
            showRepair: !(captureStatus == .running && permissionSnapshot.hidPostEventAccess == .granted),
            requestAction: #selector(requestAccessibility(_:)),
            settingsAction: #selector(openAccessibilitySettings(_:)),
            repairAction: #selector(repairAccess(_:))
        ))

        hidStatusLabel = wrappingLabel("")
        hidStatusLabel.font = .systemFont(ofSize: 11)
        hidStatusLabel.textColor = .secondaryLabelColor
        statusStack.addArrangedSubview(hidStatusLabel)

        accessFlowStatusLabel = wrappingLabel("")
        accessFlowStatusLabel.font = .systemFont(ofSize: 11)
        accessFlowStatusLabel.textColor = .systemOrange
        statusStack.addArrangedSubview(accessFlowStatusLabel)

        captureStatusLabel = wrappingLabel("")
        captureStatusLabel.font = .systemFont(ofSize: 12)
        statusStack.addArrangedSubview(captureStatusLabel)

        sideButtonStatusLabel = wrappingLabel("")
        sideButtonStatusLabel.font = .systemFont(ofSize: 12)
        sideButtonStatusLabel.textColor = .secondaryLabelColor
        statusStack.addArrangedSubview(sideButtonStatusLabel)
        body.addArrangedSubview(statusStack)

        switch captureStatus {
        case .running:
            body.addArrangedSubview(makeStatusCallout(
                icon: "checkmark.circle.fill",
                iconTint: .systemGreen,
                title: "Capture running",
                message: "A live enabled active tap is receiving global mouse events."
            ))
        case .tapUnavailable:
            body.addArrangedSubview(makeStatusCallout(
                icon: "exclamationmark.triangle.fill",
                iconTint: .systemOrange,
                title: "Tap unavailable",
                message: "macOS did not provide a usable active event tap. The app retries automatically."
            ))
        case .waitingForPermissions:
            body.addArrangedSubview(makeStatusCallout(
                icon: "lock.trianglebadge.exclamationmark",
                iconTint: .systemOrange,
                title: "Accessibility required",
                message: "Request access, enable this exact packaged app, and return here."
            ))
        }

        if permissionSnapshot.isHIDPostEventAccessDenied {
            body.addArrangedSubview(makeStatusCallout(
                icon: "arrow.down.circle",
                iconTint: .systemOrange,
                title: "Generated actions unavailable",
                message: "The HID post check is denied, so mapped physical buttons pass through instead of being suppressed."
            ))
        }
        if captureStatus == .running && permissionSnapshot.isHIDPostEventAccessDenied {
            body.addArrangedSubview(makeStatusCallout(
                icon: "wrench.and.screwdriver",
                iconTint: .systemOrange,
                title: "Recovery available",
                message: "Capture is running, but generated actions are unavailable. Click Repair Access to re-register this packaged app, then enable it again in Accessibility."
            ))
        }

        if captureStatus != .running {
            let guide = NSStackView()
            guide.orientation = .vertical
            guide.alignment = .width
            guide.spacing = 8
            let intro = wrappingLabel("Use one Accessibility / Device Control flow for the exact packaged app:")
            intro.textColor = .secondaryLabelColor
            intro.font = .systemFont(ofSize: 12)
            guide.addArrangedSubview(intro)
            guide.addArrangedSubview(numberedCaption("1. Click Request Access and enable this exact bundle in Privacy & Security → Accessibility."))
            guide.addArrangedSubview(numberedCaption("2. Return here; AX status and active-tap availability are checked automatically."))
            guide.addArrangedSubview(numberedCaption("3. If Settings is already enabled but this executable is still untrusted or the tap is unavailable, click Repair Access."))
            guide.addArrangedSubview(numberedCaption(signingIdentityMessage()))
            if !isAccessibilityOperational {
                guide.addArrangedSubview(centeredIllustration(
                    named: "accessibility-request",
                    accessibilityLabel: "Accessibility Access dialog showing the MacMouseMapper request and Open System Settings button."
                ))
                guide.addArrangedSubview(centeredIllustration(
                    named: "accessibility-toggle",
                    accessibilityLabel: "Accessibility settings row with the MacMouseMapper toggle enabled."
                ))
            }
            body.addArrangedSubview(guide)
        }

        let hintMessage: String
        if captureStatus == .running {
            switch permissionSnapshot.hidPostEventAccess {
            case .granted:
                hintMessage = "The active tap and generated actions are running. HID post access is checked off-thread when access is requested or capture recovers."
            case .denied:
                hintMessage = "The active tap is running, but generated actions are unavailable. Mapped physical events pass through until HID post access is granted; use Repair Access for recovery."
            case .unknown:
                hintMessage = "The active tap is running, but generated actions remain unavailable until the HID post check is granted. Mapped physical events pass through meanwhile."
            }
        } else {
            hintMessage = "AX and active-tap status stay passive until you click Request Access, Open Settings, or Repair Access. An explicit flow then retries once per second; HID post access is checked off-thread and a newly granted flow restarts the packaged app once."
        }
        let hint = wrappingLabel(hintMessage)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        body.addArrangedSubview(hint)
        return card
    }

    private func makeSystemAccessSummaryRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        let image = iconView(
            systemAccessIsHealthy ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
            description: "System Access",
            size: 22
        )
        image.contentTintColor = systemAccessIsHealthy ? .systemGreen : .systemOrange
        image.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(image)

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        let title = NSTextField(labelWithString: "System Access")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        accessSummaryLabel = wrappingLabel("")
        accessSummaryLabel.font = .systemFont(ofSize: 11)
        accessSummaryLabel.textColor = systemAccessIsHealthy ? .secondaryLabelColor : .systemOrange
        labels.addArrangedSubview(title)
        labels.addArrangedSubview(accessSummaryLabel)
        row.addArrangedSubview(labels)

        let state = NSTextField(labelWithString: systemAccessIsHealthy ? "Ready" : "Needs attention")
        state.font = .systemFont(ofSize: 12, weight: .semibold)
        state.textColor = systemAccessIsHealthy ? .systemGreen : .systemOrange
        state.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(state)
        row.addArrangedSubview(makeSystemAccessDisclosureButton(expanded: false))
        return row
    }

    private func makeSystemAccessDisclosureButton(expanded: Bool) -> NSButton {
        let button = NSButton(
            title: "",
            target: self,
            action: #selector(toggleSystemAccessDisclosure(_:))
        )
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(
            systemSymbolName: expanded ? "chevron.up" : "chevron.down",
            accessibilityDescription: nil
        )
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(expanded ? "Collapse System Access details" : "Expand System Access details")
        button.setAccessibilityValue(expanded ? "Expanded" : "Collapsed")
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    private func systemAccessSubtitle() -> String {
        if systemAccessIsHealthy {
            return "Ready for capture and generated actions."
        }
        if captureStatus == .running && permissionSnapshot.hidPostEventAccess == .denied {
            return "Needs attention: generated actions are unavailable."
        }
        if captureStatus == .tapUnavailable {
            return "Needs attention: the active event tap is unavailable."
        }
        if permissionSnapshot.accessibilityTrusted {
            return "Needs attention: checking the active event tap."
        }
        return "Needs attention: allow Accessibility / Device Control."
    }

    private func makePermissionRow(
        title: String,
        statusLabel: NSTextField,
        allowed: Bool,
        showRepair: Bool,
        requestAction: Selector,
        settingsAction: Selector,
        repairAction: Selector
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .vertical
        row.alignment = .width
        row.spacing = 5

        let statusLine = NSStackView()
        statusLine.orientation = .horizontal
        statusLine.alignment = .centerY
        statusLine.spacing = 8
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLine.addArrangedSubview(titleLabel)
        statusLine.addArrangedSubview(NSView())
        statusLine.addArrangedSubview(statusLabel)
        row.addArrangedSubview(statusLine)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        if !allowed {
            let requestButton = NSButton(
                title: "Request Access",
                target: self,
                action: requestAction
            )
            requestButton.bezelStyle = .rounded
            requestButton.image = NSImage(systemSymbolName: "person.badge.key", accessibilityDescription: nil)
            requestButton.imagePosition = .imageLeading
            requestButton.setAccessibilityLabel("Request \(title)")
            actions.addArrangedSubview(requestButton)
        }
        let settingsButton = NSButton(
            title: "Open Settings",
            target: self,
            action: settingsAction
        )
        settingsButton.bezelStyle = .rounded
        settingsButton.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
        settingsButton.imagePosition = .imageLeading
        settingsButton.setAccessibilityLabel("Open settings for \(title)")
        actions.addArrangedSubview(settingsButton)

        if showRepair {
            let repairButton = NSButton(
                title: "Repair Access",
                target: self,
                action: repairAction
            )
            repairButton.bezelStyle = .rounded
            repairButton.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
            repairButton.imagePosition = .imageLeading
            repairButton.setAccessibilityLabel("Repair Access for \(title)")
            actions.addArrangedSubview(repairButton)
        }

        row.addArrangedSubview(actions)
        return row
    }

    private func makeButtonMappingsCard() -> NSView {
        if selectedBundleIdentifier == nil {
            selectedBundleIdentifier = configuration.appOverrides.first?.bundleIdentifier
        }
        let button = selectedSideButton
        let card = makeCard()
        let body = cardBody(card, padding: 20)
        addMappingSectionHeading(
            to: body,
            icon: "computermouse.fill",
            title: "Button mapping",
            subtitle: "Choose one side button to see its default and application-specific behavior."
        )

        let selectorContainer = NSView()
        selectorContainer.translatesAutoresizingMaskIntoConstraints = false
        let selectorLabel = NSTextField(labelWithString: "Selected button")
        selectorLabel.translatesAutoresizingMaskIntoConstraints = false
        selectorLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        selectorLabel.alignment = .center
        selectorLabel.setContentHuggingPriority(.required, for: .horizontal)
        let selector = NSSegmentedControl(
            labels: ["Mouse Button 4", "Mouse Button 5"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(selectedSideButtonChanged(_:))
        )
        selector.translatesAutoresizingMaskIntoConstraints = false
        selector.selectedSegment = selectedSideButton == .button4 ? 0 : 1
        selector.segmentStyle = .texturedRounded
        selector.setAccessibilityLabel("Selected mouse side button")
        selector.setAccessibilityValue(selectedSideButton.displayName)
        selector.setContentHuggingPriority(.required, for: .horizontal)
        selector.setContentCompressionResistancePriority(.required, for: .horizontal)
        selectorContainer.addSubview(selectorLabel)
        selectorContainer.addSubview(selector)
        NSLayoutConstraint.activate([
            selectorLabel.centerXAnchor.constraint(equalTo: selectorContainer.centerXAnchor),
            selectorLabel.topAnchor.constraint(equalTo: selectorContainer.topAnchor),
            selector.topAnchor.constraint(equalTo: selectorLabel.bottomAnchor, constant: 6),
            selector.centerXAnchor.constraint(equalTo: selectorContainer.centerXAnchor),
            selector.bottomAnchor.constraint(equalTo: selectorContainer.bottomAnchor)
        ])
        body.addArrangedSubview(selectorContainer)

        let illustration = SideButtonIllustrationView(selectedButton: selectedSideButton)
        illustration.translatesAutoresizingMaskIntoConstraints = false
        let illustrationContainer = NSView()
        illustrationContainer.translatesAutoresizingMaskIntoConstraints = false
        illustrationContainer.addSubview(illustration)
        NSLayoutConstraint.activate([
            illustrationContainer.heightAnchor.constraint(equalToConstant: 188),
            illustration.centerXAnchor.constraint(equalTo: illustrationContainer.centerXAnchor),
            illustration.centerYAnchor.constraint(equalTo: illustrationContainer.centerYAnchor),
            illustration.widthAnchor.constraint(equalToConstant: 300),
            illustration.heightAnchor.constraint(equalToConstant: 188)
        ])
        body.addArrangedSubview(illustrationContainer)

        let orientation = wrappingLabel(
            "Typical orientation: Button 4 is the rear/lower side button and Button 5 is the front/upper one. Hardware can vary—press a button and use Last side button below to confirm."
        )
        orientation.font = .systemFont(ofSize: 11)
        orientation.textColor = .secondaryLabelColor
        orientation.alignment = .center
        body.addArrangedSubview(orientation)

        let detection = wrappingLabel("")
        detection.font = .systemFont(ofSize: 11, weight: .medium)
        detection.textColor = .secondaryLabelColor
        detection.alignment = .center
        liveDetectionLabel = detection
        body.addArrangedSubview(detection)


        addMappingSectionHeading(
            to: body,
            icon: "globe",
            title: "Default behavior",
            subtitle: "Used everywhere unless an application-specific behavior is set."
        )
        let globalEditor = MappingEditorView(
            button: button,
            mapping: configuration.globalMappings.mapping(for: button)
        ) { [weak self] mapping in
            self?.updateGlobal(mapping, for: button)
        }
        body.addArrangedSubview(globalEditor)
        globalEditor.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true

        addMappingSectionHeading(
            to: body,
            icon: "rectangle.3.group.fill",
            title: "Application-specific behavior",
            subtitle: "Customize this button for one selected application."
        )
        let help = wrappingLabel(
            "An empty app-specific mapping uses the Default behavior. Overrides are matched by bundle identifier."
        )
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        body.addArrangedSubview(help)

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 9
        let addButton = NSButton(
            title: "Add Application…",
            target: self,
            action: #selector(addApplication(_:))
        )
        addButton.bezelStyle = .rounded
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        addButton.setAccessibilityLabel("Add application override")
        actionRow.addArrangedSubview(addButton)

        if selectedOverride != nil {
            let removeButton = NSButton(
                title: "Remove",
                target: self,
                action: #selector(removeApplication(_:))
            )
            removeButton.bezelStyle = .rounded
            removeButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            removeButton.imagePosition = .imageLeading
            removeButton.setAccessibilityLabel("Remove selected application override")
            actionRow.addArrangedSubview(removeButton)
        }
        actionRow.addArrangedSubview(NSView())
        body.addArrangedSubview(actionRow)

        if !configuration.appOverrides.isEmpty {
            let picker = NSPopUpButton()
            picker.target = self
            picker.action = #selector(selectOverride(_:))
            picker.setAccessibilityLabel("Application override")
            picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            picker.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true
            for override in configuration.appOverrides {
                let item = picker.menu?.addItem(
                    withTitle: "\(override.displayName)  (\(override.bundleIdentifier))",
                    action: nil,
                    keyEquivalent: ""
                )
                item?.representedObject = override.bundleIdentifier
            }
            if let selectedBundleIdentifier,
               let item = picker.itemArray.first(where: {
                   ($0.representedObject as? String) == selectedBundleIdentifier
               }) {
                picker.select(item)
            } else if let first = configuration.appOverrides.first {
                selectedBundleIdentifier = first.bundleIdentifier
                picker.selectItem(at: 0)
            }
            body.addArrangedSubview(picker)

            if let selected = selectedOverride {
                let selectedBundleIdentifier = selected.bundleIdentifier
                let selectedLabel = wrappingLabel(
                    "Editing \(selected.displayName) · \(selected.bundleIdentifier)"
                )
                selectedLabel.font = .systemFont(ofSize: 12, weight: .medium)
                selectedLabel.textColor = .secondaryLabelColor
                body.addArrangedSubview(selectedLabel)
                let appEditor = MappingEditorView(
                    button: button,
                    mapping: selected.mappings.mapping(for: button)
                ) { [weak self] mapping in
                    self?.updateOverride(
                        mapping,
                        for: button,
                        bundleIdentifier: selectedBundleIdentifier
                    )
                }
                body.addArrangedSubview(appEditor)
                appEditor.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
            }
        } else {
            let empty = NSTextField(labelWithString: "No application overrides yet")
            empty.textColor = .secondaryLabelColor
            empty.font = .systemFont(ofSize: 12)
            body.addArrangedSubview(empty)
        }
        return card
    }
    private func addMappingSectionHeading(
        to body: NSStackView,
        icon: String,
        title: String,
        subtitle: String,
        iconTint: NSColor = .controlAccentColor
    ) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let heading = sectionHeading(
            icon: icon,
            title: title,
            subtitle: subtitle,
            iconTint: iconTint
        )
        heading.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(heading)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            heading.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            heading.topAnchor.constraint(equalTo: container.topAnchor),
            heading.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        body.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
    }


    private var selectedOverride: AppOverride? {
        if let selectedBundleIdentifier,
           let selected = configuration.appOverrides.first(where: {
               $0.bundleIdentifier == selectedBundleIdentifier
           }) {
            return selected
        }
        return configuration.appOverrides.first
    }

    private func makeFooter() -> NSView {
        let footer = NSStackView()
        footer.orientation = .vertical
        footer.alignment = .centerX
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false

        let limitations = wrappingLabel("Gesture mappings emit public Quartz pixel-scroll events in a short burst. macOS does not provide a public API for synthetic multi-touch, Mission Control, pinch, or arbitrary three-finger gestures.")
        limitations.font = .systemFont(ofSize: 11)
        limitations.textColor = .secondaryLabelColor
        limitations.alignment = .center
        footer.addArrangedSubview(limitations)
        limitations.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true

        let versionLabel = NSTextField(labelWithString: packagedVersionText())
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .center
        versionLabel.setContentHuggingPriority(.required, for: .horizontal)
        footer.addArrangedSubview(versionLabel)

        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quit(_:)))
        quitButton.bezelStyle = .rounded
        quitButton.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitButton.imagePosition = .imageLeading
        quitButton.setContentHuggingPriority(.required, for: .horizontal)
        footer.addArrangedSubview(quitButton)
        return footer
    }

    private func packagedVersionText() -> String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !version.isEmpty,
              !build.isEmpty else {
            return "Development build"
        }
        return "Version \(version) (\(build))"
    }
    private func signingIdentityMessage() -> String {
        guard let mode = Bundle.main.object(forInfoDictionaryKey: "MMMCodeSigningMode") as? String else {
            return "Development build: Repair Access works only after launching the packaged .app."
        }
        if mode == "adhoc" {
            return "Ad-hoc build: each rebuild can create a new Accessibility identity; use Repair Access for stale entries."
        }
        let identity = Bundle.main.object(forInfoDictionaryKey: "MMMCodeSigningIdentity") as? String
        if let identity, !identity.isEmpty {
            return "Signed identity: \(identity)."
        }
        return "Signed packaged build; Repair Access remains available for stale entries."
    }

    private func sectionHeading(
        icon: String,
        title: String,
        subtitle: String,
        iconTint: NSColor = .controlAccentColor
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 11
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        let image = iconView(icon, description: title, size: 22)
        image.contentTintColor = iconTint
        image.setContentHuggingPriority(.required, for: .horizontal)
        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        let subtitleLabel = wrappingLabel(subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        labels.addArrangedSubview(titleLabel)
        labels.addArrangedSubview(subtitleLabel)
        row.addArrangedSubview(image)
        row.addArrangedSubview(labels)
        return row
    }

    private func makeStatusCallout(icon: String, iconTint: NSColor, title: String, message: String) -> NSView {
        let callout = NSStackView()
        callout.orientation = .horizontal
        callout.alignment = .top
        callout.spacing = 9
        let image = iconView(icon, description: title, size: 19)
        image.contentTintColor = iconTint
        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        let messageLabel = wrappingLabel(message)
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor
        labels.addArrangedSubview(titleLabel)
        labels.addArrangedSubview(messageLabel)
        callout.addArrangedSubview(image)
        callout.addArrangedSubview(labels)
        return callout
    }

    private func numberedCaption(_ text: String) -> NSTextField {
        let label = wrappingLabel(text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func centeredIllustration(named name: String, accessibilityLabel: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        guard let image = ResourceImageLoader.image(named: name) else {
            let missing = wrappingLabel("Illustration unavailable: \(name).png")
            missing.font = .systemFont(ofSize: 12, weight: .medium)
            missing.textColor = .systemRed
            missing.setAccessibilityLabel("Missing required accessibility illustration \(name)")
            container.addSubview(missing)
            NSLayoutConstraint.activate([
                missing.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                missing.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                missing.topAnchor.constraint(equalTo: container.topAnchor),
                missing.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            return container
        }

        let imageView = NSImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.setAccessibilityLabel(accessibilityLabel)
        imageView.setAccessibilityRole(.image)
        let naturalSize = image.size
        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: naturalSize.width),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: naturalSize.height)
        ])
        return container
    }

    private func iconView(_ symbolName: String, description: String, size: CGFloat) -> NSImageView {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: description)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setAccessibilityLabel(description)
        imageView.widthAnchor.constraint(equalToConstant: size).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: size).isActive = true
        return imageView
    }

    private func wrappingLabel(_ string: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.usesSingleLineMode = false
        return label
    }

    private func updateGlobal(_ mapping: ButtonMapping?, for button: SideButton) {
        configuration.globalMappings.setMapping(mapping, for: button)
        notifyConfigurationChanged()
    }

    private func updateOverride(
        _ mapping: ButtonMapping?,
        for button: SideButton,
        bundleIdentifier: String
    ) {
        guard let index = configuration.appOverrides.firstIndex(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else { return }
        configuration.appOverrides[index].mappings.setMapping(mapping, for: button)
        notifyConfigurationChanged()
    }

    private func notifyConfigurationChanged() {
        configuration = configuration.sanitized()
        onConfigurationChanged?(configuration)
        updateStatusLabels()
    }

    private func updateStatusLabels() {
        if let accessSummaryLabel {
            accessSummaryLabel.stringValue = systemAccessSummary()
            accessSummaryLabel.textColor = systemAccessIsHealthy
                ? .secondaryLabelColor
                : .systemOrange
        }

        if let accessibilityStatusLabel {
            if captureStatus == .running {
                accessibilityStatusLabel.stringValue = "Operational via active tap"
            } else {
                accessibilityStatusLabel.stringValue = permissionSnapshot.accessibilityTrusted
                    ? "Allowed for this process"
                    : "Required for this process"
            }
            accessibilityStatusLabel.textColor = isAccessibilityOperational
                ? .systemGreen
                : .systemOrange
        }

        if let hidStatusLabel {
            switch permissionSnapshot.hidPostEventAccess {
            case .granted:
                hidStatusLabel.stringValue = "HID post check: allowed for generated actions"
                hidStatusLabel.textColor = .systemGreen
            case .denied:
                hidStatusLabel.stringValue = "HID post check: denied · mapped physical events pass through"
                hidStatusLabel.textColor = .systemOrange
            case .unknown:
                hidStatusLabel.stringValue = "HID post check: unknown · mapped physical events pass through"
                hidStatusLabel.textColor = .secondaryLabelColor
            }
        }

        if let accessFlowStatusLabel {
            accessFlowStatusLabel.stringValue = accessFlowMessage
            accessFlowStatusLabel.isHidden = accessFlowMessage.isEmpty
        }

        if let captureStatusLabel {
            switch captureStatus {
            case .running:
                captureStatusLabel.stringValue = "Capture: Running"
                captureStatusLabel.textColor = .systemGreen
            case .waitingForPermissions:
                captureStatusLabel.stringValue = permissionSnapshot.accessibilityTrusted
                    ? "Capture: Waiting for event tap"
                    : "Capture: Waiting for Accessibility"
                captureStatusLabel.textColor = .systemOrange
            case .tapUnavailable:
                captureStatusLabel.stringValue = "Capture: Tap unavailable"
                captureStatusLabel.textColor = .systemOrange
            }
        }

        let detectionText = lastDetectedSideButton.map {
            "Last side button: \($0.displayName)"
        } ?? "Last side button: None detected"
        sideButtonStatusLabel?.stringValue = detectionText
        sideButtonStatusLabel?.textColor = .secondaryLabelColor
        liveDetectionLabel?.stringValue = detectionText
        liveDetectionLabel?.textColor = .secondaryLabelColor
        remappingStatusLabel?.stringValue = configuration.isEnabled ? "Remapping active" : "Remapping paused"
        remappingStatusLabel?.textColor = configuration.isEnabled ? .systemGreen : .secondaryLabelColor
    }

    private func systemAccessSummary() -> String {
        let detection = lastDetectedSideButton.map {
            "Last side button: \($0.displayName)"
        } ?? "Press a side button to identify it"
        if systemAccessIsHealthy {
            return "Ready for capture and generated actions · \(detection)"
        }
        if !accessFlowMessage.isEmpty {
            return "Needs attention · \(accessFlowMessage)"
        }
        if captureStatus == .running && permissionSnapshot.hidPostEventAccess == .denied {
            return "Needs attention · generated actions unavailable · \(detection)"
        }
        return "Needs attention · \(detection)"
    }

    @objc private func selectedSideButtonChanged(_ sender: NSSegmentedControl) {
        let button: SideButton = sender.selectedSegment == 1 ? .button5 : .button4
        guard button != selectedSideButton else { return }
        selectedSideButton = button
        rebuildContent()
    }

    @objc private func toggleSystemAccessDisclosure(_ sender: NSButton) {
        systemAccessDisclosureExpanded = !isSystemAccessExpanded
        rebuildContent()
    }

    @objc private func toggleEnabled(_ sender: NSSwitch) {
        configuration.isEnabled = sender.state == .on
        notifyConfigurationChanged()
    }

    @objc private func requestAccessibility(_ sender: NSButton) {
        onAccessibilityRequested?()
    }

    @objc private func openAccessibilitySettings(_ sender: NSButton) {
        onAccessibilitySettingsRequested?()
    }

    @objc private func repairAccess(_ sender: NSButton) {
        onRepairAccessRequested?()
    }

    @objc private func quit(_ sender: NSButton) {
        onQuit?(sender)
    }

    @objc private func addApplication(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = "Add Application"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              AppOverride.isValidBundleIdentifier(bundleIdentifier) else {
            return
        }
        if configuration.appOverrides.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return
        }
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        configuration.appOverrides.append(AppOverride(bundleIdentifier: bundleIdentifier, displayName: displayName))
        configuration = configuration.sanitized()
        selectedBundleIdentifier = bundleIdentifier
        onConfigurationChanged?(configuration)
        rebuildContent()
    }


    @objc private func selectOverride(_ sender: NSPopUpButton) {
        guard let bundleIdentifier = sender.selectedItem?.representedObject as? String,
              configuration.appOverrides.contains(where: {
                  $0.bundleIdentifier == bundleIdentifier
              }) else { return }
        guard bundleIdentifier != selectedBundleIdentifier else { return }
        selectedBundleIdentifier = bundleIdentifier
        rebuildContent()
    }

    @objc private func removeApplication(_ sender: NSButton) {
        guard let selected = selectedOverride else { return }
        let removedBundleIdentifier = selected.bundleIdentifier
        configuration.appOverrides.removeAll {
            $0.bundleIdentifier == removedBundleIdentifier
        }
        selectedBundleIdentifier = configuration.appOverrides.first?.bundleIdentifier
        onConfigurationChanged?(configuration)
        rebuildContent()
    }
}

private final class SideButtonIllustrationView: NSView {
    private(set) var selectedButton: SideButton {
        didSet {
            updateAccessibility()
            needsDisplay = true
        }
    }

    init(selectedButton: SideButton) {
        self.selectedButton = selectedButton
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        updateAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func updateAccessibility() {
        setAccessibilityLabel(
            "Mouse with visible side buttons 4 and 5; \(selectedButton.displayName) highlighted"
        )
        setAccessibilityValue(selectedButton.displayName)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 1, bounds.height > 1 else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let bodyHeight = min(172, bounds.height - 16)
        let bodyWidth = min(112, bounds.width * 0.40)
        let bodyCenterX = bounds.midX + min(7, bounds.width * 0.03)
        let bodyRect = NSRect(
            x: bodyCenterX - bodyWidth / 2,
            y: (bounds.height - bodyHeight) / 2,
            width: bodyWidth,
            height: bodyHeight
        )

        let bodyPath = NSBezierPath()
        bodyPath.move(to: NSPoint(x: bodyRect.midX, y: bodyRect.minY))
        bodyPath.curve(
            to: NSPoint(x: bodyRect.maxX - 3, y: bodyRect.minY + 32),
            controlPoint1: NSPoint(x: bodyRect.midX + bodyRect.width * 0.31, y: bodyRect.minY + 3),
            controlPoint2: NSPoint(x: bodyRect.maxX - 1, y: bodyRect.minY + 14)
        )
        bodyPath.curve(
            to: NSPoint(x: bodyRect.maxX - 1, y: bodyRect.maxY - 44),
            controlPoint1: NSPoint(x: bodyRect.maxX + 1, y: bodyRect.minY + 76),
            controlPoint2: NSPoint(x: bodyRect.maxX + 1, y: bodyRect.maxY - 70)
        )
        bodyPath.curve(
            to: NSPoint(x: bodyRect.midX, y: bodyRect.maxY),
            controlPoint1: NSPoint(x: bodyRect.maxX - 1, y: bodyRect.maxY - 15),
            controlPoint2: NSPoint(x: bodyRect.midX + bodyRect.width * 0.32, y: bodyRect.maxY - 2)
        )
        bodyPath.curve(
            to: NSPoint(x: bodyRect.minX + 1, y: bodyRect.maxY - 44),
            controlPoint1: NSPoint(x: bodyRect.midX - bodyRect.width * 0.32, y: bodyRect.maxY - 2),
            controlPoint2: NSPoint(x: bodyRect.minX + 1, y: bodyRect.maxY - 15)
        )
        bodyPath.curve(
            to: NSPoint(x: bodyRect.minX + 3, y: bodyRect.minY + 32),
            controlPoint1: NSPoint(x: bodyRect.minX - 1, y: bodyRect.maxY - 70),
            controlPoint2: NSPoint(x: bodyRect.minX - 1, y: bodyRect.minY + 76)
        )
        bodyPath.curve(
            to: NSPoint(x: bodyRect.midX, y: bodyRect.minY),
            controlPoint1: NSPoint(x: bodyRect.minX + 1, y: bodyRect.minY + 14),
            controlPoint2: NSPoint(x: bodyRect.midX - bodyRect.width * 0.31, y: bodyRect.minY + 3)
        )
        bodyPath.close()

        NSColor.controlBackgroundColor.setFill()
        bodyPath.fill()
        NSColor.separatorColor.withAlphaComponent(0.75).setStroke()
        bodyPath.lineWidth = 1.15
        bodyPath.stroke()

        // The split reaches from the nose to the wheel, making the two
        // primary click surfaces readable without over-describing the shell.
        let clickSplit = NSBezierPath()
        clickSplit.move(to: NSPoint(x: bodyRect.midX, y: bodyRect.minY + 9))
        clickSplit.curve(
            to: NSPoint(x: bodyRect.midX, y: bodyRect.minY + 55),
            controlPoint1: NSPoint(x: bodyRect.midX + 0.5, y: bodyRect.minY + 23),
            controlPoint2: NSPoint(x: bodyRect.midX, y: bodyRect.minY + 40)
        )
        NSColor.separatorColor.withAlphaComponent(0.62).setStroke()
        clickSplit.lineWidth = 0.9
        clickSplit.stroke()

        let wheelSlotRect = NSRect(
            x: bodyRect.midX - 8,
            y: bodyRect.minY + 38,
            width: 16,
            height: 34
        )
        let wheelSlot = NSBezierPath(
            roundedRect: wheelSlotRect,
            xRadius: 8,
            yRadius: 8
        )
        NSColor.separatorColor.withAlphaComponent(0.10).setFill()
        wheelSlot.fill()
        NSColor.separatorColor.withAlphaComponent(0.42).setStroke()
        wheelSlot.lineWidth = 0.8
        wheelSlot.stroke()

        let wheelRect = NSRect(
            x: bodyRect.midX - 4,
            y: bodyRect.minY + 44,
            width: 8,
            height: 23
        )
        let wheel = NSBezierPath(
            roundedRect: wheelRect,
            xRadius: 4,
            yRadius: 4
        )
        NSColor.tertiaryLabelColor.withAlphaComponent(0.62).setFill()
        wheel.fill()
        NSColor.labelColor.withAlphaComponent(0.42).setStroke()
        wheel.lineWidth = 0.75
        wheel.stroke()
        for offset in stride(from: 6, through: 16, by: 5) {
            let wheelMark = NSBezierPath()
            wheelMark.move(to: NSPoint(x: wheelRect.minX + 2, y: wheelRect.minY + CGFloat(offset)))
            wheelMark.line(to: NSPoint(x: wheelRect.maxX - 2, y: wheelRect.minY + CGFloat(offset)))
            NSColor.labelColor.withAlphaComponent(0.55).setStroke()
            wheelMark.lineWidth = 0.7
            wheelMark.stroke()
        }

        // The buttons overlap the shell edge slightly, but share its contour
        // and fill; there is intentionally no detached side rail.
        let sideButtonWidth: CGFloat = 30
        let sideButtonHeight: CGFloat = 27
        let sideButtonX = bodyRect.minX - 5
        let button5Rect = NSRect(
            x: sideButtonX,
            y: bodyRect.minY + bodyRect.height * 0.43,
            width: sideButtonWidth,
            height: sideButtonHeight
        )
        let button4Rect = NSRect(
            x: sideButtonX,
            y: button5Rect.maxY + 8,
            width: sideButtonWidth,
            height: sideButtonHeight
        )
        drawSideButton(button5Rect, button: .button5)
        drawSideButton(button4Rect, button: .button4)
    }

    private func drawSideButton(_ rect: NSRect, button: SideButton) {
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: 10,
            yRadius: 10
        )
        let isSelected = selectedButton == button
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.24).setFill()
            NSColor.controlAccentColor.setStroke()
        } else {
            NSColor.secondaryLabelColor.withAlphaComponent(0.14).setFill()
            NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
        }
        path.lineWidth = isSelected ? 1.7 : 1
        path.fill()
        path.stroke()

        let title = button == .button4 ? "4" : "5"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: isSelected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
        ]
        let titleSize = (title as NSString).size(withAttributes: attributes)
        let titleRect = NSRect(
            x: rect.midX - titleSize.width / 2,
            y: rect.midY - titleSize.height / 2,
            width: titleSize.width,
            height: titleSize.height
        )
        (title as NSString).draw(in: titleRect, withAttributes: attributes)
    }
}

private final class GlassCardView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func updateAppearance() {
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.32).cgColor
        layer?.shadowColor = NSColor.shadowColor.withAlphaComponent(0.16).cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }
}

private enum ResourceImageLoader {
    static func image(named name: String) -> NSImage? {
        var bundles: [Bundle] = [Bundle.main]
        #if SWIFT_PACKAGE
        bundles.append(Bundle.module)
        #endif

        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) {
                return image
            }
            if let resourceURL = bundle.resourceURL,
               let nestedURLs = try? FileManager.default.contentsOfDirectory(
                   at: resourceURL,
                   includingPropertiesForKeys: nil,
                   options: [.skipsHiddenFiles]
               ) {
                for nestedURL in nestedURLs where nestedURL.pathExtension == "bundle" {
                    if let nestedBundle = Bundle(url: nestedURL),
                       let url = nestedBundle.url(forResource: name, withExtension: "png"),
                       let image = NSImage(contentsOf: url) {
                        return image
                    }
                }
            }
        }
        return nil
    }
}

private final class MappingEditorView: NSView {
    private let button: SideButton
    private var mapping: ButtonMapping?
    private let onChange: (ButtonMapping?) -> Void
    private let modePopup = NSPopUpButton()
    private let enabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let details = NSStackView()
    private let validationLabel = NSTextField(labelWithString: "")
    private var keyRecorder: KeyRecorderButton?
    private var modifierButtons: [ModifierMask: NSButton] = [:]
    private var keyWindowObserver: NSObjectProtocol?
    private var isRecordingKey = false
    private var recordingShortcut: KeyboardShortcut?

    init(button: SideButton, mapping: ButtonMapping?, onChange: @escaping (ButtonMapping?) -> Void) {
        self.button = button
        self.mapping = mapping
        self.onChange = onChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelKeyRecording()
        }
    }

    deinit {
        cancelKeyRecording()
    }

    private func build() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .width
        root.distribution = .fill
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let title = NSTextField(labelWithString: button.displayName)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)

        modePopup.addItems(withTitles: ["Pass through", "Keyboard shortcut", "Another mouse button", "Gesture"])
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        modePopup.target = self
        modePopup.action = #selector(modeChanged(_:))

        enabledButton.translatesAutoresizingMaskIntoConstraints = false
        enabledButton.target = self
        enabledButton.action = #selector(mappingChanged(_:))

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearMapping(_:)))
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.bezelStyle = .rounded
        clearButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        clearButton.imagePosition = .imageLeading
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        clearButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        header.addSubview(title)
        header.addSubview(modePopup)
        header.addSubview(enabledButton)
        header.addSubview(clearButton)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.widthAnchor.constraint(equalToConstant: 118),
            modePopup.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 9),
            modePopup.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            modePopup.widthAnchor.constraint(equalToConstant: 178),
            enabledButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -9),
            enabledButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            enabledButton.widthAnchor.constraint(equalToConstant: 74),
            clearButton.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            clearButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 70),
            modePopup.trailingAnchor.constraint(lessThanOrEqualTo: enabledButton.leadingAnchor, constant: -12)
        ])
        root.addArrangedSubview(header)

        details.orientation = .vertical
        details.alignment = .width
        details.spacing = 6
        root.addArrangedSubview(details)

        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 11)
        validationLabel.isHidden = true
        validationLabel.setAccessibilityLabel("Mapping validation")
        root.addArrangedSubview(validationLabel)
        refreshControls()
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 0:
            mapping = nil
        case 1:
            let keyCode = KeyCatalog.entries.first?.keyCode ?? 0
            mapping = ButtonMapping(action: .keyboard(KeyboardShortcut(keyCode: keyCode)))
        case 2:
            mapping = ButtonMapping(action: .mouse(MouseButton(number: 0)))
        case 3:
            mapping = ButtonMapping(action: .gesture(.smoothScrollUp))
        default:
            mapping = nil
        }
        refreshControls()
        emit()
    }

    @objc private func mappingChanged(_ sender: NSButton) {
        mapping?.isEnabled = sender.state == .on
        emit()
    }

    @objc private func clearMapping(_ sender: NSButton) {
        mapping = nil
        refreshControls()
        emit()
    }

    private func refreshControls() {
        cancelKeyRecording()
        details.arrangedSubviews.forEach {
            details.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        keyRecorder = nil
        modifierButtons.removeAll()
        validationLabel.stringValue = ""
        validationLabel.isHidden = true
        guard let mapping else {
            modePopup.selectItem(at: 0)
            enabledButton.isHidden = true
            return
        }
        enabledButton.isHidden = false
        enabledButton.state = mapping.isEnabled ? .on : .off
        switch mapping.action {
        case .keyboard(let shortcut):
            modePopup.selectItem(at: 1)
            let keyRow = NSStackView()
            keyRow.orientation = .horizontal
            keyRow.alignment = .centerY
            keyRow.spacing = 8
            let keyLabel = NSTextField(labelWithString: "Key")
            keyLabel.font = .systemFont(ofSize: 12, weight: .medium)
            keyLabel.setContentHuggingPriority(.required, for: .horizontal)

            let recorder = KeyRecorderButton(title: shortcut.displayName, target: self, action: #selector(toggleKeyRecording(_:)))
            recorder.bezelStyle = .rounded
            recorder.alignment = .center
            recorder.setContentHuggingPriority(.required, for: .horizontal)
            recorder.setContentCompressionResistancePriority(.required, for: .horizontal)
            recorder.setAccessibilityLabel("Keyboard shortcut key")
            recorder.setAccessibilityValue(shortcut.displayName)
            recorder.setAccessibilityHelp("Click to record a physical key and its currently held Command, Option, Control, Shift, or fn modifiers.")
            recorder.toolTip = "Click, then press a supported physical key"
            recorder.onKeyEvent = { [weak self] event in
                self?.recordKey(event) ?? false
            }
            recorder.onFocusLost = { [weak self] in
                self?.cancelKeyRecording()
            }
            keyRecorder = recorder
            keyRow.addArrangedSubview(keyLabel)
            keyRow.addArrangedSubview(recorder)
            details.addArrangedSubview(keyRow)

            let hint = NSTextField(wrappingLabelWithString: "Click the key button, then press a supported physical key. The held modifiers are recorded with it.")
            hint.font = .systemFont(ofSize: 11)
            hint.textColor = .secondaryLabelColor
            details.addArrangedSubview(hint)

            let modifierStack = NSStackView()
            modifierStack.orientation = .vertical
            modifierStack.alignment = .leading
            modifierStack.spacing = 4
            let modifierLabel = NSTextField(labelWithString: "Modifiers")
            modifierLabel.font = .systemFont(ofSize: 12, weight: .medium)
            modifierLabel.setContentHuggingPriority(.required, for: .horizontal)
            modifierStack.addArrangedSubview(modifierLabel)
            var modifierRow: NSStackView?
            for (index, entry) in [
                (ModifierMask.command, "⌘ Command"),
                (ModifierMask.option, "⌥ Option"),
                (ModifierMask.control, "⌃ Control"),
                (ModifierMask.shift, "⇧ Shift"),
                (ModifierMask.function, "fn")
            ].enumerated() {
                if index.isMultiple(of: 2) {
                    let row = NSStackView()
                    row.orientation = .horizontal
                    row.alignment = .centerY
                    row.spacing = 8
                    modifierStack.addArrangedSubview(row)
                    modifierRow = row
                }
                let (mask, title) = entry
                let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(modifierChanged(_:)))
                checkbox.toolTip = "Add \(title) modifier"
                checkbox.state = shortcut.modifiers.contains(mask) ? .on : .off
                checkbox.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                modifierButtons[mask] = checkbox
                modifierRow?.addArrangedSubview(checkbox)
            }
            details.addArrangedSubview(modifierStack)
        case .mouse(let mouseButton):
            modePopup.selectItem(at: 2)
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.addArrangedSubview(NSTextField(labelWithString: "Button"))
            let popup = NSPopUpButton()
            for number in 0...15 {
                popup.addItem(withTitle: MouseButton(number: UInt32(number)).displayName)
            }
            popup.selectItem(at: Int(mouseButton.number))
            popup.target = self
            popup.action = #selector(mouseChanged(_:))
            popup.widthAnchor.constraint(equalToConstant: 160).isActive = true
            row.addArrangedSubview(popup)
            details.addArrangedSubview(row)
        case .gesture(let gesture):
            modePopup.selectItem(at: 3)
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.addArrangedSubview(NSTextField(labelWithString: "Direction"))
            let popup = NSPopUpButton()
            popup.addItems(withTitles: GestureKind.allCases.map(\.displayName))
            popup.selectItem(at: GestureKind.allCases.firstIndex(of: gesture) ?? 0)
            popup.target = self
            popup.action = #selector(gestureChanged(_:))
            popup.widthAnchor.constraint(equalToConstant: 190).isActive = true
            row.addArrangedSubview(popup)
            details.addArrangedSubview(row)
        }
        if !mapping.isValid {
            validationLabel.stringValue = "Choose a real key and supported modifiers before saving."
            validationLabel.isHidden = false
        }
    }

    @objc private func toggleKeyRecording(_ sender: KeyRecorderButton) {
        guard case .keyboard(let shortcut) = mapping?.action else { return }
        if isRecordingKey {
            cancelKeyRecording()
            return
        }

        isRecordingKey = true
        recordingShortcut = shortcut
        sender.title = "Press a key…"
        sender.setAccessibilityValue("Listening for a supported physical key")
        guard let window = sender.window else {
            cancelKeyRecording()
            return
        }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.cancelKeyRecording()
        }
        guard window.makeFirstResponder(sender) else {
            cancelKeyRecording()
            return
        }
    }

    private func recordKey(_ event: NSEvent) -> Bool {
        guard isRecordingKey, event.type == .keyDown else { return false }
        guard let shortcut = KeyboardShortcut(
            capturedKeyCode: event.keyCode,
            eventModifierRawValue: event.modifierFlags.rawValue
        ) else {
            // Consume unsupported and modifier-only input, but leave the
            // recorder listening so an accidental key cannot overwrite the
            // persisted shortcut.
            NSSound.beep()
            return true
        }
        guard case .keyboard = mapping?.action else {
            cancelKeyRecording()
            return true
        }

        mapping?.action = .keyboard(shortcut)
        isRecordingKey = false
        recordingShortcut = nil
        removeKeyWindowObserver()
        if let recorder = keyRecorder {
            recorder.title = shortcut.displayName
            recorder.setAccessibilityValue(shortcut.displayName)
        }
        for (mask, checkbox) in modifierButtons {
            checkbox.state = shortcut.modifiers.contains(mask) ? .on : .off
        }
        if let recorder = keyRecorder,
           let window = recorder.window,
           window.firstResponder === recorder {
            window.makeFirstResponder(nil)
        }
        emit()
        return true
    }

    private func cancelKeyRecording() {
        let wasRecording = isRecordingKey
        isRecordingKey = false
        removeKeyWindowObserver()
        let restoredShortcut = recordingShortcut
        recordingShortcut = nil
        if wasRecording, let restoredShortcut, let recorder = keyRecorder {
            recorder.title = restoredShortcut.displayName
            recorder.setAccessibilityValue(restoredShortcut.displayName)
            if let window = recorder.window, window.firstResponder === recorder {
                window.makeFirstResponder(nil)
            }
        }
    }

    private func removeKeyWindowObserver() {
        if let observer = keyWindowObserver {
            NotificationCenter.default.removeObserver(observer)
            keyWindowObserver = nil
        }
    }

    @objc private func modifierChanged(_ sender: NSButton) {
        guard case .keyboard(var shortcut) = mapping?.action else { return }
        var modifiers: ModifierMask = []
        for (mask, checkbox) in modifierButtons where checkbox.state == .on {
            modifiers.insert(mask)
        }
        shortcut.modifiers = modifiers
        mapping?.action = .keyboard(shortcut)
        emit()
    }

    @objc private func mouseChanged(_ sender: NSPopUpButton) {
        guard mapping != nil, (0...15).contains(sender.indexOfSelectedItem) else { return }
        mapping?.action = .mouse(MouseButton(number: UInt32(sender.indexOfSelectedItem)))
        emit()
    }

    @objc private func gestureChanged(_ sender: NSPopUpButton) {
        guard mapping != nil, GestureKind.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        mapping?.action = .gesture(GestureKind.allCases[sender.indexOfSelectedItem])
        emit()
    }

    private func emit() {
        guard let mapping else {
            onChange(nil)
            return
        }
        guard mapping.isValid else {
            validationLabel.stringValue = "Choose a real key and supported modifiers before saving."
            validationLabel.isHidden = false
            return
        }
        validationLabel.isHidden = true
        onChange(mapping)
    }
}

private final class KeyRecorderButton: NSButton {
    var onKeyEvent: ((NSEvent) -> Bool)?
    var onFocusLost: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyEvent?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEvent?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            onFocusLost?()
        }
        return didResign
    }
}
