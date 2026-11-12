import os

/// Read with:
///   /usr/bin/log show --last 10m --info --style compact --predicate 'subsystem == "local.hub.Hub"'
/// (plain `log` is shadowed by a shell function in this zsh setup).
enum Log {
    /// Item moves and every path that can trigger one.
    static let arrange = Logger(subsystem: "local.hub.Hub", category: "arrange")
    /// Section state changes (collapse/expand) and what caused them.
    static let state = Logger(subsystem: "local.hub.Hub", category: "state")
}
