import AudioToolbox
import SwiftUI
import UIKit

struct SproutlyFlowerTicketFlowView: View {
    let snapshot: UIImage
    let plantCount: Int
    let capturedAt: Date
    let onRetake: () -> Void
    let onReturnToAR: () -> Void
    let onViewTickets: () -> Void

    @EnvironmentObject private var store: GardenStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .review
    @State private var pullOffset: CGFloat = 0
    @State private var savedRecord: FlowerTicketRecord?
    @State private var animationTask: Task<Void, Never>?
    @State private var saveFailed = false

    private enum Step: Equatable {
        case review
        case machine
        case printing
        case ready
        case pulling
        case complete
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / 402, proxy.size.height / 874)
            Group {
                if step == .review {
                    reviewScreen(scale: scale)
                } else {
                    generatorScreen(scale: scale)
                }
            }
            .frame(width: 402 * scale, height: 874 * scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .ignoresSafeArea()
        .onDisappear { animationTask?.cancel() }
    }

    private func reviewScreen(scale: CGFloat) -> some View {
        ZStack {
            Image(uiImage: snapshot)
                .resizable()
                .scaledToFill()
                .frame(width: 402 * scale, height: 874 * scale)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.38)],
                startPoint: .center,
                endPoint: .bottom
            )

            Button(action: onRetake) {
                Image("music_camera_back")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48 * scale, height: 48 * scale)
                    .musicGlossCircle(scale: scale)
            }
            .buttonStyle(.plain)
            .position(x: 48 * scale, y: 84 * scale)
            .accessibilityLabel("返回重拍")

            HStack(spacing: 46 * scale) {
                Button(action: onRetake) {
                    Label("重拍", systemImage: "arrow.triangle.2.circlepath.camera")
                        .gardenFont(size: 14 * scale, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 112 * scale, height: 48 * scale)
                        .background(.black.opacity(0.28), in: Capsule())
                        .musicGlossCapsule(scale: scale)
                }
                .buttonStyle(.plain)

                Button(action: startPrinting) {
                    Label("生成花签", systemImage: "checkmark")
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

    private func generatorScreen(scale: CGFloat) -> some View {
        ZStack {
            Image(uiImage: snapshot)
                .resizable()
                .scaledToFill()
                .frame(width: 402 * scale, height: 874 * scale)
                .clipped()
                .opacity(0.42)

            LinearGradient(
                colors: [
                    Color(red: 232 / 255, green: 247 / 255, blue: 240 / 255).opacity(0.76),
                    Color(red: 214 / 255, green: 235 / 255, blue: 224 / 255).opacity(0.40),
                    Color(red: 33 / 255, green: 69 / 255, blue: 56 / 255).opacity(0.48)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if step != .complete {
                Button(action: returnToReview) {
                    Image("music_camera_back")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48 * scale, height: 48 * scale)
                        .musicGlossCircle(scale: scale)
                }
                .buttonStyle(.plain)
                .position(x: 48 * scale, y: 84 * scale)
                .zIndex(20)
            }

            if step == .complete {
                completeScreen(scale: scale)
            } else {
                printingScreen(scale: scale)
            }
        }
    }

    private func printingScreen(scale: CGFloat) -> some View {
        let visibleHeight = currentVisibleHeight
        return ZStack {
            FlowerTicketCard(
                image: snapshot,
                number: nextTicketNumber,
                plantCount: plantCount,
                timestamp: capturedAt
            )
            .frame(width: 258 * scale, height: 626 * scale)
            .frame(width: 258 * scale, height: visibleHeight * scale, alignment: .top)
            .clipped()
            .position(
                x: 201 * scale,
                y: (204 + visibleHeight / 2) * scale
            )
            .contentShape(Rectangle())
            .highPriorityGesture(pullGesture(scale: scale))
            .zIndex(2)

            SproutlyTicketMachine()
                .frame(width: 304 * scale, height: 130 * scale)
                .position(x: 201 * scale, y: 163 * scale)
                .zIndex(4)

            Image("ticket_machine_slot_front")
                .resizable()
                .scaledToFit()
                .frame(width: 296 * scale, height: 18 * scale)
                .position(x: 201 * scale, y: 209 * scale)
                .zIndex(5)

            if step == .ready {
                ZStack {
                    Circle()
                        .fill(Color(red: 248 / 255, green: 244 / 255, blue: 230 / 255).opacity(0.96))
                    Circle()
                        .stroke(Color(red: 145 / 255, green: 194 / 255, blue: 173 / 255), lineWidth: 2 * scale)
                    Image("ticket_pull_arrow")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24 * scale, height: 24 * scale)
                }
                .frame(width: 52 * scale, height: 52 * scale)
                .shadow(color: Color(red: 31 / 255, green: 71 / 255, blue: 64 / 255).opacity(0.16), radius: 6 * scale, y: 4 * scale)
                .position(x: 201 * scale, y: (204 + visibleHeight - 24) * scale)
                .contentShape(Circle())
                .highPriorityGesture(pullGesture(scale: scale))
                .transition(.scale.combined(with: .opacity))
                .zIndex(8)
            }
        }
        .animation(
            reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.38),
            value: step
        )
    }

    private func completeScreen(scale: CGFloat) -> some View {
        ZStack {
            Text(saveFailed ? "花签保存失败，请重试" : "花签已保存")
                .gardenFont(size: 15 * scale, weight: .bold)
                .foregroundStyle(Color(red: 47 / 255, green: 104 / 255, blue: 91 / 255))
                .padding(.horizontal, 22 * scale)
                .frame(height: 42 * scale)
                .background(.white.opacity(0.82), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.92), lineWidth: 1.5 * scale))
                .shadow(color: .black.opacity(0.10), radius: 8 * scale, y: 4 * scale)
                .position(x: 201 * scale, y: 82 * scale)

            FlowerTicketCard(
                image: snapshot,
                number: savedRecord?.number ?? nextTicketNumber,
                plantCount: plantCount,
                timestamp: capturedAt,
                showsStamp: true
            )
            .frame(width: 232.2 * scale, height: 563.4 * scale)
            .position(x: 201 * scale, y: 393 * scale)
            .transition(.scale(scale: 0.92).combined(with: .opacity))

            VStack(spacing: 12 * scale) {
                Button {
                    guard savedRecord != nil else {
                        saveTicketIfNeeded()
                        return
                    }
                    onViewTickets()
                } label: {
                    HStack(spacing: 8 * scale) {
                        Text("查看我的花签")
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

                Button(action: onReturnToAR) {
                    Text("返回 AR 世界")
                        .gardenFont(size: 14 * scale, weight: .bold)
                        .foregroundStyle(Color(red: 47 / 255, green: 104 / 255, blue: 91 / 255))
                        .frame(width: 232 * scale, height: 46 * scale)
                        .background(.white.opacity(0.82), in: Capsule())
                        .musicGlossCapsule(scale: scale)
                }
                .buttonStyle(.plain)
            }
            .position(x: 201 * scale, y: 788 * scale)
        }
    }

    private var nextTicketNumber: Int {
        (store.flowerTickets.map(\.number).max() ?? 0) + 1
    }

    private var currentVisibleHeight: CGFloat {
        switch step {
        case .machine: 1
        case .printing: 112
        case .ready: min(626, 252 + max(0, pullOffset))
        case .pulling: 626
        default: 1
        }
    }

    private func pullGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard step == .ready else { return }
                pullOffset = min(374, max(0, value.translation.height / max(scale, 0.001)))
            }
            .onEnded { value in
                guard step == .ready else { return }
                let predicted = max(
                    pullOffset,
                    value.predictedEndTranslation.height / max(scale, 0.001)
                )
                if predicted >= 243 {
                    finishPull()
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        pullOffset = 0
                    }
                    if ParentComfortRuntime.hapticsEnabled {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                }
            }
    }

    private func startPrinting() {
        animationTask?.cancel()
        pullOffset = 0
        step = .machine
        let firstDelay = reduceMotion ? 20_000_000 : 550_000_000
        let secondDelay = reduceMotion ? 20_000_000 : 1_050_000_000
        animationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(firstDelay))
            guard !Task.isCancelled, step == .machine else { return }
            step = .printing
            try? await Task.sleep(nanoseconds: UInt64(secondDelay))
            guard !Task.isCancelled, step == .printing else { return }
            step = .ready
        }
    }

    private func finishPull() {
        pullOffset = 374
        withAnimation(reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.38)) {
            step = .pulling
        }
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(reduceMotion ? 20_000_000 : 460_000_000)
            )
            guard !Task.isCancelled, step == .pulling else { return }
            saveTicketIfNeeded()
            if ParentComfortRuntime.hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                AudioServicesPlaySystemSound(1103)
            }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                step = .complete
            }
        }
    }

    private func saveTicketIfNeeded() {
        guard savedRecord == nil else { return }
        savedRecord = store.saveFlowerTicket(
            image: snapshot,
            plantCount: plantCount,
            at: capturedAt
        )
        saveFailed = savedRecord == nil
    }

    private func returnToReview() {
        animationTask?.cancel()
        pullOffset = 0
        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.22)) {
            step = .review
        }
    }
}

