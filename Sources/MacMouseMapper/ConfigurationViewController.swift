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
        if isViewLoaded {
            rebuildContent()
        }
    }

    func setPermissionSnapshot(_ snapshot: PermissionSnapshot) {
        let changed = permissionSnapshot != snapshot
        permissionSnapshot = snapshot
        guard isViewLoaded else { return }
        if changed {
            rebuildContent()
        } else {
            updateStatusLabels()
        }
    }

    func setCaptureStatus(_ status: CaptureStatus) {
        let changed = captureStatus != status
        captureStatus = status
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
        accessFlowMessage = message
        guard isViewLoaded else { return }
        updateStatusLabels()
    }


    private func buildShell() {
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
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
        addSection(makeGlobalMappingsCard())
        addSection(makeOverridesCard())
        addSection(makeFooter())
        updateStatusLabels()
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
        let card = makeCard()
        let body = cardBody(card)
        let subtitle: String
        if captureStatus == .running {
            switch permissionSnapshot.hidPostEventAccess {
            case .granted:
                subtitle = "Global active filtering and generated actions are ready."
            case .denied:
                subtitle = "Capture is running, but generated actions are unavailable because HID post access is denied."
            case .unknown:
                subtitle = "Capture is running; generated actions are awaiting the HID post check."
            }
        } else if permissionSnapshot.accessibilityTrusted {
            subtitle = "Accessibility is trusted; checking the active event tap."
        } else {
            subtitle = "Allow Accessibility / Device Control for the active event filter."
        }
        body.addArrangedSubview(sectionHeading(
            icon: "lock.shield.fill",
            title: "System Access",
            subtitle: subtitle
        ))

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

        sideButtonStatusLabel = wrappingLabel("Last side button: None detected")
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

    private func makeGlobalMappingsCard() -> NSView {
        let card = makeCard()
        let body = cardBody(card)
        body.addArrangedSubview(sectionHeading(
            icon: "arrow.triangle.2.circlepath",
            title: "Global Mappings",
            subtitle: "These mappings apply everywhere unless an application override is active."
        ))
        body.addArrangedSubview(MappingEditorView(button: .button4, mapping: configuration.globalMappings.button4) { [weak self] mapping in
            self?.updateGlobal(mapping, for: .button4)
        })
        body.addArrangedSubview(MappingEditorView(button: .button5, mapping: configuration.globalMappings.button5) { [weak self] mapping in
            self?.updateGlobal(mapping, for: .button5)
        })
        return card
    }

    private func makeOverridesCard() -> NSView {
        let card = makeCard()
        let body = cardBody(card)
        body.addArrangedSubview(sectionHeading(
            icon: "rectangle.3.group.fill",
            title: "Application Overrides",
            subtitle: "Choose an application to give it mappings that take priority over the global defaults."
        ))
        let help = wrappingLabel("Overrides are matched by bundle identifier. An empty button mapping falls back to the global mapping.")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        body.addArrangedSubview(help)

        let controls = NSStackView()
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 9
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 9
        let addButton = NSButton(title: "Add Application…", target: self, action: #selector(addApplication(_:)))
        addButton.bezelStyle = .rounded
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        actionRow.addArrangedSubview(addButton)

        if !configuration.appOverrides.isEmpty {
            let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeApplication(_:)))
            removeButton.bezelStyle = .rounded
            removeButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            removeButton.imagePosition = .imageLeading
            actionRow.addArrangedSubview(removeButton)
        }
        controls.addArrangedSubview(actionRow)
        body.addArrangedSubview(controls)

        if !configuration.appOverrides.isEmpty {
            let picker = NSPopUpButton()
            picker.target = self
            picker.action = #selector(selectOverride(_:))
            for (index, override) in configuration.appOverrides.enumerated() {
                let item = picker.menu?.addItem(withTitle: "\(override.displayName)  (\(override.bundleIdentifier))", action: nil, keyEquivalent: "")
                item?.tag = index
            }
            picker.selectItem(at: 0)
            picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            picker.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true
            controls.addArrangedSubview(picker)

            let selected = configuration.appOverrides[0]
            let selectedLabel = wrappingLabel("Editing \(selected.displayName) · \(selected.bundleIdentifier)")
            selectedLabel.font = .systemFont(ofSize: 12, weight: .medium)
            selectedLabel.textColor = .secondaryLabelColor
            body.addArrangedSubview(selectedLabel)
            body.addArrangedSubview(MappingEditorView(button: .button4, mapping: selected.mappings.button4) { [weak self] mapping in
                self?.updateOverride(mapping, for: .button4, at: 0)
            })
            body.addArrangedSubview(MappingEditorView(button: .button5, mapping: selected.mappings.button5) { [weak self] mapping in
                self?.updateOverride(mapping, for: .button5, at: 0)
            })
        } else {
            controls.addArrangedSubview(NSTextField(labelWithString: "No application overrides yet"))
        }
        return card
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

    private func sectionHeading(icon: String, title: String, subtitle: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 11
        let image = iconView(icon, description: title, size: 22)
        image.contentTintColor = .controlAccentColor
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

    private func updateOverride(_ mapping: ButtonMapping?, for button: SideButton, at index: Int) {
        guard configuration.appOverrides.indices.contains(index) else { return }
        configuration.appOverrides[index].mappings.setMapping(mapping, for: button)
        notifyConfigurationChanged()
    }

    private func notifyConfigurationChanged() {
        configuration = configuration.sanitized()
        onConfigurationChanged?(configuration)
        updateStatusLabels()
    }

    private func updateStatusLabels() {
        guard accessibilityStatusLabel != nil,
              hidStatusLabel != nil,
              accessFlowStatusLabel != nil,
              captureStatusLabel != nil else { return }

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

        accessFlowStatusLabel.stringValue = accessFlowMessage
        accessFlowStatusLabel.isHidden = accessFlowMessage.isEmpty

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
        if let lastDetectedSideButton {
            sideButtonStatusLabel?.stringValue = "Last side button: \(lastDetectedSideButton.displayName)"
            sideButtonStatusLabel?.textColor = .secondaryLabelColor
        } else {
            sideButtonStatusLabel?.stringValue = "Last side button: None detected"
            sideButtonStatusLabel?.textColor = .secondaryLabelColor
        }
        remappingStatusLabel?.stringValue = configuration.isEnabled ? "Remapping active" : "Remapping paused"
        remappingStatusLabel?.textColor = configuration.isEnabled ? .systemGreen : .secondaryLabelColor
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
        onConfigurationChanged?(configuration)
        rebuildContent()
    }

    @objc private func selectOverride(_ sender: NSPopUpButton) {
        let selectedIndex = sender.selectedItem?.tag ?? 0
        guard configuration.appOverrides.indices.contains(selectedIndex), selectedIndex != 0 else { return }
        let selected = configuration.appOverrides.remove(at: selectedIndex)
        configuration.appOverrides.insert(selected, at: 0)
        onConfigurationChanged?(configuration)
        rebuildContent()
    }

    @objc private func removeApplication(_ sender: NSButton) {
        guard !configuration.appOverrides.isEmpty else { return }
        configuration.appOverrides.removeFirst()
        onConfigurationChanged?(configuration)
        rebuildContent()
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

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 9
        let title = NSTextField(labelWithString: button.displayName)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)

        modePopup.addItems(withTitles: ["Pass through", "Keyboard shortcut", "Another mouse button", "Gesture"])
        modePopup.target = self
        modePopup.action = #selector(modeChanged(_:))
        modePopup.widthAnchor.constraint(equalToConstant: 178).isActive = true
        enabledButton.target = self
        enabledButton.action = #selector(mappingChanged(_:))
        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearMapping(_:)))
        clearButton.bezelStyle = .rounded
        clearButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        clearButton.imagePosition = .imageLeading
        clearButton.setContentHuggingPriority(.required, for: .horizontal)

        header.addArrangedSubview(title)
        header.addArrangedSubview(modePopup)
        header.addArrangedSubview(enabledButton)
        header.addArrangedSubview(clearButton)
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
