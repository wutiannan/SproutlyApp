/*
 THESIS: 音乐世界是情绪入口，拍照与填色共同改变一段不中断的音乐。
 OWN-WORLD: 全屏自然场景、透明动态情绪球、青绿声波、蓝线正念画稿。
 STORY: 选择音乐世界，记录当下情绪，填色调节声音，再记录变化。
 FIRST VIEWPORT: 自然场景满屏，动态球居中，KAKA 与入口停靠在底部。
 FORM: Figma 音乐312–314沉浸式线性体验。
 FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md
*/

import AVFoundation
import AudioToolbox
import SwiftUI
import UIKit
import Vision

struct FigmaMusicView: View {
    var onContentReady: () -> Void = {}
    var onGuidanceFlowChanged: (Bool) -> Void = { _ in }

    @EnvironmentObject private var store: GardenStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var player = AdaptiveMusicPlayer()
    @StateObject private var homepageVideo = MusicHomepageVideoController()
    @StateObject private var camera = MusicCameraController()

    @State private var step: MusicFlowStep = .world
    @State private var selectedWorld: MusicWorld = .happy
    @State private var selectedArtworkIndex: Int
    @State private var selectedColorIndex = 0
    @State private var coloredImages: [UIImage?]
    @State private var colorAssignments: [[UInt16: UIColor]]
    @State private var colorProfile: MindfulColorProfile
    @State private var afterMood: MusicWorld?
    @State private var capturedPhoto: UIImage?
    @State private var faceCrop: UIImage?
    @State private var completedArtworkSnapshot: UIImage?
    @State private var completedCardID = UUID()
    @State private var showsAudioNotice = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdSucceeded = false
    @State private var sessionStartedAt = Date()
    @State private var sessionCompletedAt: Date?
    @State private var elapsedSeconds = 0
    @State private var showsColoringGuide = true
    @State private var sessionAudioName: String?
    @State private var compositionDuration: TimeInterval = 0
    @State private var audioCommitted = false
    @State private var showsExitColoringPrompt = false
    @State private var musicIsReady = false
    @State private var didReportContentReady = false

    private let outlineAssets = ["music313_outline"]
    private let regionAssets = ["music313_regions"]
    private let palette: [UIColor] = [
        UIColor(red: 0x4A / 255, green: 0x80 / 255, blue: 0xD1 / 255, alpha: 1),
        UIColor(red: 0x38 / 255, green: 0xD6 / 255, blue: 0xD6 / 255, alpha: 1),
        UIColor(red: 0x80 / 255, green: 0xE0 / 255, blue: 0xCF / 255, alpha: 1),
        UIColor(red: 0x8C / 255, green: 0x87 / 255, blue: 0xE8 / 255, alpha: 1),
        UIColor(red: 0xEB / 255, green: 0xA8 / 255, blue: 0xD1 / 255, alpha: 1),
        UIColor(red: 0xF2 / 255, green: 0xDB / 255, blue: 0x73 / 255, alpha: 1),
        UIColor(red: 0xEF / 255, green: 0xB6 / 255, blue: 0x6F / 255, alpha: 1),
        UIColor(red: 0xE5 / 255, green: 0x8F / 255, blue: 0x86 / 255, alpha: 1),
        UIColor(red: 0x8F / 255, green: 0xBF / 255, blue: 0x8F / 255, alpha: 1),
        UIColor(red: 0x86 / 255, green: 0xBE / 255, blue: 0xE5 / 255, alpha: 1),
        UIColor(red: 0xB5 / 255, green: 0xA3 / 255, blue: 0xDE / 255, alpha: 1),
        UIColor(red: 0xD9 / 255, green: 0xC4 / 255, blue: 0x9A / 255, alpha: 1)
    ]

    init(
        onContentReady: @escaping () -> Void = {},
        onGuidanceFlowChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onContentReady = onContentReady
        self.onGuidanceFlowChanged = onGuidanceFlowChanged
        let draft = MusicColorDraftStore.load(artworkCount: 1)
        let restoredAssignments = draft.assignments
        let artwork = 0
        _selectedArtworkIndex = State(initialValue: artwork)
        _colorAssignments = State(initialValue: restoredAssignments)
        _coloredImages = State(
            initialValue: zip(
                ["music313_regions"],
                restoredAssignments
            ).map { asset, assignments in
                MusicRegionPainter.image(
                    regionAsset: asset,
                    assignments: assignments
                )
            }
        )
        _colorProfile = State(
            initialValue: MusicRegionPainter.profile(
                regionAsset: "music313_regions",
                assignments: restoredAssignments[artwork]
            ) ?? .empty
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / 402,
                proxy.size.height / 874
            )

            ZStack {
                selectedWorld.backgroundColor
                    .ignoresSafeArea()

                Group {
                    switch step {
                    case .world:
                        worldScreen(scale: scale)
                    case .artwork:
                        artworkScreen(scale: scale)
                    case .camera:
                        cameraScreen(scale: scale)
                    case .review:
                        photoReviewScreen(scale: scale)
                    case .afterEmotion:
                        emotionScreen(
                            selection: $afterMood,
                            scale: scale
                        )
                    case .result:
                        resultScreen(scale: scale)
                    }
                }
                .frame(width: 402 * scale, height: 874 * scale)
                .clipped()
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.992)))
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .center
            )
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: reduceMotion ? 0.01 : 0.24), value: step)
        .onAppear {
            onGuidanceFlowChanged(true)
            player.prepare()
            musicIsReady = player.play(selectedWorld)
            if !musicIsReady {
                showsAudioNotice = true
            }
            reportContentReadyIfPossible()
        }
        .onChange(of: selectedWorld) { _, world in
            musicIsReady = player.play(world)
            if !musicIsReady {
                showsAudioNotice = true
            }
            reportContentReadyIfPossible()
        }
        .onChange(of: homepageVideo.isReady) { _, _ in
            reportContentReadyIfPossible()
        }
        .onChange(of: homepageVideo.activeWorld) { _, _ in
            reportContentReadyIfPossible()
        }
        .onChange(of: reduceMotion) { _, _ in
            reportContentReadyIfPossible()
        }
        .onChange(of: selectedArtworkIndex) { _, index in
            guard regionAssets.indices.contains(index),
                  colorAssignments.indices.contains(index) else { return }
            colorProfile = MusicRegionPainter.profile(
                regionAsset: regionAssets[index],
                assignments: colorAssignments[index]
            ) ?? .empty
            saveDraft()
        }
        .onChange(of: step) { _, newStep in
            if newStep == .camera {
                Task { await camera.start() }
            } else {
                camera.stop()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in
            if step == .camera {
                Task { await camera.start() }
            } else {
                player.resumeAfterInterruption()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willResignActiveNotification
            )
        ) { _ in
            player.pauseForInterruption()
        }
        .onChange(of: player.didReachRecordingLimit) { _, reachedLimit in
            guard reachedLimit, step == .artwork else { return }
            finalizeComposition()
            saveDraft()
            move(to: .camera)
        }
        .onDisappear {
            camera.stop()
            if !audioCommitted {
                MusicSessionAudioStore.delete(sessionAudioName)
            }
            player.stop()
            onGuidanceFlowChanged(false)
        }
        .alert("暂时无法播放音乐", isPresented: $showsAudioNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请检查设备媒体音量后重试，填色功能仍可继续使用。")
        }
        .confirmationDialog(
            "要保存这次填色草稿吗？",
            isPresented: $showsExitColoringPrompt,
            titleVisibility: .visible
        ) {
            Button("保存草稿") {
                saveDraft()
                player.discardRecording()
                compositionDuration = 0
                move(to: .world)
            }
            Button("不保存", role: .destructive) {
                player.discardRecording()
                MusicColorDraftStore.clear()
                colorAssignments = Array(repeating: [:], count: outlineAssets.count)
                coloredImages = Array(repeating: nil, count: outlineAssets.count)
                colorProfile = .empty
                compositionDuration = 0
                move(to: .world)
            }
            Button("继续创作", role: .cancel) {}
        }
    }

    private var completion: Double {
        colorProfile.coloredFraction
    }

    private func reportContentReadyIfPossible() {
        guard !didReportContentReady,
              musicIsReady,
              homepageVideo.activeWorld == selectedWorld,
              (homepageVideo.isReady || reduceMotion)
        else { return }
        didReportContentReady = true
        onContentReady()
    }

    private func move(to destination: MusicFlowStep, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.24)) {
                step = destination
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                step = destination
            }
        }
    }

    private func resetSession() {
        if !audioCommitted {
            MusicSessionAudioStore.delete(sessionAudioName)
        }
        player.discardRecording()
        afterMood = nil
        capturedPhoto = nil
        faceCrop = nil
        completedArtworkSnapshot = nil
        completedCardID = UUID()
        colorAssignments = Array(repeating: [:], count: outlineAssets.count)
        coloredImages = Array(repeating: nil, count: outlineAssets.count)
        colorProfile = .empty
        selectedArtworkIndex = 0
        selectedColorIndex = 0
        holdProgress = 0
        holdSucceeded = false
        sessionCompletedAt = nil
        elapsedSeconds = 0
        showsColoringGuide = true
        sessionAudioName = nil
        compositionDuration = 0
        audioCommitted = false
        sessionStartedAt = Date()
        move(to: .world)
    }

    private func saveDraft() {
        MusicColorDraftStore.save(
            selectedArtworkIndex: selectedArtworkIndex,
            assignments: colorAssignments
        )
    }

    private func finishSession(with mood: MusicWorld) {
        if sessionAudioName == nil {
            finalizeComposition()
        }
        afterMood = mood
        let completedAt = Date()
        sessionCompletedAt = completedAt
        elapsedSeconds = max(
            1,
            Int(
                compositionDuration > 0
                    ? compositionDuration.rounded()
                    : completedAt.timeIntervalSince(sessionStartedAt).rounded()
            )
        )
        let faceName = store.parentPreferences.retainEmotionPhotos
            ? faceCrop.flatMap(MusicFaceSnapshotStore.save)
            : nil
        let artwork = renderCompletedArtwork()
        completedArtworkSnapshot = artwork
        completedCardID = UUID()
        let artworkName = artwork.flatMap(MusicArtworkSnapshotStore.save)
        let details = MusicSessionDetails(
            world: selectedWorld.title,
            beforeMood: selectedWorld.checkInTitle,
            afterMood: mood.checkInTitle,
            completion: completion,
            dominantHue: colorProfile.dominantHue,
            meanSaturation: colorProfile.meanSaturation,
            warmProportion: colorProfile.warmProportion,
            artworkIndex: selectedArtworkIndex,
            faceImageName: faceName,
            artworkImageName: artworkName,
            moodColorHexes: resultMoodColorHexes,
            durationSeconds: elapsedSeconds,
            audioFileName: sessionAudioName
        )
        store.recordEmotion(
            mood.recordEmotion,
            source: .musicReflection,
            at: completedAt,
            musicSession: details
        )
        audioCommitted = true
        move(to: .result)
    }

    private func completeEmotionSelection(_ mood: MusicWorld) {
        guard !holdSucceeded else { return }
        holdSucceeded = true
        holdProgress = 1
        if store.parentPreferences.hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlaySystemSound(1025)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            finishSession(with: mood)
        }
    }

    private func returnToMusicHome() {
        MusicColorDraftStore.clear()
        sessionAudioName = nil
        resetSession()
    }

    private func openSavedRecord() {
        MusicColorDraftStore.clear()
        sessionAudioName = nil
        resetSession()
        store.requestedProfilePage = 2
        store.selectedTab = .profile
    }
}

private enum MusicFlowStep: Hashable {
    case world
    case artwork
    case camera
    case review
    case afterEmotion
    case result
}

private enum MusicWorld: Int, CaseIterable, Identifiable, Hashable {
    case happy
    case calm
    case low
    case angry
    case tense

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .happy: "快乐"
        case .calm: "平静"
        case .low: "低落"
        case .angry: "生气"
        case .tense: "紧张"
        }
    }

    var checkInTitle: String {
        switch self {
        case .happy: "开心"
        case .calm: "平静"
        case .low: "难过"
        case .angry: "生气"
        case .tense: "紧张"
        }
    }

    var backgroundAsset: String {
        switch self {
        case .happy: "music_world_happy"
        case .calm: "music_world_calm"
        case .low: "music_world_low"
        case .angry: "music_world_angry"
        case .tense: "music_world_tense"
        }
    }

    var homepageBackgroundAsset: String {
        switch self {
        case .happy: "music_home_background_happy"
        case .calm: "music_home_background_calm"
        case .low: "music_home_background_sad"
        case .angry: "music_home_background_angry"
        case .tense: "music_home_background_afraid"
        }
    }

    var homepageVideoResource: String {
        switch self {
        case .happy: "music_home_video_happy"
        case .calm: "music_home_video_calm"
        case .low: "music_home_video_low"
        case .angry: "music_home_video_angry"
        case .tense: "music_home_video_tense"
        }
    }

    var homepageOrbAsset: String {
        switch self {
        case .happy: "music_home_orb_happy"
        case .calm: "music_home_orb_calm"
        case .low: "music_home_orb_sad"
        case .angry: "music_home_orb_angry"
        case .tense: "music_home_orb_afraid"
        }
    }

    var homepageOverlayTopColor: Color {
        switch self {
        case .happy:
            Color(red: 1, green: 240 / 255, blue: 195 / 255).opacity(0.30)
        case .calm:
            Color(red: 17 / 255, green: 164 / 255, blue: 1).opacity(0.30)
        case .low:
            Color(red: 195 / 255, green: 1, blue: 249 / 255).opacity(0.30)
        case .angry:
            Color(red: 1, green: 195 / 255, blue: 196 / 255).opacity(0.30)
        case .tense:
            Color(red: 206 / 255, green: 195 / 255, blue: 1).opacity(0.30)
        }
    }

    var checkInAsset: String {
        switch self {
        case .happy: "music_checkin_happy"
        case .calm: "music_checkin_calm"
        case .low: "music_checkin_low"
        case .angry: "music_checkin_angry"
        case .tense: "music_checkin_tense"
        }
    }

    var checkInHaloColor: Color {
        switch self {
        case .happy: Color(red: 241 / 255, green: 215 / 255, blue: 120 / 255)
        case .calm: Color(red: 143 / 255, green: 214 / 255, blue: 201 / 255)
        case .low: Color(red: 148 / 255, green: 170 / 255, blue: 218 / 255)
        case .angry: Color(red: 228 / 255, green: 163 / 255, blue: 172 / 255)
        case .tense: Color(red: 197 / 255, green: 174 / 255, blue: 217 / 255)
        }
    }

    var orbAsset: String {
        switch self {
        case .happy: "music_orb_joy"
        case .calm: "music_orb_calm"
        case .low: "music_orb_low"
        case .angry, .tense: "music_orb_expectation"
        }
    }

    var diaryTitle: String {
        switch self {
        case .happy: "快乐花园"
        case .calm: "静谧花园"
        case .low: "忧郁花园"
        case .angry: "暖阳花园"
        case .tense: "安心花园"
        }
    }

    var diaryReflection: String {
        switch self {
        case .happy: "明亮的颜色在花园里跳舞，今天的快乐被好好收藏起来了。"
        case .calm: "柔和的颜色静静铺开，呼吸和音乐都慢慢安稳下来。"
        case .low: "一个安静的小花园。颜色慢慢亮起来，心也被温柔地接住。"
        case .angry: "热烈的颜色逐渐变得柔和，心里的风也慢慢停了下来。"
        case .tense: "轻轻的颜色围在身边，呼吸变慢，身体也一点点放松。"
        }
    }

    var fallbackResource: String {
        // 统一使用一段完整的纯器乐曲，情绪差异由速度、音高和空间感调整。
        "music_base_classical_vibes_2"
    }

    var accent: Color {
        switch self {
        case .happy: Color(red: 1.00, green: 0.82, blue: 0.30)
        case .calm: Color(red: 0.18, green: 0.84, blue: 0.78)
        case .low: Color(red: 0.42, green: 0.60, blue: 0.92)
        case .angry: Color(red: 0.96, green: 0.34, blue: 0.34)
        case .tense: Color(red: 0.78, green: 0.35, blue: 0.90)
        }
    }

    var orbColors: [Color] {
        switch self {
        case .happy: [.white, .yellow, .orange, Color(red: 0.30, green: 0.94, blue: 0.79)]
        case .calm: [.white, .cyan, Color(red: 0.12, green: 0.72, blue: 0.68), .mint]
        case .low: [.white, Color(red: 0.42, green: 0.72, blue: 1), .indigo, .cyan]
        case .angry: [.white, .red, .orange, .pink]
        case .tense: [.white, .purple, .indigo, .pink]
        }
    }

    var backgroundColor: Color {
        switch self {
        case .happy: Color(red: 0.77, green: 0.91, blue: 0.92)
        case .calm: Color(red: 0.70, green: 0.90, blue: 0.86)
        case .low: Color(red: 0.49, green: 0.65, blue: 0.78)
        case .angry: Color(red: 0.89, green: 0.67, blue: 0.60)
        case .tense: Color(red: 0.60, green: 0.66, blue: 0.82)
        }
    }

    var energy: Double {
        switch self {
        case .happy: 0.82
        case .calm: 0.44
        case .low: 0.28
        case .angry: 0.74
        case .tense: 0.62
        }
    }

    var streamURL: URL? {
        let value: String
        switch self {
        case .happy:
            value = "https://files.freemusicarchive.org/storage-freemusicarchive-org/music/no_curator/Kevin_MacLeod/Calming/Kevin_MacLeod_-_Carefree.mp3"
        case .calm, .angry:
            value = "https://upload.wikimedia.org/wikipedia/commons/2/2a/Gymnopedie_No._1_%28ISRC_USUAN1100787%29.mp3"
        case .low:
            value = "https://upload.wikimedia.org/wikipedia/commons/5/5e/Peaceful_Desolation_%28ISRC_USUAN1200017%29.mp3"
        case .tense:
            value = "https://upload.wikimedia.org/wikipedia/commons/e/e4/Lasting_Hope_%28ISRC_USUAN1100178%29.mp3"
        }
        return URL(string: value)
    }

    var recordEmotion: EmotionKind {
        switch self {
        case .happy: .joy
        case .calm: .calm
        case .low: .low
        case .angry, .tense: .expectation
        }
    }

    var guidance: String {
        switch self {
        case .happy: "让明亮的心情慢慢稳定下来"
        case .calm: "保持现在温柔、专注的节奏"
        case .low: "从被陪伴，慢慢走向温暖"
        case .angry: "让快节奏一点点变得舒缓"
        case .tense: "跟着安全的节拍放松下来"
        }
    }

    var motionMood: MusicMood {
        switch self {
        case .happy: .joy
        case .calm: .calm
        case .low: .low
        case .angry, .tense: .expectation
        }
    }
}

