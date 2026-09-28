import ARKit
import AVFoundation
import Combine
import ImageIO
import RealityKit
import Speech
import SwiftUI
import UIKit
import Vision

/// Figma AR-Y2～AR-Y19 的真实 AR 交互流程。
struct SproutlyARFlowView: View {
    var onTaskFlowChanged: (Bool) -> Void = { _ in }

    @EnvironmentObject private var store: GardenStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var scene = SproutlyARScene()
    @StateObject private var speech = SproutlyARSpeechRecognizer()
    @StateObject private var smileCamera = SproutlySmileCamera()
    @StateObject private var voicePlayer = SproutlyKakaVoicePlayer()

    @AppStorage("sproutly.ar.highestUnlockedTask.v2") private var highestUnlockedTask = 0
    @AppStorage("sproutly.ar.completedTasks.v2") private var completedTasks = 0
    @AppStorage("sproutly.ar.selectedTask.v2") private var savedSelectedTask = 0

    @State private var selectedTask = 0
    @State private var stage: Stage = .lobby
    @State private var panelExpanded = false
    @State private var sideControlsExpanded = false
    @State private var panelDragStart = false
    @State private var panelDragOffset: CGFloat = 0
    @State private var wrongAnswer = false
    @State private var selectedSound: Int?
    @State private var selectedExpression: Int?
    @State private var isStartingSmileCamera = false
    @State private var rewardOffset: CGSize = .zero
    @State private var rewardPlaced = false
    @State private var toast = ""
    @State private var isHoldingMic = false
    @State private var panelRevealFinished = false
    @State private var panelRevealSettled = false
    @State private var briefEntranceProgress: CGFloat = 1
    @State private var panelRevealWorkItem: DispatchWorkItem?
    @State private var automaticAdvanceWorkItem: DispatchWorkItem?
    @State private var flowerTicketSnapshot: UIImage?
    @State private var flowerTicketCapturedAt = Date()
    @State private var collectionReturnStage: Stage = .garden
    @State private var collectionPlacementKind: SproutlyARPlantKind?
    @State private var collectionPlacementOffset: CGSize = .zero
    @State private var kakaStickerPosition = CGPoint(x: 326, y: 678)
    @State private var kakaStickerDragOrigin: CGPoint?
    private let collapsedPanelTravel: CGFloat = 182

    fileprivate enum Stage: Equatable {
        case lobby
        case taskOneBrief, taskOneQuestion, taskOneCorrect, taskOneReward, taskOnePlace
        case taskTwoBrief, taskTwoQuestion, taskTwoCorrect, taskTwoReward, taskTwoPlace
        case taskThreeBrief, taskThreeMirror, taskThreeCorrect, taskThreeReward, taskThreePlace
        case garden, collection, finished
    }

