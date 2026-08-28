import AVFoundation
import Charts
import SwiftUI
import UIKit

/// 音乐1
private struct LegacyFigmaMusicView: View {
    var onGuidanceFlowChanged: (Bool) -> Void = { _ in }

    @EnvironmentObject private var store: GardenStore
    @State private var page = 1
    @State private var selectedMood: MusicMood = .joy
    @State private var showsMoodDetail = false
    @State private var usesHomepageOrb = true
    @State private var guidancePlan: EmotionGuidancePlan?
    @State private var activePlan: EmotionGuidancePlan?
    @StateObject private var moodMusicPlayer = MoodMusicPlayer()

    private let guidanceProvider = LocalEmotionGuidanceProvider()

    var body: some View {
        ZStack {
            Group {
                if page == 1 {
                    musicSpace
                } else if page == 6 {
                    MusicColoringExperience(
                        plan: activePlan ?? guidanceProvider.plan(for: selectedMood),
                        onClose: {
                            page = 1
                            showsMoodDetail = true
                        },
                        onComplete: {
                            activePlan = nil
                            page = 1
                            showsMoodDetail = false
                        }
                    )
                } else {
                    libraryPage
                }
            }

            if let guidancePlan {
                EmotionGuidancePlanView(
                    plan: guidancePlan,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            self.guidancePlan = nil
                            showsMoodDetail = true
                        }
                    },
                    onStart: {
                        activePlan = guidancePlan
                        self.guidancePlan = nil
                        page = 6
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: guidancePlan?.id)
        .onAppear {
            moodMusicPlayer.preload()
            updateMusicSpacePlayback()
            onGuidanceFlowChanged(blocksTabNavigation)
        }
        .onChange(of: selectedMood) { _, _ in
            updateMusicSpacePlayback()
        }
        .onChange(of: page) { _, _ in
            updateMusicSpacePlayback()
        }
        .onChange(of: guidancePlan?.id) { _, _ in
            updateMusicSpacePlayback()
        }
        .onChange(of: blocksTabNavigation) { _, isBlocked in
            onGuidanceFlowChanged(isBlocked)
        }
        .onDisappear {
            moodMusicPlayer.stop()
            onGuidanceFlowChanged(false)
        }
    }

    private var blocksTabNavigation: Bool {
        guidancePlan != nil || page == 6
    }

    private func updateMusicSpacePlayback() {
        if page == 1, guidancePlan == nil {
            moodMusicPlayer.play(selectedMood)
        } else {
            moodMusicPlayer.stop()
        }
    }

    private var musicSpace: some View {
        ZStack {
            FigmaScreenCanvas(asset: "figma_music_1") { scale in
                Group {
                    // 只替换需要动起来的区域，其余像素继续使用 Figma 原稿。
                    SproutlyHomeGradientSlice(
                        sourceY: 425,
                        sourceHeight: 70,
                        scale: scale
                    )
                        .frame(width: 402 * scale, height: 70 * scale)
                        .position(x: 201 * scale, y: 460 * scale)
                    Color.white
                        .frame(width: 226 * scale, height: 226 * scale)
                        .clipShape(Circle())
                        .position(x: 201 * scale, y: 295 * scale)
                    SproutlyHomeGradientSlice(
                        sourceY: 543,
                        sourceHeight: 193,
                        scale: scale
                    )
                        .frame(width: 402 * scale, height: 193 * scale)
                        .position(x: 201 * scale, y: 639.5 * scale)
                    // Figma 底图自带 3 个静态圆点；先用渐变终点的纯白色完整遮盖，
                    // 再在下方绘制与 4 张动态卡片一一对应的分页器。
                    Color.white
                        .frame(width: 402 * scale, height: 20 * scale)
                        .position(x: 201 * scale, y: 748 * scale)

                    MusicMotionHeader(
                        mood: selectedMood,
                        orbAsset: usesHomepageOrb ? "music_orb_home" : selectedMood.orbAsset,
                        scale: scale,
                        spansFullWidth: false
                    )

                    if store.kakaAppearance != .happy {
                        SproutlyHomeGradientSlice(
                            sourceY: 276,
                            sourceHeight: 94,
                            scale: scale
                        )
                        .frame(width: 83 * scale, height: 94 * scale)
                        .clipped()
                        .position(x: 363.5 * scale, y: 323 * scale)

                        KakaAvatarView(magnification: 1.32)
                            .frame(width: 94 * scale, height: 82 * scale)
                            .position(x: 374 * scale, y: 323 * scale)
                            .allowsHitTesting(false)
                    }

                    MusicCardCarousel(selection: $selectedMood) { mood in
                        selectedMood = mood
                        usesHomepageOrb = false
                        withAnimation(.easeInOut(duration: 0.28)) {
                            showsMoodDetail = true
                        }
                    }
                    .frame(width: 402 * scale, height: 193 * scale)
                    .position(x: 201 * scale, y: 639.5 * scale)
                    .onChange(of: selectedMood) { _, _ in
                        usesHomepageOrb = false
                    }

                    HStack(spacing: 10 * scale) {
                        ForEach(MusicMood.allCases) { mood in
                            Circle()
                                .fill(
                                    mood == selectedMood
                                        ? Color(red: 0, green: 0.76, blue: 0.82)
                                        : Color(red: 0.74, green: 0.98, blue: 0.96)
                                )
                                .frame(width: 10 * scale, height: 10 * scale)
                        }
                    }
                    .position(x: 201 * scale, y: 748 * scale)

                    hotspot(x: 75, y: 64, width: 125, height: 48, scale: scale) {
                        withAnimation(.easeInOut(duration: 0.35)) { page = 7 }
                    }
                }
            }

            if showsMoodDetail {
                MusicMoodDetail(
                    selection: $selectedMood,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            showsMoodDetail = false
                        }
                    },
                    onSelect: {
                        store.recordEmotion(selectedMood.emotionKind, source: .musicCheckIn)
                        let plan = guidanceProvider.plan(for: selectedMood)
                        withAnimation(.easeInOut(duration: 0.28)) {
                            showsMoodDetail = false
                            guidancePlan = plan
                        }
                    },
                    onOpenLibrary: {
                        showsMoodDetail = false
                        withAnimation(.easeInOut(duration: 0.35)) {
                            page = 7
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
    }

    private var libraryPage: some View {
        FigmaScreenCanvas(asset: "figma_music_\(page)") { scale in
            Group {
                if page == 6 {
                    hotspot(x: 356, y: 122, width: 46, height: 52, scale: scale) {
                        page = 1
                        showsMoodDetail = true
                    }
                } else if page == 7 {
                    hotspot(x: 280, y: 570, width: 108, height: 100, scale: scale) {
                        page = 8
                    }
                    hotspot(x: 280, y: 665, width: 108, height: 90, scale: scale) {
                        page = 9
                    }
                } else {
                    hotspot(x: 18, y: 58, width: 52, height: 55, scale: scale) {
                        page = 7
                    }
                }
                if page == 7 {
                    hotspot(x: 195, y: 64, width: 130, height: 48, scale: scale) {
                        withAnimation(.easeInOut(duration: 0.35)) { page = 1 }
                    }
                }
            }
        }
    }
}

private struct MindfulSynthesisPreset {
    let rootFrequency: Double
    let harmonyRatio: Double
    let pulseFrequency: Double
    let brightness: Double

    func interpolated(
        to target: MindfulSynthesisPreset,
        progress: Double
    ) -> MindfulSynthesisPreset {
        let amount = min(max(progress, 0), 1)
        return MindfulSynthesisPreset(
            rootFrequency: rootFrequency + (target.rootFrequency - rootFrequency) * amount,
            harmonyRatio: harmonyRatio + (target.harmonyRatio - harmonyRatio) * amount,
            pulseFrequency: pulseFrequency + (target.pulseFrequency - pulseFrequency) * amount,
            brightness: brightness + (target.brightness - brightness) * amount
        )
    }
}

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

private struct EmotionGuidanceStage: Identifiable {
    let id: Int
    let title: String
    let musicType: String
    let guidance: String
    let duration: TimeInterval
    let accent: Color
    let preset: MindfulSynthesisPreset
}

private struct EmotionGuidancePlan: Identifiable {
    let id = UUID()
    let mood: MusicMood
    let target: String
    let summary: String
    let stages: [EmotionGuidanceStage]

    var totalDuration: TimeInterval {
        stages.reduce(0) { $0 + $1.duration }
    }

    var totalMinutes: Int {
        max(1, Int(ceil(totalDuration / 60)))
    }

    func stageIndex(at elapsed: TimeInterval) -> Int {
        guard !stages.isEmpty else { return 0 }
        let time = min(max(elapsed, 0), totalDuration)
        var boundary: TimeInterval = 0
        for (index, stage) in stages.enumerated() {
            boundary += stage.duration
            if time < boundary || index == stages.count - 1 {
                return index
            }
        }
        return stages.count - 1
    }

    func synthesisPreset(at elapsed: TimeInterval) -> MindfulSynthesisPreset {
        guard !stages.isEmpty else {
            return MindfulSynthesisPreset(
                rootFrequency: 220,
                harmonyRatio: 1.5,
                pulseFrequency: 0.6,
                brightness: 0.3
            )
        }

        let index = stageIndex(at: elapsed)
        let stageStart = stages.prefix(index).reduce(0) { $0 + $1.duration }
        let stage = stages[index]
        let nextStage = stages[min(index + 1, stages.count - 1)]
        let localProgress = stage.duration > 0
            ? min(max((elapsed - stageStart) / stage.duration, 0), 1)
            : 1
        let transitionProgress = min(max((localProgress - 0.22) / 0.78, 0), 1)
        let easedProgress = transitionProgress * transitionProgress * (3 - 2 * transitionProgress)
        return stage.preset.interpolated(
            to: nextStage.preset,
            progress: easedProgress
        )
    }
}

private protocol EmotionGuidanceProviding {
    func plan(for mood: MusicMood) -> EmotionGuidancePlan
}

/// 本地可解释的情绪匹配实现。后续接入经审核的大模型服务时，只需替换此 Provider。
private struct LocalEmotionGuidanceProvider: EmotionGuidanceProviding {
    func plan(for mood: MusicMood) -> EmotionGuidancePlan {
        switch mood {
        case .joy:
            EmotionGuidancePlan(
                mood: mood,
                target: "从快乐慢慢回到平稳",
                summary: "先接住快乐的能量，再用柔和节律帮助身体安静下来。",
                stages: [
                    stage(0, "接住快乐", "轻快律动", "跟着明亮的节拍，选一种最喜欢的颜色。", 246.94, 1.02, 0.66, .orange),
                    stage(1, "轻柔摆动", "舒缓木琴", "让动作慢一点，把颜色轻轻铺进花瓣。", 246.94, 0.82, 0.46, Color(red: 0.18, green: 0.84, blue: 0.82)),
                    stage(2, "平稳停靠", "温暖氛围音", "看看画面，做一次慢慢的呼吸。", 246.94, 0.64, 0.30, Color(red: 0.35, green: 0.70, blue: 0.92))
                ]
            )
        case .calm:
            EmotionGuidancePlan(
                mood: mood,
                target: "保持平静，进入温柔专注",
                summary: "稳定的节律会陪伴填色，让注意力自然停留在当下。",
                stages: [
                    stage(0, "保持平稳", "自然氛围音", "听一听稳定的声音，从喜欢的区域开始。", 220.00, 0.62, 0.26, Color(red: 0.12, green: 0.82, blue: 0.84)),
                    stage(1, "安静专注", "柔和钢琴", "留意每一次落笔，不用着急完成。", 220.00, 0.56, 0.32, Color(red: 0.35, green: 0.72, blue: 0.94)),
                    stage(2, "温暖收束", "低频和声", "选最后一种颜色，为今天的感受留个位置。", 220.00, 0.50, 0.24, Color(red: 0.55, green: 0.62, blue: 0.92))
                ]
            )
        case .expectation:
            EmotionGuidancePlan(
                mood: mood,
                target: "让兴奋的能量慢慢安静",
                summary: "音乐会先贴近现在的节奏，再逐步放慢，帮助身体恢复舒适。",
                stages: [
                    stage(0, "跟上节奏", "明亮律动", "先不用压住兴奋，跟着节奏选出第一种颜色。", 233.08, 1.16, 0.66, Color(red: 1.00, green: 0.62, blue: 0.26)),
                    stage(1, "放慢呼吸", "舒缓节拍", "音乐变慢了，试着让涂色动作也慢下来。", 233.08, 0.78, 0.44, Color(red: 0.24, green: 0.84, blue: 0.80)),
                    stage(2, "安静专注", "轻柔环境音", "把注意力放在一个小区域，慢慢把它填满。", 233.08, 0.54, 0.26, Color(red: 0.34, green: 0.66, blue: 0.92))
                ]
            )
        case .low:
            EmotionGuidancePlan(
                mood: mood,
                target: "从低落走向温暖和希望",
                summary: "不催促情绪离开，音乐会先陪伴，再一点点增加明亮感。",
                stages: [
                    stage(0, "接住现在", "温暖低频和声", "现在的感受可以留在这里，先选一种舒服的颜色。", 220.00, 0.48, 0.20, Color(red: 0.35, green: 0.58, blue: 0.90)),
                    stage(1, "慢慢抬头", "柔和木琴", "听见一点更亮的声音，再为花朵添一种颜色。", 220.00, 0.64, 0.42, Color(red: 0.24, green: 0.82, blue: 0.76)),
                    stage(2, "看见亮光", "明亮自然音景", "看看已经完成的颜色，把喜欢的部分留在心里。", 220.00, 0.78, 0.60, Color(red: 1.00, green: 0.76, blue: 0.30))
                ]
            )
        }
    }

    private func stage(
        _ id: Int,
        _ title: String,
        _ musicType: String,
        _ guidance: String,
        _ rootFrequency: Double,
        _ pulseFrequency: Double,
        _ brightness: Double,
        _ accent: Color
    ) -> EmotionGuidanceStage {
        EmotionGuidanceStage(
            id: id,
            title: title,
            musicType: musicType,
            guidance: guidance,
            duration: 15,
            accent: accent,
            preset: MindfulSynthesisPreset(
                rootFrequency: rootFrequency,
                harmonyRatio: 1.5,
                pulseFrequency: pulseFrequency,
                brightness: brightness
            )
        )
    }
}

private struct EmotionGuidancePlanView: View {
    let plan: EmotionGuidancePlan
    let onClose: () -> Void
    let onStart: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / 402, proxy.size.height / 874)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.82, green: 1.00, blue: 0.97),
                        Color(red: 0.95, green: 1.00, blue: 0.99),
                        .white
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(plan.stages.first?.accent.opacity(0.22) ?? .clear)
                    .frame(width: 270 * scale, height: 270 * scale)
                    .blur(radius: 48 * scale)
                    .position(x: 304 * scale, y: 128 * scale)

                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4 * scale) {
                            Text("为你生成的音乐旅程")
                                .gardenFont(size: 25 * scale, weight: .bold)
                            Text("当前心情 · \(plan.mood.title)")
                                .gardenFont(size: 13 * scale)
                                .opacity(0.62)
                        }
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16 * scale, weight: .bold))
                                .frame(width: 42 * scale, height: 42 * scale)
                                .background(.white.opacity(0.72), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭")
                    }
                    .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))

                    HStack(spacing: 14 * scale) {
                        AnimatedMoodOrb(
                            asset: plan.mood.orbAsset,
                            frameDuration: plan.mood.orbFrameDuration
                        )
                        .frame(width: 92 * scale, height: 92 * scale)

                        VStack(alignment: .leading, spacing: 7 * scale) {
                            Text(plan.target)
                                .gardenFont(size: 19 * scale, weight: .bold)
                            Text(plan.summary)
                                .gardenFont(size: 12 * scale)
                                .lineSpacing(3 * scale)
                                .opacity(0.72)
                        }
                        .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
                    }
                    .padding(.top, 24 * scale)

                    VStack(spacing: 0) {
                        ForEach(Array(plan.stages.enumerated()), id: \.element.id) { index, stage in
                            stageRow(stage, number: index + 1, scale: scale)
                            if index < plan.stages.count - 1 {
                                Rectangle()
                                    .fill(Color(red: 0.10, green: 0.73, blue: 0.75).opacity(0.18))
                                    .frame(height: 1 * scale)
                                    .padding(.leading, 48 * scale)
                            }
                        }
                    }
                    .padding(.horizontal, 14 * scale)
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 24 * scale, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                            .stroke(.white.opacity(0.88), lineWidth: 1 * scale)
                    }
                    .shadow(color: Color(red: 0, green: 0.45, blue: 0.48).opacity(0.09), radius: 18 * scale, y: 8 * scale)
                    .padding(.top, 22 * scale)

                    Spacer(minLength: 18 * scale)

                    Button(action: onStart) {
                        HStack(spacing: 9 * scale) {
                            Image(systemName: "play.fill")
                            Text("开始音乐引导 · \(plan.totalMinutes) 分钟")
                                .gardenFont(size: 17 * scale, weight: .bold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56 * scale)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.13, green: 0.83, blue: 0.81),
                                    Color(red: 0.05, green: 0.68, blue: 0.76)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                        .shadow(color: Color(red: 0.05, green: 0.68, blue: 0.76).opacity(0.24), radius: 13 * scale, y: 7 * scale)
                    }
                    .buttonStyle(.plain)

                    Text("用于日常情绪陪伴，不替代专业治疗建议")
                        .gardenFont(size: 10 * scale)
                        .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34).opacity(0.46))
                        .padding(.top, 12 * scale)
                }
                .padding(.horizontal, 24 * scale)
                .padding(.top, 54 * scale)
                .padding(.bottom, 34 * scale)
                .frame(width: 402 * scale, height: 874 * scale)
            }
            .frame(width: 402 * scale, height: 874 * scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .ignoresSafeArea()
    }

    private func stageRow(
        _ stage: EmotionGuidanceStage,
        number: Int,
        scale: CGFloat
    ) -> some View {
        HStack(spacing: 12 * scale) {
            Text("\(number)")
                .gardenFont(size: 14 * scale, weight: .bold)
                .foregroundStyle(.white)
                .frame(width: 32 * scale, height: 32 * scale)
                .background(stage.accent, in: Circle())

            VStack(alignment: .leading, spacing: 3 * scale) {
                HStack(spacing: 7 * scale) {
                    Text(stage.title)
                        .gardenFont(size: 16 * scale, weight: .bold)
                    Text(stage.musicType)
                        .gardenFont(size: 10 * scale)
                        .padding(.horizontal, 8 * scale)
                        .padding(.vertical, 3 * scale)
                        .background(stage.accent.opacity(0.15), in: Capsule())
                }
                Text(stage.guidance)
                    .gardenFont(size: 11 * scale)
                    .opacity(0.64)
                    .lineLimit(2)
            }
            .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
            Spacer(minLength: 0)
        }
        .frame(minHeight: 82 * scale)
    }
}

