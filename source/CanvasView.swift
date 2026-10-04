// Fractales -- the Metal view and everything the mouse, trackpad and keyboard do to it.

import AppKit
import MetalKit
import SwiftUI

final class CanvasView: MTKView {
    var model: FractalModel!
    var renderer: Renderer?   // MTKView keeps its delegate weakly
    private var lastDrag: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }
    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = point(event)
        if event.modifierFlags.contains(.option) {
            model.openJulia(at: p, in: bounds.size)
            return
        }
        if event.clickCount == 2 {
            let zoomOut = event.modifierFlags.contains(.shift)
            model.animateZoom(by: zoomOut ? 1 / 3.0 : 3, at: p, in: bounds.size)
            return
        }
        lastDrag = p
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDrag else { return }
        let p = point(event)
        model.pan(by: CGVector(dx: p.x - last.x, dy: p.y - last.y), in: bounds.size)
        lastDrag = p
    }

    override func mouseUp(with event: NSEvent) {
        if lastDrag != nil { NSCursor.pop() }
        lastDrag = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        model.animateZoom(by: 1 / 3.0, at: point(event), in: bounds.size)
    }

    // MARK: Trackpad and wheel

    override func scrollWheel(with event: NSEvent) {
        let p = point(event)
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            // Two fingers on a trackpad: move the picture with them.
            model.pan(by: CGVector(dx: event.scrollingDeltaX, dy: -event.scrollingDeltaY), in: bounds.size)
        } else {
            // Mouse wheel (or ⌘ + two fingers): zoom on the pointer.
            let step = event.hasPreciseScrollingDeltas ? 1.01 : 1.15
            model.zoom(by: pow(step, Double(event.scrollingDeltaY)), at: p, in: bounds.size)
        }
    }

    override func magnify(with event: NSEvent) {
        model.zoom(by: 1 + Double(event.magnification), at: point(event), in: bounds.size)
    }

    override func smartMagnify(with event: NSEvent) {
        model.animateZoom(by: 3, at: point(event), in: bounds.size)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let size = bounds.size
        let step = min(size.width, size.height) * 0.15
        switch event.keyCode {
        case 123: model.pan(by: CGVector(dx: step, dy: 0), in: size); return    // ←
        case 124: model.pan(by: CGVector(dx: -step, dy: 0), in: size); return   // →
        case 125: model.pan(by: CGVector(dx: 0, dy: step), in: size); return    // ↓
        case 126: model.pan(by: CGVector(dx: 0, dy: -step), in: size); return   // ↑
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "+", "=": model.animateZoom(by: 3, at: center, in: size)
        case "-", "_": model.animateZoom(by: 1 / 3.0, at: center, in: size)
        case "r", "0": model.goHome()
        case "j": model.toggleJulia()
        default: super.keyDown(with: event)
        }
    }
}

struct MetalCanvas: NSViewRepresentable {
    @ObservedObject var model: FractalModel

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.model = model
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        if let device = view.device {
            do {
                let renderer = try Renderer(model: model, device: device)
                view.renderer = renderer
                view.delegate = renderer
            } catch {
                let text = "Le moteur Metal n'a pas démarré : \(error.localizedDescription)"
                DispatchQueue.main.async { model.errorMessage = text }
            }
        } else {
            DispatchQueue.main.async { model.errorMessage = "Aucun processeur graphique Metal trouvé." }
        }
        model.requestRedraw = { [weak view] in view?.needsDisplay = true }
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        view.needsDisplay = true
    }
}
