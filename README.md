# Onda

Software nativo macOS per cattura, compositing e streaming/registrazione video in tempo reale. Pensato come alternativa a OBS Studio, ma costruito su misura per macOS con priorita' su **latenza minima** e **integrazione nativa** (Metal, ScreenCaptureKit, AVFoundation, VideoToolbox). Niente Electron, niente FFmpeg nel percorso critico.

> Stato: in sviluppo iniziale. Struttura modulare completa e compilante; pipeline di cattura/render/encode in fase di collegamento.

## Caratteristiche (direzione)

- **Multiview** di tutte le inquadrature della scena nel pannello principale.
- **Studio mode**: Preview e Program affiancati, con transizioni (taglio, dissolvenza, scorrimento) tra scene e inquadrature.
- Sorgenti: schermo/finestra (ScreenCaptureKit), webcam/capture card (AVFoundation), testo e immagini.
- Compositing su GPU via Metal, conversione pixel buffer -> texture zero-copy.
- **Mixer audio** con meter di livello, effetti (gate/compressore/EQ) realtime-safe.
- Encoding hardware H.264/HEVC via VideoToolbox; registrazione locale e streaming.
- **Camera virtuale** per usare l'output in altre app.

## Requisiti

- macOS 15+ (sviluppato su macOS 26, Apple Silicon M3 Pro).
- Swift 6.3+.
- Per build/firma/test completi: Xcode (Apple ID gratuito sufficiente).

## Build

```bash
# Build dei moduli e dell'app (basta Command Line Tools)
swift build

# Esecuzione (durante lo sviluppo)
swift run Onda

# Test e benchmark (richiedono Xcode installato)
swift test
```

## Architettura

Package SPM unico con moduli a dipendenze a senso unico:

- `Shared/OndaShared` — tipi valore condivisi (frame, formati, timing, log).
- `Core/CaptureEngine` — ScreenCaptureKit + AVFoundation.
- `Core/RenderEngine` — pipeline Metal, scene graph, compositor, display link.
- `Core/AudioEngine` — AVAudioEngine, mixing, effetti.
- `Core/OutputEngine` — VideoToolbox, registrazione, streaming.
- `Plugins/SourceProtocols`, `Plugins/FilterProtocols` — punti di estensione.
- `App/OndaApp` — UI AppKit (preview) + SwiftUI (pannelli secondari).

Dettagli e vincoli di performance: vedi [CLAUDE.md](CLAUDE.md).

## Installazione (release non notarizzata)

Onda e' distribuita come app firmata con certificato self-signed, **non notarizzata**. Al primo avvio macOS mostra l'avviso Gatekeeper. Per sbloccarla:

1. **Clic destro sull'app -> Apri**, poi conferma nel dialogo.
   In alternativa: Impostazioni di Sistema -> Privacy e Sicurezza -> "Apri comunque".
2. Oppure da terminale, per rimuovere l'attributo di quarantena:

   ```bash
   xattr -cr /Applications/Onda.app
   ```

Al primo utilizzo l'app chiedera' i permessi **Registrazione schermo**, **Fotocamera** e **Microfono**: vanno concessi in Impostazioni di Sistema -> Privacy e Sicurezza.

## Licenza

Uso personale. Nessuna dipendenza a pagamento.
