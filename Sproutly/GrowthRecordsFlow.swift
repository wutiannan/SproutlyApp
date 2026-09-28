import SwiftUI
import UIKit

struct GrowthRecordsFlowView: View {
    @EnvironmentObject private var store: GardenStore
    @StateObject private var musicPlayback = MusicRecordPlaybackController.shared
    @State private var route: Route = .overview

    let onClose: () -> Void

    private enum Route: Equatable {
        case overview
        case usage
        case music
        case flower
        case musicRecord(UUID)
    }

    var body: some View {
        Group {
            if case let .musicRecord(id) = route,
               let activity = allMusicActivities.first(where: { $0.id == id }) {
                ZStack {
                    EmotionMusicRecordScene(
                        data: musicPresentation(for: activity),
                        showsCardStack: true
                    )
                    GrowthBackButton {
                        musicPlayback.stop()
                        route = .music
                    }
                        .frame(width: 48, height: 48)
                        .position(x: 44, y: 79)
                        .zIndex(20)
                }
                .ignoresSafeArea()
            } else {
                GrowthRecordCanvas { scale in
                    switch route {
                    case .overview:
                        overviewPage(scale: scale)
                    case .usage:
                        usagePage(scale: scale)
                    case .music:
                        musicObservationPage(scale: scale)
                    case .flower:
                        flowerObservationPage(scale: scale)
                    case .musicRecord:
                        Color.clear
                    }
                }
            }
        }
        .onDisappear {
            if musicPlayback.activeRecordID != nil {
                musicPlayback.stop()
            }
        }
    }
}

private extension GrowthRecordsFlowView {
    var calendar: Calendar { .autoupdatingCurrent }

