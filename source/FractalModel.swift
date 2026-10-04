// Fractales -- what is on screen: the formula, where the view is, how deep, which colours.
//
// The view centre is kept in FractalCore's fixed point (fc_num, about 144 digits), because a
// Double runs out of digits after a zoom of about x10^13. Everything that only needs to be
// relative to the centre (offsets, sizes) stays in Double.

import Foundation
import QuartzCore
import SwiftUI

// MARK: - Languages

/// The text shown to the user, in the language macOS chose for the app (French or English).
/// The keys are the French texts; the translations are in fr.lproj and en.lproj/Localizable.strings.
func L(_ french: String) -> String {
    NSLocalizedString(french, comment: "")
}

/// Number formatting that matches the language of the interface, not only the region.
let appLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

// MARK: - Formulas

enum Formula: Int32, CaseIterable, Identifiable {
    case mandelbrot = 0, burningShip = 1, tricorn = 2, multibrot3 = 3, celtic = 4  // FC_* in FractalCore.h

    var id: Int32 { rawValue }

    var name: String {
        switch self {
        case .mandelbrot: return "Mandelbrot"
        case .burningShip: return "Burning Ship"
        case .tricorn: return L("Tricorne")
        case .multibrot3: return "Multibrot z³"
        case .celtic: return L("Celtique")
        }
    }

    /// Degree of the formula, for the smooth colouring.
    var power: Float { self == .multibrot3 ? 3 : 2 }

    /// The Burning Ship only looks like a ship with the imaginary axis pointing down.
    var ySign: Double { self == .burningShip ? -1 : 1 }

    /// Whole-figure view: centre and half the visible height, in complex units.
    var home: (x: String, y: String, halfHeight: Double) {
        switch self {
        case .mandelbrot: return ("-0.6", "0", 1.25)
        case .burningShip: return ("-0.45", "-0.5", 1.2)
        case .tricorn: return ("-0.3", "0", 1.4)
        case .multibrot3: return ("0", "0", 1.3)
        case .celtic: return ("-0.5", "0", 1.4)
        }
    }
}

// MARK: - Ready-made figures

struct Preset: Identifiable {
    let id = UUID()
    let name: String
    let formula: Formula
    var julia: (x: Double, y: Double)? = nil
    let x: String
    let y: String
    let halfHeight: Double
}

let presets: [Preset] = [
    Preset(name: "Mandelbrot", formula: .mandelbrot, x: "-0.6", y: "0", halfHeight: 1.25),
    Preset(name: L("Vallée des hippocampes"), formula: .mandelbrot, x: "-0.7453", y: "0.1127", halfHeight: 0.0065),
    Preset(name: L("Vallée des éléphants"), formula: .mandelbrot, x: "0.2715", y: "0.0055", halfHeight: 0.012),
    Preset(name: L("Spirale profonde"), formula: .mandelbrot,
           x: "-0.743643887037158704752191506114774", y: "0.131825904205311970493132056385139",
           halfHeight: 2e-11),
    Preset(name: L("Julia : lapin de Douady"), formula: .mandelbrot, julia: (-0.123, 0.745), x: "0", y: "0", halfHeight: 1.3),
    Preset(name: L("Julia : dendrite"), formula: .mandelbrot, julia: (0, 1), x: "0", y: "0", halfHeight: 1.3),
    Preset(name: L("Julia : San Marco"), formula: .mandelbrot, julia: (-0.75, 0), x: "0", y: "0", halfHeight: 1.1),
    Preset(name: L("Julia : spirales"), formula: .mandelbrot, julia: (-0.7269, 0.1889), x: "0", y: "0", halfHeight: 1.2),
    Preset(name: "Burning Ship", formula: .burningShip, x: "-0.45", y: "-0.5", halfHeight: 1.2),
    Preset(name: L("Burning Ship : l'armada"), formula: .burningShip, x: "-1.762", y: "-0.028", halfHeight: 0.04),
    Preset(name: L("Tricorne"), formula: .tricorn, x: "-0.3", y: "0", halfHeight: 1.4),
    Preset(name: "Multibrot z³", formula: .multibrot3, x: "0", y: "0", halfHeight: 1.3),
    Preset(name: L("Celtique"), formula: .celtic, x: "-0.5", y: "0", halfHeight: 1.4),
]

