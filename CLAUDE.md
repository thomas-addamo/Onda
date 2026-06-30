# CLAUDE.md

Questo file fornisce contesto a Claude Code per lavorare su questo progetto. Leggilo per intero prima di scrivere codice.

> Nota di stile: i commenti nel codice e in questi documenti usano la convenzione ASCII con apostrofo (es. "puo'", "e'", "piu'", "proprieta'") perche' i caratteri accentati possono corrompersi nel flusso di scrittura degli strumenti. Mantenere questa convenzione.

## Panoramica del progetto

Software nativo macOS per cattura, compositing e streaming/registrazione video in tempo reale, paragonabile a OBS Studio ma sviluppato su misura, con priorita' assoluta su **latenza minima** e **integrazione nativa con macOS** (no Electron, no Chromium, no stack web per il core).

Nome progetto: **Onda**
Bundle identifier: `com.onda.app`
Target: solo uso personale, distribuzione locale + GitHub Release pubblica (no App Store).

L'obiettivo non e' clonare OBS ma **superarlo**: tutto cio' che fa OBS va bene come base, ma l'interfaccia deve essere piu' professionale e al tempo stesso semplice (non banale), e si possono aggiungere funzionalita' a discrezione.

## Vincoli non negoziabili

- **Niente Electron, niente WebView per il rendering video.** Il compositing video deve avvenire su GPU via Metal, mai tramite DOM/Canvas/WebGL.
- **Niente FFmpeg per cattura o encoding.** Cattura e encoding devono usare framework Apple nativi e hardware-accelerati (vedi stack sotto). FFmpeg/librerie esterne sono accettabili solo per muxing/protocollo di output (es. RTMP), mai nel percorso cattura -> render -> encode.
- **Niente operazioni sincrone bloccanti nel render loop o nel capture callback.** Qualsiasi I/O, allocazione pesante, o lavoro non deterministico va spostato fuori dal thread di rendering/cattura.
- **Niente allocazioni per-frame evitabili.** Pixel buffer, texture, encoder buffer devono essere riusati/pool-ati, non allocati ad ogni frame.
- **Zero costi.** Nessuna dipendenza, libreria o servizio a pagamento. Apple ID gratuito (personal team) per firma/esecuzione locale.

## Stack tecnologico

| Ambito | Tecnologia |
|---|---|
| Linguaggio | Swift (Swift 6, strict concurrency dove possibile) |
| UI principale / preview | AppKit (controllo diretto su layer e refresh) |
| UI pannelli secondari (impostazioni, mixer audio) | SwiftUI, solo per UI non critica in termini di latenza |
| Cattura schermo/finestre | ScreenCaptureKit (macOS 13+) |
| Cattura webcam / capture card / input esterni | AVFoundation (AVCaptureSession) |
| Audio: routing, mixing, monitor | CoreAudio + AVAudioEngine |
| Effetti audio (noise gate, compressore, EQ) | AudioUnit (AUv3 dove possibile) |
| Compositing video (scene, overlay, transizioni) | Metal, pipeline diretta |
| Conversione pixel buffer -> texture | CVMetalTextureCache (mai conversioni manuali per frame) |
| Encoding hardware (H.264/HEVC) | VideoToolbox |
| Output streaming (RTMP o altro protocollo) | Client minimale scritto ad-hoc, oppure libreria esterna isolata solo nel modulo Output |
| Persistenza configurazione (scene, sorgenti, profili) | JSON locale via Codable (scelta iniziale: niente dipendenze, diff-abile, versionabile; SwiftData valutabile in seguito) |
| Package management | Swift Package Manager |

## Architettura

Moduli SPM separati, con responsabilita' isolate e dipendenze a senso unico. Implementati come target di un singolo package (`Package.swift`) con path personalizzati, cosi' ogni modulo compila/testa in isolamento ma il repo resta unico.

```
Shared/
  OndaShared/          -> tipi valore condivisi (VideoFrame, VideoFormat, timing, log)
Core/
  CaptureEngine/       -> wrapping di ScreenCaptureKit e AVFoundation, espone VideoFrame/CVPixelBuffer
  RenderEngine/        -> pipeline Metal, scene graph, compositing, transizioni, display link
  AudioEngine/         -> routing, mixing, AVAudioEngine graph, AudioUnit host
  OutputEngine/        -> encoding (VideoToolbox) + muxing/registrazione/streaming
Plugins/
  SourceProtocols/     -> protocollo CaptureSource e implementazioni concrete
  FilterProtocols/     -> protocolli VideoFilter / AudioFilter e implementazioni concrete
App/
  OndaApp/             -> finestra principale (AppKit), pannelli (SwiftUI), settings
Tests/
  LatencyBenchmarks/   -> misurazione frame time end-to-end (swift-testing)
  UnitTests/           -> logica non realtime (swift-testing)
```

