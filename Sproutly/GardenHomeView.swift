import AVFoundation
import SwiftUI

/// Figma 高保真最终稿「首页1」的可交互实现。
/// 设计基准：402 × 874，节点 66:2743。
struct GardenHomeView: View {
    @EnvironmentObject private var store: GardenStore
    var onCustomizationChanged: (Bool) -> Void = { _ in }
    @State private var page = 1
    @State private var selectedMood: HomeMood = .yellow
    @State private var outfitSelection: KakaAppearance? = .bee
    @State private var moodSelection: KakaAppearance? = .angry
    @StateObject private var moodMusicPlayer = MoodMusicPlayer()
    /// 首页 6 不是整页跳转，而是从底部上升的装扮弹窗；60 为设计稿中保留的顶部空白。
    @State private var customizationSheetOffset: CGFloat = 874

    private enum HomeMood {
        case yellow, blue, orange, green

        var musicMood: MusicMood {
            switch self {
            case .yellow: .joy
            case .green: .calm
            case .orange: .expectation
            case .blue: .low
            }
        }

        var emotionKind: EmotionKind {
            musicMood.emotionKind
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / 402, proxy.size.height / 874)
            let renderedWidth = 402 * scale
            let renderedHeight = 874 * scale
            let backgroundPage = page == 6 ? 4 : page
            let usesIndependentHomeLayer = (1...4).contains(backgroundPage)
            let backgroundAsset = usesIndependentHomeLayer
                ? "figma_home_\(backgroundPage)_clean"
                : "figma_home_\(backgroundPage)"

            ZStack {
                SproutlyHomeGradient().ignoresSafeArea()

                homeBaseLayer(
                    asset: backgroundAsset,
                    hidesLegacyTop: usesIndependentHomeLayer,
                    renderedWidth: renderedWidth,
                    renderedHeight: renderedHeight,
                    scale: scale,
                    center: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                )

                if page <= 4 {
                    independentHomeLayer(scale: scale)
                }

                if page <= 4 {
                    homeKaka(scale: scale)

                    if page == 1 {
                        homeSpeechBubble(scale: scale)
                    }
                }

                if page <= 5 {
                    designButton(x: 24, y: 80, width: 85, height: 85, scale: scale) {
                        markHomeInteraction()
                        withAnimation(.easeInOut(duration: 0.36)) {
                            page = page == 3 ? 4 : 3
                        }
                    }

                    designButton(x: 251, y: 80, width: 127, height: 83, scale: scale) {
                        markHomeInteraction()
                        withAnimation(.easeInOut(duration: 0.36)) {
                            page = page == 2 ? 4 : 2
                        }
                    }
                }

                if page == 3 {
                    moodChoice(.yellow, x: 112, y: 65, scale: scale)
                    moodChoice(.blue, x: 119, y: 120, scale: scale)
                    moodChoice(.orange, x: 27, y: 171, scale: scale)
                    moodChoice(.green, x: 82, y: 165, scale: scale)
                }

                designButton(x: 16, y: 680, width: 370, height: 72, scale: scale) {
                    markHomeInteraction()
                }

                if (1...4).contains(page) {
                    let kakaFrame = page == 1
                        ? CGRect(x: 24, y: 620, width: 185, height: 128)
                        : CGRect(x: 282, y: 516, width: 105, height: 90)
                    designButton(
                        x: kakaFrame.minX,
                        y: kakaFrame.minY,
                        width: kakaFrame.width,
                        height: kakaFrame.height,
                        scale: scale
                    ) {
                        markHomeInteraction()
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
                            page = 6
                            customizationSheetOffset = 60
                        }
                    }
                }

                if page == 4 {
                    designButton(x: 0, y: 261, width: 402, height: 268, scale: scale) {
                        markHomeInteraction()
                        withAnimation(.easeIn(duration: 0.3)) { page = 7 }
                    }
                }

                if page == 7 {
                    designButton(x: 354, y: 174, width: 42, height: 42, scale: scale) {
                        page = 4
                    }
                }

                if page == 6 {
                    customizationSheet(scale: scale)
                }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear {
            moodMusicPlayer.preload()
            moodMusicPlayer.play(selectedMood.musicMood)
        }
        .onChange(of: page) { _, newPage in
            onCustomizationChanged(newPage == 6)
            if newPage == 6 {
                synchronizeCustomizationSelection()
            }
        }
        .onDisappear {
            moodMusicPlayer.stop()
            onCustomizationChanged(false)
        }
    }

