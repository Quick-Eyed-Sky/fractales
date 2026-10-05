// Fractales -- the Metal view and everything the mouse, trackpad and keyboard do to it.

import AppKit
import MetalKit
import SwiftUI

final class CanvasView: MTKView {
    var model: FractalModel!
    var renderer: Renderer?   // MTKView keeps its delegate weakly
    private var lastDrag: CGPoint?
    private var spaceMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        if spaceMonitor == nil {
            // The Space bar zooms wherever the keyboard focus is (a slider, a button of the
            // panel), except while typing text.
            spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self = self, event.keyCode == 49, event.window === self.window, self.window != nil,
                      !event.modifierFlags.contains(.command),
                      !(self.window?.firstResponder is NSText) else { return event }
                if event.type == .keyDown {
                    if !event.isARepeat { self.model.startGlide(out: event.modifierFlags.contains(.shift)) }
                } else {
                    self.model.releaseGlide()
                }
                return nil
            }
            // A Space key released in another window never reaches us: stop there too.
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil,
                                                   queue: .main) { [weak self] note in
                if let self = self, note.object as? NSWindow === self.window { self.model.releaseGlide() }
            }
        }
    }

    deinit {
        if let monitor = spaceMonitor { NSEvent.removeMonitor(monitor) }
    }

    /// Where the Space bar zooms: the pointer if it is over the picture, else the middle.
    func zoomPoint() -> (point: CGPoint, size: CGSize) {
        var p = center
        if let window = window {
            let q = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(q) { p = q }
        }
        return (p, bounds.size)
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
                let text = String(format: L("Le moteur Metal n'a pas démarré : %@"), error.localizedDescription)
                DispatchQueue.main.async { model.errorMessage = text }
            }
        } else {
            DispatchQueue.main.async { model.errorMessage = L("Aucun processeur graphique Metal trouvé.") }
        }
        model.requestRedraw = { [weak view] in view?.needsDisplay = true }
        model.pointer = { [weak view] in view?.zoomPoint() }
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        view.needsDisplay = true
    }
}