/// 音乐6
private struct MusicColoringExperience: View {
    @EnvironmentObject private var store: GardenStore
    @StateObject private var voiceMonitor = SingingVoiceMonitor()
    @StateObject private var musicPlayer = MindfulMusicPlayer()
    @State private var selectedColorIndex = 1
    @State private var selectedArtworkIndex = 0
    @State private var coloredImages: [UIImage?] = [nil]
    @State private var colorAssignments: [[UInt8: UIColor]] = [[:]]
    @State private var isPlaying = true
    @State private var stageIndex = 0
    @State private var elapsed: TimeInterval = 0
    @State private var showsReflection = false
    @State private var showsMicrophoneAlert = false
    @State private var showsAudioAlert = false
    @State private var synthesisPulse: CGFloat = 0
    @State private var colorProfile = MindfulColorProfile.empty

    let plan: EmotionGuidancePlan
    let onClose: () -> Void
    let onComplete: () -> Void

    private let outlineAssets = ["music313_outline"]

    private let regionAssets = ["music313_regions"]

    private let colors: [UIColor] = [
        UIColor(red: 0.20, green: 0.49, blue: 0.91, alpha: 1.00),
        UIColor(red: 0.08, green: 0.94, blue: 0.91, alpha: 1.00),
        UIColor(red: 0.42, green: 0.94, blue: 0.80, alpha: 1.00),
        UIColor(red: 0.48, green: 0.43, blue: 0.95, alpha: 1.00),
        UIColor(red: 0.96, green: 0.74, blue: 0.90, alpha: 1.00),
        UIColor(red: 1.00, green: 0.77, blue: 0.72, alpha: 1.00),
        UIColor(red: 1.00, green: 0.91, blue: 0.43, alpha: 1.00),
        UIColor(red: 0.94, green: 0.49, blue: 0.79, alpha: 1.00)
    ]