    private func moodBall(scale: CGFloat) -> some View {
        homeMoodOrb(selectedMood, size: 85, scale: scale)
            .frame(width: 85 * scale, height: 85 * scale)
            .position(x: 66.5 * scale, y: 122.5 * scale)
            .allowsHitTesting(false)
    }

    /// 首页 1–4 的旧整页截图只保留底部导航区域。
    /// 顶部内容完全由统一渐变和透明独立素材组成，避免旧截图中的白底再次透出。
    @ViewBuilder
    private func homeBaseLayer(
        asset: String,
        hidesLegacyTop: Bool,
        renderedWidth: CGFloat,
        renderedHeight: CGFloat,
        scale: CGFloat,
        center: CGPoint
    ) -> some View {
        if hidesLegacyTop {
            Image(asset)
                .resizable()
                .interpolation(.high)
                .frame(width: renderedWidth, height: renderedHeight)
                .mask(alignment: .bottom) {
                    Rectangle()
                        .frame(width: renderedWidth, height: 232 * scale)
                }
                .position(center)
                .accessibilityHidden(true)
        } else {
            Image(asset)
                .resizable()
                .interpolation(.high)
                .frame(width: renderedWidth, height: renderedHeight)
                .position(center)
                .accessibilityHidden(true)
        }
    }

    /// 首页顶部采用一张连续渐变底面，再叠加 Figma 独立导出素材。
    /// 不再从整页截图裁片，避免情绪球和故事卡周围出现矩形拼接边界。
    private func independentHomeLayer(scale: CGFloat) -> some View {
        ZStack {
            SproutlyHomeGradientSlice(
                sourceY: 0,
                sourceHeight: 642,
                scale: scale
            )
            .position(x: 201 * scale, y: 321 * scale)

            Image("home_globe")
                .resizable()
                .interpolation(.high)
                .frame(width: 402 * scale, height: 353 * scale)
                .position(x: 201 * scale, y: 425.5 * scale)

            Image("home_stage_title")
                .resizable()
                .interpolation(.high)
                .frame(width: 186 * scale, height: 36 * scale)
                .position(x: 201 * scale, y: 622 * scale)

            Image(page == 2 ? "home_story_expanded" : "home_story_collapsed")
                .resizable()
                .interpolation(.high)
                .frame(
                    width: 127 * scale,
                    height: (page == 2 ? 222 : 83) * scale
                )
                .position(
                    x: 314.5 * scale,
                    y: (page == 2 ? 191 : 121.5) * scale
                )

            moodBall(scale: scale)

            if page == 3 {
                homeMoodOrb(.yellow, size: 40, scale: scale)
                    .position(x: 132 * scale, y: 85 * scale)
                homeMoodOrb(.blue, size: 40, scale: scale)
                    .position(x: 139 * scale, y: 140 * scale)
                homeMoodOrb(.orange, size: 40, scale: scale)
                    .position(x: 47 * scale, y: 191 * scale)
                homeMoodOrb(.green, size: 40, scale: scale)
                    .position(x: 102 * scale, y: 185 * scale)
            }
        }
        .allowsHitTesting(false)
    }

    private func homeMoodOrb(
        _ mood: HomeMood,
        size: CGFloat,
        scale: CGFloat
    ) -> some View {
        AnimatedMoodOrb(
            asset: mood.musicMood.orbAsset,
            frameDuration: mood.musicMood.orbFrameDuration
        )
        .frame(width: size * scale, height: size * scale)
        .id(mood.musicMood.orbAsset)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func homeSpeechBubble(scale: CGFloat) -> some View {
        ZStack {
            HomeSpeechBubbleShape()
                .fill(Color(red: 0.96, green: 0.96, blue: 0.98).opacity(0.9))
                .overlay {
                    HomeSpeechBubbleShape()
                        .stroke(Color.white.opacity(0.82), lineWidth: scale)
                }
                .shadow(color: .black.opacity(0.17), radius: 6 * scale, y: 3 * scale)

            Text("Hi~欢迎回到灵想世界，我是你的好伙伴KAKA!")
                .gardenFont(size: 10 * scale)
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: 204 * scale, height: 50 * scale)
                .offset(x: 5 * scale, y: -6 * scale)
        }
        .frame(width: 224 * scale, height: 68 * scale)
        .position(x: 270 * scale, y: 646 * scale)
        .allowsHitTesting(false)
    }

