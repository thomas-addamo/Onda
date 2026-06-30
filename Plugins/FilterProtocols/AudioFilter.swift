import Foundation

/// Effetto/filtro audio (noise gate, compressore, EQ, ...).
///
/// L'elaborazione vera avviene nel render block realtime dell'AudioEngine, sotto
/// vincoli durissimi (no alloc, no lock, no ARC: vedi CLAUDE.md). Questo
/// protocollo descrive solo configurazione e parametri, preparati FUORI dal
/// thread realtime; l'AudioEngine traduce i parametri in stato lock-free letto
/// dal render block.
public protocol AudioFilter: AnyObject {
    var name: String { get }
    var isEnabled: Bool { get set }

    /// Numero di parametri esposti alla UI (gain, threshold, ratio, ...).
    var parameterCount: Int { get }
}