    private let ink = Color(red: 0, green: 80 / 255, blue: 86 / 255)
    private let mint = Color(red: 44 / 255, green: 210 / 255, blue: 201 / 255)

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / 402, proxy.size.height / 874)
            ZStack {
                if stage == .lobby {
                    lobby(scale: scale)
                } else {
                    arWorld(scale: scale)
                }

                if !toast.isEmpty {
                    Text(toast)
                        .gardenFont(size: 14 * scale, weight: .bold)
                        .foregroundStyle(ink)
                        .padding(.horizontal, 20 * scale)
                        .frame(minHeight: 44 * scale)
                        .background(.white.opacity(0.94), in: Capsule())
                        .overlay(Capsule().stroke(.white, lineWidth: 1.5 * scale))
                        .shadow(color: .black.opacity(0.12), radius: 9 * scale, y: 4 * scale)
                        .position(x: 201 * scale, y: 82 * scale)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(20)
                }

                if let flowerTicketSnapshot {
                    SproutlyFlowerTicketFlowView(
                        snapshot: flowerTicketSnapshot,
                        plantCount: scene.placedPlantCount,
                        capturedAt: flowerTicketCapturedAt,
                        onRetake: discardFlowerTicketSnapshot,
                        onReturnToAR: returnFlowerTicketToLobby,
                        onViewTickets: openFlowerTicketAlbum
                    )
                    .transition(.opacity)
                    .zIndex(40)
                }
            }
            .frame(width: 402 * scale, height: 874 * scale)
            .coordinateSpace(name: "sproutlyARCanvas")
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .ignoresSafeArea()
        .task { await speech.requestPermissions() }
        .onAppear {
            selectedTask = min(max(savedSelectedTask, 0), 2)
            scene.resume()
            onTaskFlowChanged(true)
        }
        .onDisappear {
            panelRevealWorkItem?.cancel()
            automaticAdvanceWorkItem?.cancel()
            speech.cancel()
            voicePlayer.stop()
            isStartingSmileCamera = false
            smileCamera.stop()
            scene.pause()
            onTaskFlowChanged(false)
        }
    }

    // MARK: - AR 世界首页

    private func lobby(scale: CGFloat) -> some View {
        ZStack {
            SproutlyHomeGradient()

            Button {
                store.selectedTab = .garden
            } label: {
                Image("ar_lobby_home")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56 * scale, height: 56 * scale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回首页")
            .position(x: 48.34 * scale, y: 83.88 * scale)

            HStack(spacing: 8 * scale) {
                Image("ar_ui_title")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 55 * scale, height: 33 * scale)
                Text("第一幕·春意盎然")
                    .gardenFont(size: 16 * scale, weight: .medium)
            }
                .foregroundStyle(ink)
                .position(x: 201 * scale, y: 87 * scale)

            ZStack {
                SproutlyARContainer(scene: scene)
                    .frame(width: 338 * scale, height: 548 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 30 * scale, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                            .fill(.black.opacity(0.25))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                            .strokeBorder(.white, lineWidth: 6 * scale)
                    }
                    .offset(y: 3.7 * scale)

                Image("ar_ui_brackets")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 271 * scale, height: 438 * scale)

                Button { enterSelectedTask() } label: {
                    ZStack {
                        Image("ar_enter_world_button")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 266 * scale, height: 266 * scale)
                        Text("进入\n世界")
                            .gardenFont(size: 24 * scale, weight: .bold)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(1 * scale)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(width: 354 * scale, height: 589 * scale)
            .shadow(color: Color(red: 49/255, green: 95/255, blue: 88/255).opacity(0.18), radius: 14 * scale, y: 12 * scale)
            .position(x: 201 * scale, y: 389.5 * scale)

            taskSelector(scale: scale)
                .position(x: 201 * scale, y: 779 * scale)
        }
    }

    private func taskSelector(scale: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let unlocked = index <= highestUnlockedTask
                let selected = selectedTask == index
                let width = selected ? 108.0 : 94.0
                let height = selected ? 130.0 : 110.0

                Button {
                    guard unlocked else {
                        lockedFeedback(index: index)
                        return
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        selectedTask = index
                        savedSelectedTask = index
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: (selected ? 23 : 21) * scale, style: .continuous)
                            .fill(selectorCardColor(index))

                        if unlocked {
                            homeTaskArtwork(index: index, selected: selected, scale: scale)
                                .position(x: width * 0.5 * scale, y: (selected ? 52.5 : 40.5) * scale)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 20 * scale, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.94))
                                .position(x: width * 0.5 * scale, y: (selected ? 52.5 : 40.5) * scale)
                        }

                        Text("1-\(index + 1)")
                            .gardenFont(size: (selected ? 21 : 18) * scale, weight: .bold)
                            .foregroundStyle(selectorTextColor(index))
                            .position(x: width * 0.5 * scale, y: (selected ? 107 : 88) * scale)
                    }
                    .frame(width: width * scale, height: height * scale)
                    .overlay {
                        RoundedRectangle(cornerRadius: (selected ? 23 : 21) * scale, style: .continuous)
                            .stroke(
                                selected
                                    ? Color(red: 110/255, green: 167/255, blue: 149/255).opacity(0.98)
                                    : .white.opacity(0.76),
                                lineWidth: (selected ? 3 : 2) * scale
                            )
                    }
                    .shadow(
                        color: selected ? Color(red: 73/255, green: 125/255, blue: 112/255).opacity(0.20) : .clear,
                        radius: 7 * scale,
                        y: 6 * scale
                    )
                    .opacity(unlocked ? 1 : 0.76)
                }
                .buttonStyle(.plain)
                .position(x: [63.0, 175.0, 287.0][index] * scale, y: 77 * scale)

                Circle()
                    .fill(selected ? Color(red: 110/255, green: 167/255, blue: 149/255) : Color(red: 217/255, green: 224/255, blue: 217/255))
                    .frame(width: (selected ? 10 : 6) * scale, height: (selected ? 10 : 6) * scale)
                    .position(x: [63.0, 175.0, 287.0][index] * scale, y: (selected ? 149 : 151) * scale)
            }
        }
        .frame(width: 354 * scale, height: 158 * scale)
        .background(Color(red: 1, green: 249/255, blue: 239/255), in: RoundedRectangle(cornerRadius: 28 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28 * scale, style: .continuous).stroke(.white.opacity(0.92), lineWidth: 2 * scale))
        .shadow(color: Color(red: 66/255, green: 108/255, blue: 99/255).opacity(0.13), radius: 11 * scale, y: 8 * scale)
    }

    private func homePlantAsset(_ index: Int) -> String {
        ["ar_ui_home_peach", "ar_ui_home_begonia", "ar_ui_home_tulip"][min(max(index, 0), 2)]
    }

    @ViewBuilder
    private func homeTaskArtwork(index: Int, selected: Bool, scale: CGFloat) -> some View {
        if index == 0 {
            Image("ar_ui_home_peach")
                .resizable()
                .scaledToFit()
                .frame(width: (selected ? 100 : 86) * scale, height: 80 * scale)
        } else {
            let sourceWidth = 120 * scale
            let cropWidth = 59 * scale
            ZStack {
                Image("ar_ui_home_begonia")
                    .resizable()
                    .scaledToFill()
                    .frame(width: sourceWidth, height: 80 * scale)
                    .offset(x: index == 1 ? sourceWidth / 4 : -sourceWidth / 4)
            }
            .frame(width: cropWidth, height: 80 * scale)
            .clipped()
        }
    }

    private func selectorCardColor(_ index: Int) -> Color {
        [Color(red: 247/255, green: 228/255, blue: 233/255),
         Color(red: 244/255, green: 225/255, blue: 220/255),
         Color(red: 232/255, green: 227/255, blue: 243/255)][min(max(index, 0), 2)]
    }

    private func selectorTextColor(_ index: Int) -> Color {
        [Color(red: 53/255, green: 109/255, blue: 99/255),
         Color(red: 110/255, green: 102/255, blue: 141/255),
         Color(red: 71/255, green: 119/255, blue: 110/255)][min(max(index, 0), 2)]
    }

    // MARK: - AR-Y2～Y19

    private func arWorld(scale: CGFloat) -> some View {
        ZStack {
            // ARView 始终保留在同一视图树中。任务 1-3 只用双摄预览覆盖它，
            // 避免识别完成后重建 RealityKit 场景并重复挂载旧锚点。
            SproutlyARContainer(scene: scene)

            if showsDraggableKakaSticker {
                sceneKakaSticker(scale: scale)
            }

            if isMirrorStage {
                SproutlyMultiCamPreview(camera: smileCamera, position: .back)
            }

            Color.black.opacity(panelExpanded && isQuestionStage ? 0.25 : 0)
                .animation(.easeOut(duration: 0.2), value: panelExpanded)
                .allowsHitTesting(false)

            if stage == .garden || stage == .finished {
                gardenOverlay(scale: scale)
            } else if stage == .collection {
                collectionOverlay(scale: scale)
            } else {
                taskPanel(scale: scale)
            }

            if let collectionPlacementKind, stage != .collection, !isMirrorStage {
                collectionPlacementPreview(kind: collectionPlacementKind, scale: scale)
            }

            if showsWorldChrome {
                arSideControls(scale: scale)
            }

            if showsBottomBack {
                bottomBack(scale: scale)
            }
        }
    }

    private func sceneKakaSticker(scale: CGFloat) -> some View {
        KakaAvatarView(matchesVariantScale: true)
            .frame(width: 96 * scale, height: 96 * scale)
            .contentShape(Rectangle())
            .position(
                x: kakaStickerPosition.x * scale,
                y: kakaStickerPosition.y * scale
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("sproutlyARCanvas"))
                    .onChanged { value in
                        let origin = kakaStickerDragOrigin ?? kakaStickerPosition
                        if kakaStickerDragOrigin == nil {
                            kakaStickerDragOrigin = origin
                        }
                        kakaStickerPosition = CGPoint(
                            x: min(max(origin.x + value.translation.width / max(scale, 0.001), 48), 354),
                            y: min(max(origin.y + value.translation.height / max(scale, 0.001), 112), 812)
                        )
                    }
                    .onEnded { _ in
                        kakaStickerDragOrigin = nil
                        if ParentComfortRuntime.hapticsEnabled {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
            )
            .accessibilityHint("拖动可以调整 KAKA 贴纸的位置")
    }

    private var showsDraggableKakaSticker: Bool {
        if stage == .collection || isMirrorStage { return false }
        // 任务 1 的开始页没有说话气泡，KAKA 仍作为可拖动贴纸留在实景中。
        if stage == .taskOneBrief { return true }
        // 任务面板展开时，KAKA 由任务栏或右下角说话位统一展示，避免重复。
        return !panelExpanded
    }

    private var showsBottomBack: Bool {
        if stage == .collection { return false }
        if stage == .garden || stage == .finished { return true }
        return !panelExpanded && panelDragOffset <= 1
    }

    private var isMirrorStage: Bool {
        stage == .taskThreeMirror || stage == .taskThreeCorrect
    }

    private var isQuestionStage: Bool {
        switch stage {
        case .taskOneQuestion, .taskOneCorrect, .taskTwoQuestion, .taskTwoCorrect,
             .taskThreeMirror, .taskThreeCorrect:
            return true
        default:
            return false
        }
    }

    private var showsWorldChrome: Bool {
        if stage == .garden || stage == .finished { return true }
        if stage == .collection { return false }
        return !panelExpanded && panelDragOffset <= 1
    }

    private func taskPanel(scale: CGFloat) -> some View {
        ZStack {
            if currentBriefTask != nil {
                panelContents(scale: scale)
            } else if panelExpanded {
                if panelRevealSettled {
                    panelContents(scale: scale)
                } else {
                    segmentedPanelEntrance(scale: scale)
                }
            } else {
                collapsedPanel(scale: scale)
            }

            Color.clear
                .frame(width: 150 * scale, height: 58 * scale)
                .contentShape(Rectangle())
                .highPriorityGesture(panelGesture(scale: scale))
                .position(x: 201 * scale, y: panelHandleY * scale)
                .zIndex(30)
        }
        .frame(width: 402 * scale, height: 874 * scale)
        .onChange(of: panelExpanded) { _, expanded in
            preparePanelReveal(expanded: expanded)
        }
    }

    private func collapsedPanel(scale: CGFloat) -> some View {
        let height = 256 - collapsedPanelTravel
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: 10 * scale,
            bottomTrailingRadius: 10 * scale,
            style: .continuous
        )
        return ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    Color(red: 196/255, green: 1, blue: 249/255),
                    .white.opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 402 * scale, height: 256 * scale)
            .offset(y: (height - 256) * scale / 2)

            Capsule()
                .fill(Color(red: 217/255, green: 217/255, blue: 217/255))
                .frame(width: 96 * scale, height: 6 * scale)
                .position(x: 201 * scale, y: (245 - collapsedPanelTravel) * scale)
        }
        .frame(width: 402 * scale, height: height * scale)
        .clipShape(shape)
        .position(x: 201 * scale, y: height * scale / 2)
    }

    private func segmentedPanelEntrance(scale: CGFloat) -> some View {
        ZStack {
            panelContents(scale: scale)
                .allowsHitTesting(false)
                .mask(alignment: .top) {
                    Rectangle().frame(height: 190 * scale)
                }
                .offset(y: panelRevealFinished ? 0 : -190 * scale)

            panelContents(scale: scale)
                .allowsHitTesting(false)
                .mask {
                    Rectangle()
                        .frame(width: 402 * scale, height: 426 * scale)
                        .offset(y: -34 * scale)
                }
                .opacity(panelRevealFinished ? 1 : 0)
                .scaleEffect(panelRevealFinished ? 1 : 0.94, anchor: .center)

            panelContents(scale: scale)
                .allowsHitTesting(false)
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: 258 * scale)
                }
                .offset(y: panelRevealFinished ? 0 : 258 * scale)
        }
    }

    private var panelHandleY: CGFloat {
        if currentBriefTask != nil {
            return 245 + briefPanelOffset
        }
        guard panelExpanded else { return 245 - collapsedPanelTravel }
        switch stage {
        case .taskOneBrief, .taskTwoBrief, .taskThreeBrief:
            return 245
        case .taskOneQuestion, .taskOneCorrect, .taskTwoQuestion, .taskTwoCorrect,
             .taskThreeMirror, .taskThreeCorrect:
            return 166
        default:
            return 63
        }
    }

    private func panelGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if !panelDragStart { panelDragStart = true }
                if currentBriefTask != nil {
                    let translation = value.translation.height / max(scale, 0.001)
                    let base = panelExpanded ? CGFloat.zero : -collapsedPanelTravel
                    panelDragOffset = min(collapsedPanelTravel, max(-collapsedPanelTravel, base + translation)) - base
                    return
                }
                if value.translation.height > 44 { setPanelExpanded(true) }
                if value.translation.height < -44 { setPanelExpanded(false) }
            }
            .onEnded { value in
                panelDragStart = false
                if currentBriefTask != nil {
                    let translation = value.predictedEndTranslation.height / max(scale, 0.001)
                    if panelExpanded {
                        setPanelExpanded(translation >= -54)
                    } else {
                        setPanelExpanded(translation > 54)
                    }
                    return
                }
                if value.translation.height > 28 { setPanelExpanded(true) }
                if value.translation.height < -28 { setPanelExpanded(false) }
            }
    }

    private func setPanelExpanded(_ expanded: Bool) {
        if panelExpanded != expanded {
            panelRevealFinished = false
            panelRevealSettled = false
        }
        withAnimation(panelMotionAnimation) {
            panelExpanded = expanded
            panelDragOffset = 0
        }
    }

    private var currentBriefTask: Int? {
        switch stage {
        case .taskOneBrief: 0
        case .taskTwoBrief: 1
        case .taskThreeBrief: 2
        default: nil
        }
    }

    private var briefPanelOffset: CGFloat {
        let base = panelExpanded ? CGFloat.zero : -collapsedPanelTravel
        let interactiveOffset = min(0, max(-collapsedPanelTravel, base + panelDragOffset))
        guard panelExpanded, briefEntranceProgress < 1 else { return interactiveOffset }
        return min(interactiveOffset, -collapsedPanelTravel * (1 - briefEntranceProgress))
    }

    private var briefPanelRevealProgress: CGFloat {
        (briefPanelOffset + collapsedPanelTravel) / collapsedPanelTravel
    }

    private func preparePanelReveal(expanded: Bool) {
        panelRevealWorkItem?.cancel()
        panelRevealFinished = false
        panelRevealSettled = false
        guard expanded else { return }
        DispatchQueue.main.async {
            guard panelExpanded else { return }
            withAnimation(panelMotionAnimation) {
                panelRevealFinished = true
            }
        }
        let workItem = DispatchWorkItem {
            guard panelExpanded else { return }
            panelRevealSettled = true
        }
        panelRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + panelMotionDuration + 0.02, execute: workItem)
    }

    private var panelMotionDuration: Double {
        reduceMotion ? 0.01 : 0.34
    }

    private var panelMotionAnimation: Animation {
        reduceMotion
            ? .linear(duration: panelMotionDuration)
            : .timingCurve(0.16, 1, 0.3, 1, duration: panelMotionDuration)
    }

    @ViewBuilder
    private func panelContents(scale: CGFloat) -> some View {
        switch stage {
        case .taskOneBrief:
            briefPage(task: 0, scale: scale)
        case .taskOneQuestion, .taskOneCorrect:
            emotionQuestion(scale: scale)
        case .taskOneReward:
            rewardPage(kind: .peach, scale: scale)
        case .taskOnePlace:
            placementPage(kind: .peach, scale: scale)
        case .taskTwoBrief:
            briefPage(task: 1, scale: scale)
        case .taskTwoQuestion, .taskTwoCorrect:
            soundQuestion(scale: scale)
        case .taskTwoReward:
            rewardPage(kind: .begonia, scale: scale)
        case .taskTwoPlace:
            placementPage(kind: .begonia, scale: scale)
        case .taskThreeBrief:
            briefPage(task: 2, scale: scale)
        case .taskThreeMirror, .taskThreeCorrect:
            mirrorQuestion(scale: scale)
        case .taskThreeReward:
            rewardPage(kind: .tulip, scale: scale)
        case .taskThreePlace:
            placementPage(kind: .tulip, scale: scale)
        default:
            EmptyView()
        }
    }

    private func briefPage(task: Int, scale: CGFloat) -> some View {
        let prompt = [
            "春风来啦，桃花种子躲进了房间~\n让我们一起找一找吧！",
            "海棠花苞轻轻晃了晃，\n它想听见开心的声音。",
            "郁金香花苞像一面小镜子，\n想看看你和 KAKA 的表情。"
        ][task]
        return ZStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 196/255, green: 1, blue: 249/255), .white.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .background(.ultraThinMaterial)
                .frame(width: 402 * scale, height: 256 * scale)
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 10 * scale,
                        bottomTrailingRadius: 10 * scale,
                        style: .continuous
                    )
                )
                .position(x: 201 * scale, y: 128 * scale)

                Text("任务1-\(task + 1)")
                    .gardenFont(size: 15 * scale, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 78 * scale, height: 35 * scale)
                    .background(
                        LinearGradient(colors: [mint.opacity(0.25), Color(red: 0, green: 208/255, blue: 135/255).opacity(0.75)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                    )
                    .position(x: 59 * scale, y: 83 * scale)

                Text(prompt)
                    .gardenFont(size: 13 * scale, weight: .medium)
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2 * scale)
                    .frame(width: 224 * scale, height: 58 * scale)
                    .position(x: 167 * scale, y: 136 * scale)

                Button { beginTask(task) } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                            .fill(mint)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                                    .stroke(.white.opacity(0.62), lineWidth: 2 * scale)
                            }
                            .shadow(color: .black.opacity(0.17), radius: 10 * scale, x: -3 * scale, y: -2 * scale)
                        Image(systemName: "play.fill")
                            .font(.system(size: 23 * scale, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 75 * scale, height: 75 * scale)
                }
                .buttonStyle(.plain)
                .position(x: 341 * scale, y: 135.5 * scale)

                Capsule()
                    .fill(Color(red: 217/255, green: 217/255, blue: 217/255))
                    .frame(width: 96 * scale, height: 6 * scale)
                    .position(x: 201 * scale, y: 245 * scale)
            }
            .frame(width: 402 * scale, height: 874 * scale)
            .offset(y: briefPanelOffset * scale)

            if task != 0 {
                briefGuideBubble(task: task, scale: scale)
                    .offset(y: (1 - briefPanelRevealProgress) * 24 * scale)
                    .opacity(briefPanelRevealProgress)

                KakaAvatarView(matchesVariantScale: true)
                    .frame(width: 107 * scale, height: 107 * scale)
                    .position(x: 348.5 * scale, y: 803.5 * scale)
                    .offset(y: (1 - briefPanelRevealProgress) * 24 * scale)
                    .opacity(briefPanelRevealProgress)
            }
        }
        .frame(width: 402 * scale, height: 874 * scale)
    }

    private func briefGuideBubble(task: Int, scale: CGFloat) -> some View {
        let text = task == 1
            ? "第二阵春风来啦！\n海棠花苞想听听开心的声音。\n一起去听听吧！"
            : "海棠花找到新位置啦！\n第三阵春风正等着你。\n和家人一起进入表情镜子吧！"

        return Text(text)
            .gardenFont(size: 12 * scale, weight: .medium)
            .foregroundStyle(ink)
            .multilineTextAlignment(.center)
            .lineSpacing(0)
            .frame(width: 230 * scale, height: 59 * scale)
            .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                    .stroke(.white, lineWidth: 1.5 * scale)
            }
            .shadow(color: .black.opacity(0.10), radius: 6 * scale, y: 3 * scale)
            .position(x: 201 * scale, y: 740.5 * scale)
    }

    private func taskHeader(task: Int, scale: CGFloat) -> some View {
        HStack {
            Text("任务1-\(task + 1)")
                .gardenFont(size: 17 * scale, weight: .bold)
            Spacer()
            Text(plantKind(task).title)
                .gardenFont(size: 13 * scale, weight: .bold)
                .padding(.horizontal, 15 * scale)
                .frame(height: 34 * scale)
                .background(taskColor(task).opacity(0.62), in: Capsule())
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 30 * scale)
    }

    private func emotionQuestion(scale: CGFloat) -> some View {
        let correct = stage == .taskOneCorrect
        return ZStack {
            questionTopPanel(
                text: correct
                    ? "找到啦！\n桃花种子被春风轻轻唤醒了！"
                    : (wrongAnswer
                        ? "想想看，哪些个卡卡的嘴巴是向上翘的呢？"
                        : "春风吹进房间，\n桃花种子藏在开心的 KAKA 身边。\n你能找到开心的KAKA吗？"),
                scale: scale
            )

            kakaCloud(scale: scale)

            interactionPanel(
                pinyin: correct ? "jī ge zhǎng · zài jì xù" : "diǎn yì diǎn · shuō yì shuō",
                title: correct ? "击个掌 · 再继续" : "点一点 · 说一说",
                replacementText: correct ? nil : voiceReplacementText,
                scale: scale
            )

            SproutlyARWaveform(active: correct || isHoldingMic, color: Color(red: 0, green: 195/255, blue: 208/255))
                .frame(width: 244 * scale, height: 55 * scale)
                .position(x: 201 * scale, y: 692.5 * scale)

            holdMic(scale: scale)
                .position(x: 201 * scale, y: 779.5 * scale)
                .allowsHitTesting(!correct)

            cancelQuestionButton(scale: scale)
                .position(x: 344.5 * scale, y: 832.5 * scale)

            if correct {
                correctCheckOverlay(scale: scale)
                    .position(x: 210 * scale, y: 428 * scale)
            }
        }
        .frame(width: 402 * scale, height: 874 * scale)
    }

    private func kakaCloud(scale: CGFloat) -> some View {
        ZStack {
            kakaImage("ar_kaka_1", x: 102.5, y: 318.5, size: 107, label: "1", scale: scale)
            kakaImage("ar_kaka_2", x: 297.5, y: 313.5, size: 107, label: "2", scale: scale)
            kakaImage("ar_kaka_3", x: 221.5, y: 431.5, size: 81, label: "3", scale: scale)
            kakaImage("ar_kaka_4", x: 95.5, y: 481.5, size: 107, label: "4", scale: scale)
            kakaImage("ar_kaka_5", x: 324.5, y: 535.5, size: 107, label: "5", scale: scale)
        }
        .frame(width: 402 * scale, height: 874 * scale)
    }

    private func kakaImage(_ asset: String, x: CGFloat, y: CGFloat, size: CGFloat, label: String, scale: CGFloat) -> some View {
        ZStack {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: size * scale, height: size * scale)
            Text(label)
                .gardenFont(size: 18 * scale, weight: .bold)
                .foregroundStyle(.white)
                .offset(y: 22 * scale)
        }
            .position(x: x * scale, y: y * scale)
    }

    private func soundQuestion(scale: CGFloat) -> some View {
        let correct = stage == .taskTwoCorrect
        return ZStack {
            questionTopPanel(
                text: correct
                    ? "你们听出来啦！\n海棠花苞听见了开心的声音。\n一起来看它开花吧！"
                    : (wrongAnswer
                        ? "再听一听，\n开心的声音会轻轻向上扬哦。"
                        : "竖起小耳朵，\n开心的声音会轻轻向上扬。\n让我们听听看吧！"),
                scale: scale
            )

            soundKakaButton(index: 0, x: 102.5, y: 318.5, size: 107, iconX: 151, iconY: 281, scale: scale)
            soundKakaButton(index: 1, x: 297.5, y: 313.5, size: 107, iconX: 351, iconY: 276, scale: scale)
            soundKakaButton(index: 2, x: 221.5, y: 431.5, size: 81, iconX: 255, iconY: 393, scale: scale)
            soundKakaButton(index: 3, x: 95.5, y: 481.5, size: 107, iconX: 137, iconY: 434, scale: scale)
            soundKakaButton(index: 4, x: 324.5, y: 535.5, size: 107, iconX: 364, iconY: 492, scale: scale)

            interactionPanel(
                pinyin: correct ? "kàn yì kàn · huā kāi la" : "tīng yì tīng · xuǎn yì xuǎn",
                title: correct ? "看一看 · 花开啦" : "听一听 · 选一选",
                replacementText: correct ? nil : voiceReplacementText,
                scale: scale
            )

            SproutlyARWaveform(active: correct || selectedSound != nil || isHoldingMic, color: Color(red: 0, green: 195/255, blue: 208/255))
                .frame(width: 244 * scale, height: 55 * scale)
                .position(x: 201 * scale, y: 692.5 * scale)

            holdMic(scale: scale)
                .position(x: 201 * scale, y: 779.5 * scale)
                .allowsHitTesting(!correct)

            cancelQuestionButton(scale: scale)
                .position(x: 344.5 * scale, y: 832.5 * scale)

            if correct {
                correctCheckOverlay(scale: scale)
                    .position(x: 210 * scale, y: 428 * scale)
            }
        }
        .frame(width: 402 * scale, height: 874 * scale)
    }

    private func soundKakaButton(
        index: Int,
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        iconX: CGFloat,
        iconY: CGFloat,
        scale: CGFloat
    ) -> some View {
        Button {
            selectedSound = index
            voicePlayer.play(index: index)
        } label: {
            ZStack {
                Image("ar_kaka_5")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * scale, height: size * scale)
                Text("\(index + 1)")
                    .gardenFont(size: 18 * scale, weight: .bold)
                    .foregroundStyle(.white)
                    .offset(y: 22 * scale)
                Image(systemName: selectedSound == index ? "speaker.wave.2.circle.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 24 * scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: (iconX - x) * scale, y: (iconY - y) * scale)
            }
            .frame(width: size * scale, height: size * scale)
        }
        .buttonStyle(.plain)
        .frame(width: size * scale, height: size * scale)
        .position(x: x * scale, y: y * scale)
    }

    private func questionTopPanel(text: String, scale: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 196/255, green: 1, blue: 249/255).opacity(0.90), .white.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .background(.ultraThinMaterial)
            .frame(width: 402 * scale, height: 173 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))

            Text(text)
                .gardenFont(size: 13 * scale, weight: .medium)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .lineSpacing(1 * scale)
                .frame(width: 222 * scale, height: 68 * scale)
                .position(x: 163 * scale, y: 107 * scale)

            KakaAvatarView(matchesVariantScale: true)
                .frame(width: 107 * scale, height: 107 * scale)
                .position(x: 327.5 * scale, y: 119.5 * scale)

            Capsule()
                .fill(Color(red: 217/255, green: 217/255, blue: 217/255))
                .frame(width: 65 * scale, height: 6 * scale)
                .position(x: 197.5 * scale, y: 166 * scale)
        }
        .frame(width: 402 * scale, height: 173 * scale)
        .position(x: 201 * scale, y: 86.5 * scale)
    }

    private func interactionPanel(
        pinyin: String,
        title: String,
        replacementText: String? = nil,
        scale: CGFloat
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                .fill(Color(red: 231/255, green: 239/255, blue: 239/255).opacity(0.86))
                .background(.ultraThinMaterial)
                .frame(width: 402 * scale, height: 258 * scale)
            if let replacementText {
                Text(replacementText)
                    .gardenFont(size: 13 * scale, weight: .bold)
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 300 * scale)
                    .position(x: 201 * scale, y: 34 * scale)
            } else {
                VStack(spacing: 0) {
                    Text(pinyin)
                        .gardenFont(size: 10 * scale, weight: .medium)
                    Text(title)
                        .gardenFont(size: 13 * scale, weight: .medium)
                }
                .lineSpacing(0)
                .foregroundStyle(ink)
                .position(x: 201 * scale, y: 34 * scale)
            }
        }
        .frame(width: 402 * scale, height: 258 * scale)
        .position(x: 201 * scale, y: 745 * scale)
    }

    private func cancelQuestionButton(scale: CGFloat) -> some View {
        Button {
            setPanelExpanded(false)
        } label: {
            ZStack {
                Image("ar_ui_cancel")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 53 * scale, height: 53 * scale)
                Text("×")
                    .gardenFont(size: 26 * scale, weight: .bold)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private func mirrorQuestion(scale: CGFloat) -> some View {
        ZStack {
            questionTopPanel(
                text: selectedExpression == nil
                    ? "郁金香花苞打开了表情镜子。\n选一个开心的 KAKA，\n再学学它的表情吧！"
                    : (stage == .taskThreeCorrect ? "真棒！镜子看见你开心的笑容啦。" : "再试试，\n让嘴角轻轻向上翘一翘吧！"),
                scale: scale
            )

            expressionKakaButton(index: 0, x: 104, y: 318.5, size: 107, scale: scale)
            expressionKakaButton(index: 1, x: 238, y: 413, size: 107, scale: scale)
            expressionKakaButton(index: 2, x: 302.5, y: 236, size: 81, scale: scale)
            expressionKakaButton(index: 3, x: 53.5, y: 552.5, size: 107, scale: scale)
            expressionKakaButton(index: 4, x: 338, y: 541.5, size: 107, scale: scale)

            interactionPanel(pinyin: "xué yì xué · pāi yì pāi", title: "学一学 · 拍一拍", scale: scale)

            SproutlyMultiCamPreview(camera: smileCamera, position: .front)
                .frame(width: 353 * scale, height: 183 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
                .overlay {
                    if isStartingSmileCamera {
                        ProgressView("镜头准备中…")
                            .tint(.white)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                        .stroke(smileCamera.isSmiling ? mint : .white.opacity(0.72), lineWidth: 2 * scale)
                }
                .overlay {
                    if stage == .taskThreeCorrect {
                        ZStack {
                            Circle()
                                .fill(mint.opacity(0.86))
                                .frame(width: 142 * scale, height: 142 * scale)
                            Image(systemName: "checkmark")
                                .font(.system(size: 76 * scale, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .transition(.scale(scale: 0.72).combined(with: .opacity))
                    }
                }
                .position(x: 201.5 * scale, y: 772 * scale)
        }
        .frame(width: 402 * scale, height: 874 * scale)
        .onChange(of: smileCamera.isSmiling) { _, _ in
            completeMirrorTaskIfReady()
        }
        .onChange(of: selectedExpression) { _, _ in
            completeMirrorTaskIfReady()
        }
    }

    private func expressionKakaButton(index: Int, x: CGFloat, y: CGFloat, size: CGFloat, scale: CGFloat) -> some View {
        Button { selectedExpression = index } label: {
            ZStack {
                Image(expressionAssets[index])
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * scale, height: size * scale)
                Text("\(index + 1)")
                    .gardenFont(size: 18 * scale, weight: .bold)
                    .foregroundStyle(.white)
                    .offset(y: 22 * scale)
            }
            .overlay {
                Circle()
                    .stroke(selectedExpression == index ? mint : .clear, lineWidth: 3 * scale)
                    .padding(2 * scale)
            }
        }
        .buttonStyle(.plain)
        .frame(width: size * scale, height: size * scale)
        .position(x: x * scale, y: y * scale)
    }

    private var expressionAssets: [String] {
        ["ar_kaka_happy", "kaka_mood_calm", "kaka_mood_surprised", "kaka_mood_angry", "kaka_mood_shy"]
    }

    private func rewardPage(kind: SproutlyARPlantKind, scale: CGFloat) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    completeRewardCard(kind)
                }

            ZStack {
                RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Color(red: 254/255, green: 212/255, blue: 215/255).opacity(0.90),
                                                Color(red: 192/255, green: 251/255, blue: 1).opacity(0.90)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                SproutlyStaticPlantView(asset: kind.assetName)
                    .frame(width: 222 * scale, height: 300 * scale)
                    .offset(y: 6 * scale)
                LinearGradient(colors: [.clear, Color(red: 0, green: 195/255, blue: 208/255)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: 242 * scale, height: 96 * scale)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10 * scale, bottomTrailingRadius: 10 * scale))
                    .offset(y: 126 * scale)

                VStack(spacing: 0) {
                    Text(kind.pinyin)
                        .gardenFont(size: 14 * scale, weight: .medium)
                    Text(kind.title)
                        .gardenFont(size: 16 * scale, weight: .bold)
                }
                .foregroundStyle(.white)
                .position(x: 121 * scale, y: 27 * scale)

                Text(kind.rewardDescription)
                    .gardenFont(size: 11 * scale, weight: .medium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 218 * scale, height: 44 * scale)
                    .position(x: 121 * scale, y: 326 * scale)
            }
            .frame(width: 242 * scale, height: 348 * scale)
            .overlay(RoundedRectangle(cornerRadius: 10 * scale).stroke(.white.opacity(0.9), lineWidth: 1.5 * scale))
            .shadow(color: .black.opacity(0.12), radius: 10 * scale, y: 5 * scale)
            .position(x: 179 * scale, y: 451 * scale)

            ZStack {
                Image("ar_new_plant_badge")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 102 * scale, height: 102 * scale)
                Text("新植物！")
                    .gardenFont(size: 10 * scale, weight: .medium)
                    .foregroundStyle(ink)
                    .offset(y: 4 * scale)
            }
            .position(x: 313 * scale, y: 315 * scale)

            Button { completeRewardCard(kind) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                        .fill(.white.opacity(0.86))
                        .frame(width: 248 * scale, height: 69 * scale)
                        .overlay(RoundedRectangle(cornerRadius: 18 * scale).stroke(.white, lineWidth: 1.5 * scale))
                    VStack(spacing: 0) {
                        Text(kind.rewardPinyinLine)
                            .gardenFont(size: 10 * scale, weight: .medium)
                        Text(kind.rewardTitleLine)
                            .gardenFont(size: 12 * scale, weight: .medium)
                        Text(kind.rewardGuideLine)
                            .gardenFont(size: 10 * scale, weight: .medium)
                    }
                    .foregroundStyle(ink)
                }
            }
            .buttonStyle(.plain)
            .position(x: 201 * scale, y: 745.5 * scale)

            KakaAvatarView(matchesVariantScale: true)
                .frame(width: 107 * scale, height: 107 * scale)
                .position(x: 348.5 * scale, y: 803.5 * scale)

        }
        .frame(width: 402 * scale, height: 874 * scale)
    }

    private func placementPage(kind: SproutlyARPlantKind, scale: CGFloat) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    guard rewardPlaced else { return }
                    finishPlacement(kind)
                }

            LinearGradient(
                colors: [Color(red: 196/255, green: 1, blue: 249/255).opacity(0.72), .white.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )
            .background(.ultraThinMaterial)
            .frame(width: 402 * scale, height: 73 * scale)
            .position(x: 201 * scale, y: 36.5 * scale)

            Capsule()
                .fill(Color(red: 217/255, green: 217/255, blue: 217/255))
                .frame(width: 65 * scale, height: 6 * scale)
                .position(x: 201 * scale, y: 63 * scale)

            if !rewardPlaced {
                SproutlyGIFView(asset: kind.assetName)
                    .frame(width: 220 * scale, height: 246 * scale)
                    .offset(rewardOffset)
                    .position(x: 201 * scale, y: 500 * scale)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("sproutlyARCanvas"))
                            .onChanged { rewardOffset = $0.translation }
                            .onEnded { value in
                                rewardOffset = value.translation
                                let baseOffset = kind.previewBaselineOffset(
                                    in: CGSize(width: 220, height: 246)
                                )
                                let baseline = CGPoint(
                                    x: (201 + baseOffset.width) * scale + value.translation.width,
                                    y: (500 + baseOffset.height) * scale + value.translation.height
                                )
                                let normalizedPoint = CGPoint(
                                    x: baseline.x / (402 * scale),
                                    y: baseline.y / (874 * scale)
                                )
                                rewardPlaced = scene.place(kind: kind, normalizedPoint: normalizedPoint)
                                if rewardPlaced {
                                    if ParentComfortRuntime.hapticsEnabled {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }
                                } else {
                                    rewardOffset = .zero
                                    showToast("请移动手机识别空间后再放置")
                                }
                            }
                    )
            }

            Button {
                guard rewardPlaced else { return }
                finishPlacement(kind)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                        .fill(.white.opacity(0.86))
                        .frame(width: 248 * scale, height: 69 * scale)
                        .overlay(RoundedRectangle(cornerRadius: 18 * scale).stroke(.white, lineWidth: 1.5 * scale))
                    Text(rewardPlaced ? kind.placementSuccessLine : "把\(kind.title)拖到你喜欢的位置吧！")
                        .gardenFont(size: 12 * scale, weight: .medium)
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.center)
                        .frame(width: 214 * scale)
                }
            }
            .buttonStyle(.plain)
            .position(x: 205 * scale, y: 745.5 * scale)

            KakaAvatarView(matchesVariantScale: true)
                .frame(width: 107 * scale, height: 107 * scale)
                .position(x: 348.5 * scale, y: 803.5 * scale)

        }
        .frame(width: 402 * scale, height: 874 * scale)
    }

    private func guideBubble(_ text: String, scale: CGFloat) -> some View {
        let bubbleColor = Color(red: 224 / 255, green: 1, blue: 246 / 255)
        return HStack(spacing: 10 * scale) {
            KakaAvatarView(matchesVariantScale: true)
                .frame(width: 62 * scale, height: 62 * scale)
            Text(text)
                .gardenFont(size: 14 * scale, weight: .bold)
                .foregroundStyle(ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 15 * scale)
        .padding(.vertical, 10 * scale)
        .frame(width: 350 * scale, alignment: .leading)
        .frame(minHeight: 82 * scale)
        .background(bubbleColor, in: RoundedRectangle(cornerRadius: 22 * scale))
        .overlay(RoundedRectangle(cornerRadius: 22 * scale).stroke(.white, lineWidth: 2 * scale))
    }

    private var voiceReplacementText: String? {
        if isHoldingMic { return "正在识别…" }
        let value = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func correctCheckOverlay(scale: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(red: 0, green: 195/255, blue: 208/255).opacity(0.78))
                .frame(width: 254 * scale, height: 254 * scale)
            Image(systemName: "checkmark")
                .font(.system(size: 116 * scale, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: 254 * scale, height: 254 * scale)
        .allowsHitTesting(false)
    }

    private func holdMic(scale: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(mint)
                .frame(width: 89 * scale, height: 89 * scale)
                .overlay(Circle().stroke(.white.opacity(0.88), lineWidth: 2 * scale))
                .shadow(color: .black.opacity(0.20), radius: 5 * scale, y: 4 * scale)
            Image("ar_ui_microphone")
                .resizable()
                .scaledToFit()
                .frame(width: 48 * scale, height: 48 * scale)
        }
            .frame(width: 110 * scale, height: 110 * scale)
            .scaleEffect(isHoldingMic ? 1.06 : 1)
            .animation(.easeInOut(duration: 0.16), value: isHoldingMic)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 0.08, maximumDistance: 70 * scale, pressing: { pressing in
            if pressing && !isHoldingMic {
                isHoldingMic = speech.start()
                if isHoldingMic, ParentComfortRuntime.hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } else if !pressing && isHoldingMic {
                isHoldingMic = false
                speech.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { checkVoiceAnswer() }
            }
        }, perform: {})
        .accessibilityLabel("按住说话")
    }

    private func nextButton(
        title: String,
        enabled: Bool = true,
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9 * scale) {
                Text(title)
                    .gardenFont(size: 16 * scale, weight: .bold)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15 * scale, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: 216 * scale, height: 54 * scale)
            .background(enabled ? mint : Color.gray.opacity(0.34), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 2 * scale))
            .shadow(color: enabled ? mint.opacity(0.28) : .clear, radius: 10 * scale, y: 5 * scale)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func arSideControls(scale: CGFloat) -> some View {
        VStack(spacing: 18 * scale) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    sideControlsExpanded = false
                }
                openCollection()
            } label: {
                Image("ar_ui_side_collection")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60 * scale, height: 60 * scale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开植物收集屋")
            .opacity(sideControlsExpanded ? 1 : 0)
            .scaleEffect(sideControlsExpanded ? 1 : 0.72)
            .offset(y: sideControlsExpanded ? 0 : 156 * scale)
            .allowsHitTesting(sideControlsExpanded)

            Button {
                captureFlowerTicket()
            } label: {
                ZStack {
                    Image("ar_ui_side_sound")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60 * scale, height: 60 * scale)
                    Image("ar_ui_side_sound_glyph")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 31 * scale, height: 31 * scale)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("截取画面并生成花签")
            .opacity(sideControlsExpanded ? 1 : 0)
            .scaleEffect(sideControlsExpanded ? 1 : 0.78)
            .offset(y: sideControlsExpanded ? 0 : 78 * scale)
            .allowsHitTesting(sideControlsExpanded)

            Button {
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.14)
                        : .spring(response: 0.32, dampingFraction: 0.84)
                ) {
                    sideControlsExpanded.toggle()
                }
            } label: {
                ZStack {
                    Image("ar_ui_side_plus_base")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60 * scale, height: 60 * scale)
                        .scaleEffect(sideControlsExpanded ? 0.96 : 1)

                    Image("ar_ui_side_plus")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32 * scale, height: 32 * scale)
                        .scaleEffect(sideControlsExpanded ? 0.72 : 1)
                        .opacity(sideControlsExpanded ? 0 : 1)

                    Image("ar_ui_side_minus")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32 * scale, height: 32 * scale)
                        .scaleEffect(sideControlsExpanded ? 1 : 0.72)
                        .opacity(sideControlsExpanded ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sideControlsExpanded ? "收起快捷按钮" : "展开快捷按钮")
        }
        .position(x: 342 * scale, y: 733 * scale)
    }

    private func bottomBack(scale: CGFloat) -> some View {
        musicBackButton(scale: scale) {
            speech.cancel()
            if stage == .taskThreeBrief || stage == .taskThreeMirror || stage == .taskThreeCorrect {
                isStartingSmileCamera = false
                smileCamera.stop {
                    scene.resume()
                    transition(.lobby)
                }
            } else {
                scene.resume()
                transition(.lobby)
            }
        }
        .position(x: 48 * scale, y: 808 * scale)
    }

    private func musicBackButton(scale: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image("music_camera_back")
                .resizable()
                .scaledToFit()
                .frame(width: 48 * scale, height: 48 * scale)
                .musicGlossCircle(scale: scale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回")
    }

    private func glossySystemIcon(_ name: String, scale: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 19 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60 * scale, height: 60 * scale)
                .background(Color(red: 62/255, green: 115/255, blue: 92/255).opacity(0.56), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.82), lineWidth: 1.5 * scale))
                .shadow(color: .black.opacity(0.15), radius: 8 * scale, y: 3 * scale)
        }
        .buttonStyle(.plain)
    }

    // MARK: - AR-Y17～Y19

    private func gardenOverlay(scale: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 196/255, green: 1, blue: 249/255).opacity(0.72), .white.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )
            .background(.ultraThinMaterial)
            .frame(width: 402 * scale, height: 73 * scale)
            .position(x: 201 * scale, y: 36.5 * scale)

            Capsule()
                .fill(Color(red: 217/255, green: 217/255, blue: 217/255))
                .frame(width: 65 * scale, height: 6 * scale)
                .position(x: 201 * scale, y: 63 * scale)

            Button {
                if stage == .garden { openCollection() }
                else { transition(.lobby) }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                        .fill(.white.opacity(0.86))
                        .frame(width: 248 * scale, height: 69 * scale)
                        .overlay(RoundedRectangle(cornerRadius: 18 * scale).stroke(.white, lineWidth: 1.5 * scale))
                    Text(stage == .garden
                         ? "这里就是我们的秘密基地啦~你可以\n和植物们一起互动哦！"
                         : "春日花园完成啦！\n点击返回 AR 世界主页")
                        .gardenFont(size: 12 * scale, weight: .medium)
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.center)
                }
            }
            .buttonStyle(.plain)
            .position(x: 201 * scale, y: 657.5 * scale)
        }
        .frame(width: 402 * scale, height: 874 * scale)
    }

    private func collectionOverlay(scale: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 232/255, green: 247/255, blue: 240/255).opacity(0.76), location: 0),
                            .init(color: Color(red: 214/255, green: 235/255, blue: 224/255).opacity(0.40), location: 0.52),
                            .init(color: Color(red: 33/255, green: 69/255, blue: 56/255).opacity(0.48), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(.ultraThinMaterial)
                .frame(width: 402 * scale, height: 874 * scale)
                .position(x: 201 * scale, y: 437 * scale)
                .contentShape(Rectangle())

            RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                .fill(.white.opacity(0.75))
                .frame(width: 354 * scale, height: 780 * scale)
                .position(x: 201 * scale, y: 450 * scale)

            Text("植物收集屋")
                .gardenFont(size: 16 * scale, weight: .bold)
                .foregroundStyle(.white)
                .frame(width: 136 * scale, height: 29 * scale)
                .background(mint, in: Capsule())
                .shadow(color: mint.opacity(0.35), radius: 4 * scale, y: 3 * scale)
                .position(x: 201 * scale, y: 86.5 * scale)

            Button { closeCollection() } label: {
                Image("ar_collection_close")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24 * scale, height: 24 * scale)
            }
            .buttonStyle(.plain)
            .position(x: 358 * scale, y: 81 * scale)
            .accessibilityLabel("关闭植物收集屋")

            KakaAvatarView(matchesVariantScale: true)
                .frame(width: 107 * scale, height: 107 * scale)
                .position(x: 321.5 * scale, y: 127.5 * scale)
                .allowsHitTesting(false)

            Text("这里收集着所有我们拥有的植物，你可以选择\n自己喜欢的花放置在自己的世界里~")
                .gardenFont(size: 10 * scale, weight: .medium)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .lineSpacing(4 * scale)
                .frame(width: 214 * scale, height: 29 * scale)
                .position(x: 152 * scale, y: 137.5 * scale)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [
                        GridItem(.fixed(159 * scale), spacing: 16 * scale),
                        GridItem(.fixed(159 * scale))
                    ],
                    spacing: 10 * scale
                ) {
                    ForEach(collectionPlants, id: \.self) { kind in
                        collectionCard(kind: kind, scale: scale)
                    }
                }
                .padding(.bottom, 12 * scale)
            }
            .frame(width: 334 * scale, height: 651 * scale)
            .position(x: 201 * scale, y: 502.5 * scale)
        }
        .frame(width: 402 * scale, height: 874 * scale)
    }

    private var collectionPlants: [SproutlyARPlantKind] {
        let earned = [SproutlyARPlantKind.peach, .begonia, .tulip]
            .filter { completedTasks & (1 << $0.index) != 0 }
            .sorted { $0.index < $1.index }
        return [.lotus, .narcissus, .wisteria, .peony, .sunflower, .camellia] + earned
    }

    private func collectionCard(kind: SproutlyARPlantKind, scale: CGFloat) -> some View {
        Button { beginCollectionPlacement(kind) } label: {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 254/255, green: 212/255, blue: 215/255),
                        Color(red: 192/255, green: 251/255, blue: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                collectionPlantPreview(kind: kind, scale: scale)

                LinearGradient(
                    colors: [.clear, Color(red: 24/255, green: 87/255, blue: 90/255).opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 159 * scale, height: 63 * scale)
                .position(x: 79.5 * scale, y: 196.5 * scale)

                VStack(spacing: 0) {
                    Text(kind.pinyin)
                        .gardenFont(size: 10 * scale, weight: .medium)
                    Text(kind.collectionTitle)
                        .gardenFont(size: 16 * scale, weight: .medium)
                }
                .foregroundStyle(.white)
                .position(x: 79.5 * scale, y: 25 * scale)

                Text(kind.collectionCardDescription)
                    .gardenFont(size: 8 * scale, weight: .medium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4 * scale)
                    .frame(width: 145 * scale, height: 31 * scale)
                    .position(x: 79.5 * scale, y: 209.5 * scale)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 159 * scale, height: 228 * scale)
        .contentShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                .stroke(.white.opacity(0.88), lineWidth: 1.2 * scale)
        }
        .shadow(color: .black.opacity(0.09), radius: 10.2 * scale, x: -3 * scale, y: -2 * scale)
        .shadow(color: .black.opacity(0.25), radius: 4 * scale, y: 4 * scale)
        .accessibilityLabel("选择\(kind.title)并放入AR场景")
    }

    @ViewBuilder
    private func collectionPlantPreview(kind: SproutlyARPlantKind, scale: CGFloat) -> some View {
        let layout = kind.collectionPreviewLayout

        if let assetName = kind.collectionStaticAssetName {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .frame(width: layout.size.width * scale, height: layout.size.height * scale)
                .clipped()
                .position(x: layout.center.x * scale, y: layout.center.y * scale)
        } else {
            SproutlyStaticPlantView(asset: kind.assetName)
                .frame(width: layout.size.width * scale, height: layout.size.height * scale)
                .position(x: layout.center.x * scale, y: layout.center.y * scale)
        }
    }

    private func collectionPlacementPreview(kind: SproutlyARPlantKind, scale: CGFloat) -> some View {
        SproutlyGIFView(asset: kind.assetName)
            .frame(width: 220 * scale, height: 246 * scale)
            .offset(collectionPlacementOffset)
            .position(x: 201 * scale, y: 500 * scale)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("sproutlyARCanvas"))
                    .onChanged { collectionPlacementOffset = $0.translation }
                    .onEnded { value in
                        collectionPlacementOffset = value.translation
                        let baseOffset = kind.previewBaselineOffset(
                            in: CGSize(width: 220, height: 246)
                        )
                        let baseline = CGPoint(
                            x: (201 + baseOffset.width) * scale + value.translation.width,
                            y: (500 + baseOffset.height) * scale + value.translation.height
                        )
                        let normalizedPoint = CGPoint(
                            x: baseline.x / (402 * scale),
                            y: baseline.y / (874 * scale)
                        )
                        if scene.place(kind: kind, normalizedPoint: normalizedPoint) {
                            collectionPlacementKind = nil
                            collectionPlacementOffset = .zero
                            if ParentComfortRuntime.hapticsEnabled {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                            showToast("\(kind.title)已经放进场景啦")
                        } else {
                            collectionPlacementOffset = .zero
                            showToast("请移动手机识别空间后再放置")
                        }
                    }
            )
            .zIndex(18)
    }

    // MARK: - State

    private func openCollection() {
        collectionReturnStage = stage == .collection ? collectionReturnStage : stage
        collectionPlacementKind = nil
        collectionPlacementOffset = .zero
        speech.cancel()
        isHoldingMic = false
        stage = .collection
    }

    private func closeCollection() {
        collectionPlacementKind = nil
        collectionPlacementOffset = .zero
        stage = collectionReturnStage
    }

    private func beginCollectionPlacement(_ kind: SproutlyARPlantKind) {
        collectionPlacementKind = kind
        collectionPlacementOffset = .zero
        stage = collectionReturnStage
        if stage != .garden && stage != .finished {
            setPanelExpanded(false)
        }
        showToast("拖动\(kind.title)放到你喜欢的位置")
    }

    private func enterSelectedTask() {
        guard selectedTask <= highestUnlockedTask else {
            lockedFeedback(index: selectedTask)
            return
        }
        if selectedTask == 0 {
            scene.resetPlants()
            transition(.taskOneBrief, expanded: false)
        } else if selectedTask == 1 {
            transition(.taskTwoBrief, expanded: false)
        } else {
            transition(.taskThreeBrief, expanded: false)
        }
    }

    private func beginTask(_ task: Int) {
        wrongAnswer = false
        if task == 0 { transition(.taskOneQuestion) }
        if task == 1 { transition(.taskTwoQuestion) }
        if task == 2 {
            guard !isStartingSmileCamera else { return }
            isStartingSmileCamera = true
            scene.pause()
            transition(.taskThreeMirror)
            smileCamera.start { started in
                guard isStartingSmileCamera, stage == .taskThreeMirror else {
                    if started { smileCamera.stop() }
                    return
                }
                isStartingSmileCamera = false
                guard started else {
                    scene.resume()
                    transition(.taskThreeBrief)
                    showToast("前置摄像头暂时无法开启，请再试一次")
                    return
                }
            }
        }
    }

    private func completeMirrorTaskIfReady() {
        guard stage == .taskThreeMirror,
              selectedExpression == 0,
              smileCamera.isSmiling else { return }

        if ParentComfortRuntime.hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        transition(.taskThreeCorrect)

        let workItem = DispatchWorkItem {
            guard stage == .taskThreeCorrect else { return }
            smileCamera.stop {
                guard stage == .taskThreeCorrect else { return }
                scene.resume()
                transition(.taskThreeReward)
            }
        }
        automaticAdvanceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func checkVoiceAnswer() {
        guard stage == .taskOneQuestion || stage == .taskTwoQuestion else { return }
        let normalized = speech.transcript
            .replacingOccurrences(of: "四", with: "4")
            .replacingOccurrences(of: "五", with: "5")
        let isCorrect = stage == .taskOneQuestion
            ? normalized.contains("4") || normalized.contains("5")
            : normalized.contains("5")
        if isCorrect {
            wrongAnswer = false
            if stage == .taskOneQuestion {
                transition(.taskOneCorrect)
                scheduleAutomaticAdvance(from: .taskOneCorrect, to: .taskOneReward)
            } else {
                transition(.taskTwoCorrect)
                scheduleAutomaticAdvance(from: .taskTwoCorrect, to: .taskTwoReward)
            }
        } else {
            wrongAnswer = true
            if ParentComfortRuntime.hapticsEnabled {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
    }

    private func scheduleAutomaticAdvance(from source: Stage, to destination: Stage) {
        automaticAdvanceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            guard stage == source else { return }
            transition(destination)
        }
        automaticAdvanceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: workItem)
    }

    private func finishPlacement(_ kind: SproutlyARPlantKind) {
        completedTasks |= (1 << kind.index)
        if kind.index < 2 {
            highestUnlockedTask = max(highestUnlockedTask, kind.index + 1)
            selectedTask = kind.index + 1
            savedSelectedTask = selectedTask
            transition(kind.index == 0 ? .taskTwoBrief : .taskThreeBrief, expanded: true)
        } else {
            highestUnlockedTask = 2
            selectedTask = 2
            savedSelectedTask = 2
            transition(.garden)
        }
    }

    private func completeRewardCard(_ kind: SproutlyARPlantKind) {
        transition(kind.placeStage)
    }

    private func transition(_ destination: Stage, expanded: Bool? = nil) {
        let source = stage
        let shouldRevealQuestion = isBriefStage(source) && isQuestionEntryStage(destination)
        automaticAdvanceWorkItem?.cancel()
        speech.cancel()
        voicePlayer.stop()
        isHoldingMic = false
        if destination == .lobby {
            collectionPlacementKind = nil
            collectionPlacementOffset = .zero
        }
        rewardOffset = .zero
        rewardPlaced = false
        panelDragOffset = 0
        if shouldRevealQuestion {
            panelRevealWorkItem?.cancel()
            panelRevealFinished = false
            panelRevealSettled = false
        }
        selectedSound = destination == .taskTwoQuestion ? nil : selectedSound
        selectedExpression = destination == .taskThreeMirror ? nil : selectedExpression
        stage = destination

        let desiredExpansion: Bool?
        if let expanded {
            desiredExpansion = expanded
        } else if destination != .lobby && destination != .garden && destination != .collection && destination != .finished {
            desiredExpansion = true
        } else {
            desiredExpansion = nil
        }
        let shouldRevealBrief = isBriefStage(destination) && desiredExpansion == true
        briefEntranceProgress = shouldRevealBrief ? 0 : 1
        if let desiredExpansion, panelExpanded != desiredExpansion {
            setPanelExpanded(desiredExpansion)
        }
        if shouldRevealBrief {
            DispatchQueue.main.async {
                guard isBriefStage(stage), panelExpanded else { return }
                withAnimation(panelMotionAnimation) {
                    briefEntranceProgress = 1
                }
            }
        }
        if shouldRevealQuestion {
            preparePanelReveal(expanded: true)
        }
        if destination == .taskThreeBrief && source != .taskThreeBrief {
            // 先呈现说明页，再配置双摄；此时仍不启动镜头，后置 AR 保持显示。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard stage == .taskThreeBrief else { return }
                smileCamera.prepare()
            }
        }
    }

    private func isBriefStage(_ value: Stage) -> Bool {
        value == .taskOneBrief || value == .taskTwoBrief || value == .taskThreeBrief
    }

    private func isQuestionEntryStage(_ value: Stage) -> Bool {
        value == .taskOneQuestion || value == .taskTwoQuestion || value == .taskThreeMirror
    }

    private func lockedFeedback(index: Int) {
        if ParentComfortRuntime.hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        showToast("先完成任务1-\(index)，才能解锁这里哦")
    }

    private func showToast(_ value: String) {
        withAnimation { toast = value }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toast == value { withAnimation { toast = "" } }
        }
    }

    private func captureFlowerTicket() {
        guard scene.placedPlantCount > 0 else {
            if ParentComfortRuntime.hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
            showToast("请先在实景中放置至少一株植物")
            return
        }
        sideControlsExpanded = false
        scene.captureSnapshot { image in
            DispatchQueue.main.async {
                guard let image else {
                    showToast("暂时无法截取画面，请稍后重试")
                    return
                }
                flowerTicketCapturedAt = Date()
                flowerTicketSnapshot = image
                scene.pause()
                if ParentComfortRuntime.hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
    }

    private func discardFlowerTicketSnapshot() {
        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.2)) {
            flowerTicketSnapshot = nil
        }
        scene.resume()
    }

    private func returnFlowerTicketToLobby() {
        flowerTicketSnapshot = nil
        sideControlsExpanded = false
        scene.resume()
        transition(.lobby)
    }

    private func openFlowerTicketAlbum() {
        flowerTicketSnapshot = nil
        store.requestedProfilePage = 3
        store.selectedTab = .profile
    }

    private func plantKind(_ index: Int) -> SproutlyARPlantKind {
        SproutlyARPlantKind(rawValue: min(max(index, 0), 2)) ?? .peach
    }

    private func taskColor(_ index: Int) -> Color {
        [Color(red: 1, green: 0.77, blue: 0.79),
         Color(red: 1, green: 0.69, blue: 0.49),
         Color(red: 0.98, green: 0.86, blue: 0.39)][min(max(index, 0), 2)]
    }

    private func placementButtonTitle(_ kind: SproutlyARPlantKind) -> String {
        kind == .tulip ? "看看我的花园" : "进入任务1-\(kind.index + 2)"
    }

    private func previousBrief(for kind: SproutlyARPlantKind) -> Stage {
        switch kind {
        case .peach: .taskOneBrief
        case .begonia: .taskTwoBrief
        case .tulip: .taskThreeBrief
        case .lotus, .narcissus, .wisteria, .peony, .sunflower, .camellia: .taskOneBrief
        }
    }
}