    var weekStart: Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -6, to: today) ?? today
    }

    var allMusicActivities: [GrowthMusicActivity] {
        store.emotionRecords
            .filter { $0.source == .musicReflection }
            .map(GrowthMusicActivity.init)
            .sorted { $0.completedAt > $1.completedAt }
    }

    var musicActivities: [GrowthMusicActivity] {
        allMusicActivities.filter { $0.completedAt >= weekStart }
    }

    var allARActivities: [GrowthARActivity] {
        let actual = store.arLearningRecords.map(GrowthARActivity.init)
        let firstActual = actual.map(\.completedAt).min() ?? .distantFuture
        let legacy = store.flowerTickets
            .filter { $0.timestamp < firstActual }
            .map(GrowthARActivity.init)
        return (actual + legacy).sorted { $0.completedAt > $1.completedAt }
    }

    var arActivities: [GrowthARActivity] {
        allARActivities.filter { $0.completedAt >= weekStart }
    }

    var usageDays: [GrowthUsageDay] {
        let dates = Set(
            musicActivities.map { calendar.startOfDay(for: $0.completedAt) }
                + arActivities.map { calendar.startOfDay(for: $0.completedAt) }
        )
        return dates.sorted(by: >).map { date in
            GrowthUsageDay(
                date: date,
                music: musicActivities.filter { calendar.isDate($0.completedAt, inSameDayAs: date) },
                ar: arActivities.filter { calendar.isDate($0.completedAt, inSameDayAs: date) }
            )
        }
    }

    var weekEmotionRecords: [EmotionRecord] {
        store.emotionRecords.filter { $0.timestamp >= weekStart }
    }

    var totalDuration: Int {
        musicActivities.reduce(0) { $0 + $1.durationSeconds }
            + arActivities.reduce(0) { $0 + $1.durationSeconds }
    }

    var totalActivityCount: Int { musicActivities.count + arActivities.count }

    var totalDurationMinutes: Int {
        guard totalDuration > 0 else { return 0 }
        return max(1, Int(ceil(Double(totalDuration) / 60)))
    }

    var weekRangeText: String {
        let end = Date()
        let first = GrowthDate.yearMonthDay.string(from: weekStart)
        let last = GrowthDate.monthDayDots.string(from: end)
        return "\(first)–\(last)"
    }

    var weekShortRangeText: String {
        "\(GrowthDate.monthDayChinese.string(from: weekStart).replacingOccurrences(of: "月", with: "月"))–\(GrowthDate.dayChinese.string(from: Date()))"
    }

    var currentMoodName: String {
        GrowthMood.displayName(weekEmotionRecords.last?.musicSession?.afterMood)
            ?? weekEmotionRecords.last.map { GrowthMood.displayName($0.emotion) }
            ?? "平静"
    }

    var dominantMoodName: String {
        let names = weekEmotionRecords.map {
            GrowthMood.displayName($0.musicSession?.afterMood)
                ?? GrowthMood.displayName($0.emotion)
        }
        let groups = Dictionary(grouping: names, by: { $0 })
        return groups.max { $0.value.count < $1.value.count }?.key ?? "平静"
    }

    var mainSummary: String {
        guard totalActivityCount > 0 || !weekEmotionRecords.isEmpty else {
            return "KAKA还没有发现新记录"
        }
        let musicText = musicActivities.isEmpty
            ? "还没有音乐创作"
            : "完成了\(musicActivities.count)次音乐创作"
        let arText = arActivities.isEmpty
            ? "还没有花房探索"
            : "完成了\(arActivities.count)次花房探索"
        return "本周\(musicText)，\(arText)。最常出现的心情是“\(dominantMoodName)”，现在是“\(currentMoodName)”。"
    }

    func overviewPage(scale: CGFloat) -> some View {
        ZStack {
            GrowthBackground()
            GrowthPageHeader(
                title: "成长记录",
                subtitle: "看见每一次小小成长",
                scale: scale,
                backAction: onClose
            )

            GrowthCard(cornerRadius: 20, scale: scale) {
                HStack(spacing: 12 * scale) {
                    Image("profile_child_avatar")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 46 * scale, height: 46 * scale)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2 * scale))

                    VStack(alignment: .leading, spacing: 2 * scale) {
                        Text(store.userName)
                            .gardenFont(size: 16 * scale, weight: .bold)
                        Text(weekRangeText)
                            .gardenFont(size: 9 * scale)
                            .foregroundStyle(GrowthPalette.subtleInk)
                    }
                    Spacer(minLength: 0)
                    Text("近7天状况")
                        .gardenFont(size: 11 * scale)
                        .foregroundStyle(GrowthPalette.teal)
                        .padding(.horizontal, 12 * scale)
                        .frame(height: 34 * scale)
                        .background(GrowthPalette.mintPill, in: Capsule())
                }
                .padding(.horizontal, 18 * scale)
            }
            .frame(width: 362 * scale, height: 70 * scale)
            .position(x: 201 * scale, y: 154 * scale)

            weekOverviewCard(scale: scale)
                .position(x: 201 * scale, y: 275.25 * scale)

            Button { route = .usage } label: {
                usagePreviewCard(scale: scale)
            }
            .buttonStyle(.plain)
            .position(x: 201 * scale, y: 437 * scale)

            overviewLowerContent(scale: scale)
        }
    }

    private func overviewLowerContent(scale: CGFloat) -> some View {
        VStack(spacing: 17 * scale) {
            HStack(spacing: 16 * scale) {
                GrowthCategoryCard(
                    kind: .music,
                    primaryText: "\(musicActivities.count)件作品",
                    secondaryText: dominantColorText,
                    scale: scale
                ) { route = .music }

                GrowthCategoryCard(
                    kind: .flower,
                    primaryText: "完成\(arActivities.count)关",
                    secondaryText: arActivities.isEmpty ? "等待练习" : "获得\(arActivities.count)株植物",
                    scale: scale
                ) { route = .flower }
            }
            .frame(height: 164 * scale)

            GrowthCard(cornerRadius: 20, scale: scale) {
                HStack(alignment: .top, spacing: 6 * scale) {
                    KakaAvatarView(matchesVariantScale: true)
                        .frame(width: 62 * scale, height: 62 * scale)
                        .offset(x: -7 * scale)
                    VStack(alignment: .leading, spacing: 7 * scale) {
                        Text("本周KAKA发现")
                            .gardenFont(size: 14 * scale, weight: .bold)
                        Text(mainSummary)
                            .gardenFont(size: 10 * scale)
                            .foregroundStyle(GrowthPalette.subtleInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10 * scale)
                .padding(.vertical, 12 * scale)
            }
            .frame(width: 362 * scale)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 530 * scale)
        .frame(width: 402 * scale, height: 874 * scale, alignment: .top)
    }

    var dominantColorText: String {
        let colors = musicActivities.flatMap { $0.details?.moodColorHexes ?? [] }
        guard !colors.isEmpty else { return "使用色彩待记录" }
        return "使用\(Set(colors).count)种颜色"
    }

    func weekOverviewCard(scale: CGFloat) -> some View {
        GrowthCard(cornerRadius: 22, scale: scale) {
            ZStack {
                HStack {
                    Text("本周概览").gardenFont(size: 15 * scale, weight: .bold)
                    Spacer()
                    Text(weekShortRangeText)
                        .gardenFont(size: 9 * scale)
                        .foregroundStyle(GrowthPalette.subtleInk)
                }
                .padding(.horizontal, 17 * scale)
                .position(x: 181 * scale, y: 22 * scale)

                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 6 * scale) {
                        Image("growth_duration_icon")
                            .resizable().scaledToFit()
                            .frame(width: 28 * scale, height: 28 * scale)
                        Text("\(totalDurationMinutes)")
                            .gardenFont(size: 28 * scale, weight: .bold)
                    }
                    Text("分钟")
                        .gardenFont(size: 10 * scale)
                        .foregroundStyle(GrowthPalette.subtleInk)
                    Text("本周活动时长")
                        .gardenFont(size: 8 * scale)
                        .foregroundStyle(GrowthPalette.faintInk)
                        .padding(.top, 4 * scale)
                }
                .frame(width: 105 * scale, height: 83 * scale)
                .background(GrowthPalette.softMint, in: RoundedRectangle(cornerRadius: 18 * scale))
                .position(x: 73 * scale, y: 87 * scale)

                VStack(alignment: .leading, spacing: 8 * scale) {
                    Text("\(totalActivityCount)项活动")
                        .gardenFont(size: 12 * scale, weight: .bold)
                    GeometryReader { proxy in
                        let count = max(1, totalActivityCount)
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(GrowthPalette.music)
                                .frame(width: proxy.size.width * CGFloat(musicActivities.count) / CGFloat(count))
                            Rectangle()
                                .fill(GrowthPalette.flower)
                                .frame(width: proxy.size.width * CGFloat(arActivities.count) / CGFloat(count))
                            if totalActivityCount == 0 {
                                Rectangle().fill(GrowthPalette.empty)
                            }
                        }
                    }
                    .frame(height: 10 * scale)
                    .clipShape(Capsule())

                    HStack(spacing: 17 * scale) {
                        GrowthLegendDot(color: GrowthPalette.music, text: "音乐 \(musicActivities.count)次", scale: scale)
                        GrowthLegendDot(color: GrowthPalette.flower, text: "花房 \(arActivities.count)次", scale: scale)
                    }
                }
                .frame(width: 194 * scale, alignment: .leading)
                .position(x: 241 * scale, y: 87 * scale)
            }
        }
        .frame(width: 362 * scale, height: 139 * scale)
    }

    func usagePreviewCard(scale: CGFloat) -> some View {
        GrowthCard(cornerRadius: 22, scale: scale) {
            VStack(spacing: 6 * scale) {
                HStack {
                    VStack(alignment: .leading, spacing: 1 * scale) {
                        Text("使用记录").gardenFont(size: 15 * scale, weight: .bold)
                        Text("时间 · 活动 · 心情变化")
                            .gardenFont(size: 8 * scale)
                            .foregroundStyle(GrowthPalette.subtleInk)
                    }
                    Spacer()
                    Text("查看全部  ›")
                        .gardenFont(size: 9 * scale)
                        .foregroundStyle(GrowthPalette.teal)
                }

                if usageDays.isEmpty {
                    Spacer(minLength: 0)
                    Text("KAKA还没有发现新记录")
                        .gardenFont(size: 10 * scale)
                        .foregroundStyle(GrowthPalette.faintInk)
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(usageDays.prefix(3))) { day in
                        GrowthUsagePreviewRow(day: day, scale: scale)
                    }
                }
            }
            .padding(.horizontal, 16 * scale)
            .padding(.vertical, 12 * scale)
            .frame(width: 362 * scale, height: 151 * scale)
            .overlay(alignment: .leading) {
                Capsule().fill(GrowthPalette.teal)
                    .frame(width: 4 * scale, height: 88 * scale)
            }
        }
        .frame(width: 362 * scale, height: 151 * scale)
    }

    func usagePage(scale: CGFloat) -> some View {
        ZStack {
            GrowthBackground()
            GrowthPageHeader(
                title: "使用记录",
                subtitle: "查看每一次使用中的活动与主动表达",
                scale: scale,
                backAction: { route = .overview }
            )

            sevenDayOverview(scale: scale)
                .position(x: 201 * scale, y: 169 * scale)

            VStack(alignment: .leading, spacing: 8 * scale) {
                Text("使用记录 · 近7天")
                    .gardenFont(size: 15 * scale, weight: .bold)
                    .padding(.leading, 2 * scale)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 14 * scale) {
                        if usageDays.isEmpty {
                            GrowthEmptyCard(message: "KAKA还没有发现新记录", scale: scale)
                        } else {
                            ForEach(usageDays) { day in
                                GrowthUsageDayCard(day: day, scale: scale)
                            }
                        }
                    }
                    .padding(.bottom, 24 * scale)
                }
            }
            .frame(width: 362 * scale, height: 622 * scale, alignment: .top)
            .position(x: 201 * scale, y: 551 * scale)
        }
    }

    func sevenDayOverview(scale: CGFloat) -> some View {
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        return GrowthCard(cornerRadius: 22, scale: scale) {
            VStack(spacing: 7 * scale) {
                HStack {
                    Text("7日使用概览").gardenFont(size: 13 * scale, weight: .bold)
                    Spacer()
                    Text("\(usageDays.count)天 · \(totalActivityCount)项活动")
                        .gardenFont(size: 8 * scale)
                        .foregroundStyle(GrowthPalette.subtleInk)
                }
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { date in
                        let count = musicActivities.filter { calendar.isDate($0.completedAt, inSameDayAs: date) }.count
                            + arActivities.filter { calendar.isDate($0.completedAt, inSameDayAs: date) }.count
                        VStack(spacing: 4 * scale) {
                            Circle()
                                .fill(count == 0 ? GrowthPalette.empty : (count > 1 ? GrowthPalette.teal : GrowthPalette.flower))
                                .frame(width: (count == 0 ? 10 : 26) * scale, height: (count == 0 ? 10 : 26) * scale)
                                .overlay {
                                    if count > 0 {
                                        Text("\(count)").gardenFont(size: 9 * scale, weight: .bold).foregroundStyle(.white)
                                    }
                                }
                                .frame(height: 26 * scale)
                            Text(GrowthDate.dayOnly.string(from: date))
                                .gardenFont(size: 8 * scale)
                                .foregroundStyle(GrowthPalette.faintInk)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 16 * scale)
            .padding(.vertical, 11 * scale)
        }
        .frame(width: 362 * scale, height: 94 * scale)
    }

    func musicObservationPage(scale: CGFloat) -> some View {
        ZStack {
            GrowthBackground()
            GrowthPageHeader(
                title: "音乐创作观察",
                subtitle: "观察色彩、声音与创作过程",
                scale: scale,
                backAction: { route = .overview }
            )
            .zIndex(10)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14 * scale) {
                    GrowthMusicTrajectoryCard(
                        music: musicActivities,
                        weekStart: weekStart,
                        scale: scale
                    )

                    Text("最近作品")
                        .gardenFont(size: 15 * scale, weight: .bold)
                        .padding(.leading, 2 * scale)

                    if musicActivities.isEmpty {
                        GrowthEmptyCard(message: "KAKA还没有发现新记录", scale: scale)
                    } else {
                        ForEach(musicActivities) { activity in
                            Button {
                                route = .musicRecord(activity.id)
                                musicPlayback.play(record: activity.record)
                            } label: {
                                GrowthMusicWorkCard(activity: activity, scale: scale)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    GrowthKakaObservationCard(
                        title: "KAKA创作观察",
                        badge: "近7天 · \(musicActivities.count)件作品",
                        conclusion: musicConclusion,
                        behavior: musicBehavior,
                        suggestion: musicSuggestion,
                        scale: scale
                    )
                }
                .padding(.bottom, 24 * scale)
            }
            .frame(width: 362 * scale, height: 746 * scale)
            .position(x: 201 * scale, y: 496 * scale)
        }
    }

    var musicConclusion: String {
        guard !musicActivities.isEmpty else { return "完成音乐创作后，KAKA会在这里总结规律" }
        let changed = musicActivities.filter { $0.beforeMood != $0.afterMood }.count
        return changed > 0
            ? "本周情绪路径已出现重复规律"
            : "本周创作情绪整体保持稳定"
    }

    var musicBehavior: String {
        guard !musicActivities.isEmpty else { return "暂无可分析的创作行为。" }
        let changed = musicActivities.filter { $0.beforeMood != $0.afterMood }.count
        return "\(musicActivities.count)次中有\(changed)次发生情绪变化；最常结束于“\(dominantMusicEndMood)”。"
    }

    var musicSuggestion: String {
        guard !musicActivities.isEmpty else { return "完成一次音乐花园，开始积累成长记录" }
        return "继续保持轻柔开场与渐进变化"
    }

    var dominantMusicEndMood: String {
        let groups = Dictionary(grouping: musicActivities.map(\.afterMood), by: { $0 })
        return groups.max { $0.value.count < $1.value.count }?.key ?? "平静"
    }

    func flowerObservationPage(scale: CGFloat) -> some View {
        ZStack {
            GrowthBackground()
            GrowthPageHeader(
                title: "花房探索",
                subtitle: "观察情绪理解、表达与提示需求",
                scale: scale,
                backAction: { route = .overview },
                matchesFlowerDesign: true
            )

            GrowthFlowerLearningProfile(records: arActivities, scale: scale)
                .position(x: 201 * scale, y: 193 * scale)

            VStack(alignment: .leading, spacing: 10.5 * scale) {
                Text("最近学习")
                    .gardenFont(size: 14 * scale, weight: .bold)
                    .foregroundStyle(Color(red: 49 / 255, green: 95 / 255, blue: 89 / 255))
                    .frame(height: 20 * scale)
                    .padding(.leading, 2 * scale)
                if let latest = arActivities.first {
                    GrowthRecentARCard(record: latest, scale: scale)
                } else {
                    GrowthEmptyCard(message: "KAKA还没有发现新记录", scale: scale, height: 150)
                        .frame(height: 150 * scale)
                }
            }
            .frame(width: 362 * scale, height: 181 * scale, alignment: .top)
            .position(x: 201 * scale, y: 366 * scale)

            Text("学习情况")
                .gardenFont(size: 14 * scale, weight: .bold)
                .foregroundStyle(Color(red: 49 / 255, green: 95 / 255, blue: 89 / 255))
                .frame(width: 354 * scale, height: 20 * scale, alignment: .leading)
                .position(x: 201 * scale, y: 478 * scale)

            GrowthLearningStateCard(records: arActivities, scale: scale)
                .position(x: 201 * scale, y: 552.5 * scale)

            GrowthRewardCard(record: arActivities.first, scale: scale)
                .position(x: 201 * scale, y: 642.5 * scale)

            GrowthKakaObservationCard(
                title: "KAKA学习观察",
                badge: "近7天 · \(arActivities.count)次训练",
                conclusion: arConclusion,
                behavior: arBehavior,
                suggestion: arSuggestion,
                scale: scale,
                matchesFlowerDesign: true
            )
            .frame(width: 362 * scale, height: 154 * scale)
            .position(x: 201 * scale, y: 756.5 * scale)
        }
    }

    var arConclusion: String {
        guard !arActivities.isEmpty else { return "完成AR任务后，KAKA会在这里记录表现" }
        let hinted = arActivities.filter(\.completedAfterHint).count
        return hinted == 0 ? "已能独立识别任务中的情绪线索" : "已能识别情绪，部分任务仍需提示"
    }

    var arBehavior: String {
        guard !arActivities.isEmpty else { return "暂无可分析的训练行为。" }
        let independent = arActivities.filter { !$0.completedAfterHint }.count
        return "独立完成\(independent)次，提示后完成\(arActivities.count - independent)次。"
    }

    var arSuggestion: String {
        guard !arActivities.isEmpty else { return "完成一关AR任务，开始积累学习记录" }
        return arActivities.contains(where: \.completedAfterHint)
            ? "先观察嘴角或语调，再尝试不看提示作答"
            : "继续尝试听声音与模仿表情"
    }

    func musicPresentation(for activity: GrowthMusicActivity) -> EmotionMusicCardPresentation {
        let mood = activity.afterMood
        return EmotionMusicCardPresentation(
            id: activity.id,
            artwork: MusicArtworkSnapshotStore.load(activity.details?.artworkImageName),
            fallbackArtworkAsset: "profile_emotion_artwork",
            face: MusicFaceSnapshotStore.load(activity.details?.faceImageName),
            fallbackFaceAsset: "profile_emotion_avatar",
            moodAsset: GrowthMood.asset(for: mood),
            avatarHaloColor: GrowthMood.color(for: mood),
            timestamp: activity.completedAt,
            theme: GrowthMood.diaryTitle(for: activity.details?.world),
            durationSeconds: activity.durationSeconds,
            moodColors: (activity.details?.moodColorHexes ?? []).compactMap(Color.init(growthHex:)),
            reflection: GrowthMood.reflection(for: activity.details?.world)
        )
    }
}

private struct GrowthMusicActivity: Identifiable, Hashable {
    let record: EmotionRecord
    var id: UUID { record.id }
    var completedAt: Date { record.timestamp }
    var details: MusicSessionDetails? { record.musicSession }
    var durationSeconds: Int { max(1, details?.durationSeconds ?? 9 * 60) }
    var startedAt: Date { completedAt.addingTimeInterval(-Double(durationSeconds)) }
    var beforeMood: String {
        GrowthMood.displayName(details?.beforeMood ?? details?.world)
            ?? GrowthMood.displayName(record.emotion)
    }
    var afterMood: String {
        GrowthMood.displayName(details?.afterMood)
            ?? GrowthMood.displayName(record.emotion)
    }
}

private struct GrowthARActivity: Identifiable, Hashable {
    let id: UUID
    let taskNumber: Int
    let startedAt: Date
    let completedAt: Date
    let durationSeconds: Int
    let attemptCount: Int
    let rewardName: String

    init(_ record: ARLearningRecord) {
        id = record.id
        taskNumber = record.taskNumber
        startedAt = record.startedAt
        completedAt = record.completedAt
        durationSeconds = record.durationSeconds
        attemptCount = record.attemptCount
        rewardName = record.rewardName
    }

    init(_ ticket: FlowerTicketRecord) {
        id = ticket.id
        taskNumber = ticket.number.isMultiple(of: 2) ? 2 : 1
        durationSeconds = 14 * 60
        completedAt = ticket.timestamp
        startedAt = ticket.timestamp.addingTimeInterval(-14 * 60)
        attemptCount = 1
        rewardName = taskNumber == 1 ? "桃花" : "荷花"
    }

    var completedAfterHint: Bool { attemptCount > 1 }
    var statusText: String { completedAfterHint ? "提示后完成" : "独立完成" }
    var taskTitle: String {
        taskNumber == 1 ? "任务1-1 · 识别开心表情" : "任务1-2 · 听声音找开心KAKA"
    }
    var skillTitle: String { taskNumber == 1 ? "看懂开心" : "听懂开心声音" }
}

private struct GrowthUsageDay: Identifiable {
    let date: Date
    let music: [GrowthMusicActivity]
    let ar: [GrowthARActivity]
    var id: Date { date }
    var count: Int { music.count + ar.count }
    var startAt: Date { (music.map(\.startedAt) + ar.map(\.startedAt)).min() ?? date }
    var endAt: Date { (music.map(\.completedAt) + ar.map(\.completedAt)).max() ?? date }
    var durationSeconds: Int {
        music.reduce(0) { $0 + $1.durationSeconds } + ar.reduce(0) { $0 + $1.durationSeconds }
    }
}

private enum GrowthMood {
    static func displayName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case "快乐", "愉悦", "开心", "闪耀": return "开心"
        case "平静", "放松": return "平静"
        case "低落", "难过": return "难过"
        case "生气", "愤怒": return "生气"
        case "紧张", "害怕": return "害怕"
        default: return raw
        }
    }

    static func displayName(_ emotion: EmotionKind) -> String {
        switch emotion {
        case .joy: "开心"
        case .calm: "平静"
        case .expectation: "害怕"
        case .low: "难过"
        }
    }

    static func row(_ mood: String) -> Int {
        switch displayName(mood) ?? mood {
        case "开心": 0
        case "平静": 1
        case "难过": 2
        case "生气": 3
        default: 4
        }
    }

    static func asset(for mood: String) -> String {
        switch displayName(mood) ?? mood {
        case "开心": "music_checkin_happy"
        case "平静": "music_checkin_calm"
        case "难过": "music_checkin_low"
        case "生气": "music_checkin_angry"
        default: "music_checkin_tense"
        }
    }

    static func color(for mood: String) -> Color {
        switch displayName(mood) ?? mood {
        case "开心": Color(red: 241 / 255, green: 215 / 255, blue: 120 / 255)
        case "平静": Color(red: 143 / 255, green: 214 / 255, blue: 201 / 255)
        case "难过": Color(red: 148 / 255, green: 170 / 255, blue: 218 / 255)
        case "生气": Color(red: 228 / 255, green: 163 / 255, blue: 172 / 255)
        default: Color(red: 197 / 255, green: 174 / 255, blue: 217 / 255)
        }
    }

    static func diaryTitle(for world: String?) -> String {
        switch world {
        case "快乐": "快乐花园"
        case "平静": "静谧花园"
        case "低落": "忧郁花园"
        case "生气": "暖阳花园"
        case "紧张": "安心花园"
        default: "情绪花园"
        }
    }

    static func reflection(for world: String?) -> String {
        switch world {
        case "快乐": "明亮的颜色在花园里跳舞，今天的快乐被好好收藏起来了。"
        case "平静": "柔和的颜色静静铺开，呼吸和音乐都慢慢安稳下来。"
        case "低落": "颜色慢慢亮起来，心也被温柔地接住。"
        case "生气": "热烈的颜色逐渐变得柔和，心里的风也慢慢停了下来。"
        case "紧张": "轻轻的颜色围在身边，呼吸变慢，身体也一点点放松。"
        default: "今天的颜色和音乐，都被好好收藏在这张乐卡里。"
        }
    }
}