private extension FigmaMusicView {
    func worldScreen(scale: CGFloat) -> some View {
        ZStack {
            MusicHomepageBackdrop(
                world: selectedWorld,
                controller: homepageVideo,
                isActive: true,
                reduceMotion: reduceMotion
            )
                .frame(width: 402 * scale, height: 874 * scale)

            Button {
                store.selectedTab = .garden
            } label: {
                Image("music_world_back")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48 * scale, height: 48 * scale)
                    .musicGlossCircle(scale: scale)
            }
            .buttonStyle(.plain)
            .position(x: 48 * scale, y: 84 * scale)
            .accessibilityLabel("返回首页")

            MusicInteractiveMoodOrb(
                world: selectedWorld,
                orbSize: 224 * scale,
                particleReach: 50 * scale
            )
            .frame(width: 324 * scale, height: 324 * scale)
            .position(x: 201 * scale, y: 307 * scale)
            .accessibilityLabel("\(selectedWorld.title)情绪球")

            AnimatedWaveform(
                mood: selectedWorld.motionMood,
                gradient: selectedWorld == .tense
                    ? Array(selectedWorld.orbColors.dropLast())
                    : nil
            )
                .frame(width: 402 * scale, height: 83 * scale)
                .position(x: 201 * scale, y: 711 * scale)

            MusicCarouselArrow(direction: .left, scale: scale) {
                cycleWorld(by: -1)
            }
            .position(x: 40.702 * scale, y: 316.622 * scale)
            .zIndex(12)

            MusicCarouselArrow(direction: .right, scale: scale) {
                cycleWorld(by: 1)
            }
            .position(x: 361.302 * scale, y: 316.622 * scale)
            .zIndex(12)

            MusicSpeechBubble(text: "欢迎进入“\(selectedWorld.title)”的音乐世界", scale: scale)
                .frame(width: 238 * scale, height: 58 * scale)
                .position(x: 199 * scale, y: 547 * scale)

            KakaAvatarView(magnification: 1.28)
                .frame(width: 88 * scale, height: 82 * scale)
                .position(x: 352 * scale, y: 598 * scale)

            MusicEntryButton(scale: scale) {
                sessionStartedAt = Date()
                sessionCompletedAt = nil
                elapsedSeconds = 0
                move(to: .artwork)
            }
            .position(x: 315.16 * scale, y: 809 * scale)
            .zIndex(20)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    let orbCenter = CGPoint(x: 201 * scale, y: 307 * scale)
                    let startDistance = hypot(
                        value.startLocation.x - orbCenter.x,
                        value.startLocation.y - orbCenter.y
                    )
                    // 球内拖动专用于粒子探索；只有从球外开始的横向手势才切换音乐世界。
                    guard startDistance > 112 * scale else { return }
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.3,
                          abs(value.translation.width) > 52 * scale else { return }
                    cycleWorld(by: value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    func artworkScreen(scale: CGFloat) -> some View {
        ZStack {
            MusicHomepageBackdrop(
                world: selectedWorld,
                controller: homepageVideo,
                isActive: false,
                reduceMotion: reduceMotion
            )
                .frame(width: 402 * scale, height: 874 * scale)
                .blur(radius: 5 * scale)
                .scaleEffect(1.03)

            RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                .fill(Color(red: 0.969, green: 0.984, blue: 0.973).opacity(0.96))
                .frame(width: 354.25 * scale, height: 505.18 * scale)
                .shadow(color: Color(red: 0.10, green: 0.28, blue: 0.29).opacity(0.09), radius: 14 * scale, y: 4 * scale)
                .position(x: 201 * scale, y: 379.34 * scale)

            MusicColoringPager(
                outlineAssets: outlineAssets,
                regionAssets: regionAssets,
                selectedColor: palette[selectedColorIndex],
                onRegionFilled: handleRegionFilled,
                onCanvasTapped: dismissColoringGuide,
                selectedIndex: $selectedArtworkIndex,
                coloredImages: $coloredImages,
                colorAssignments: $colorAssignments
            )
            .frame(width: 337.48 * scale, height: 488.41 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 20 * scale, style: .continuous))
            .position(x: 201 * scale, y: 379.34 * scale)

            coloringKakaGuide(scale: scale)

            Button {
                if player.hasActiveRecording {
                    showsExitColoringPrompt = true
                } else {
                    move(to: .world)
                }
            } label: {
                Image("music_artwork_back")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48 * scale, height: 48 * scale)
                    .musicGlossCircle(scale: scale)
            }
            .buttonStyle(.plain)
            .position(x: 48 * scale, y: 84 * scale)
            .accessibilityLabel("返回音乐空间")

            Image("music_artwork_title")
                .resizable()
                .scaledToFit()
                .frame(width: 42.4 * scale, height: 41.1 * scale)
                .position(x: 201 * scale, y: 80 * scale)

            MusicPaletteStrip(
                colors: palette,
                selectedIndex: $selectedColorIndex,
                scale: scale
            )
            .frame(width: 354 * scale, height: 64 * scale)
            .position(x: 201 * scale, y: 717.84 * scale)

            MusicPlaybackPill(
                world: selectedWorld,
                level: player.level,
                isOnline: player.isOnline,
                scale: scale
            )
            .frame(width: 150 * scale, height: 48 * scale)
            .position(x: 98.87 * scale, y: 809 * scale)

            MusicArtworkEntryButton(scale: scale) {
                guard completion >= 0.70 else { return }
                finalizeComposition()
                saveDraft()
                move(to: .camera)
            }
            .disabled(completion < 0.70)
            .opacity(completion >= 0.70 ? 1 : 0.46)
            .position(x: 315.16 * scale, y: 809 * scale)
            .zIndex(20)
            .accessibilityHint("当前已完成 \(Int(completion * 100))%，达到百分之七十后可继续拍照")
        }
    }

