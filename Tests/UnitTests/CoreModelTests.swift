import Testing
import Foundation
@testable import OndaShared
@testable import RenderEngine

@Suite("Modelli core")
struct CoreModelTests {

    @Test("Frame budget coerente col frame rate")
    func frameBudget() {
        #expect(abs(VideoFormat.hd1080p60.frameBudget - 1.0 / 60.0) < 1e-9)
        #expect(abs(VideoFormat.hd1080p30.frameBudget - 1.0 / 30.0) < 1e-9)
    }

    @Test("Statistiche di timing entro il budget")
    func frameTimingWithinBudget() {
        var stats = FrameTimingStats()
        for _ in 0..<100 { stats.add(10.0) }
        #expect(stats.count == 100)
        #expect(abs(stats.averageMillis - 10.0) < 1e-9)
        #expect(stats.withinBudget(forFrameRate: 60))
        #expect(!stats.withinBudget(forFrameRate: 120))
    }

    @Test("Min e max dei tempi")
    func frameTimingMinMax() {
        var stats = FrameTimingStats()
        for v in [5.0, 12.0, 8.0, 20.0, 3.0] { stats.add(v) }
        #expect(stats.minMillis == 3.0)
        #expect(stats.maxMillis == 20.0)
    }

    @Test("Ordine dei layer nella scena")
    func sceneLayerOrdering() {
        let s1 = UUID(), s2 = UUID()
        var scene = Scene(name: "Test")
        scene.layers = [
            SceneLayer(name: "Sfondo", sourceID: s1),
            SceneLayer(name: "Overlay", sourceID: s2),
        ]
        #expect(scene.layers.count == 2)
        #expect(scene.layers.first?.name == "Sfondo")
        #expect(scene.layers.last?.transform.opacity == 1.0)
    }

    @Test("Transform fullscreen di default")
    func layerTransformFullscreen() {
        let t = LayerTransform.fullscreen
        #expect(t.rect.width == 1)
        #expect(t.rect.height == 1)
        #expect(t.opacity == 1.0)
    }
}