    var body: some View {
        ZStack {
            FigmaScreenCanvas(asset: "figma_music_6") { scale in
                Group {
                    GuidanceSessionPill(
                        stage: currentStage,
                        progress: journeyProgress
                    )
                    .frame(width: 326 * scale, height: 61 * scale)
                    .position(x: 201 * scale, y: 287 * scale)

                    MusicColoringPager(
                        outlineAssets: outlineAssets,
                        regionAssets: regionAssets,
                        selectedColor: colors[selectedColorIndex],
                        onRegionFilled: { color, regionFraction, profile in
                            respondToColoring(
                                color: color,
                                regionFraction: regionFraction,
                                profile: profile
                            )
                        },
                        selectedIndex: $selectedArtworkIndex,
                        coloredImages: $coloredImages,
                        colorAssignments: $colorAssignments
                    )
                    .frame(width: 308 * scale, height: 338 * scale)
                    .position(x: 216 * scale, y: 499 * scale)

                    VStack(spacing: 9 * scale) {
                        ForEach(colors.indices, id: \.self) { index in
                            Button {
                                selectedColorIndex = index
                            } label: {
                                paletteSwatch(index: index, scale: scale)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("选择颜色")
                            .accessibilityValue(index == selectedColorIndex ? "已选择" : "")
                        }
                    }
                    .position(x: 38.4 * scale, y: 484.8 * scale)

                    SingingWaveform(
                        level: voiceMonitor.level,
                        synthesisLevel: synthesisPulse,
                        isListening: voiceMonitor.isListening,
                        isPlaying: isPlaying,
                        pulseFrequency: visualPreset.pulseFrequency,
                        brightness: visualPreset.brightness,
                        accent: colorProfile.hasColor
                            ? colorProfile.visualAccent
                            : currentStage.accent
                    )
                    .frame(width: 402 * scale, height: 48 * scale)
                    .position(x: 201 * scale, y: 773 * scale)
                    .allowsHitTesting(false)

                    if voiceMonitor.isListening {
                        Circle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 3 * scale)
                            .frame(width: 116 * scale, height: 116 * scale)
                            .shadow(
                                color: Color(red: 0.17, green: 0.92, blue: 0.91).opacity(0.85),
                                radius: (13 + voiceMonitor.level * 18) * scale
                            )
                            .position(x: 201 * scale, y: 773 * scale)
                            .allowsHitTesting(false)
                    }

                    Button {
                        Task {
                            if voiceMonitor.isListening {
                                voiceMonitor.stop(deactivateSession: false)
                            } else if await !voiceMonitor.start() {
                                showsMicrophoneAlert = true
                            }
                        }
                    } label: {
                        Color.clear
                            .frame(width: 116 * scale, height: 116 * scale)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(x: 201 * scale, y: 773 * scale)
                    .accessibilityLabel(voiceMonitor.isListening ? "停止唱歌" : "开始唱歌")

                    Button {
                        togglePlayback()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(isPlaying ? 0.001 : 0.58))
                            if !isPlaying {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12 * scale, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 32 * scale, height: 32 * scale)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(x: 157 * scale, y: 207 * scale)
                    .accessibilityLabel(isPlaying ? "暂停音乐" : "继续音乐")

                    hotspot(x: 360, y: 124, width: 42, height: 48, scale: scale) {
                        stopAudioSession()
                        onClose()
                    }
                }
            }

            if showsReflection {
                EmotionReflectionOverlay(
                    sourceMood: plan.mood,
                    onDone: { choice in
                        store.recordEmotion(
                            reflectionEmotion(for: choice),
                            source: .musicReflection
                        )
                        stopAudioSession()
                        onComplete()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(30)
            }
        }
        .task {
            startJourney()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { break }
                if isPlaying && !showsReflection {
                    elapsed = min(elapsed + 0.25, plan.totalDuration)
                    stageIndex = plan.stageIndex(at: elapsed)
                    musicPlayer.updateJourney(
                        mood: plan.mood,
                        progress: journeyProgress
                    )
                    if elapsed >= plan.totalDuration {
                        completeJourney()
                    }
                }
            }
        }
        .onDisappear {
            stopAudioSession()
        }
        .alert("需要麦克风权限", isPresented: $showsMicrophoneAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请在“设置 → 隐私与安全性 → 麦克风”中允许“灵想”使用麦克风。")
        }
        .alert("暂时无法播放音乐", isPresented: $showsAudioAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请检查网络和设备音量后重试。填色功能仍可继续使用。")
        }
    }

    private var currentStage: EmotionGuidanceStage {
        plan.stages[min(max(stageIndex, 0), plan.stages.count - 1)]
    }

    private var journeyProgress: Double {
        guard plan.totalDuration > 0 else { return 0 }
        return min(max(elapsed / plan.totalDuration, 0), 1)
    }

    private var visualPreset: MindfulSynthesisPreset {
        let base = plan.synthesisPreset(at: elapsed)
        guard colorProfile.hasColor else { return base }
        let influence = min(colorProfile.coloredFraction / 0.62, 1)
        let colorEnergy = (colorProfile.meanSaturation - 0.5) * 0.38
            + (colorProfile.warmProportion - colorProfile.coolProportion) * 0.28
        return MindfulSynthesisPreset(
            rootFrequency: base.rootFrequency,
            harmonyRatio: base.harmonyRatio,
            pulseFrequency: min(
                max(base.pulseFrequency + colorEnergy * influence, 0.22),
                1.24
            ),
            brightness: min(
                max(
                    base.brightness
                        + (colorProfile.meanBrightness - 0.5) * 0.34 * influence,
                    0.12
                ),
                0.82
            )
        )
    }

    private func startJourney() {
        guard !plan.stages.isEmpty else { return }
        isPlaying = true
        if !musicPlayer.play(plan: plan) {
            showsAudioAlert = true
        } else {
            musicPlayer.updateJourney(mood: plan.mood, progress: 0)
        }
    }

    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            if !musicPlayer.resume() {
                showsAudioAlert = true
            } else {
                musicPlayer.updateJourney(
                    mood: plan.mood,
                    progress: journeyProgress
                )
            }
        } else {
            musicPlayer.pause()
            voiceMonitor.pauseLevelDisplay()
        }
    }

    private func respondToColoring(
        color: UIColor,
        regionFraction: CGFloat,
        profile: MindfulColorProfile
    ) {
        colorProfile = profile
        musicPlayer.respondToColoring(
            color: color,
            regionFraction: regionFraction,
            profile: profile,
            mood: plan.mood,
            progress: journeyProgress
        )

        synthesisPulse = 1
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            withAnimation(.easeOut(duration: 0.78)) {
                synthesisPulse = 0
            }
        }
    }

    private func completeJourney() {
        guard !showsReflection else { return }
        musicPlayer.pause()
        isPlaying = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            showsReflection = true
        }
    }

    private func stopAudioSession() {
        voiceMonitor.stop(deactivateSession: false)
        musicPlayer.stop()
    }

    private func reflectionEmotion(
        for choice: EmotionReflectionChoice
    ) -> EmotionKind {
        guard choice == .better else { return plan.mood.emotionKind }
        switch plan.mood {
        case .joy, .calm, .expectation, .low:
            return .calm
        }
    }

    @ViewBuilder
    private func paletteSwatch(index: Int, scale: CGFloat) -> some View {
        let isSelected = index == selectedColorIndex

        ZStack {
            if index == colors.count - 1 {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                            center: .center
                        )
                    )
            } else {
                Circle().fill(Color(uiColor: colors[index]))
            }

            if isSelected {
                Circle()
                    .stroke(Color.white, lineWidth: 2.5 * scale)
                    .shadow(color: .black.opacity(0.22), radius: 2 * scale)
            }
        }
        .frame(width: 28.8 * scale, height: 28.8 * scale)
        .scaleEffect(isSelected ? 1.08 : 1)
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }
}

private struct GuidanceSessionPill: View {
    let stage: EmotionGuidanceStage
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 326

            HStack(spacing: 10 * scale) {
                ZStack {
                    Circle()
                        .fill(stage.accent.opacity(0.17))
                    Image(systemName: "music.note")
                        .font(.system(size: 14 * scale, weight: .bold))
                        .foregroundStyle(stage.accent)
                }
                .frame(width: 36 * scale, height: 36 * scale)

                VStack(alignment: .leading, spacing: 3 * scale) {
                    HStack(spacing: 6 * scale) {
                        Text("音乐正在慢慢变化")
                            .gardenFont(size: 11.5 * scale, weight: .bold)
                        Spacer(minLength: 4 * scale)
                        Text(stage.title)
                            .gardenFont(size: 9 * scale)
                            .opacity(0.58)
                    }

                    Text(stage.guidance)
                        .gardenFont(size: 8.5 * scale)
                        .opacity(0.58)
                        .lineLimit(1)

                    GeometryReader { barProxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(stage.accent.opacity(0.14))
                            Capsule()
                                .fill(stage.accent)
                                .frame(width: barProxy.size.width * progress)
                        }
                    }
                    .frame(height: 4 * scale)
                }
                .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
            }
            .padding(.horizontal, 12 * scale)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(.white.opacity(0.88), in: Capsule())
            .overlay {
                Capsule().stroke(.white, lineWidth: 1 * scale)
            }
            .shadow(color: Color(red: 0, green: 0.42, blue: 0.46).opacity(0.11), radius: 9 * scale, y: 4 * scale)
        }
    }
}

private enum EmotionReflectionChoice: String, CaseIterable, Identifiable {
    case better = "更舒服了"
    case same = "差不多"
    case needsSupport = "还需要陪伴"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .better: "sun.max.fill"
        case .same: "cloud.fill"
        case .needsSupport: "heart.fill"
        }
    }
}

private struct EmotionReflectionOverlay: View {
    let sourceMood: MusicMood
    let onDone: (EmotionReflectionChoice) -> Void
    @State private var selection: EmotionReflectionChoice?

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / 402, proxy.size.height / 874)

            ZStack {
                Color(red: 0, green: 0.24, blue: 0.26).opacity(0.18)
                    .background(.ultraThinMaterial)

                VStack(spacing: 18 * scale) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.79, green: 1.00, blue: 0.96))
                        Image(systemName: "sparkles")
                            .font(.system(size: 28 * scale, weight: .medium))
                            .foregroundStyle(Color(red: 0.02, green: 0.70, blue: 0.74))
                    }
                    .frame(width: 72 * scale, height: 72 * scale)

                    VStack(spacing: 6 * scale) {
                        Text("完成啦")
                            .gardenFont(size: 25 * scale, weight: .bold)
                        Text("刚才从「\(sourceMood.title)」出发，\n现在感觉怎么样？")
                            .gardenFont(size: 14 * scale)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4 * scale)
                            .opacity(0.66)
                    }
                    .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))

                    VStack(spacing: 10 * scale) {
                        ForEach(EmotionReflectionChoice.allCases) { choice in
                            Button {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    selection = choice
                                }
                            } label: {
                                HStack(spacing: 11 * scale) {
                                    Image(systemName: choice.symbol)
                                        .font(.system(size: 16 * scale, weight: .semibold))
                                    Text(choice.rawValue)
                                        .gardenFont(size: 15 * scale, weight: .bold)
                                    Spacer()
                                    Image(systemName: selection == choice ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 18 * scale))
                                }
                                .foregroundStyle(
                                    selection == choice
                                        ? Color(red: 0.01, green: 0.65, blue: 0.70)
                                        : Color(red: 0, green: 0.31, blue: 0.34).opacity(0.72)
                                )
                                .padding(.horizontal, 16 * scale)
                                .frame(height: 50 * scale)
                                .background(
                                    selection == choice
                                        ? Color(red: 0.80, green: 1.00, blue: 0.96)
                                        : Color.white.opacity(0.68),
                                    in: RoundedRectangle(cornerRadius: 15 * scale, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        guard let selection else { return }
                        onDone(selection)
                    } label: {
                        Text(selection == .needsSupport ? "回到音乐空间继续陪伴" : "完成本次调节")
                            .gardenFont(size: 15 * scale, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52 * scale)
                            .background(
                                selection == nil
                                    ? Color.gray.opacity(0.28)
                                    : Color(red: 0.03, green: 0.72, blue: 0.76),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(selection == nil)
                }
                .padding(24 * scale)
                .frame(width: 344 * scale)
                .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 30 * scale, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                        .stroke(.white, lineWidth: 1 * scale)
                }
                .shadow(color: .black.opacity(0.14), radius: 24 * scale, y: 12 * scale)
            }
            .frame(width: 402 * scale, height: 874 * scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .ignoresSafeArea()
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
    @Binding var colorAssignments: [[UInt8: UIColor]]

    init(
        outlineAssets: [String],
        regionAssets: [String],
        selectedColor: UIColor,
        onRegionFilled: @escaping (UIColor, CGFloat, MindfulColorProfile) -> Void,
        onCanvasTapped: @escaping () -> Void = {},
        selectedIndex: Binding<Int>,
        coloredImages: Binding<[UIImage?]>,
        colorAssignments: Binding<[[UInt8: UIColor]]>
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
        .accessibilityHint("轻点蓝色线条围成的封闭区域填色")
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
            }

            Image(outlineAsset)
                .resizable()
                .interpolation(.high)
        }
    }
}