    func cameraScreen(scale: CGFloat) -> some View {
        let guide = cameraFaceGuideLayout(scale: scale)

        return ZStack {
            MusicCameraPreview(session: camera.session)
                .frame(width: 402 * scale, height: 874 * scale)
                .ignoresSafeArea()

            Image("music_camera_face_guide")
                .resizable()
                .interpolation(.high)
                .frame(width: guide.size.width, height: guide.size.height)
                .position(guide.center)
                .animation(.easeOut(duration: 0.16), value: guide)

            Image("music_camera_flower")
                .resizable()
                .scaledToFit()
                .frame(width: 35 * scale, height: 34 * scale)
                .position(
                    x: guide.center.x,
                    y: guide.center.y - guide.size.height / 2 + 8 * scale
                )
                .animation(.easeOut(duration: 0.16), value: guide)

            Button {
                move(to: .artwork)
            } label: {
                Image("music_camera_back")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48 * scale, height: 48 * scale)
                    .musicGlossCircle(scale: scale)
            }
            .buttonStyle(.plain)
            .position(x: 48 * scale, y: 84 * scale)
            .accessibilityLabel("返回线稿")

            if camera.authorization != .denied {
                Button {
                    guard let capture = camera.captureCurrentFrame() else { return }
                    capturedPhoto = capture.fullImage
                    faceCrop = capture.faceImage
                    camera.stop()
                    move(to: .review, animated: false)
                } label: {
                    ZStack {
                        Image("music_camera_capture_base")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 136 * scale, height: 136 * scale)
                            .offset(y: 5 * scale)
                        Image("music_camera_capture_ring")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 108 * scale, height: 108 * scale)
                            .offset(y: 5 * scale)
                        Image("music_camera_capture_face")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 62 * scale, height: 62 * scale)
                        Image("music_camera_capture_icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 37.985 * scale, height: 31.613 * scale)
                    }
                    .frame(width: 104 * scale, height: 104 * scale)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!camera.hasFreshFrame)
                .position(x: 201 * scale, y: 728 * scale)
                .accessibilityLabel("拍照")
            }

            if camera.authorization == .denied {
                Color(red: 0.04, green: 0.22, blue: 0.23).opacity(0.88)
                VStack(spacing: 15 * scale) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 34 * scale))
                    Text("需要相机权限")
                        .gardenFont(size: 22 * scale, weight: .bold)
                    Text("请允许“灵想”使用前置相机，\n完成本次情绪记录。")
                        .gardenFont(size: 14 * scale)
                        .multilineTextAlignment(.center)
                    Button("前往设置") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .gardenFont(size: 15 * scale, weight: .bold)
                    .buttonStyle(.borderedProminent)
                    .tint(GardenTheme.deepMint)
                }
                .foregroundStyle(.white)
            }
        }
    }

    private func cameraFaceGuideLayout(scale: CGFloat) -> MusicFaceGuideLayout {
        let fallback = MusicFaceGuideLayout(
            center: CGPoint(x: 201 * scale, y: 468.5 * scale),
            size: CGSize(width: 331 * scale, height: 325 * scale)
        )
        guard let trackedFace = camera.trackedFace else { return fallback }

        let viewport = CGSize(width: 402, height: 874)
        let source = trackedFace.imageSize
        guard source.width > 0, source.height > 0 else { return fallback }

        let aspectFillScale = max(
            viewport.width / source.width,
            viewport.height / source.height
        )
        let renderedSize = CGSize(
            width: source.width * aspectFillScale,
            height: source.height * aspectFillScale
        )
        let cropX = (renderedSize.width - viewport.width) / 2
        let cropY = (renderedSize.height - viewport.height) / 2
        let bounds = trackedFace.normalizedBounds
        let faceRect = CGRect(
            x: bounds.minX * renderedSize.width - cropX,
            y: (1 - bounds.maxY) * renderedSize.height - cropY,
            width: bounds.width * renderedSize.width,
            height: bounds.height * renderedSize.height
        )

        let guideWidth = min(
            350,
            max(220, max(faceRect.width * 1.55, faceRect.height * 1.25))
        )
        let guideHeight = guideWidth * 325 / 331
        let halfWidth = guideWidth / 2
        let halfHeight = guideHeight / 2
        let center = CGPoint(
            x: min(max(faceRect.midX, halfWidth), viewport.width - halfWidth),
            y: min(max(faceRect.midY, halfHeight + 112), viewport.height - halfHeight - 122)
        )
        return MusicFaceGuideLayout(
            center: CGPoint(x: center.x * scale, y: center.y * scale),
            size: CGSize(width: guideWidth * scale, height: guideHeight * scale)
        )
    }

    func photoReviewScreen(scale: CGFloat) -> some View {
        ZStack {
            if let capturedPhoto {
                Image(uiImage: capturedPhoto)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 402 * scale, height: 874 * scale)
                    .clipped()
            } else {
                Color.black
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.38)],
                startPoint: .center,
                endPoint: .bottom
            )

            Button {
                capturedPhoto = nil
                faceCrop = nil
                move(to: .camera)
            } label: {
                Image("music_camera_back")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48 * scale, height: 48 * scale)
                    .musicGlossCircle(scale: scale)
            }
            .buttonStyle(.plain)
            .position(x: 48 * scale, y: 84 * scale)
            .accessibilityLabel("返回拍照")

            HStack(spacing: 46 * scale) {
                Button {
                    capturedPhoto = nil
                    faceCrop = nil
                    move(to: .camera)
                } label: {
                    Label("重拍", systemImage: "arrow.triangle.2.circlepath.camera")
                        .gardenFont(size: 14 * scale, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 112 * scale, height: 48 * scale)
                        .background(.black.opacity(0.28), in: Capsule())
                        .musicGlossCapsule(scale: scale)
                }
                .buttonStyle(.plain)

                Button {
                    guard capturedPhoto != nil else { return }
                    withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.28)) {
                        step = .afterEmotion
                    }
                } label: {
                    Label("使用照片", systemImage: "checkmark")
                        .gardenFont(size: 14 * scale, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 128 * scale, height: 48 * scale)
                        .background(GardenTheme.deepMint, in: Capsule())
                        .musicGlossCapsule(scale: scale)
                }
                .buttonStyle(.plain)
            }
            .position(x: 201 * scale, y: 800 * scale)
        }
    }

    func emotionScreen(
        selection: Binding<MusicWorld?>,
        scale: CGFloat
    ) -> some View {
        ZStack {
            if let capturedPhoto {
                Image(uiImage: capturedPhoto)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 475.588 * scale, height: 940.53 * scale)
                    .position(x: 201 * scale, y: 470.265 * scale)
                    .blur(radius: 9 * scale)
            } else {
                MusicWorldBackdrop(world: selectedWorld)
                    .frame(width: 402 * scale, height: 874 * scale)
                    .blur(radius: 9 * scale)
            }
            Color(red: 13 / 255, green: 87 / 255, blue: 89 / 255)
                .opacity(0.50)

            Button {
                move(to: .world)
            } label: {
                Image("music_checkin_back")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48 * scale, height: 48 * scale)
                    .musicGlossCircle(scale: scale)
            }
            .buttonStyle(.plain)
            .position(x: 48.34 * scale, y: 84 * scale)
            .accessibilityLabel("返回音乐空间")

            ZStack {
                Circle()
                    .fill(Color(red: 0.91, green: 0.91, blue: 0.85).opacity(0.26))
                    .frame(width: 240 * scale, height: 240 * scale)

                Group {
                    if let faceCrop {
                        Image(uiImage: faceCrop)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
                .frame(width: 211.2 * scale, height: 211.2 * scale)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.94), lineWidth: 3.6 * scale)
                }
                .shadow(
                    color: (selection.wrappedValue?.accent ?? .white).opacity(
                        selection.wrappedValue == nil ? 0.45 : 0.86
                    ),
                    radius: (selection.wrappedValue == nil ? 11 : 18) * scale
                )
            }
            .frame(width: 240 * scale, height: 240 * scale)
            .position(x: 201 * scale, y: 355 * scale)

            if let selected = selection.wrappedValue {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.90))
                        .overlay {
                            Circle().stroke(selected.accent.opacity(0.74), lineWidth: 2 * scale)
                        }
                        .shadow(color: selected.accent.opacity(0.72), radius: 11 * scale)
                    MusicEmotionSymbol(world: selected, scale: scale)
                        .frame(width: 49 * scale, height: 50 * scale)
                }
                .frame(width: 67 * scale, height: 67 * scale)
                .position(x: 292 * scale, y: 437 * scale)
                .transition(.scale(scale: 0.86).combined(with: .opacity))
            }

            VStack(spacing: 6 * scale) {
                Circle()
                    .fill(.white.opacity(0.80))
                    .frame(width: 7 * scale, height: 7 * scale)
                Circle()
                    .fill(.white.opacity(0.80))
                    .frame(width: 7 * scale, height: 7 * scale)
                Circle()
                    .fill(Color(red: 1.00, green: 0.91, blue: 0.43))
                    .frame(width: 8 * scale, height: 8 * scale)
            }
            .position(x: 201 * scale, y: 513.5 * scale)

            RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                .fill(Color(red: 0.70, green: 0.70, blue: 0.70).opacity(0.39))
                .overlay {
                    RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: scale)
                }
                .frame(width: 355.213 * scale, height: 93.361 * scale)
                .position(x: 201 * scale, y: 605.5 * scale)

            ForEach(Array(MusicWorld.allCases.enumerated()), id: \.element.id) { index, world in
                Button {
                    if ParentComfortRuntime.hapticsEnabled {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                    holdProgress = 0
                    holdSucceeded = false
                    withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.22)) {
                        selection.wrappedValue = world
                    }
                } label: {
                    ZStack {
                        if selection.wrappedValue == world {
                            Circle()
                                .fill(world.accent.opacity(0.28))
                                .frame(width: 72 * scale, height: 72 * scale)
                                .blur(radius: 8 * scale)
                        }
                        MusicEmotionSymbol(world: world, scale: scale)
                            .frame(width: 62 * scale, height: 62 * scale)
                    }
                    .frame(width: 72 * scale, height: 72 * scale)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .position(
                    x: [67, 134, 201, 268, 335][index] * scale,
                    y: 605.5 * scale
                )
                .accessibilityLabel(world.title)
                .accessibilityAddTraits(selection.wrappedValue == world ? .isSelected : [])
            }

            Button {
                capturedPhoto = nil
                faceCrop = nil
                selection.wrappedValue = nil
                move(to: .camera)
            } label: {
                Image("music_checkin_retake")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40.171 * scale, height: 40.171 * scale)
                    .frame(width: 58 * scale, height: 58 * scale)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(x: 60.8 * scale, y: 747.3 * scale)
            .accessibilityLabel("重新拍照")

            ZStack {
                Image("music_checkin_confirm")
                    .resizable()
                    .scaledToFit()
                    .mask {
                        Circle()
                            .frame(width: 82 * scale, height: 82 * scale)
                    }

                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 124 / 255, green: 254 / 255, blue: 224 / 255),
                                Color(red: 134 / 255, green: 255 / 255, blue: 206 / 255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(
                            lineWidth: 5 * scale,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 88.8 * scale, height: 88.8 * scale)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.82),
                                .white.opacity(0.20),
                                Color(red: 124 / 255, green: 254 / 255, blue: 224 / 255)
                                    .opacity(0.46)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2 * scale
                    )
                    .frame(width: 79.5 * scale, height: 79.5 * scale)
                    .allowsHitTesting(false)
            }
            .frame(width: 122.79 * scale, height: 122.79 * scale)
            .contentShape(Circle())
            .opacity(selection.wrappedValue == nil ? 0.52 : 1)
            .allowsHitTesting(selection.wrappedValue != nil)
            .onLongPressGesture(
                minimumDuration: 1.25,
                maximumDistance: 48 * scale,
                pressing: { pressing in
                    guard selection.wrappedValue != nil else { return }
                    if pressing {
                        holdSucceeded = false
                        holdProgress = 0
                        withAnimation(.linear(duration: reduceMotion ? 0.01 : 1.25)) {
                            holdProgress = 1
                        }
                    } else if !holdSucceeded {
                        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.18)) {
                            holdProgress = 0
                        }
                    }
                },
                perform: {
                    guard let mood = selection.wrappedValue else { return }
                    completeEmotionSelection(mood)
                }
            )
            .position(x: 204.505 * scale, y: 745.845 * scale)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("长按确认心情")
            .accessibilityValue("进度 (Int(holdProgress * 100))%")
            .accessibilityAction {
                guard let mood = selection.wrappedValue else { return }
                completeEmotionSelection(mood)
            }

            emotionKakaGuide(
                selection: selection.wrappedValue,
                scale: scale
            )
        }
    }

    private func emotionKakaGuide(
        selection: MusicWorld?,
        scale: CGFloat
    ) -> some View {
        ZStack {
            Image("music_coloring_guide_bubble")
                .resizable()
                .interpolation(.high)
                .frame(width: 266.252 * scale, height: 89.4 * scale)
                .position(x: 199.34 * scale, y: 148.57 * scale)

            Text(
                selection.map { "你现在的心情是\($0.checkInTitle)" }
                    ?? "点一点，选出你的现在的心情~"
            )
            .gardenFont(size: 14 * scale)
            .tracking(0.812 * scale)
            .foregroundStyle(Color(red: 0, green: 80 / 255, blue: 86 / 255))
            .multilineTextAlignment(.center)
            .frame(width: 222 * scale, height: 59 * scale)
            .position(x: 200.24 * scale, y: 145.57 * scale)

            KakaAvatarView(magnification: 1.42)
                .frame(width: 134.861 * scale, height: 88.425 * scale)
                .position(x: 366.10 * scale, y: 205.193 * scale)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func coloringKakaGuide(scale: CGFloat) -> some View {
        if showsColoringGuide {
            Image("music_coloring_guide_bubble")
                .resizable()
                .interpolation(.high)
                .frame(width: 266.252 * scale, height: 89.4 * scale)
                .position(x: 149.966 * scale, y: 537.24 * scale)
                .allowsHitTesting(false)

            Text("请点一点颜色，然后在框中填色哦~")
                .gardenFont(size: 14 * scale)
                .tracking(0.812 * scale)
                .foregroundStyle(Color(red: 0, green: 80 / 255, blue: 86 / 255))
                .multilineTextAlignment(.center)
                .frame(width: 237.541 * scale, height: 59 * scale)
                .position(x: 151.03 * scale, y: 534.24 * scale)
                .allowsHitTesting(false)

            KakaAvatarView(magnification: 1.42)
                .frame(width: 185.786 * scale, height: 121.816 * scale)
                .position(x: 309.103 * scale, y: 610.818 * scale)
                .allowsHitTesting(false)
        } else {
            KakaAvatarView(magnification: 1.24)
                .frame(width: 113.647 * scale, height: 74.516 * scale)
                .rotationEffect(.degrees(8.19))
                .position(x: 346.004 * scale, y: 107.997 * scale)
                .allowsHitTesting(false)
        }
    }

    private func dismissColoringGuide() {
        guard showsColoringGuide else { return }
        showsColoringGuide = false
    }

    private func handleRegionFilled(
        color: UIColor,
        regionFraction: CGFloat,
        profile: MindfulColorProfile
    ) {
        if !player.hasActiveRecording {
            sessionStartedAt = Date()
        }
        colorProfile = profile
        player.respondToColoring(
            color: color,
            regionFraction: regionFraction,
            profile: profile,
            world: selectedWorld
        )
        Task { @MainActor in
            await Task.yield()
            saveDraft()
        }
    }

    private func finalizeComposition() {
        guard sessionAudioName == nil,
              let recording = player.finishRecording() else { return }
        sessionAudioName = recording.name
        compositionDuration = recording.duration
    }

    func resultScreen(scale: CGFloat) -> some View {
        let date = sessionCompletedAt ?? Date()
        let checkedInMood = afterMood ?? selectedWorld
        let data = EmotionMusicCardPresentation(
            id: completedCardID,
            artwork: completedArtworkSnapshot ?? renderCompletedArtwork(),
            fallbackArtworkAsset: "profile_emotion_artwork",
            face: faceCrop,
            fallbackFaceAsset: "profile_emotion_avatar",
            moodAsset: checkedInMood.checkInAsset,
            avatarHaloColor: checkedInMood.checkInHaloColor,
            timestamp: date,
            theme: selectedWorld.diaryTitle,
            durationSeconds: elapsedSeconds,
            moodColors: resultMoodColors,
            reflection: selectedWorld.diaryReflection
        )
        return ZStack {
            EmotionMusicRecordScene(
                data: data,
                showsCardStack: false,
                cardScale: 0.86,
                cardCenterY: 421
            )

            Text("乐卡已保存")
                .gardenFont(size: 14 * scale, weight: .bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 18 * scale)
                .frame(height: 38 * scale)
                .background(.black.opacity(0.18), in: Capsule())
                .position(x: 201 * scale, y: 77 * scale)

            EmotionMusicRecordButtons(
                scale: scale,
                openAlbum: openSavedRecord,
                returnHome: returnToMusicHome
            )
            .position(x: 201 * scale, y: 800 * scale)
        }
    }

    @ViewBuilder
    func completedArtwork(contentMode: ContentMode) -> some View {
        ZStack {
            if coloredImages.indices.contains(selectedArtworkIndex),
               let colored = coloredImages[selectedArtworkIndex] {
                Image(uiImage: colored)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            }
            if outlineAssets.indices.contains(selectedArtworkIndex) {
                Image(outlineAssets[selectedArtworkIndex])
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            }
        }
    }

    func renderCompletedArtwork() -> UIImage? {
        guard outlineAssets.indices.contains(selectedArtworkIndex),
              let outline = UIImage(named: outlineAssets[selectedArtworkIndex]) else {
            return coloredImages.indices.contains(selectedArtworkIndex)
                ? coloredImages[selectedArtworkIndex]
                : nil
        }
        let targetSize = outline.size
        guard targetSize.width > 0, targetSize.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            if coloredImages.indices.contains(selectedArtworkIndex),
               let colored = coloredImages[selectedArtworkIndex] {
                colored.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            outline.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    var resultMoodColors: [Color] {
        resultMoodUIColors.map { Color(uiColor: $0) }
    }

    var resultMoodColorHexes: [String] {
        resultMoodUIColors.compactMap { color in
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            guard color.getRed(&red, green: &green, blue: &blue, alpha: nil) else { return nil }
            return String(
                format: "#%02X%02X%02X",
                Int((red * 255).rounded()),
                Int((green * 255).rounded()),
                Int((blue * 255).rounded())
            )
        }
    }

    var resultMoodUIColors: [UIColor] {
        guard colorAssignments.indices.contains(selectedArtworkIndex) else {
            return Array(palette.prefix(3))
        }
        var unique: [UIColor] = []
        for color in colorAssignments[selectedArtworkIndex].values {
            guard !unique.contains(where: { $0.isEqual(color) }) else { continue }
            unique.append(color)
        }
        for fallback in palette where unique.count < 3 {
            guard !unique.contains(where: { $0.isEqual(fallback) }) else { continue }
            unique.append(fallback)
        }
        return Array(unique.prefix(3))
    }

    func cycleWorld(by delta: Int) {
        let worlds = MusicWorld.allCases
        let next = (selectedWorld.rawValue + delta + worlds.count) % worlds.count
        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.24)) {
            selectedWorld = worlds[next]
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct MusicWorldBackdrop: View {
    let world: MusicWorld

    var body: some View {
        Image(world.backgroundAsset)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .overlay(world.backgroundColor.opacity(0.08))
            .clipped()
            .accessibilityHidden(true)
    }
}

private struct MusicHomepageBackdrop: View {
    let world: MusicWorld
    @ObservedObject var controller: MusicHomepageVideoController
    let isActive: Bool
    let reduceMotion: Bool
    @Environment(\.scenePhase) private var scenePhase

    private var playbackIsActive: Bool {
        isActive && scenePhase == .active
    }

    var body: some View {
        ZStack {
            Image(world.homepageBackgroundAsset)
                .resizable()
                .interpolation(.high)
                .scaledToFill()

            if isActive,
               !reduceMotion,
               controller.activeWorld == world,
               let player = controller.player {
                MusicHomepageVideoLayer(player: player) {
                    controller.markReady(for: world)
                }
                    .opacity(controller.isReady ? 1 : 0)
                    .animation(.easeInOut(duration: 0.24), value: controller.isReady)
            }

            LinearGradient(
                colors: [
                    world.homepageOverlayTopColor,
                    Color.white.opacity(0.30)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .accessibilityHidden(true)
        .onAppear {
            controller.update(
                world: world,
                isActive: playbackIsActive,
                reduceMotion: reduceMotion
            )
        }
        .onChange(of: world) { _, newWorld in
            controller.update(
                world: newWorld,
                isActive: playbackIsActive,
                reduceMotion: reduceMotion
            )
        }
        .onChange(of: isActive) { _, active in
            controller.update(
                world: world,
                isActive: active && scenePhase == .active,
                reduceMotion: reduceMotion
            )
        }
        .onChange(of: reduceMotion) { _, reduced in
            controller.update(
                world: world,
                isActive: playbackIsActive,
                reduceMotion: reduced
            )
        }
        .onChange(of: scenePhase) { _, _ in
            controller.update(
                world: world,
                isActive: playbackIsActive,
                reduceMotion: reduceMotion
            )
        }
        .onDisappear {
            controller.update(
                world: world,
                isActive: false,
                reduceMotion: reduceMotion
            )
        }
    }
}

@MainActor
private final class MusicHomepageVideoController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var activeWorld: MusicWorld?
    @Published private(set) var isReady = false

    private var looper: AVPlayerLooper?
    private var shouldPlay = false

    func update(world: MusicWorld, isActive: Bool, reduceMotion: Bool) {
        shouldPlay = isActive && !reduceMotion
        if activeWorld != world {
            prepare(world: world)
        }

        guard shouldPlay else {
            player?.pause()
            return
        }
        player?.playImmediately(atRate: 1)
    }

    func markReady(for world: MusicWorld) {
        guard activeWorld == world else { return }
        isReady = true
    }

    private func prepare(world: MusicWorld) {
        looper = nil

        player?.pause()
        player = nil
        isReady = false
        activeWorld = world

        guard let url = Bundle.main.url(
            forResource: world.homepageVideoResource,
            withExtension: "mp4"
        ) else {
            return
        }

        let item = AVPlayerItem(url: url)
        let nextPlayer = AVQueuePlayer()
        nextPlayer.isMuted = true
        nextPlayer.automaticallyWaitsToMinimizeStalling = false
        nextPlayer.actionAtItemEnd = .advance
        looper = AVPlayerLooper(player: nextPlayer, templateItem: item)
        player = nextPlayer

        if shouldPlay {
            nextPlayer.playImmediately(atRate: 1)
        }
    }
}

private struct MusicHomepageVideoLayer: UIViewRepresentable {
    let player: AVPlayer
    let onReadyForDisplay: () -> Void

    func makeUIView(context: Context) -> MusicHomepageVideoView {
        let view = MusicHomepageVideoView()
        view.onReadyForDisplay = onReadyForDisplay
        view.player = player
        return view
    }

    func updateUIView(_ uiView: MusicHomepageVideoView, context: Context) {
        uiView.onReadyForDisplay = onReadyForDisplay
        uiView.player = player
    }
}

private final class MusicHomepageVideoView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var onReadyForDisplay: (() -> Void)? {
        didSet { reportReadyFrameIfNeeded() }
    }

    private var readyObservation: NSKeyValueObservation?
    private var hasReportedReadyFrame = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        playerLayer.backgroundColor = UIColor.clear.cgColor
        readyObservation = playerLayer.observe(
            \AVPlayerLayer.isReadyForDisplay,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.reportReadyFrameIfNeeded()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            guard playerLayer.player !== newValue else { return }
            hasReportedReadyFrame = false
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspectFill
            reportReadyFrameIfNeeded()
        }
    }

    private func reportReadyFrameIfNeeded() {
        guard !hasReportedReadyFrame,
              playerLayer.isReadyForDisplay,
              let onReadyForDisplay else { return }
        hasReportedReadyFrame = true
        onReadyForDisplay()
    }
}

private struct MusicRoundButton: View {
    let symbol: String
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17 * scale, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44 * scale, height: 44 * scale)
                .background(.black.opacity(0.20), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: scale))
        }
        .buttonStyle(.plain)
    }
}