private struct SproutlyTicketMachine: View {
    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 304
            ZStack {
                Image("ticket_machine_shell")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 334 * scale, height: 148 * scale)
                    .position(x: 152 * scale, y: 68 * scale)

                ZStack {
                    Circle()
                        .fill(.white.opacity(0.92))
                    Circle()
                        .stroke(Color(red: 111 / 255, green: 178 / 255, blue: 151 / 255), lineWidth: 2 * scale)
                    KakaAvatarView(matchesVariantScale: true)
                        .padding(7 * scale)
                }
                .frame(width: 66 * scale, height: 66 * scale)
                .position(x: 152 * scale, y: 34 * scale)

                HStack(spacing: 8 * scale) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule()
                            .fill(Color(red: 165 / 255, green: 205 / 255, blue: 184 / 255))
                            .frame(width: 24 * scale, height: 18 * scale)
                            .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 1 * scale))
                    }
                }
                .position(x: 152 * scale, y: 73 * scale)

                Image("ticket_machine_powder")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32 * scale, height: 18 * scale)
                    .position(x: 260 * scale, y: 76 * scale)

                Image("ticket_machine_slot_rear")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 288 * scale, height: 26 * scale)
                    .position(x: 152 * scale, y: 110 * scale)
            }
        }
    }
}

