import os

/// Wrapper leggero attorno a `os_unfair_lock` con indirizzo stabile (allocato su
/// heap), per proteggere sezioni critiche minime sui path video (NON audio
/// realtime, dove anche questo lock e' vietato — vedi CLAUDE.md).
public final class UnfairLock: @unchecked Sendable {
    private let _lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)

    public init() {
        _lock.initialize(to: os_unfair_lock())
    }

    deinit {
        _lock.deinitialize(count: 1)
        _lock.deallocate()
    }

    @inline(__always)
    public func locked<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(_lock)
        defer { os_unfair_lock_unlock(_lock) }
        return body()
    }
}