private struct MusicInteractiveMoodOrb: View {
    let world: MusicWorld
    let orbSize: CGFloat
    let particleReach: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var particles: [MusicMoodParticle] = []
    @State private var orbBodyParticles: [MusicOrbBodyParticle] = []
    @State private var ripples: [MusicMoodRipple] = []
    @State private var chargeProgress: CGFloat = 0
    @State private var dissolveProgress: CGFloat = 0
    @State private var isTouching = false
    @State private var isTouchingCenter = false
    @State private var touchLocation = CGPoint.zero
    @State private var touchStartedAt: TimeInterval = 0
    @State private var lastTouchUpdateAt: TimeInterval = 0
    @State private var lastTouchLocation = CGPoint.zero
    @State private var lastRippleAt: TimeInterval = 0
    @State private var fingerSpeed: CGFloat = 0
    @State private var emissionTick = 0
    @State private var emissionTask: Task<Void, Never>?
    @State private var burstTask: Task<Void, Never>?

    private var fieldSize: CGFloat {
        orbSize + particleReach * 2
    }

    private var scale: CGFloat {
        orbSize / 224
    }

    var body: some View {
        ZStack {
            orbSurface
                .frame(width: orbSize, height: orbSize)

            particleField
                .frame(width: fieldSize, height: fieldSize)
                .allowsHitTesting(false)

            Circle()
                .fill(.white.opacity(0.001))
                .frame(width: orbSize, height: orbSize)
                .contentShape(Circle())
                .gesture(orbGesture)
        }
        .frame(width: fieldSize, height: fieldSize)
        .onChange(of: world) { _, _ in
            resetInteraction(clearParticles: true)
        }
        .onChange(of: reduceMotion) { _, isEnabled in
            guard isEnabled else { return }
            resetInteraction(clearParticles: true)
        }
        .onDisappear {
            resetInteraction(clearParticles: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(world.title)动态情绪球")
        .accessibilityHint("触摸或拖动可以观察情绪粒子")
    }

    private var orbSurface: some View {
        ZStack {
            MusicHomepageEmotionOrb(world: world)
            .id(world.homepageOrbAsset)
            .transaction { transaction in
                transaction.animation = nil
            }
            .opacity(max(1 - dissolveProgress * 1.08, 0))
            .scaleEffect(1 - chargeProgress * 0.24)
            .blur(radius: dissolveProgress * 1.2 * scale)
            .animation(
                .timingCurve(0.16, 0.84, 0.24, 1, duration: isTouching ? 0.30 : 0.58),
                value: dissolveProgress
            )
            .animation(
                .timingCurve(0.22, 0.78, 0.28, 1, duration: isTouching ? 0.14 : 0.58),
                value: chargeProgress
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(reduceMotion ? 0 : 0.13),
                            Color.black.opacity(reduceMotion ? 0 : 0.035),
                            .clear
                        ],
                        center: touchGradientCenter,
                        startRadius: 0,
                        endRadius: 42 * scale
                    )
                )
                .blendMode(.multiply)
                .opacity(isTouching ? max(1 - dissolveProgress, 0) : 0)
                .animation(
                    .easeOut(duration: isTouching ? 0.08 : 0.35),
                    value: isTouching
                )
        }
    }

    private var touchGradientCenter: UnitPoint {
        UnitPoint(
            x: min(max(touchLocation.x / max(orbSize, 1), 0), 1),
            y: min(max(touchLocation.y / max(orbSize, 1), 0), 1)
        )
    }

    private var particleField: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? 1 / 15 : 1 / 60,
                paused: !isTouching
                    && particles.isEmpty
                    && orbBodyParticles.isEmpty
                    && ripples.isEmpty
            )
        ) { timeline in
            Canvas { context, _ in
                let now = timeline.date.timeIntervalSinceReferenceDate
                drawOrbBodyParticles(context: &context, at: now)
                drawParticles(context: &context, at: now)
                drawRipples(context: &context, at: now)
                drawTouchIndicator(context: &context, at: now)
            }
        }
    }

    private var orbGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                updateTouch(at: value.location)
            }
            .onEnded { _ in
                endInteraction()
            }
    }

    private func updateTouch(at location: CGPoint) {
        let now = Date().timeIntervalSinceReferenceDate
        let center = CGPoint(x: orbSize / 2, y: orbSize / 2)
        let distance = hypot(location.x - center.x, location.y - center.y)

        guard distance <= orbSize / 2 else {
            endInteraction()
            return
        }

        let touchesCenter = distance <= orbSize * 0.20
        touchLocation = location

        if !isTouching {
            beginInteraction(at: location, isCenter: touchesCenter, now: now)
            return
        }

        let elapsed = max(now - lastTouchUpdateAt, 1 / 120)
        let travelled = hypot(
            location.x - lastTouchLocation.x,
            location.y - lastTouchLocation.y
        )
        let instantaneousSpeed = travelled / elapsed
        fingerSpeed = fingerSpeed * 0.62 + instantaneousSpeed * 0.38
        lastTouchLocation = location
        lastTouchUpdateAt = now

        if touchesCenter != isTouchingCenter {
            isTouchingCenter = touchesCenter
            triggerSoftHaptic()
            if touchesCenter {
                appendCenterRipple(at: now)
            }
        }
    }

    private func beginInteraction(
        at location: CGPoint,
        isCenter: Bool,
        now: TimeInterval
    ) {
        isTouching = true
        isTouchingCenter = isCenter
        touchStartedAt = now
        lastTouchUpdateAt = now
        lastTouchLocation = location
        lastRippleAt = now
        fingerSpeed = 0
        emissionTick = 0
        triggerSoftHaptic()

        if !reduceMotion {
            beginOrbDissolve(at: now)
        }

        if isCenter {
            appendCenterRipple(at: now)
        }

        guard !reduceMotion else { return }
        startEmissionLoop()
    }

    private func startEmissionLoop() {
        emissionTask?.cancel()
        emissionTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(33))
                } catch {
                    break
                }
                guard isTouching else { break }
                emitParticles(at: Date().timeIntervalSinceReferenceDate)
            }
        }
    }

    @MainActor
    private func emitParticles(at now: TimeInterval) {
        particles.removeAll { now - $0.bornAt >= $0.lifetime }
        ripples.removeAll { now - $0.bornAt >= $0.lifetime }

        emissionTick += 1
        fingerSpeed *= 0.88

        if isTouchingCenter, now - lastRippleAt >= 1.2 {
            appendCenterRipple(at: now)
        }

        let profile = world.particleMotionProfile
        guard emissionTick % profile.emissionCadence == 0 else { return }

        let holdProgress = min(max((now - touchStartedAt) / 1.2, 0), 1)
        let speedProgress = min(fingerSpeed / max(520 * scale, 1), 1)
        let intensity = min(0.34 + holdProgress * 0.40 + speedProgress * 0.30, 1)
        let count = intensity > 0.76 ? 3 : (intensity > 0.46 ? 2 : 1)

        for _ in 0..<count {
            particles.append(makeParticle(at: now, intensity: CGFloat(intensity)))
        }

        if particles.count > 140 {
            particles.removeFirst(particles.count - 140)
        }
    }

    private func makeParticle(
        at now: TimeInterval,
        intensity: CGFloat
    ) -> MusicMoodParticle {
        let orbCenter = CGPoint(x: orbSize / 2, y: orbSize / 2)
        let touchVector = CGVector(
            dx: touchLocation.x - orbCenter.x,
            dy: touchLocation.y - orbCenter.y
        )
        let profile = world.particleMotionProfile

        let baseAngle: CGFloat
        if isTouchingCenter {
            baseAngle = .random(in: 0...(2 * .pi))
        } else {
            baseAngle = atan2(touchVector.dy, touchVector.dx)
        }
        let angle = baseAngle + CGFloat.random(in: -profile.angularSpread...profile.angularSpread)
        let generatorAngle = CGFloat.random(in: 0...(2 * .pi))
        let generatorRadius = CGFloat.random(in: (7 * scale)...(12 * scale))
        let origin = CGPoint(
            x: touchLocation.x + particleReach + cos(generatorAngle) * generatorRadius,
            y: touchLocation.y + particleReach + sin(generatorAngle) * generatorRadius
        )
        let speed = CGFloat.random(in: profile.speedRange) * scale * (0.76 + intensity * 0.24)
        let velocity = CGVector(
            dx: cos(angle) * speed,
            dy: sin(angle) * speed + profile.verticalBias * scale
        )
        let palette = world.particlePalette(at: now)
        let isFastGesture = fingerSpeed > 140 * scale

        return MusicMoodParticle(
            bornAt: now,
            lifetime: Double.random(in: 0.72...0.84),
            origin: origin,
            velocity: velocity,
            size: CGFloat.random(in: (2 * scale)...(5 * scale)),
            color: palette.randomElement() ?? .white,
            gravity: profile.gravity * scale,
            curl: profile.curl * scale,
            phase: CGFloat.random(in: 0...(2 * .pi)),
            hasLightStrand: isFastGesture && Double.random(in: 0...1) < 0.16
        )
    }

    private func appendCenterRipple(at now: TimeInterval) {
        guard !reduceMotion else { return }
        ripples.append(
            MusicMoodRipple(
                bornAt: now,
                lifetime: 0.95,
                color: world.particlePalette(at: now).first ?? .white
            )
        )
        lastRippleAt = now
    }

    private func endInteraction() {
        guard isTouching else { return }
        isTouching = false
        isTouchingCenter = false
        fingerSpeed = 0
        emissionTask?.cancel()
        emissionTask = nil
        burstTask?.cancel()
        burstTask = nil
        reformOrb()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard !isTouching else { return }
            particles.removeAll()
            ripples.removeAll()
        }
    }

    private func resetInteraction(clearParticles: Bool) {
        isTouching = false
        isTouchingCenter = false
        fingerSpeed = 0
        emissionTask?.cancel()
        emissionTask = nil
        burstTask?.cancel()
        burstTask = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            chargeProgress = 0
            dissolveProgress = 0
        }
        if clearParticles {
            particles.removeAll()
            orbBodyParticles.removeAll()
            ripples.removeAll()
        }
    }

    private func beginOrbDissolve(at now: TimeInterval) {
        if orbBodyParticles.isEmpty {
            orbBodyParticles = makeOrbBodyParticles(at: now)
        }
        burstTask?.cancel()
        dissolveProgress = 0

        withAnimation(.timingCurve(0.22, 0.78, 0.28, 1, duration: 0.14)) {
            chargeProgress = 1
        }

        burstTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(140))
            } catch {
                return
            }
            guard isTouching else { return }

            if ParentComfortRuntime.hapticsEnabled {
                let feedback = UIImpactFeedbackGenerator(style: .medium)
                feedback.prepare()
                feedback.impactOccurred(intensity: 0.72)
            }
            withAnimation(.timingCurve(0.12, 0.76, 0.18, 1, duration: 0.30)) {
                dissolveProgress = 1
            }
        }
    }

    private func reformOrb() {
        guard !reduceMotion else {
            chargeProgress = 0
            dissolveProgress = 0
            orbBodyParticles.removeAll()
            return
        }

        burstTask?.cancel()
        burstTask = nil
        withAnimation(.timingCurve(0.16, 0.88, 0.24, 1, duration: 0.58)) {
            chargeProgress = 0
            dissolveProgress = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.64) {
            guard !isTouching else { return }
            orbBodyParticles.removeAll()
        }
    }

    private func makeOrbBodyParticles(at now: TimeInterval) -> [MusicOrbBodyParticle] {
        let center = CGPoint(x: fieldSize / 2, y: fieldSize / 2)
        let palette = world.particlePalette(at: now)
        let sourceRadius = orbSize / 2 - 8 * scale

        return (0..<420).map { _ in
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let radius = sqrt(CGFloat.random(in: 0...1)) * sourceRadius
            let sourceOffset = CGVector(
                dx: cos(angle) * radius,
                dy: sin(angle) * radius
            )
            let scatterAngle = angle + CGFloat.random(in: -0.42...0.42)
            let scatterDistance = CGFloat.random(in: (38 * scale)...(72 * scale))

            return MusicOrbBodyParticle(
                origin: CGPoint(
                    x: center.x + sourceOffset.dx,
                    y: center.y + sourceOffset.dy
                ),
                scatterOffset: CGVector(
                    dx: cos(scatterAngle) * scatterDistance,
                    dy: sin(scatterAngle) * scatterDistance
                ),
                size: CGFloat.random(in: (1.6 * scale)...(5.2 * scale)),
                color: palette.randomElement() ?? .white,
                phase: CGFloat.random(in: 0...(2 * .pi))
            )
        }
    }

    private func triggerSoftHaptic() {
        guard ParentComfortRuntime.hapticsEnabled else { return }
        let feedback = UIImpactFeedbackGenerator(style: .soft)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.55)
    }

    private func drawOrbBodyParticles(
        context: inout GraphicsContext,
        at now: TimeInterval
    ) {
        guard !reduceMotion, dissolveProgress > 0, !orbBodyParticles.isEmpty else { return }
        let progress = min(max(dissolveProgress, 0), 1)
        let easedProgress = 1 - pow(1 - progress, 4)
        let center = CGPoint(x: fieldSize / 2, y: fieldSize / 2)
        let sourceScale = 1 - chargeProgress * 0.24

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            for particle in orbBodyParticles {
                let scatterLength = max(
                    hypot(particle.scatterOffset.dx, particle.scatterOffset.dy),
                    0.001
                )
                let tangent = CGVector(
                    dx: -particle.scatterOffset.dy / scatterLength,
                    dy: particle.scatterOffset.dx / scatterLength
                )
                let drift = CGFloat(sin(now * 1.8 + Double(particle.phase)))
                    * 3.2 * scale * progress
                let chargedOrigin = CGPoint(
                    x: center.x + (particle.origin.x - center.x) * sourceScale,
                    y: center.y + (particle.origin.y - center.y) * sourceScale
                )
                let point = CGPoint(
                    x: chargedOrigin.x
                        + particle.scatterOffset.dx * easedProgress
                        + tangent.dx * drift,
                    y: chargedOrigin.y
                        + particle.scatterOffset.dy * easedProgress
                        + tangent.dy * drift
                )
                let diameter = particle.size * (0.70 + progress * 0.34)
                let opacity = min(progress * 2.2, 1)
                let outerGlowRect = CGRect(
                    x: point.x - diameter * 2.45,
                    y: point.y - diameter * 2.45,
                    width: diameter * 4.9,
                    height: diameter * 4.9
                )
                layer.fill(
                    Path(ellipseIn: outerGlowRect),
                    with: .color(particle.color.opacity(opacity * 0.045))
                )
                let glowRect = CGRect(
                    x: point.x - diameter * 1.55,
                    y: point.y - diameter * 1.55,
                    width: diameter * 3.1,
                    height: diameter * 3.1
                )
                layer.fill(
                    Path(ellipseIn: glowRect),
                    with: .color(particle.color.opacity(opacity * 0.10))
                )
                let nearGlowRect = CGRect(
                    x: point.x - diameter,
                    y: point.y - diameter,
                    width: diameter * 2,
                    height: diameter * 2
                )
                layer.fill(
                    Path(ellipseIn: nearGlowRect),
                    with: .color(particle.color.opacity(opacity * 0.18))
                )
                layer.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: point.x - diameter / 2,
                            y: point.y - diameter / 2,
                            width: diameter,
                            height: diameter
                        )
                    ),
                    with: .color(particle.color.opacity(opacity * 0.82))
                )
            }
        }
    }

    private func drawParticles(
        context: inout GraphicsContext,
        at now: TimeInterval
    ) {
        guard !reduceMotion else { return }

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            for particle in particles {
                let age = now - particle.bornAt
                guard age >= 0, age < particle.lifetime else { continue }

                let elapsed = CGFloat(age)
                let progress = min(max(elapsed / CGFloat(particle.lifetime), 0), 1)
                let speed = max(hypot(particle.velocity.dx, particle.velocity.dy), 0.001)
                let perpendicular = CGVector(
                    dx: -particle.velocity.dy / speed,
                    dy: particle.velocity.dx / speed
                )
                let curlOffset = sin(progress * .pi * 2 + particle.phase)
                    * particle.curl * progress
                let point = CGPoint(
                    x: particle.origin.x
                        + particle.velocity.dx * elapsed
                        + perpendicular.dx * curlOffset,
                    y: particle.origin.y
                        + particle.velocity.dy * elapsed
                        + 0.5 * particle.gravity * elapsed * elapsed
                        + perpendicular.dy * curlOffset
                )
                let fadeIn = min(progress / 0.10, 1)
                let fadeOut = pow(max(1 - progress, 0), 1.65)
                let opacity = fadeIn * fadeOut
                let diameter = particle.size * (0.78 + (1 - progress) * 0.32)

                let outerGlowRect = CGRect(
                    x: point.x - diameter * 2.6,
                    y: point.y - diameter * 2.6,
                    width: diameter * 5.2,
                    height: diameter * 5.2
                )
                layer.fill(
                    Path(ellipseIn: outerGlowRect),
                    with: .color(particle.color.opacity(opacity * 0.055))
                )
                let glowRect = CGRect(
                    x: point.x - diameter * 1.55,
                    y: point.y - diameter * 1.55,
                    width: diameter * 3.1,
                    height: diameter * 3.1
                )
                layer.fill(
                    Path(ellipseIn: glowRect),
                    with: .color(particle.color.opacity(opacity * 0.13))
                )
                let nearGlowRect = CGRect(
                    x: point.x - diameter,
                    y: point.y - diameter,
                    width: diameter * 2,
                    height: diameter * 2
                )
                layer.fill(
                    Path(ellipseIn: nearGlowRect),
                    with: .color(particle.color.opacity(opacity * 0.22))
                )

                let coreRect = CGRect(
                    x: point.x - diameter / 2,
                    y: point.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                layer.fill(
                    Path(ellipseIn: coreRect),
                    with: .color(particle.color.opacity(opacity * 0.82))
                )

                if particle.hasLightStrand {
                    let strandLength = min(14 * scale, speed * 0.15)
                    var strand = Path()
                    strand.move(
                        to: CGPoint(
                            x: point.x - particle.velocity.dx / speed * strandLength,
                            y: point.y - particle.velocity.dy / speed * strandLength
                        )
                    )
                    strand.addLine(to: point)
                    layer.stroke(
                        strand,
                        with: .color(particle.color.opacity(opacity * 0.48)),
                        style: StrokeStyle(
                            lineWidth: max(0.8 * scale, diameter * 0.28),
                            lineCap: .round
                        )
                    )
                }
            }
        }
    }

    private func drawRipples(
        context: inout GraphicsContext,
        at now: TimeInterval
    ) {
        guard !reduceMotion else { return }
        let center = CGPoint(x: fieldSize / 2, y: fieldSize / 2)

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            for ripple in ripples {
                for delay in [0.0, 0.16] {
                    let age = now - ripple.bornAt - delay
                    guard age >= 0, age < ripple.lifetime else { continue }
                    let progress = CGFloat(age / ripple.lifetime)
                    let radius = orbSize * (0.08 + progress * 0.34)
                    let opacity = pow(max(1 - progress, 0), 1.8) * 0.52
                    let rect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    layer.stroke(
                        Path(ellipseIn: rect),
                        with: .color(ripple.color.opacity(opacity)),
                        style: StrokeStyle(
                            lineWidth: max(scale, (2.4 - progress * 1.2) * scale),
                            lineCap: .round
                        )
                    )
                }
            }
        }
    }

    private func drawTouchIndicator(
        context: inout GraphicsContext,
        at now: TimeInterval
    ) {
        guard isTouching else { return }
        let point = CGPoint(
            x: touchLocation.x + particleReach,
            y: touchLocation.y + particleReach
        )
        let pulse = reduceMotion ? 0 : CGFloat((sin(now * 5.2) + 1) / 2)
        let radius = (10 + pulse * 2) * scale
        let color = world.particlePalette(at: now).first ?? .white
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.fill(
                Path(ellipseIn: rect.insetBy(dx: -4 * scale, dy: -4 * scale)),
                with: .color(color.opacity(reduceMotion ? 0.14 : 0.10))
            )
            layer.stroke(
                Path(ellipseIn: rect),
                with: .color(color.opacity(0.56)),
                style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round)
            )
        }
    }
}

