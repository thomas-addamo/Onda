import os

/// Logger centralizzato basato su `os.Logger` (unified logging), a costo quasi
/// nullo quando il livello non e' attivo. Mai usare `print` nei path critici.
///
/// I sottosistemi seguono i moduli dell'architettura cosi' da poterli filtrare
/// in Console.app o con `log stream --predicate`.
public enum OndaLog {
    public static let subsystem = "com.onda.app"

    public static let capture = Logger(subsystem: subsystem, category: "Capture")
    public static let render = Logger(subsystem: subsystem, category: "Render")
    public static let audio = Logger(subsystem: subsystem, category: "Audio")
    public static let output = Logger(subsystem: subsystem, category: "Output")
    public static let app = Logger(subsystem: subsystem, category: "App")
}