Grafo dipendenze (a senso unico):
`OndaShared` <- tutto. `SourceProtocols`/`FilterProtocols` <- `OndaShared`. `CaptureEngine` <- `SourceProtocols`. `RenderEngine` <- `FilterProtocols`. `OutputEngine` <- `RenderEngine`. `OndaApp` <- tutti.

### Strategia strict concurrency

- Moduli di pura logica/protocolli (`OndaShared`, `SourceProtocols`, `FilterProtocols`) -> Swift 6 language mode (strict).
- Moduli che incapsulano framework non-Sendable (Metal/AVFoundation/AppKit/VideoToolbox) -> Swift 5 mode per ora, da migrare a Swift 6 incrementalmente.

### Protocolli chiave

Ogni nuova sorgente video/audio implementa `CaptureSource` (vedi `Plugins/SourceProtocols`):

```swift
protocol CaptureSource: AnyObject, Sendable {
    var id: UUID { get }
    var kind: CaptureSourceKind { get }
    var format: VideoFormat? { get }
    func setFrameHandler(_ handler: @escaping FrameHandler)
    func start() async throws
    func stop()
}
```

I frame sono consegnati via callback (`FrameHandler`) su queue dedicata ad alta priorita', mai polling bloccante ne' AsyncStream (overhead per frame). `start()`/`stop()` non sono path hot: `async` li' e' lecito.

Ogni effetto/filtro video implementa `VideoFilter`:

```swift
protocol VideoFilter: AnyObject {
    var name: String { get }
    var isEnabled: Bool { get set }
    func apply(to texture: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture
}
```

Questo permette di aggiungere nuove sorgenti o filtri senza toccare il core di rendering/cattura.

## Convenzioni di codice

- **Commenti in italiano** (ASCII con apostrofo), codice in inglese secondo convenzione Swift standard.
- Codice pulito, leggibile, evitare over-engineering: soluzioni dirette, niente astrazioni premature.
- Naming esplicito, niente abbreviazioni criptiche.
- Ogni modulo deve poter essere compilato e testato isolatamente.
- Evitare force-unwrap (`!`) nel percorso di cattura/rendering: gestire gli errori esplicitamente, un crash nel render loop e' inaccettabile.

## Vincoli di performance critici

- Misurare sempre il **frame time end-to-end** (cattura -> composizione -> encode) prima e dopo modifiche rilevanti.
- Target indicativo: frame time entro il budget del framerate scelto (es. <=16.6ms per 60fps), con margine.
- Il render loop gira su thread/queue dedicato ad alta priorita' (`DispatchQoS.userInteractive` o equivalente), mai sul main thread.
- Ogni feature che tocca cattura/render/encode va accompagnata da un benchmark in `Tests/LatencyBenchmarks/`.
- I pixel buffer da ScreenCaptureKit/AVFoundation arrivano IOSurface-backed: mappali direttamente a texture Metal (CVMetalTextureCache) senza copie intermedie.

## Ottimizzazione macOS-specifica e anti-lag

Prioritaria quanto i vincoli non negoziabili.

### Audio realtime-safe

Il render callback di AVAudioEngine/AudioUnit gira su un thread realtime con vincoli durissimi: **nessuna allocazione, nessun lock, nessuna chiamata che attivi ARC retain/release, nessuna I/O, nessun String/Array che alloca** dentro il blocco di rendering audio. I dati per il render block vanno preparati fuori dal thread realtime e passati via strutture lock-free (ring buffer atomico) o `os_unfair_lock` solo se strettamente necessario, sezioni critiche minime. Una violazione causa click/drop, non semplice "lag".

### Threading: GCD vs Swift Concurrency

Per i percorsi hot (cattura, compositing, encode, audio) **non usare Swift Concurrency strutturata (`async/await`, `actor`)**: lo scheduler cooperativo non garantisce priorita' realtime deterministiche. Usare `DispatchQueue` con `DispatchQoS.userInteractive` (o `pthread` + `thread_policy_set` con `THREAD_TIME_CONSTRAINT_POLICY` per il render loop principale se necessario). Riservare `async/await`/`actor` a UI, persistenza, networking non realtime.

### App Nap e throttling

Dichiarare attivita' critica con `ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: ...)` per tutta la durata di una sessione di cattura/streaming, rilasciandola solo a fine sessione. (Gia' fatto in `AppDelegate`.)

### Sincronizzazione col refresh