private enum GrowthDate {
    static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter
    }

    static let yearMonthDay = formatter("yyyy.MM.dd")
    static let monthDayDots = formatter("MM.dd")
    static let monthDayChinese = formatter("M月d日")
    static let dayChinese = formatter("d日")
    static let dayOnly = formatter("dd")
    static let time = formatter("HH:mm")
}

private enum GrowthPalette {
    static let ink = Color(red: 35 / 255, green: 91 / 255, blue: 89 / 255)
    static let subtleInk = Color(red: 85 / 255, green: 130 / 255, blue: 126 / 255)
    static let faintInk = Color(red: 126 / 255, green: 158 / 255, blue: 153 / 255)
    static let teal = Color(red: 43 / 255, green: 174 / 255, blue: 155 / 255)
    static let softMint = Color(red: 237 / 255, green: 250 / 255, blue: 247 / 255)
    static let mintPill = Color(red: 220 / 255, green: 247 / 255, blue: 239 / 255)
    static let music = Color(red: 139 / 255, green: 134 / 255, blue: 207 / 255)
    static let musicPale = Color(red: 239 / 255, green: 235 / 255, blue: 253 / 255)
    static let flower = Color(red: 231 / 255, green: 150 / 255, blue: 94 / 255)
    static let flowerPale = Color(red: 255 / 255, green: 235 / 255, blue: 220 / 255)
    static let empty = Color(red: 226 / 255, green: 239 / 255, blue: 235 / 255)
}