enum MusicRegionPainter {
    private struct RegionMap {
        let width: Int
        let height: Int
        let regionCount: Int
        let labels: [UInt8]
        let regionPixelCounts: [Int]
        let drawablePixelCount: Int
    }

    private static var cachedMaps: [String: RegionMap] = [:]

    static func paint(
        regionAsset: String,
        assignments: [UInt8: UIColor],
        at point: CGPoint,
        canvasSize: CGSize,
        color: UIColor
    ) -> (
        image: UIImage,
        assignments: [UInt8: UIColor],
        regionFraction: CGFloat
    )? {
        guard canvasSize.width > 0,
              canvasSize.height > 0,
              let map = regionMap(named: regionAsset) else { return nil }

        let x = min(max(Int(point.x / canvasSize.width * CGFloat(map.width)), 0), map.width - 1)
        let y = min(max(Int(point.y / canvasSize.height * CGFloat(map.height)), 0), map.height - 1)
        let tolerance = max(1, Int((6 / canvasSize.width * CGFloat(map.width)).rounded()))
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
        assignments: [UInt8: UIColor]
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
        assignments: [UInt8: UIColor]
    ) -> UIImage? {
        guard let map = regionMap(named: regionAsset) else { return nil }
        return render(map: map, assignments: assignments)
    }

    private static func regionMap(named assetName: String) -> RegionMap? {
        if let cached = cachedMaps[assetName] {
            return cached
        }
        guard let data = NSDataAsset(name: assetName)?.data,
              data.count >= 10,
              Array(data.prefix(4)) == [0x53, 0x47, 0x52, 0x31] else {
            return nil
        }

        func uint16(at offset: Int) -> Int {
            Int(data[offset]) | (Int(data[offset + 1]) << 8)
        }

        let width = uint16(at: 4)
        let height = uint16(at: 6)
        let regionCount = uint16(at: 8)
        let pixelCount = width * height
        guard width > 0, height > 0, regionCount > 0 else { return nil }

        var labels: [UInt8] = []
        labels.reserveCapacity(pixelCount)
        var cursor = 10
        while cursor + 2 < data.count, labels.count < pixelCount {
            let regionID = data[cursor]
            let runLength = uint16(at: cursor + 1)
            guard runLength > 0 else { return nil }
            labels.append(contentsOf: repeatElement(regionID, count: runLength))
            cursor += 3
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
    ) -> UInt8? {
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
                return UInt8(best)
            }
        }
        return nil
    }

    private static func countRegion(_ regionID: UInt8, in counts: inout [Int]) {
        let index = Int(regionID)
        guard index > 0, index < counts.count else { return }
        counts[index] += 1
    }

    private static func render(
        map: RegionMap,
        assignments: [UInt8: UIColor]
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
}
private struct SingingWaveform: View {
    let level: CGFloat
    let synthesisLevel: CGFloat
    let isListening: Bool
    let isPlaying: Bool
    let pulseFrequency: Double
    let brightness: Double
    let accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let count = 49
                let spacing = size.width / CGFloat(count)
                let musicLevel = CGFloat(0.20 + brightness * 0.22)
                let microphoneLevel = isListening
                    ? max(musicLevel, min(level, 1))
                    : musicLevel
                let normalizedLevel = max(
                    microphoneLevel,
                    min(max(synthesisLevel, 0), 1)
                )
                let speed = max(2.4, pulseFrequency * 5.2)

                for index in 0..<count {
                    let distance = abs(CGFloat(index) - CGFloat(count - 1) / 2)
                        / (CGFloat(count - 1) / 2)
                    let primaryMotion = (sin(time * speed + Double(index) * 0.54) + 1) / 2
                    let secondaryMotion = (sin(time * speed * 0.62 - Double(index) * 0.31) + 1) / 2
                    let motion = primaryMotion * 0.72 + secondaryMotion * 0.28
                    let envelope = 0.30 + (1 - distance) * 0.70
                    let height = 4 + normalizedLevel * 40 * envelope * CGFloat(0.42 + motion * 0.58)
                    let rect = CGRect(
                        x: (CGFloat(index) + 0.5) * spacing - 1.5,
                        y: (size.height - height) / 2,
                        width: 3,
                        height: height
                    )
                    let path = Path(roundedRect: rect, cornerRadius: 1.5)
                    context.fill(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [
                                .white,
                                accent.opacity(0.92),
                                .white
                            ]),
                            startPoint: CGPoint(x: rect.midX, y: rect.minY),
                            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                        )
                    )
                }
            }
        }
        .opacity(isPlaying ? 1 : 0.62)
        .animation(.easeInOut(duration: 0.8), value: isPlaying)
        .accessibilityHidden(true)
    }
}

@MainActor
private final class MindfulMusicPlayer: ObservableObject {
    @Published private(set) var isPlaying = false

    private var player: AVPlayer?
    private let noteEngine = AVAudioEngine()
    private let noteMixer = AVAudioMixerNode()
    private let noteReverb = AVAudioUnitReverb()
    private let noteEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let notePlayers = [
        AVAudioPlayerNode(),
        AVAudioPlayerNode(),
        AVAudioPlayerNode()
    ]
    private let sampleRate = 44_100.0
    private var nextNoteVoice = 0
    private var desiredBaseRate: Float = 1
    private var activeMood: MusicMood = .calm
    private var activeJourneyProgress: Double = 0
    private var colorProfile = MindfulColorProfile.empty

    init() {
        guard let format = noteFormat else { return }

        noteEngine.attach(noteMixer)
        noteEngine.attach(noteEQ)
        noteEngine.attach(noteReverb)
        for voice in notePlayers {
            noteEngine.attach(voice)
            noteEngine.connect(voice, to: noteMixer, format: format)
        }
        noteEngine.connect(noteMixer, to: noteEQ, format: format)
        noteEngine.connect(noteEQ, to: noteReverb, format: format)
        noteEngine.connect(
            noteReverb,
            to: noteEngine.mainMixerNode,
            format: format
        )

        let softeningBand = noteEQ.bands[0]
        softeningBand.filterType = .lowPass
        softeningBand.frequency = 8_400
        softeningBand.bypass = false
        noteEQ.globalGain = -3
        noteMixer.outputVolume = 0.72
        noteReverb.loadFactoryPreset(.mediumHall)
        noteReverb.wetDryMix = 42
    }

    func play(plan: EmotionGuidancePlan) -> Bool {
        guard let streamURL = plan.mood.musicStreamURL else { return false }

        do {
            activeMood = plan.mood
            activeJourneyProgress = 0
            colorProfile = .empty
            desiredBaseRate = Float(journeyRate(mood: plan.mood, progress: 0))
            try configureAudioSession()
            try startNoteEngine()
            let item = AVPlayerItem(url: streamURL)
            item.audioTimePitchAlgorithm = .spectral
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            newPlayer.volume = 0.70
            player = newPlayer
            newPlayer.playImmediately(atRate: desiredBaseRate)
            isPlaying = true
            applyAdaptiveMix(response: 1)
            return true
        } catch {
            player = nil
            isPlaying = false
            return false
        }
    }

    func pause() {
        player?.pause()
        for voice in notePlayers where voice.isPlaying {
            voice.pause()
        }
        isPlaying = false
    }

    func resume() -> Bool {
        guard let player else { return false }
        do {
            try configureAudioSession()
            try startNoteEngine()
            player.playImmediately(atRate: desiredBaseRate)
            isPlaying = true
            return true
        } catch {
            isPlaying = false
            return false
        }
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        for voice in notePlayers {
            voice.stop()
        }
        noteEngine.stop()
        isPlaying = false
        colorProfile = .empty
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    func updateJourney(mood: MusicMood, progress: Double) {
        activeMood = mood
        activeJourneyProgress = min(max(progress, 0), 1)
        applyAdaptiveMix(response: 0.12)
    }

    func respondToColoring(
        color: UIColor,
        regionFraction: CGFloat,
        profile: MindfulColorProfile,
        mood: MusicMood,
        progress: Double
    ) {
        activeMood = mood
        activeJourneyProgress = min(max(progress, 0), 1)
        colorProfile = profile
        applyAdaptiveMix(response: 0.38)

        guard isPlaying,
              let buffer = makeChime(
                color: color,
                regionFraction: regionFraction,
                profile: profile,
                mood: mood,
                progress: progress
              ) else { return }

        do {
            try startNoteEngine()
            let voice = notePlayers[nextNoteVoice]
            nextNoteVoice = (nextNoteVoice + 1) % notePlayers.count
            voice.stop()
            voice.scheduleBuffer(buffer)
            voice.play()
        } catch {
            return
        }
    }

    private func applyAdaptiveMix(response: Float) {
        let profile = colorProfile
        let influence = min(max(profile.coloredFraction / 0.62, 0), 1)
        let temperature = profile.warmProportion - profile.coolProportion
        let lightness = profile.meanBrightness - 0.5
        let saturation = profile.meanSaturation - 0.5
        let colorRateDelta = influence * (
            temperature * 0.020
                + lightness * 0.026
                + saturation * 0.014
        )
        let targetRate = min(
            max(
                journeyRate(
                    mood: activeMood,
                    progress: activeJourneyProgress
                ) + colorRateDelta,
                0.90
            ),
            1.06
        )
        desiredBaseRate += (Float(targetRate) - desiredBaseRate) * response

        let targetReverb = baseReverb(
            mood: activeMood,
            progress: activeJourneyProgress
        ) + Float(
            influence * (
                profile.coolProportion * 7
                    - profile.warmProportion * 4
                    + profile.hueDiversity * 3
            )
        )
        noteReverb.wetDryMix += (
            min(max(targetReverb, 28), 56) - noteReverb.wetDryMix
        ) * response

        let targetCutoff = Float(
            4_600
                + profile.meanBrightness * 3_600
                + profile.meanSaturation * 1_000
        )
        let currentCutoff = noteEQ.bands[0].frequency
        noteEQ.bands[0].frequency += (
            min(max(targetCutoff, 3_800), 9_200) - currentCutoff
        ) * response
        let targetNoteVolume = Float(
            0.62
                + influence * 0.10
                + profile.hueDiversity * influence * 0.08
        )
        noteMixer.outputVolume += (
            min(max(targetNoteVolume, 0.58), 0.80) - noteMixer.outputVolume
        ) * response

        guard isPlaying else { return }
        player?.rate = desiredBaseRate
        let targetVolume = Float(
            0.68
                + activeJourneyProgress * 0.035
                + influence * (profile.meanBrightness - 0.5) * 0.035
        )
        if let player {
            player.volume += (
                min(max(targetVolume, 0.64), 0.74) - player.volume
            ) * response
        }
    }

    private func journeyRate(mood: MusicMood, progress: Double) -> Double {
        let progress = min(max(progress, 0), 1)
        switch mood {
        case .joy:
            return 1.01 - progress * 0.07
        case .calm:
            return 0.98
        case .expectation:
            return 1.03 - progress * 0.10
        case .low:
            return 0.96 + progress * 0.04
        }
    }

    private func baseReverb(
        mood: MusicMood,
        progress: Double
    ) -> Float {
        switch mood {
        case .joy, .expectation:
            return Float(34 + progress * 12)
        case .calm:
            return 44
        case .low:
            return Float(48 - progress * 8)
        }
    }

    private var noteFormat: AVAudioFormat? {
        AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )
    }

