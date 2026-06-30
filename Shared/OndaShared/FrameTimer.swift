import Foundation

/// Misurazione ad alta risoluzione del tempo, basata su `mach_absolute_time`,
/// per i benchmark di latenza del percorso critico (cattura -> render -> encode).
///
/// Non alloca e non prende lock: utilizzabile anche vicino ai path hot.
public enum HighResClock {
    /// Fattore di conversione tick -> nanosecondi, calcolato una volta sola.
    private static let nanosPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    /// Istante corrente in tick grezzi (`mach_absolute_time`).
    @inline(__always)
    public static func nowTicks() -> UInt64 {
        mach_absolute_time()
    }

    /// Converte un intervallo in tick a millisecondi.
    @inline(__always)
    public static func millis(fromTicks ticks: UInt64) -> Double {
        Double(ticks) * nanosPerTick / 1_000_000.0
    }

    /// Millisecondi trascorsi da un istante `startTicks` ad ora.
    @inline(__always)
    public static func elapsedMillis(since startTicks: UInt64) -> Double {
        millis(fromTicks: mach_absolute_time() &- startTicks)
    }
}

/// Accumulatore di statistiche sul tempo per frame (min/max/media/percentili
/// approssimati). Pensato per essere aggiornato fuori dai path hot, ad esempio
/// dopo aver raccolto i campioni in un buffer.
public struct FrameTimingStats: Sendable {
    public private(set) var count: Int = 0
    public private(set) var minMillis: Double = .greatestFiniteMagnitude
    public private(set) var maxMillis: Double = 0
    public private(set) var totalMillis: Double = 0

    public init() {}

    public mutating func add(_ millis: Double) {
        count += 1
        totalMillis += millis
        if millis < minMillis { minMillis = millis }
        if millis > maxMillis { maxMillis = millis }
    }

    public var averageMillis: Double {
        count > 0 ? totalMillis / Double(count) : 0
    }

    /// Verifica se il tempo medio rientra nel budget del frame rate indicato.
    public func withinBudget(forFrameRate fps: Int) -> Bool {
        guard fps > 0 else { return false }
        return averageMillis <= (1000.0 / Double(fps))
    }
}
