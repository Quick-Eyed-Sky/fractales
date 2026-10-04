// Fractales -- Metal rendering.
//
// Each frame: if the view changed, (1) refresh the reference orbit on the CPU when needed,
// (2) run the `iterate` kernel into a float texture of escape counts; then always (3) colour
// that texture into the window through the palette. While the view moves, (2) runs at half
// resolution so it keeps up, and a full-resolution pass follows as soon as it stops.

import Foundation
import Metal
import MetalKit
import QuartzCore

final class Renderer: NSObject, MTKViewDelegate {
    private let model: FractalModel
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let iteratePipeline: MTLComputePipelineState
    private let colorPipeline: MTLRenderPipelineState

    private var counts: MTLTexture?
    private var palette: MTLTexture?
    private var paletteLoaded = -1

    // Reference orbits (see Shaders.metal). B is A itself for the Mandelbrot-type formulas.
    private var orbitA: MTLBuffer?
    private var orbitB: MTLBuffer?
    private var lenA: UInt32 = 0
    private var lenB: UInt32 = 0
    private var refX = fc_num()
    private var refY = fc_num()
    private var refKey: ReferenceKey?

    private var computedRevision = -1
    private var computedSize = (0, 0)
    private var lastCommandBuffer: MTLCommandBuffer?
    private var settleScheduled = false

    static let bailout2: Float = 65536   // escape radius 256: smooth colours without bands

    init(model: FractalModel, device: MTLDevice) throws {
        self.model = model
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw RendererError.message(L("Pas de file de commandes Metal.")) }
        self.queue = queue