    private func startNoteEngine() throws {
        guard !noteEngine.isRunning else { return }
        noteEngine.prepare()
        try noteEngine.start()
    }

    private func makeChime(
        color: UIColor,
        regionFraction: CGFloat,
        profile: MindfulColorProfile,
        mood: MusicMood,
        progress: Double
    ) -> AVAudioPCMBuffer? {
        guard let format = noteFormat else { return nil }

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

        let progress = min(max(progress, 0), 1)
        let regionFraction = min(max(regionFraction, 0.005), 0.45)
        let frequency = chimeFrequency(
            mood: mood,
            hue: hue,
            regionFraction: regionFraction,
            progress: progress,
            profile: profile
        )
        let duration = 1.35 + Double(sqrt(regionFraction)) * 2.15
        let capacity = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: capacity
        ), let channels = buffer.floatChannelData else { return nil }

        buffer.frameLength = capacity
        let twoPi = Double.pi * 2
        let harmonicBrightness = 0.14
            + Double(brightness) * 0.13
            + profile.meanBrightness * 0.08
        let shimmer = 0.03
            + Double(saturation) * 0.05
            + profile.hueDiversity * 0.07
        let gain = 0.060 + Double(min(regionFraction, 0.18)) * 0.12
        let pan = Double(hue * 2 - 1) * 0.16
        let leftGain = sqrt((1 - pan) * 0.5)
        let rightGain = sqrt((1 + pan) * 0.5)
        let companionRatio: Double
        if profile.warmProportion > profile.coolProportion + 0.16,
           profile.meanBrightness > 0.56 {
            companionRatio = pow(2, 4.0 / 12.0)
        } else if profile.coolProportion > profile.warmProportion + 0.16 {
            companionRatio = pow(2, 7.0 / 12.0)
        } else {
            companionRatio = pow(2, 3.0 / 12.0)
        }

        for frame in 0..<Int(capacity) {
            let time = Double(frame) / sampleRate
            let attack = min(1, time / 0.035)
            let release = pow(max(0, 1 - time / duration), 2.35)
            let envelope = attack * release
            let breath = 0.97 + sin(twoPi * 0.45 * time) * 0.03

            let fundamental = sin(twoPi * frequency * time)
            let companion = sin(
                twoPi * frequency * companionRatio * time + 0.11
            ) * exp(-time * 1.05)
            let warmPartial = sin(twoPi * frequency * 2.002 * time + 0.18)
                * exp(-time * 1.45)
            let glassPartial = sin(twoPi * frequency * 3.01 * time + 0.44)
                * exp(-time * 2.75)
            let body = fundamental
                + companion * (0.10 + profile.hueDiversity * 0.10)
                + warmPartial * harmonicBrightness
                + glassPartial * shimmer
            let sample = tanh(body * 0.76) * envelope * breath * gain

            channels[0][frame] = Float(sample * leftGain)
            channels[1][frame] = Float(sample * rightGain)
        }
        return buffer
    }

    private func chimeFrequency(
        mood: MusicMood,
        hue: CGFloat,
        regionFraction: CGFloat,
        progress: Double,
        profile: MindfulColorProfile
    ) -> Double {
        let root: Double
        var intervals: [Int]

        switch mood {
        case .joy:
            root = 261.63
            intervals = [0, 4, 7, 9, 12]
        case .calm:
            root = 220.00
            intervals = [0, 2, 7, 9, 12]
        case .expectation:
            root = 246.94
            intervals = progress < 0.55
                ? [0, 4, 7, 11, 12]
                : [0, 2, 7, 9, 12]
        case .low:
            root = 196.00
            intervals = progress < 0.52
                ? [0, 3, 5, 7, 10]
                : [0, 4, 5, 7, 9]
        }

        if profile.warmProportion > profile.coolProportion + 0.18,
           profile.meanBrightness > 0.55 {
            intervals = [0, 4, 7, 9, 12]
        } else if profile.coolProportion > profile.warmProportion + 0.18 {
            intervals = [0, 2, 7, 9, 12]
        } else if profile.meanBrightness < 0.46 {
            intervals = [0, 3, 5, 7, 10]
        }

        let degree = min(
            Int(hue * CGFloat(intervals.count)),
            intervals.count - 1
        )
        let octaveShift: Int
        if regionFraction < 0.035 {
            octaveShift = 12
        } else if regionFraction > 0.20 {
            octaveShift = -12
        } else {
            octaveShift = 0
        }
        let semitones = intervals[degree] + octaveShift
        return root * pow(2, Double(semitones) / 12)
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothHFP]
        )
        try session.setActive(true)
    }
}

@MainActor
private final class SingingVoiceMonitor: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var level: CGFloat = 0.10

    private let audioEngine = AVAudioEngine()
    private var hasInputTap = false

    func start() async -> Bool {
        let isAllowed: Bool
        if AVAudioApplication.shared.recordPermission == .undetermined {
            isAllowed = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        } else {
            isAllowed = AVAudioApplication.shared.recordPermission == .granted
        }

        guard isAllowed else { return false }
        stop(deactivateSession: false)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothHFP]
            )
            try session.setActive(true)

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { return false }

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let channel = buffer.floatChannelData?.pointee else { return }
                let frameCount = Int(buffer.frameLength)
                guard frameCount > 0 else { return }

                var sum: Float = 0
                for index in 0..<frameCount {
                    let sample = channel[index]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(frameCount))
                let decibels = 20 * log10(max(rms, 0.000_001))
                let normalized = CGFloat(max(0, min(1, (decibels + 55) / 45)))

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.level = self.level * 0.72 + normalized * 0.28
                }
            }
            hasInputTap = true

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            return true
        } catch {
            stop(deactivateSession: false)
            return false
        }
    }

    func pauseLevelDisplay() {
        level = 0.10
    }

    func stop(deactivateSession: Bool = true) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        isListening = false
        level = 0.10
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
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
    var title: String {
        switch self {
        case .joy: "愉悦"
        case .calm: "平静"
        case .expectation: "期待"
        case .low: "低落"
        }
    }
    var previewPlaybackRate: Float {
        self == .low ? 0.82 : 1
    }
    var musicStreamURL: URL? {
        let rawValue: String
        switch self {
        case .joy:
            rawValue = "https://files.freemusicarchive.org/storage-freemusicarchive-org/music/no_curator/Kevin_MacLeod/Calming/Kevin_MacLeod_-_Carefree.mp3"
        case .calm:
            rawValue = "https://upload.wikimedia.org/wikipedia/commons/2/2a/Gymnopedie_No._1_%28ISRC_USUAN1100787%29.mp3"
        case .expectation:
            rawValue = "https://upload.wikimedia.org/wikipedia/commons/e/e4/Lasting_Hope_%28ISRC_USUAN1100178%29.mp3"
        case .low:
            rawValue = "https://upload.wikimedia.org/wikipedia/commons/5/5e/Peaceful_Desolation_%28ISRC_USUAN1200017%29.mp3"
        }
        return URL(string: rawValue)
    }
    var cardAsset: String {
        switch self {
        case .joy: "music_mood_joy"
        case .calm: "music_mood_calm"
        case .expectation: "music_mood_expectation"
        case .low: "music_mood_low"
        }
    }
    var screenAsset: String { "figma_music_\(rawValue + 2)" }
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
    var waveColor: Color {
        switch self {
        case .joy: Color(red: 1, green: 0.78, blue: 0.08)
        case .calm: Color(red: 0, green: 0.78, blue: 0.82)
        case .expectation: Color(red: 1, green: 0.62, blue: 0.28)
        case .low: Color(red: 0.16, green: 0.51, blue: 0.86)
        }
    }
}

private struct MusicMotionHeader: View {
    let mood: MusicMood
    let orbAsset: String
    let scale: CGFloat
    let spansFullWidth: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            AnimatedMoodOrb(asset: orbAsset, frameDuration: mood.orbFrameDuration)
                .frame(width: 226 * scale, height: 226 * scale)
                .position(x: 201 * scale, y: 295 * scale)
                .id(orbAsset)
                .transaction { transaction in
                    transaction.animation = nil
                }
            AnimatedWaveform(mood: mood)
                .frame(
                    width: (spansFullWidth ? 402 : 244) * scale,
                    height: 83 * scale
                )
                .position(x: 201 * scale, y: 460.5 * scale)
        }
        .frame(width: 402 * scale, height: 874 * scale, alignment: .topLeading)
        .allowsHitTesting(false)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                                Gradient(colors: mood.waveGradient),
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

private struct MusicCardCarousel: View {
    @Binding var selection: MusicMood
    let onOpen: (MusicMood) -> Void
    @State private var centeredIndex: Int? = 1