// MARK: - Palettes

struct Palette: Identifiable {
    let id: Int
    let name: String
    /// Colour stops (position 0...1, r, g, b 0...255). The palette loops: 1 joins back to 0.
    let stops: [(Double, Double, Double, Double)]

    /// 1024 RGBA8 texels, linearly interpolated between the stops.
    func texels(count: Int = 1024) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: count * 4)
        let s = stops.sorted { $0.0 < $1.0 }
        for i in 0..<count {
            let t = Double(i) / Double(count)
            // The stop at or before t, and the next one (wrapping round).
            var k = s.count - 1
            for (j, stop) in s.enumerated() where stop.0 <= t { k = j }
            let a = s[k], b = s[(k + 1) % s.count]
            var span = b.0 - a.0
            if span <= 0 { span += 1 }
            var u = t - a.0
            if u < 0 { u += 1 }
            let f = min(max(u / span, 0), 1)
            out[i * 4 + 0] = UInt8((a.1 + (b.1 - a.1) * f).rounded())
            out[i * 4 + 1] = UInt8((a.2 + (b.2 - a.2) * f).rounded())
            out[i * 4 + 2] = UInt8((a.3 + (b.3 - a.3) * f).rounded())
        }
        return out
    }
}

let palettes: [Palette] = [
    Palette(id: 0, name: L("Classique"), stops: [(0, 0, 7, 100), (0.16, 32, 107, 203), (0.42, 237, 255, 255),
                                              (0.6425, 255, 170, 0), (0.8575, 0, 2, 0)]),
    Palette(id: 1, name: L("Feu"), stops: [(0, 10, 0, 0), (0.25, 140, 10, 0), (0.5, 255, 120, 0),
                                        (0.7, 255, 230, 90), (0.85, 255, 255, 230)]),
    Palette(id: 2, name: L("Océan"), stops: [(0, 2, 10, 40), (0.3, 0, 80, 140), (0.55, 40, 200, 210),
                                          (0.75, 220, 250, 255), (0.9, 20, 60, 110)]),
    Palette(id: 3, name: L("Aurore"), stops: [(0, 20, 0, 50), (0.25, 160, 20, 160), (0.5, 40, 220, 120),
                                           (0.75, 30, 200, 255), (0.9, 10, 20, 90)]),
    Palette(id: 4, name: L("Arc-en-ciel"), stops: [(0, 255, 0, 0), (1.0 / 6, 255, 255, 0), (2.0 / 6, 0, 255, 0),
                                                (3.0 / 6, 0, 255, 255), (4.0 / 6, 0, 0, 255), (5.0 / 6, 255, 0, 255)]),
    Palette(id: 5, name: L("Encre"), stops: [(0, 0, 0, 0), (0.5, 255, 255, 255)]),
]

// MARK: - Model

final class FractalModel: ObservableObject {
    static let version = "0.1.0"

    /// Deepest zoom: half the view height, in complex units. Below about 1e-33 per pixel the
    /// GPU's floats lose the pixel offsets altogether.
    static let minHalfHeight = 1e-30
    static let maxHalfHeight = 4.0

    @Published var formula: Formula = .mandelbrot { didSet { if formula != oldValue { goHome() } } }
    @Published private(set) var julia = false
    @Published private(set) var juliaK = (x: -0.123, y: 0.745)
    /// Multiplies the automatic iteration count (more = finer detail, slower).
    @Published var detail: Double = 1 { didSet { viewChanged() } }
    @Published var paletteIndex = 0 { didSet { redraw() } }
    @Published var colorDensity: Double = 0.35 { didSet { redraw() } }
    @Published var colorOffset: Double = 0 { didSet { redraw() } }

    // Filled in by the renderer.
    @Published var lastRenderMilliseconds: Double = 0
    @Published var errorMessage: String?