private extension SproutlyARPlantKind {
    var placeStage: SproutlyARFlowView.Stage {
        switch self {
        case .peach: .taskOnePlace
        case .begonia: .taskTwoPlace
        case .tulip: .taskThreePlace
        case .lotus, .narcissus, .wisteria, .peony, .sunflower, .camellia: .garden
        }
    }

    var rewardStage: SproutlyARFlowView.Stage {
        switch self {
        case .peach: .taskOneReward
        case .begonia: .taskTwoReward
        case .tulip: .taskThreeReward
        case .lotus, .narcissus, .wisteria, .peony, .sunflower, .camellia: .garden
        }
    }
}

// MARK: - Plant animation resources

private enum SproutlyARPlantKind: Int, CaseIterable, Hashable {
    case peach = 0
    case begonia = 1
    case tulip = 2
    case lotus = 3
    case narcissus = 4
    case wisteria = 5
    case peony = 6
    case sunflower = 7
    case camellia = 8

    var index: Int { rawValue }

    var title: String {
        switch self {
        case .peach: "桃花"
        case .begonia: "海棠花"
        case .tulip: "郁金香"
        case .lotus: "荷花"
        case .narcissus: "水仙"
        case .wisteria: "紫藤"
        case .peony: "牡丹花"
        case .sunflower: "向日葵"
        case .camellia: "山茶花"
        }
    }

