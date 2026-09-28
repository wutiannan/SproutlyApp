import AVFoundation
import Combine
import simd
import SwiftUI

private enum HomeWorldDestination: Int, CaseIterable {
    case music
    case ar
    case profile

    var title: String {
        switch self {
        case .music: "音乐花园"
        case .ar: "花房探索"
        case .profile: "我的小屋"
        }
    }

    var tab: AppTab {
        switch self {
        case .music: .mood
        case .ar: .room
        case .profile: .profile
        }
    }

    var entrance: HomeGlobeEntrance {
        switch self {
        case .music: .music
        case .ar: .ar
        case .profile: .profile
        }
    }

    var navAsset: String {
        switch self {
        case .music: "home_world_nav_music"
        case .ar: "home_world_nav_ar"
        case .profile: "home_world_nav_profile"
        }
    }

    var previewAsset: String {
        switch self {
        case .music: "home_confirm_music_window"
        case .ar: "home_confirm_ar_window"
        case .profile: "home_confirm_profile_window"
        }
    }

    var tint: Color {
        switch self {
        case .music: Color(red: 0.29, green: 0.40, blue: 0.55)
        case .ar: Color(red: 0.17, green: 0.40, blue: 0.33)
        case .profile: Color(red: 0.46, green: 0.29, blue: 0.32)
        }
    }

    var confirmationFill: Color {
        switch self {
        case .music: Color(red: 0.43, green: 0.57, blue: 0.74).opacity(0.86)
        case .ar: Color(red: 0.38, green: 0.67, blue: 0.54).opacity(0.88)
        case .profile: Color(red: 0.74, green: 0.50, blue: 0.53).opacity(0.88)
        }
    }

    var confirmationShadow: Color {
        switch self {
        case .music: Color(red: 0.20, green: 0.31, blue: 0.48).opacity(0.20)
        case .ar: Color(red: 0.17, green: 0.39, blue: 0.31).opacity(0.20)
        case .profile: Color(red: 0.42, green: 0.24, blue: 0.27).opacity(0.19)
        }
    }

    var rotation: simd_quatf { entrance.focusRotation }

}

/// Figma「SY1-1～SY1-5」首页：3D 世界球、循环轨道导航和 KAKA 装扮入口。
/// 设计基准：402 × 874，起始节点 1595:6889。
struct GardenHomeView: View {
    @EnvironmentObject private var store: GardenStore
    var onContentReady: () -> Void = {}
    var onNavigate: ((AppTab) -> Void)? = nil
    var onCustomizationChanged: (Bool) -> Void = { _ in }

    @State private var selectedWorld: HomeWorldDestination = .music
    @State private var pendingWorld: HomeWorldDestination?
    @State private var hasActivatedWorldNavigation = false
    @State private var globeRotation = HomeWorldDestination.music.rotation
    @State private var globeInteraction = HomeGlobeInteraction()
    @State private var dragOriginRotation: simd_quatf?
    @State private var isDraggingGlobe = false
    @State private var isCustomizing = false
    @State private var selectedMood: HomeMood = .happy
    @State private var areMoodOptionsExpanded = false
    @AppStorage("sproutly.homeSelectedMood") private var storedMoodRawValue: Int = 0
    @State private var outfitSelection: KakaAppearance? = .bee
    @StateObject private var moodMusicPlayer = MoodMusicPlayer()
    @State private var customizationSheetOffset: CGFloat = 874
    @State private var lastGlobeAutoSpinDate: Date?
    private let customizationSheetHeight: CGFloat = 788

    private static let globeAutoSpinTimer = Timer.publish(
        every: 1.0 / 30.0,
        on: .main,
        in: .common
    ).autoconnect()

    private var customizationSheetRestingOffset: CGFloat {
        874 - customizationSheetHeight
    }

    private enum HomeMood: Int, CaseIterable, Hashable {
        case happy, calm, sad, angry, afraid

        var title: String {
            switch self {
            case .happy: "开心"
            case .calm: "平静"
            case .sad: "难过"
            case .angry: "生气"
            case .afraid: "害怕"
            }
        }