    /// View centre, full precision.
    private(set) var centerX = fc_num()
    private(set) var centerY = fc_num()
    /// Half the visible height, in complex units.
    @Published private(set) var halfHeight: Double = 1.25

    /// Goes up whenever the picture must be recomputed (not for colour changes).
    private(set) var revision = 0
    /// Set by the canvas: asks for a new frame.
    var requestRedraw: () -> Void = {}

    private var lastInteraction: CFTimeInterval = 0
    private var animation: ZoomAnimation?
    private var glide: Glide?
    /// Set by the canvas: where the pointer is (or the middle of the view if it is elsewhere),
    /// for the Space-bar zoom.
    var pointer: () -> (point: CGPoint, size: CGSize)? = { nil }

    // Automatic voyage (Voyage.c).
    /// Zoom speed of the voyage: 1 halves the view height every 1.5 seconds.
    @Published var voyageSpeed: Double = 1
    @Published private(set) var voyaging = false
    @Published private(set) var voyagePhase: VoyagePhase = .diving
    private var voyage = fc_voyage()
    private var voyageLastStep: CFTimeInterval = 0
    static let voyageBaseRate = log(2.0) / 1.5
    /// Where the Mandelbrot-type view was before opening a Julia set, to come back to it.
    private var savedView: (x: fc_num, y: fc_num, halfHeight: Double)?

    init() { goHome() }

    // MARK: Derived values

    var maxIterations: Int { Self.iterations(halfHeight: halfHeight, detail: detail) }

    /// More iterations the deeper the view: the boundary needs them to show its detail.
    static func iterations(halfHeight: Double, detail: Double = 1) -> Int {
        let octaves = max(0, log2(2.5 / halfHeight))
        let auto = 250 + 90 * octaves
        return Int(min(max(auto * detail, 64), 200_000))
    }

    /// Half height of the whole figure (or of the Julia set).
    var homeHalfHeight: Double { julia ? 1.3 : formula.home.halfHeight }

    var zoomFactor: Double { formula.home.halfHeight / halfHeight }

    /// True for a short while after the view moved: the renderer then works at half resolution.
    var isInteracting: Bool { isAnimating || CACurrentMediaTime() - lastInteraction < 0.2 }
    /// True while the view moves by itself: the renderer then draws frame after frame.
    var isAnimating: Bool { animation != nil || glide != nil || voyaging }

    func centerText(digits: Int? = nil) -> (x: String, y: String) {
        let d = digits ?? max(6, Int(-log10(halfHeight)) + 4)
        func text(_ n: fc_num) -> String {
            var n = n
            var buf = [CChar](repeating: 0, count: 200)
            fc_to_string(&n, Int32(min(d, 150)), &buf, buf.count)
            return String(cString: buf)
        }
        return (text(centerX), text(centerY))
    }

    // MARK: Changes

    private func viewChanged() {
        revision += 1
        lastInteraction = CACurrentMediaTime()
        requestRedraw()
    }

    private func redraw() { requestRedraw() }

    func goHome() {
        animation = nil
        glide = nil
        restartVoyageIfRunning()
        if julia {
            fc_zero(&centerX); fc_zero(&centerY)
            halfHeight = 1.3
        } else {
            let h = formula.home
            fc_parse(&centerX, h.x); fc_parse(&centerY, h.y)
            halfHeight = h.halfHeight
        }
        viewChanged()
    }

    func apply(_ p: Preset) {
        animation = nil
        glide = nil
        savedView = nil
        if formula != p.formula {
            formula = p.formula   // its didSet goes home; the preset's view replaces that below
        }
        if let k = p.julia {
            julia = true
            juliaK = k
        } else {
            julia = false
        }
        fc_parse(&centerX, p.x); fc_parse(&centerY, p.y)
        halfHeight = p.halfHeight
        restartVoyageIfRunning()
        viewChanged()
    }

    /// Offset of a point of the canvas from the view centre, in complex units.
    /// `point` is in view coordinates (origin bottom left, y up), `size` the view size.
    func offset(of point: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
        let u = 2 * halfHeight / max(Double(size.height), 1)
        return ((Double(point.x) - Double(size.width) / 2) * u,
                (Double(point.y) - Double(size.height) / 2) * u * formula.ySign)
    }

