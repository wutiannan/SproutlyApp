import SwiftUI
import UIKit

struct MindfulColorProfile {
    static let hueBinCount = 12
    static let empty = MindfulColorProfile(
        coloredPixels: 0,
        drawablePixels: 0,
        hueCosine: 0,
        hueSine: 0,
        saturationTotal: 0,
        brightnessTotal: 0,
        warmPixels: 0,
        coolPixels: 0,
        hueBins: Array(repeating: 0, count: hueBinCount)
    )

    let coloredPixels: Double
    let drawablePixels: Double
    let hueCosine: Double
    let hueSine: Double
    let saturationTotal: Double
    let brightnessTotal: Double
    let warmPixels: Double
    let coolPixels: Double
    let hueBins: [Double]

    var hasColor: Bool {
        coloredPixels > 0
    }

    var coloredFraction: Double {
        guard drawablePixels > 0 else { return 0 }
        return min(max(coloredPixels / drawablePixels, 0), 1)
    }

    var averageHue: Double {
        guard hasColor else { return 0.5 }
        let angle = atan2(hueSine, hueCosine)
        return angle >= 0
            ? angle / (Double.pi * 2)
            : angle / (Double.pi * 2) + 1
    }

    var dominantHue: Double {
        guard let index = hueBins.indices.max(by: {
            hueBins[$0] < hueBins[$1]
        }), hueBins[index] > 0 else {
            return averageHue
        }
        return (Double(index) + 0.5) / Double(Self.hueBinCount)
    }

    var meanSaturation: Double {
        guard hasColor else { return 0.5 }
        return min(max(saturationTotal / coloredPixels, 0), 1)
    }

    var meanBrightness: Double {
        guard hasColor else { return 0.5 }
        return min(max(brightnessTotal / coloredPixels, 0), 1)
    }

    var warmProportion: Double {
        guard hasColor else { return 0 }
        return min(max(warmPixels / coloredPixels, 0), 1)
    }

    var coolProportion: Double {
        guard hasColor else { return 0 }
        return min(max(coolPixels / coloredPixels, 0), 1)
    }

    var hueDiversity: Double {
        guard coloredPixels > 0 else { return 0 }
        let entropy = hueBins.reduce(0.0) { result, weight in
            guard weight > 0 else { return result }
            let proportion = weight / coloredPixels
            return result - proportion * log(proportion)
        }
        return min(
            max(entropy / log(Double(Self.hueBinCount)), 0),
            1
        )
    }

    var visualAccent: Color {
        Color(
            hue: dominantHue,
            saturation: max(0.42, meanSaturation * 0.82),
            brightness: max(0.72, meanBrightness)
        )
    }

    static func combining(
        _ profiles: [MindfulColorProfile]
    ) -> MindfulColorProfile {
        guard !profiles.isEmpty else { return .empty }
        var hueBins = Array(repeating: 0.0, count: hueBinCount)
        for profile in profiles {
            for index in hueBins.indices where index < profile.hueBins.count {
                hueBins[index] += profile.hueBins[index]
            }
        }
        return MindfulColorProfile(
            coloredPixels: profiles.reduce(0) { $0 + $1.coloredPixels },
            drawablePixels: profiles.reduce(0) { $0 + $1.drawablePixels },
            hueCosine: profiles.reduce(0) { $0 + $1.hueCosine },
            hueSine: profiles.reduce(0) { $0 + $1.hueSine },
            saturationTotal: profiles.reduce(0) { $0 + $1.saturationTotal },
            brightnessTotal: profiles.reduce(0) { $0 + $1.brightnessTotal },
            warmPixels: profiles.reduce(0) { $0 + $1.warmPixels },
            coolPixels: profiles.reduce(0) { $0 + $1.coolPixels },
            hueBins: hueBins
        )
    }
}

struct MusicColoringPager: View {
    let outlineAssets: [String]
    let regionAssets: [String]
    let selectedColor: UIColor
    let onRegionFilled: (UIColor, CGFloat, MindfulColorProfile) -> Void
    let onCanvasTapped: () -> Void
    @Binding var selectedIndex: Int
    @Binding var coloredImages: [UIImage?]
    @Binding var colorAssignments: [[UInt16: UIColor]]