    private func moodChoice(_ mood: HomeMood, x: CGFloat, y: CGFloat, scale: CGFloat) -> some View {
        designButton(x: x, y: y, width: 44, height: 44, scale: scale) {
            selectedMood = mood
            moodMusicPlayer.play(mood.musicMood)
            store.recordEmotion(mood.emotionKind, source: .homeCheckIn)
            markHomeInteraction()
            withAnimation(.easeOut(duration: 0.28)) {
                page = 4
            }
        }
    }

    @ViewBuilder
    private func homeKaka(scale: CGFloat) -> some View {
        switch page {
        case 1:
            KakaAvatarView(magnification: 1.42)
                .frame(width: 185 * scale, height: 128 * scale)
                .position(x: 116.5 * scale, y: 684 * scale)
                .allowsHitTesting(false)
        case 2...4:
            KakaAvatarView(magnification: 1.24)
                .frame(width: 105 * scale, height: 90 * scale)
                .position(x: 334.5 * scale, y: 561 * scale)
                .allowsHitTesting(false)
        default:
            EmptyView()
        }
    }

    /// Figma 首页 6：从屏幕底部出现、顶部不顶满的装扮弹窗。
    private func customizationSheet(scale: CGFloat) -> some View {
        ZStack {
            Image("figma_home_6_clean")
                .resizable()
                .interpolation(.high)
                .frame(width: 402 * scale, height: 814 * scale)
                .position(x: 201 * scale, y: 407 * scale)
                .accessibilityHidden(true)

            // 舞台永远只放当前选中的 KAKA；空舞台底图已移除原装角色。
            KakaAvatarView(magnification: 1.38, matchesVariantScale: true)
                .frame(width: 242 * scale, height: 174 * scale)
                .position(x: 201 * scale, y: 365 * scale)
                .allowsHitTesting(false)

            kakaCustomizationControls(scale: scale)
        }
        .frame(width: 402 * scale, height: 814 * scale)
        .position(x: 201 * scale, y: 407 * scale)
        .offset(y: customizationSheetOffset * scale)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard value.translation.height > 0 else { return }
                    customizationSheetOffset = 60 + value.translation.height / scale
                }
                .onEnded { value in
                    if value.translation.height > 90 * scale || value.predictedEndTranslation.height > 150 * scale {
                        dismissCustomizationSheet()
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            customizationSheetOffset = 60
                        }
                    }
                }
        )
        .accessibilityHint("在弹窗顶部向下滑动可关闭装扮世界")
    }

    private func kakaCustomizationControls(scale: CGFloat) -> some View {
        Group {
            // 覆盖底图标题，保持 Figma 首页 6 的青绿色标题胶囊与准确文字。
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.13, green: 0.87, blue: 0.81), Color(red: 0.0, green: 0.63, blue: 0.67)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Capsule().stroke(.white.opacity(0.75), lineWidth: scale))
                    .shadow(color: .black.opacity(0.22), radius: 3 * scale, y: 2 * scale)

                Text("KAKA的装扮世界")
                    .gardenFont(size: 16 * scale, weight: .medium)
                    .foregroundStyle(.white)
            }
            .frame(width: 136 * scale, height: 30 * scale)
            .position(x: 201 * scale, y: 63 * scale)

            KakaCarouselSection(
                items: KakaAppearance.outfits,
                selection: $outfitSelection,
                scale: scale,
                cardColors: [.orange, .pink, .yellow, .green, .orange, .blue, .red]
            )
            .position(x: 201 * scale, y: 548 * scale)

            KakaCarouselSection(
                items: KakaAppearance.moods,
                selection: $moodSelection,
                scale: scale,
                cardColors: [.pink, .red, .purple, .orange, .yellow, .cyan]
            )
            .position(x: 201 * scale, y: 716 * scale)
        }
    }

    private func synchronizeCustomizationSelection() {
        if KakaAppearance.outfits.contains(store.kakaAppearance) {
            outfitSelection = store.kakaAppearance
        }
        if KakaAppearance.moods.contains(store.kakaAppearance) {
            moodSelection = store.kakaAppearance
        }
    }

    private func dismissCustomizationSheet() {
        withAnimation(.easeIn(duration: 0.24)) {
            customizationSheetOffset = 874
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            page = 4
        }
    }

    private func markHomeInteraction() {
        if page == 1 {
            page = 4
        }
    }

    private func designButton(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Color.clear
                .contentShape(Rectangle())
                .frame(width: width * scale, height: height * scale)
        }
        .buttonStyle(.plain)
        .position(x: (x + width / 2) * scale, y: (y + height / 2) * scale)
    }

}