        guard let url = Bundle.main.url(forResource: "Shaders", withExtension: "metal"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw RendererError.message(L("Shaders.metal est introuvable dans l'appli. Reconstruis-la avec build_app.sh."))
        }
        let options = MTLCompileOptions()
        // Exact IEEE maths: the perturbation relies on small differences surviving.
        if #available(macOS 15.0, *) {
            options.mathMode = .safe
        } else {
            options.fastMathEnabled = false
        }
        let library = try device.makeLibrary(source: source, options: options)
        guard let iterate = library.makeFunction(name: "iterate"),
              let vertex = library.makeFunction(name: "colorVertex"),
              let fragment = library.makeFunction(name: "colorFragment") else {
            throw RendererError.message(L("Fonctions manquantes dans Shaders.metal."))
        }
        iteratePipeline = try device.makeComputePipelineState(function: iterate)

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        colorPipeline = try device.makeRenderPipelineState(descriptor: desc)
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.needsDisplay = true
    }

    func draw(in view: MTKView) {
        model.advanceAnimation(now: CACurrentMediaTime())
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer() else { return }

        let full = view.drawableSize
        let interacting = model.isInteracting
        let scale = interacting ? 0.5 : 1.0
        let width = max(1, Int(full.width * scale))
        let height = max(1, Int(full.height * scale))

        let mustCompute = model.revision != computedRevision || computedSize != (width, height) || counts == nil
        if mustCompute {
            encodeIterations(commandBuffer, width: width, height: height)
            computedRevision = model.revision
            computedSize = (width, height)
        }
        loadPaletteIfNeeded()

        if let counts = counts, let palette = palette,
           let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            var colors = fc_color_params(density: Float(model.colorDensity), offset: Float(model.colorOffset),
                                         insideR: 0, insideG: 0, insideB: 0)
            encoder.setRenderPipelineState(colorPipeline)
            encoder.setFragmentBytes(&colors, length: MemoryLayout<fc_color_params>.stride, index: 0)
            encoder.setFragmentTexture(counts, index: 0)
            encoder.setFragmentTexture(palette, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        if mustCompute {
            let model = self.model
            commandBuffer.addCompletedHandler { cb in
                let ms = (cb.gpuEndTime - cb.gpuStartTime) * 1000
                if let error = cb.error {
                    DispatchQueue.main.async { model.errorMessage = String(format: L("Erreur GPU : %@"), error.localizedDescription) }
                } else if ms > 0 {
                    DispatchQueue.main.async { model.lastRenderMilliseconds = ms }
                }
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        lastCommandBuffer = commandBuffer

        if model.isAnimating {
            DispatchQueue.main.async { view.needsDisplay = true }
        } else if interacting && !settleScheduled {
            // Once the view stops moving, draw it again at full resolution.
            settleScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak view] in
                self?.settleScheduled = false
                view?.needsDisplay = true
            }
        }
    }

    // MARK: - Iterations

    private func encodeIterations(_ commandBuffer: MTLCommandBuffer, width: Int, height: Int) {
        if counts == nil || counts!.width != width || counts!.height != height {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: width,
                                                                height: height, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .private
            counts = device.makeTexture(descriptor: desc)
        }
        guard let counts = counts else { return }

        let pixelSize = 2 * model.halfHeight / Double(height)
        let maxIter = model.maxIterations
        updateReference(pixelSize: pixelSize, maxIter: maxIter)
        guard let orbitA = orbitA, let orbitB = orbitB else { return }

        var centerX = model.centerX, centerY = model.centerY
        var p = fc_gpu_params()
        p.offsetX = Float(fc_diff_to_double(&centerX, &refX))
        p.offsetY = Float(fc_diff_to_double(&centerY, &refY))
        p.pixelSize = Float(pixelSize)
        p.ySign = Float(model.formula.ySign)
        p.fullWidth = UInt32(width); p.fullHeight = UInt32(height)
        p.originX = 0; p.originY = 0
        p.width = UInt32(width); p.height = UInt32(height)
        p.maxIter = UInt32(maxIter)
        p.formula = UInt32(model.formula.rawValue)
        p.julia = model.julia ? 1 : 0
        p.lenA = lenA; p.lenB = lenB
        p.bailout2 = Self.bailout2
        p.logPower = log(model.formula.power)

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(iteratePipeline)
        encoder.setBytes(&p, length: MemoryLayout<fc_gpu_params>.stride, index: 0)
        encoder.setBuffer(orbitA, offset: 0, index: 1)
        encoder.setBuffer(orbitB, offset: 0, index: 2)
        encoder.setTexture(counts, index: 0)
        let tw = iteratePipeline.threadExecutionWidth
        let th = max(1, iteratePipeline.maxTotalThreadsPerThreadgroup / tw)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
        encoder.endEncoding()
    }

    /// Recomputes the reference orbits when the formula, the Julia point, the iteration count or
    /// the precision changed, or when the view wandered too far from the reference point.
    private func updateReference(pixelSize: Double, maxIter: Int) {
        let limbs = Int(fc_limbs_for_pixel_size(pixelSize))
        let key = ReferenceKey(formula: model.formula.rawValue, julia: model.julia,
                               kx: model.juliaK.x, ky: model.juliaK.y, maxIter: maxIter)
        var centerX = model.centerX, centerY = model.centerY
        let dx = abs(fc_diff_to_double(&centerX, &refX))
        let dy = abs(fc_diff_to_double(&centerY, &refY))
        let far = max(dx, dy) > 2 * model.halfHeight
        if key == refKey && limbs <= refLimbs && !far && orbitA != nil { return }

        // The GPU may still be reading the old orbits.
        lastCommandBuffer?.waitUntilCompleted()

        let bytes = (maxIter + 1) * 2 * MemoryLayout<Float>.stride
        if orbitA == nil || orbitA!.length < bytes {
            orbitA = device.makeBuffer(length: bytes, options: .storageModeShared)
        }
        guard let a = orbitA else { return }
        refX = centerX
        refY = centerY
        var zero = fc_num()
        var kx = fc_num(), ky = fc_num()
        fc_from_double(&kx, model.juliaK.x)
        fc_from_double(&ky, model.juliaK.y)
        let formula = model.formula.rawValue
        let outA = a.contents().assumingMemoryBound(to: Float.self)
        if model.julia {
            if orbitB == nil || orbitB === orbitA || orbitB!.length < bytes {
                orbitB = device.makeBuffer(length: bytes, options: .storageModeShared)
            }
            guard let b = orbitB else { return }
            let outB = b.contents().assumingMemoryBound(to: Float.self)
            lenA = UInt32(fc_orbit(formula, &refX, &refY, &kx, &ky, Int32(limbs), Int32(maxIter), Double(Self.bailout2), outA))
            lenB = UInt32(fc_orbit(formula, &zero, &zero, &kx, &ky, Int32(limbs), Int32(maxIter), Double(Self.bailout2), outB))
        } else {
            lenA = UInt32(fc_orbit(formula, &zero, &zero, &refX, &refY, Int32(limbs), Int32(maxIter), Double(Self.bailout2), outA))
            orbitB = a
            lenB = lenA
        }
        refKey = key
        refLimbs = limbs
    }
    private var refLimbs = 0

    // MARK: - Palette

    private func loadPaletteIfNeeded() {
        let index = min(max(model.paletteIndex, 0), palettes.count - 1)
        guard index != paletteLoaded else { return }
        let count = 1024
        if palette == nil {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: count,
                                                                height: 1, mipmapped: false)
            desc.usage = [.shaderRead]
            palette = device.makeTexture(descriptor: desc)
        }
        let texels = palettes[index].texels(count: count)
        texels.withUnsafeBytes { raw in
            palette?.replace(region: MTLRegionMake2D(0, 0, count, 1), mipmapLevel: 0,
                             withBytes: raw.baseAddress!, bytesPerRow: count * 4)
        }
        paletteLoaded = index
    }
}

private struct ReferenceKey: Equatable {
    let formula: Int32
    let julia: Bool
    let kx: Double
    let ky: Double
    let maxIter: Int
}

enum RendererError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}