private struct GrowthRecordCanvas<Content: View>: View {
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / 402, proxy.size.height / 874)
            content(scale)
                .frame(width: 402 * scale, height: 874 * scale)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .ignoresSafeArea()
    }
}

private struct GrowthBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 249 / 255, green: 254 / 255, blue: 252 / 255),
                    Color(red: 225 / 255, green: 245 / 255, blue: 239 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(Color.white.opacity(0.42))
                .frame(width: 250, height: 250)
                .offset(x: 166, y: -315)
            Circle()
                .fill(Color(red: 169 / 255, green: 220 / 255, blue: 208 / 255).opacity(0.12))
                .frame(width: 310, height: 310)
                .offset(x: -205, y: 255)
        }
    }
}

private struct GrowthPageHeader: View {
    let title: String
    let subtitle: String
    let scale: CGFloat
    let backAction: () -> Void
    var matchesFlowerDesign = false

    var body: some View {
        ZStack {
            GrowthBackButton(action: backAction)
                .frame(width: 48 * scale, height: 48 * scale)
                .position(x: 44 * scale, y: 79 * scale)

            VStack(alignment: .leading, spacing: (matchesFlowerDesign ? 12 : 1) * scale) {
                Text(title)
                    .gardenFont(size: (matchesFlowerDesign ? 23 : 24) * scale, weight: .bold)
                    .foregroundStyle(matchesFlowerDesign
                        ? Color(red: 23 / 255, green: 79 / 255, blue: 75 / 255)
                        : GrowthPalette.ink)
                    .frame(height: matchesFlowerDesign ? 20 * scale : nil)
                Text(subtitle)
                    .gardenFont(size: (matchesFlowerDesign ? 11 : 10) * scale)
                    .foregroundStyle(matchesFlowerDesign
                        ? Color(red: 109 / 255, green: 145 / 255, blue: 140 / 255)
                        : GrowthPalette.subtleInk)
                    .frame(height: matchesFlowerDesign ? 20 * scale : nil)
            }
            .foregroundStyle(GrowthPalette.ink)
            .frame(width: 270 * scale, alignment: .leading)
            .position(x: 226 * scale, y: (matchesFlowerDesign ? 84 : 80) * scale)
        }
    }
}