    init(
        outlineAssets: [String],
        regionAssets: [String],
        selectedColor: UIColor,
        onRegionFilled: @escaping (UIColor, CGFloat, MindfulColorProfile) -> Void,
        onCanvasTapped: @escaping () -> Void = {},
        selectedIndex: Binding<Int>,
        coloredImages: Binding<[UIImage?]>,
        colorAssignments: Binding<[[UInt16: UIColor]]>
    ) {
        self.outlineAssets = outlineAssets
        self.regionAssets = regionAssets
        self.selectedColor = selectedColor
        self.onRegionFilled = onRegionFilled
        self.onCanvasTapped = onCanvasTapped
        _selectedIndex = selectedIndex
        _coloredImages = coloredImages
        _colorAssignments = colorAssignments
    }

    var body: some View {
        GeometryReader { proxy in
            MusicColoringCanvas(
                outlineAsset: outlineAssets[selectedIndex],
                coloredImage: coloredImages[selectedIndex]
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        onCanvasTapped()
                        fillRegion(at: value.location, in: proxy.size)
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("花朵填色画布")
        .accessibilityHint("轻点线条围成的封闭区域填色")
    }

    private func fillRegion(at location: CGPoint, in canvasSize: CGSize) {
        guard selectedIndex >= 0,
              selectedIndex < outlineAssets.count,
              selectedIndex < regionAssets.count,
              selectedIndex < coloredImages.count,
              selectedIndex < colorAssignments.count,
              let result = MusicRegionPainter.paint(
                regionAsset: regionAssets[selectedIndex],
                assignments: colorAssignments[selectedIndex],
                at: location,
                canvasSize: canvasSize,
                color: selectedColor
              ) else { return }

        var updatedArtworkAssignments = colorAssignments
        updatedArtworkAssignments[selectedIndex] = result.assignments
        colorAssignments = updatedArtworkAssignments
        var updatedColoredImages = coloredImages
        updatedColoredImages[selectedIndex] = result.image
        coloredImages = updatedColoredImages
        let selectedProfile = MusicRegionPainter.profile(
            regionAsset: regionAssets[selectedIndex],
            assignments: updatedArtworkAssignments[selectedIndex]
        ) ?? .empty
        onRegionFilled(
            selectedColor,
            result.regionFraction,
            selectedProfile
        )
    }
}

private struct MusicColoringCanvas: View {
    let outlineAsset: String
    let coloredImage: UIImage?

    var body: some View {
        ZStack {
            if let coloredImage {
                Image(uiImage: coloredImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }

            Image(outlineAsset)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        }
    }
}

enum MusicRegionPainter {
    private struct RegionMap {
        let width: Int
        let height: Int
        let regionCount: Int
        let labels: [UInt16]
        let regionPixelCounts: [Int]
        let drawablePixelCount: Int
    }

    private static var cachedMaps: [String: RegionMap] = [:]

    static func paint(
        regionAsset: String,
        assignments: [UInt16: UIColor],
        at point: CGPoint,
        canvasSize: CGSize,
        color: UIColor
    ) -> (
        image: UIImage,
        assignments: [UInt16: UIColor],
        regionFraction: CGFloat
    )? {
        guard canvasSize.width > 0,
              canvasSize.height > 0,
              let map = regionMap(named: regionAsset) else { return nil }

        let imageRect = aspectFitRect(
            imageSize: CGSize(width: map.width, height: map.height),
            in: CGRect(origin: .zero, size: canvasSize)
        )
        guard imageRect.contains(point) else { return nil }
        let x = min(
            max(Int((point.x - imageRect.minX) / imageRect.width * CGFloat(map.width)), 0),
            map.width - 1
        )
        let y = min(
            max(Int((point.y - imageRect.minY) / imageRect.height * CGFloat(map.height)), 0),
            map.height - 1
        )
        let tolerance = max(1, Int((6 / imageRect.width * CGFloat(map.width)).rounded()))
        guard let regionID = regionID(in: map, x: x, y: y, tolerance: tolerance) else {
            return nil
        }

        var updatedAssignments = assignments
        updatedAssignments[regionID] = color
        guard let image = render(map: map, assignments: updatedAssignments) else {
            return nil
        }
        let regionPixels = map.regionPixelCounts[Int(regionID)]
        let regionFraction = CGFloat(regionPixels)
            / CGFloat(max(map.drawablePixelCount, 1))
        return (image, updatedAssignments, regionFraction)
    }

    static func profile(
        regionAsset: String,
        assignments: [UInt16: UIColor]
    ) -> MindfulColorProfile? {
        guard let map = regionMap(named: regionAsset) else { return nil }
        var coloredPixels = 0.0
        var hueCosine = 0.0
        var hueSine = 0.0
        var saturationTotal = 0.0
        var brightnessTotal = 0.0
        var warmPixels = 0.0
        var coolPixels = 0.0
        var hueBins = Array(
            repeating: 0.0,
            count: MindfulColorProfile.hueBinCount
        )

        for (regionID, color) in assignments {
            let index = Int(regionID)
            guard index > 0, index < map.regionPixelCounts.count else { continue }
            let pixelWeight = Double(map.regionPixelCounts[index])
            guard pixelWeight > 0 else { continue }

            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            if !color.getHue(
                &hue,
                saturation: &saturation,
                brightness: &brightness,
                alpha: &alpha
            ) {
                color.getWhite(&brightness, alpha: &alpha)
            }

            let effectivePixels = pixelWeight * Double(alpha)
            guard effectivePixels > 0 else { continue }
            let normalizedHue = Double(hue)
            let angle = normalizedHue * Double.pi * 2
            coloredPixels += effectivePixels
            hueCosine += cos(angle) * effectivePixels
            hueSine += sin(angle) * effectivePixels
            saturationTotal += Double(saturation) * effectivePixels
            brightnessTotal += Double(brightness) * effectivePixels

            if normalizedHue < 0.22 || normalizedHue >= 0.82 {
                warmPixels += effectivePixels
            } else if normalizedHue >= 0.34 && normalizedHue < 0.76 {
                coolPixels += effectivePixels
            }

            let hueIndex = min(
                Int(normalizedHue * Double(MindfulColorProfile.hueBinCount)),
                MindfulColorProfile.hueBinCount - 1
            )
            hueBins[hueIndex] += effectivePixels
        }

        return MindfulColorProfile(
            coloredPixels: coloredPixels,
            drawablePixels: Double(map.drawablePixelCount),
            hueCosine: hueCosine,
            hueSine: hueSine,
            saturationTotal: saturationTotal,
            brightnessTotal: brightnessTotal,
            warmPixels: warmPixels,
            coolPixels: coolPixels,
            hueBins: hueBins
        )
    }

    static func image(
        regionAsset: String,
        assignments: [UInt16: UIColor]
    ) -> UIImage? {
        guard let map = regionMap(named: regionAsset) else { return nil }
        return render(map: map, assignments: assignments)
    }

    private static func regionMap(named assetName: String) -> RegionMap? {
        if let cached = cachedMaps[assetName] {
            return cached
        }
        guard let data = NSDataAsset(name: assetName)?.data,
              data.count >= 10 else {
            return nil
        }

        let signature = Array(data.prefix(4))
        let usesExtendedLabels = signature == [0x53, 0x47, 0x52, 0x32]
        guard usesExtendedLabels || signature == [0x53, 0x47, 0x52, 0x31] else {
            return nil
        }

        func uint16(at offset: Int) -> Int {
            Int(data[offset]) | (Int(data[offset + 1]) << 8)
        }

        func uint32(at offset: Int) -> Int {
            Int(data[offset])
                | (Int(data[offset + 1]) << 8)
                | (Int(data[offset + 2]) << 16)
                | (Int(data[offset + 3]) << 24)
        }

        let width = uint16(at: 4)
        let height = uint16(at: 6)
        let regionCount = uint16(at: 8)
        let pixelCount = width * height
        guard width > 0, height > 0, regionCount > 0 else { return nil }

        var labels: [UInt16] = []
        labels.reserveCapacity(pixelCount)
        var cursor = 10
        while labels.count < pixelCount {
            let entrySize = usesExtendedLabels ? 6 : 3
            guard cursor + entrySize <= data.count else { return nil }
            let regionID = usesExtendedLabels
                ? UInt16(uint16(at: cursor))
                : UInt16(data[cursor])
            let runLength = usesExtendedLabels
                ? uint32(at: cursor + 2)
                : uint16(at: cursor + 1)
            guard runLength > 0 else { return nil }
            labels.append(contentsOf: repeatElement(regionID, count: runLength))
            cursor += entrySize
        }
        guard labels.count == pixelCount else { return nil }

        var regionPixelCounts = [Int](repeating: 0, count: regionCount + 1)
        for regionID in labels {
            let index = Int(regionID)
            if index > 0, index < regionPixelCounts.count {
                regionPixelCounts[index] += 1
            }
        }
        let drawablePixelCount = regionPixelCounts.dropFirst().reduce(0, +)

        let map = RegionMap(
            width: width,
            height: height,
            regionCount: regionCount,
            labels: labels,
            regionPixelCounts: regionPixelCounts,
            drawablePixelCount: drawablePixelCount
        )
        cachedMaps[assetName] = map
        return map
    }

    private static func regionID(
        in map: RegionMap,
        x: Int,
        y: Int,
        tolerance: Int
    ) -> UInt16? {
        let direct = map.labels[y * map.width + x]
        if direct > 0 {
            return direct
        }

        var counts = [Int](repeating: 0, count: map.regionCount + 1)
        for radius in 1...tolerance {
            let minX = max(0, x - radius)
            let maxX = min(map.width - 1, x + radius)
            let minY = max(0, y - radius)
            let maxY = min(map.height - 1, y + radius)

            for nearbyX in minX...maxX {
                countRegion(map.labels[minY * map.width + nearbyX], in: &counts)
                if maxY != minY {
                    countRegion(map.labels[maxY * map.width + nearbyX], in: &counts)
                }
            }
            if maxY - minY > 1 {
                for nearbyY in (minY + 1)..<maxY {
                    countRegion(map.labels[nearbyY * map.width + minX], in: &counts)
                    if maxX != minX {
                        countRegion(map.labels[nearbyY * map.width + maxX], in: &counts)
                    }
                }
            }

            if let best = counts.indices.dropFirst().max(by: {
                counts[$0] < counts[$1]
            }), counts[best] > 0 {
                return UInt16(best)
            }
        }
        return nil
    }

    private static func countRegion(_ regionID: UInt16, in counts: inout [Int]) {
        let index = Int(regionID)
        guard index > 0, index < counts.count else { return }
        counts[index] += 1
    }

    private static func render(
        map: RegionMap,
        assignments: [UInt16: UIColor]
    ) -> UIImage? {
        let bytesPerRow = map.width * 4
        guard let context = CGContext(
            data: nil,
            width: map.width,
            height: map.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ), let output = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        var red = [UInt8](repeating: 0, count: map.regionCount + 1)
        var green = red
        var blue = red
        var alpha = red

        for (regionID, color) in assignments {
            let index = Int(regionID)
            guard index > 0, index <= map.regionCount else { continue }
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            red[index] = UInt8((r * a * 255).rounded())
            green[index] = UInt8((g * a * 255).rounded())
            blue[index] = UInt8((b * a * 255).rounded())
            alpha[index] = UInt8((a * 255).rounded())
        }

        for pixel in map.labels.indices {
            let regionID = Int(map.labels[pixel])
            guard regionID > 0, alpha[regionID] > 0 else { continue }
            let offset = pixel * 4
            output[offset] = red[regionID]
            output[offset + 1] = green[regionID]
            output[offset + 2] = blue[regionID]
            output[offset + 3] = alpha[regionID]
        }

        guard let image = context.makeImage() else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    private static func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(
            bounds.width / imageSize.width,
            bounds.height / imageSize.height
        )
        let size = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
enum MusicMood: Int, CaseIterable, Hashable, Identifiable {
    case joy, calm, expectation, low

    var id: Int { rawValue }
    var emotionKind: EmotionKind {
        switch self {
        case .joy: .joy
        case .calm: .calm
        case .expectation: .expectation
        case .low: .low
        }
    }
    var orbAsset: String {
        switch self {
        case .joy: "music_orb_joy"
        case .calm: "music_orb_calm"
        case .expectation: "music_orb_expectation"
        case .low: "music_orb_low"
        }
    }
    var orbFrameDuration: TimeInterval {
        switch self {
        case .joy: 1
        case .calm, .low: 2
        case .expectation: 0.8
        }
    }
    var waveFrameDuration: TimeInterval {
        self == .expectation ? 0.8 : 1
    }
    var waveMinimumHeight: CGFloat {
        switch self {
        case .joy: 5
        case .calm: 4
        case .expectation: 7
        case .low: 4
        }
    }
    var waveAmplitude: CGFloat {
        switch self {
        case .joy: 66
        case .calm: 40
        case .expectation: 72
        case .low: 34
        }
    }
    var wavePhaseSpacing: CGFloat {
        switch self {
        case .joy: 0.72
        case .calm: 0.46
        case .expectation: 0.86
        case .low: 0.38
        }
    }
    var waveGradient: [Color] {
        switch self {
        case .joy:
            [.white, Color(red: 1, green: 0.94, blue: 0.22), Color(red: 1, green: 0.55, blue: 0.43)]
        case .calm:
            [.white, Color(red: 0.10, green: 0.92, blue: 0.94), Color(red: 0, green: 0.74, blue: 0.80)]
        case .expectation:
            [.white, Color(red: 1, green: 0.77, blue: 0.22), Color(red: 1, green: 0.48, blue: 0.62)]
        case .low:
            [.white, Color(red: 0.32, green: 0.76, blue: 1), Color(red: 0.16, green: 0.43, blue: 0.85)]
        }
    }
}

struct AnimatedMoodOrb: View {
    let asset: String
    let frameDuration: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AnimatedFigmaSprite(
            asset: asset,
            frameCount: 4,
            secondsPerFrame: frameDuration,
            usesEaseInOut: false,
            pausesAnimation: reduceMotion
        )
    }
}

struct AnimatedWaveform: View {
    let mood: MusicMood
    let gradient: [Color]?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(mood: MusicMood, gradient: [Color]? = nil) {
        self.mood = mood
        self.gradient = gradient
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let barCount = max(31, Int(size.width / 8))
                let spacing = size.width / CGFloat(barCount)
                let center = CGFloat(barCount - 1) / 2

                for index in 0..<barCount {
                    let distance = abs(CGFloat(index) - center) / center
                    let phase = CGFloat(time / mood.waveFrameDuration) * .pi * 2
                        + CGFloat(index) * mood.wavePhaseSpacing
                    let primaryWave = (sin(phase) + 1) / 2
                    let secondaryWave = (sin(phase * 0.53 + CGFloat(index) * 0.31) + 1) / 2
                    let envelope = 0.28 + (1 - distance) * 0.72
                    let height = mood.waveMinimumHeight
                        + mood.waveAmplitude * envelope * (0.32 + primaryWave * 0.48 + secondaryWave * 0.20)
                    let x = (CGFloat(index) + 0.5) * spacing
                    let rect = CGRect(
                        x: x - 2,
                        y: (size.height - height) / 2,
                        width: 4,
                        height: height
                    )
                    let path = Path(roundedRect: rect, cornerRadius: 2)

                    context.drawLayer { layer in
                        layer.fill(
                                            path,
                                            with: .linearGradient(
                                                Gradient(colors: gradient ?? mood.waveGradient),
                                                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                                            )
                        )
                    }
                }
            }
        }
    }
}

private struct AnimatedFigmaSprite: View {
    let asset: String
    let frameCount: Int
    let secondsPerFrame: TimeInterval
    let usesEaseInOut: Bool
    let pausesAnimation: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: pausesAnimation)) { timeline in
            let rawPhase = pausesAnimation ? 0 : timeline.date.timeIntervalSinceReferenceDate / secondsPerFrame
            let baseFrame = Int(floor(rawPhase)) % frameCount
            let nextFrame = (baseFrame + 1) % frameCount
            let linearBlend = rawPhase - floor(rawPhase)
            let blend = usesEaseInOut
                ? (1 - cos(.pi * linearBlend)) / 2
                : linearBlend

            ZStack {
                spriteFrame(baseFrame)
                    .opacity(1 - blend)
                spriteFrame(nextFrame)
                    .opacity(blend)
            }
        }
        .clipped()
    }

    private func spriteFrame(_ index: Int) -> some View {
        GeometryReader { proxy in
            Image(asset)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height * CGFloat(frameCount)
                )
                .offset(y: -proxy.size.height * CGFloat(index))
        }
    }
}

/// AR
struct FigmaARView: View {
    var onTaskFlowChanged: (Bool) -> Void = { _ in }

    var body: some View {
        SproutlyARFlowView(onTaskFlowChanged: onTaskFlowChanged)
    }
}

struct FigmaScreenCanvas<Overlay: View>: View {
    let asset: String
    @ViewBuilder let overlay: (CGFloat) -> Overlay

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / 402, proxy.size.height / 874)
            let width = 402 * scale
            let height = 874 * scale

            ZStack {
                Image(asset)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
                overlay(scale)
            }
            .frame(width: width, height: height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .ignoresSafeArea()
    }
}
