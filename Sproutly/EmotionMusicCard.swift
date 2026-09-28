import SwiftUI
import UIKit

struct EmotionMusicCardPresentation {
    let id: UUID
    let artwork: UIImage?
    let fallbackArtworkAsset: String
    let face: UIImage?
    let fallbackFaceAsset: String
    let moodAsset: String
    let avatarHaloColor: Color
    let timestamp: Date
    let theme: String
    let durationSeconds: Int
    let moodColors: [Color]
    let reflection: String
}

struct EmotionMusicRecordScene: View {
    let data: EmotionMusicCardPresentation
    var showsCardStack = false
    var cardScale: CGFloat = 1
    var cardCenterY: CGFloat = 455

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / 402, proxy.size.height / 874)
            ZStack {
                EmotionMusicRecordBackdrop(data: data)

                EmotionMusicCardStack(data: data, showsBackCard: showsCardStack)
                    .frame(
                        width: 338 * cardScale * scale,
                        height: 659 * cardScale * scale
                    )
                    .position(x: 201 * scale, y: cardCenterY * scale)
            }
            .frame(width: 402 * scale, height: 874 * scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .ignoresSafeArea()
    }
}

struct EmotionMusicRecordBackdrop: View {
    let data: EmotionMusicCardPresentation

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / 402, proxy.size.height / 874)
            ZStack {
                EmotionMusicArtworkView(data: data, contentMode: .fill)
                    .frame(width: 577.153 * scale, height: 875.563 * scale)
                    .clipped()
                    .position(x: 201 * scale, y: 436.22 * scale)

                Color(red: 112 / 255, green: 142 / 255, blue: 142 / 255)
                    .opacity(0.88)

                Image("music_result_botanical_left")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96 * scale, height: 250 * scale)
                    .position(x: 36 * scale, y: 275 * scale)

                Image("music_result_botanical_right")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96 * scale, height: 250 * scale)
                    .rotationEffect(.degrees(180))
                    .position(x: 270 * scale, y: 405 * scale)
            }
            .frame(width: 402 * scale, height: 874 * scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .clipped()
    }
}

struct EmotionMusicCardStack: View {
    let data: EmotionMusicCardPresentation
    var showsBackCard = true

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 338
            ZStack {
                if showsBackCard {
                    EmotionMusicCardBack()
                        .frame(width: 338 * scale, height: 659 * scale)
                }

                EmotionMusicDiaryCard(data: data)
                    .frame(width: 338 * scale, height: 656 * scale)
            }
            .frame(width: 338 * scale, height: 659 * scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

struct EmotionMusicCardBack: View {
    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 338
            RoundedRectangle(cornerRadius: 15 * scale, style: .continuous)
                .fill(Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255))
                .overlay {
                    Image("music_result_paper_texture")
                        .resizable()
                        .scaledToFill()
                        .blendMode(.multiply)
                        .opacity(0.20)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 15 * scale, style: .continuous)
                        )
                }
                .rotationEffect(.degrees(5.07))
                .shadow(color: .black.opacity(0.08), radius: 8 * scale, y: 5 * scale)
        }
        .accessibilityHidden(true)
    }
}

struct EmotionMusicDiaryCard: View {
    let data: EmotionMusicCardPresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artworkVisible = false
    @State private var infoVisible = false
    @State private var noteVisible = false
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 338
            ZStack(alignment: .topLeading) {
                paper(scale: scale)
                header(scale: scale)

                artwork(scale: scale)
                    .opacity(artworkVisible ? 1 : 0)
                    .offset(y: artworkVisible ? 0 : -24 * scale)
                    .scaleEffect(artworkVisible ? 1 : 1.08)
                    .animation(
                        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.45),
                        value: artworkVisible
                    )