private struct GrowthBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.74))
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: Color.black.opacity(0.14), radius: 5, y: 4)
                Image("growth_back_arrow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回")
    }
}

private struct GrowthCard<Content: View>: View {
    let cornerRadius: CGFloat
    let scale: CGFloat
    @ViewBuilder let content: Content

    init(cornerRadius: CGFloat, scale: CGFloat, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.scale = scale
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(GrowthPalette.ink)
            .background(Color.white.opacity(0.90), in: RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous)
                    .stroke(.white.opacity(0.94), lineWidth: 1 * scale)
            }
            .shadow(color: GrowthPalette.ink.opacity(0.06), radius: 10 * scale, y: 5 * scale)
    }
}

private struct GrowthLegendDot: View {
    let color: Color
    let text: String
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 4 * scale) {
            Circle().fill(color).frame(width: 6 * scale, height: 6 * scale)
            Text(text).gardenFont(size: 8 * scale).foregroundStyle(GrowthPalette.subtleInk)
        }
    }
}

private struct GrowthCategoryCard: View {
    enum Kind { case music, flower }
    let kind: Kind
    let primaryText: String
    let secondaryText: String
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22 * scale)
                    .fill(Color.white.opacity(0.92))
                UnevenRoundedRectangle(
                    topLeadingRadius: 22 * scale,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 22 * scale
                )
                .fill(kind == .music ? GrowthPalette.musicPale : GrowthPalette.flowerPale)
                .frame(height: 65 * scale)

                ZStack {
                    Circle().fill(kind == .music ? Color(red: 123 / 255, green: 155 / 255, blue: 193 / 255) : Color(red: 217 / 255, green: 149 / 255, blue: 99 / 255))
                    Image(kind == .music ? "growth_music_glyph" : "growth_flower_glyph")
                        .resizable().scaledToFit()
                        .frame(width: (kind == .music ? 31 : 29) * scale, height: 29 * scale)
                }
                .frame(width: 52 * scale, height: 52 * scale)
                .position(x: 43 * scale, y: 43 * scale)

                VStack(alignment: .leading, spacing: 6 * scale) {
                    Text(kind == .music ? "音乐花园" : "花房探索")
                        .gardenFont(size: 16 * scale, weight: .bold)
                    Text(primaryText).gardenFont(size: 9 * scale)
                    Text(secondaryText)
                        .gardenFont(size: 8 * scale)
                        .foregroundStyle(GrowthPalette.subtleInk)
                    Text("查看  ›")
                        .gardenFont(size: 9 * scale, weight: .bold)
                        .foregroundStyle(kind == .music ? GrowthPalette.music : GrowthPalette.flower)
                }
                .padding(.leading, 17 * scale)
                .padding(.top, 80 * scale)
            }
            .frame(width: 173 * scale, height: 164 * scale)
            .overlay {
                RoundedRectangle(cornerRadius: 22 * scale)
                    .stroke(.white.opacity(0.9), lineWidth: 1 * scale)
            }
            .shadow(color: GrowthPalette.ink.opacity(0.07), radius: 8 * scale, y: 5 * scale)
        }
        .buttonStyle(.plain)
    }
}

private struct GrowthUsagePreviewRow: View {
    let day: GrowthUsageDay
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 7 * scale) {
            Text(GrowthDate.monthDayChinese.string(from: day.date))
                .frame(width: 45 * scale, alignment: .leading)
            Text("\(GrowthDate.time.string(from: day.startAt))–\(GrowthDate.time.string(from: day.endAt))")
                .frame(width: 70 * scale, alignment: .leading)
                .foregroundStyle(GrowthPalette.faintInk)
            Text(activityNames)
                .frame(width: 83 * scale)
                .padding(.vertical, 3 * scale)
                .background(day.music.isEmpty ? GrowthPalette.flowerPale : GrowthPalette.musicPale, in: Capsule())
            HStack(spacing: 3 * scale) {
                if let music = day.music.first {
                    Image(GrowthMood.asset(for: music.beforeMood)).resizable().scaledToFit()
                    Text("→").foregroundStyle(GrowthPalette.faintInk)
                    Image(GrowthMood.asset(for: music.afterMood)).resizable().scaledToFit()
                } else {
                    Image("music_checkin_low").resizable().scaledToFit().opacity(0.75)
                    Text("→").foregroundStyle(GrowthPalette.faintInk)
                    Text("未记录").gardenFont(size: 7 * scale).foregroundStyle(GrowthPalette.faintInk)
                }
            }
            .frame(width: 68 * scale, height: 20 * scale)
        }
        .gardenFont(size: 8 * scale)
        .foregroundStyle(GrowthPalette.subtleInk)
        .frame(height: 21 * scale)
        .background((day.id.timeIntervalSince1970.truncatingRemainder(dividingBy: 2) == 0 ? GrowthPalette.softMint : Color(red: 248 / 255, green: 244 / 255, blue: 1)), in: Capsule())
    }

    private var activityNames: String {
        if !day.music.isEmpty && !day.ar.isEmpty { return "音乐 · 花房" }
        return day.music.isEmpty ? "花房" : "音乐"
    }
}

private struct GrowthUsageDayCard: View {
    let day: GrowthUsageDay
    let scale: CGFloat