private struct MusicMoodParticle: Identifiable {
    let id = UUID()
    let bornAt: TimeInterval
    let lifetime: TimeInterval
    let origin: CGPoint
    let velocity: CGVector
    let size: CGFloat
    let color: Color
    let gravity: CGFloat
    let curl: CGFloat
    let phase: CGFloat
    let hasLightStrand: Bool
}

private struct MusicHomepageEmotionOrb: View {
    let world: MusicWorld

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let frameCount = 3

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1 / 30, paused: reduceMotion)
        ) { timeline in
            let secondsPerFrame = world.motionMood.orbFrameDuration
            let rawPhase = reduceMotion
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate / secondsPerFrame
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
        .clipped()
    }

    private func spriteFrame(_ index: Int) -> some View {
        GeometryReader { proxy in
            Image(world.homepageOrbAsset)
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

private struct MusicOrbBodyParticle: Identifiable {
    let id = UUID()
    let origin: CGPoint
    let scatterOffset: CGVector
    let size: CGFloat
    let color: Color
    let phase: CGFloat
}

private struct MusicMoodRipple: Identifiable {
    let id = UUID()
    let bornAt: TimeInterval
    let lifetime: TimeInterval
    let color: Color
}

private struct MusicParticleMotionProfile {
    let speedRange: ClosedRange<CGFloat>
    let angularSpread: CGFloat
    let gravity: CGFloat
    let curl: CGFloat
    let verticalBias: CGFloat
    let emissionCadence: Int
}

private extension MusicWorld {
    var particleMotionProfile: MusicParticleMotionProfile {
        switch self {
        case .happy:
            MusicParticleMotionProfile(
                speedRange: 42...55,
                angularSpread: 0.42,
                gravity: -5,
                curl: 4,
                verticalBias: -5,
                emissionCadence: 1
            )
        case .calm:
            MusicParticleMotionProfile(
                speedRange: 26...38,
                angularSpread: 0.56,
                gravity: -1,
                curl: 5,
                verticalBias: -2,
                emissionCadence: 2
            )
        case .low:
            MusicParticleMotionProfile(
                speedRange: 24...34,
                angularSpread: 0.30,
                gravity: 13,
                curl: 3,
                verticalBias: 6,
                emissionCadence: 2
            )
        case .angry:
            MusicParticleMotionProfile(
                speedRange: 46...60,
                angularSpread: 0.18,
                gravity: 1,
                curl: 2,
                verticalBias: 0,
                emissionCadence: 1
            )
        case .tense:
            MusicParticleMotionProfile(
                speedRange: 34...48,
                angularSpread: 0.48,
                gravity: 3,
                curl: 8,
                verticalBias: 1,
                emissionCadence: 1
            )
        }
    }

    func particlePalette(at time: TimeInterval) -> [Color] {
        let frameDuration = max(motionMood.orbFrameDuration, 0.1)
        let frame = Int(floor(time / frameDuration)) % 4

        let palettes: [[Color]]
        switch self {
        case .happy:
            palettes = [
                [Color(red: 1.00, green: 0.78, blue: 0.32), Color(red: 1.00, green: 0.52, blue: 0.60), .white],
                [Color(red: 1.00, green: 0.72, blue: 0.26), Color(red: 1.00, green: 0.86, blue: 0.48), .white],
                [Color(red: 1.00, green: 0.58, blue: 0.24), Color(red: 1.00, green: 0.81, blue: 0.46), .white],
                [Color(red: 1.00, green: 0.85, blue: 0.22), Color(red: 1.00, green: 0.61, blue: 0.46), .white]
            ]
        case .calm:
            palettes = [
                [Color(red: 0.28, green: 0.91, blue: 0.94), Color(red: 0.60, green: 0.98, blue: 0.93), .white],
                [Color(red: 0.10, green: 0.78, blue: 0.91), Color(red: 0.54, green: 0.92, blue: 0.98), .white],
                [Color(red: 0.10, green: 0.88, blue: 0.80), Color(red: 0.35, green: 0.69, blue: 0.96), .white],
                [Color(red: 0.42, green: 0.94, blue: 0.79), Color(red: 0.55, green: 0.90, blue: 0.94), .white]
            ]
        case .low:
            palettes = [
                [Color(red: 0.44, green: 0.64, blue: 0.82), Color(red: 0.65, green: 0.77, blue: 0.91), .white],
                [Color(red: 0.19, green: 0.55, blue: 0.88), Color(red: 0.18, green: 0.84, blue: 0.81), .white],
                [Color(red: 0.36, green: 0.32, blue: 0.94), Color(red: 0.33, green: 0.79, blue: 0.92), .white],
                [Color(red: 0.56, green: 0.45, blue: 0.91), Color(red: 0.69, green: 0.66, blue: 0.93), .white]
            ]
        case .angry:
            palettes = [
                [Color(red: 1.00, green: 0.91, blue: 0.38), Color(red: 1.00, green: 0.72, blue: 0.42), .white],
                [Color(red: 1.00, green: 0.82, blue: 0.16), Color(red: 1.00, green: 0.93, blue: 0.46), .white],
                [Color(red: 1.00, green: 0.86, blue: 0.26), Color(red: 1.00, green: 0.66, blue: 0.54), .white],
                [Color(red: 0.96, green: 0.92, blue: 0.72), Color(red: 1.00, green: 0.72, blue: 0.72), .white]
            ]
        case .tense:
            palettes = [
                [Color(red: 0.76, green: 0.52, blue: 0.98), Color(red: 0.43, green: 0.36, blue: 0.92), .white],
                [Color(red: 0.62, green: 0.38, blue: 0.94), Color(red: 0.31, green: 0.25, blue: 0.80), .white],
                [Color(red: 0.78, green: 0.42, blue: 0.96), Color(red: 0.96, green: 0.48, blue: 0.74), .white],
                [Color(red: 0.45, green: 0.36, blue: 0.88), Color(red: 0.92, green: 0.52, blue: 0.78), .white]
            ]
        }
        return palettes[frame]
    }
}

private struct MusicWorldOrb: View {
    let world: MusicWorld
    let level: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let bounds = CGRect(origin: .zero, size: size)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2

                context.fill(
                    Path(ellipseIn: bounds.insetBy(dx: radius * 0.035, dy: radius * 0.035)),
                    with: .radialGradient(
                        Gradient(colors: [
                            world.orbColors[0].opacity(0.96),
                            world.orbColors[1].opacity(0.76),
                            world.orbColors[2].opacity(0.88)
                        ]),
                        center: CGPoint(x: center.x * 0.72, y: center.y * 0.66),
                        startRadius: 2,
                        endRadius: radius * 1.08
                    )
                )

                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: radius * 0.16))
                    for index in 0..<4 {
                        let phase = time * (0.35 + Double(index) * 0.06) + Double(index) * 1.7
                        let orbit = radius * (0.22 + CGFloat(index) * 0.055)
                        let diameter = radius * (0.68 + CGFloat(index % 2) * 0.18 + level * 0.12)
                        let point = CGPoint(
                            x: center.x + cos(phase) * orbit,
                            y: center.y + sin(phase * 0.84) * orbit
                        )
                        let rect = CGRect(
                            x: point.x - diameter / 2,
                            y: point.y - diameter / 2,
                            width: diameter,
                            height: diameter
                        )
                        layer.fill(
                            Path(ellipseIn: rect),
                            with: .color(world.orbColors[(index + 1) % world.orbColors.count].opacity(0.48))
                        )
                    }
                }

                let highlight = CGRect(
                    x: radius * 0.30,
                    y: radius * 0.22,
                    width: radius * 0.62,
                    height: radius * 0.38
                )
                context.fill(
                    Path(ellipseIn: highlight),
                    with: .linearGradient(
                        Gradient(colors: [.white.opacity(0.72), .clear]),
                        startPoint: highlight.origin,
                        endPoint: CGPoint(x: highlight.maxX, y: highlight.maxY)
                    )
                )
            }
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.94), lineWidth: 4)
            }
            .shadow(color: world.accent.opacity(0.38), radius: 19, y: 9)
        }
        .drawingGroup(opaque: false)
    }
}

private struct MusicSpectrumWave: View {
    let world: MusicWorld
    let level: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let barCount = 54
                let spacing = size.width / CGFloat(barCount)
                let energy = CGFloat(world.energy)
                for index in 0..<barCount {
                    let envelope = 0.34 + sin(CGFloat(index) / CGFloat(barCount - 1) * .pi) * 0.66
                    let waveA = (sin(time * (3.0 + world.energy * 2.4) + Double(index) * 0.51) + 1) / 2
                    let waveB = (sin(time * 1.9 - Double(index) * 0.27) + 1) / 2
                    let motion = CGFloat(waveA * 0.70 + waveB * 0.30)
                    let height = 4 + (8 + level * 39 + energy * 8) * envelope * (0.36 + motion * 0.64)
                    let rect = CGRect(
                        x: CGFloat(index) * spacing + spacing * 0.29,
                        y: (size.height - height) / 2,
                        width: max(2, spacing * 0.42),
                        height: height
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: rect.width / 2),
                        with: .linearGradient(
                            Gradient(colors: [.white.opacity(0.96), world.accent]),
                            startPoint: CGPoint(x: rect.midX, y: rect.minY),
                            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                        )
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MusicSpeechBubble: View {
    let text: String
    let scale: CGFloat

    var body: some View {
        Text(text)
            .gardenFont(size: 12 * scale, weight: .bold)
            .foregroundStyle(Color(red: 0.05, green: 0.36, blue: 0.37))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.90), in: MusicBubbleShape())
            .shadow(color: .black.opacity(0.10), radius: 8 * scale, y: 4 * scale)
    }
}