                recordInfo(scale: scale)
                    .opacity(infoVisible ? 1 : 0)
                    .offset(y: infoVisible ? 0 : 8 * scale)
                    .animation(
                        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.30),
                        value: infoVisible
                    )

                reflectionNote(scale: scale)
                    .opacity(noteVisible ? 1 : 0)
                    .offset(y: noteVisible ? 0 : 8 * scale)
                    .animation(
                        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.33),
                        value: noteVisible
                    )
            }
        }
        .task(id: data.id) { await revealContent() }
        .onDisappear { revealTask?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(data.theme)情绪乐卡")
    }

    private func paper(scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
            .fill(Color(red: 1, green: 253 / 255, blue: 249 / 255))
            .overlay {
                Image("music_result_paper_texture")
                    .resizable()
                    .scaledToFill()
                    .blendMode(.multiply)
                    .opacity(0.36)
                    .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
            }
            .shadow(
                color: Color(red: 31 / 255, green: 56 / 255, blue: 56 / 255).opacity(0.12),
                radius: 7 * scale,
                y: 5 * scale
            )
    }

    private func header(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            EmotionMusicWave(seed: data.id.hashValue)
                .frame(width: 220 * scale, height: 26 * scale)
                .offset(x: 80 * scale, y: 21 * scale)

            ZStack {
                Circle()
                    .fill(data.avatarHaloColor)

                Group {
                    if let face = data.face {
                        Image(uiImage: face)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(data.fallbackFaceAsset)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 50 * scale, height: 50 * scale)
                .clipShape(Circle())

                Image(data.moodAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28 * scale, height: 28 * scale)
                    .offset(x: 20 * scale, y: 20 * scale)
            }
            .frame(width: 60 * scale, height: 60 * scale)
            .offset(x: 7 * scale, y: 7 * scale)
        }
    }

    private func artwork(scale: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                .fill(Color(red: 203 / 255, green: 207 / 255, blue: 242 / 255))
                .frame(width: 302 * scale, height: 397.363 * scale)
                .rotationEffect(.degrees(-1.2))

            RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                .fill(.white)
                .frame(width: 286 * scale, height: 381.808 * scale)
                .shadow(color: Color.black.opacity(0.10), radius: 4 * scale, y: 3 * scale)

            EmotionMusicArtworkView(data: data, contentMode: .fill)
                .frame(width: 268.506 * scale, height: 363.621 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))

            tape(scale: scale)
                .rotationEffect(.degrees(-46.2))
                .offset(x: -137 * scale, y: -180 * scale)
            tape(scale: scale)
                .rotationEffect(.degrees(43.8))
                .offset(x: 137 * scale, y: -187 * scale)
            tape(scale: scale)
                .rotationEffect(.degrees(43.8))
                .offset(x: -137 * scale, y: 190 * scale)
            tape(scale: scale)
                .rotationEffect(.degrees(-46.2))
                .offset(x: 137 * scale, y: 187 * scale)

            diaryStamp(scale: scale)
                .frame(width: 69.334 * scale, height: 69.334 * scale)
                .rotationEffect(.degrees(-1.2))
                .offset(x: 112 * scale, y: -164 * scale)
        }
        .frame(width: 310 * scale, height: 410 * scale)
        .position(x: 169 * scale, y: 264 * scale)
    }

    private func recordInfo(scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            infoColumn(title: "日期", value: dateText, width: 52, scale: scale)
            infoDivider(scale: scale)
            infoColumn(title: "主题", value: data.theme, width: 61, scale: scale)
            infoDivider(scale: scale)
            infoColumn(title: "用时", value: durationText, width: 52, scale: scale)

            VStack(alignment: .leading, spacing: 4 * scale) {
                Text("情绪主色彩")
                    .gardenFont(size: 12 * scale, weight: .bold)
                    .lineLimit(1)
                HStack(spacing: 8 * scale) {
                    ForEach(Array(displayColors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 14 * scale, height: 14 * scale)
                    }
                }
            }
            .foregroundStyle(Color(red: 49 / 255, green: 91 / 255, blue: 93 / 255))
            .frame(width: 62 * scale, height: 48 * scale, alignment: .leading)
        }
        .frame(width: 288 * scale, height: 58 * scale)
        .position(x: 176.9 * scale, y: 515.4 * scale)
    }

    private func reflectionNote(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("music_result_note")
                .resizable()
                .scaledToFit()
                .frame(width: 294 * scale, height: 92.5 * scale)
                .offset(x: 4 * scale, y: 4.4 * scale)

            Image("music_result_handprint")
                .resizable()
                .scaledToFit()
                .frame(width: 34 * scale, height: 48 * scale)
                .offset(x: 18 * scale, y: 25.5 * scale)

            VStack(alignment: .leading, spacing: 4 * scale) {
                Text("今天情绪小记")
                    .gardenFont(size: 16 * scale, weight: .bold)
                Text(data.reflection)
                    .gardenFont(size: 14 * scale, weight: .medium)
                    .lineSpacing(2 * scale)
                    .lineLimit(2)
            }
            .foregroundStyle(Color(red: 49 / 255, green: 91 / 255, blue: 93 / 255))
            .frame(width: 210 * scale, alignment: .leading)
            .offset(x: 65.9 * scale, y: 14.4 * scale)
        }
        .frame(width: 302 * scale, height: 120 * scale, alignment: .topLeading)
        .position(x: 169 * scale, y: 606.5 * scale)
    }

    private func tape(scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
            .fill(Color(red: 220 / 255, green: 231 / 255, blue: 227 / 255))
            .opacity(0.72)
            .frame(width: 60 * scale, height: 18 * scale)
    }

    private func diaryStamp(scale: CGFloat) -> some View {
        ZStack {
            Image("music_result_dashed_ring")
                .resizable()
                .scaledToFit()
                .frame(width: 58 * scale, height: 58 * scale)
            VStack(spacing: 0) {
                Text(monthText)
                    .gardenFont(size: 10 * scale, weight: .medium)
                Text(dayText)
                    .gardenFont(size: 14 * scale, weight: .bold)
            }
            .foregroundStyle(Color(red: 104 / 255, green: 102 / 255, blue: 176 / 255))
        }
    }

    private func infoColumn(
        title: String,
        value: String,
        width: CGFloat,
        scale: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text(title)
                .gardenFont(size: 12 * scale, weight: .bold)
                .foregroundStyle(Color(red: 89 / 255, green: 109 / 255, blue: 109 / 255))
            Text(value)
                .gardenFont(size: 12 * scale, weight: .medium)
                .foregroundStyle(Color(red: 49 / 255, green: 91 / 255, blue: 93 / 255))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: width * scale, height: 48 * scale, alignment: .leading)
    }

    private func infoDivider(scale: CGFloat) -> some View {
        Rectangle()
            .fill(Color(red: 200 / 255, green: 191 / 255, blue: 175 / 255))
            .frame(width: scale, height: 36 * scale)
    }

    private var displayColors: [Color] {
        let fallback = [
            Color(red: 98 / 255, green: 85 / 255, blue: 181 / 255),
            Color(red: 112 / 255, green: 146 / 255, blue: 196 / 255),
            Color(red: 132 / 255, green: 154 / 255, blue: 77 / 255)
        ]
        return Array((data.moodColors + fallback).prefix(3))
    }

    private var monthText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter.string(from: data.timestamp).uppercased()
    }

    private var dayText: String {
        String(Calendar.autoupdatingCurrent.component(.day, from: data.timestamp))
    }

    private var dateText: String { "\(monthText) \(dayText)" }

    private var durationText: String {
        let seconds = max(0, data.durationSeconds)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    @MainActor
    private func revealContent() async {
        revealTask?.cancel()
        artworkVisible = reduceMotion
        infoVisible = reduceMotion
        noteVisible = reduceMotion
        guard !reduceMotion else { return }

        revealTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            artworkVisible = true
            try? await Task.sleep(for: .milliseconds(630))
            guard !Task.isCancelled else { return }
            infoVisible = true
            try? await Task.sleep(for: .milliseconds(270))
            guard !Task.isCancelled else { return }
            noteVisible = true
        }
        await revealTask?.value
    }
}