        var orbAsset: String {
            switch self {
            case .happy: "music_home_orb_happy"
            case .calm: "music_home_orb_calm"
            case .sad: "music_home_orb_sad"
            case .angry: "music_home_orb_angry"
            case .afraid: "music_home_orb_afraid"
            }
        }

        var musicMood: MusicMood {
            switch self {
            case .happy: .joy
            case .calm: .calm
            case .sad: .low
            case .angry, .afraid: .expectation
            }
        }

        var playback: HomeMoodPlayback {
            switch self {
            case .happy:
                HomeMoodPlayback(key: "happy", rate: 1.08, pitch: 3.0, filterFrequency: 9_200)
            case .calm:
                HomeMoodPlayback(key: "calm", rate: 0.94, pitch: 0, filterFrequency: 7_000)
            case .sad:
                HomeMoodPlayback(key: "sad", rate: 0.82, pitch: -4.0, filterFrequency: 4_800)
            case .angry:
                HomeMoodPlayback(key: "angry", rate: 1.12, pitch: 2.0, filterFrequency: 8_600)
            case .afraid:
                HomeMoodPlayback(key: "afraid", rate: 1.00, pitch: -1.0, filterFrequency: 6_200)
            }
        }

        var orbFrameDuration: TimeInterval {
            switch self {
            case .happy: 1.0
            case .calm, .sad: 2.0
            case .angry, .afraid: 0.8
            }
        }

        var emotionKind: EmotionKind {
            musicMood.emotionKind
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / 402, proxy.size.height / 874)

            ZStack {
                SproutlyHomeGradient().ignoresSafeArea()

                stageTitle(scale: scale)
                moodSelector(scale: scale)
                homeKaka(scale: scale)
                    .zIndex(13)

                if !hasActivatedWorldNavigation {
                    homeSpeechBubble(scale: scale)
                        .zIndex(13)
                }

                if hasActivatedWorldNavigation {
                    worldOrbitVisual(scale: scale)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .zIndex(11)
                }

                globeLayer(scale: scale)
                    .zIndex(10)

                if hasActivatedWorldNavigation {
                    worldOrbitInteractionLayer(scale: scale)
                        .zIndex(12)
                }

                kakaCustomizationHotspot(scale: scale)
                    .zIndex(12)

                if let pendingWorld {
                    worldConfirmation(pendingWorld, scale: scale)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(20)
                }

                if isCustomizing {
                    customizationSheet(scale: scale)
                        .zIndex(30)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear {
            selectedMood = HomeMood(rawValue: storedMoodRawValue) ?? .happy
            moodMusicPlayer.preload()
            if !store.parentPreferences.isQuietTime() {
                moodMusicPlayer.play(selectedMood.playback)
            }
            if store.requestsKakaCustomization {
                store.requestsKakaCustomization = false
                synchronizeCustomizationSelection()
                isCustomizing = true
                customizationSheetOffset = customizationSheetRestingOffset
            }
        }
        .onChange(of: isCustomizing) { _, newValue in
            onCustomizationChanged(newValue)
            if newValue {
                synchronizeCustomizationSelection()
            }
        }
        .onChange(of: store.requestsKakaCustomization) { _, requested in
            guard requested else { return }
            store.requestsKakaCustomization = false
            synchronizeCustomizationSelection()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                isCustomizing = true
                customizationSheetOffset = customizationSheetRestingOffset
            }
        }
        .onDisappear {
            moodMusicPlayer.stop(deactivateSession: store.selectedTab != .mood)
            onCustomizationChanged(false)
        }
        .onReceive(Self.globeAutoSpinTimer) { date in
            guard !hasActivatedWorldNavigation,
                  !isDraggingGlobe,
                  !UIAccessibility.isReduceMotionEnabled else {
                lastGlobeAutoSpinDate = date
                return
            }

            let previousDate = lastGlobeAutoSpinDate ?? date
            let elapsed = min(max(date.timeIntervalSince(previousDate), 0), 0.1)
            lastGlobeAutoSpinDate = date
            guard elapsed > 0 else { return }

            // 初始的小球只做很慢的自转，进入可交互导航后完全交给手势控制。
            let yaw = simd_quatf(
                angle: Float(elapsed * 0.16),
                axis: SIMD3<Float>(0, 1, 0)
            )
            // 右乘表示绕世界球自身的局部竖直轴旋转，模拟地球自转；
            // 左乘会绕页面世界轴横向翻转，视觉上像球在横着滚。
            globeRotation = simd_normalize(globeRotation * yaw)
        }
    }