private struct MusicBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let body = CGRect(x: 0, y: 0, width: rect.width, height: rect.height * 0.80)
        path.addRoundedRect(in: body, cornerSize: CGSize(width: 18, height: 18))
        path.move(to: CGPoint(x: rect.width * 0.80, y: rect.height * 0.76))
        path.addLine(to: CGPoint(x: rect.width * 0.91, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.77))
        path.closeSubpath()
        return path
    }
}

private struct MusicCarouselArrow: View {
    enum Direction {
        case left
        case right

        var baseAsset: String {
            self == .left
                ? "music_world_carousel_left_base"
                : "music_world_carousel_right_base"
        }

        var arrowAsset: String {
            self == .left
                ? "music_world_carousel_left_arrow"
                : "music_world_carousel_right_arrow"
        }
    }

    let direction: Direction
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(direction.baseAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 33.404 * scale, height: 33.404 * scale)
                Image(direction.arrowAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11.03 * scale, height: 15 * scale)
                    .rotationEffect(.degrees(direction == .right ? 180 : 0))
            }
                .frame(width: 52 * scale, height: 52 * scale)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction == .left ? "上一个音乐世界" : "下一个音乐世界")
    }
}

private struct MusicPaletteStrip: View {
    let colors: [UIColor]
    @Binding var selectedIndex: Int
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let motion = motionValues(at: timeline.date)

            ZStack(alignment: .trailing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8 * scale) {
                        ForEach(colors.indices, id: \.self) { index in
                            Button {
                                if ParentComfortRuntime.hapticsEnabled {
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                }
                                selectedIndex = index
                            } label: {
                                Circle()
                                    .fill(Color(uiColor: colors[index]))
                                    .overlay {
                                        Circle()
                                            .stroke(
                                                .white,
                                                lineWidth: selectedIndex == index
                                                    ? motion.ringWidth * scale
                                                    : 0
                                            )
                                    }
                                    .scaleEffect(
                                        selectedIndex == index
                                            ? motion.selectedScale
                                            : 1
                                    )
                                    .frame(width: 48 * scale, height: 48 * scale)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: 48 * scale, height: 48 * scale)
                            .accessibilityLabel("第 \(index + 1) 种颜色")
                            .accessibilityAddTraits(selectedIndex == index ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 8 * scale)
                    .frame(height: 64 * scale)
                }
                .scrollClipDisabled()

                LinearGradient(
                    colors: [.white.opacity(0), .white.opacity(0.70)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 42 * scale, height: 62 * scale)
                .allowsHitTesting(false)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13 * scale, weight: .bold))
                    .foregroundStyle(Color(red: 0.29, green: 0.52, blue: 0.53))
                    .opacity(motion.hintOpacity)
                    .offset(x: motion.hintOffset * scale)
                    .padding(.trailing, 10 * scale)
                    .allowsHitTesting(false)
            }
        }
        .background(.white.opacity(0.48), in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    Color(red: 0.29, green: 0.52, blue: 0.53).opacity(0.10),
                    lineWidth: scale
                )
        }
        .shadow(
            color: Color(red: 0.02, green: 0.28, blue: 0.30).opacity(0.12),
            radius: 18 * scale,
            y: 6 * scale
        )
        .clipShape(Capsule())
    }

    private func motionValues(at date: Date) -> (
        selectedScale: CGFloat,
        ringWidth: CGFloat,
        hintOpacity: Double,
        hintOffset: CGFloat
    ) {
        guard !reduceMotion else { return (1, 4, 0.64, 0) }
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 2)

        let pulse: CGFloat
        if phase <= 0.12 {
            pulse = easeOut(CGFloat(phase / 0.12))
        } else if phase <= 0.30 {
            pulse = 1 - easeOut(CGFloat((phase - 0.12) / 0.18))
        } else {
            pulse = 0
        }

        let hintProgress: CGFloat
        let hintOpacity: Double
        if phase <= 0.22 {
            hintProgress = easeOut(CGFloat(phase / 0.22))
            hintOpacity = 0.45 + Double(hintProgress) * 0.40
        } else if phase <= 0.50 {
            let retreat = easeOut(CGFloat((phase - 0.22) / 0.28))
            hintProgress = 1 - retreat
            hintOpacity = 0.85 - Double(retreat) * 0.21
        } else {
            hintProgress = 0
            hintOpacity = 0.64
        }

        return (
            selectedScale: 1 + pulse * 0.12,
            ringWidth: 4 + pulse * 2,
            hintOpacity: hintOpacity,
            hintOffset: hintProgress * 3
        )
    }

    private func easeOut(_ value: CGFloat) -> CGFloat {
        1 - pow(1 - min(max(value, 0), 1), 3)
    }
}

private struct MusicEntryButton: View {
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10 * scale) {
                Image("music_world_entry_palette")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 35 * scale, height: 34 * scale)
                Image("music_world_entry_arrow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28 * scale, height: 28 * scale)
            }
            .frame(width: 115 * scale, height: 48 * scale)
            .background(
                Color(red: 19 / 255, green: 92 / 255, blue: 102 / 255)
                    .opacity(0.20),
                in: Capsule()
            )
            .shadow(
                color: Color(red: 5 / 255, green: 56 / 255, blue: 61 / 255)
                    .opacity(0.18),
                radius: 16 * scale,
                y: 6 * scale
            )
            .musicGlossCapsule(scale: scale)
            .frame(width: 135 * scale, height: 68 * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("进入正念画面")
    }
}

private struct MusicArtworkEntryButton: View {
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10 * scale) {
                Image("music_artwork_action_icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 43 * scale, height: 42 * scale)
                Image("music_artwork_action_arrow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28 * scale, height: 28 * scale)
            }
            .frame(width: 115 * scale, height: 48 * scale)
            .background(
                Color(red: 19 / 255, green: 92 / 255, blue: 102 / 255).opacity(0.20),
                in: Capsule()
            )
            .shadow(
                color: Color(red: 5 / 255, green: 56 / 255, blue: 61 / 255).opacity(0.18),
                radius: 16 * scale,
                y: 6 * scale
            )
            .musicGlossCapsule(scale: scale)
            .frame(width: 135 * scale, height: 68 * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("拍照并开始情绪记录")
    }
}

private struct MusicPlaybackPill: View {
    let world: MusicWorld
    let level: CGFloat
    let isOnline: Bool
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 8 * scale) {
            AnimatedMoodOrb(asset: world.orbAsset, frameDuration: 1)
                .frame(width: 30 * scale, height: 30 * scale)

            MusicSpectrumWave(world: world, level: level)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 13 * scale)
        .background(
            Color(red: 19 / 255, green: 92 / 255, blue: 102 / 255).opacity(0.20),
            in: Capsule()
        )
    }
}

extension View {
    func musicGlossCircle(scale: CGFloat) -> some View {
        overlay {
            Circle()
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.82), location: 0),
                            .init(color: .white.opacity(0.34), location: 0.45),
                            .init(
                                color: Color(red: 124 / 255, green: 254 / 255, blue: 224 / 255)
                                    .opacity(0.30),
                                location: 1
                            )
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15 * scale
                )
                .padding(0.7 * scale)
        }
        .shadow(color: .white.opacity(0.24), radius: 2 * scale, x: -scale, y: -scale)
        .shadow(
            color: Color(red: 5 / 255, green: 56 / 255, blue: 61 / 255).opacity(0.20),
            radius: 8 * scale,
            y: 4 * scale
        )
    }

    func musicGlossCapsule(scale: CGFloat) -> some View {
        overlay {
            Capsule()
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.70), location: 0),
                            .init(color: .white.opacity(0.26), location: 0.48),
                            .init(
                                color: Color(red: 124 / 255, green: 254 / 255, blue: 224 / 255)
                                    .opacity(0.24),
                                location: 1
                            )
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1 * scale
                )
                .padding(0.7 * scale)
        }
        .shadow(color: .white.opacity(0.16), radius: 2 * scale, x: -scale, y: -scale)
    }
}

private struct MusicEmotionSymbol: View {
    let world: MusicWorld
    let scale: CGFloat

    var body: some View {
        Image(world.checkInAsset)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }
}

