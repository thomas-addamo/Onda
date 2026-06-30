import Foundation
import OndaShared

/// Tipo di transizione tra scene.
public enum TransitionKind: Sendable, Equatable {
    case cut          // cambio istantaneo
    case fade         // dissolvenza incrociata
}

/// Gestisce le scene e il cambio scena con transizioni. Thread-safe: lo stato e'
/// protetto da `UnfairLock` perche' letto dal render loop e mutato dalla UI.
///
/// Per ogni frame fornisce un "piano di rendering": l'elenco delle scene da
/// comporre con la rispettiva opacita' globale (durante una dissolvenza ci sono
/// due scene, altrimenti una sola).
public final class SceneController: @unchecked Sendable {

    /// Una scena da comporre con la sua opacita' globale (0...1).
    public struct ScenePass {
        public let scene: Scene
        public let globalOpacity: Float
    }

    private struct ActiveTransition {
        let from: UUID
        let to: UUID
        let startTicks: UInt64
        let duration: Double
        let kind: TransitionKind
    }

    private let lock = UnfairLock()
    private var scenes: [UUID: Scene] = [:]
    private var order: [UUID] = []
    private var activeID: UUID?
    private var transition: ActiveTransition?

    public init(scenes: [Scene], activeID: UUID?) {
        for scene in scenes {
            self.scenes[scene.id] = scene
            self.order.append(scene.id)
        }
        self.activeID = activeID ?? scenes.first?.id
    }

    /// Avvia il cambio verso `sceneID`. `cut` o durata <= 0 = cambio immediato.
    public func switchTo(_ sceneID: UUID, kind: TransitionKind = .fade, duration: Double = 0.4) {
        lock.locked {
            guard scenes[sceneID] != nil, sceneID != activeID else { return }
            if kind == .cut || duration <= 0 || activeID == nil {
                activeID = sceneID
                transition = nil
            } else {
                transition = ActiveTransition(
                    from: activeID!, to: sceneID,
                    startTicks: HighResClock.nowTicks(),
                    duration: duration, kind: kind
                )
            }
        }
    }

    /// Piano di rendering per l'istante corrente. Avanza/chiude la transizione.
    public func renderPlan() -> [ScenePass] {
        lock.locked {
            guard let transition else {
                if let activeID, let scene = scenes[activeID] {
                    return [ScenePass(scene: scene, globalOpacity: 1)]
                }
                return []
            }

            let elapsed = HighResClock.elapsedMillis(since: transition.startTicks) / 1000.0
            let t = Float(min(1.0, elapsed / transition.duration))

            if t >= 1.0 {
                // Transizione completata.
                activeID = transition.to
                self.transition = nil
                if let scene = scenes[transition.to] {
                    return [ScenePass(scene: scene, globalOpacity: 1)]
                }
                return []
            }

            var passes: [ScenePass] = []
            if let from = scenes[transition.from] {
                passes.append(ScenePass(scene: from, globalOpacity: 1))
            }
            if let to = scenes[transition.to] {
                passes.append(ScenePass(scene: to, globalOpacity: t))
            }
            return passes
        }
    }

    public var activeSceneID: UUID? { lock.locked { activeID } }

    public var sceneOrder: [Scene] {
        lock.locked { order.compactMap { scenes[$0] } }
    }

    /// Aggiorna/aggiunge una scena (es. dopo modifiche dalla UI).
    public func upsert(_ scene: Scene) {
        lock.locked {
            if scenes[scene.id] == nil { order.append(scene.id) }
            scenes[scene.id] = scene
        }
    }
}