    private func stageTitle(scale: CGFloat) -> some View {
        ZStack {
            Image("home_stage_glyph")
                .resizable()
                .scaledToFit()
                .frame(width: 55 * scale, height: 33 * scale)
                .position(x: 135.5 * scale, y: 99.9 * scale)

            Text("第一幕  春芽初醒")
                .gardenFont(size: 16 * scale, weight: .medium)
                .foregroundStyle(Color(red: 0.19, green: 0.37, blue: 0.39))
                .frame(width: 142 * scale, height: 31 * scale)
                .position(x: 231 * scale, y: 103.9 * scale)
        }
        .frame(width: 402 * scale, height: 140 * scale)
        .position(x: 201 * scale, y: 70 * scale)
        .accessibilityElement(children: .combine)
    }

    private func globeLayer(scale: CGFloat) -> some View {
        let diameter = (hasActivatedWorldNavigation ? 820 : 370) * scale
        let renderHeight = diameter + (hasActivatedWorldNavigation ? 240 : 0) * scale
        let renderWidth = diameter + (hasActivatedWorldNavigation ? 0 : 64) * scale
        let centerY = (hasActivatedWorldNavigation ? 760 : 509) * scale
        let isAutoSpinning = !hasActivatedWorldNavigation && !isDraggingGlobe

        return ZStack {
            HomeGlobeView(
                rotation: globeRotation,
                // 自转期间关闭 RealityKit 的补间动画；每个节拍直接应用小角度，
                // 避免 0.46 秒的连续 move 叠加造成拖影或延迟。
                isInteracting: isDraggingGlobe || isAutoSpinning,
                showsEntranceHints: hasActivatedWorldNavigation,
                interaction: globeInteraction,
                renderHeightScale: Float(renderHeight / diameter),
                onReady: onContentReady
            )
                // 小球旋转时凸起地形可越过触摸圆；留透明渲染余量避免左缘被裁切。
                .frame(width: renderWidth, height: renderHeight)
                .allowsHitTesting(false)

            Color.clear
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .gesture(globeDragGesture(diameter: diameter, hitTestYOffset: (renderHeight - diameter) / 2))
                .accessibilityLabel("灵想世界球")
                .accessibilityHint(
                    hasActivatedWorldNavigation
                        ? "向任意方向拖动球体，点击球面上的入口进入"
                        : "向任意方向拖动球体"
                )
        }
            .frame(width: diameter, height: renderHeight)
            .position(x: 201 * scale, y: centerY)
            .animation(.spring(response: 0.55, dampingFraction: 0.86), value: hasActivatedWorldNavigation)
    }