struct FlowerTicketCard: View {
    let image: UIImage
    let number: Int
    let plantCount: Int
    let timestamp: Date
    var showsStamp = false

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 258
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                    .fill(Color(red: 248 / 255, green: 243 / 255, blue: 231 / 255))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                            .stroke(.white.opacity(0.9), lineWidth: 2 * scale)
                    }
                    .shadow(
                        color: Color(red: 15 / 255, green: 46 / 255, blue: 36 / 255).opacity(0.28),
                        radius: 14 * scale,
                        y: 10 * scale
                    )

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 234 * scale, height: 509 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 17 * scale, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17 * scale, style: .continuous)
                            .stroke(.white, lineWidth: 5 * scale)
                    }
                    .position(x: 129 * scale, y: 263 * scale)

                Image("ticket_info_dashed")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 234 * scale, height: 7 * scale)
                    .position(x: 129 * scale, y: 531 * scale)

                Image("ticket_info_plant")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52 * scale, height: 52 * scale)
                    .position(x: 53 * scale, y: 575 * scale)

                VStack(alignment: .leading, spacing: 0) {
                    Text("huā fáng")
                        .gardenFont(size: 9 * scale, weight: .medium)
                    Text(String(format: "花房 %02d", number))
                        .gardenFont(size: 15 * scale, weight: .bold)
                    HStack(spacing: 4 * scale) {
                        Image("ticket_info_flowers")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34 * scale, height: 12 * scale)
                        Text("\(plantCount)")
                            .gardenFont(size: 11 * scale, weight: .bold)
                    }
                }
                .foregroundStyle(Color(red: 79 / 255, green: 130 / 255, blue: 120 / 255))
                .position(x: 137 * scale, y: 574 * scale)

                Rectangle()
                    .fill(Color(red: 189 / 255, green: 209 / 255, blue: 199 / 255).opacity(0.72))
                    .frame(width: 1 * scale, height: 39 * scale)
                    .position(x: 166 * scale, y: 576 * scale)

                VStack(alignment: .leading, spacing: 3 * scale) {
                    Text(dateText)
                        .gardenFont(size: 11 * scale, weight: .bold)
                    Text(timeText)
                        .gardenFont(size: 9 * scale, weight: .medium)
                }
                .foregroundStyle(Color(red: 48 / 255, green: 95 / 255, blue: 85 / 255))
                .position(x: 211 * scale, y: 573 * scale)

                if showsStamp {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.92))
                        Circle()
                            .stroke(
                                Color(red: 107 / 255, green: 177 / 255, blue: 150 / 255),
                                style: StrokeStyle(lineWidth: 2 * scale, dash: [4 * scale, 3 * scale])
                            )
                        KakaAvatarView(matchesVariantScale: true)
                            .padding(7 * scale)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12 * scale, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 24 * scale, height: 24 * scale)
                            .background(GardenTheme.deepMint, in: Circle())
                            .offset(x: 25 * scale, y: 24 * scale)
                    }
                    .frame(width: 66 * scale, height: 66 * scale)
                    .rotationEffect(.degrees(8))
                    .position(x: 219 * scale, y: 54 * scale)
                    .transition(.scale(scale: 1.35).combined(with: .opacity))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("花房 \(number)，\(plantCount) 株植物，\(dateText) \(timeText)")
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: timestamp)
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
}