    var body: some View {
        GrowthCard(cornerRadius: 22, scale: scale) {
            VStack(spacing: 8 * scale) {
                HStack {
                    Text(GrowthDate.monthDayChinese.string(from: day.date))
                        .gardenFont(size: 11 * scale, weight: .bold)
                    Spacer()
                    Text("\(GrowthDate.time.string(from: day.startAt))–\(GrowthDate.time.string(from: day.endAt)) · \(growthDuration(day.durationSeconds))")
                        .gardenFont(size: 8 * scale)
                        .foregroundStyle(GrowthPalette.subtleInk)
                }

                ForEach(day.music) { activity in
                    VStack(spacing: 6 * scale) {
                        HStack(spacing: 7 * scale) {
                            GrowthStatePill(title: "开始 · \(activity.beforeMood)", color: GrowthPalette.mintPill, scale: scale)
                            GrowthStatePill(title: "音乐后 · \(activity.afterMood)", color: GrowthPalette.musicPale, scale: scale)
                        }
                        HStack {
                            Text("音乐花园")
                            Spacer()
                            Text("\(GrowthDate.time.string(from: activity.startedAt))–\(GrowthDate.time.string(from: activity.completedAt)) · \(growthDuration(activity.durationSeconds))")
                        }
                        .gardenFont(size: 8 * scale)
                        .foregroundStyle(GrowthPalette.subtleInk)
                        .padding(.horizontal, 10 * scale)
                        .frame(height: 24 * scale)
                        .background(Color(red: 242 / 255, green: 239 / 255, blue: 252 / 255), in: Capsule())
                    }
                }

                ForEach(day.ar) { activity in
                    HStack {
                        Text("AR训练 · 任务\(activity.taskNumber)")
                        Spacer()
                        Text("\(GrowthDate.time.string(from: activity.startedAt))–\(GrowthDate.time.string(from: activity.completedAt)) · \(activity.statusText)")
                    }
                    .gardenFont(size: 8 * scale)
                    .foregroundStyle(GrowthPalette.subtleInk)
                    .padding(.horizontal, 10 * scale)
                    .frame(height: 24 * scale)
                    .background(GrowthPalette.softMint, in: Capsule())
                }
            }
            .padding(16 * scale)
        }
        .frame(width: 362 * scale)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GrowthStatePill: View {
    let title: String
    let color: Color
    let scale: CGFloat

    var body: some View {
        Text(title)
            .gardenFont(size: 8 * scale)
            .foregroundStyle(GrowthPalette.subtleInk)
            .frame(maxWidth: .infinity)
            .frame(height: 30 * scale)
            .background(color, in: Capsule())
    }
}

private struct GrowthEmptyCard: View {
    let message: String
    let scale: CGFloat
    var height: CGFloat = 118

    var body: some View {
        GrowthCard(cornerRadius: 22, scale: scale) {
            VStack(spacing: 8 * scale) {
                KakaAvatarView(matchesVariantScale: true)
                    .frame(width: 54 * scale, height: 54 * scale)
                Text(message)
                    .gardenFont(size: 11 * scale, weight: .bold)
                    .foregroundStyle(GrowthPalette.subtleInk)
            }
            .frame(maxWidth: .infinity, minHeight: height * scale)
        }
        .frame(width: 362 * scale)
    }
}

private struct GrowthMusicTrajectoryCard: View {
    let music: [GrowthMusicActivity]
    let weekStart: Date
    let scale: CGFloat

    var body: some View {
        GrowthCard(cornerRadius: 22, scale: scale) {
            VStack(alignment: .leading, spacing: 7 * scale) {
                HStack {
                    VStack(alignment: .leading, spacing: 2 * scale) {
                        Text("本周情绪轨迹").gardenFont(size: 14 * scale, weight: .bold)
                        Text("\(music.count)幅作品 · \(music.count)次完整记录")
                            .gardenFont(size: 8 * scale)
                            .foregroundStyle(GrowthPalette.subtleInk)
                    }
                    Spacer()
                    Text("近7天")
                        .gardenFont(size: 9 * scale)
                        .foregroundStyle(GrowthPalette.subtleInk)
                        .padding(.horizontal, 11 * scale)
                        .frame(height: 24 * scale)
                        .background(GrowthPalette.softMint, in: Capsule())
                }

                Text(music.isEmpty ? "KAKA还没有发现新记录" : "KAKA总结：本周最常见结束心情是“\(dominantMood)”")
                    .gardenFont(size: 9 * scale, weight: .bold)
                    .padding(.horizontal, 8 * scale)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 26 * scale)
                    .background(GrowthPalette.softMint, in: RoundedRectangle(cornerRadius: 8 * scale))

                GrowthMoodTrajectoryChart(music: music, weekStart: weekStart, scale: scale)
                    .frame(height: 87 * scale)

                HStack(spacing: 8 * scale) {
                    metric("发生变化 \(changedCount)次", GrowthPalette.mintPill)
                    metric("保持相同 \(max(0, music.count - changedCount))次", GrowthPalette.musicPale)
                    metric("完整记录 \(music.count)/\(music.count)", Color(red: 241 / 255, green: 244 / 255, blue: 244 / 255))
                }
            }
            .padding(14 * scale)
        }
        .frame(width: 362 * scale, height: 190 * scale)
    }

    private var changedCount: Int { music.filter { $0.beforeMood != $0.afterMood }.count }

    private var dominantMood: String {
        let groups = Dictionary(grouping: music.map(\.afterMood), by: { $0 })
        return groups.max { $0.value.count < $1.value.count }?.key ?? "平静"
    }

    private func metric(_ title: String, _ color: Color) -> some View {
        Text(title)
            .gardenFont(size: 7 * scale)
            .foregroundStyle(GrowthPalette.subtleInk)
            .frame(maxWidth: .infinity)
            .frame(height: 17 * scale)
            .background(color, in: Capsule())
    }
}

private struct GrowthMoodTrajectoryChart: View {
    let music: [GrowthMusicActivity]
    let weekStart: Date
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 4 * scale) {
            VStack(alignment: .trailing, spacing: 1 * scale) {
                ForEach(["开心", "平静", "难过", "生气", "害怕"], id: \.self) { mood in
                    Text(mood)
                        .gardenFont(size: 7 * scale)
                        .foregroundStyle(GrowthPalette.subtleInk)
                        .frame(height: 11 * scale)
                }
            }
            .frame(width: 29 * scale)

            GeometryReader { proxy in
                let rowHeight = proxy.size.height * 0.69 / 4
                let plotHeight = rowHeight * 4
                ZStack(alignment: .topLeading) {
                    ForEach(0..<5, id: \.self) { row in
                        Rectangle()
                            .fill(GrowthPalette.empty)
                            .frame(height: 1 * scale)
                            .offset(y: CGFloat(row) * rowHeight)
                    }
                    ForEach(Array(music.enumerated()), id: \.element.id) { index, activity in
                        let x = xPosition(for: activity.completedAt, width: proxy.size.width)
                        let startY = CGFloat(GrowthMood.row(activity.beforeMood)) * rowHeight
                        let endY = CGFloat(GrowthMood.row(activity.afterMood)) * rowHeight
                        Path { path in
                            path.move(to: CGPoint(x: x - 4 * scale, y: startY))
                            path.addLine(to: CGPoint(x: x + 4 * scale, y: endY))
                        }
                        .stroke(index.isMultiple(of: 2) ? GrowthPalette.teal : GrowthPalette.music, style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round))
                        Circle().fill(GrowthPalette.flower).frame(width: 5 * scale, height: 5 * scale).position(x: x - 4 * scale, y: startY)
                        Circle().fill(GrowthPalette.teal).frame(width: 5 * scale, height: 5 * scale).position(x: x + 4 * scale, y: endY)
                    }
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { day in
                            Text(GrowthDate.dayOnly.string(from: Calendar.autoupdatingCurrent.date(byAdding: .day, value: day, to: weekStart) ?? weekStart))
                                .gardenFont(size: 7 * scale)
                                .foregroundStyle(GrowthPalette.faintInk)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .offset(y: plotHeight + 8 * scale)
                }
            }
        }
    }

    private func xPosition(for date: Date, width: CGFloat) -> CGFloat {
        let day = Calendar.autoupdatingCurrent.dateComponents([.day], from: weekStart, to: date).day ?? 0
        return (CGFloat(min(6, max(0, day))) + 0.5) * width / 7
    }
}

private struct GrowthMusicWorkCard: View {
    let activity: GrowthMusicActivity
    let scale: CGFloat

