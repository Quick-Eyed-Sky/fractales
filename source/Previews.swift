// Fractales -- previews of the ready-made figures, for the list on the left.
//
// The escape counts of each small picture are computed once, on the CPU in double precision
// (fc_preview in Voyage.c, enough for these views), then coloured like the GPU does it with the
// current palette, so the previews follow the colour settings at no cost.

import AppKit
import SwiftUI

final class PreviewStore: ObservableObject {
    /// Pixel size of a preview (shown at half that size in points, sharp on Retina screens).
    static let width = 180
    static let height = 120

    /// Escape counts of each figure, by index in `presets`, as they become ready.
    @Published private(set) var counts: [Int: [Float]] = [:]
    private var started = false
    private var cache: [Int: (key: ColourKey, image: CGImage)] = [:]
    private var texels: [Int: [UInt8]] = [:]

    func start() {
        guard !started else { return }
        started = true
        let jobs = Array(presets.enumerated())
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for (index, p) in jobs {
                let w = PreviewStore.width, h = PreviewStore.height
                var out = [Float](repeating: -1, count: w * h)
                let k = p.julia ?? (x: 0, y: 0)
                let x = Double(p.x) ?? 0, y = Double(p.y) ?? 0
                // Same height of the plane as the figure shows in the window; a little wider.
                let iterations = FractalModel.iterations(halfHeight: p.halfHeight)
                out.withUnsafeMutableBufferPointer { buffer in
                    fc_preview(p.formula.rawValue, p.julia == nil ? 0 : 1, k.x, k.y, x, y, p.halfHeight,
                               p.formula.ySign, Int32(w), Int32(h), Int32(iterations), buffer.baseAddress)
                }
                DispatchQueue.main.async { self?.counts[index] = out }
            }
        }
    }

    /// The preview of figure `index` in the given colours, or nil while it is being computed.
    func image(_ index: Int, palette: Int, density: Double, offset: Double) -> CGImage? {
        guard let values = counts[index] else { return nil }
        let key = ColourKey(palette: palette, density: density, offset: offset)
        if let cached = cache[index], cached.key == key { return cached.image }
        let image = colour(values, key)
        if let image = image { cache[index] = (key, image) }
        return image
    }

    /// Same colouring as colorFragment in Shaders.metal: black inside, else the palette at
    /// fract(sqrt(count) × density + offset), linearly interpolated and looping.
    private func colour(_ values: [Float], _ key: ColourKey) -> CGImage? {
        let index = min(max(key.palette, 0), palettes.count - 1)
        if texels[index] == nil { texels[index] = palettes[index].texels(count: 1024) }
        guard let table = texels[index] else { return nil }
        let n = table.count / 4
        var rgba = [UInt8](repeating: 255, count: values.count * 4)
        for (i, v) in values.enumerated() {
            if v < 0 {
                rgba[i * 4] = 0; rgba[i * 4 + 1] = 0; rgba[i * 4 + 2] = 0
                continue
            }
            let t = Double(v).squareRoot() * key.density + key.offset
            let f = (t - t.rounded(.down)) * Double(n) - 0.5
            let i0 = Int(f.rounded(.down))
            let u = f - Double(i0)
            let a = ((i0 % n) + n) % n, b = (a + 1) % n
            for c in 0..<3 {
                let value = Double(table[a * 4 + c]) * (1 - u) + Double(table[b * 4 + c]) * u
                rgba[i * 4 + c] = UInt8(min(max(value.rounded(), 0), 255))
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: Self.width, height: Self.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: Self.width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private struct ColourKey: Equatable {
        let palette: Int
        let density: Double
        let offset: Double
    }
}

// MARK: - The list of figures, on the left

struct FigureList: View {
    @EnvironmentObject var model: FractalModel
    @StateObject private var previews = PreviewStore()
    @State private var chosen: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Figures"))
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(presets.enumerated()), id: \.offset) { index, p in
                        Button {
                            chosen = index
                            model.apply(p)
                        } label: {
                            card(index, p)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .onAppear { previews.start() }
    }

    private func card(_ index: Int, _ p: Preset) -> some View {
        let selected = chosen == index
        return HStack(spacing: 10) {
            Group {
                if let image = previews.image(index, palette: model.paletteIndex,
                                              density: model.colorDensity, offset: model.colorOffset) {
                    Image(decorative: image, scale: 2).resizable()
                } else {
                    Rectangle().fill(Color.black.opacity(0.6))
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            .frame(width: CGFloat(PreviewStore.width) / 2, height: CGFloat(PreviewStore.height) / 2)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(p.julia == nil ? p.formula.name : L("Ensemble de Julia"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(selected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
    }
}