    private var loopedMoods: [MusicMood] {
        [.low] + MusicMood.allCases + [.joy]
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 402
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16 * scale) {
                    ForEach(Array(loopedMoods.enumerated()), id: \.offset) { index, mood in
                        Button {
                            selection = mood
                            onOpen(mood)
                        } label: {
                            moodCard(mood, width: 137 * scale, height: 193 * scale)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 124 / 137)
                                .opacity(phase.isIdentity ? 1 : 0.88)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, (402 - 137) * scale / 2, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $centeredIndex)
            .onChange(of: centeredIndex) { _, newIndex in
                guard let newIndex else { return }

                if newIndex == 0 {
                    selection = .low
                    jumpWithoutAnimation(to: MusicMood.allCases.count)
                } else if newIndex == loopedMoods.count - 1 {
                    selection = .joy
                    jumpWithoutAnimation(to: 1)
                } else {
                    selection = loopedMoods[newIndex]
                }
            }
            .onChange(of: selection) { _, newMood in
                let target = newMood.rawValue + 1
                if centeredIndex != target {
                    centeredIndex = target
                }
            }
        }
    }

    private func jumpWithoutAnimation(to index: Int) {
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                centeredIndex = index
            }
        }
    }

    private func moodCard(_ mood: MusicMood, width: CGFloat, height: CGFloat) -> some View {
        Image(mood.cardAsset)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MusicMoodDetail: View {
    @Binding var selection: MusicMood
    let onClose: () -> Void
    let onSelect: () -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        FigmaScreenCanvas(asset: selection.screenAsset) { scale in
            Group {
                LinearGradient(
                    colors: [
                        Color(red: 0.90, green: 1.00, blue: 0.99),
                        Color(red: 0.93, green: 1.00, blue: 0.99)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                    .frame(width: 402 * scale, height: 70 * scale)
                    .position(x: 201 * scale, y: 460 * scale)
                Color.white
                    .frame(width: 226 * scale, height: 226 * scale)
                    .clipShape(Circle())
                    .position(x: 201 * scale, y: 295 * scale)
                MusicMotionHeader(
                    mood: selection,
                    orbAsset: selection.orbAsset,
                    scale: scale,
                    spansFullWidth: true
                )

                InfiniteMoodDetailPager(selection: $selection, scale: scale)
                .frame(width: 402 * scale, height: 228 * scale)
                .position(x: 201 * scale, y: 636 * scale)

                hotspot(x: 350, y: 518, width: 52, height: 55, scale: scale) {
                    onClose()
                }
                hotspot(x: 140, y: 686, width: 122, height: 55, scale: scale) {
                    onSelect()
                }
                hotspot(x: 75, y: 64, width: 125, height: 48, scale: scale) {
                    onOpenLibrary()
                }
            }
        }
    }
}

private struct InfiniteMoodDetailPager: View {
    @Binding var selection: MusicMood
    let scale: CGFloat
    @State private var pageIndex = 1

    private var loopedMoods: [MusicMood] {
        [.low] + MusicMood.allCases + [.joy]
    }

    var body: some View {
        TabView(selection: $pageIndex) {
            ForEach(Array(loopedMoods.enumerated()), id: \.offset) { index, mood in
                FigmaScreenCrop(
                    asset: mood.screenAsset,
                    sourceY: 522,
                    sourceHeight: 228,
                    scale: scale
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear {
            pageIndex = selection.rawValue + 1
        }
        .onChange(of: pageIndex) { _, newIndex in
            if newIndex == 0 {
                selection = .low
                jumpWithoutAnimation(to: MusicMood.allCases.count)
            } else if newIndex == loopedMoods.count - 1 {
                selection = .joy
                jumpWithoutAnimation(to: 1)
            } else {
                selection = loopedMoods[newIndex]
            }
        }
        .onChange(of: selection) { _, newMood in
            let target = newMood.rawValue + 1
            if pageIndex != target {
                pageIndex = target
            }
        }
    }

    private func jumpWithoutAnimation(to index: Int) {
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pageIndex = index
            }
        }
    }
}

private struct FigmaScreenCrop: View {
    let asset: String
    let sourceY: CGFloat
    let sourceHeight: CGFloat
    let scale: CGFloat

    var body: some View {
        Image(asset)
            .resizable()
            .interpolation(.high)
            .frame(width: 402 * scale, height: 874 * scale)
            .offset(y: (437 - sourceY - sourceHeight / 2) * scale)
            .frame(width: 402 * scale, height: sourceHeight * scale)
            .clipped()
    }
}

/// AR
struct FigmaARView: View {
    var onTaskFlowChanged: (Bool) -> Void = { _ in }

    var body: some View {
        LiveARView(onTaskFlowChanged: onTaskFlowChanged)
    }
}

/// 社区1
struct FigmaCommunityView: View {
    @State private var page = 1

    var body: some View {
        Group {
            if page == 1 {
                FigmaScreenCanvas(asset: "figma_community_1") { scale in
                    CommunityWorldScroll {
                        withAnimation(.timingCurve(0.42, 0, 1, 1, duration: 0.8)) {
                            page = 2
                        }
                    }
                    .frame(width: 354 * scale, height: 441 * scale)
                    .position(x: 201 * scale, y: 520.5 * scale)
                }
            } else {
                FigmaScreenCanvas(asset: "figma_community_\(page)") { scale in
                    Group {
                        hotspot(x: 12, y: 48, width: 54, height: 54, scale: scale) {
                            withAnimation(.timingCurve(0.42, 0, 1, 1, duration: 0.8)) {
                                page -= 1
                            }
                        }
                        if page == 2 {
                            hotspot(x: 24, y: 408, width: 176, height: 62, scale: scale) {
                                withAnimation(.timingCurve(0.42, 0, 1, 1, duration: 0.8)) {
                                    page = 3
                                }
                            }
                        }
                    }
                }
            }
        }
        .transition(.opacity)
    }
}

private struct CommunityWorld: Identifiable {
    let id: Int
    let title: String
    let author: String
    let canEnter: Bool

    var image: String {
        "community_card_\(String(format: "%02d", id))"
    }

    var avatar: String {
        "community_avatar_\(String(format: "%02d", id))"
    }
}

private struct CommunityWorldScroll: View {
    let onEnter: () -> Void

    private let leftWorlds = [
        CommunityWorld(id: 1, title: "枕边静域", author: "星星Na", canEnter: false),
        CommunityWorld(id: 3, title: "静心小卧", author: "健康小粥", canEnter: false),
        CommunityWorld(id: 5, title: "放空栖居", author: "星星小糖", canEnter: false),
        CommunityWorld(id: 7, title: "风铃回廊", author: "糯米团子", canEnter: false),
        CommunityWorld(id: 9, title: "节律共鸣", author: "南瓜米米", canEnter: false),
        CommunityWorld(id: 11, title: "轻语静心", author: "养乐多多", canEnter: false),
        CommunityWorld(id: 13, title: "暖光春芽", author: "百变小星", canEnter: false)
    ]

    private let rightWorlds = [
        CommunityWorld(id: 2, title: "床畔回廊", author: "周周", canEnter: true),
        CommunityWorld(id: 4, title: "低语慢听", author: "软萌跳跳", canEnter: false),
        CommunityWorld(id: 6, title: "余韵放松", author: "冰冰", canEnter: false),
        CommunityWorld(id: 8, title: "呼吸缓境", author: "晶晶", canEnter: false),
        CommunityWorld(id: 10, title: "暖光安抚", author: "momo", canEnter: false),
        CommunityWorld(id: 12, title: "温柔回声", author: "共星小树", canEnter: false),
        CommunityWorld(id: 14, title: "风铃回廊", author: "Habibi", canEnter: false)
    ]

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 354
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .top, spacing: 10 * scale) {
                        cardColumn(leftWorlds, scale: scale)
                        cardColumn(rightWorlds, scale: scale)
                            .padding(.top, 103 * scale)
                    }

                    CommunitySpeechBubble()
                        .fill(Color(red: 0.949, green: 0.949, blue: 0.969).opacity(0.84))
                        .frame(width: 119 * scale, height: 48 * scale)
                        .overlay {
                            CommunitySpeechBubble()
                                .stroke(.white.opacity(0.45), lineWidth: 0.7 * scale)
                        }
                        .shadow(color: .black.opacity(0.09), radius: 5.1 * scale, x: -3 * scale, y: -2 * scale)
                        .shadow(color: .black.opacity(0.18), radius: 2 * scale, x: 0, y: 4 * scale)
                        .position(x: 236.5 * scale, y: 25 * scale)

                    Text("看看其他人的植物世\n界吧！")
                        .gardenFont(size: 10 * scale)
                        .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
                        .multilineTextAlignment(.center)
                        .lineSpacing(1 * scale)
                        .frame(width: 104 * scale, height: 36 * scale)
                        .position(x: 234 * scale, y: 21 * scale)

                    KakaAvatarView(magnification: 0.82)
                        .frame(width: 99 * scale, height: 99 * scale)
                        .position(x: 312.5 * scale, y: 71.5 * scale)
                }
                .padding(.bottom, 10 * scale)
            }
            .scrollIndicators(.hidden)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.82, green: 1, blue: 0.98),
                        Color.white
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipped()
    }

    private func cardColumn(_ worlds: [CommunityWorld], scale: CGFloat) -> some View {
        LazyVStack(spacing: 8 * scale) {
            ForEach(worlds) { world in
                CommunityWorldCard(world: world, scale: scale, onEnter: onEnter)
            }
        }
        .frame(width: 172 * scale)
    }
}


private struct CommunitySpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 118.225
        let sy = rect.height / 48

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        var path = Path()
        path.move(to: point(95.694, 0))
        path.addLine(to: point(19.5, 0))
        path.addCurve(
            to: point(0, 19.5),
            control1: point(8.73, 0),
            control2: point(0, 8.73)
        )
        path.addCurve(
            to: point(19.5, 39),
            control1: point(0, 30.27),
            control2: point(8.73, 39)
        )
        path.addLine(to: point(97.229, 39))
        path.addCurve(
            to: point(110.67, 44.19),
            control1: point(102.198, 39),
            control2: point(106.99, 40.85)
        )
        path.addLine(to: point(114.161, 47.358))
        path.addCurve(
            to: point(115.823, 48),
            control1: point(114.616, 47.771),
            control2: point(115.208, 48)
        )
        path.addCurve(
            to: point(118.225, 44.919),
            control1: point(117.435, 48),
            control2: point(118.613, 46.483)
        )
        path.addCurve(
            to: point(115.694, 25.898),
            control1: point(116.538, 38.114),
            control2: point(115.694, 33.707)
        )
        path.addLine(to: point(115.694, 20))
        path.addCurve(
            to: point(95.694, 0),
            control1: point(115.694, 8.954),
            control2: point(106.74, 0)
        )
        path.closeSubpath()
        return path
    }
}

