import ARKit
import AVFoundation
import Combine
import ImageIO
import RealityKit
import Speech
import SwiftUI
import UIKit

struct LiveARView: View {
    var onTaskFlowChanged: (Bool) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step {
        case landing
        case taskOneBrief
        case taskOneQuestion
        case taskOneCorrect
        case taskOneReward
        case taskOnePlacement
        case taskTwoBrief
        case taskTwoQuestion
        case taskTwoCorrect
        case taskTwoReward
        case taskTwoPlacement
        case ar17GardenIntro
        case ar18Garden
        case ar19PlantInteraction
        case ar20SoundInteraction
        case ar21PlantCollection
    }

    @StateObject private var scene = ARGardenScene()
    @StateObject private var speech = GardenSpeechRecognizer()
    @State private var step: Step = .landing
    @State private var isHoldingToSpeak = false
    @State private var answerFeedback = ""
    @State private var rewardDragOffset: CGSize = .zero
    @State private var isDraggingReward = false
    @State private var rewardWasPlaced = false
    @State private var taskPanelReveal: CGFloat = 0
    @State private var taskPanelDragStart: CGFloat?

    private let taskPanelTravel: CGFloat = 182

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / 402, proxy.size.height / 874)
            let canvasSize = CGSize(width: 402 * scale, height: 874 * scale)

            ZStack {
                arSurface(scale: scale)

                if supportsCollapsibleTaskPanel {
                    collapsibleTaskFlow(scale: scale)
                } else {
                    content(scale: scale)
                }

                if showsAnswerControls && isTaskPanelExpanded {
                    holdToSpeakLayer(scale: scale)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .coordinateSpace(name: "arCanvas")
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .ignoresSafeArea()
        .task {
            await speech.requestPermissions()
        }
        .onAppear {
            scene.resume()
            onTaskFlowChanged(false)
        }
        .onDisappear {
            onTaskFlowChanged(false)
            speech.cancel()
            scene.pause()
        }
    }

    @ViewBuilder
    private func arSurface(scale: CGFloat) -> some View {
        let isLanding = step == .landing

        ZStack {
            if isLanding {
                SproutlyHomeGradient()
                .frame(width: 402 * scale, height: 874 * scale)
                .allowsHitTesting(false)
            }

            ARGardenContainer(scene: scene)
                .frame(
                    width: (isLanding ? 356 : 402) * scale,
                    height: (isLanding ? 508 : 874) * scale
                )
                .clipShape(RoundedRectangle(cornerRadius: (isLanding ? 10 : 0) * scale))
                .overlay {
                    if isLanding {
                        RoundedRectangle(cornerRadius: 10 * scale)
                            .stroke(.white.opacity(0.5), lineWidth: 1 * scale)
                            .allowsHitTesting(false)
                    }
                }
                .shadow(
                    color: .black.opacity(isLanding ? 0.09 : 0),
                    radius: 10.2 * scale,
                    x: -3 * scale,
                    y: -2 * scale
                )
                .shadow(
                    color: .black.opacity(isLanding ? 0.25 : 0),
                    radius: 4 * scale,
                    y: 4 * scale
                )
                .position(x: 201 * scale, y: (isLanding ? 468 : 437) * scale)
        }
    }

    private var isQuestionStep: Bool {
        step == .taskOneQuestion || step == .taskTwoQuestion
    }

    private var showsAnswerControls: Bool {
        isQuestionStep || step == .taskOneCorrect || step == .taskTwoCorrect
    }

    private var supportsCollapsibleTaskPanel: Bool {
        switch step {
        case .taskOneBrief, .taskOneQuestion, .taskOneCorrect,
             .taskOneReward, .taskOnePlacement, .taskTwoBrief,
             .taskTwoQuestion, .taskTwoCorrect, .taskTwoReward,
             .taskTwoPlacement:
            true
        default:
            false
        }
    }

    private var isTaskPanelExpanded: Bool {
        taskPanelReveal >= taskPanelTravel - 0.5
    }

    private var isTaskTwo: Bool {
        switch step {
        case .taskTwoBrief, .taskTwoQuestion, .taskTwoCorrect,
             .taskTwoReward, .taskTwoPlacement, .ar17GardenIntro,
             .ar18Garden, .ar19PlantInteraction, .ar20SoundInteraction,
             .ar21PlantCollection:
            true
        default:
            false
        }
    }

    @ViewBuilder
    private func content(scale: CGFloat) -> some View {
        switch step {
        case .landing:
            landingPage(scale: scale)
        case .taskOneBrief:
            taskBriefPage(task: 1, scale: scale)
        case .taskOneQuestion, .taskOneCorrect:
            questionPage(task: 1, scale: scale)
        case .taskOneReward:
            rewardPage(task: 1, scale: scale)
        case .taskOnePlacement:
            placementPage(task: 1, scale: scale)
        case .taskTwoBrief:
            taskBriefPage(task: 2, scale: scale)
        case .taskTwoQuestion, .taskTwoCorrect:
            questionPage(task: 2, scale: scale)
        case .taskTwoReward:
            rewardPage(task: 2, scale: scale)
        case .taskTwoPlacement:
            placementPage(task: 2, scale: scale)
        case .ar17GardenIntro:
            ar17GardenIntroPage(scale: scale)
        case .ar18Garden:
            interactiveGardenPage(mode: .menu, scale: scale)
        case .ar19PlantInteraction:
            interactiveGardenPage(mode: .plants, scale: scale)
        case .ar20SoundInteraction:
            interactiveGardenPage(mode: .sound, scale: scale)
        case .ar21PlantCollection:
            plantCollectionPage(scale: scale)
        }
    }

    private func landingPage(scale: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10 * scale)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 197 / 255, green: 211 / 255, blue: 0),
                            Color(red: 227 / 255, green: 240 / 255, blue: 152 / 255),
                            Color(red: 241 / 255, green: 1, blue: 229 / 255)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 263 * scale, height: 56 * scale)
                .position(x: 246.5 * scale, y: 169 * scale)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 3 * scale) {
                Text("第一幕·春意盎然")
                    .arNativeText(size: 16, weight: .bold, scale: scale)
                Text("鼹鼠先生的新花园")
                    .arNativeText(size: 10, scale: scale)
            }
            .foregroundStyle(arInk)
            .position(x: 242 * scale, y: 166 * scale)

            Image("ar_landing_story")
                .resizable()
                .scaledToFill()
                .frame(width: 129 * scale, height: 109 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
                .position(x: 88.5 * scale, y: 142.5 * scale)
                .allowsHitTesting(false)
                .zIndex(2)

            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 22 * scale, weight: .regular))
                .foregroundStyle(Color(red: 0.32, green: 0.70, blue: 0.68))
                .frame(width: 24 * scale, height: 24 * scale)
                .position(x: 366 * scale, y: 107 * scale)
                .allowsHitTesting(false)

            Image(systemName: "play.fill")
                .font(.system(size: 30 * scale, weight: .medium))
                .foregroundStyle(Color(red: 0.35, green: 0.84, blue: 0.62))
                .frame(width: 56 * scale, height: 56 * scale)
                .position(x: 347 * scale, y: 169 * scale)
                .allowsHitTesting(false)

            ZStack {
                Image("ar_enter_world_button")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 266 * scale, height: 266 * scale)
                    .accessibilityHidden(true)
                Button {
                    transition(to: .taskOneBrief)
                } label: {
                    Text("进入世界")
                        .arNativeText(size: 24, weight: .bold, lineHeight: 36, scale: scale)
                        .foregroundStyle(.white)
                        .frame(width: 126 * scale, height: 126 * scale)
                }
                .buttonStyle(.plain)
            }
            .position(x: 202 * scale, y: 486 * scale)

            speechBubble(
                "你好，我是你的伙伴KAKA，让我们一起创造属于自己的秘密基地吧！",
                width: 248,
                height: 69,
                scale: scale
            )
            .position(x: 161 * scale, y: 644.5 * scale)

            KakaAvatarView(magnification: 1.26)
                .frame(width: 154 * scale, height: 154 * scale)
                .position(x: 323 * scale, y: 717 * scale)
                .allowsHitTesting(false)

            Image("ar_bottom_tabbar_vector")
                .resizable()
                .frame(width: 402 * scale, height: 117 * scale)
                .position(x: 201 * scale, y: 815.5 * scale)
                .allowsHitTesting(false)
        }
    }

    private func taskBriefPage(task: Int, scale: CGFloat) -> some View {
        ZStack {
            taskHeader(task: task, expanded: true, scale: scale)

            KakaAvatarView(magnification: 1.26)
                .frame(width: 107 * scale, height: 107 * scale)
                .position(x: 114.5 * scale, y: 377.5 * scale)
                .allowsHitTesting(false)

            bottomBackButton(scale: scale) {
                transition(to: task == 1 ? .landing : .taskOnePlacement)
            }
        }
    }

    /// 面板开合只控制展示层，不修改 `step`，因此题目、答案、奖励和放置进度都会保留。
    private func collapsibleTaskFlow(scale: CGFloat) -> some View {
        let progress = min(1, max(0, taskPanelReveal / taskPanelTravel))
        let task = isTaskTwo ? 2 : 1
        let expandedGrabberY = taskPanelExpandedGrabberY
        let grabberY = 63 + (expandedGrabberY - 63) * progress

        return ZStack {
            collapsedTaskPage(task: task, scale: scale)
                .opacity(1 - progress)
                .allowsHitTesting(progress < 0.02)

            content(scale: scale)
                .opacity(progress)
                .offset(y: -18 * (1 - progress) * scale)
                .allowsHitTesting(progress > 0.98)

            Color.clear
                .frame(width: 112 * scale, height: 42 * scale)
                .contentShape(Rectangle())
                .position(x: 201 * scale, y: grabberY * scale)
                .gesture(taskPanelDragGesture(scale: scale))
                .accessibilityLabel("任务面板")
                .accessibilityValue(isTaskPanelExpanded ? "已展开" : "已收起")
                .accessibilityAction(named: "展开任务面板") {
                    setTaskPanel(open: true)
                }
                .accessibilityAction(named: "收起任务面板") {
                    setTaskPanel(open: false)
                }
        }
    }

    private var taskPanelExpandedGrabberY: CGFloat {
        switch step {
        case .taskOneBrief, .taskTwoBrief:
            245
        case .taskOneQuestion, .taskOneCorrect,
             .taskTwoQuestion, .taskTwoCorrect:
            166
        case .taskOneReward, .taskOnePlacement,
             .taskTwoReward, .taskTwoPlacement:
            61
        default:
            63
        }
    }

    private func collapsedTaskPage(task: Int, scale: CGFloat) -> some View {
        ZStack {
            taskHeader(task: task, expanded: true, scale: scale)
                .offset(y: -taskPanelTravel * scale)
                .allowsHitTesting(false)

            KakaAvatarView(magnification: 1.26)
                .frame(width: 107 * scale, height: 107 * scale)
                .position(x: 114.5 * scale, y: 377.5 * scale)
                .allowsHitTesting(false)

            bottomBackButton(scale: scale) {
                transition(to: task == 1 ? .landing : .taskOnePlacement)
            }
        }
    }

    private func taskPanelDragGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("arCanvas"))
            .onChanged { value in
                let start = taskPanelDragStart ?? taskPanelReveal
                if taskPanelDragStart == nil {
                    taskPanelDragStart = start
                }
                taskPanelReveal = min(
                    taskPanelTravel,
                    max(0, start + value.translation.height / scale)
                )
            }
            .onEnded { value in
                let start = taskPanelDragStart ?? taskPanelReveal
                let predicted = start
                    + value.predictedEndTranslation.height / scale
                taskPanelDragStart = nil
                setTaskPanel(open: predicted >= taskPanelTravel / 2)
            }
    }

    private func setTaskPanel(open: Bool) {
        if !open {
            speech.cancel()
            isHoldingToSpeak = false
        }
        let animation: Animation = reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.34, dampingFraction: 0.88)
        withAnimation(animation) {
            taskPanelReveal = open ? taskPanelTravel : 0
        }
    }

    private func taskHeader(task: Int, expanded: Bool, scale: CGFloat) -> some View {
        let title = task == 1
            ? "找到房间里的KAKA，并帮助鼹鼠先生获得桃花"
            : "听声音找到开心的KAKA，并帮助鼹鼠先生获得荷花"

        return ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(red: 0.77, green: 1, blue: 0.98).opacity(0.82),
                            .white.opacity(0.56)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(width: 402 * scale, height: (expanded ? 256 : 74) * scale)

            Capsule()
                .fill(Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255))
                .frame(width: 65 * scale, height: 6 * scale)
                .position(x: 200.5 * scale, y: (expanded ? 245 : 61) * scale)

            if expanded {
                HStack(spacing: 5 * scale) {
                    KakaAvatarView(magnification: 1.24)
                        .frame(width: 54 * scale, height: 46 * scale)
                    Text("任务\(task == 1 ? "一" : "二")")
                        .arNativeText(size: 16, weight: .bold, scale: scale)
                        .foregroundStyle(.white)
                }
                .frame(width: 124 * scale, height: 35 * scale)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.31, green: 0.86, blue: 0.78),
                            Color(red: 0.11, green: 0.73, blue: 0.72)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .position(x: 86 * scale, y: 88.5 * scale)

                Text(title)
                    .arNativeText(size: 16, scale: scale)
                    .foregroundStyle(arInk)
                    .multilineTextAlignment(.center)
                    .frame(width: 224 * scale, height: 58 * scale)
                    .background(Color(red: 0.56, green: 0.92, blue: 0.91).opacity(0.45), in: RoundedRectangle(cornerRadius: 12 * scale))
                    .position(x: 166.5 * scale, y: 135.5 * scale)

                Button {
                    transition(to: task == 1 ? .taskOneQuestion : .taskTwoQuestion)
                } label: {
                    Text("开始\n游戏")
                        .arNativeText(size: 16, weight: .bold, scale: scale)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .frame(width: 75 * scale, height: 75 * scale)
                        .background(Color(red: 0, green: 0.76, blue: 0.82), in: RoundedRectangle(cornerRadius: 13 * scale))
                        .shadow(color: .black.opacity(0.18), radius: 5 * scale, y: 3 * scale)
                }
                .buttonStyle(.plain)
                .position(x: 340.5 * scale, y: 135.5 * scale)
            }
        }
        .frame(width: 402 * scale, height: (expanded ? 256 : 74) * scale)
        .position(x: 201 * scale, y: (expanded ? 128 : 37) * scale)
    }

    private func questionPage(task: Int, scale: CGFloat) -> some View {
        ZStack {
            questionTopPanel(task: task, scale: scale)

            RoundedRectangle(cornerRadius: 10 * scale)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10 * scale)
                        .fill(Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255).opacity(0.60))
                )
                .frame(width: 366 * scale, height: 335 * scale)
                .position(x: 201 * scale, y: 421.5 * scale)
                .allowsHitTesting(false)

            kakaChoices(task: task, scale: scale)

            RoundedRectangle(cornerRadius: 10 * scale)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10 * scale)
                        .fill(Color(red: 231 / 255, green: 239 / 255, blue: 239 / 255).opacity(0.86))
                )
                .frame(width: 402 * scale, height: 258 * scale)
                .position(x: 201 * scale, y: 745 * scale)
                .allowsHitTesting(false)

            Text(
                isHoldingToSpeak || !speech.transcript.isEmpty
                    ? (speech.transcript.isEmpty ? "正在聆听…" : speech.transcript)
                    : "请你念出你现在的KAKA序号，说出哪几个KAKA现在是高兴的呢？"
            )
                .arNativeText(size: 10, scale: scale)
                .foregroundStyle(arInk)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: 333 * scale, height: 34 * scale)
                .background(
                    (isHoldingToSpeak || !speech.transcript.isEmpty)
                        ? Color.white.opacity(0.58)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10 * scale)
                )
                .position(x: 201.5 * scale, y: 644 * scale)
                .allowsHitTesting(false)

            bottomExitButton(scale: scale)
        }
    }

    private func questionTopPanel(task: Int, scale: CGFloat) -> some View {
        let regularPrompt = task == 1
            ? "请你找出画面中高兴的KAKA，它的身上藏着鼹鼠先生需要的桃花！"
            : "听声音，找出画面中语气表示开心的KAKA，它的身上有鼹鼠先生需要的荷花！"
        let correct = step == .taskOneCorrect || step == .taskTwoCorrect
        let displayedPrompt: String
        if correct {
            displayedPrompt = "恭喜你都答对了！你是最棒的小朋友~"
        } else if !answerFeedback.isEmpty {
            displayedPrompt = answerFeedback
        } else {
            displayedPrompt = regularPrompt
        }
        let isWrong = !answerFeedback.isEmpty
        let promptWidth: CGFloat = isWrong ? 238 : 222
        let promptHeight: CGFloat = isWrong ? 58 : 62
        let promptX: CGFloat = isWrong ? 150 : 163
        let kakaX: CGFloat = isWrong ? 324.5 : 327.5

        return ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(red: 196 / 255, green: 1, blue: 249 / 255),
                            .white.opacity(0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(width: 402 * scale, height: 173 * scale)

            Text(displayedPrompt)
                .arNativeText(size: 16, scale: scale)
                .foregroundStyle(arInk)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .frame(width: promptWidth * scale, height: promptHeight * scale)
                .position(x: promptX * scale, y: 107 * scale)

            KakaAvatarView(magnification: 1.26)
                .frame(width: 107 * scale, height: 107 * scale)
                .position(x: kakaX * scale, y: 119.5 * scale)

            Capsule()
                .fill(Color.gray.opacity(0.48))
                .frame(width: 65 * scale, height: 6 * scale)
                .position(x: 197.5 * scale, y: 166 * scale)
        }
        .frame(width: 402 * scale, height: 173 * scale)
        .position(x: 201 * scale, y: 86.5 * scale)
        .allowsHitTesting(false)
    }

    private func kakaChoices(task: Int, scale: CGFloat) -> some View {
        let choices: [(name: String, x: CGFloat, y: CGFloat, size: CGFloat, number: Int)] = [
            ("ar_kaka_5", 102.5, 318.5, 107, 1),
            ("ar_kaka_4", 297.5, 313.5, 107, 2),
            ("ar_kaka_2", 221.5, 431.5, 81, 3),
            ("ar_kaka_1", 95.5, 481.5, 107, 4),
            ("ar_kaka_3", 324.5, 535.5, 107, 5)
        ]

        return ZStack {
            ForEach(choices, id: \.number) { choice in
                ZStack {
                    Image(choice.name)
                        .resizable()
                        .scaledToFit()
                        .frame(width: choice.size * scale, height: choice.size * scale)

                    Text("\(choice.number)号")
                        .arNativeText(size: 16, weight: .bold, scale: scale)
                        .foregroundStyle(.white)
                        .offset(y: 17 * scale)

                    if task == 2 {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 17 * scale, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: arInk.opacity(0.35), radius: 2)
                            .offset(x: choice.size * 0.39 * scale, y: -choice.size * 0.36 * scale)
                    }
                }
                .frame(width: choice.size * scale, height: choice.size * scale)
                .position(x: choice.x * scale, y: choice.y * scale)
            }

            if step == .taskOneCorrect || step == .taskTwoCorrect {
                Circle()
                    .fill(Color(red: 0, green: 0.76, blue: 0.82).opacity(0.94))
                    .frame(width: 212 * scale, height: 212 * scale)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 92 * scale, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .position(x: 201 * scale, y: 445 * scale)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }

    private func holdToSpeakLayer(scale: CGFloat) -> some View {
        ZStack {
            voiceWaveform(scale: scale)
                .position(x: 201 * scale, y: 692.5 * scale)

            RoundedRectangle(cornerRadius: 10 * scale)
                .fill(Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255))
                .frame(width: 189 * scale, height: 24 * scale)
                .position(x: 201.5 * scale, y: 798 * scale)
                .allowsHitTesting(false)

            microphoneVisual(scale: scale)
                .allowsHitTesting(false)
                .position(x: 201.5 * scale, y: 779.5 * scale)

            Color.clear
            .frame(width: 89 * scale, height: 89 * scale)
            .contentShape(Circle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        beginVoiceCapture()
                    }
                    .onEnded { _ in
                        endVoiceCapture()
                    }
            )
            .position(x: 201.5 * scale, y: 779.5 * scale)
            .accessibilityLabel("按住说话")
            .accessibilityHint("按住开始录音，松开完成语音转写")
        }
    }

    private func voiceWaveform(scale: CGFloat) -> some View {
        let figmaHeights: [CGFloat] = [
            35, 23, 15, 9, 15, 23, 35, 47, 37, 27,
            17, 9, 5, 13, 5, 5, 13, 21, 31, 41,
            53, 45, 35, 25, 15, 7, 13, 21, 31, 21, 11
        ]

        return HStack(spacing: 4 * scale) {
            ForEach(figmaHeights.indices, id: \.self) { index in
                let activeAdjustment = CGFloat((index * 7) % 16 - 8)
                let activeHeight = min(max(figmaHeights[index] + activeAdjustment, 5), 53)
                Capsule()
                    .fill(Color(red: 0, green: 0.76, blue: 0.82))
                    .frame(
                        width: 4 * scale,
                        height: (isHoldingToSpeak ? activeHeight : figmaHeights[index]) * scale
                    )
                    .animation(
                        isHoldingToSpeak
                            ? .easeInOut(duration: 0.24 + Double(index % 5) * 0.035)
                                .repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.18),
                        value: isHoldingToSpeak
                    )
            }
        }
        .frame(width: 244 * scale, height: 55 * scale)
        .allowsHitTesting(false)
    }

    private func microphoneVisual(scale: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(red: 0, green: 195 / 255, blue: 208 / 255))
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.72), lineWidth: 1.4 * scale)
                }
                .shadow(color: .black.opacity(0.24), radius: 4 * scale, y: 3 * scale)

            Image(systemName: "mic")
                .font(.system(size: 35 * scale, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .frame(width: 48 * scale, height: 48 * scale)
        }
            .frame(width: 109.4 * scale, height: 109.4 * scale)
    }

    private func beginVoiceCapture() {
        guard !isHoldingToSpeak, isQuestionStep else { return }
        answerFeedback = ""
        speech.transcript = ""
        isHoldingToSpeak = speech.start()
    }

    private func endVoiceCapture() {
        guard isHoldingToSpeak else { return }
        isHoldingToSpeak = false
        speech.finishCapture()
        Task {
            try? await Task.sleep(for: .milliseconds(1100))
            submitSpokenAnswer()
        }
    }

    private func submitSpokenAnswer() {
        guard isQuestionStep else { return }

        let spoken = speech.transcript
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: "、", with: "")

        guard !spoken.isEmpty else {
            speech.cancel()
            answerFeedback = "没有听清，请按住话筒再说一次"
            return
        }

        let fourExpressions = ["4号", "四号", "第四", "4", "四", "肆"]
        let fiveExpressions = ["5号", "五号", "第五", "5", "五", "伍"]
        let isCorrect =
            fourExpressions.contains(where: spoken.contains) ||
            fiveExpressions.contains(where: spoken.contains)

        speech.cancel()
        speech.transcript = ""

        if isCorrect {
            let correctStep: Step = isTaskTwo ? .taskTwoCorrect : .taskOneCorrect
            let rewardStep: Step = isTaskTwo ? .taskTwoReward : .taskOneReward
            withAnimation(.spring(duration: 0.38, bounce: 0.18)) {
                step = correctStep
                answerFeedback = ""
            }
            Task {
                try? await Task.sleep(for: .milliseconds(1050))
                transition(to: rewardStep)
            }
        } else {
            answerFeedback = isTaskTwo
                ? "想想看，哪些个卡卡的声音更上扬？"
                : "想想看，哪些个卡卡的嘴巴是向上翘的呢？"
        }
    }

    private func rewardPage(task: Int, scale: CGFloat) -> some View {
        let asset = task == 1 ? "ar_peach_reward" : "ar_lotus_reward"
        let plantName = task == 1 ? "桃 花" : "荷 花"
        let romanized = task == 1 ? "táo huā" : "hé huā"
        let description = task == 1
            ? "风一吹，桃花就晃着小脑袋跳舞，看见它的小朋友，坏心情一下子就被赶跑啦！"
            : "荷叶托着粉嘟嘟的荷花，风一吹轻轻晃，瞧见它，心情就软软的、甜甜的。"

        return ZStack {
            taskHeader(task: task, expanded: false, scale: scale)

            ZStack {
                RoundedRectangle(cornerRadius: 10 * scale)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 254 / 255, green: 212 / 255, blue: 215 / 255).opacity(0.90),
                                Color(red: 192 / 255, green: 251 / 255, blue: 1).opacity(0.90)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 242 * scale, height: 348 * scale)
                    .position(x: 141 * scale, y: 244 * scale)

                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 222 * scale, height: 300 * scale)
                    .position(x: 144.25 * scale, y: 240 * scale)
                    .allowsHitTesting(false)

                LinearGradient(
                    colors: [
                        .clear,
                        Color(red: 118 / 255, green: 207 / 255, blue: 213 / 255).opacity(0.50),
                        Color(red: 0, green: 195 / 255, blue: 208 / 255)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 242 * scale, height: 96 * scale)
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 10 * scale,
                        bottomTrailingRadius: 10 * scale
                    )
                )
                .position(x: 141 * scale, y: 370 * scale)
                .allowsHitTesting(false)

                Text(romanized)
                    .arNativeText(size: 16, scale: scale)
                    .foregroundStyle(.white)
                    .position(x: 137 * scale, y: 85.5 * scale)

                Text(plantName)
                    .arNativeText(size: 16, scale: scale)
                    .foregroundStyle(.white)
                    .position(x: 137 * scale, y: 106.5 * scale)

                Text(description)
                    .arNativeText(size: 10, lineHeight: 12, scale: scale)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 218 * scale, height: 44 * scale)
                    .position(x: 137 * scale, y: 396 * scale)

                Image("ar_new_plant_badge")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 111 * scale, height: 111 * scale)
                    .rotationEffect(.degrees(-30))
                    .position(x: 265 * scale, y: 66 * scale)
                    .allowsHitTesting(false)

                VStack(spacing: 1 * scale) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14 * scale, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text("新植物！")
                        .arNativeText(size: 16, scale: scale)
                        .foregroundStyle(arInk)
                        .multilineTextAlignment(.center)
                        .frame(width: 88 * scale, alignment: .center)
                }
                .frame(width: 96 * scale, alignment: .center)
                .position(x: 265 * scale, y: 70.5 * scale)
                .allowsHitTesting(false)
            }
            .frame(width: 326 * scale, height: 460 * scale)
            .position(x: 201 * scale, y: 437 * scale)

            speechBubble(
                "太棒了！鼹鼠先生赠送了一株\(task == 1 ? "桃花" : "荷花")给你，你可以把它布置在房间里~",
                width: 248,
                height: 69,
                scale: scale
            )
            .position(x: 201 * scale, y: 745.5 * scale)

            KakaAvatarView(magnification: 1.26)
                .frame(width: 107 * scale, height: 107 * scale)
                .position(x: 348.5 * scale, y: 803.5 * scale)

            Button {
                transition(to: task == 1 ? .taskOnePlacement : .taskTwoPlacement)
            } label: {
                Color.clear
                    .frame(width: 326 * scale, height: 460 * scale)
                    .contentShape(RoundedRectangle(cornerRadius: 18 * scale))
            }
            .buttonStyle(.plain)
            .position(x: 201 * scale, y: 437 * scale)

            bottomBackButton(scale: scale) {
                transition(to: task == 1 ? .taskOneQuestion : .taskTwoQuestion)
            }
        }
    }

    private func placementPage(task: Int, scale: CGFloat) -> some View {
        let asset = task == 1 ? "ar_peach_reward" : "ar_lotus_reward"
        let label = task == 1 ? "桃花" : "荷花"

        return ZStack {
            taskHeader(task: task, expanded: false, scale: scale)

            speechBubble(
                rewardWasPlaced
                    ? (
                        task == 1
                            ? "放在这里和房间非常的搭配呢，准备好了，让我们解锁下一关吧！"
                            : "放在这里和房间非常的搭配呢，两个任务都完成啦！"
                    )
                    : (
                        isDraggingReward
                            ? "拖到你喜欢的位置，松开手指就可以放下\(label)啦！"
                            : "把\(label)拖到房间里的任意位置吧！"
                    ),
                width: 248,
                height: 69,
                scale: scale
            )
            .position(x: 205 * scale, y: 745.5 * scale)
            .allowsHitTesting(false)

            KakaAvatarView(magnification: 1.26)
                .frame(width: 107 * scale, height: 107 * scale)
                .position(x: 348.5 * scale, y: 803.5 * scale)
                .allowsHitTesting(false)

            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(
                    width: (task == 1 ? 104 : 130) * scale,
                    height: (task == 1 ? 141 : 175) * scale
                )
                .scaleEffect(isDraggingReward ? 1.08 : 1)
                .shadow(color: .black.opacity(isDraggingReward ? 0.24 : 0.14), radius: 8 * scale, y: 4 * scale)
                .position(
                    x: 201 * scale + rewardDragOffset.width,
                    y: 420 * scale + rewardDragOffset.height
                )
                .opacity(rewardWasPlaced ? 0 : 1)
                .allowsHitTesting(!rewardWasPlaced)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(coordinateSpace: .named("arCanvas"))
                        .onChanged { value in
                            guard !rewardWasPlaced else { return }
                            isDraggingReward = true
                            rewardDragOffset = clampedRewardTranslation(value.translation, scale: scale)
                        }
                        .onEnded { value in
                            guard !rewardWasPlaced else { return }
                            isDraggingReward = false
                            rewardDragOffset = clampedRewardTranslation(value.translation, scale: scale)
                            // Anchor the AR raycast to the visible plant base in the
                            // scaled reward artwork, so it does not jump after release.
                            let rootOffset = task == 1
                                ? CGSize(width: -0.468, height: 65.52)
                                : CGSize(width: 0.293, height: 57.33)
                            let dropPoint = CGPoint(
                                x: (201 + rootOffset.width) * scale + rewardDragOffset.width,
                                y: (420 + rootOffset.height) * scale + rewardDragOffset.height
                            )
                            let didPlace = scene.placeRewardPlant(
                                at: dropPoint,
                                kind: task == 1 ? .peach : .lotus
                            )
                            guard didPlace else { return }
                            rewardWasPlaced = true

                            Task {
                                do {
                                    try await Task.sleep(for: .milliseconds(1800))
                                } catch {
                                    return
                                }
                                let expectedStep: Step = task == 1
                                    ? .taskOnePlacement
                                    : .taskTwoPlacement
                                guard step == expectedStep, rewardWasPlaced else { return }
                                transition(to: task == 1 ? .taskTwoBrief : .ar17GardenIntro)
                            }
                        }
                )
                .accessibilityLabel("\(label)奖励，拖动到房间任意位置")

            if rewardWasPlaced {
                Image("ar_new_plant_badge")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76 * scale, height: 76 * scale)
                    .rotationEffect(.degrees(-30))
                    .overlay {
                        Text("新植物！")
                            .arNativeText(size: 10, scale: scale)
                            .foregroundStyle(arInk)
                            .multilineTextAlignment(.center)
                            .frame(width: 62 * scale, alignment: .center)
                    }
                    .position(x: 320 * scale, y: 252 * scale)
                    .allowsHitTesting(false)
            }

            bottomBackButton(scale: scale) {
                transition(to: task == 1 ? .taskOneReward : .taskTwoReward)
            }
        }
    }

    private func clampedRewardTranslation(_ translation: CGSize, scale: CGFloat) -> CGSize {
        CGSize(
            width: min(max(translation.width, -145 * scale), 145 * scale),
            height: min(max(translation.height, -270 * scale), 270 * scale)
        )
    }

    private enum GardenInteractionMode {
        case menu
        case plants
        case sound
    }

    private func ar17GardenIntroPage(scale: CGFloat) -> some View {
        ZStack {
            gardenPlantLayer(mode: .menu, scale: scale)

            Button {
                transition(to: .ar18Garden)
            } label: {
                speechBubble(
                    "这里就是我们的秘密基地啦~你可以和植物们一起互动哦！",
                    width: 248,
                    height: 69,
                    scale: scale
                )
            }
            .buttonStyle(.plain)
            .position(x: 181 * scale, y: 653.5 * scale)

            KakaAvatarView(magnification: 1.26)
                .frame(width: 107 * scale, height: 107 * scale)
                .position(x: 327.5 * scale, y: 716.5 * scale)
                .allowsHitTesting(false)

            bottomBackButton(scale: scale) {
                transition(to: .taskTwoPlacement)
            }

            arWorldHomeButton(scale: scale)
                .position(x: 366 * scale, y: 90 * scale)
        }
        .onAppear {
            scene.setGardenInteraction(isEditing: false, reactsToSound: false)
        }
    }

    private func interactiveGardenPage(mode: GardenInteractionMode, scale: CGFloat) -> some View {
        ZStack {
            gardenPlantLayer(mode: mode, scale: scale)

            VStack(spacing: 17 * scale) {
                gardenRoundControl(
                    symbol: "leaf.fill",
                    selected: mode == .plants,
                    scale: scale
                ) {
                    transition(to: mode == .plants ? .ar21PlantCollection : .ar19PlantInteraction)
                }

                gardenRoundControl(
                    symbol: mode == .sound ? "speaker.wave.3.fill" : "speaker.wave.2.fill",
                    selected: mode == .sound,
                    scale: scale
                ) {
                    transition(to: .ar20SoundInteraction)
                }

                gardenRoundControl(symbol: "plus", selected: false, scale: scale) {
                    transition(to: .ar17GardenIntro)
                }
            }
            .position(x: 341 * scale, y: 734 * scale)

            if mode == .plants {
                Text("拖动植物可以调整它在 AR 世界中的位置")
                    .arNativeText(size: 12, scale: scale)
                    .foregroundStyle(arInk)
                    .multilineTextAlignment(.center)
                    .frame(width: 224 * scale, height: 42 * scale)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14 * scale))
                    .position(x: 165 * scale, y: 650 * scale)
            } else if mode == .sound {
                HStack(spacing: 4 * scale) {
                    Image(systemName: "waveform")
                    Text("植物正在回应声音")
                }
                .arNativeText(size: 12, scale: scale)
                .foregroundStyle(arInk)
                .frame(width: 196 * scale, height: 42 * scale)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14 * scale))
                .position(x: 160 * scale, y: 650 * scale)
            }

            bottomBackButton(scale: scale) {
                transition(to: .ar17GardenIntro)
            }

            arWorldHomeButton(scale: scale)
                .position(x: 366 * scale, y: 90 * scale)
        }
        .onAppear {
            scene.setGardenInteraction(
                isEditing: mode == .plants,
                reactsToSound: mode == .sound
            )
        }
    }

    private func gardenRoundControl(
        symbol: String,
        selected: Bool,
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 29 * scale, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 60 * scale, height: 60 * scale)
                .background(
                    selected
                        ? Color(red: 0, green: 195 / 255, blue: 208 / 255).opacity(0.92)
                        : Color.white.opacity(0.24),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.82), lineWidth: 1.5 * scale)
                }
                .shadow(color: .white.opacity(0.9), radius: 8 * scale)
        }
        .buttonStyle(.plain)
    }

    private func gardenPlantLayer(mode: GardenInteractionMode, scale: CGFloat) -> some View {
        Color.clear
            .frame(width: 402 * scale, height: 874 * scale)
            .allowsHitTesting(false)
    }

    private func plantCollectionPage(scale: CGFloat) -> some View {
        let plants: [(String, String, String, String)] = [
            ("桃 花", "táo huā", "ar_peach_reward", "风一吹，桃花就晃着小脑袋跳舞，看见它，坏心情一下子就被赶跑啦！"),
            ("荷 花", "hé huā", "ar_lotus_reward", "荷叶托着粉嘟嘟的荷花，风一吹轻轻晃，心情也甜甜的。")
        ]

        return ZStack {
            RoundedRectangle(cornerRadius: 10 * scale)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 10 * scale)
                        .fill(Color.white.opacity(0.72))
                }
                .frame(width: 354 * scale, height: 780 * scale)
                .shadow(color: .black.opacity(0.18), radius: 9 * scale, y: 4 * scale)
                .position(x: 201 * scale, y: 450 * scale)

            VStack(spacing: 7 * scale) {
                Text("植物收集屋")
                    .arNativeText(size: 16, weight: .bold, scale: scale)
                    .foregroundStyle(.white)
                    .frame(width: 136 * scale, height: 29 * scale)
                    .background(
                        Color(red: 0, green: 195 / 255, blue: 208 / 255).opacity(0.75),
                        in: Capsule()
                    )
                    .shadow(color: .black.opacity(0.16), radius: 4 * scale, y: 2 * scale)

                Text("这里收集着所有我们拥有的植物，你可以选择自己喜欢的并放置在自己的世界里~")
                    .arNativeText(size: 10, lineHeight: 14, scale: scale)
                    .foregroundStyle(arInk)
                    .multilineTextAlignment(.center)
                    .frame(width: 230 * scale, height: 34 * scale)
            }
            .position(x: 182 * scale, y: 112 * scale)

            KakaAvatarView(magnification: 1.26)
                .frame(width: 107 * scale, height: 107 * scale)
                .position(x: 321.5 * scale, y: 127.5 * scale)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [
                        GridItem(.fixed(159 * scale), spacing: 16 * scale),
                        GridItem(.fixed(159 * scale))
                    ],
                    spacing: 10 * scale
                ) {
                    ForEach(plants.indices, id: \.self) { index in
                        plantCollectionCard(
                            name: plants[index].0,
                            romanized: plants[index].1,
                            asset: plants[index].2,
                            description: plants[index].3,
                            scale: scale
                        )
                    }
                }
            }
            .frame(width: 334 * scale, height: 651 * scale)
            .position(x: 202 * scale, y: 502.5 * scale)

            Button {
                transition(to: .ar19PlantInteraction)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 24 * scale, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.62))
                    .frame(width: 44 * scale, height: 44 * scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: 358 * scale, y: 81 * scale)

            arWorldHomeButton(scale: scale)
            .position(x: 88 * scale, y: 81 * scale)
        }
    }

    private func plantCollectionCard(
        name: String,
        romanized: String,
        asset: String,
        description: String,
        scale: CGFloat
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10 * scale)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 254 / 255, green: 212 / 255, blue: 215 / 255).opacity(0.90),
                            Color(red: 192 / 255, green: 251 / 255, blue: 1).opacity(0.90)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 0) {
                Text(romanized)
                    .arNativeText(size: 10, scale: scale)
                Text(name)
                    .arNativeText(size: 16, scale: scale)

                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 141 * scale, height: 132 * scale)
            }
            .foregroundStyle(.white)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 4 * scale)

            LinearGradient(
                colors: [
                    .clear,
                    Color(red: 0, green: 195 / 255, blue: 208 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 63 * scale)
            .clipShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 10 * scale,
                    bottomTrailingRadius: 10 * scale
                )
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            Text(description)
                .arNativeText(size: 10, lineHeight: 12, scale: scale)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .frame(width: 145 * scale, height: 42 * scale)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 4 * scale)
        }
        .frame(width: 159 * scale, height: 228 * scale)
        .shadow(color: .black.opacity(0.18), radius: 4 * scale, y: 3 * scale)
    }

    private func speechBubble(
        _ text: String,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat
    ) -> some View {
        Text(text)
            .arNativeText(size: 14, scale: scale)
            .foregroundStyle(arInk)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 9 * scale)
            .frame(width: width * scale, height: height * scale)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16 * scale))
    }

    private func bottomBackButton(scale: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 24 * scale, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56 * scale, height: 56 * scale)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .position(x: 36 * scale, y: 828 * scale)
    }

    private func arWorldHomeButton(scale: CGFloat) -> some View {
        Button {
            transition(to: .landing)
        } label: {
            Image(systemName: "house.fill")
                .font(.system(size: 21 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48 * scale, height: 48 * scale)
            .background(
                Color(red: 0, green: 195 / 255, blue: 208 / 255).opacity(0.82),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.72), lineWidth: 1 * scale)
            }
            .shadow(color: .black.opacity(0.14), radius: 4 * scale, y: 2 * scale)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回AR世界主页")
    }

    private func bottomExitButton(scale: CGFloat) -> some View {
        Button {
            speech.cancel()
            isHoldingToSpeak = false
            transition(to: .landing)
        } label: {
            Text("退出")
                .arNativeText(size: 16, scale: scale)
                .foregroundStyle(.white)
                .frame(width: 53 * scale, height: 53 * scale)
                .background(Color(red: 0.32, green: 0.77, blue: 0.78).opacity(0.62), in: Circle())
        }
        .buttonStyle(.plain)
        .position(x: 344.5 * scale, y: 832.5 * scale)
    }

    private func transition(to destination: Step) {
        if destination == .taskOneBrief {
            scene.resetRewards()
        }
        if destination == .taskOneBrief || destination == .taskTwoBrief {
            taskPanelReveal = 0
            taskPanelDragStart = nil
        }
        switch destination {
        case .ar19PlantInteraction:
            scene.setGardenInteraction(isEditing: true, reactsToSound: false)
        case .ar20SoundInteraction:
            scene.setGardenInteraction(isEditing: false, reactsToSound: true)
        default:
            scene.setGardenInteraction(isEditing: false, reactsToSound: false)
        }
        speech.cancel()
        speech.transcript = ""
        isHoldingToSpeak = false
        answerFeedback = ""
        rewardDragOffset = .zero
        isDraggingReward = false
        rewardWasPlaced = false
        onTaskFlowChanged(destination != .landing)
        withAnimation(.easeInOut(duration: 0.3)) {
            step = destination
        }
    }

    private var arInk: Color {
        Color(red: 0, green: 80 / 255, blue: 86 / 255)
    }
}

