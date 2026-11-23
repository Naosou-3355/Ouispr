// OuisprApp/Views/PersonaOrb/PersonaOrbView.swift
// The character orb that stands for the voice assistant, drawn by a Metal shader.
import MetalKit
import OuisprCore
import SwiftUI

/// Ouispr's face: a glass orb with a rainbow ring and two eyes (direction "Personnage",
/// chosen by Alex on the bench of 23 Nov 2026). It replaces `ParticleSphereView` on Home
/// and the recording screen, with the same parameters.
///
/// WHY a shader: every layer (ring, strands, silk, eyes) is a soft distance field. A
/// Canvas would rebuild thousands of paths a frame; the GPU evaluates the picture per
/// pixel in one pass. WHY an `MTKView` and not SwiftUI's `colorEffect`: `colorEffect`
/// needs a precompiled `.metal` file (see `PersonaOrbShader`), and an `MTKView` lets
/// the display link stop outright when the orb is paused, with no SwiftUI body re-run
/// per frame.
///
/// Decorative: the stage is always written next to it, so VoiceOver skips it.
struct PersonaOrbView: View {
    let mood: ParticleSphereMood
    var voiceLevel: Double = 0
    var isPaused: Bool = false

    @State private var driver: PersonaOrbDriver

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(mood: ParticleSphereMood, voiceLevel: Double = 0, isPaused: Bool = false, sharesMotion: Bool = false) {
        self.mood = mood
        self.voiceLevel = voiceLevel
        self.isPaused = isPaused
        _driver = State(initialValue: sharesMotion ? PersonaOrbDriver.shared : PersonaOrbDriver())
    }

    var body: some View {
        // No frames while hidden, in the background, or standing still under Reduce
        // Motion (outside listening, where the brightness still follows the voice).
        let paused = isPaused || scenePhase != .active || (reduceMotion && mood != .listening)
        PersonaOrbMetalView(
            driver: driver,
            state: .init(mood: mood, voiceLevel: voiceLevel, reduceMotion: reduceMotion),
            paused: paused
        )
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What the orb is showing, read by the renderer on every frame.
struct PersonaOrbState: Equatable {
    var mood: ParticleSphereMood
    var voiceLevel: Double
    var reduceMotion: Bool
}

private struct PersonaOrbMetalView: UIViewRepresentable {
    let driver: PersonaOrbDriver
    let state: PersonaOrbState
    let paused: Bool

    func makeCoordinator() -> PersonaOrbRenderer {
        PersonaOrbRenderer(driver: driver)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: PersonaOrbRenderer.device)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        context.coordinator.state = state
        apply(paused: paused, to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.state = state
        apply(paused: paused, to: view)
    }

    private func apply(paused: Bool, to view: MTKView) {
        // A paused view draws once on demand (a mood change under Reduce Motion, or the
        // frame it stops on) and asks for nothing more.
        view.isPaused = paused
        view.enableSetNeedsDisplay = paused
        if paused { view.setNeedsDisplay() }
    }
}

/// Owns the GPU pipeline and draws a frame from the driver.
final class PersonaOrbRenderer: NSObject, MTKViewDelegate {
    static let device = MTLCreateSystemDefaultDevice()

    /// Compiled once per launch and shared by every orb.
    private static let pipeline: (MTLRenderPipelineState, MTLCommandQueue)? = {
        guard let device else { return nil }
        do {
            let library = try device.makeLibrary(source: PersonaOrbShader.source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "personaOrbVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "personaOrbFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            guard let queue = device.makeCommandQueue() else { return nil }
            return (try device.makeRenderPipelineState(descriptor: descriptor), queue)
        } catch {
            assertionFailure("Persona orb shader: \(error)")
            return nil
        }
    }()

    private let driver: PersonaOrbDriver
    var state = PersonaOrbState(mood: .resting, voiceLevel: 0, reduceMotion: false)

    init(driver: PersonaOrbDriver) {
        self.driver = driver
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let (pipeline, queue) = Self.pipeline,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        let frame = driver.frame(
            at: Date(),
            mood: state.mood,
            voiceLevel: state.voiceLevel,
            reduceMotion: state.reduceMotion,
            advancing: !view.isPaused
        )
        var uniforms = OrbUniforms(
            a: frame.a, b: frame.b, c: frame.c, d: frame.d,
            size: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OrbUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }
}

/// Mirrors the shader's `OrbUniforms`: four float4 then a float2, padded to 80 bytes
/// on both sides.
private struct OrbUniforms {
    var a: SIMD4<Float>
    var b: SIMD4<Float>
    var c: SIMD4<Float>
    var d: SIMD4<Float>
    var size: SIMD2<Float>
}