private struct CommunityWorldCard: View {
    let world: CommunityWorld
    let scale: CGFloat
    let onEnter: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(world.image)
                .resizable()
                .scaledToFill()
                .frame(width: 172 * scale, height: 205 * scale)
                .clipped()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(world.title)
                        .gardenFont(size: 16 * scale)
                        .tracking(0.352 * scale)
                        .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))

                    HStack(spacing: 5 * scale) {
                        Image(world.avatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 17 * scale, height: 17 * scale)
                            .clipShape(Circle())
                        Text(world.author)
                            .gardenFont(size: 10 * scale)
                            .tracking(0.22 * scale)
                            .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34).opacity(0.6))
                    }
                }
                .padding(.leading, 5 * scale)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: world.canEnter ? onEnter : {}) {
                    Text("进入\n世界")
                        .gardenFont(size: 16 * scale, weight: .bold)
                        .tracking(0.352 * scale)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4 * scale)
                        .foregroundStyle(.white)
                        .frame(width: 63 * scale, height: 64 * scale)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.74, green: 1, blue: 0.95).opacity(0.7),
                                    Color(red: 0.41, green: 0.83, blue: 0.86).opacity(0.7)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 64 * scale)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.74, green: 1, blue: 0.95).opacity(0.7),
                        Color(red: 0.41, green: 0.83, blue: 0.86).opacity(0.7)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .background(.ultraThinMaterial.opacity(0.18))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
        }
        .frame(width: 172 * scale, height: 205 * scale)
        .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
    }
}

/// Figma 最终稿「我的1–3」，节点 66:3003、453:8872、453:8991。
struct FigmaProfileView: View {
    @EnvironmentObject private var store: GardenStore
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true
    @State private var page = 1
    @State private var sharesEmotionData = true
    @State private var cloudSync = true

    var body: some View {
        FigmaScreenCanvas(
            asset: page == 1 ? "figma_profile_1" : "figma_profile_\(page)_clean"
        ) { scale in
            Group {
                if page == 1 {
                    ProfilePlantScroll()
                        .frame(width: 354 * scale, height: 360 * scale)
                        .position(x: 202 * scale, y: 567 * scale)

                    hotspot(x: 143, y: 264, width: 115, height: 49, scale: scale) {
                        page = 2
                    }
                    hotspot(x: 264, y: 264, width: 114, height: 49, scale: scale) {
                        page = 3
                    }
                } else {
                    hotspot(x: 340, y: 48, width: 48, height: 48, scale: scale) {
                        page = 1
                    }
                }

                if page == 2 {
                    ProfileEmotionRecordOverlay(
                        records: store.emotionRecords,
                        scale: scale
                    )
                }

                if page == 3 {
                    profileToggle(
                        isOn: $sharesEmotionData,
                        x: 323,
                        y: 544,
                        scale: scale
                    )
                    profileToggle(
                        isOn: $cloudSync,
                        x: 323,
                        y: 619,
                        scale: scale
                    )
                    hotspot(x: 44, y: 659, width: 312, height: 72, scale: scale) {
                        hasSeenOnboarding = false
                    }
                }
            }
        }
        .onAppear {
            guard let requested = store.requestedProfilePage else { return }
            page = requested
            store.requestedProfilePage = nil
        }
        .onChange(of: store.requestedProfilePage) { _, requested in
            guard let requested else { return }
            page = requested
            store.requestedProfilePage = nil
        }
    }

    private func profileToggle(
        isOn: Binding<Bool>,
        x: CGFloat,
        y: CGFloat,
        scale: CGFloat
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            ZStack {
                // The Figma screenshot already contains an enabled switch. Cover it
                // completely before drawing the interactive state on top.
                Color.white
                    .frame(width: 64 * scale, height: 40 * scale)

                Capsule()
                    .fill(
                        isOn.wrappedValue
                            ? Color(red: 0.00, green: 0.76, blue: 0.82)
                            : Color(red: 0.88, green: 0.88, blue: 0.90)
                    )
                    .frame(width: 47 * scale, height: 27 * scale)

                Circle()
                    .fill(Color.white)
                    .frame(width: 23 * scale, height: 23 * scale)
                    .shadow(
                        color: Color.black.opacity(0.16),
                        radius: 1.5 * scale,
                        y: 1 * scale
                    )
                    .offset(x: (isOn.wrappedValue ? 10 : -10) * scale)
            }
            .frame(width: 64 * scale, height: 40 * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: x * scale, y: y * scale)
    }
}

private struct EmotionChartPoint: Identifiable {
    let dayIndex: Int
    let date: Date
    let emotion: EmotionKind
    let count: Int

    var id: String {
        "\(emotion.rawValue)-\(date.timeIntervalSinceReferenceDate)"
    }
}

private struct EmotionWeekSnapshot {
    let days: [Date]
    let points: [EmotionChartPoint]
    let totalCount: Int
    let dominantEmotion: EmotionKind?
    let dominantPercentage: Double
    let maxFrequency: Int
    let dateRangeText: String

    init(records: [EmotionRecord], now: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let days = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
        let daySet = Set(days)
        var counts: [Date: [EmotionKind: Int]] = [:]

        for record in records {
            let day = calendar.startOfDay(for: record.timestamp)
            guard daySet.contains(day) else { continue }
            var moodCounts = counts[day] ?? [:]
            moodCounts[record.emotion, default: 0] += 1
            counts[day] = moodCounts
        }

        let points = days.enumerated().flatMap { dayIndex, day in
            EmotionKind.allCases.map { emotion in
                EmotionChartPoint(
                    dayIndex: dayIndex,
                    date: day,
                    emotion: emotion,
                    count: counts[day]?[emotion] ?? 0
                )
            }
        }
        let totalCount = points.reduce(0) { $0 + $1.count }
        let totals = EmotionKind.allCases.reduce(into: [EmotionKind: Int]()) { result, emotion in
            result[emotion] = points
                .filter { $0.emotion == emotion }
                .reduce(0) { $0 + $1.count }
        }
        let dominantEmotion = totalCount == 0 ? nil : EmotionKind.allCases.max {
            totals[$0, default: 0] < totals[$1, default: 0]
        }
        let dominantCount = dominantEmotion.map { totals[$0, default: 0] } ?? 0

        self.days = days
        self.points = points
        self.totalCount = totalCount
        self.dominantEmotion = dominantEmotion
        self.dominantPercentage = totalCount == 0
            ? 0
            : Double(dominantCount) / Double(totalCount)
        self.maxFrequency = max(1, points.map(\.count).max() ?? 1)
        self.dateRangeText = Self.rangeText(from: days.first ?? today, to: days.last ?? today)
    }

    func points(for emotion: EmotionKind) -> [EmotionChartPoint] {
        points.filter { $0.emotion == emotion }
    }

    private static func rangeText(from start: Date, to end: Date) -> String {
        let startFormatter = DateFormatter()
        startFormatter.locale = Locale(identifier: "zh_Hans_CN")
        startFormatter.dateFormat = "yyyy.M.d"

        let endFormatter = DateFormatter()
        endFormatter.locale = Locale(identifier: "zh_Hans_CN")
        endFormatter.dateFormat = "M.d"
        return "\(startFormatter.string(from: start))-\(endFormatter.string(from: end))"
    }
}

private struct ProfileEmotionRecordOverlay: View {
    let records: [EmotionRecord]
    let scale: CGFloat

    private var snapshot: EmotionWeekSnapshot {
        EmotionWeekSnapshot(records: records)
    }

    var body: some View {
        Group {
            // figma_profile_2_clean contains the original static chart artwork.
            // Remove that baked layer completely before placing the live cards.
            ProfileEmotionChartBaseCleaner()
                .frame(width: 328 * scale, height: 342 * scale)
                .position(x: 201 * scale, y: 609 * scale)

            ProfileWeeklyEmotionSummary(snapshot: snapshot)
                .frame(width: 307 * scale, height: 162 * scale)
                .position(x: 200.5 * scale, y: 185 * scale)

            ProfileEmotionLineCard(snapshot: snapshot)
                .frame(width: 307 * scale, height: 156 * scale)
                .position(x: 201.5 * scale, y: 525 * scale)

            ProfileEmotionBarCard(snapshot: snapshot)
                .frame(width: 307 * scale, height: 156 * scale)
                .position(x: 201.5 * scale, y: 693 * scale)
        }
        .animation(.easeOut(duration: 0.46), value: snapshot.totalCount)
    }
}

private struct ProfileEmotionChartBaseCleaner: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(
                    color: Color(red: 0.878, green: 0.988, blue: 0.976),
                    location: 0
                ),
                .init(
                    color: Color(red: 0.937, green: 0.996, blue: 0.988),
                    location: 0.51
                ),
                .init(
                    color: Color(red: 0.988, green: 0.988, blue: 0.984),
                    location: 1
                )
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ProfileWeeklyEmotionSummary: View {
    let snapshot: EmotionWeekSnapshot

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 307
            let percentage = Int((snapshot.dominantPercentage * 100).rounded())

            ZStack {
                ProfileEmotionGauge(progress: snapshot.dominantPercentage)
                    .frame(width: 134 * scale, height: 134 * scale)
                    .position(x: 87 * scale, y: 86 * scale)

                ProfileVariableTextCover(cornerRadius: 10 * scale)
                    .frame(width: 72 * scale, height: 52 * scale)
                    .position(x: 87 * scale, y: 85 * scale)

                ProfileVariableTextCover(cornerRadius: 12 * scale)
                    .frame(width: 139 * scale, height: 78 * scale)
                    .position(x: 232.5 * scale, y: 105 * scale)

                VStack(spacing: 0) {
                    Text("\(percentage)%")
                        .gardenFont(size: 21 * scale)
                    Text(
                        snapshot.dominantEmotion.map { "\($0.title)情绪" }
                            ?? "暂无记录"
                    )
                        .gardenFont(size: 11 * scale)
                }
                .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
                .position(x: 87 * scale, y: 85 * scale)

                Text(summaryText)
                    .gardenFont(size: 10.5 * scale)
                    .lineSpacing(2 * scale)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
                .frame(width: 131 * scale, alignment: .leading)
                .position(x: 232.5 * scale, y: 102 * scale)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("本周共记录 \(snapshot.totalCount) 次，\(snapshot.dominantEmotion?.title ?? "暂无主要情绪")")
        }
    }

    private var summaryText: String {
        guard let dominant = snapshot.dominantEmotion else {
            return "本周还没有情绪记录，去首页选择当前心情后，这里会自动生成变化。"
        }
        return "本周共记录\(snapshot.totalCount)次情绪，整体变化较平稳，其中“\(dominant.title)”出现次数最多。"
    }
}

private struct ProfileVariableTextCover: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
            .blur(radius: 2.4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct ProfileEmotionGauge: View {
    let progress: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.385
            let lineWidth = min(size.width, size.height) * 0.208
            let start = Angle.degrees(145)
            let sweep = 250.0
            let end = Angle.degrees(145 + sweep)
            let progressEnd = Angle.degrees(145 + sweep * min(max(progress, 0), 1))

            var track = Path()
            track.addArc(
                center: center,
                radius: radius,
                startAngle: start,
                endAngle: end,
                clockwise: false
            )
            context.stroke(
                track,
                with: .color(.white.opacity(0.96)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            if progress > 0 {
                var value = Path()
                value.addArc(
                    center: center,
                    radius: radius,
                    startAngle: start,
                    endAngle: progressEnd,
                    clockwise: false
                )
                context.stroke(
                    value,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.61, green: 0.93, blue: 0.91),
                            Color(red: 0.31, green: 0.85, blue: 0.70)
                        ]),
                        startPoint: CGPoint(x: center.x, y: center.y - radius),
                        endPoint: CGPoint(x: center.x, y: center.y + radius)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }

            for index in 0..<8 {
                let fraction = Double(index) / 7
                let angle = (145 + sweep * fraction) * .pi / 180
                let point = CGPoint(
                    x: center.x + radius * cos(angle),
                    y: center.y + radius * sin(angle)
                )
                let dotSize = min(size.width, size.height) * 0.078
                let dot = CGRect(
                    x: point.x - dotSize / 2,
                    y: point.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                context.fill(Path(ellipseIn: dot), with: .color(.white))
            }
        }
    }
}