Usare display link per sincronizzare il render loop al refresh reale. Preview a refresh nativo; encode/output al framerate configurato (disaccoppiati). NB: `CVDisplayLink` e' deprecato da macOS 15 (warning attivi in `DisplayLinkDriver`); migrazione pianificata verso `NSView/NSScreen.displayLink(target:selector:)` su un thread dedicato.

### Memoria nei path critici

- Pool di buffer riutilizzabili per pixel buffer, texture, audio buffer: mai alloc/dealloc per-frame.
- Preferire value type dove possibile; minimizzare retain/release per frame su risorse Metal/GPU.
- Monitorare la pressione di memoria e degradare gracefully (es. ridurre risoluzione di un layer) invece di swap/crash.

### UI mai sul percorso critico

Main thread e AppKit/SwiftUI mai toccati in modo sincrono dal render/capture loop. Lo stato UI (contatori, meter, preview) si aggiorna per campionamento (es. 30Hz) postando dati pre-calcolati via `DispatchQueue.main.async`.

### Profiling obbligatorio

Prima di chiudere una feature su cattura/render/audio/encode, profilare con Instruments: **Time Profiler**, **Metal System Trace**, **Allocations**, e per l'audio il template **Audio**. Annotare i risultati nel benchmark corrispondente.

### Termico e consumo (M3 Pro)

Encoding sempre via VideoToolbox hardware (Media Engine), mai software, per evitare throttling termico. Testare sessioni realistiche (30-60 min) con `powermetrics`/Activity Monitor, non solo run brevi.

## Permessi macOS richiesti

A runtime, indipendentemente dalla firma:

- **Screen Recording** (ScreenCaptureKit)
- **Camera** (AVFoundation)
- **Microphone** (AVAudioEngine)

Dichiarare in Info.plist (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`). Gestire lo stato "permesso negato" con messaggio chiaro, mai crash.

## Build, firma e distribuzione

- Build via Xcode con **Apple ID gratuito (personal team)**, nessun Apple Developer Program.
- Firma stabile con **certificato self-signed** creato in Keychain Access (Certificate Assistant -> Create a Certificate -> Code Signing), riusato per tutte le release (i permessi TCC sono legati all'identita' di firma: firma instabile = riconcessione permessi ad ogni update).
- Bypass Gatekeeper una tantum (clic destro -> Apri, oppure `xattr -cr`).
- Script riproducibile in `Scripts/build_and_sign.sh`.

## Stato ambiente di sviluppo (giugno 2026)

- macOS 26.5 (Tahoe) su Apple M3 Pro.
- Swift 6.3.2 (toolchain Command Line Tools).
- **Xcode.app non ancora installato**: `swift build` dei moduli e dell'app funziona; `swift test` (swift-testing) richiede Xcode per il plugin macro. Il workflow `.app` bundle + Info.plist + entitlements + firma TCC arriva con Xcode.

## Distribuzione su GitHub

Repository pubblico, gratuito, senza Apple Developer Program (no notarizzazione). 

### Build automatica con GitHub Actions

Runner macOS gratuiti e illimitati sui repo pubblici. Workflow (`.github/workflows/release.yml`):
- Trigger su push di un tag `v*`.
- Build Release con `xcodebuild`.
- Firma col certificato self-signed importato come secret (`.p12` base64, mai in chiaro).
- Creazione `.dmg`/`.zip` e upload come asset della Release.

### Istruzioni Gatekeeper nel README

L'app non e' notarizzata: il README deve spiegare come sbloccarla (clic destro -> Apri, oppure `xattr -cr /Applications/Onda.app`).

## Funzionalita' del software

Specificate in conversazione, modulo per modulo, man mano che il progetto procede. Direzione UI: pannello principale con **multiview** di tutte le inquadrature della scena, Preview/Program (studio mode), transizioni tra scene/inquadrature, overlay testo e media, **mixer audio**, pannello di controllo (Avvia diretta, Registra, **Camera virtuale**, impostazioni).

## Note operative per Claude Code

- Prima di implementare una feature che tocca `Core/RenderEngine`, `Core/CaptureEngine` o `Core/AudioEngine`, proporre un breve piano (quali protocolli, dove si inserisce nella pipeline) prima di scrivere codice.
- Non introdurre nuove dipendenze esterne (SPM o altro) senza discuterne.
- Mantenere i moduli disaccoppiati: `App/UI` passa solo da interfacce pubbliche pulite, mai da interni di `RenderEngine`.

## Testing

- Test unitari per logica non realtime (parsing config, gestione scene, stato UI).
- Benchmark di latenza per ogni componente del percorso critico.
- Ogni claim di performance va supportato da un numero misurato, mai da impressioni soggettive.
