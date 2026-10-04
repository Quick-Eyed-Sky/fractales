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
        .defaultSize(width: 1440, height: 860)
        .commands {
            CommandMenu(L("Vue")) {
                Button(model.voyaging ? L("Pause du voyage") : L("Lancer le voyage")) { model.toggleVoyage() }
                    .keyboardShortcut("v", modifiers: [])
                Divider()
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
            FigureList().frame(width: 236)
            Divider()
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
                section(L("Voyage infini")) {
                    Button {
                        model.toggleVoyage()
                    } label: {
                        Label(model.voyaging ? L("Pause du voyage") : L("Lancer le voyage"),
                              systemImage: model.voyaging ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    LabeledContent(L("Vitesse")) {
                        Slider(value: Binding(get: { log2(model.voyageSpeed) }, set: { model.voyageSpeed = pow(2, $0) }),
                               in: -2...2)
                    }
                    hint(voyageText)
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
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                              spacing: 8) {
                        ForEach(palettes) { p in swatch(p) }
                    }
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
                        hint(L("Espace : zoom vers le pointeur, tant qu'on la tient"))
                        hint(L("⇧ Espace, clic droit : zoom arrière"))
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

    private var voyageText: String {
        guard model.voyaging else {
            return L("L'appli plonge toute seule vers les zones riches en détails, sans fin. Touche V. Toucher l'image reprend la main.")
        }
        switch model.voyagePhase {
        case .diving: return L("Le pilote suit les contours et évite le vide.")
        case .backingOut: return L("Rien à voir ici : le pilote recule pour chercher du détail.")
        case .climbing: return L("Tout au fond : le pilote remonte pour replonger ailleurs.")
        }
    }

    /// A palette as a strip of its colours, to click.
    private func swatch(_ p: Palette) -> some View {
        let selected = model.paletteIndex == p.id
        let sorted = p.stops.sorted { $0.0 < $1.0 }
        // The palette loops: end on the first colour again.
        var stops = sorted.map { Gradient.Stop(color: Color(red: $0.1 / 255, green: $0.2 / 255, blue: $0.3 / 255),
                                               location: $0.0) }
        if let first = sorted.first {
            stops.append(Gradient.Stop(color: Color(red: first.1 / 255, green: first.2 / 255, blue: first.3 / 255),
                                       location: 1))
        }
        return Button {
            model.paletteIndex = p.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(gradient: Gradient(stops: stops), startPoint: .leading, endPoint: .trailing))
                    .frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15),
                                      lineWidth: selected ? 2 : 1))
                Text(p.name).font(.caption).foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