    var collectionTitle: String {
        switch self {
        case .peach: "桃 花"
        case .begonia: "海 棠 花"
        case .tulip: "郁 金 香"
        case .lotus: "荷 花"
        case .narcissus: "水 仙"
        case .wisteria: "紫 藤"
        case .peony: "牡 丹 花"
        case .sunflower: "向 日 葵"
        case .camellia: "山 茶 花"
        }
    }

    var pinyin: String {
        switch self {
        case .peach: "táo huā"
        case .begonia: "hǎi táng huā"
        case .tulip: "yù jīn xiāng"
        case .lotus: "hé huā"
        case .narcissus: "shuǐ xiān"
        case .wisteria: "zǐ ténɡ"
        case .peony: "mǔ dān huā"
        case .sunflower: "xiànɡ rì kuí"
        case .camellia: "shān chá huā"
        }
    }

    var collectionDescription: String {
        switch self {
        case .peach: "粉粉的花瓣轻轻张开，春风来过了，\n瞧着它，心里也软软甜甜的"
        case .begonia: "海棠花轻轻舒展，花瓣迎着春风，\n看一眼，心里就暖暖的"
        case .tulip: "彩色花苞迎着光打开，春天住进房间，\n心情也跟着亮起来"
        case .lotus: "荷叶托着粉嘟嘟的荷花，风一吹轻轻晃，\n瞧见它，心情就软软的、甜甜的"
        case .narcissus: "水仙亭亭立着，清凌凌的花像小星光，\n看一眼心里亮亮的，烦忧都散啦"
        case .wisteria: "紫藤花串串垂下来，紫莹莹晃悠悠，\n瞧着它，心情也软软糯糯的甜"
        case .peony: "牡丹花艳艳开满园，层层花瓣像小裙摆，\n见着它，心里欢喜得冒泡泡"
        case .sunflower: "向日葵追着太阳笑，金闪闪的脸暖洋洋，\n看它就满心阳光，坏心情全跑光"
        case .camellia: "白山茶花白嫩嫩挂枝头，花瓣润润的，\n望着它，心里温温的，特别踏实"
        }
    }