@MainActor
final class MoodMusicPlayer: ObservableObject {
    private let targetVolume: Float = 0.62
    private struct Channel {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
    }

    private var channels: [MusicMood: Channel] = [:]
    private var activeMood: MusicMood?

    func preload() {
        for mood in MusicMood.allCases {
            // Construct every queue and item up front. Calling `preroll` while a
            // remote item is still `.unknown` raises an Objective-C exception.
            _ = channel(for: mood)
        }
    }

    func play(_ mood: MusicMood) {
        if activeMood == mood, let player = channels[mood]?.player {
            if player.timeControlStatus != .playing {
                configureAudioSession()
                player.playImmediately(atRate: mood.previewPlaybackRate)
            }
            return
        }
        guard let nextChannel = channel(for: mood) else { return }

        configureAudioSession()
        if let activeMood, let activePlayer = channels[activeMood]?.player {
            activePlayer.pause()
            activePlayer.volume = 0
        }

        nextChannel.player.volume = targetVolume
        nextChannel.player.playImmediately(atRate: mood.previewPlaybackRate)
        activeMood = mood
    }

    func stop() {
        for channel in channels.values {
            channel.player.pause()
            channel.player.volume = 0
        }
        activeMood = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func channel(for mood: MusicMood) -> Channel? {
        if let channel = channels[mood] {
            return channel
        }
        guard let url = mood.musicStreamURL else { return nil }

        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = mood == .low ? .varispeed : .spectral
        item.preferredForwardBufferDuration = 3
        let player = AVQueuePlayer()
        player.automaticallyWaitsToMinimizeStalling = false
        player.volume = 0
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let channel = Channel(player: player, looper: looper)
        channels[mood] = channel
        return channel
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers]
        )
        try? session.setActive(true)
    }
}

private struct HomeSpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let body = CGRect(
            x: rect.width * 0.055,
            y: 0,
            width: rect.width * 0.945,
            height: rect.height * 0.79
        )
        path.addRoundedRect(
            in: body,
            cornerSize: CGSize(width: rect.height * 0.24, height: rect.height * 0.24)
        )
        path.move(to: CGPoint(x: rect.width * 0.18, y: rect.height * 0.73))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 0.075, y: rect.height * 0.62))
        path.closeSubpath()
        return path
    }
}

/// 首页 6 的横向选项轨道。使用可对齐停靠的滚动视图，露出相邻卡片以提示还能继续滑动。
private struct KakaCarouselSection: View {
    @EnvironmentObject private var store: GardenStore
    let items: [KakaAppearance]
    @Binding var selection: KakaAppearance?
    let scale: CGFloat
    let cardColors: [Color]

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 11 * scale, style: .continuous)
                // 完全不透明，覆盖 Figma 背景截图中原本的静态卡片与静态圆点。
                .fill(Color(red: 0.93, green: 0.96, blue: 0.95))
                .overlay {
                    RoundedRectangle(cornerRadius: 11 * scale, style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: scale)
                }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 11 * scale) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, appearance in
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                selection = appearance
                                store.selectKaka(appearance)
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                                    .fill(cardGradient(color: cardColors[index]))

                                KakaAvatarView(selectedAppearance: appearance, magnification: 1.12)
                                    .frame(width: 85 * scale, height: 85 * scale)
                                    .padding(.top, 4 * scale)
                            }
                            .frame(width: 92 * scale, height: 92 * scale)
                            .overlay {
                                if selection == appearance {
                                    RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                                        .stroke(Color(red: 0.02, green: 0.78, blue: 0.81), lineWidth: 2.5 * scale)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("选择\(appearance.accessibilityName)")
                        .accessibilityAddTraits(selection == appearance ? .isSelected : [])
                        .id(appearance)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 123 * scale, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection)
            .frame(width: 338 * scale, height: 92 * scale)
            .padding(.bottom, 20 * scale)

            HStack(spacing: 5 * scale) {
                ForEach(items) { appearance in
                    Circle()
                        .fill(selection == appearance ? Color(red: 0.02, green: 0.78, blue: 0.81) : Color.white.opacity(0.88))
                        .frame(width: 8 * scale, height: 8 * scale)
                }
            }
            .padding(.bottom, 5 * scale)
        }
        .frame(width: 354 * scale, height: 126 * scale)
        .onChange(of: selection) { _, newValue in
            guard let newValue else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                store.selectKaka(newValue)
            }
        }
    }

    private func cardGradient(color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.42), .white.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