    /// Moves the picture by `delta` points, as if dragged.
    func pan(by delta: CGVector, in size: CGSize) {
        takeOver()
        let u = 2 * halfHeight / max(Double(size.height), 1)
        fc_add_double(&centerX, -Double(delta.dx) * u)
        fc_add_double(&centerY, -Double(delta.dy) * u * formula.ySign)
        viewChanged()
    }

    /// Zooms by `factor` (>1 = closer), keeping the point under `point` where it is.
    func zoom(by factor: Double, at point: CGPoint, in size: CGSize) {
        takeOver()
        zoomInPlace(by: factor, at: point, in: size)
        viewChanged()
    }

    private func zoomInPlace(by factor: Double, at point: CGPoint, in size: CGSize) {
        let d = offset(of: point, in: size)
        let newHalf = min(max(halfHeight / factor, Self.minHalfHeight), Self.maxHalfHeight)
        let keep = 1 - newHalf / halfHeight
        fc_add_double(&centerX, d.x * keep)
        fc_add_double(&centerY, d.y * keep)
        halfHeight = newHalf
    }

    /// The user moves the view by hand: the voyage and any running zoom stop.
    private func takeOver() {
        animation = nil
        voyaging = false
    }

    /// Same as zoom(by:at:in:), but smoothly over a third of a second.
    func animateZoom(by factor: Double, at point: CGPoint, in size: CGSize) {
        takeOver()
        glide = nil
        let d = offset(of: point, in: size)
        let target = min(max(halfHeight / factor, Self.minHalfHeight), Self.maxHalfHeight)
        animation = ZoomAnimation(start: CACurrentMediaTime(), duration: 0.35,
                                  startX: centerX, startY: centerY, anchor: d,
                                  fromHalf: halfHeight, toHalf: target)
        viewChanged()
    }

    /// Called by the renderer before each frame.
    func advanceAnimation(now: CFTimeInterval) {
        advanceGlide(now: now)
        advanceVoyage(now: now)
        guard let a = animation else { return }
        let t = min(max((now - a.start) / a.duration, 0), 1)
        let e = t * t * (3 - 2 * t)   // ease in and out
        let half = exp(log(a.fromHalf) + (log(a.toHalf) - log(a.fromHalf)) * e)
        // The anchor stays still: centre = anchor - d * (half / fromHalf).
        let keep = 1 - half / a.fromHalf
        centerX = a.startX
        centerY = a.startY
        fc_add_double(&centerX, a.anchor.x * keep)
        fc_add_double(&centerY, a.anchor.y * keep)
        halfHeight = half
        if t >= 1 { animation = nil }
        revision += 1
        lastInteraction = now
    }

    /// Opens the Julia set of the point under `point` (from a Mandelbrot-type view).
    func openJulia(at point: CGPoint, in size: CGSize) {
        guard !julia else { return }
        let d = offset(of: point, in: size)
        juliaK = (fc_to_double(&centerX) + d.x, fc_to_double(&centerY) + d.y)
        enterJulia()
    }

    /// J key: the Julia set of the view centre, or back to where we were.
    func toggleJulia() {
        if julia {
            julia = false
            animation = nil
            if let s = savedView {
                centerX = s.x; centerY = s.y; halfHeight = s.halfHeight
                savedView = nil
                viewChanged()
            } else {
                goHome()
            }
        } else {
            juliaK = (fc_to_double(&centerX), fc_to_double(&centerY))
            enterJulia()
        }
    }

    func setJulia(_ on: Bool) {
        if on != julia { toggleJulia() }
    }

    private func enterJulia() {
        animation = nil
        glide = nil
        savedView = (centerX, centerY, halfHeight)
        julia = true
        fc_zero(&centerX); fc_zero(&centerY)
        halfHeight = 1.3
        restartVoyageIfRunning()
        viewChanged()
    }

    // MARK: Space bar: zoom towards the pointer