    var collectionCardDescription: String {
        switch self {
        case .peach, .begonia, .tulip:
            rewardDescription
        case .lotus, .narcissus, .wisteria, .peony, .sunflower, .camellia:
            collectionDescription
        }
    }

    var rewardDescription: String {
        switch self {
        case .peach: "粉粉的花瓣轻轻张开，\n春风来过了。"
        case .begonia: "白白的花瓣缓缓舒展，\n春风落脚了。"
        case .tulip: "一束花瓣轻轻张开，\n第三阵春风停在了花心里。"
        case .lotus, .narcissus, .wisteria, .peony, .sunflower, .camellia: collectionDescription
        }
    }

    var rewardPinyinLine: String {
        switch self {
        case .peach: "táo huā xǐng lái la"
        case .begonia: "hǎi táng huā kāi la"
        case .tulip: "yù jīn xiāng kāi la"
        case .lotus, .narcissus, .wisteria, .peony, .sunflower, .camellia: pinyin
        }
    }

    var rewardTitleLine: String {
        switch self {
        case .peach: "桃花醒来啦！"
        case .begonia: "海棠花开啦！"
        case .tulip: "郁金香开啦！"
        case .lotus, .narcissus, .wisteria, .peony, .sunflower, .camellia: "\(title)开啦！"
        }
    }

