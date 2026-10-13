import Foundation

/// The authorization state relevant to active remapping and generated events.
///
/// Accessibility is the user-facing device-control permission for the active
/// event tap. HID post-event access is retained as a tri-state diagnostic:
/// `.unknown` means no authorization result is available yet, so callbacks
/// conservatively pass physical mapped events through until `.granted`.
/// A known `.denied` result likewise prevents suppressing a physical mapped
/// event that the injector cannot replace.
public enum HIDPostEventAccess: Equatable, Sendable {
    case unknown
    case granted
    case denied
}

public struct PermissionSnapshot: Equatable, Sendable {
    public let accessibilityTrusted: Bool
    public let hidPostEventAccess: HIDPostEventAccess

    public init(
        accessibilityTrusted: Bool,
        hidPostEventAccess: HIDPostEventAccess = .unknown
    ) {
        self.accessibilityTrusted = accessibilityTrusted
        self.hidPostEventAccess = hidPostEventAccess
    }

    /// Whether the process may be able to create an active filtering tap.
    ///
    /// This is deliberately based only on AX. HID post access is an injection
    /// diagnostic and must never prevent an active tap attempt.
    public var hasActiveEventTapAccess: Bool {
        accessibilityTrusted
    }

    /// Whether generated events are currently authorized by the HID check.
    public var hasHIDPostEventAccess: Bool {
        hidPostEventAccess == .granted
    }

    /// Whether injection is known to be unavailable.
    public var isHIDPostEventAccessDenied: Bool {
        hidPostEventAccess == .denied
    }

}

/// One-shot restart policy for an explicit Accessibility grant flow.
///
/// A background status poll never starts this policy. A flow that starts while
/// already trusted does not restart, and one grant transition can consume the
/// restart at most once. A repair-launched process starts unconsumed because
/// its fresh-process prompt must observe the false-to-true grant transition
/// before launching the final clean process.
public struct AuthorizationRestartPolicy: Equatable, Sendable {
    private var awaitingGrant = false
    public private(set) var restartConsumed: Bool

    public init(launchedForRepair: Bool = false) {
        // Repair uses this process for the explicit prompt, so its one allowed
        // restart must not be consumed until Accessibility becomes trusted.
        restartConsumed = false
    }

    public var isAwaitingGrant: Bool {
        awaitingGrant
    }

    public mutating func beginExplicitGrant(currentlyTrusted: Bool) {
        guard !currentlyTrusted, !restartConsumed else { return }
        awaitingGrant = true
    }

    @discardableResult
    public mutating func observe(accessibilityTrusted: Bool) -> Bool {
        guard awaitingGrant, accessibilityTrusted, !restartConsumed else {
            return false
        }
        awaitingGrant = false
        restartConsumed = true
        return true
    }
}

