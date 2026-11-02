import Foundation

/// Before/after switch for the motion prototype. Absent flags keep today's
/// behavior, so one build can record both.
///
/// `-motionProto 1` turns every item on. `-motionProto.<item> 1` turns one
/// item on, and `-motionProto.<item> 0` turns that item off even when the
/// master switch is on. Accepted values: 1/0, true/false, yes/no, on/off.
///
/// Items: `skeleton`, `silent`, `drag`, `cover`, `transitions`, `reduceMotion`.
nonisolated enum MotionProto {

    nonisolated enum Item: String, Sendable {
        case skeleton
        case silent
        case drag
        case cover
        case transitions
        case reduceMotion
    }

    nonisolated static func isEnabled(
        _ item: Item,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if let override = flag(named: "-motionProto.\(item.rawValue)", in: arguments) {
            return override
        }
        return flag(named: "-motionProto", in: arguments) ?? false
    }

    /// Last occurrence wins, so a later launch argument can override.
    private nonisolated static func flag(named name: String, in arguments: [String]) -> Bool? {
        var resolved: Bool?
        var index = 0
        while index < arguments.count {
            if arguments[index] == name, index + 1 < arguments.count, let value = parse(arguments[index + 1]) {
                resolved = value
                index += 2
                continue
            }
            index += 1
        }
        return resolved
    }

    private nonisolated static func parse(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: return nil
        }
    }
}

/// What a list shows while a fetch is in flight. Skeleton replaces a blank
/// page; a silent refresh keeps rows that are already on screen.
nonisolated enum MotionLoading {

    struct Chrome: Equatable, Sendable {
        var showSkeleton: Bool
        var showBlockingSpinner: Bool
        var showSubtleIndicator: Bool
    }

    nonisolated static func chrome(
        isLoading: Bool,
        hasContent: Bool,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Chrome {
        let skeleton = MotionProto.isEnabled(.skeleton, arguments: arguments) && isLoading && !hasContent
        let silent = MotionProto.isEnabled(.silent, arguments: arguments) && isLoading && hasContent
        return Chrome(
            showSkeleton: skeleton,
            showBlockingSpinner: isLoading && !skeleton && !silent,
            showSubtleIndicator: silent
        )
    }
}