private enum ARNativeFontWeight {
    case medium
    case semibold
    case bold

    var gardenWeight: GardenFontWeight {
        switch self {
        case .medium: .medium
        case .semibold: .bold
        case .bold: .bold
        }
    }

    var postScriptName: String {
        gardenWeight.postScriptName
    }
}

private struct ARNativeTextModifier: ViewModifier {
    let size: CGFloat
    let weight: ARNativeFontWeight
    let lineHeight: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        let renderedSize = size * scale
        let renderedLineHeight = lineHeight * scale
        let naturalLineHeight = UIFont(
            name: weight.postScriptName,
            size: renderedSize
        )?.lineHeight ?? renderedSize

        content
            .gardenFont(size: renderedSize, weight: weight.gardenWeight)
            .tracking(size * 0.058 * scale)
            .lineSpacing(max(0, renderedLineHeight - naturalLineHeight))
    }
}

private extension View {
    func arNativeText(
        size: CGFloat,
        weight: ARNativeFontWeight = .medium,
        lineHeight: CGFloat = 22,
        scale: CGFloat
    ) -> some View {
        modifier(
            ARNativeTextModifier(
                size: size,
                weight: weight,
                lineHeight: lineHeight,
                scale: scale
            )
        )
    }
}

private struct ARGardenContainer: UIViewRepresentable {
    @ObservedObject var scene: ARGardenScene

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        scene.connect(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

private enum ARAnimationAsset: String, Hashable, CaseIterable {
    case lotus = "ar_plant_lotus"
    case peach = "ar_plant_peach"

    var canvasSize: CGSize {
        switch self {
        case .lotus: CGSize(width: 240, height: 320)
        case .peach: CGSize(width: 324, height: 240)
        }
    }

    var phaseOffset: TimeInterval {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return Double(index) * 0.01
    }

    // Union of all 51 transparent-frame bounds. Keeping the original canvas
    // prevents the growing animations from jumping between frames.
    var contentBounds: CGRect {
        switch self {
        case .lotus: CGRect(x: 37, y: 107, width: 182, height: 153)
        case .peach: CGRect(x: 62, y: 0, width: 200, height: 226)
        }
    }
}

private enum ARPlantKind: String {
    case lotus
    case peach

    var animation: ARAnimationAsset {
        switch self {
        case .lotus: .lotus
        case .peach: .peach
        }
    }

    var visibleHeight: Float {
        switch self {
        case .lotus: 0.24
        case .peach: 0.36
        }
    }
}

private struct ARAnimationPlaneLayout {
    let planeWidth: Float
    let planeHeight: Float
    let centerX: Float
    let centerY: Float
    let visibleWidth: Float
}

@MainActor
private final class ARPlantAnimationClip {
    let texture: TextureResource

    private let data: Data
    private let source: CGImageSource
    private let frameDurations: [TimeInterval]
    private let totalDuration: TimeInterval
    private var elapsed: TimeInterval = 0
    private var displayedFrameIndex = 0

    init?(asset: ARAnimationAsset) {
        guard
            let dataAsset = NSDataAsset(name: asset.rawValue),
            let imageSource = CGImageSourceCreateWithData(
                dataAsset.data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ),
            CGImageSourceGetCount(imageSource) > 0,
            let sourceFrame = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
            let firstFrame = Self.normalizedRGBAFrame(sourceFrame)
        else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(imageSource)
        let durations = (0..<frameCount).map { index in
            Self.frameDuration(source: imageSource, index: index)
        }
        let options = TextureResource.CreateOptions(
            semantic: .color,
            mipmapsMode: .none
        )

        guard let generatedTexture = try? TextureResource.generate(
            from: firstFrame,
            withName: asset.rawValue,
            options: options
        ) else {
            return nil
        }

        data = dataAsset.data
        source = imageSource
        frameDurations = durations
        totalDuration = max(durations.reduce(0, +), 0.1)
        elapsed = asset.phaseOffset.truncatingRemainder(dividingBy: totalDuration)
        texture = generatedTexture
    }

    func layout(asset: ARAnimationAsset, visibleHeight: Float) -> ARAnimationPlaneLayout {
        let canvas = asset.canvasSize
        let bounds = asset.contentBounds
        let planeHeight = visibleHeight * Float(canvas.height / bounds.height)
        let planeWidth = planeHeight * Float(canvas.width / canvas.height)
        let centerX = Float(0.5 - bounds.midX / canvas.width) * planeWidth
        let centerY = Float(bounds.maxY / canvas.height - 0.5) * planeHeight
        let visibleWidth = visibleHeight * Float(bounds.width / bounds.height)

        return ARAnimationPlaneLayout(
            planeWidth: planeWidth,
            planeHeight: planeHeight,
            centerX: centerX,
            centerY: centerY,
            visibleWidth: visibleWidth
        )
    }

    func advance(by deltaTime: TimeInterval) {
        guard frameDurations.count > 1 else { return }

        elapsed = (elapsed + deltaTime).truncatingRemainder(dividingBy: totalDuration)
        var frameIndex = 0
        var cursor: TimeInterval = 0

        for duration in frameDurations {
            if elapsed < cursor + duration { break }
            cursor += duration
            frameIndex += 1
        }
        frameIndex = min(frameIndex, frameDurations.count - 1)
        guard frameIndex != displayedFrameIndex else { return }
        guard
            let sourceFrame = CGImageSourceCreateImageAtIndex(source, frameIndex, nil),
            let frame = Self.normalizedRGBAFrame(sourceFrame)
        else {
            return
        }

        let options = TextureResource.CreateOptions(
            semantic: .color,
            mipmapsMode: .none
        )
        do {
            try texture.replace(withImage: frame, options: options)
            displayedFrameIndex = frameIndex
        } catch {
            // Keep the last valid frame; the next update can retry.
        }
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any],
            let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1
        }

        let unclamped = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
        let clamped = (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
        return max(unclamped ?? clamped ?? 0.1, 0.06)
    }

    private static func normalizedRGBAFrame(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
            CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

@MainActor
private final class ARGardenScene: NSObject, ObservableObject, ARSessionDelegate {
    private weak var arView: ARView?
    private var rewardAnchors: [ARPlantKind: AnchorEntity] = [:]
    private var rewardRoots: [ARPlantKind: ModelEntity] = [:]
    private var plantRoots: [ModelEntity] = []
    private var rootAnimationAssets: [ObjectIdentifier: Set<ARAnimationAsset>] = [:]
    private var animationAssetUseCounts: [ARAnimationAsset: Int] = [:]
    private var plantGestures: [UIGestureRecognizer] = []
    private var clips: [ARAnimationAsset: ARPlantAnimationClip] = [:]
    private var updateSubscription: (any Cancellable)?
    private var isEditingGarden = false
    private var reactsToSound = false
    private var soundPhase: TimeInterval = 0

    func connect(to view: ARView) {
        if let oldView = arView, oldView !== view {
            plantGestures.forEach { oldView.removeGestureRecognizer($0) }
            plantGestures.removeAll()
            updateSubscription?.cancel()
        }

        arView = view
        view.automaticallyConfigureSession = false
        view.session.delegate = self
        runSession(on: view)

        for anchor in rewardAnchors.values {
            anchor.removeFromParent()
            view.scene.addAnchor(anchor)
        }
        reinstallPlantGestures()
        subscribeToSceneUpdates(on: view)
    }

    func resume() {
        guard let arView else { return }
        runSession(on: arView)
    }

    private func runSession(on view: ARView) {
        guard ARWorldTrackingConfiguration.isSupported else { return }

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        view.session.run(configuration)
    }

    func pause() {
        arView?.session.pause()
    }

    func resetRewards() {
        rewardAnchors.values.forEach { $0.removeFromParent() }
        Array(rewardRoots.values).forEach(removePlantRoot)
        rewardAnchors.removeAll()
        rewardRoots.removeAll()
        clips.removeAll()
        reinstallPlantGestures()
    }

    @discardableResult
    func placeRewardPlant(at screenPoint: CGPoint, kind: ARPlantKind) -> Bool {
        guard let arView else { return false }
        let point = CGPoint(
            x: min(max(screenPoint.x, 0), arView.bounds.width),
            y: min(max(screenPoint.y, 0), arView.bounds.height)
        )

        guard let transform = placementTransform(
            at: point,
            alignment: .any,
            fallbackOffset: SIMD3(0, -0.22, -0.8)
        ) else { return false }
        guard let root = makeAnimatedPlant(kind: kind) else { return false }

        let anchor = AnchorEntity(world: transform)
        anchor.addChild(root)

        rewardAnchors[kind]?.removeFromParent()
        if let previousRoot = rewardRoots[kind] {
            removePlantRoot(previousRoot)
        }

        arView.scene.addAnchor(anchor)
        rewardAnchors[kind] = anchor
        rewardRoots[kind] = root
        reinstallPlantGestures()
        return true
    }

    func setGardenInteraction(isEditing: Bool, reactsToSound: Bool) {
        isEditingGarden = isEditing
        self.reactsToSound = reactsToSound
        plantGestures.forEach { $0.isEnabled = isEditing }

        if !reactsToSound {
            plantRoots.forEach { $0.scale = SIMD3(repeating: 1) }
        }
    }

    private func makeAnimatedPlant(kind: ARPlantKind) -> ModelEntity? {
        guard
            let flowerClip = clip(for: kind.animation),
            let flowerPlane = makeAnimatedPlane(
                asset: kind.animation,
                clip: flowerClip,
                visibleHeight: kind.visibleHeight
            )
        else {
            return nil
        }

        let root = ModelEntity()
        root.name = "animated-plant-\(kind.rawValue)"

        root.addChild(flowerPlane.entity)
        root.collision = CollisionComponent(
            shapes: [
                ShapeResource.generateBox(
                    size: SIMD3(flowerPlane.visibleWidth, kind.visibleHeight, 0.035)
                )
                .offsetBy(translation: SIMD3(0, kind.visibleHeight / 2, 0))
            ]
        )
        registerPlantRoot(root, animationAssets: [kind.animation])
        return root
    }

    private func registerPlantRoot(
        _ root: ModelEntity,
        animationAssets: Set<ARAnimationAsset>
    ) {
        plantRoots.append(root)
        rootAnimationAssets[ObjectIdentifier(root)] = animationAssets
        for asset in animationAssets {
            animationAssetUseCounts[asset, default: 0] += 1
        }
    }

    private func removePlantRoot(_ root: ModelEntity) {
        plantRoots.removeAll { $0 === root }
        guard let assets = rootAnimationAssets.removeValue(
            forKey: ObjectIdentifier(root)
        ) else { return }

        for asset in assets {
            let remainingUses = max(0, animationAssetUseCounts[asset, default: 0] - 1)
            if remainingUses == 0 {
                animationAssetUseCounts.removeValue(forKey: asset)
            } else {
                animationAssetUseCounts[asset] = remainingUses
            }
        }
    }

    private func makeAnimatedPlane(
        asset: ARAnimationAsset,
        clip: ARPlantAnimationClip,
        visibleHeight: Float
    ) -> (entity: ModelEntity, visibleWidth: Float)? {
        let layout = clip.layout(asset: asset, visibleHeight: visibleHeight)
        var material = UnlitMaterial()
        material.color = .init(
            tint: .white,
            texture: .init(clip.texture)
        )
        material.blending = .transparent(opacity: .init(scale: 1))

        let entity = ModelEntity(
            mesh: .generatePlane(width: layout.planeWidth, height: layout.planeHeight),
            materials: [material]
        )
        entity.position = SIMD3(layout.centerX, layout.centerY, 0)
        return (entity, layout.visibleWidth)
    }

    private func clip(for asset: ARAnimationAsset) -> ARPlantAnimationClip? {
        if let clip = clips[asset] { return clip }
        guard let clip = ARPlantAnimationClip(asset: asset) else { return nil }
        clips[asset] = clip
        return clip
    }

    private func placementTransform(
        at point: CGPoint,
        alignment: ARRaycastQuery.TargetAlignment,
        fallbackOffset: SIMD3<Float>
    ) -> simd_float4x4? {
        guard let arView else { return nil }

        if let result = arView.raycast(
            from: point,
            allowing: .estimatedPlane,
            alignment: alignment
        ).first {
            var transform = matrix_identity_float4x4
            transform.columns.3 = result.worldTransform.columns.3
            return transform
        }

        if let ray = arView.ray(through: point) {
            let distance = max(simd_length(fallbackOffset), 0.55)
            let position = ray.origin + simd_normalize(ray.direction) * distance
            var transform = matrix_identity_float4x4
            transform.columns.3 = SIMD4(position.x, position.y, position.z, 1)
            return transform
        }

        guard let camera = arView.session.currentFrame?.camera.transform else { return nil }
        var transform = matrix_identity_float4x4
        transform.columns.3 = camera * SIMD4(fallbackOffset.x, fallbackOffset.y, fallbackOffset.z, 1)
        return transform
    }

    private func reinstallPlantGestures() {
        plantGestures.forEach { gesture in
            gesture.view?.removeGestureRecognizer(gesture)
        }
        plantGestures.removeAll()

        guard let arView else { return }
        plantRoots.forEach { installGesture(for: $0, in: arView) }
    }

    private func installGesture(for root: ModelEntity, in view: ARView) {
        let installed = view.installGestures(.translation, for: root)
        for gesture in installed {
            gesture.isEnabled = isEditingGarden
            plantGestures.append(gesture as UIGestureRecognizer)
        }
    }

    private func subscribeToSceneUpdates(on view: ARView) {
        updateSubscription?.cancel()
        updateSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self else { return }
            for (asset, clip) in self.clips
            where self.animationAssetUseCounts[asset, default: 0] > 0 {
                clip.advance(by: event.deltaTime)
            }
            self.updatePlantFacingAndSound(deltaTime: event.deltaTime)
        }
    }

    private func updatePlantFacingAndSound(deltaTime: TimeInterval) {
        guard
            let cameraTransform = arView?.session.currentFrame?.camera.transform
        else { return }

        soundPhase += deltaTime
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        for (index, root) in plantRoots.enumerated() {
            let position = root.position(relativeTo: nil)
            let horizontalDirection = SIMD2(
                cameraPosition.x - position.x,
                cameraPosition.z - position.z
            )
            if simd_length_squared(horizontalDirection) > 0.0001 {
                let yaw = atan2(horizontalDirection.x, horizontalDirection.y)
                root.orientation = simd_quatf(
                    angle: yaw,
                    axis: SIMD3(0, 1, 0)
                )
            }

            let pulse = reactsToSound
                ? Float(1 + sin(soundPhase * 4.2 + Double(index) * 0.7) * 0.035)
                : 1
            root.scale = SIMD3(repeating: pulse)
        }
    }
}

@MainActor
private final class GardenSpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isRecording = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasPermission = false
    private var hasInputTap = false

    func requestPermissions() async {
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        hasPermission = speechAllowed && microphoneAllowed
    }

    @discardableResult
    func start() -> Bool {
        hasPermission =
            SFSpeechRecognizer.authorizationStatus() == .authorized &&
            AVAudioApplication.shared.recordPermission == .granted

        guard hasPermission, !audioEngine.isRunning else {
            if !hasPermission {
                transcript = "请在系统设置中允许麦克风和语音识别权限"
            }
            return false
        }

        guard let recognizer, recognizer.isAvailable else {
            transcript = "语音识别暂不可用，请检查网络后再试"
            return false
        }

        cancel()
        transcript = ""

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.duckOthers, .defaultToSpeaker]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = false
            request.taskHint = .confirmation
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                transcript = "没有检测到可用麦克风，请再试一次"
                cancel()
                return false
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasInputTap = true

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result {
                        self?.transcript = result.bestTranscription.formattedString
                    } else if error != nil, self?.transcript.isEmpty == true {
                        self?.transcript = "没有听清，请按住话筒再说一次"
                    }
                }
            }
            return true
        } catch {
            cancel()
            transcript = "语音输入启动失败，请再试一次"
            return false
        }
    }

    func finishCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        removeInputTap()
        request?.endAudio()
        isRecording = false
    }

    func cancel() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        removeInputTap()
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func removeInputTap() {
        guard hasInputTap else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        hasInputTap = false
    }
}