    var body: some View {
        GrowthCard(cornerRadius: 22, scale: scale) {
            HStack(spacing: 13 * scale) {
                Group {
                    if let image = MusicArtworkSnapshotStore.load(activity.details?.artworkImageName) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image("profile_emotion_artwork").resizable().scaledToFill()
                    }
                }
                .frame(width: 103 * scale, height: 122 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 16 * scale))

                VStack(alignment: .leading, spacing: 8 * scale) {
                    Text(GrowthMood.diaryTitle(for: activity.details?.world))
                        .gardenFont(size: 16 * scale, weight: .bold)
                    HStack(spacing: 10 * scale) {
                        ForEach(Array(displayColors.enumerated()), id: \.offset) { _, color in
                            HStack(spacing: 3 * scale) {
                                Circle().fill(color).frame(width: 9 * scale, height: 9 * scale)
                                Text("\(Int(100 / max(1, displayColors.count)))%")
                            }
                        }
                    }
                    .gardenFont(size: 7 * scale)
                    .foregroundStyle(GrowthPalette.subtleInk)

                    HStack {
                        Text(activity.beforeMood)
                        Text("→")
                        Text(activity.afterMood)
                    }
                    .gardenFont(size: 8 * scale)
                    .foregroundStyle(GrowthPalette.subtleInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 25 * scale)
                    .background(GrowthPalette.softMint, in: Capsule())

                    Text(activity.beforeMood == activity.afterMood ? "独立完成" : "情绪发生变化")
                        .gardenFont(size: 8 * scale)
                        .foregroundStyle(GrowthPalette.teal)
                        .padding(.horizontal, 10 * scale)
                        .frame(height: 22 * scale)
                        .background(GrowthPalette.mintPill, in: Capsule())

                    HStack(spacing: 8 * scale) {
                        Capsule().fill(GrowthPalette.teal).frame(height: 3 * scale)
                        Text(growthClock(activity.durationSeconds))
                            .gardenFont(size: 8 * scale)
                            .foregroundStyle(GrowthPalette.faintInk)
                    }
                }
            }
            .padding(13 * scale)
        }
        .frame(width: 362 * scale, height: 150 * scale)
    }

    private var displayColors: [Color] {
        let colors = (activity.details?.moodColorHexes ?? []).compactMap(Color.init(growthHex:))
        return Array((colors + [GrowthPalette.music, GrowthPalette.teal, GrowthPalette.flower]).prefix(3))
    }
}

private struct GrowthKakaObservationCard: View {
    let title: String
    let badge: String
    let conclusion: String
    let behavior: String
    let suggestion: String
    let scale: CGFloat
    var matchesFlowerDesign = false

    var body: some View {
        GrowthCard(cornerRadius: 22, scale: scale) {
            VStack(spacing: 8 * scale) {
                HStack {
                    Text(title)
                        .gardenFont(size: 14 * scale, weight: .bold)
                        .foregroundStyle(matchesFlowerDesign
                            ? Color(red: 37 / 255, green: 79 / 255, blue: 73 / 255)
                            : GrowthPalette.ink)
                        .padding(.leading, matchesFlowerDesign ? 6 * scale : 0)
                    Spacer()
                    Text(badge)
                        .gardenFont(size: 8 * scale)
                        .foregroundStyle(GrowthPalette.subtleInk)
                        .padding(.horizontal, 11 * scale)
                        .frame(height: 24 * scale)
                        .background(.white.opacity(0.75), in: Capsule())
                        .overlay(Capsule().stroke(GrowthPalette.music.opacity(0.3), lineWidth: 1 * scale))
                }
                HStack(spacing: 8 * scale) {
                    KakaAvatarView(matchesVariantScale: true)
                        .frame(width: 48 * scale, height: 48 * scale)
                    VStack(alignment: .leading, spacing: 2 * scale) {
                        Text("观察结论").gardenFont(size: 8 * scale).foregroundStyle(GrowthPalette.subtleInk)
                        Text(conclusion).gardenFont(size: 10 * scale, weight: .bold).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9 * scale)
                .frame(height: 55 * scale)
                .background(GrowthPalette.softMint, in: RoundedRectangle(cornerRadius: 12 * scale))

                HStack {
                    Text("行为依据").gardenFont(size: 8 * scale).foregroundStyle(GrowthPalette.subtleInk)
                    Text(behavior).gardenFont(size: 8 * scale).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 5 * scale) {
                    Circle().fill(Color(red: 237 / 255, green: 179 / 255, blue: 74 / 255)).frame(width: 6 * scale, height: 6 * scale)
                    Text("陪伴建议：\(suggestion)").gardenFont(size: 8 * scale).lineLimit(1).minimumScaleFactor(0.72)
                }
                .foregroundStyle(GrowthPalette.subtleInk)
                .padding(.horizontal, 10 * scale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 23 * scale)
                .background(Color(red: 255 / 255, green: 247 / 255, blue: 226 / 255), in: Capsule())
            }
            .padding(12 * scale)
            .background(Color(red: 245 / 255, green: 239 / 255, blue: 255 / 255).opacity(0.48), in: RoundedRectangle(cornerRadius: 22 * scale))
        }
        .frame(width: 362 * scale, height: 154 * scale)
    }
}

private struct GrowthFlowerLearningProfile: View {
    let records: [GrowthARActivity]
    let scale: CGFloat

    var body: some View {
        GrowthCard(cornerRadius: 22, scale: scale) {
            VStack(spacing: 8 * scale) {
                HStack {
                    Text("本周学习画像")
                        .gardenFont(size: 14 * scale, weight: .bold)
                        .foregroundStyle(Color(red: 49 / 255, green: 95 / 255, blue: 89 / 255))
                        .padding(.leading, 2 * scale)
                    Spacer()
                    Text("第一幕 · 立春").gardenFont(size: 8 * scale).foregroundStyle(GrowthPalette.subtleInk)
                }
                HStack(spacing: 14 * scale) {
                    ZStack {
                        Circle().stroke(GrowthPalette.empty, lineWidth: 9 * scale)
                        Circle().trim(from: 0, to: progress)
                            .stroke(Color(red: 111 / 255, green: 237 / 255, blue: 206 / 255), style: StrokeStyle(lineWidth: 9 * scale, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(completedSkillCount)/3").gardenFont(size: 20 * scale, weight: .bold)
                            Text("已学习").gardenFont(size: 8 * scale).foregroundStyle(GrowthPalette.subtleInk)
                        }
                    }
                    .frame(width: 72 * scale, height: 72 * scale)

                    VStack(spacing: 6 * scale) {
                        skillRow(icon: "eye.fill", title: "看表情", state: taskOne == nil ? "待学习" : "独立", active: taskOne != nil)
                        skillRow(icon: "face.smiling", title: "做表情", state: taskOne == nil ? "待学习" : (taskOne!.completedAfterHint ? "提示完成" : "独立"), active: taskOne != nil)
                        skillRow(icon: "speaker.wave.2.fill", title: "听声音", state: taskTwo == nil ? "待学习" : taskTwo!.statusText, active: taskTwo != nil)
                    }
                }
            }
            .padding(14 * scale)
            .background(GrowthPalette.softMint.opacity(0.8), in: RoundedRectangle(cornerRadius: 22 * scale))
        }
        .frame(width: 362 * scale, height: 144 * scale)
    }

    private var taskOne: GrowthARActivity? { records.first { $0.taskNumber == 1 } }
    private var taskTwo: GrowthARActivity? { records.first { $0.taskNumber == 2 } }
    private var completedSkillCount: Int { (taskOne == nil ? 0 : 2) + (taskTwo == nil ? 0 : 1) }
    private var progress: CGFloat { CGFloat(completedSkillCount) / 3 }

    private func skillRow(icon: String, title: String, state: String, active: Bool) -> some View {
        HStack(spacing: 7 * scale) {
            Image(systemName: icon)
                .font(.system(size: 9 * scale, weight: .medium))
                .foregroundStyle(active ? GrowthPalette.teal : GrowthPalette.faintInk)
            Text(title).gardenFont(size: 9 * scale, weight: .bold)
            Spacer()
            Text(state)
                .gardenFont(size: 8 * scale)
                .foregroundStyle(active ? GrowthPalette.teal : GrowthPalette.faintInk)
                .frame(width: 69 * scale, height: 19 * scale)
                .background(active ? GrowthPalette.mintPill : Color.white.opacity(0.72), in: Capsule())
        }
        .padding(.horizontal, 9 * scale)
        .frame(width: 244 * scale, height: 23 * scale)
        .background(Color.white.opacity(0.7), in: Capsule())
    }
}

private struct GrowthRecentARCard: View {
    let record: GrowthARActivity
    let scale: CGFloat