private struct MusicPetalBackdrop: View {
    let accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<18 {
                    let seed = Double(index) * 1.73
                    let x = CGFloat((sin(seed * 1.9) + 1) / 2) * size.width
                    let travel = (time * (7 + Double(index % 4) * 2) + seed * 90)
                        .truncatingRemainder(dividingBy: Double(size.height + 80))
                    let y = CGFloat(travel) - 40
                    let rect = CGRect(x: x, y: y, width: 10 + CGFloat(index % 3) * 4, height: 18 + CGFloat(index % 3) * 5)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(index.isMultiple(of: 2) ? accent : .white.opacity(0.74))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private final class AdaptiveMusicPlayer: NSObject, ObservableObject {
    @Published private(set) var level: CGFloat = 0.12
    @Published private(set) var isOnline = false
    @Published private(set) var recordingElapsed: TimeInterval = 0
    @Published private(set) var didReachRecordingLimit = false

    private let engine = AVAudioEngine()
    private let basePlayer = AVAudioPlayerNode()
    private let melodyPlayer = AVAudioPlayerNode()
    private let baseTimePitch = AVAudioUnitTimePitch()
    private let masterMixer = AVAudioMixerNode()
    private let colorMixer = AVAudioMixerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 1)
    private let reverb = AVAudioUnitReverb()
    private let layerPlayers = (0..<5).map { _ in AVAudioPlayerNode() }
    private let accentPlayers = (0..<6).map { _ in AVAudioPlayerNode() }
    private let sampleRate = 44_100.0
    private let maximumRecordingDuration: TimeInterval = 10 * 60
    private let recordingLock = NSLock()

    private var baseBuffers: [MusicWorld: AVAudioPCMBuffer] = [:]
    private var melodyBuffers: [MusicWorld: AVAudioPCMBuffer] = [:]
    private var layerBuffers: [AVAudioPCMBuffer] = []
    nonisolated(unsafe) private var recordingFile: AVAudioFile?
    private var recordingName: String?
    nonisolated(unsafe) private var recordedFrameCount: AVAudioFramePosition = 0
    nonisolated(unsafe) private var recordingSampleRate = 44_100.0
    private var tapFormat: AVAudioFormat?
    private var tapInstalled = false
    private var nextAccentVoice = 0
    private var activeWorld: MusicWorld?
    private var colorInfluence = 0.0
    private var beatAnchor: TimeInterval = 0
    private var pendingColorTask: Task<Void, Never>?
    private var inactivityTask: Task<Void, Never>?
    private var masterRampTask: Task<Void, Never>?
    private var layerRampTask: Task<Void, Never>?
    private var wasPlayingBeforeInterruption = false

    var hasActiveRecording: Bool {
        recordingLock.lock()
        defer { recordingLock.unlock() }
        return recordingFile != nil
    }

    override init() {
        super.init()
        guard let synthFormat else { return }

        engine.attach(basePlayer)
        engine.attach(melodyPlayer)
        engine.attach(baseTimePitch)
        engine.attach(masterMixer)
        engine.attach(colorMixer)
        engine.attach(equalizer)
        engine.attach(reverb)
        layerPlayers.forEach(engine.attach)
        accentPlayers.forEach(engine.attach)

        for player in layerPlayers {
            engine.connect(player, to: colorMixer, format: synthFormat)
        }
        for player in accentPlayers {
            engine.connect(player, to: colorMixer, format: synthFormat)
        }
        engine.connect(melodyPlayer, to: masterMixer, format: synthFormat)
        engine.connect(colorMixer, to: masterMixer, format: synthFormat)
        engine.connect(masterMixer, to: equalizer, format: synthFormat)
        engine.connect(equalizer, to: reverb, format: synthFormat)
        engine.connect(reverb, to: engine.mainMixerNode, format: synthFormat)

        let band = equalizer.bands[0]
        band.filterType = .lowPass
        band.frequency = 7_600
        band.bypass = false
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 34
        colorMixer.outputVolume = 0.82
        masterMixer.outputVolume = ParentComfortRuntime.musicVolume
    }

    func prepare() {
        // 五种情绪共用同一段基础器乐，只加载一次，避免在真机内存中重复展开 MP3。
        if let buffer = MoodMusicPlayer.preloadedBaseBuffer ?? loadBaseBuffer(for: .calm) {
            for world in MusicWorld.allCases {
                baseBuffers[world] = buffer
            }
        }
        for world in MusicWorld.allCases {
            if let buffer = makeMelodyBuffer(for: world) {
                melodyBuffers[world] = buffer
            }
        }
    }

    @discardableResult
    func play(_ world: MusicWorld) -> Bool {
        do {
            try configureAudioSession()
            if activeWorld == world, engine.isRunning {
                return true
            }

            stopNodes()
            if engine.isRunning {
                engine.stop()
            }
            guard let baseBuffer = baseBuffers[world] ?? loadBaseBuffer(for: world) else {
                return false
            }
            baseBuffers[world] = baseBuffer

            engine.disconnectNodeOutput(basePlayer)
            engine.disconnectNodeOutput(baseTimePitch)
            engine.connect(basePlayer, to: baseTimePitch, format: baseBuffer.format)
            engine.connect(baseTimePitch, to: masterMixer, format: nil)
            try installOutputTapIfNeeded()

            activeWorld = world
            colorInfluence = 0
            baseTimePitch.rate = baseRate(for: world)
            baseTimePitch.pitch = basePitch(for: world)
            basePlayer.volume = baseVolume(for: world)
            equalizer.bands[0].frequency = baseFilterFrequency(for: world)
            reverb.wetDryMix = baseReverbMix(for: world)
            // 下载的器乐曲已经自带旋律，关闭合成旋律，避免两条旋律互相打架。
            melodyPlayer.volume = 0
            guard let melodyBuffer = melodyBuffers[world] ?? makeMelodyBuffer(for: world) else {
                return false
            }
            melodyBuffers[world] = melodyBuffer
            layerBuffers = (0..<5).compactMap {
                makeLayerBuffer(family: $0, world: world)
            }
            guard layerBuffers.count == layerPlayers.count else { return false }

            basePlayer.scheduleBuffer(baseBuffer, at: nil, options: .loops)
            melodyPlayer.scheduleBuffer(melodyBuffer, at: nil, options: .loops)
            for (index, player) in layerPlayers.enumerated() {
                player.volume = 0
                player.scheduleBuffer(layerBuffers[index], at: nil, options: .loops)
            }

            engine.prepare()
            try engine.start()
            basePlayer.play()
            melodyPlayer.play()
            layerPlayers.forEach { $0.play() }
            activeWorld = world
            beatAnchor = CACurrentMediaTime()
            isOnline = false
            return true
        } catch {
            stopNodes()
            engine.stop()
            activeWorld = nil
            return false
        }
    }

    func respondToColoring(
        color: UIColor,
        regionFraction: CGFloat,
        profile: MindfulColorProfile,
        world: MusicWorld
    ) {
        beginRecordingIfNeeded()
        activeWorld = world
        colorInfluence = min(max(profile.coloredFraction / 0.70, 0), 1)
        resumeFromColoringActivity()

        pendingColorTask?.cancel()
        let delay = secondsUntilNextBeat(for: world)
        pendingColorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.applyColorProfile(profile, world: world)
            self.playAccent(
                color: color,
                regionFraction: regionFraction,
                profile: profile,
                world: world
            )
        }
        if ParentComfortRuntime.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.58)
        }
    }

    func finishRecording() -> (name: String, duration: TimeInterval)? {
        recordingLock.lock()
        let file = recordingFile
        let name = recordingName
        let frameCount = recordedFrameCount
        let sampleRate = recordingSampleRate
        recordingFile = nil
        recordingName = nil
        recordingLock.unlock()

        guard file != nil,
              let name,
              frameCount > 0 else {
            MusicSessionAudioStore.delete(name)
            return nil
        }
        let duration = Double(frameCount) / max(sampleRate, 1)
        recordingElapsed = duration
        return (name, duration)
    }

    func discardRecording() {
        recordingLock.lock()
        let name = recordingName
        recordingFile = nil
        recordingName = nil
        recordedFrameCount = 0
        recordingLock.unlock()
        MusicSessionAudioStore.delete(name)
        recordingElapsed = 0
        didReachRecordingLimit = false
    }

    func pauseForInterruption() {
        wasPlayingBeforeInterruption = engine.isRunning
        if engine.isRunning {
            engine.pause()
        }
    }

    func resumeAfterInterruption() {
        guard wasPlayingBeforeInterruption, activeWorld != nil else { return }
        do {
            try configureAudioSession()
            try engine.start()
        } catch {
            return
        }
        wasPlayingBeforeInterruption = false
    }

    func stop() {
        pendingColorTask?.cancel()
        inactivityTask?.cancel()
        masterRampTask?.cancel()
        layerRampTask?.cancel()
        discardRecording()
        stopNodes()
        engine.stop()
        activeWorld = nil
        isOnline = false
        level = 0.12
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private var synthFormat: AVAudioFormat? {
        AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )
    }

    private func baseRate(for world: MusicWorld) -> Float {
        switch world {
        case .happy: 1.08
        case .calm: 0.94
        case .low: 0.82
        case .angry: 1.12
        case .tense: 1.00
        }
    }

    private func basePitch(for world: MusicWorld) -> Float {
        switch world {
        case .happy: 3.0
        case .calm: 0
        case .low: -4.0
        case .angry: 2.0
        case .tense: -1.0
        }
    }

    private func baseVolume(for world: MusicWorld) -> Float {
        switch world {
        case .happy: 0.66
        case .calm: 0.60
        case .low: 0.56
        case .angry: 0.64
        case .tense: 0.58
        }
    }

    private func baseFilterFrequency(for world: MusicWorld) -> Float {
        switch world {
        case .happy: 9_200
        case .calm: 7_000
        case .low: 4_800
        case .angry: 10_200
        case .tense: 6_200
        }
    }

    private func baseReverbMix(for world: MusicWorld) -> Float {
        switch world {
        case .happy: 24
        case .calm: 48
        case .low: 58
        case .angry: 20
        case .tense: 42
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func loadBaseBuffer(for world: MusicWorld) -> AVAudioPCMBuffer? {
        let url = Bundle.main.url(
            forResource: world.fallbackResource,
            withExtension: "mp3"
        )
        guard let url, let file = try? AVAudioFile(forReading: url) else { return nil }
        let capacity = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: capacity
        ) else { return nil }
        do {
            try file.read(into: buffer)
            return buffer
        } catch {
            return nil
        }
    }

    private func installOutputTapIfNeeded() throws {
        guard !tapInstalled else { return }
        let output = engine.mainMixerNode
        let format = output.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "SproutlyMusic", code: 1)
        }
        tapFormat = format
        output.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: format
        ) { [weak self] buffer, _ in
            self?.processOutput(buffer)
        }
        tapInstalled = true
    }

    nonisolated private func processOutput(_ buffer: AVAudioPCMBuffer) {
        recordingLock.lock()
        if let recordingFile {
            do {
                try recordingFile.write(from: buffer)
                recordedFrameCount += AVAudioFramePosition(buffer.frameLength)
            } catch {
                // 保留已成功写入的部分；失败的缓冲区不计入创作时长。
            }
        }
        let frameCount = recordedFrameCount
        let sampleRate = recordingSampleRate
        let isRecording = recordingFile != nil
        recordingLock.unlock()

        let rms = rmsLevel(in: buffer)
        let elapsed = Double(frameCount) / max(sampleRate, 1)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.level += (min(max(CGFloat(rms) * 5.4, 0.10), 1) - self.level) * 0.28
            guard isRecording else { return }
            self.recordingElapsed = elapsed
            if elapsed >= self.maximumRecordingDuration {
                self.didReachRecordingLimit = true
            }
        }
    }

    nonisolated private func rmsLevel(in buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData,
              buffer.frameLength > 0 else { return 0.02 }
        let count = Int(buffer.frameLength)
        let strideSize = 8
        var sum: Float = 0
        var samples = 0
        for frame in Swift.stride(from: 0, to: count, by: strideSize) {
            let sample = channels[0][frame]
            sum += sample * sample
            samples += 1
        }
        return sqrt(sum / Float(max(samples, 1)))
    }

    private func beginRecordingIfNeeded() {
        guard !hasActiveRecording,
              let destination = MusicSessionAudioStore.makeRecordingURL(),
              let format = tapFormat ?? synthFormat else { return }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        do {
            let file = try AVAudioFile(
                forWriting: destination.url,
                settings: settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            recordingLock.lock()
            recordingFile = file
            recordingName = destination.name
            recordedFrameCount = 0
            recordingSampleRate = format.sampleRate
            recordingLock.unlock()
            recordingElapsed = 0
            didReachRecordingLimit = false
        } catch {
            MusicSessionAudioStore.delete(destination.name)
        }
    }

    private func secondsUntilNextBeat(for world: MusicWorld) -> TimeInterval {
        let beat = 60 / bpm(for: world)
        let elapsed = max(0, CACurrentMediaTime() - beatAnchor)
        let remainder = elapsed.truncatingRemainder(dividingBy: beat)
        return remainder < 0.035 ? 0 : beat - remainder
    }

    private func bpm(for world: MusicWorld) -> Double {
        switch world {
        case .happy: 92
        case .calm: 66
        case .low: 58
        case .angry: 100
        case .tense: 72
        }
    }

    private func resumeFromColoringActivity() {
        inactivityTask?.cancel()
        rampMasterVolume(to: ParentComfortRuntime.musicVolume, duration: 0.28)
        inactivityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.rampMasterVolume(
                to: ParentComfortRuntime.musicVolume * 0.35,
                duration: 1.1
            )
        }
    }

    private func rampMasterVolume(to target: Float, duration: TimeInterval) {
        masterRampTask?.cancel()
        let start = masterMixer.outputVolume
        let steps = max(1, Int(duration * 30))
        masterRampTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = Float(step) / Float(steps)
                let eased = 1 - pow(1 - progress, 3)
                self.masterMixer.outputVolume = start + (target - start) * eased
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func applyColorProfile(_ profile: MindfulColorProfile, world: MusicWorld) {
        let weights = colorFamilyWeights(profile)
        let influence = min(max(profile.coloredFraction / 0.70, 0), 1)
        let targets = weights.map { weight -> Float in
            guard weight > 0.005 else { return 0 }
            // 填色后颜色声部成为主角，背景音乐退到更低的层次。
            return Float(0.10 + sqrt(weight) * (0.28 + influence * 0.38))
        }
        rampLayerVolumes(to: targets)

        let warmth = profile.warmProportion - profile.coolProportion
        let brightness = profile.meanBrightness - 0.5
        let saturation = profile.meanSaturation - 0.5
        let rateDelta = influence * (
            warmth * 0.035 + brightness * 0.045 + saturation * 0.020
        )
        baseTimePitch.rate = Float(
            min(max(Double(baseRate(for: world)) + rateDelta, 0.78), 1.16)
        )
        basePlayer.volume = max(
            0.20,
            baseVolume(for: world) - Float(influence) * 0.34
        )
        melodyPlayer.volume = 0
        baseTimePitch.pitch = basePitch(for: world) + Float(
            (warmth * 0.70 + brightness * 0.35) * influence
        )
        let filterFrequency = Double(baseFilterFrequency(for: world))
            + profile.meanBrightness * 2_800
            + profile.meanSaturation * 900
        equalizer.bands[0].frequency = Float(filterFrequency)
        let reverbTarget = Double(baseReverbMix(for: world))
            + weights[2] * 10
            + weights[3] * 14
            + profile.hueDiversity * 7
        reverb.wetDryMix = Float(min(max(reverbTarget, 18), 72))
    }

    private func rampLayerVolumes(to targets: [Float]) {
        layerRampTask?.cancel()
        let starts = layerPlayers.map(\.volume)
        layerRampTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for step in 1...12 {
                guard !Task.isCancelled else { return }
                let progress = Float(step) / 12
                let eased = 1 - pow(1 - progress, 3)
                for index in self.layerPlayers.indices {
                    let target = targets.indices.contains(index) ? targets[index] : 0
                    self.layerPlayers[index].volume = starts[index] + (target - starts[index]) * eased
                }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
        }
    }

    private func colorFamilyWeights(_ profile: MindfulColorProfile) -> [Double] {
        guard profile.coloredPixels > 0 else { return Array(repeating: 0, count: 5) }
        var result = Array(repeating: 0.0, count: 5)
        for (index, pixels) in profile.hueBins.enumerated() {
            let hue = (Double(index) + 0.5) / Double(max(profile.hueBins.count, 1))
            let family: Int
            switch hue {
            case 0..<0.18, 0.96...1: family = 0
            case 0.18..<0.53: family = 1
            case 0.53..<0.68: family = 2
            case 0.68..<0.82: family = 3
            default: family = 4
            }
            result[family] += pixels / profile.coloredPixels
        }
        return result
    }

    private func playAccent(
        color: UIColor,
        regionFraction: CGFloat,
        profile: MindfulColorProfile,
        world: MusicWorld
    ) {
        guard engine.isRunning,
              let buffer = makeAccentBuffer(
                color: color,
                regionFraction: regionFraction,
                profile: profile,
                world: world
              ) else { return }
        let voice = accentPlayers[nextAccentVoice]
        nextAccentVoice = (nextAccentVoice + 1) % accentPlayers.count
        voice.stop()
        voice.volume = 0.70
        voice.scheduleBuffer(buffer)
        voice.play()
    }

    /// 基础音不再只是持续铺底：用与情绪对应的音阶生成一条很轻的八小节旋律。
    /// 旋律独立于填色声部，因此进入页面后就有完整的音乐动机，填色后仍可叠加变化。
    private func makeMelodyBuffer(for world: MusicWorld) -> AVAudioPCMBuffer? {
        guard let format = synthFormat else { return nil }
        let beatDuration = 60 / bpm(for: world)
        let notePattern: [Int]
        switch world {
        case .happy:
            notePattern = [0, 1, 2, 1, 0, 2, 3, 2, 0, 1, 2, 4, 3, 2, 1, 0]
        case .calm:
            notePattern = [0, 1, 2, 1, 0, 1, 3, 1, 0, 2, 3, 2, 1, 0, 1, 0]
        case .low:
            notePattern = [0, 1, 2, 1, 0, 2, 3, 2, 3, 2, 1, 0, 0, 1, 2, 1]
        case .angry:
            notePattern = [0, 0, 2, 3, 2, 1, 0, 1, 3, 2, 1, 0, 2, 1, 0, 0]
        case .tense:
            notePattern = [0, 1, 3, 2, 4, 2, 1, 0, 0, 2, 3, 1, 4, 3, 2, 0]
        }

        let duration = beatDuration * Double(notePattern.count)
        let capacity = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: capacity
        ), let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = capacity

        let musical = musicalIdentity(for: world)
        let amplitude: Double
        let chordPattern: [Int]
        switch world {
        case .happy:
            amplitude = 0.18
            chordPattern = [0, 3, 4, 0]
        case .calm:
            amplitude = 0.15
            chordPattern = [0, 3, 1, 0]
        case .low:
            amplitude = 0.13
            chordPattern = [0, 2, 3, 0]
        case .angry:
            amplitude = 0.16
            chordPattern = [0, 2, 3, 2]
        case .tense:
            amplitude = 0.15
            chordPattern = [0, 1, 3, 0]
        }
        let twoPi = Double.pi * 2

        for frame in 0..<Int(capacity) {
            let time = Double(frame) / sampleRate
            let noteIndex = min(Int(time / beatDuration), notePattern.count - 1)
            let noteTime = time.truncatingRemainder(dividingBy: beatDuration)
            let noteDuration = beatDuration * 0.82
            var value = 0.0
            if noteTime < noteDuration {
                let degreeIndex = notePattern[noteIndex] % musical.intervals.count
                let frequency = musical.root * pow(
                    2,
                    Double(musical.intervals[degreeIndex]) / 12
                )
                let attack = min(1, noteTime / 0.055)
                let release = pow(max(0, 1 - noteTime / noteDuration), 1.7)
                let envelope = attack * release
                let vibrato = 1 + sin(twoPi * 5.1 * time) * 0.003
                // 轻微的基频、泛音和尾音，听起来更接近柔和的钢琴/木琴，而不是单调正弦波。
                let tone = sin(twoPi * frequency * vibrato * time) * 0.78
                    + sin(twoPi * frequency * 2 * vibrato * time) * 0.16
                    + sin(twoPi * frequency * 3 * vibrato * time) * 0.06
                value += tone * envelope * amplitude
            }

            // 每四拍换一个和弦，给旋律一个干净、可循环的器乐底。
            let barDuration = beatDuration * 4
            let barIndex = min(Int(time / barDuration), chordPattern.count - 1)
            let barTime = time.truncatingRemainder(dividingBy: barDuration)
            let chordRoot = chordPattern[barIndex] % musical.intervals.count
            let chordDegrees = [
                chordRoot,
                (chordRoot + 2) % musical.intervals.count,
                (chordRoot + 4) % musical.intervals.count
            ]
            let padEnvelope = min(1, barTime / 0.28)
                * pow(max(0, 1 - barTime / barDuration), 0.55)
            for (index, degree) in chordDegrees.enumerated() {
                let chordFrequency = musical.root * 0.5 * pow(
                    2,
                    Double(musical.intervals[degree]) / 12
                )
                let partial = sin(twoPi * chordFrequency * time)
                    + sin(twoPi * chordFrequency * 2 * time) * 0.18
                value += partial * padEnvelope * (0.020 - Double(index) * 0.003)
            }

            channels[0][frame] = Float(value * 0.98)
            channels[1][frame] = Float(value)
        }
        return buffer
    }

    private func makeLayerBuffer(family: Int, world: MusicWorld) -> AVAudioPCMBuffer? {
        guard let format = synthFormat else { return nil }
        let beatDuration = 60 / bpm(for: world)
        let duration = beatDuration * 4
        let capacity = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: capacity
        ), let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = capacity

        let musical = musicalIdentity(for: world)
        let patterns = [
            [0, 2, 4, 2],
            [0, 1, 3, 1],
            [0, 2, 1, 3],
            [1, 3, 4, 2],
            [0, 4, 2, 3]
        ]
        let transpositions = [12, 0, -12, 7, 0]
        let pattern = patterns[family]
        let pan = Double(family - 2) * 0.10
        let leftGain = sqrt((1 - pan) * 0.5)
        let rightGain = sqrt((1 + pan) * 0.5)

        for frame in 0..<Int(capacity) {
            let time = Double(frame) / sampleRate
            let beatIndex = min(Int(time / beatDuration), pattern.count - 1)
            let noteTime = time.truncatingRemainder(dividingBy: beatDuration)
            let degree = musical.intervals[pattern[beatIndex] % musical.intervals.count]
                + transpositions[family]
            let frequency = musical.root * pow(2, Double(degree) / 12)
            let value = layerSample(
                family: family,
                frequency: frequency,
                time: time,
                noteTime: noteTime,
                beatDuration: beatDuration
            ) * 0.15
            channels[0][frame] = Float(value * leftGain)
            channels[1][frame] = Float(value * rightGain)
        }
        return buffer
    }

    private func layerSample(
        family: Int,
        frequency: Double,
        time: Double,
        noteTime: Double,
        beatDuration: Double
    ) -> Double {
        let twoPi = Double.pi * 2
        let attack = min(1, noteTime / 0.035)
        let release = pow(max(0, 1 - noteTime / beatDuration), family == 2 ? 0.65 : 1.7)
        let envelope = attack * release
        let fundamental = sin(twoPi * frequency * time)
        switch family {
        case 0:
            return envelope * (
                fundamental
                    + sin(twoPi * frequency * 2.01 * time) * 0.32
                    + sin(twoPi * frequency * 3.97 * time) * 0.14
            ) * exp(-noteTime * 1.15)
        case 1:
            return envelope * (
                fundamental * 0.76
                    + sin(twoPi * frequency * 2 * time) * 0.17
                    + sin(twoPi * 1.2 * time) * 0.04
            )
        case 2:
            return envelope * (
                fundamental * 0.82
                    + sin(twoPi * frequency * 0.5 * time) * 0.12
                    + sin(twoPi * frequency * 1.5 * time) * 0.08
            )
        case 3:
            return envelope * (
                fundamental * 0.68
                    + sin(twoPi * frequency * 1.5 * time) * 0.20
                    + sin(twoPi * frequency * 2.5 * time) * 0.09
            )
        default:
            return envelope * exp(-noteTime * 1.6) * (
                fundamental
                    + sin(twoPi * frequency * 2 * time) * 0.24
                    + sin(twoPi * frequency * 3 * time) * 0.08
            )
        }
    }

    private func makeAccentBuffer(
        color: UIColor,
        regionFraction: CGFloat,
        profile: MindfulColorProfile,
        world: MusicWorld
    ) -> AVAudioPCMBuffer? {
        guard let format = synthFormat else { return nil }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        _ = color.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )
        let musical = musicalIdentity(for: world)
        let degree = min(
            Int(Double(hue) * Double(musical.intervals.count)),
            musical.intervals.count - 1
        )
        let octave = regionFraction < 0.04 ? 12 : (regionFraction > 0.18 ? -12 : 0)
        let frequency = musical.root * pow(
            2,
            Double(musical.intervals[degree] + octave) / 12
        )
        let duration = 1.0 + Double(sqrt(max(regionFraction, 0.005))) * 1.8
        let capacity = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: capacity
        ), let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = capacity
        let family = familyIndex(for: Double(hue))
        let pan = (Double(hue) * 2 - 1) * 0.16
        let leftGain = sqrt((1 - pan) * 0.5)
        let rightGain = sqrt((1 + pan) * 0.5)
        for frame in 0..<Int(capacity) {
            let time = Double(frame) / sampleRate
            let attack = min(1, time / 0.025)
            let release = pow(max(0, 1 - time / duration), 2.1)
            let timbre = layerSample(
                family: family,
                frequency: frequency,
                time: time,
                noteTime: time,
                beatDuration: duration
            )
            let diversity = 0.82 + profile.hueDiversity * 0.18
            let value = tanh(timbre * diversity) * attack * release * 0.20
            channels[0][frame] = Float(value * leftGain)
            channels[1][frame] = Float(value * rightGain)
        }
        return buffer
    }

    private func familyIndex(for hue: Double) -> Int {
        switch hue {
        case 0..<0.18, 0.96...1: 0
        case 0.18..<0.53: 1
        case 0.53..<0.68: 2
        case 0.68..<0.82: 3
        default: 4
        }
    }

    private func musicalIdentity(for world: MusicWorld) -> (root: Double, intervals: [Int]) {
        switch world {
        case .happy: (261.63, [0, 4, 7, 9, 12])
        case .calm: (220.00, [0, 2, 7, 9, 12])
        case .low: (196.00, [0, 3, 5, 7, 10])
        case .angry: (146.83, [0, 3, 5, 7, 10])
        case .tense: (246.94, [0, 2, 5, 7, 11])
        }
    }

    private func stopNodes() {
        basePlayer.stop()
        melodyPlayer.stop()
        layerPlayers.forEach { $0.stop() }
        accentPlayers.forEach { $0.stop() }
    }
}