struct EmotionMusicArtworkView: View {
    let data: EmotionMusicCardPresentation
    let contentMode: ContentMode

    var body: some View {
        Group {
            if let artwork = data.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(data.fallbackArtworkAsset)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            }
        }
    }
}

struct EmotionMusicWave: View {
    let seed: Int

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 220
            TimelineView(.animation(minimumInterval: 1 / 18)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate * 3.1
                HStack(spacing: 4 * scale) {
                    ForEach(0..<31, id: \.self) { index in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 97 / 255, green: 85 / 255, blue: 245 / 255),
                                        Color(red: 195 / 255, green: 252 / 255, blue: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: 3 * scale,
                                height: (7 + 15 * abs(
                                    sin(phase + Double(index) * 0.66 + Double(seed % 17) * 0.1)
                                )) * scale
                            )
                            .opacity(0.72)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

struct EmotionMusicRecordButtons: View {
    let scale: CGFloat
    let openAlbum: () -> Void
    let returnHome: () -> Void

    var body: some View {
        VStack(spacing: 12 * scale) {
            Button(action: openAlbum) {
                HStack(spacing: 8 * scale) {
                    Text("查看我的乐卡")
                        .gardenFont(size: 14 * scale, weight: .bold)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13 * scale, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(width: 232 * scale, height: 48 * scale)
                .background(GardenTheme.deepMint, in: Capsule())
                .musicGlossCapsule(scale: scale)
            }
            .buttonStyle(.plain)

            Button(action: returnHome) {
                Text("返回音乐首页")
                    .gardenFont(size: 14 * scale, weight: .bold)
                    .foregroundStyle(Color(red: 47 / 255, green: 104 / 255, blue: 91 / 255))
                    .frame(width: 232 * scale, height: 46 * scale)
                    .background(.white.opacity(0.86), in: Capsule())
                    .musicGlossCapsule(scale: scale)
            }
            .buttonStyle(.plain)
        }
    }
}

enum MusicArtworkSnapshotStore {
    static func save(_ image: UIImage) -> String? {
        let normalized = image.normalizedMusicArtwork(maxDimension: 1800)
        guard let data = normalized.jpegData(compressionQuality: 0.92) else { return nil }
        let name = UUID().uuidString + ".jpg"
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func load(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static var directory: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("Sproutly", isDirectory: true)
            .appendingPathComponent("MusicArtwork", isDirectory: true)
    }
}

private extension UIImage {
    func normalizedMusicArtwork(maxDimension: CGFloat) -> UIImage {
        let ratio = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(
            width: max(1, size.width * ratio),
            height: max(1, size.height * ratio)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