    private func globeDragGesture(diameter: CGFloat, hitTestYOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let travel = hypot(value.translation.width, value.translation.height)
                guard travel >= 8 else { return }

                activateWorldNavigation()
                if dragOriginRotation == nil {
                    dragOriginRotation = globeRotation
                }
                isDraggingGlobe = true
                let start = arcballVector(at: value.startLocation, diameter: diameter)
                let current = arcballVector(at: value.location, diameter: diameter)
                let delta = simd_quatf(from: start, to: current)
                globeRotation = simd_normalize(
                    delta * (dragOriginRotation ?? globeRotation)
                )
                selectedWorld = nearestWorld(to: globeRotation)
            }
            .onEnded { value in
                let wasDragging = isDraggingGlobe
                dragOriginRotation = nil
                isDraggingGlobe = false

                guard !wasDragging else { return }
                guard hasActivatedWorldNavigation else { return }
                let hitPoint = CGPoint(x: value.location.x, y: value.location.y + hitTestYOffset)
                guard let entrance = globeInteraction.entrance(at: hitPoint),
                      let destination = HomeWorldDestination.allCases.first(where: { $0.entrance == entrance })
                else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    pendingWorld = destination
                }
            }
    }

    /// 将触点映射到虚拟球面，斜向拖动也会产生对应的复合旋转轴。
    private func arcballVector(at point: CGPoint, diameter: CGFloat) -> SIMD3<Float> {
        let radius = max(diameter * 0.5, 1)
        var x = Float((point.x - radius) / radius)
        var y = Float((radius - point.y) / radius)
        let squaredLength = x * x + y * y

        if squaredLength > 1 {
            let inverseLength = 1 / sqrt(squaredLength)
            x *= inverseLength
            y *= inverseLength
            return SIMD3<Float>(x, y, 0)
        }
        return SIMD3<Float>(x, y, sqrt(max(0, 1 - squaredLength)))
    }

    private func nearestWorld(to rotation: simd_quatf) -> HomeWorldDestination {
        let focus = simd_normalize(SIMD3<Float>(0, 0.55, 0.84))
        return HomeWorldDestination.allCases.max { lhs, rhs in
            simd_dot(rotation.act(lhs.entrance.direction), focus)
                < simd_dot(rotation.act(rhs.entrance.direction), focus)
        } ?? selectedWorld
    }

    private func moodSelector(scale: CGFloat) -> some View {
        let surroundingSlots = [
            CGPoint(x: 132, y: 180.67),
            CGPoint(x: 140, y: 237.67),
            CGPoint(x: 105, y: 283.67),
            CGPoint(x: 47, y: 290.67)
        ]
        let surroundingMoods = HomeMood.allCases.filter { $0 != selectedMood }

        return ZStack {
            moodChoice(
                selectedMood,
                center: CGPoint(x: 66.5, y: 218.17),
                size: 85,
                scale: scale,
                isSelected: true
            )

            if areMoodOptionsExpanded {
                ForEach(Array(surroundingMoods.enumerated()), id: \.element) { index, mood in
                    moodChoice(
                        mood,
                        center: surroundingSlots[index],
                        size: 40,
                        scale: scale,
                        isSelected: false
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
        }
        .frame(width: 402 * scale, height: 874 * scale)
        .zIndex(4)
    }

    private func homeMoodOrb(
        _ mood: HomeMood,
        size: CGFloat,
        scale: CGFloat,
        isSelected: Bool
    ) -> some View {
        FigmaHomeMoodOrb(
            asset: mood.orbAsset,
            isAnimated: isSelected,
            frameDuration: mood.orbFrameDuration
        )
        .frame(width: size * scale, height: size * scale)
        .id("\(mood.orbAsset)-\(isSelected)")
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func homeSpeechBubble(scale: CGFloat) -> some View {
        ZStack {
            Image("home_kaka_speech_bubble")
                .resizable()
                .interpolation(.high)
                .frame(width: 235 * scale, height: 81 * scale)

            Text("转动世界球，看看不同的地方吧")
                .gardenFont(size: 10 * scale)
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: 204 * scale, height: 50 * scale)
                .offset(x: 5 * scale, y: -6 * scale)
        }
        .frame(width: 235 * scale, height: 81 * scale)
        .position(x: 224 * scale, y: 740 * scale)
        .allowsHitTesting(false)
    }

    private func moodChoice(
        _ mood: HomeMood,
        center: CGPoint,
        size: CGFloat,
        scale: CGFloat,
        isSelected: Bool
    ) -> some View {
        Button {
            if isSelected {
                withAnimation(.easeOut(duration: 0.22)) {
                    areMoodOptionsExpanded.toggle()
                }
                return
            }
            selectedMood = mood
            storedMoodRawValue = mood.rawValue
            moodMusicPlayer.play(mood.playback)
            store.recordEmotion(mood.emotionKind, source: .homeCheckIn)
            withAnimation(.easeOut(duration: 0.18)) {
                areMoodOptionsExpanded = false
            }
        } label: {
            homeMoodOrb(mood, size: size, scale: scale, isSelected: isSelected)
                .frame(width: (size + (isSelected ? 4 : 8)) * scale,
                       height: (size + (isSelected ? 4 : 8)) * scale)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .zIndex(isSelected ? 2 : 1)
        .position(x: center.x * scale, y: center.y * scale)
        .accessibilityLabel(mood.title)
        .accessibilityHint(
            isSelected
                ? (areMoodOptionsExpanded ? "收起其他心情" : "展开其他心情")
                : "切换到\(mood.title)并播放对应音乐"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func homeKaka(scale: CGFloat) -> some View {
        KakaAvatarView(magnification: hasActivatedWorldNavigation ? 1.25 : 1.42)
            .frame(
                width: (hasActivatedWorldNavigation ? 140 : 190) * scale,
                height: (hasActivatedWorldNavigation ? 104 : 138) * scale
            )
            .position(
                x: (hasActivatedWorldNavigation ? 330 : 87) * scale,
                y: (hasActivatedWorldNavigation ? 342 : 784) * scale
            )
            .allowsHitTesting(false)
            .animation(.spring(response: 0.5, dampingFraction: 0.84), value: hasActivatedWorldNavigation)
    }

    private func kakaCustomizationHotspot(scale: CGFloat) -> some View {
        Button {
            synchronizeCustomizationSelection()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                isCustomizing = true
                customizationSheetOffset = customizationSheetRestingOffset
            }
        } label: {
            Color.clear
                .frame(
                    width: (hasActivatedWorldNavigation ? 140 : 190) * scale,
                    height: (hasActivatedWorldNavigation ? 104 : 138) * scale
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(
            x: (hasActivatedWorldNavigation ? 330 : 67) * scale,
            y: (hasActivatedWorldNavigation ? 342 : 704) * scale
        )
        .animation(.spring(response: 0.5, dampingFraction: 0.84), value: hasActivatedWorldNavigation)
        .accessibilityLabel("KAKA")
        .accessibilityHint("打开 KAKA 的装扮世界")
    }

    private func worldOrbitVisual(scale: CGFloat) -> some View {
        Image(selectedWorld.navAsset)
            .resizable()
            .interpolation(.high)
            .frame(width: 374 * scale, height: 110 * scale)
            .contentTransition(.opacity)
            .id(selectedWorld.navAsset)
            .allowsHitTesting(false)
            .position(x: 201 * scale, y: 808 * scale)
    }

    /// 透明热区与可见图标分离，球体手势不会吞掉底部导航点击。
    private func worldOrbitInteractionLayer(scale: CGFloat) -> some View {
        let destinations = orbitDestinations

        return ZStack {
            worldOrbitButton(
                label: "转到\(destinations[0].title)",
                width: 64,
                height: 64,
                scale: scale
            ) {
                selectWorld(destinations[0])
            }
            .position(x: 62 * scale, y: 55 * scale)

            worldOrbitButton(
                label: "转到\(destinations[1].title)",
                width: 84,
                height: 86,
                scale: scale
            ) {
                selectWorld(destinations[1])
            }
            .position(x: 187 * scale, y: 55 * scale)

            worldOrbitButton(
                label: "转到\(destinations[2].title)",
                width: 64,
                height: 64,
                scale: scale
            ) {
                selectWorld(destinations[2])
            }
            .position(x: 298 * scale, y: 55 * scale)
        }
        .frame(width: 374 * scale, height: 110 * scale)
        .position(x: 201 * scale, y: 808 * scale)
    }

    /// Figma「世界轨道导航」的循环顺序：当前入口居中，两侧入口随状态换位。
    private var orbitDestinations: [HomeWorldDestination] {
        switch selectedWorld {
        case .music: [.profile, .music, .ar]
        case .ar: [.music, .ar, .profile]
        case .profile: [.ar, .profile, .music]
        }
    }

    private func selectWorld(_ destination: HomeWorldDestination) {
        pendingWorld = nil
        dragOriginRotation = nil
        isDraggingGlobe = false

        withAnimation(.easeInOut(duration: 0.46)) {
            selectedWorld = destination
        }
        globeRotation = destination.rotation
    }

    private func worldOrbitButton(
        label: String,
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
        .accessibilityLabel(label)
    }

    private func worldConfirmation(
        _ destination: HomeWorldDestination,
        scale: CGFloat
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(red: 0.16, green: 0.37, blue: 0.39).opacity(0.20))
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { pendingWorld = nil }
                }

            ZStack(alignment: .topLeading) {
                HStack(spacing: 7 * scale) {
                    confirmationHeaderIcon(destination, scale: scale)

                    Text(destination.title)
                        .gardenFont(size: 25 * scale, weight: .bold)
                        .foregroundStyle(destination.tint)
                        .lineLimit(1)
                }
                .fixedSize()
                .position(
                    x: 161 * scale,
                    y: (destination == .music ? 32.1 : 27.5) * scale
                )

                Image(destination.previewAsset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(
                        width: 278 * scale,
                        height: (destination == .profile ? 134 : 122) * scale
                    )
                    .position(
                        x: 161 * scale,
                        y: (destination == .profile ? 115 : 117) * scale
                    )

                confirmationBackButton(destination, scale: scale)
                    .position(x: 68.5 * scale, y: 223 * scale)

                confirmationEnterButton(destination, scale: scale)
                    .position(x: 209.5 * scale, y: 223 * scale)
            }
            .frame(width: 322 * scale, height: 268 * scale)
            .background(
                RoundedRectangle(cornerRadius: 34 * scale, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.97, blue: 0.93).opacity(0.76))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 34 * scale, style: .continuous)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 34 * scale, style: .continuous)
                    .stroke(.white.opacity(0.82), lineWidth: 1.5 * scale)
            }
            .shadow(
                color: Color(red: 0.08, green: 0.23, blue: 0.24).opacity(0.18),
                radius: 15 * scale,
                y: 12 * scale
            )
            .position(x: 202.84 * scale, y: 454.62 * scale)

            KakaAvatarView(magnification: 1.04, matchesVariantScale: true)
                .frame(width: 105 * scale, height: 77 * scale)
                .position(x: 66.84 * scale, y: 325.12 * scale)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func confirmationHeaderIcon(
        _ destination: HomeWorldDestination,
        scale: CGFloat
    ) -> some View {
        switch destination {
        case .music:
            Image("home_confirm_music_icon")
                .resizable()
                .scaledToFit()
                .frame(width: 39 * scale, height: 28.5 * scale)
        case .ar:
            Image("home_confirm_ar_icon")
                .resizable()
                .scaledToFit()
                .frame(width: 35.75 * scale, height: 33.72 * scale)
        case .profile:
            ZStack(alignment: .topLeading) {
                Image("home_confirm_profile_frame")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36.48 * scale, height: 35.4 * scale)

                Image("home_confirm_profile_head")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 10.86 * scale, height: 10.86 * scale)
                    .position(x: 16.31 * scale, y: 11.94 * scale)

                Image("home_confirm_profile_body")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 23.22 * scale, height: 11.27 * scale)
                    .position(x: 18.14 * scale, y: 24.1 * scale)
            }
            .frame(width: 36.48 * scale, height: 35.4 * scale)
        }
    }

    private func confirmationBackButton(
        _ destination: HomeWorldDestination,
        scale: CGFloat
    ) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { pendingWorld = nil }
        } label: {
            ZStack {
                Capsule()
                    .fill(.white.opacity(0.34))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.62), lineWidth: scale)
                    }
                    .shadow(
                        color: Color(red: 0.12, green: 0.28, blue: 0.28).opacity(0.10),
                        radius: 6 * scale,
                        y: 4 * scale
                    )

                Image("home_confirm_back")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32 * scale, height: 32 * scale)
            }
            .frame(width: 80 * scale, height: 62 * scale)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回\(destination.title)")
    }

    private func confirmationEnterButton(
        _ destination: HomeWorldDestination,
        scale: CGFloat
    ) -> some View {
        Button {
            if let onNavigate {
                onNavigate(destination.tab)
            } else {
                pendingWorld = nil
                store.selectedTab = destination.tab
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(destination.confirmationFill)
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.52), lineWidth: scale)
                    }
                    .shadow(
                        color: destination.confirmationShadow,
                        radius: 7.5 * scale,
                        y: 6 * scale
                    )

                Image("home_confirm_check")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32 * scale, height: 32 * scale)
            }
            .frame(width: 162 * scale, height: 62 * scale)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("确认进入\(destination.title)")
    }

    /// Figma 首页 6：移除心情区后，从屏幕底部出现的装扮弹窗。
    private func customizationSheet(scale: CGFloat) -> some View {
        ZStack {
            Image("kaka_customization_background")
                .resizable()
                .interpolation(.high)
                .frame(width: 402 * scale, height: 788 * scale)
                .position(x: 201 * scale, y: 394 * scale)
                .accessibilityHidden(true)

            // 舞台永远只放当前选中的 KAKA；空舞台底图已移除原装角色。
            KakaAvatarView(magnification: 1.38, matchesVariantScale: true)
                .frame(width: 242 * scale, height: 174 * scale)
                .position(x: 201 * scale, y: 365 * scale)
                .allowsHitTesting(false)

            kakaCustomizationControls(scale: scale)
        }
        .frame(width: 402 * scale, height: 788 * scale)
        .frame(width: 402 * scale, height: customizationSheetHeight * scale, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 30 * scale, style: .continuous))
        .position(x: 201 * scale, y: customizationSheetHeight * scale / 2)
        .offset(y: customizationSheetOffset * scale)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard value.translation.height > 0 else { return }
                    customizationSheetOffset = customizationSheetRestingOffset + value.translation.height / scale
                }
                .onEnded { value in
                    if value.translation.height > 90 * scale || value.predictedEndTranslation.height > 150 * scale {
                        dismissCustomizationSheet()
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            customizationSheetOffset = customizationSheetRestingOffset
                        }
                    }
                }
        )
        .accessibilityHint("在弹窗顶部向下滑动可关闭装扮世界")
    }

    private func kakaCustomizationControls(scale: CGFloat) -> some View {
        Group {
            Text("换装")
                .gardenFont(size: 16 * scale, weight: .medium)
                .foregroundStyle(.white)
                .frame(width: 338 * scale, height: 24 * scale, alignment: .leading)
                .position(x: 201 * scale, y: 564 * scale)

            KakaCarouselSection(
                items: KakaAppearance.outfits,
                selection: $outfitSelection,
                scale: scale,
                cardColors: [.orange, .pink, .yellow, .green, .orange, .blue, .red]
            )
            .position(x: 201 * scale, y: 649 * scale)
        }
    }

    private func synchronizeCustomizationSelection() {
        if KakaAppearance.outfits.contains(store.kakaAppearance) {
            outfitSelection = store.kakaAppearance
        }
    }

    private func dismissCustomizationSheet() {
        withAnimation(.easeIn(duration: 0.24)) {
            customizationSheetOffset = 874
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            isCustomizing = false
        }
    }

    private func activateWorldNavigation() {
        guard !hasActivatedWorldNavigation else { return }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
            hasActivatedWorldNavigation = true
        }
    }

}

