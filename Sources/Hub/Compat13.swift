import Foundation

// macOS 13: MainActor.assumeIsolated arrived in macOS 14. These callers already run on the main thread.
extension MainActor {
    static func assumeIsolated<T>(_ operation: @MainActor () throws -> T) rethrows -> T {
        try withoutActuallyEscaping(operation) { try unsafeBitCast($0, to: (() throws -> T).self)() }
    }
}