private enum MusicCameraAuthorization {
    case unknown
    case allowed
    case denied
}

private struct MusicPhotoCapture {
    let fullImage: UIImage
    let faceImage: UIImage
}

private struct MusicTrackedFace: Equatable {
    let normalizedBounds: CGRect
    let imageSize: CGSize
}

private struct MusicFaceGuideLayout: Equatable {
    let center: CGPoint
    let size: CGSize
}

private final class MusicCameraController: NSObject, ObservableObject {
    @Published private(set) var authorization: MusicCameraAuthorization = .unknown
    @Published private(set) var isFaceCentered = false
    @Published private(set) var hasFreshFrame = false
    @Published private(set) var trackedFace: MusicTrackedFace?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "sproutly.music.camera.session")
    private let outputQueue = DispatchQueue(label: "sproutly.music.camera.frames")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let frameLock = NSLock()
    private var latestImage: CGImage?
    private var latestFaceBounds: CGRect?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var captureRotationObservation: NSKeyValueObservation?
    private var configured = false
    private var frameNumber = 0
    private var smoothedFaceBounds: CGRect?
    private var missingFaceFrames = 0

    func start() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let allowed: Bool
        switch status {
        case .authorized:
            allowed = true
        case .notDetermined:
            allowed = await AVCaptureDevice.requestAccess(for: .video)
        default:
            allowed = false
        }

        clearCapturedFrame()
        await MainActor.run {
            authorization = allowed ? .allowed : .denied
            hasFreshFrame = false
            isFaceCentered = false
            trackedFace = nil
        }
        guard allowed else { return }
        configureAndStart()
    }

    func stop() {
        clearCapturedFrame()
        DispatchQueue.main.async { [weak self] in
            self?.hasFreshFrame = false
            self?.isFaceCentered = false
            self?.trackedFace = nil
        }
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func captureCurrentFrame() -> MusicPhotoCapture? {
        frameLock.lock()
        let image = latestImage
        let faceBounds = latestFaceBounds
        frameLock.unlock()
        guard let image else { return nil }

        // The data-output connection already rotates every delivered pixel buffer
        // into the coordinator's horizon-level portrait orientation.
        let orientation: UIImage.Orientation = .up
        let full = UIImage(
            cgImage: image,
            scale: 1,
            orientation: orientation
        ).normalizedForMusicPhoto(maxDimension: 1800)
        let face = cropFace(
            from: image,
            normalizedBounds: faceBounds,
            orientation: orientation
        )
        return MusicPhotoCapture(fullImage: full, faceImage: face)
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                defer { self.session.commitConfiguration() }

                guard let device = AVCaptureDevice.default(
                    .builtInWideAngleCamera,
                    for: .video,
                    position: .front
                ), let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) else { return }
                self.session.addInput(input)

                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                output.setSampleBufferDelegate(self, queue: self.outputQueue)
                guard self.session.canAddOutput(output) else { return }
                self.session.addOutput(output)
                self.videoOutput = output
                let coordinator = AVCaptureDevice.RotationCoordinator(
                    device: device,
                    previewLayer: nil
                )
                self.rotationCoordinator = coordinator
                self.captureRotationObservation = coordinator.observe(
                    \.videoRotationAngleForHorizonLevelCapture,
                    options: [.initial, .new]
                ) { [weak self] coordinator, _ in
                    guard let self else { return }
                    let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                    self.sessionQueue.async { [weak self] in
                        self?.configureOutputConnection(rotationAngle: angle)
                    }
                }
                self.configured = true
            }

            let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 0
            self.configureOutputConnection(rotationAngle: angle)
            if !self.session.isRunning {
                self.session.startRunning()
            }
            self.configureOutputConnection(rotationAngle: angle)
        }
    }

    private func configureOutputConnection(rotationAngle: CGFloat) {
        guard let connection = videoOutput?.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    private func clearCapturedFrame() {
        frameLock.lock()
        latestImage = nil
        latestFaceBounds = nil
        smoothedFaceBounds = nil
        missingFaceFrames = 0
        frameLock.unlock()
    }

    private func cropFace(
        from image: CGImage,
        normalizedBounds: CGRect?,
        orientation: UIImage.Orientation
    ) -> UIImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        var crop: CGRect
        if let bounds = normalizedBounds {
            let raw = CGRect(
                x: bounds.minX * width,
                y: (1 - bounds.maxY) * height,
                width: bounds.width * width,
                height: bounds.height * height
            )
            let side = max(raw.width, raw.height) * 1.52
            crop = CGRect(
                x: raw.midX - side / 2,
                y: raw.midY - side * 0.48,
                width: side,
                height: side
            )
        } else {
            let side = min(width, height) * 0.64
            crop = CGRect(
                x: (width - side) / 2,
                y: (height - side) / 2,
                width: side,
                height: side
            )
        }
        crop = crop.intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
        guard let cropped = image.cropping(to: crop) else {
            return UIImage(
                cgImage: image,
                scale: 1,
                orientation: orientation
            )
            .normalizedForMusicPhoto(maxDimension: 640)
            .circularMasked()
        }
        return UIImage(
            cgImage: cropped,
            scale: 1,
            orientation: orientation
        )
        .normalizedForMusicPhoto(maxDimension: 640)
        .circularMasked()
    }
}

extension MusicCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameNumber += 1
        guard frameNumber.isMultiple(of: 3),
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let image = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try? handler.perform([request])
        let face = (request.results ?? []).max { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height
                < rhs.boundingBox.width * rhs.boundingBox.height
        }?.boundingBox

        frameLock.lock()
        if let face {
            missingFaceFrames = 0
            if let previous = smoothedFaceBounds {
                let amount: CGFloat = 0.24
                smoothedFaceBounds = CGRect(
                    x: previous.origin.x + (face.origin.x - previous.origin.x) * amount,
                    y: previous.origin.y + (face.origin.y - previous.origin.y) * amount,
                    width: previous.width + (face.width - previous.width) * amount,
                    height: previous.height + (face.height - previous.height) * amount
                )
            } else {
                smoothedFaceBounds = face
            }
        } else {
            missingFaceFrames += 1
            if missingFaceFrames > 8 {
                smoothedFaceBounds = nil
            }
        }
        let trackedBounds = smoothedFaceBounds
        latestImage = cgImage
        latestFaceBounds = trackedBounds
        frameLock.unlock()

        let centered: Bool
        if let face = trackedBounds {
            let center = CGPoint(x: face.midX, y: face.midY)
            centered = abs(center.x - 0.5) < 0.17
                && abs(center.y - 0.53) < 0.20
                && face.width > 0.23
        } else {
            centered = false
        }
        DispatchQueue.main.async { [weak self] in
            self?.isFaceCentered = centered
            self?.trackedFace = trackedBounds.map {
                MusicTrackedFace(
                    normalizedBounds: $0,
                    imageSize: CGSize(width: cgImage.width, height: cgImage.height)
                )
            }
            if self?.hasFreshFrame == false {
                self?.hasFreshFrame = true
            }
        }
    }
}

private struct MusicCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> MusicPreviewView {
        let view = MusicPreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.setSession(session)
        return view
    }

    func updateUIView(_ uiView: MusicPreviewView, context: Context) {
        uiView.setSession(session)
    }
}

private final class MusicPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private weak var observedSession: AVCaptureSession?
    private weak var rotationDevice: AVCaptureDevice?
    private var sessionStartObserver: NSObjectProtocol?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?

    deinit {
        if let sessionStartObserver {
            NotificationCenter.default.removeObserver(sessionStartObserver)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        installRotationCoordinatorIfPossible()
    }

    func setSession(_ session: AVCaptureSession) {
        if observedSession !== session {
            if let sessionStartObserver {
                NotificationCenter.default.removeObserver(sessionStartObserver)
            }
            observedSession = session
            previewLayer.session = session
            sessionStartObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureSession.didStartRunningNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.installRotationCoordinatorIfPossible()
            }
        }
        installRotationCoordinatorIfPossible()
    }

    private func installRotationCoordinatorIfPossible() {
        guard let input = previewLayer.session?.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first else { return }

        if rotationDevice !== input.device {
            previewRotationObservation = nil
            let coordinator = AVCaptureDevice.RotationCoordinator(
                device: input.device,
                previewLayer: previewLayer
            )
            rotationDevice = input.device
            rotationCoordinator = coordinator
            previewRotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                self?.configurePreviewConnection(
                    rotationAngle: coordinator.videoRotationAngleForHorizonLevelPreview
                )
            }
        }

        guard let rotationCoordinator else { return }
        configurePreviewConnection(
            rotationAngle: rotationCoordinator.videoRotationAngleForHorizonLevelPreview
        )
    }

    private func configurePreviewConnection(rotationAngle: CGFloat) {
        guard let connection = previewLayer.connection else { return }
        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}

private struct CodableMusicColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ color: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.red = Double(red)
        self.green = Double(green)
        self.blue = Double(blue)
        self.alpha = Double(alpha)
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private struct CodableMusicDraft: Codable {
    let selectedArtworkIndex: Int
    let assignments: [[String: CodableMusicColor]]
}

private enum MusicColorDraftStore {
    private static let key = "sproutly.music.coloring.music313.v3"

    static func load(
        artworkCount: Int
    ) -> (selectedArtworkIndex: Int, assignments: [[UInt16: UIColor]]) {
        guard let data = UserDefaults.standard.data(forKey: key),
              let draft = try? JSONDecoder().decode(CodableMusicDraft.self, from: data) else {
            return (0, Array(repeating: [:], count: artworkCount))
        }

        var restored = Array(repeating: [UInt16: UIColor](), count: artworkCount)
        for index in 0..<min(artworkCount, draft.assignments.count) {
            for (key, color) in draft.assignments[index] {
                guard let region = UInt16(key) else { continue }
                restored[index][region] = color.uiColor
            }
        }
        return (draft.selectedArtworkIndex, restored)
    }

    static func save(
        selectedArtworkIndex: Int,
        assignments: [[UInt16: UIColor]]
    ) {
        let encoded = assignments.map { artwork in
            Dictionary(uniqueKeysWithValues: artwork.map {
                (String($0.key), CodableMusicColor($0.value))
            })
        }
        let draft = CodableMusicDraft(
            selectedArtworkIndex: selectedArtworkIndex,
            assignments: encoded
        )
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

enum MusicFaceSnapshotStore {
    static func save(_ image: UIImage) -> String? {
        guard let data = image.pngData() else { return nil }
        let name = UUID().uuidString + ".png"
        let directory = snapshotsDirectory
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(
            at: snapshotsDirectory.appendingPathComponent(name)
        )
    }

    static func load(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        return UIImage(
            contentsOfFile: snapshotsDirectory.appendingPathComponent(name).path
        )
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: snapshotsDirectory)
    }

    private static var snapshotsDirectory: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("Sproutly", isDirectory: true)
            .appendingPathComponent("FaceSnapshots", isDirectory: true)
    }
}

private extension UIImage {
    func normalizedForMusicPhoto(maxDimension: CGFloat) -> UIImage {
        let swapsAxes: Bool
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            swapsAxes = true
        default:
            swapsAxes = false
        }
        let orientedSize = swapsAxes
            ? CGSize(width: size.height, height: size.width)
            : size
        let resizeScale = min(
            1,
            maxDimension / max(orientedSize.width, orientedSize.height)
        )
        let targetSize = CGSize(
            width: max(1, orientedSize.width * resizeScale),
            height: max(1, orientedSize.height * resizeScale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: targetSize,
            format: format
        ).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func circularMasked() -> UIImage {
        let side = min(size.width, size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            UIBezierPath(ovalIn: rect).addClip()
            let source = CGRect(
                x: (side - size.width) / 2,
                y: (side - size.height) / 2,
                width: size.width,
                height: size.height
            )
            draw(in: source)
        }
    }
}