@MainActor
final class MoodMusicPlayer: ObservableObject {
    private static var sharedBaseBuffer: AVAudioPCMBuffer?
    static var preloadedBaseBuffer: AVAudioPCMBuffer? { sharedBaseBuffer }
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 1)
    private var baseBuffer: AVAudioPCMBuffer?
    private var graphInstalled = false
    private var activeMoodKey: String?
    private var transitionTask: Task<Void, Never>?

    func preload() {
        guard baseBuffer == nil else { return }
        if let cached = Self.sharedBaseBuffer {
            baseBuffer = cached
            return
        }
        guard
              let url = Bundle.main.url(
                forResource: "music_base_classical_vibes_2",
                withExtension: "mp3"
              ),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
              ) else { return }
        do {
            try file.read(into: buffer)
            baseBuffer = buffer
            Self.sharedBaseBuffer = buffer
        } catch {
            baseBuffer = nil
        }
    }

    func play(_ mood: MusicMood) {
        let profile: HomeMoodPlayback
        switch mood {
        case .joy:
            profile = HomeMoodPlayback(key: "happy", rate: 1.08, pitch: 3.0, filterFrequency: 9_200)
        case .calm:
            profile = HomeMoodPlayback(key: "calm", rate: 0.94, pitch: 0, filterFrequency: 7_000)
        case .expectation:
            profile = HomeMoodPlayback(key: "expectation", rate: 1.00, pitch: -1.0, filterFrequency: 6_200)
        case .low:
            profile = HomeMoodPlayback(key: "sad", rate: 0.82, pitch: -4.0, filterFrequency: 4_800)
        }
        play(profile)
    }

    func play(_ profile: HomeMoodPlayback) {
        preload()
        guard let baseBuffer else { return }

        if activeMoodKey == profile.key, engine.isRunning {
            return
        }

        transitionTask?.cancel()
        let shouldFadeOut = engine.isRunning
        transitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if shouldFadeOut {
                await self.fadePlayer(to: 0, duration: 0.24)
            }
            guard !Task.isCancelled else { return }
            self.start(profile, baseBuffer: baseBuffer)
            await self.fadePlayer(
                to: ParentComfortRuntime.musicVolume * 0.64,
                duration: 0.26
            )
        }
    }

    private func start(_ profile: HomeMoodPlayback, baseBuffer: AVAudioPCMBuffer) {

        configureAudioSession()
        player.stop()
        if engine.isRunning {
            engine.stop()
        }

        do {
            if !graphInstalled {
                engine.attach(player)
                engine.attach(timePitch)
                engine.attach(equalizer)
                engine.connect(player, to: timePitch, format: baseBuffer.format)
                engine.connect(timePitch, to: equalizer, format: baseBuffer.format)
                engine.connect(equalizer, to: engine.mainMixerNode, format: baseBuffer.format)
                let band = equalizer.bands[0]
                band.filterType = .lowPass
                band.bypass = false
                graphInstalled = true
            }

            timePitch.rate = profile.rate
            timePitch.pitch = profile.pitch
            equalizer.bands[0].frequency = profile.filterFrequency
            equalizer.bands[0].gain = 0
            player.volume = 0
            player.scheduleBuffer(baseBuffer, at: nil, options: .loops)
            engine.prepare()
            try engine.start()
            player.play()
            activeMoodKey = profile.key
        } catch {
            stop()
        }
    }

    private func fadePlayer(to target: Float, duration: TimeInterval) async {
        let start = player.volume
        let steps = max(1, Int(duration / 0.04))
        for step in 1...steps {
            guard !Task.isCancelled else { return }
            let progress = Float(step) / Float(steps)
            player.volume = start + (target - start) * progress
            try? await Task.sleep(for: .milliseconds(40))
        }
        player.volume = target
    }

    func stop(deactivateSession: Bool = true) {
        transitionTask?.cancel()
        transitionTask = nil
        player.stop()
        engine.stop()
        player.volume = 0
        activeMoodKey = nil
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
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

struct HomeMoodPlayback {
    let key: String
    let rate: Float
    let pitch: Float
    let filterFrequency: Float
}

/// 首页五种情绪球使用 Figma 导出的透明三帧素材。
/// 未选中时只显示首帧，选中时在同一素材内循环播放，保证球的颜色和音乐板块一致。
private struct FigmaHomeMoodOrb: View {
    let asset: String
    let isAnimated: Bool
    let frameDuration: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let frameCount = 3

    var body: some View {
        Group {
            if isAnimated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let rawPhase = timeline.date.timeIntervalSinceReferenceDate / frameDuration
                    let baseFrame = Int(floor(rawPhase)) % frameCount
                    let nextFrame = (baseFrame + 1) % frameCount
                    let linearBlend = rawPhase - floor(rawPhase)
                    let blend = (1 - cos(.pi * linearBlend)) / 2

                    ZStack {
                        spriteFrame(baseFrame)
                            .opacity(1 - blend)
                        spriteFrame(nextFrame)
                            .opacity(blend)
                    }
                }
            } else {
                spriteFrame(0)
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
                ForEach(0..<3, id: \.self) { page in
                    Circle()
                        .fill(page == currentPage ? Color(red: 0.02, green: 0.78, blue: 0.81) : Color.white.opacity(0.88))
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

    private var currentPage: Int {
        guard let selection, let index = items.firstIndex(of: selection) else { return 0 }
        return min(index / 3, 2)
    }

    private func cardGradient(color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.42), .white.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