    var rewardGuideLine: String {
        switch self {
        case .peach: "让我们把春天放在房间吧"
        case .begonia: "和家人把第二阵春风带回房间吧"
        case .tulip: "把最后一阵春风种进房间吧"
        case .lotus, .narcissus, .wisteria, .peony, .sunflower, .camellia: "把\(title)放进我们的世界吧"
        }
    }

    var placementSuccessLine: String {
        switch self {
        case .peach: "桃花找到新位置啦！\n第二阵春风正等着你。"
        case .begonia: "海棠花找到新位置啦！\n第三阵春风正等着你。\n和家人一起进入表情镜子吧！"
        case .tulip: "三朵花都找到位置啦！\n一起看看春日花园吧。"
        case .lotus, .narcissus, .wisteria, .peony, .sunflower, .camellia: "\(title)找到新位置啦！"
        }
    }

    var assetName: String {
        switch self {
        case .peach: "ar_plant_peach"
        case .begonia: "ar_plant_begonia"
        case .tulip: "ar_plant_tulip"
        case .lotus: "ar_plant_lotus"
        case .narcissus: "ar_plant_narcissus"
        case .wisteria: "ar_plant_wisteria"
        case .peony: "ar_plant_peony"
        case .sunflower: "ar_plant_sunflower"
        case .camellia: "ar_plant_camellia"
        }
    }

    var collectionStaticAssetName: String? {
        switch self {
        case .lotus: "ar_collection_lotus"
        case .narcissus: "ar_collection_narcissus"
        case .wisteria: "ar_collection_wisteria"
        case .peony: "ar_collection_peony"
        case .sunflower: "ar_collection_sunflower"
        case .camellia: "ar_collection_camellia"
        case .peach, .begonia, .tulip: nil
        }
    }

    var collectionPreviewLayout: (size: CGSize, center: CGPoint) {
        switch self {
        case .lotus:
            (CGSize(width: 141, height: 114), CGPoint(x: 79.5, y: 120))
        case .narcissus:
            (CGSize(width: 123, height: 165), CGPoint(x: 82.5, y: 107.5))
        case .wisteria:
            (CGSize(width: 118, height: 160), CGPoint(x: 77, y: 120))
        case .peony:
            (CGSize(width: 122, height: 164), CGPoint(x: 79, y: 114))
        case .sunflower:
            (CGSize(width: 140, height: 189), CGPoint(x: 77, y: 138.5))
        case .camellia:
            (CGSize(width: 129, height: 174), CGPoint(x: 79.5, y: 114))
        case .peach, .begonia, .tulip:
            (CGSize(width: 146, height: 197), CGPoint(x: 79.5, y: 118))
        }
    }

    var canvasSize: CGSize {
        switch self {
        case .peach, .begonia: CGSize(width: 324, height: 240)
        case .tulip, .lotus, .narcissus, .wisteria, .peony, .sunflower, .camellia:
            CGSize(width: 240, height: 320)
        }
    }

    /// 源动图固定画布内植物的可见联合区域，用底边作为 AR 落点。
    var contentBounds: CGRect {
        switch self {
        case .peach: CGRect(x: 73, y: 0, width: 178, height: 226)
        case .begonia: CGRect(x: 76, y: 7, width: 172, height: 227)
        case .tulip: CGRect(x: 24, y: 9, width: 190, height: 303)
        case .lotus: CGRect(x: 37, y: 107, width: 182, height: 153)
        case .narcissus: CGRect(x: 5, y: 21, width: 229, height: 279)
        case .wisteria: CGRect(x: 42, y: 0, width: 197, height: 296)
        case .peony: CGRect(x: 25, y: 83, width: 193, height: 195)
        case .sunflower: CGRect(x: 1, y: 22, width: 238, height: 284)
        case .camellia: CGRect(x: 23, y: 74, width: 197, height: 198)
        }
    }

    var visibleHeight: Float {
        switch self {
        case .peach: 0.36
        case .begonia: 0.34
        case .tulip: 0.42
        case .lotus: 0.28
        case .narcissus: 0.40
        case .wisteria: 0.42
        case .peony: 0.32
        case .sunflower: 0.44
        case .camellia: 0.32
        }
    }

    /// 将动图画布中植物的可见底边换算到拖拽预览坐标，松手后 AR 植物不会跳位。
    func previewBaselineOffset(in frameSize: CGSize) -> CGSize {
        let fitScale = min(frameSize.width / canvasSize.width, frameSize.height / canvasSize.height)
        let renderedSize = CGSize(width: canvasSize.width * fitScale, height: canvasSize.height * fitScale)
        let origin = CGPoint(
            x: (frameSize.width - renderedSize.width) / 2,
            y: (frameSize.height - renderedSize.height) / 2
        )
        let baseline = CGPoint(
            x: origin.x + contentBounds.midX * fitScale,
            y: origin.y + contentBounds.maxY * fitScale
        )
        return CGSize(
            width: baseline.x - frameSize.width / 2,
            height: baseline.y - frameSize.height / 2
        )
    }
}