private struct ProfileEmotionLineCard: View {
    let snapshot: EmotionWeekSnapshot

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 307

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                    .fill(Color.white)
                    .shadow(
                        color: Color(red: 0.247, green: 0.235, blue: 0.212).opacity(0.05),
                        radius: 8 * scale,
                        y: 8 * scale
                    )

                Text("使用频率")
                    .gardenFont(size: 10 * scale)
                    .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
                    .position(x: 25 * scale, y: 24 * scale)

                emotionLineChart(scale: scale)
                    .frame(width: 292 * scale, height: 64 * scale)
                    .position(x: 154 * scale, y: 65 * scale)

                ProfileEmotionLegend(scale: scale)
                    .position(x: 295 * scale, y: 33 * scale)

                Text("天数")
                    .gardenFont(size: 10 * scale)
                    .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
                    .position(x: 291.5 * scale, y: 109 * scale)

                VStack(alignment: .leading, spacing: 1 * scale) {
                    Text("本周情绪波动曲线")
                        .gardenFont(size: 16 * scale)
                    ProfileEmotionDateRow(text: snapshot.dateRangeText, scale: scale)
                }
                .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
                .frame(width: 253 * scale, alignment: .leading)
                .position(x: 138.5 * scale, y: 128 * scale)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("本周情绪波动曲线，共 \(snapshot.totalCount) 条记录")
        }
    }

    private func emotionLineChart(scale: CGFloat) -> some View {
        ZStack {
            Chart {
                if snapshot.totalCount > 0, let dominant = snapshot.dominantEmotion {
                    ForEach(snapshot.points(for: dominant)) { point in
                        AreaMark(
                            x: .value("日期", point.date),
                            yStart: .value("起点", 0),
                            yEnd: .value("次数", point.count)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [dominant.chartColor.opacity(0.30), dominant.chartColor.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }

                if snapshot.totalCount > 0 {
                    ForEach(snapshot.points) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("次数", point.count),
                            series: .value("情绪", point.emotion.rawValue)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(point.emotion.chartColor.opacity(0.88))
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: 2.1 * scale,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }
            }
            .chartXScale(domain: (snapshot.days.first ?? Date())...(snapshot.days.last ?? Date()))
            .chartYScale(domain: 0...Double(snapshot.maxFrequency + 1))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .padding(.trailing, 3 * scale)
            .padding(.top, 6 * scale)
            .padding(.leading, 6 * scale)

            ProfileChartAxes(scale: scale)

            if snapshot.totalCount == 0 {
                Text("记录心情后生成曲线")
                    .gardenFont(size: 10 * scale)
                    .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34).opacity(0.46))
            }
        }
    }
}

private struct ProfileEmotionBarCard: View {
    let snapshot: EmotionWeekSnapshot

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 307

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                    .fill(Color.white)
                    .shadow(
                        color: Color(red: 0.247, green: 0.235, blue: 0.212).opacity(0.05),
                        radius: 8 * scale,
                        y: 8 * scale
                    )

                Text("使用频率")
                    .gardenFont(size: 10 * scale)
                    .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
                    .position(x: 25 * scale, y: 24 * scale)

                emotionBarChart(scale: scale)
                    .frame(width: 292 * scale, height: 62 * scale)
                    .position(x: 154 * scale, y: 66 * scale)

                ProfileEmotionLegend(scale: scale)
                    .position(x: 295 * scale, y: 33 * scale)

                Text("天数")
                    .gardenFont(size: 10 * scale)
                    .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
                    .position(x: 291.5 * scale, y: 109 * scale)

                VStack(alignment: .leading, spacing: 0) {
                    Text("本周情绪识别训练情况")
                        .gardenFont(size: 16 * scale)
                    ProfileEmotionDateRow(text: snapshot.dateRangeText, scale: scale)
                }
                .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
                .frame(width: 253 * scale, alignment: .leading)
                .position(x: 138.5 * scale, y: 128 * scale)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("本周情绪识别训练情况，共 \(snapshot.totalCount) 条记录")
        }
    }

    private func emotionBarChart(scale: CGFloat) -> some View {
        let lastDayIndex = max(snapshot.days.count - 1, 0)
        let xDomain = -0.5...(Double(lastDayIndex) + 0.5)

        return ZStack {
            Chart(snapshot.points) { point in
                BarMark(
                    x: .value("日期位置", barXPosition(for: point)),
                    y: .value("次数", point.count),
                    width: .fixed(5.2 * scale)
                )
                .foregroundStyle(point.emotion.chartColor.opacity(0.76))
                .cornerRadius(3 * scale)
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: 0...Double(snapshot.maxFrequency + 1))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartPlotStyle { plotArea in
                plotArea.overlay {
                    ProfileChartAxes(scale: scale)
                }
            }
            .padding(.trailing, 3 * scale)
            .padding(.top, 5 * scale)
            .padding(.leading, 6 * scale)

            if snapshot.totalCount == 0 {
                Text("记录心情后生成统计")
                    .gardenFont(size: 10 * scale)
                    .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34).opacity(0.46))
            }
        }
    }

    private func barXPosition(for point: EmotionChartPoint) -> Double {
        let emotions = EmotionKind.allCases
        let emotionIndex = emotions.firstIndex(of: point.emotion) ?? 0
        let centeredIndex = Double(emotionIndex) - Double(emotions.count - 1) / 2

        return Double(point.dayIndex) + centeredIndex * 0.15
    }
}

private struct ProfileChartAxes: View {
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let color = Color(red: 0.02, green: 0.74, blue: 0.78)
            let origin = CGPoint(x: 5 * scale, y: proxy.size.height - 4 * scale)

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: origin.x, y: 4 * scale))
                    path.addLine(to: origin)
                    path.addLine(to: CGPoint(x: proxy.size.width - 3 * scale, y: origin.y))
                }
                .stroke(
                    color.opacity(0.58),
                    style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round)
                )

                Circle()
                    .fill(color)
                    .frame(width: 7 * scale, height: 7 * scale)
                    .position(origin)

                Circle()
                    .fill(color)
                    .frame(width: 3.5 * scale, height: 3.5 * scale)
                    .position(x: origin.x, y: 4 * scale)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ProfileEmotionLegend: View {
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 3 * scale) {
            ForEach(EmotionKind.allCases) { emotion in
                Circle()
                    .fill(emotion.chartColor)
                    .frame(width: 4 * scale, height: 4 * scale)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ProfileEmotionDateRow: View {
    let text: String
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 6 * scale) {
            Text(text)
            Circle()
                .fill(Color(red: 0.79, green: 0.78, blue: 0.77))
                .frame(width: 4 * scale, height: 4 * scale)
            Text("KAKA")
        }
        .gardenFont(size: 14 * scale)
        .foregroundStyle(Color(red: 0.45, green: 0.42, blue: 0.40))
    }
}

private struct ProfilePlant: Identifiable {
    let id: Int
    let pinyin: String
    let name: String
    let date: String
    let description: String
    let orbColors: [Color]
}

private struct ProfilePlantScroll: View {
    private let plants = [
        ProfilePlant(
            id: 1,
            pinyin: "yù jīn xiāng",
            name: "郁金香",
            date: "2025.12.22获得",
            description: "郁金香悄悄绽开，像小杯子盛着春天的光，花瓣软软的、亮晶晶的，看一眼心里暖暖的，快乐就冒出来啦。",
            orbColors: [Color(red: 1, green: 0.95, blue: 0.45), Color(red: 1, green: 0.72, blue: 0.42)]
        ),
        ProfilePlant(
            id: 2,
            pinyin: "zǐ téng",
            name: "紫藤",
            date: "2025.12.23获得",
            description: "紫藤花串串垂下来，紫莹莹晃悠悠，瞧着它，心情也软软糯糯的甜。",
            orbColors: [Color(red: 0.55, green: 0.92, blue: 1), Color(red: 0.72, green: 0.48, blue: 0.95)]
        ),
        ProfilePlant(
            id: 3,
            pinyin: "shān chá huā",
            name: "山茶花",
            date: "2025.12.24获得",
            description: "白山茶花白嫩嫩挂枝头，花瓣润润的，望着它，心里温温的，特别踏实。",
            orbColors: [Color.white, Color(red: 0.68, green: 1, blue: 0.9)]
        )
    ]

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 354
            ScrollView(.vertical) {
                LazyVStack(spacing: 8 * scale) {
                    ForEach(plants) { plant in
                        ProfilePlantCard(plant: plant, scale: scale)
                    }
                }
                .padding(.vertical, 1 * scale)
            }
            .scrollIndicators(.hidden)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.76, green: 1, blue: 0.98), .white],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ProfilePlantCard: View {
    let plant: ProfilePlant
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 10 * scale) {
            Image("profile_plant_\(plant.id)")
                .resizable()
                .scaledToFit()
                .frame(width: 136 * scale, height: 191 * scale)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 1, green: 0.83, blue: 0.84).opacity(0.9),
                            Color(red: 0.75, green: 0.98, blue: 1).opacity(0.9)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
                .shadow(color: .black.opacity(0.15), radius: 4 * scale, y: 3 * scale)

            VStack(alignment: .leading, spacing: 2 * scale) {
                Text(plant.pinyin)
                    .gardenFont(size: 16 * scale)
                Text(plant.name)
                    .gardenFont(size: 24 * scale)
                Text(plant.date)
                    .gardenFont(size: 16 * scale)
                Spacer(minLength: 6 * scale)
                Text(plant.description)
                    .gardenFont(size: 10 * scale)
                    .lineSpacing(1 * scale)
                    .opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color(red: 0, green: 0.31, blue: 0.34))
            .padding(.vertical, 12 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: plant.orbColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50 * scale, height: 50 * scale)
                    .blur(radius: 2 * scale)
                    .padding(.top, 24 * scale)
            }
        }
        .padding(9 * scale)
        .frame(width: 354 * scale, height: 210 * scale)
        .background(
            RadialGradient(
                colors: [Color(red: 0.76, green: 1, blue: 0.98), .white.opacity(0.25)],
                center: .center,
                startRadius: 0,
                endRadius: 190 * scale
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
        .shadow(color: .black.opacity(0.12), radius: 5 * scale, y: 3 * scale)
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

private func hotspot(
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    scale: CGFloat,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Color.clear
            .frame(width: width * scale, height: height * scale)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .position(x: (x + width / 2) * scale, y: (y + height / 2) * scale)
}
