import Testing
@testable import OndaShared

/// Benchmark di base sul percorso di misura della latenza. I benchmark che
/// toccano GPU/cattura reale (Compositor, texture mapping) vanno aggiunti man
/// mano che i moduli vengono collegati, annotando qui i risultati di Instruments
/// (Time Profiler / Metal System Trace / Allocations) come da CLAUDE.md.
@Suite("Benchmark latenza")
struct ClockBenchmarks {

    /// L'overhead della misura stessa deve essere trascurabile rispetto al
    /// budget di frame (es. <0.01ms), altrimenti falserebbe i benchmark reali.
    @Test("Overhead del clock trascurabile")
    func clockOverheadIsNegligible() {
        let iterations = 100_000
        let start = HighResClock.nowTicks()
        var sink: UInt64 = 0
        for _ in 0..<iterations {
            sink &+= HighResClock.nowTicks()
        }
        let elapsed = HighResClock.elapsedMillis(since: start)
        #expect(sink > 0)
        let perCall = elapsed / Double(iterations)
        #expect(perCall < 0.01, "Overhead per chiamata clock troppo alto: \(perCall)ms")
    }

    /// Esempio di raccolta statistiche su una serie di frame simulati.
    @Test("Aggregazione timing su frame simulati")
    func syntheticFrameTimingAggregation() {
        var stats = FrameTimingStats()
        for i in 0..<600 {
            let jitter = Double((i % 5)) * 0.5
            stats.add(8.0 + jitter)
        }
        #expect(stats.count == 600)
        #expect(stats.withinBudget(forFrameRate: 60))
        #expect(stats.maxMillis < 16.6)
    }
}