private struct SproutlyGIFView: UIViewRepresentable {
    let asset: String

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = false
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        guard context.coordinator.asset != asset else { return }
        context.coordinator.asset = asset
        uiView.image = nil
        let coordinator = context.coordinator
        DispatchQueue.global(qos: .userInitiated).async {
            let image = SproutlyGIFDecoder.animatedImage(asset: asset)
            DispatchQueue.main.async {
                guard coordinator.asset == asset else { return }
                uiView.image = image
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var asset = ""
    }
}

private struct SproutlyStaticPlantView: UIViewRepresentable {
    let asset: String

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = false
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        guard context.coordinator.asset != asset else { return }
        context.coordinator.asset = asset
        uiView.image = nil
        let coordinator = context.coordinator
        DispatchQueue.global(qos: .userInitiated).async {
            let image = SproutlyGIFDecoder.staticImage(asset: asset)
            DispatchQueue.main.async {
                guard coordinator.asset == asset else { return }
                uiView.image = image
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var asset = ""
    }
}

private struct SproutlyARWaveform: View {
    let active: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !active)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                HStack(alignment: .center, spacing: 4) {
                    ForEach(0..<31, id: \.self) { index in
                        let envelope = 0.28 + 0.72 * sin(CGFloat(index) / 30 * .pi)
                        let pulse = active
                            ? (sin(CGFloat(time) * 5.2 + CGFloat(index) * 0.74) + 1) / 2
                            : (sin(CGFloat(index) * 0.92) + 1) / 2
                        Capsule()
                            .fill(color)
                            .frame(width: max(2, proxy.size.width / 85),
                                   height: max(6, proxy.size.height * envelope * (0.22 + pulse * 0.72)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private enum SproutlyGIFDecoder {
    private static let imageCache = NSCache<NSString, UIImage>()
    private static let staticImageCache = NSCache<NSString, UIImage>()

    static func animatedImage(asset: String) -> UIImage? {
        if let cached = imageCache.object(forKey: asset as NSString) { return cached }
        guard
            let dataAsset = NSDataAsset(name: asset),
            let source = CGImageSourceCreateWithData(dataAsset.data as CFData, nil)
        else { return nil }

        var images: [UIImage] = []
        var total = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            guard
                let frame = CGImageSourceCreateImageAtIndex(source, index, nil),
                let keyed = SproutlyGreenScreen.key(frame)
            else { continue }
            images.append(UIImage(cgImage: keyed, scale: 1, orientation: .up))
            total += frameDuration(source: source, index: index)
        }
        guard let first = images.first else { return nil }
        let image = images.count == 1 ? first : UIImage.animatedImage(with: images, duration: max(total, 0.1))
        if let image { imageCache.setObject(image, forKey: asset as NSString) }
        return image
    }

    static func staticImage(asset: String) -> UIImage? {
        if let cached = staticImageCache.object(forKey: asset as NSString) { return cached }
        guard
            let dataAsset = NSDataAsset(name: asset),
            let source = CGImageSourceCreateWithData(dataAsset.data as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            let frame = CGImageSourceCreateImageAtIndex(
                source,
                CGImageSourceGetCount(source) - 1,
                nil
            ),
            let keyed = SproutlyGreenScreen.key(frame)
        else { return nil }

        let image = UIImage(cgImage: keyed, scale: 1, orientation: .up)
        staticImageCache.setObject(image, forKey: asset as NSString)
        return image
    }

    static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.1 }
        let unclamped = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
        let clamped = (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
        return max(unclamped ?? clamped ?? 0.1, 0.04)
    }
}

private enum SproutlyGreenScreen {
    static func key(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            let dominance = green - max(red, blue)

            // 只识别素材中的高亮荧光绿幕，保留植物自身的深绿色叶片。
            if green > 170, dominance > 45, red < 120, blue < 140 {
                let greenScore = min(max(Double(green - 170) / 70, 0), 1)
                let dominanceScore = min(max(Double(dominance - 45) / 80, 0), 1)
                let redScore = min(max(Double(120 - red) / 70, 0), 1)
                let blueScore = min(max(Double(140 - blue) / 80, 0), 1)
                let removal = min(greenScore, dominanceScore, redScore, blueScore)
                let keep = 1 - removal
                let alpha = Double(pixels[offset + 3]) * keep
                let despilledGreen = min(green, max(red, blue))
                pixels[offset] = UInt8(max(0, min(255, Int(Double(red) * keep))))
                pixels[offset + 1] = UInt8(max(0, min(255, Int(Double(despilledGreen) * keep))))
                pixels[offset + 2] = UInt8(max(0, min(255, Int(Double(blue) * keep))))
                pixels[offset + 3] = UInt8(max(0, min(255, Int(alpha))))
                if pixels[offset + 3] < 5 {
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 0
                    pixels[offset + 3] = 0
                }
            }
        }
        return context.makeImage()
    }
}

// MARK: - RealityKit scene

private struct SproutlyARContainer: UIViewRepresentable {
    @ObservedObject var scene: SproutlyARScene

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        scene.connect(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

private struct SproutlyAnimationLayout {
    let planeWidth: Float
    let planeHeight: Float
    let centerX: Float
    let centerY: Float
    let visibleWidth: Float
}

@MainActor
private final class SproutlyARAnimationClip {
    let texture: TextureResource

    private let source: CGImageSource
    private let durations: [TimeInterval]
    private let totalDuration: TimeInterval
    private var elapsed: TimeInterval = 0
    private var shownIndex = 0

    init?(kind: SproutlyARPlantKind) {
        guard
            let dataAsset = NSDataAsset(name: kind.assetName),
            let source = CGImageSourceCreateWithData(
                dataAsset.data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ),
            CGImageSourceGetCount(source) > 0,
            let firstSource = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let first = SproutlyGreenScreen.key(firstSource)
        else { return nil }

        let durations = (0..<CGImageSourceGetCount(source)).map {
            SproutlyGIFDecoder.frameDuration(source: source, index: $0)
        }
        let options = TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none)
        guard let texture = try? TextureResource.generate(from: first, withName: kind.assetName, options: options) else {
            return nil
        }
        self.source = source
        self.durations = durations
        totalDuration = max(durations.reduce(0, +), 0.1)
        self.texture = texture
    }

    func layout(kind: SproutlyARPlantKind) -> SproutlyAnimationLayout {
        let canvas = kind.canvasSize
        let bounds = kind.contentBounds
        let planeHeight = kind.visibleHeight * Float(canvas.height / bounds.height)
        let planeWidth = planeHeight * Float(canvas.width / canvas.height)
        let centerX = Float(0.5 - bounds.midX / canvas.width) * planeWidth
        let centerY = Float(bounds.maxY / canvas.height - 0.5) * planeHeight
        let visibleWidth = kind.visibleHeight * Float(bounds.width / bounds.height)
        return SproutlyAnimationLayout(
            planeWidth: planeWidth,
            planeHeight: planeHeight,
            centerX: centerX,
            centerY: centerY,
            visibleWidth: visibleWidth
        )
    }

    func advance(by delta: TimeInterval) {
        guard durations.count > 1 else { return }
        elapsed = (elapsed + delta).truncatingRemainder(dividingBy: totalDuration)
        var cursor = 0.0
        var index = 0
        for duration in durations {
            if elapsed < cursor + duration { break }
            cursor += duration
            index += 1
        }
        index = min(index, durations.count - 1)
        guard index != shownIndex,
              let sourceFrame = CGImageSourceCreateImageAtIndex(source, index, nil),
              let keyed = SproutlyGreenScreen.key(sourceFrame)
        else { return }
        let options = TextureResource.CreateOptions(semantic: .color, mipmapsMode: .none)
        do {
            try texture.replace(withImage: keyed, options: options)
            shownIndex = index
        } catch {
            // 保留上一有效帧，下一次刷新继续尝试。
        }
    }
}

@MainActor
private final class SproutlyARScene: NSObject, ObservableObject, ARSessionDelegate {
    private enum DraggableItem {
        case plant(SproutlyARPlantKind)
    }

    @Published private(set) var placedPlantCount = 0
    // 保留旧 ARView，直到所有 Anchor 从旧 Scene 安全移除。RealityKit 的根 Anchor
    // 不能只调用 removeFromParent 后直接跨 Scene 复用，否则会访问已释放的组件表。
    private var arView: ARView?
    private var anchors: [SproutlyARPlantKind: AnchorEntity] = [:]
    private var roots: [SproutlyARPlantKind: ModelEntity] = [:]
    private var plantScales: [SproutlyARPlantKind: Float] = [:]
    private var clips: [SproutlyARPlantKind: SproutlyARAnimationClip] = [:]
    private var gestures: [UIGestureRecognizer] = []
    private var draggedItem: DraggableItem?
    private var pinchedPlant: SproutlyARPlantKind?
    private var pinchStartingScale: Float = 1
    private var updateSubscription: (any Cancellable)?
    private var shouldRunSession = true

    func connect(to view: ARView) {
        if let current = arView, current === view {
            if shouldRunSession {
                runSession(on: view)
            } else {
                view.session.pause()
            }
            return
        }

        if let old = arView {
            gestures.forEach { old.removeGestureRecognizer($0) }
            gestures.removeAll()
            updateSubscription?.cancel()
            anchors.values.forEach { old.scene.removeAnchor($0) }
        }
        arView = view
        view.automaticallyConfigureSession = false
        view.session.delegate = self
        if shouldRunSession {
            runSession(on: view)
        } else {
            view.session.pause()
        }
        anchors.values.forEach {
            view.scene.addAnchor($0)
        }
        reinstallGestures()
        updateSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self else { return }
            self.clips.values.forEach { $0.advance(by: event.deltaTime) }
            self.faceBillboardsTowardCamera()
        }
    }

    func resume() {
        shouldRunSession = true
        guard let arView else { return }
        runSession(on: arView)
    }

    func pause() {
        shouldRunSession = false
        arView?.session.pause()
    }

    private func runSession(on view: ARView) {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.isLightEstimationEnabled = true
        configuration.environmentTexturing = .automatic
        view.session.run(configuration)
    }

    func resetPlants() {
        anchors.values.forEach { $0.removeFromParent() }
        anchors.removeAll()
        roots.removeAll()
        plantScales.removeAll()
        draggedItem = nil
        pinchedPlant = nil
        gestures.forEach { $0.view?.removeGestureRecognizer($0) }
        gestures.removeAll()
        placedPlantCount = 0
        reinstallGestures()
    }

    func captureSnapshot(completion: @escaping (UIImage?) -> Void) {
        guard let arView else {
            completion(nil)
            return
        }
        arView.snapshot(saveToHDR: false, completion: completion)
    }

    @discardableResult
    func place(kind: SproutlyARPlantKind, normalizedPoint: CGPoint) -> Bool {
        guard let arView else { return false }
        let unitPoint = CGPoint(
            x: min(max(normalizedPoint.x, 0), 1),
            y: min(max(normalizedPoint.y, 0), 1)
        )
        let localPoint = CGPoint(
            x: unitPoint.x * arView.bounds.width,
            y: unitPoint.y * arView.bounds.height
        )
        guard let transform = placementTransform(at: localPoint), let root = makePlant(kind: kind) else { return false }
        root.scale = SIMD3(repeating: plantScales[kind] ?? 1)
        let anchor = AnchorEntity(world: transform)
        anchor.addChild(root)
        anchors[kind]?.removeFromParent()
        arView.scene.addAnchor(anchor)
        anchors[kind] = anchor
        roots[kind] = root
        placedPlantCount = roots.count
        reinstallGestures()
        return true
    }

    private func makePlant(kind: SproutlyARPlantKind) -> ModelEntity? {
        let clip: SproutlyARAnimationClip
        if let existing = clips[kind] {
            clip = existing
        } else if let created = SproutlyARAnimationClip(kind: kind) {
            clips[kind] = created
            clip = created
        } else {
            return nil
        }
        let layout = clip.layout(kind: kind)
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(clip.texture))
        material.blending = .transparent(opacity: .init(scale: 1))
        let plane = ModelEntity(
            mesh: .generatePlane(width: layout.planeWidth, height: layout.planeHeight),
            materials: [material]
        )
        plane.position = SIMD3(layout.centerX, layout.centerY, 0)

        let root = ModelEntity()
        root.name = "sproutly-gif-\(kind.title)"
        root.addChild(plane)
        root.collision = CollisionComponent(shapes: [
            ShapeResource.generateBox(size: SIMD3(layout.visibleWidth, kind.visibleHeight, 0.04))
                .offsetBy(translation: SIMD3(0, kind.visibleHeight / 2, 0))
        ])
        return root
    }

    private func placementTransform(at point: CGPoint, preservingDepthOf root: ModelEntity? = nil) -> simd_float4x4? {
        guard let ray = arView?.ray(through: point), simd_length_squared(ray.direction) > 0 else { return nil }
        let height = max(arView?.bounds.height ?? 0, 1)
        let verticalFraction = Float(min(max(point.y / height, 0), 1))
        let placementDistance = 1.15 + (1 - verticalFraction) * 0.65
        let distance = root.map { simd_length($0.position(relativeTo: nil) - ray.origin) } ?? placementDistance
        let position = ray.origin + simd_normalize(ray.direction) * distance

        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(position.x, position.y, position.z, 1)
        return transform
    }

    private func reinstallGestures() {
        gestures.forEach { $0.view?.removeGestureRecognizer($0) }
        gestures.removeAll()
        guard let arView, !roots.isEmpty else { return }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePlantPan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        arView.addGestureRecognizer(pan)
        gestures.append(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePlantPinch(_:)))
        pinch.cancelsTouchesInView = false
        arView.addGestureRecognizer(pinch)
        gestures.append(pinch)
    }

    @objc private func handlePlantPan(_ recognizer: UIPanGestureRecognizer) {
        guard let arView else { return }
        let point = recognizer.location(in: arView)

        switch recognizer.state {
        case .began:
            guard let entity = arView.entity(at: point) else {
                draggedItem = nil
                return
            }
            draggedItem = draggableItem(containing: entity)
        case .changed, .ended:
            defer {
                if recognizer.state == .ended { self.draggedItem = nil }
            }
            guard let draggedItem else { return }
            let root: ModelEntity?
            switch draggedItem {
            case .plant(let kind): root = roots[kind]
            }
            guard let root,
                  let transform = placementTransform(at: point, preservingDepthOf: root)
            else { return }

            let position = SIMD3<Float>(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )
            root.setPosition(position, relativeTo: nil)
            // 保留用户双指设定的尺寸，镜头移动时再由透视产生近大远小。
            if case .plant(let kind) = draggedItem {
                root.scale = SIMD3(repeating: plantScales[kind] ?? 1)
            }

            if recognizer.state == .ended {
                if ParentComfortRuntime.hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        case .cancelled, .failed:
            draggedItem = nil
        default:
            break
        }
    }

    @objc private func handlePlantPinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let arView else { return }
        switch recognizer.state {
        case .began:
            guard let entity = arView.entity(at: recognizer.location(in: arView)),
                  case .plant(let kind)? = draggableItem(containing: entity)
            else { return }
            pinchedPlant = kind
            pinchStartingScale = plantScales[kind] ?? 1
        case .changed, .ended:
            guard let kind = pinchedPlant, let root = roots[kind] else { return }
            let scale = min(max(pinchStartingScale * Float(recognizer.scale), 0.75), 1.6)
            plantScales[kind] = scale
            root.scale = SIMD3(repeating: scale)
            if recognizer.state == .ended { pinchedPlant = nil }
        case .cancelled, .failed:
            pinchedPlant = nil
        default:
            break
        }
    }

    private func draggableItem(containing entity: Entity) -> DraggableItem? {
        var current: Entity? = entity
        while let candidate = current {
            if let match = roots.first(where: { $0.value === candidate }) {
                return .plant(match.key)
            }
            current = candidate.parent
        }
        return nil
    }

    private func faceBillboardsTowardCamera() {
        guard let camera = arView?.session.currentFrame?.camera.transform else { return }
        let cameraPosition = SIMD3<Float>(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
        for (kind, root) in roots {
            root.scale = SIMD3(repeating: plantScales[kind] ?? 1)
            let position = root.position(relativeTo: nil)
            let direction = SIMD2(cameraPosition.x - position.x, cameraPosition.z - position.z)
            guard simd_length_squared(direction) > 0.0001 else { continue }
            root.orientation = simd_quatf(angle: atan2(direction.x, direction.y), axis: SIMD3(0, 1, 0))
        }
    }
}

// MARK: - Voice answer and KAKA audio

@MainActor
private final class SproutlyARSpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isRecording = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasTap = false
    private var recognitionGeneration = 0

    func requestPermissions() async {
        _ = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        _ = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    @discardableResult
    func start() -> Bool {
        guard
            SFSpeechRecognizer.authorizationStatus() == .authorized,
            AVAudioApplication.shared.recordPermission == .granted
        else {
            transcript = "请先允许麦克风和语音识别权限"
            return false
        }
        cancel()
        transcript = ""
        guard let recognizer, recognizer.isAvailable else {
            transcript = "语音识别暂不可用，请稍后再试"
            return false
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = false
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { return false }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasTap = true
            engine.prepare()
            try engine.start()
            isRecording = true
            let generation = recognitionGeneration
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
                if let text = result?.bestTranscription.formattedString {
                    Task { @MainActor in
                        guard let self, self.recognitionGeneration == generation else { return }
                        self.transcript = text
                    }
                }
            }
            return true
        } catch {
            cancel()
            transcript = "录音启动失败，请再试一次"
            return false
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        request?.endAudio()
        isRecording = false
    }

    func cancel() {
        recognitionGeneration += 1
        if engine.isRunning { engine.stop() }
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        request?.endAudio()
        recognitionTask?.cancel()
        request = nil
        recognitionTask = nil
        isRecording = false
        transcript = ""
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
private final class SproutlyKakaVoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private let soundNames = [
        "ar_emotion_angry",
        "ar_emotion_sad",
        "ar_emotion_afraid",
        "ar_emotion_calm",
        "ar_emotion_happy"
    ]

    func play(index: Int) {
        stop()
        let soundName = soundNames[min(max(index, 0), soundNames.count - 1)]
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "mp3") else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)

            let nextPlayer = try AVAudioPlayer(contentsOf: url)
            nextPlayer.delegate = self
            nextPlayer.prepareToPlay()
            nextPlayer.play()
            player = nextPlayer
        } catch {
            stop()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

// MARK: - Front and rear live camera mirror

/// MultiCam 的画面直接交给 `AVCaptureVideoPreviewLayer` 显示，避免每帧生成
/// `CGImage` 导致的内存尖峰。前置画面和后置背景仍来自同一个双摄会话。
private struct SproutlyMultiCamPreview: UIViewRepresentable {
    @ObservedObject var camera: SproutlySmileCamera
    let position: AVCaptureDevice.Position

    func makeUIView(context: Context) -> SproutlyMultiCamPreviewView {
        let view = SproutlyMultiCamPreviewView(session: camera.session)
        view.camera = camera
        camera.attachPreview(view.previewLayer, position: position)
        return view
    }

    func updateUIView(_ uiView: SproutlyMultiCamPreviewView, context: Context) {
        camera.attachPreview(uiView.previewLayer, position: position)
    }

    static func dismantleUIView(_ uiView: SproutlyMultiCamPreviewView, coordinator: ()) {
        uiView.camera?.detachPreview(uiView.previewLayer)
    }
}

private final class SproutlyMultiCamPreviewView: UIView {
    let previewLayer: AVCaptureVideoPreviewLayer
    weak var camera: SproutlySmileCamera?

    init(session: AVCaptureMultiCamSession) {
        previewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.10, green: 0.18, blue: 0.18, alpha: 1)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

private final class SproutlySmileCamera: NSObject, ObservableObject {
    @Published private(set) var isSmiling = false
    @Published private(set) var hasFace = false

    let session = AVCaptureMultiCamSession()
    private let sessionQueue = DispatchQueue(label: "sproutly.ar.smile.session")
    private let visionQueue = DispatchQueue(label: "sproutly.ar.smile.vision")
    private let frontOutput = AVCaptureVideoDataOutput()
    private var frontDevice: AVCaptureDevice?
    private var rearDevice: AVCaptureDevice?
    private var frontPort: AVCaptureInput.Port?
    private var rearPort: AVCaptureInput.Port?
    private var captureRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var captureRotationObservation: NSKeyValueObservation?
    private var previewBindings: [ObjectIdentifier: PreviewBinding] = [:]
    private var configured = false
    private var lastAnalysis = Date.distantPast
    private var recentSmileSamples: [Bool] = []
    private var smileHeldUntil = Date.distantPast
    private let smileWindowSize = 7

    private final class PreviewBinding {
        let connection: AVCaptureConnection
        let rotationCoordinator: AVCaptureDevice.RotationCoordinator
        var observation: NSKeyValueObservation?

        init(
            connection: AVCaptureConnection,
            rotationCoordinator: AVCaptureDevice.RotationCoordinator
        ) {
            self.connection = connection
            self.rotationCoordinator = rotationCoordinator
        }
    }

    func prepare() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.configured else { return }
            self.configure()
        }
    }

    func start(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                guard allowed else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                DispatchQueue.main.async { self?.start(completion: completion) }
            }
            return
        case .authorized:
            break
        default:
            completion(false)
            return
        }
        resetSmileTracking()
        sessionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            if !self.configured { self.configure() }
            guard self.configured else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let started = self.session.isRunning
            DispatchQueue.main.async { completion(started) }
        }
    }