    var body: some View {
        GrowthCard(cornerRadius: 22, scale: scale) {
            VStack(alignment: .leading, spacing: 9 * scale) {
                HStack {
                    Text(record.taskTitle)
                        .gardenFont(size: 14 * scale, weight: .bold)
                        .foregroundStyle(Color(red: 49 / 255, green: 95 / 255, blue: 89 / 255))
                    Spacer()
                    Text(record.completedAfterHint ? "提示后完成" : "独立完成")
                        .gardenFont(size: 8 * scale)
                        .foregroundStyle(record.completedAfterHint ? GrowthPalette.music : GrowthPalette.teal)
                        .padding(.horizontal, 11 * scale)
                        .frame(height: 23 * scale)
                        .background(record.completedAfterHint ? GrowthPalette.musicPale : GrowthPalette.mintPill, in: Capsule())
                }
                Text("目标动作：\(record.taskNumber == 1 ? "嘴角向上" : "辨别上扬语气")")
                    .gardenFont(size: 8 * scale)
                    .foregroundStyle(GrowthPalette.subtleInk)

                HStack(spacing: 0) {
                    GrowthARStepNode(symbol: "xmark", title: "首次完成", subtitle: record.completedAfterHint ? "尚未完成" : "已完成", active: !record.completedAfterHint, scale: scale)
                    Capsule().fill(GrowthPalette.empty).frame(height: 3 * scale)
                    GrowthARStepNode(kaka: true, title: "KAKA示范", subtitle: record.completedAfterHint ? "提示1次" : "未使用", active: record.completedAfterHint, scale: scale)
                    Capsule().fill(GrowthPalette.empty).frame(height: 3 * scale)
                    GrowthARStepNode(symbol: "checkmark", title: "第\(record.attemptCount)次完成", subtitle: "答对完成", active: true, scale: scale)
                }
                Text("共尝试 \(record.attemptCount)次  ·  用时\(growthDuration(record.durationSeconds))")
                    .gardenFont(size: 8 * scale)
                    .foregroundStyle(GrowthPalette.subtleInk)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(16 * scale)
        }
        .frame(width: 362 * scale, height: 150 * scale)
    }
}

private struct GrowthARStepNode: View {
    var symbol: String = ""
    var kaka = false
    let title: String
    let subtitle: String
    let active: Bool
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 3 * scale) {
            ZStack {
                Circle().fill(active ? GrowthPalette.mintPill : GrowthPalette.empty)
                if kaka {
                    KakaAvatarView(matchesVariantScale: true).padding(1 * scale)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 11 * scale, weight: .bold))
                        .foregroundStyle(active ? GrowthPalette.teal : GrowthPalette.faintInk)
                }
            }
            .frame(width: 31 * scale, height: 31 * scale)
            Text(title).gardenFont(size: 7 * scale, weight: .bold)
            Text(subtitle).gardenFont(size: 7 * scale).foregroundStyle(GrowthPalette.subtleInk)
        }
        .frame(width: 73 * scale)
    }
}

private struct GrowthLearningStateCard: View {
    let records: [GrowthARActivity]
    let scale: CGFloat

    var body: some View {
        GrowthCard(cornerRadius: 22, scale: scale) {
            HStack(spacing: 0) {
                state("checkmark", "已经会", "看懂开心", done: records.contains { $0.taskNumber == 1 })
                Capsule().fill(GrowthPalette.empty).frame(height: 3 * scale)
                state("person.fill", "正在学", "做出开心", done: !records.isEmpty, kaka: true)
                Capsule().fill(GrowthPalette.empty).frame(height: 3 * scale)
                state("speaker.wave.2.fill", "下一步", "听懂开心声音", done: records.contains { $0.taskNumber == 2 })
            }
            .padding(.horizontal, 14 * scale)
            .frame(width: 362 * scale, height: 107 * scale)
        }
        .frame(width: 362 * scale, height: 107 * scale)
    }

    private func state(_ icon: String, _ title: String, _ subtitle: String, done: Bool, kaka: Bool = false) -> some View {
        VStack(spacing: 4 * scale) {
            ZStack {
                Circle().fill(done ? GrowthPalette.mintPill : GrowthPalette.empty)
                if kaka {
                    KakaAvatarView(matchesVariantScale: true).padding(1 * scale)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(done ? GrowthPalette.teal : GrowthPalette.faintInk)
                }
            }
            .frame(width: 32 * scale, height: 32 * scale)
            Text(title).gardenFont(size: 8 * scale).foregroundStyle(done ? GrowthPalette.teal : GrowthPalette.subtleInk)
            Text(subtitle).gardenFont(size: 8 * scale, weight: .bold)
        }
        .frame(width: 82 * scale)
    }
}

private struct GrowthRewardCard: View {
    let record: GrowthARActivity?
    let scale: CGFloat

    var body: some View {
        GrowthCard(cornerRadius: 18, scale: scale) {
            HStack(spacing: 12 * scale) {
                Image(record?.rewardName == "荷花" ? "ar_lotus_reward" : "ar_peach_reward")
                    .resizable().scaledToFit()
                    .frame(width: 42 * scale, height: 42 * scale)
                VStack(alignment: .leading, spacing: 3 * scale) {
                    Text(record == nil ? "本次鼓励：等待获得植物" : "本次鼓励：获得\(record!.rewardName)")
                        .gardenFont(size: 10 * scale, weight: .bold)
                    Text(record == nil ? "完成AR任务后会自动记录" : "第\(record!.attemptCount)次作答 · \(GrowthDate.monthDayChinese.string(from: record!.completedAt)) \(GrowthDate.time.string(from: record!.completedAt))")
                        .gardenFont(size: 8 * scale)
                        .foregroundStyle(GrowthPalette.subtleInk)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14 * scale)
            .frame(width: 362 * scale, height: 57 * scale)
            .background(GrowthPalette.softMint.opacity(0.85), in: RoundedRectangle(cornerRadius: 18 * scale))
        }
        .frame(width: 362 * scale, height: 57 * scale)
    }
}

private func growthDuration(_ seconds: Int) -> String {
    let minutes = max(1, Int(ceil(Double(seconds) / 60)))
    return "\(minutes)分钟"
}

private func growthClock(_ seconds: Int) -> String {
    let minutes = max(0, seconds / 60)
    let remainder = max(0, seconds % 60)
    return String(format: "%02d:%02d", minutes, remainder)
}

private extension Color {
    init?(growthHex: String) {
        let value = growthHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
