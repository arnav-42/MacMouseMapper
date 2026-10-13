import Foundation

public struct MappingResolver: Sendable {
    public var configuration: AppConfiguration

    public init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    /// Resolution is intentionally small and deterministic: an enabled mapping
    /// for the active bundle wins, then an enabled global mapping, otherwise the
    /// source event remains untouched.
    public func resolve(button: SideButton, activeBundleIdentifier: String?) -> ButtonMapping? {
        guard configuration.isEnabled else { return nil }

        if let bundleIdentifier = activeBundleIdentifier,
           let appOverride = configuration.appOverrides.first(where: { $0.bundleIdentifier == bundleIdentifier }),
           let overrideMapping = appOverride.mappings.mapping(for: button),
           overrideMapping.isUsable {
            return overrideMapping
        }

        if let globalMapping = configuration.globalMappings.mapping(for: button), globalMapping.isUsable {
            return globalMapping
        }
        return nil
    }
}

public enum PressPhase: Equatable, Sendable {
    case down
    case up
}

public enum EventHandlingResult: Equatable, Sendable {
    case passThrough
    case suppress
    case execute(ButtonMapping, phase: PressPhase)

    public var suppressesSourceEvent: Bool {
        switch self {
        case .passThrough: return false
        case .suppress, .execute: return true
        }
    }
}

/// Tracks a physical press so an action fires once and a remapped mouse button
/// receives a coherent down/up pair even if active-app state changes mid-press.
public struct PressTracker: Sendable {
    private var activeMappings: [SideButton: ButtonMapping] = [:]

    public init() {}

    public mutating func handle(
        button: SideButton,
        phase: PressPhase,
        resolvedMapping: ButtonMapping?
    ) -> EventHandlingResult {
        switch phase {
        case .down:
            guard let mapping = resolvedMapping, mapping.isUsable else {
                return .passThrough
            }
            guard activeMappings[button] == nil else {
                // A repeated down from the same physical press is suppressed,
                // but does not trigger a second keyboard shortcut or gesture.
                return .suppress
            }
            activeMappings[button] = mapping
            return .execute(mapping, phase: .down)

        case .up:
            guard let mapping = activeMappings.removeValue(forKey: button) else {
                // There is no generated action to release. Passing this event
                // through avoids swallowing an unrelated/missed physical press.
                return .passThrough
            }
            return .execute(mapping, phase: .up)
        }
    }

    public var activePressCount: Int {
        activeMappings.count
    }
}