    func stop(completion: @escaping () -> Void = {}) {
        resetSmileTracking()
        sessionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async(execute: completion)
                return
            }
            if self.session.isRunning { self.session.stopRunning() }
            // 让相机硬件完成释放后再交还给 ARKit，避免双摄与 AR 会话争抢资源。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: completion)
        }
    }

    func attachPreview(_ previewLayer: AVCaptureVideoPreviewLayer, position: AVCaptureDevice.Position) {
        previewLayer.backgroundColor = UIColor(red: 0.10, green: 0.18, blue: 0.18, alpha: 1).cgColor
        sessionQueue.async { [weak self, weak previewLayer] in
            guard let self, let previewLayer else { return }
            if !self.configured { self.configure() }
            let identifier = ObjectIdentifier(previewLayer)
            guard self.configured, self.previewBindings[identifier] == nil else { return }

            let port = position == .front ? self.frontPort : self.rearPort
            let device = position == .front ? self.frontDevice : self.rearDevice
            guard let port, let device else { return }

            let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
            guard self.session.canAddConnection(connection) else { return }
            self.session.beginConfiguration()
            self.session.addConnection(connection)
            self.session.commitConfiguration()

            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            let binding = PreviewBinding(connection: connection, rotationCoordinator: coordinator)
            binding.observation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.initial, .new]
            ) { [weak self, weak connection] coordinator, _ in
                guard let self, let connection else { return }
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                self.sessionQueue.async { [weak self, weak connection] in
                    guard let self, let connection else { return }
                    self.configureConnection(
                        connection,
                        rotationAngle: angle,
                        mirrored: position == .front
                    )
                }
            }
            self.previewBindings[identifier] = binding
        }
    }

    func detachPreview(_ previewLayer: AVCaptureVideoPreviewLayer) {
        sessionQueue.async { [weak self, weak previewLayer] in
            guard let self, let previewLayer else { return }
            let identifier = ObjectIdentifier(previewLayer)
            guard let binding = self.previewBindings.removeValue(forKey: identifier) else { return }
            binding.observation = nil
            if self.session.connections.contains(where: { $0 === binding.connection }) {
                self.session.beginConfiguration()
                self.session.removeConnection(binding.connection)
                self.session.commitConfiguration()
            }
        }
    }

    private func resetSmileTracking() {
        visionQueue.async { [weak self] in
            self?.recentSmileSamples.removeAll(keepingCapacity: true)
            self?.smileHeldUntil = .distantPast
        }
        Task { @MainActor [weak self] in
            self?.isSmiling = false
            self?.hasFace = false
        }
    }

}

extension SproutlySmileCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    private func configure() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else { return }
        var configurationSucceeded = false
        session.beginConfiguration()
        defer {
            if !configurationSucceeded {
                session.connections.forEach(session.removeConnection)
                session.outputs.forEach(session.removeOutput)
                session.inputs.forEach(session.removeInput)
            }
            session.commitConfiguration()
        }

        guard
            let frontDevice = cameraDevice(position: .front),
            let rearDevice = cameraDevice(position: .back),
            prepareForMultiCam(frontDevice),
            prepareForMultiCam(rearDevice),
            let frontInput = try? AVCaptureDeviceInput(device: frontDevice),
            let rearInput = try? AVCaptureDeviceInput(device: rearDevice),
            session.canAddInput(frontInput),
            session.canAddInput(rearInput)
        else { return }

        session.addInputWithNoConnections(frontInput)
        session.addInputWithNoConnections(rearInput)

        configureOutput(frontOutput, queue: visionQueue)
        guard session.canAddOutput(frontOutput) else { return }
        session.addOutputWithNoConnections(frontOutput)

        guard
            let frontPort = frontInput.ports.first(where: { $0.mediaType == .video }),
            let rearPort = rearInput.ports.first(where: { $0.mediaType == .video })
        else { return }

        let frontConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)
        guard session.canAddConnection(frontConnection) else { return }
        session.addConnection(frontConnection)

        self.frontDevice = frontDevice
        self.rearDevice = rearDevice
        self.frontPort = frontPort
        self.rearPort = rearPort
        installCaptureRotationCoordinator(device: frontDevice, connection: frontConnection)
        configured = true
        configurationSucceeded = true
    }

    private func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func prepareForMultiCam(_ device: AVCaptureDevice) -> Bool {
        let formats = device.formats.filter { format in
            format.isMultiCamSupported && format.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= 30 && $0.maxFrameRate >= 24
            }
        }
        guard
            let preferred = formats.min(by: { lhs, rhs in
            let left = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let right = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            let target = 1280 * 720
            let leftDelta = abs(Int(left.width * left.height) - target)
            let rightDelta = abs(Int(right.width * right.height) - target)
            return leftDelta < rightDelta
            }),
            preferred.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameRate <= 30 && $0.maxFrameRate >= 24
            })
        else { return false }

        do {
            try device.lockForConfiguration()
            device.activeFormat = preferred
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    private func configureOutput(_ output: AVCaptureVideoDataOutput, queue: DispatchQueue) {
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: queue)
    }

    private func installCaptureRotationCoordinator(
        device: AVCaptureDevice,
        connection: AVCaptureConnection
    ) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        let observation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.initial, .new]
        ) { [weak self, weak connection] coordinator, _ in
            guard let self, let connection else { return }
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            self.sessionQueue.async { [weak self, weak connection] in
                guard let self, let connection else { return }
                self.configureConnection(connection, rotationAngle: angle, mirrored: true)
            }
        }
        captureRotationCoordinator = coordinator
        captureRotationObservation = observation
    }

    private func configureConnection(
        _ connection: AVCaptureConnection,
        rotationAngle: CGFloat,
        mirrored: Bool
    ) {
        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = Date()
        guard output === frontOutput else { return }
        guard now.timeIntervalSince(lastAnalysis) > 0.16 else { return }
        lastAnalysis = now

        let request = VNDetectFaceLandmarksRequest { [weak self] request, _ in
            guard let self else { return }
            let face = (request.results as? [VNFaceObservation])?.max(by: {
                $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
            })
            let rawSmile = face.map(Self.smileEstimate) ?? false
            let smiling = self.stabilizedSmile(rawSmile, hasFace: face != nil, at: now)
            Task { @MainActor in
                self.hasFace = face != nil
                self.isSmiling = smiling
            }
        }
        // The capture connection has already rotated the buffer upright for the
        // current device attitude; Vision therefore analyses a portrait image.
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
    }

    /// Vision 的单帧嘴型点会随光线和儿童头部轻微移动而抖动。
    /// 使用短窗口投票，并在成功后保留 1.4 秒，让用户有时间点击确认。
    private func stabilizedSmile(_ rawSmile: Bool, hasFace: Bool, at date: Date) -> Bool {
        guard hasFace else {
            recentSmileSamples.removeAll(keepingCapacity: true)
            smileHeldUntil = .distantPast
            return false
        }

        recentSmileSamples.append(rawSmile)
        if recentSmileSamples.count > smileWindowSize {
            recentSmileSamples.removeFirst(recentSmileSamples.count - smileWindowSize)
        }

        let positiveCount = recentSmileSamples.lazy.filter { $0 }.count
        let requiredVotes = recentSmileSamples.count >= 6 ? 3 : 2
        let stable = recentSmileSamples.count >= 3 && positiveCount >= requiredVotes
        if stable {
            smileHeldUntil = date.addingTimeInterval(1.4)
        }
        return stable || date < smileHeldUntil
    }

    private static func smileEstimate(_ face: VNFaceObservation) -> Bool {
        guard let points = face.landmarks?.outerLips?.normalizedPoints, points.count >= 6 else { return false }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return false }
        let width = maxX - minX
        let height = maxY - minY
        let ratio = height / max(width, 0.001)

        // 儿童的嘴部在脸框中的占比通常更小，也更容易出现张嘴笑。
        // 比旧阈值更宽容，但仍排除嘴部点过小或纵向拉伸过强的误判。
        return width > 0.32 && height > 0.04 && ratio < 0.78
    }
}