    /// Space pressed: zooms towards the pointer for as long as the key is held, and at least
    /// long enough for a tap to zoom about ×3. With ⇧, backs out instead.
    func startGlide(out: Bool) {
        takeOver()
        let now = CACurrentMediaTime()
        glide = Glide(start: now, last: now, out: out)
        viewChanged()
    }

    /// Space released.
    func releaseGlide() {
        glide?.released = true
    }

    private func advanceGlide(now: CFTimeInterval) {
        guard var g = glide else { return }
        let dt = min(max(now - g.last, 0), 0.1)
        g.last = now
        let ramp = min((now - g.start) / 0.1, 1)   // a soft start
        let rate = Glide.rate * ramp * (g.out ? -1 : 1)
        if let p = pointer() {
            zoomInPlace(by: exp(rate * dt), at: p.point, in: p.size)
        }
        glide = g.released && now - g.start >= Glide.minimumDuration ? nil : g
        revision += 1
        lastInteraction = now
    }

    // MARK: Automatic voyage

    func toggleVoyage() {
        if voyaging { stopVoyage() } else { startVoyage() }
    }

    func startVoyage() {
        animation = nil
        glide = nil
        fc_voyage_start(&voyage, UInt32.random(in: 1...UInt32.max))
        voyageLastStep = 0
        voyagePhase = .diving
        voyaging = true
        viewChanged()
    }

    func stopVoyage() {
        guard voyaging else { return }
        voyaging = false
        viewChanged()   // and the renderer draws it once more at full resolution
    }

    private func restartVoyageIfRunning() {
        guard voyaging else { return }
        fc_voyage_start(&voyage, UInt32.random(in: 1...UInt32.max))
        voyageLastStep = 0
        voyagePhase = .diving
    }

    private func advanceVoyage(now: CFTimeInterval) {
        guard voyaging else { return }
        let dt = voyageLastStep == 0 ? 0 : now - voyageLastStep
        voyageLastStep = now
        var mx = 0.0, my = 0.0
        let z = fc_voyage_step(&voyage, dt, Self.voyageBaseRate * voyageSpeed, halfHeight, &mx, &my)
        fc_add_double(&centerX, mx)
        fc_add_double(&centerY, my * formula.ySign)
        halfHeight = min(max(halfHeight * z, Self.minHalfHeight), Self.maxHalfHeight)
        revision += 1
        lastInteraction = now
    }

    /// Called by the renderer with a small grid of escape counts (row 0 at the top) sampled from
    /// a picture it computed, centred on (x, y) with half height `probeHalf`.
    func voyageLook(_ samples: [Float], width: Int, height: Int, x: fc_num, y: fc_num, probeHalf: Double) {
        guard voyaging, samples.count >= width * height else { return }
        var x = x, y = y
        let ox = fc_diff_to_double(&x, &centerX)
        let oy = fc_diff_to_double(&y, &centerY) * formula.ySign
        samples.withUnsafeBufferPointer { buffer in
            fc_voyage_look(&voyage, buffer.baseAddress, Int32(width), Int32(height), ox, oy, probeHalf,
                           halfHeight, Self.minHalfHeight, homeHalfHeight)
        }
        let phase: VoyagePhase = voyage.backing == 2 ? .climbing : voyage.backing == 1 ? .backingOut : .diving
        if phase != voyagePhase { voyagePhase = phase }
    }
}

enum VoyagePhase {
    case diving       // heading for the detail
    case backingOut   // nothing to see here: backing out to look further
    case climbing     // at the deepest zoom the engine allows: climbing back to dive elsewhere
}

private struct Glide {
    static let rate = log(3.0) / 0.5        // ×3 every half second
    static let minimumDuration = 0.5        // so a tap zooms about ×3
    let start: CFTimeInterval
    var last: CFTimeInterval
    let out: Bool
    var released = false
}

private struct ZoomAnimation {
    let start: CFTimeInterval
    let duration: Double
    let startX: fc_num
    let startY: fc_num
    let anchor: (x: Double, y: Double)
    let fromHalf: Double
    let toHalf: Double
}
