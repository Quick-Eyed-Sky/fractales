// Fractales -- the app and its window.

import AppKit
import SwiftUI

@main
struct FractalesApp: App {
    @StateObject private var model = FractalModel()

    var body: some Scene {
        Window("Fractales", id: "main") {
            ContentView().environmentObject(model)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandMenu(L("Vue")) {
                Button(L("Zoomer")) { model.animateZoomAtCenter(3) }.keyboardShortcut("+", modifiers: [])
                Button(L("Dézoomer")) { model.animateZoomAtCenter(1 / 3.0) }.keyboardShortcut("-", modifiers: [])
                Button(L("Vue d'ensemble")) { model.goHome() }.keyboardShortcut("r", modifiers: [])
                Divider()
                Button(model.julia ? L("Revenir à l'ensemble") : L("Ensemble de Julia du centre")) { model.toggleJulia() }
                    .keyboardShortcut("j", modifiers: [])
            }
        }
    }
}

extension FractalModel {
    /// Menu commands have no canvas at hand: zoom on the middle of the view.
    func animateZoomAtCenter(_ factor: Double) {
        let size = CGSize(width: 2, height: 2)
        animateZoom(by: factor, at: CGPoint(x: 1, y: 1), in: size)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: FractalModel

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                MetalCanvas(model: model)
                InfoOverlay().padding(10)
                if let error = model.errorMessage {
                    Text(error)
                        .padding(12)
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 480, minHeight: 360)
            Divider()
            ControlPanel().frame(width: 270)
        }
    }
}

// MARK: - Bottom-left information

struct InfoOverlay: View {
    @EnvironmentObject var model: FractalModel

    var body: some View {
        let c = model.centerText()
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: L("Zoom %@  ·  %ld itérations  ·  %ld ms"), zoomText(model.zoomFactor),
                        model.maxIterations, Int(model.lastRenderMilliseconds.rounded())))
            Text("x \(c.x)")
            Text("y \(c.y)")
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
        .textSelection(.enabled)
        .allowsHitTesting(true)
    }
}

/// "×12", "×3 400", "×1,2 × 10¹⁵".
func zoomText(_ z: Double) -> String {
    if z < 100_000 {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = z < 10 ? 1 : 0
        f.locale = appLocale
        return "×" + (f.string(from: NSNumber(value: z)) ?? "\(z)")
    }
    let e = Int(floor(log10(z)))
    let m = z / pow(10, Double(e))
    let digits: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
    let sup = String(String(e).map { digits[Int(String($0))!] })
    let separator = appLocale.decimalSeparator ?? "."
    return String(format: "×%.1f × 10", m).replacingOccurrences(of: ".", with: separator) + sup
}

// MARK: - Right-hand panel

struct ControlPanel: View {
    @EnvironmentObject var model: FractalModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(L("Figures")) {
                    Menu(L("Choisir une figure…")) {
                        ForEach(presets) { p in
                            Button(p.name) { model.apply(p) }
                        }
                    }
                }

                section(L("Formule")) {
                    Picker("", selection: $model.formula) {
                        ForEach(Formula.allCases) { f in Text(f.name).tag(f) }
                    }
                    .labelsHidden()
                    Toggle(L("Ensemble de Julia"), isOn: Binding(get: { model.julia }, set: { model.setJulia($0) }))
                    if model.julia {
                        Text(String(format: "c = %.5f %@ %.5f i", model.juliaK.x,
                                    model.juliaK.y < 0 ? "−" : "+", abs(model.juliaK.y)))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    hint(model.julia
                         ? L("J revient à l'ensemble de départ.")
                         : L("⌥-clic sur l'image : l'ensemble de Julia de ce point."))
                }

                section(L("Détails")) {
                    Slider(value: Binding(get: { log2(model.detail) }, set: { model.detail = pow(2, $0) }),
                           in: -2...3)
                    hint(String(format: L("%ld itérations au plus par pixel. Plus de détails, rendu plus lent."),
                                model.maxIterations))
                }

                section(L("Couleurs")) {
                    Picker("", selection: $model.paletteIndex) {
                        ForEach(palettes) { p in Text(p.name).tag(p.id) }
                    }
                    .labelsHidden()
                    LabeledContent(L("Densité")) {
                        Slider(value: $model.colorDensity, in: 0.02...2)
                    }
                    LabeledContent(L("Décalage")) {
                        Slider(value: $model.colorOffset, in: 0...1)
                    }
                }

                section(L("Navigation")) {
                    VStack(alignment: .leading, spacing: 4) {
                        hint(L("Glisser, ou deux doigts : déplacer"))
                        hint(L("Pincer, molette, ⌘ + deux doigts : zoomer"))
                        hint(L("Double-clic : zoom ×3   ⇧ double-clic, clic droit : arrière"))
                        hint(L("Flèches, + et − ; R : vue d'ensemble"))
                    }
                    Button(L("Vue d'ensemble")) { model.goHome() }
                }

                Spacer(minLength: 0)
                Text(String(format: L("Fractales %@ · rendu Metal"), FractalModel.version))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
