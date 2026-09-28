import SwiftUI
import UIKit

struct FigmaProfileView: View {
    var body: some View {
        SproutlyProfileFlowView()
    }
}

private struct SproutlyProfileFlowView: View {
    @EnvironmentObject private var store: GardenStore
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true
    @StateObject private var musicPlayback = MusicRecordPlaybackController.shared
    @State private var route: Route = .home
    @State private var selectedFlowerID: UUID?
    @State private var selectedEmotionID: UUID?
    @State private var emotionFilter: ProfileMood?
    @State private var pendingEmotionDeletionID: UUID?
    @State private var showsEmotionDeleteConfirmation = false
    @State private var pendingFlowerDeletionID: UUID?
    @State private var showsFlowerDeleteConfirmation = false

    private enum Route: Int {
        case home = 1
        case emotionAlbum = 2
        case flowerAlbum = 3
        case flowerDetail = 4
        case emotionDetail = 5
        case growthRecords = 6
        case parentManagement = 7
        case growthRecordsGate = 8
    }

    var body: some View {
        Group {
            switch route {
            case .home:
                ProfileCanvas { scale in profileHome(scale: scale) }
            case .emotionAlbum:
                ProfileCanvas { scale in emotionAlbum(scale: scale) }
            case .flowerAlbum:
                ProfileCanvas { scale in flowerAlbum(scale: scale) }
            case .flowerDetail:
                ProfileCanvas { scale in flowerDetail(scale: scale) }
            case .emotionDetail:
                ProfileCanvas { scale in emotionDetail(scale: scale) }
            case .growthRecordsGate:
                ParentVerificationFlowView(
                    purpose: .growthRecords,
                    onClose: { route = .home },
                    onVerified: { route = .growthRecords }
                )
            case .growthRecords:
                GrowthRecordsFlowView { route = .home }
            case .parentManagement:
                ParentCenterFlowView { route = .home }
            }
        }
        .onAppear { consumeRequestedPage() }
        .onChange(of: store.requestedProfilePage) { _, _ in consumeRequestedPage() }
        .onChange(of: route) { previous, current in
            if (previous == .emotionAlbum || previous == .emotionDetail)
                && current != .emotionDetail
                && musicPlayback.activeRecordID != nil {
                musicPlayback.stop()
            }
        }
        .onChange(of: selectedEmotionID) { _, id in
            guard route == .emotionDetail,
                  let id,
                  let record = filteredMusicEmotionRecords.first(where: { $0.id == id }) else {
                return
            }
            musicPlayback.play(record: record)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willResignActiveNotification
            )
        ) { _ in
            musicPlayback.pause()
            if route == .growthRecords {
                route = .growthRecordsGate
            }
        }
        .onDisappear {
            if musicPlayback.activeRecordID != nil {
                musicPlayback.stop()
            }
        }
        .alert(
            "删除这张情绪乐卡？",
            isPresented: $showsEmotionDeleteConfirmation
        ) {
            Button("取消", role: .cancel) {
                pendingEmotionDeletionID = nil
            }
            Button("删除", role: .destructive) {
                deletePendingEmotionRecord()
            }
        } message: {
            Text("照片、画稿和专属音乐也会一起删除，此操作无法撤销。")
        }
        .alert(
            "删除这张花签？",
            isPresented: $showsFlowerDeleteConfirmation
        ) {
            Button("取消", role: .cancel) {
                pendingFlowerDeletionID = nil
            }
            Button("删除", role: .destructive) {
                deletePendingFlowerTicket()
            }
        } message: {
            Text("这张花签和对应的图片会从本机删除，此操作无法撤销。")
        }
    }

    private func consumeRequestedPage() {
        guard let requested = store.requestedProfilePage else { return }
        route = Route(rawValue: requested) ?? .home
        if route == .growthRecords {
            route = .growthRecordsGate
        }
        if route == .flowerAlbum {
            selectedFlowerID = store.flowerTickets.first?.id
        } else if route == .emotionAlbum {
            selectedEmotionID = musicEmotionRecords.first?.id
        }
        store.requestedProfilePage = nil
    }

    private func profileHome(scale: CGFloat) -> some View {
        ZStack {
            ProfileGradient()

            Image("profile_header_bg")
                .resizable()
                .scaledToFill()
                .frame(width: 595 * scale, height: 338 * scale)
                .clipped()
                .position(x: 172 * scale, y: 169 * scale)

            LinearGradient(
                colors: [.clear, Color(red: 38 / 255, green: 68 / 255, blue: 68 / 255).opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 584 * scale, height: 370 * scale)
            .position(x: 192 * scale, y: 185 * scale)

            RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 244 / 255, green: 251 / 255, blue: 248 / 255),
                            Color(red: 218 / 255, green: 239 / 255, blue: 232 / 255)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 402 * scale, height: 541 * scale)
                .position(x: 201 * scale, y: 618 * scale)

            Image("profile_child_avatar")
                .resizable()
                .scaledToFill()
                .frame(width: 109 * scale, height: 109 * scale)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.78), lineWidth: 2 * scale))
                .position(x: 103 * scale, y: 136 * scale)

            VStack(alignment: .leading, spacing: 4 * scale) {
                Text("青青")
                    .gardenFont(size: 22 * scale, weight: .bold)
                Text("qīng qīng")
                    .gardenFont(size: 11 * scale, weight: .medium)
                    .tracking(1.2 * scale)
                Text("灵想号：2025200000")
                    .gardenFont(size: 9 * scale, weight: .medium)
                    .padding(.top, 4 * scale)
                Text("IP：成都")
                    .gardenFont(size: 9 * scale, weight: .medium)
            }
            .foregroundStyle(.white)
            .frame(width: 150 * scale, alignment: .leading)
            .position(x: 258 * scale, y: 140 * scale)

            KakaAvatarView(matchesVariantScale: true)
                .frame(width: 113 * scale, height: 113 * scale)
                .rotationEffect(.degrees(-9))
                .id(store.kakaAppearance)
                .position(x: 363 * scale, y: 188 * scale)

            profileToolButton(
                title: "数据记录",
                subtitle: "孩子的成长记录",
                systemImage: "chart.xyaxis.line",
                x: 118.5,
                scale: scale
            ) {
                route = .growthRecordsGate
            }

            profileToolButton(
                title: "家长管理",
                subtitle: "账号与设置",
                systemImage: "person.2.fill",
                x: 307.5,
                scale: scale
            ) {
                route = .parentManagement
            }

            profileCollectionEntry(
                kind: .music,
                y: 476.25,
                scale: scale
            ) {
                route = .emotionAlbum
            }

            profileCollectionEntry(
                kind: .flower,
                y: 701.25,
                scale: scale
            ) {
                selectedFlowerID = store.flowerTickets.first?.id
                route = .flowerAlbum
            }

            Button {
                if musicPlayback.activeRecordID != nil {
                    musicPlayback.stop()
                }
                store.selectedTab = .garden
            } label: {
                Image("profile_back")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48 * scale, height: 48 * scale)
            }
            .buttonStyle(.plain)
            .position(x: 348 * scale, y: 74 * scale)
            .accessibilityLabel("返回首页")
        }
    }

    private func profileToolButton(
        title: String,
        subtitle: String,
        systemImage: String,
        x: CGFloat,
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9 * scale) {
                Image(systemName: systemImage)
                    .font(.system(size: 20 * scale, weight: .medium))
                VStack(alignment: .leading, spacing: 1 * scale) {
                    Text(title).gardenFont(size: 13 * scale, weight: .bold)
                    Text(subtitle).gardenFont(size: 8 * scale, weight: .medium)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11 * scale, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11 * scale)
            .frame(width: 173 * scale, height: 51 * scale)
            .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 16 * scale))
            .overlay {
                RoundedRectangle(cornerRadius: 16 * scale)
                    .stroke(.white.opacity(0.26), lineWidth: 1 * scale)
            }
            .shadow(color: Color(red: 41 / 255, green: 79 / 255, blue: 74 / 255).opacity(0.09), radius: 4 * scale, y: 4 * scale)
        }
        .buttonStyle(.plain)
        .position(x: x * scale, y: 272 * scale)
    }

    private enum ProfileEntryKind: Equatable {
        case music
        case flower
    }

    private func profileCollectionEntry(
        kind: ProfileEntryKind,
        y: CGFloat,
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        let isMusic = kind == .music
        let latestTicket = store.flowerTickets.first
        let latestMusic = musicEmotionRecords.first.map(emotionPresentation(for:))
        return Button(action: action) {
            ZStack {
                LinearGradient(
                    colors: isMusic
                        ? [Color(red: 232 / 255, green: 232 / 255, blue: 252 / 255), Color(red: 212 / 255, green: 242 / 255, blue: 242 / 255)]
                        : [Color(red: 222 / 255, green: 245 / 255, blue: 222 / 255), Color(red: 1, green: 240 / 255, blue: 212 / 255)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                Image(isMusic ? "profile_music_icon" : "profile_flower_icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34 * scale, height: 34 * scale)
                    .position(x: 33.5 * scale, y: 31.5 * scale)

                VStack(alignment: .leading, spacing: 0) {
                    Text(isMusic ? "情绪乐卡" : "我的花房")
                        .gardenFont(size: 18 * scale, weight: .bold)
                    Text(isMusic ? "qíng xù yuè kǎ" : "wǒ de huā fáng")
                        .gardenFont(size: 9 * scale, weight: .medium)
                        .tracking(0.8 * scale)
                        .foregroundStyle(Color(red: 92 / 255, green: 125 / 255, blue: 99 / 255))
                }
                .foregroundStyle(Color(red: 31 / 255, green: 82 / 255, blue: 64 / 255))
                .frame(width: 150 * scale, alignment: .leading)
                .position(x: 135.5 * scale, y: 31.5 * scale)

                ZStack {
                    RoundedRectangle(cornerRadius: 15 * scale)
                        .fill(
                            LinearGradient(
                                colors: [.pink.opacity(0.35), .cyan.opacity(0.45)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 137 * scale, height: 118 * scale)
                        .rotationEffect(.degrees(4))
                        .offset(x: 9 * scale, y: 5 * scale)

                    RoundedRectangle(cornerRadius: 15 * scale)
                        .fill(.white.opacity(0.68))
                        .frame(width: 137 * scale, height: 118 * scale)

                    Group {
                        if isMusic, let latestMusic {
                            EmotionMusicArtworkView(data: latestMusic, contentMode: .fill)
                        } else if let latestTicket, !isMusic, let image = store.flowerTicketImage(for: latestTicket) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(isMusic ? "profile_home_music_artwork" : "profile_home_room")
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .frame(width: 160 * scale, height: 116 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 15 * scale))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15 * scale)
                            .stroke(.white.opacity(0.95), lineWidth: 5 * scale)
                    }
                    .rotationEffect(.degrees(-8.7))
                    .shadow(color: Color(red: 46 / 255, green: 64 / 255, blue: 92 / 255).opacity(0.18), radius: 5 * scale, y: 5 * scale)
                    .offset(x: -9 * scale, y: 6 * scale)
                }
                .frame(width: 180 * scale, height: 142 * scale)
                .position(x: 97 * scale, y: 118 * scale)

                if isMusic {
                    Group {
                        if let face = latestMusic?.face {
                            Image(uiImage: face)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(latestMusic?.fallbackFaceAsset ?? "profile_home_face")
                                .resizable()
                                .scaledToFill()
                        }
                    }
                        .frame(width: 43 * scale, height: 43 * scale)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2 * scale))
                        .position(x: 146 * scale, y: 165 * scale)
                }

                VStack(alignment: .leading, spacing: 3 * scale) {
                    Text(isMusic ? "今日获得" : "今日装扮")
                        .gardenFont(size: 9 * scale, weight: .medium)
                    HStack(alignment: .firstTextBaseline, spacing: 2 * scale) {
                        Text("\(isMusic ? todayMusicCardCount : store.flowerTickets.count)")
                            .gardenFont(size: 24 * scale, weight: .medium)
                        Text(isMusic ? "张新的卡片" : "个新的花房")
                            .gardenFont(size: 9 * scale, weight: .medium)
                    }
                }
                .foregroundStyle(Color(red: 49 / 255, green: 91 / 255, blue: 93 / 255))
                .frame(width: 108 * scale, alignment: .leading)
                .position(x: 291 * scale, y: 97 * scale)

                HStack(spacing: 9 * scale) {
                    Text(isMusic ? "打开卡包" : "进入花房")
                        .gardenFont(size: 14 * scale, weight: .bold)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14 * scale, weight: .bold))
                }
                .foregroundStyle(Color(red: 46 / 255, green: 119 / 255, blue: 120 / 255))
                .frame(width: 104 * scale, height: 38 * scale)
                .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 11 * scale))
                .position(x: 290 * scale, y: 158 * scale)
            }
            .frame(width: 362 * scale, height: 196 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 24 * scale, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24 * scale)
                    .stroke(.white.opacity(0.72), lineWidth: 1.5 * scale)
            }
            .shadow(color: Color(red: 64 / 255, green: 77 / 255, blue: 122 / 255).opacity(0.13), radius: 9 * scale, y: 8 * scale)
        }
        .buttonStyle(.plain)
        .position(x: 201 * scale, y: y * scale)
    }

    private func emotionAlbum(scale: CGFloat) -> some View {
        ZStack {
            ProfileGradient()
            profileBackButton(scale: scale) {
                musicPlayback.stop()
                route = .home
            }
                .position(x: 44 * scale, y: 78 * scale)

            ProfilePageTitle(
                icon: "profile_music_icon",
                title: "情绪乐卡",
                pinyin: "qíng xù yuè kǎ",
                scale: scale
            )
            .position(x: 201 * scale, y: 79 * scale)

            HStack(spacing: 13 * scale) {
                ForEach(ProfileMood.allCases) { mood in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            emotionFilter = emotionFilter == mood ? nil : mood
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        ProfileMoodFilterIcon(
                            mood: mood,
                            isSelected: emotionFilter == mood,
                            scale: scale
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("筛选\(mood.title)乐卡")
                    .accessibilityAddTraits(emotionFilter == mood ? .isSelected : [])
                }
            }
            .position(x: 201 * scale, y: 142 * scale)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [
                        GridItem(.fixed(174 * scale), spacing: 14 * scale),
                        GridItem(.fixed(174 * scale))
                    ],
                    spacing: 18 * scale
                ) {
                    ForEach(filteredMusicEmotionRecords) { record in
                        ZStack(alignment: .topLeading) {
                            Button {
                                selectedEmotionID = record.id
                                route = .emotionDetail
                                musicPlayback.play(record: record)
                            } label: {
                                ProfileEmotionCard(
                                    data: emotionPresentation(for: record),
                                    isPlaying: musicPlayback.activeRecordID == record.id
                                        && musicPlayback.isPlaying,
                                    scale: scale
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                musicPlayback.toggle(record: record)
                            } label: {
                                Color.clear
                                    .frame(width: 44 * scale, height: 44 * scale)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .position(x: 27 * scale, y: 196 * scale)
                            .accessibilityLabel(
                                musicPlayback.activeRecordID == record.id
                                    && musicPlayback.isPlaying
                                    ? "暂停这张情绪乐卡"
                                    : "播放这张情绪乐卡"
                            )
                        }
                        .frame(width: 174 * scale, height: 264 * scale)
                    }

                    ForEach(
                        0..<max(6 - filteredMusicEmotionRecords.count, 0),
                        id: \.self
                    ) { index in
                        ProfileEmotionPlaceholder(
                            tint: emotionPlaceholderTints[index % emotionPlaceholderTints.count],
                            scale: scale
                        )
                    }
                }
                .padding(.bottom, 20 * scale)
            }
            .frame(width: 362 * scale, height: 650 * scale)
            .position(x: 201 * scale, y: 515 * scale)
        }
    }

    private func flowerAlbum(scale: CGFloat) -> some View {
        ZStack {
            ProfileGradient()
            profileBackButton(scale: scale) { route = .home }
                .position(x: 44 * scale, y: 78 * scale)

            ProfilePageTitle(
                icon: "profile_flower_icon",
                title: "我的花房",
                pinyin: "wǒ de huā fáng",
                scale: scale
            )
            .position(x: 201 * scale, y: 79 * scale)

            ZStack {
                Image("profile_flower_machine_shell")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 381 * scale, height: 151 * scale)
                ZStack {
                    Circle().fill(.white.opacity(0.88))
                    Circle().stroke(Color(red: 108 / 255, green: 173 / 255, blue: 148 / 255), lineWidth: 2 * scale)
                    KakaAvatarView(matchesVariantScale: true)
                        .padding(8 * scale)
                }
                .frame(width: 80 * scale, height: 80 * scale)
                .offset(y: -14 * scale)
            }
            .position(x: 201 * scale, y: 190 * scale)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [
                        GridItem(.fixed(174 * scale), spacing: 14 * scale),
                        GridItem(.fixed(174 * scale))
                    ],
                    spacing: 18 * scale
                ) {
                    ForEach(store.flowerTickets) { record in
                        Button {
                            selectedFlowerID = record.id
                            route = .flowerDetail
                        } label: {
                            ProfileFlowerCard(
                                record: record,
                                image: store.flowerTicketImage(for: record),
                                scale: scale
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(0..<max(4 - store.flowerTickets.count, 0), id: \.self) { index in
                        ProfileFlowerPlaceholder(
                            tint: index.isMultiple(of: 2) ? .pink : .purple,
                            scale: scale
                        )
                    }
                }
                .padding(.bottom, 20 * scale)
            }
            .frame(width: 362 * scale, height: 546 * scale)
            .position(x: 201 * scale, y: 567 * scale)
        }
    }

    private func flowerDetail(scale: CGFloat) -> some View {
        let selected = selectedFlowerRecord
        return ZStack {
            Group {
                if let selected, let image = store.flowerTicketImage(for: selected) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image("profile_room_sample1")
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 402 * scale, height: 874 * scale)
            .clipped()
            .blur(radius: 4 * scale)
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

            profileBackButton(scale: scale) { route = .flowerAlbum }
                .frame(width: 52 * scale, height: 52 * scale)
                .position(x: 46 * scale, y: 80 * scale)
                .zIndex(10)

            if store.flowerTickets.isEmpty {
                VStack(spacing: 10 * scale) {
                    Image("profile_flower_icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54 * scale, height: 54 * scale)
                    Text("还没有花签")
                        .gardenFont(size: 17 * scale, weight: .bold)
                    Text("回到 AR 世界放置植物后，就能生成第一张花签。")
                        .gardenFont(size: 11 * scale, weight: .medium)
                        .multilineTextAlignment(.center)
                        .frame(width: 230 * scale)
                }
                .foregroundStyle(Color(red: 49 / 255, green: 91 / 255, blue: 93 / 255))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 40 * scale) {
                        ForEach(store.flowerTickets) { record in
                            FlowerTicketCard(
                                image: store.flowerTicketImage(for: record) ?? UIImage(),
                                number: record.number,
                                plantCount: record.plantCount,
                                timestamp: record.timestamp
                            )
                            .frame(width: 258 * scale, height: 626 * scale)
                            .id(record.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 72 * scale, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedFlowerID, anchor: .center)
                .frame(width: 402 * scale, height: 674 * scale)
                .position(x: 201 * scale, y: 444 * scale)
            }
        }
    }

    private var selectedFlowerRecord: FlowerTicketRecord? {
        guard let selectedFlowerID else { return store.flowerTickets.first }
        return store.flowerTickets.first { $0.id == selectedFlowerID }
            ?? store.flowerTickets.first
    }

    private var musicEmotionRecords: [EmotionRecord] {
        store.emotionRecords
            .filter { $0.source == .musicReflection && $0.musicSession != nil }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var filteredMusicEmotionRecords: [EmotionRecord] {
        guard let emotionFilter else { return musicEmotionRecords }
        return musicEmotionRecords.filter { emotionFilter.matches($0) }
    }

    private var todayMusicCardCount: Int {
        musicEmotionRecords.filter {
            Calendar.autoupdatingCurrent.isDateInToday($0.timestamp)
        }.count
    }

    private var emotionPlaceholderTints: [Color] {
        [
            Color(red: 191 / 255, green: 225 / 255, blue: 215 / 255),
            Color(red: 205 / 255, green: 190 / 255, blue: 232 / 255),
            Color(red: 235 / 255, green: 190 / 255, blue: 203 / 255),
            Color(red: 238 / 255, green: 215 / 255, blue: 146 / 255)
        ]
    }

    private var selectedEmotionPresentation: EmotionMusicCardPresentation? {
        let records = filteredMusicEmotionRecords
        let record = selectedEmotionID.flatMap { selectedID in
            records.first { $0.id == selectedID }
        } ?? records.first
        return record.map(emotionPresentation(for:))
    }

    private func emotionPresentation(
        for record: EmotionRecord
    ) -> EmotionMusicCardPresentation {
        let details = record.musicSession
        return EmotionMusicCardPresentation(
            id: record.id,
            artwork: MusicArtworkSnapshotStore.load(details?.artworkImageName),
            fallbackArtworkAsset: "profile_emotion_artwork",
            face: MusicFaceSnapshotStore.load(details?.faceImageName),
            fallbackFaceAsset: "profile_emotion_avatar",
            moodAsset: ProfileMood.moodAsset(
                forCheckInMood: details?.afterMood,
                fallbackEmotion: record.emotion
            ),
            avatarHaloColor: ProfileMood.haloColor(
                forCheckInMood: details?.afterMood,
                fallbackEmotion: record.emotion
            ),
            timestamp: record.timestamp,
            theme: ProfileMood.diaryTitle(for: details?.world),
            durationSeconds: details?.durationSeconds ?? 0,
            moodColors: (details?.moodColorHexes ?? []).compactMap(Color.init(hex:)),
            reflection: ProfileMood.reflection(for: details?.world)
        )
    }

    private func emotionDetail(scale: CGFloat) -> some View {
        ZStack {
            if filteredMusicEmotionRecords.isEmpty {
                ProfileGradient()
                Text("还没有可以查看的情绪乐卡")
                    .gardenFont(size: 15 * scale, weight: .bold)
                    .foregroundStyle(Color(red: 49 / 255, green: 91 / 255, blue: 93 / 255))
            } else {
                if let selectedEmotionPresentation {
                    EmotionMusicRecordBackdrop(data: selectedEmotionPresentation)
                        .frame(width: 402 * scale, height: 874 * scale)
                }

                if filteredMusicEmotionRecords.count > 1 {
                    EmotionMusicCardBack()
                        .frame(width: 338 * scale, height: 659 * scale)
                        .position(x: 201 * scale, y: 455 * scale)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(filteredMusicEmotionRecords) { record in
                            ZStack {
                                EmotionMusicDiaryCard(data: emotionPresentation(for: record))
                                    .frame(width: 338 * scale, height: 656 * scale)
                                    .offset(y: 18 * scale)
                            }
                            .frame(width: 402 * scale, height: 874 * scale)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                    .rotation3DEffect(
                                        .degrees(Double(phase.value) * -10),
                                        axis: (x: 0, y: 1, z: 0),
                                        perspective: 0.72
                                    )
                                    .offset(y: abs(phase.value) * 18 * scale)
                                    .opacity(phase.isIdentity ? 1 : 0.58)
                            }
                            .id(record.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: $selectedEmotionID, anchor: .center)
                .frame(width: 402 * scale, height: 874 * scale)
            }

            Button {
                musicPlayback.stop()
                route = .emotionAlbum
            } label: {
                Image("profile_emotion_back")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48 * scale, height: 48 * scale)
            }
            .buttonStyle(.plain)
            .position(x: 48 * scale, y: 84 * scale)
            .zIndex(20)
            .accessibilityLabel("返回情绪乐卡卡册")

        }
    }

    private func deletePendingEmotionRecord() {
        guard let id = pendingEmotionDeletionID else { return }
        musicPlayback.stop()
        _ = store.deleteEmotionRecord(id: id)
        pendingEmotionDeletionID = nil
        showsEmotionDeleteConfirmation = false
        selectedEmotionID = nil
        route = .emotionAlbum
    }

    private func deletePendingFlowerTicket() {
        guard let id = pendingFlowerDeletionID else { return }
        _ = store.deleteFlowerTicket(id: id)
        pendingFlowerDeletionID = nil
        showsFlowerDeleteConfirmation = false

        if let next = store.flowerTickets.first {
            selectedFlowerID = next.id
        } else {
            selectedFlowerID = nil
            route = .flowerAlbum
        }
    }

    private func detailInfo(
        title: String,
        value: String,
        width: CGFloat,
        scale: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Text(title).gardenFont(size: 9 * scale, weight: .medium)
            Text(value).gardenFont(size: 11 * scale, weight: .bold)
        }
        .foregroundStyle(Color(red: 67 / 255, green: 91 / 255, blue: 87 / 255))
        .frame(width: width * scale, alignment: .leading)
    }

    private func detailDivider(scale: CGFloat) -> some View {
        Rectangle()
            .fill(Color(red: 200 / 255, green: 191 / 255, blue: 175 / 255))
            .frame(width: 1 * scale, height: 36 * scale)
    }

    private func profileBackButton(
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
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

}

private enum ProfileMood: String, CaseIterable, Identifiable, Equatable {
    case happy
    case calm
    case sad
    case angry
    case afraid

    var id: String { rawValue }
    var asset: String { "profile_mood_\(rawValue)" }

    var unselectedAsset: String {
        self == .calm ? "profile_mood_calm_unselected" : asset
    }

    var unselectedFrameSize: CGSize {
        self == .sad ? CGSize(width: 55, height: 55) : CGSize(width: 39, height: 40)
    }

    var selectedFrameSize: CGSize {
        self == .sad ? CGSize(width: 68, height: 68) : CGSize(width: 48, height: 49)
    }

    var title: String {
        switch self {
        case .happy: "开心"
        case .calm: "平静"
        case .sad: "难过"
        case .angry: "生气"
        case .afraid: "紧张"
        }
    }

    func matches(_ record: EmotionRecord) -> Bool {
        let checkedInMood = record.musicSession?.afterMood
        switch self {
        case .happy:
            return checkedInMood.map { ["开心", "快乐"].contains($0) }
                ?? (record.emotion == .joy)
        case .calm:
            return checkedInMood.map { ["平静", "放松"].contains($0) }
                ?? (record.emotion == .calm)
        case .sad:
            return checkedInMood.map { ["难过", "低落"].contains($0) }
                ?? (record.emotion == .low)
        case .angry:
            return checkedInMood.map { $0 == "生气" }
                ?? (record.emotion == .expectation)
        case .afraid:
            return checkedInMood.map { ["害怕", "紧张"].contains($0) }
                ?? false
        }
    }

    static func moodAsset(
        forCheckInMood mood: String?,
        fallbackEmotion emotion: EmotionKind
    ) -> String {
        switch mood {
        case "开心", "快乐": "music_checkin_happy"
        case "平静", "放松": "music_checkin_calm"
        case "难过", "低落": "music_checkin_low"
        case "生气": "music_checkin_angry"
        case "害怕", "紧张": "music_checkin_tense"
        default:
            switch emotion {
            case .joy: "music_checkin_happy"
            case .calm: "music_checkin_calm"
            case .low: "music_checkin_low"
            case .expectation: "music_checkin_tense"
            }
        }
    }

    static func haloColor(
        forCheckInMood mood: String?,
        fallbackEmotion emotion: EmotionKind
    ) -> Color {
        switch mood {
        case "开心", "快乐":
            Color(red: 241 / 255, green: 215 / 255, blue: 120 / 255)
        case "平静", "放松":
            Color(red: 143 / 255, green: 214 / 255, blue: 201 / 255)
        case "难过", "低落":
            Color(red: 148 / 255, green: 170 / 255, blue: 218 / 255)
        case "生气":
            Color(red: 228 / 255, green: 163 / 255, blue: 172 / 255)
        case "害怕", "紧张":
            Color(red: 197 / 255, green: 174 / 255, blue: 217 / 255)
        default:
            switch emotion {
            case .joy:
                Color(red: 241 / 255, green: 215 / 255, blue: 120 / 255)
            case .calm:
                Color(red: 143 / 255, green: 214 / 255, blue: 201 / 255)
            case .low:
                Color(red: 148 / 255, green: 170 / 255, blue: 218 / 255)
            case .expectation:
                Color(red: 197 / 255, green: 174 / 255, blue: 217 / 255)
            }
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
        case "低落": "一个安静的小花园。颜色慢慢亮起来，心也被温柔地接住。"
        case "生气": "热烈的颜色逐渐变得柔和，心里的风也慢慢停了下来。"
        case "紧张": "轻轻的颜色围在身边，呼吸变慢，身体也一点点放松。"
        default: "今天的颜色和音乐，都被好好收藏在这张乐卡里。"
        }
    }
}

private struct ProfileMoodFilterIcon: View {
    let mood: ProfileMood
    let isSelected: Bool
    let scale: CGFloat

    var body: some View {
        ZStack {
            if isSelected, mood == .calm {
                // 设计稿中的平静选中态素材已包含白边与 4pt 柔和阴影。
                Image(mood.asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60 * scale, height: 61 * scale)
            } else if isSelected {
                ZStack {
                    Image(mood.unselectedAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: mood.selectedFrameSize.width * scale,
                            height: mood.selectedFrameSize.height * scale
                        )

                    Circle()
                        .strokeBorder(.white, lineWidth: 3 * scale)
                        .frame(width: 43 * scale, height: 43 * scale)
                }
                .compositingGroup()
                .shadow(color: .black.opacity(0.25), radius: 2 * scale, y: 4 * scale)
            } else {
                Image(mood.unselectedAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: mood.unselectedFrameSize.width * scale,
                        height: mood.unselectedFrameSize.height * scale
                    )
            }
        }
        .frame(width: 60 * scale, height: 61 * scale)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}

private struct ProfileCanvas<Content: View>: View {
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

private struct ProfileGradient: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 244 / 255, green: 251 / 255, blue: 248 / 255),
                Color(red: 218 / 255, green: 239 / 255, blue: 232 / 255)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct ProfilePageTitle: View {
    let icon: String
    let title: String
    let pinyin: String
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 8 * scale) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 40 * scale, height: 40 * scale)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).gardenFont(size: 20 * scale, weight: .bold)
                Text(pinyin).gardenFont(size: 9 * scale, weight: .medium)
            }
        }
        .foregroundStyle(Color(red: 17 / 255, green: 78 / 255, blue: 78 / 255))
    }
}

private struct ProfileEmotionCard: View {
    let data: EmotionMusicCardPresentation
    let isPlaying: Bool
    let scale: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22 * scale)
                .fill(Color(red: 248 / 255, green: 242 / 255, blue: 230 / 255))
            EmotionMusicArtworkView(data: data, contentMode: .fill)
                .frame(width: 158 * scale, height: 154 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 16 * scale))
                .overlay {
                    RoundedRectangle(cornerRadius: 16 * scale)
                        .stroke(Color(red: 204 / 255, green: 207 / 255, blue: 242 / 255).opacity(0.65), lineWidth: 4 * scale)
                }
                .position(x: 87 * scale, y: 84 * scale)
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
                .frame(width: 38 * scale, height: 38 * scale)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2 * scale))
                .position(x: 145 * scale, y: 156 * scale)
            HStack(spacing: 8 * scale) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13 * scale, weight: .bold))
                    .foregroundStyle(Color(red: 47 / 255, green: 91 / 255, blue: 93 / 255))
                    .frame(width: 36 * scale, height: 36 * scale)
                    .background(Color(red: 219 / 255, green: 236 / 255, blue: 233 / 255), in: Circle())
                EmotionMusicWave(seed: data.id.hashValue)
                    .frame(width: 56 * scale, height: 26 * scale)

                HStack(spacing: 5 * scale) {
                    ForEach(Array(displayColors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 11 * scale, height: 11 * scale)
                    }
                }
            }
            .position(x: 84 * scale, y: 196 * scale)
            Text(dateText)
                .gardenFont(size: 10 * scale, weight: .medium)
                .foregroundStyle(Color(red: 49 / 255, green: 91 / 255, blue: 93 / 255))
                .position(x: 42 * scale, y: 239 * scale)
            Image(systemName: "arrow.right")
                .font(.system(size: 18 * scale, weight: .medium))
                .foregroundStyle(Color(red: 49 / 255, green: 91 / 255, blue: 93 / 255))
                .position(x: 145 * scale, y: 238 * scale)
        }
        .frame(width: 174 * scale, height: 264 * scale)
        .overlay {
            RoundedRectangle(cornerRadius: 22 * scale)
                .stroke(.white.opacity(0.8), lineWidth: 1.5 * scale)
        }
        .shadow(color: Color(red: 51 / 255, green: 69 / 255, blue: 97 / 255).opacity(0.16), radius: 8 * scale, y: 7 * scale)
    }

    private var displayColors: [Color] {
        let fallback = [
            Color(red: 98 / 255, green: 85 / 255, blue: 181 / 255),
            Color(red: 112 / 255, green: 146 / 255, blue: 196 / 255),
            Color(red: 132 / 255, green: 154 / 255, blue: 77 / 255)
        ]
        return Array((data.moodColors + fallback).prefix(3))
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: data.timestamp).uppercased()
    }
}

private struct ProfileFlowerCard: View {
    let record: FlowerTicketRecord
    let image: UIImage?
    let scale: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22 * scale)
                .fill(Color(red: 249 / 255, green: 243 / 255, blue: 229 / 255))
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(red: 231 / 255, green: 241 / 255, blue: 233 / 255)
                }
            }
            .frame(width: 158 * scale, height: 176 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 16 * scale))
            .overlay {
                RoundedRectangle(cornerRadius: 16 * scale)
                    .stroke(.white, lineWidth: 5 * scale)
            }
            .position(x: 87 * scale, y: 95 * scale)
            Rectangle()
                .fill(Color(red: 205 / 255, green: 198 / 255, blue: 181 / 255).opacity(0.65))
                .frame(width: 146 * scale, height: 1 * scale)
                .position(x: 87 * scale, y: 201 * scale)
            Image("ticket_info_plant")
                .resizable()
                .scaledToFit()
                .frame(width: 28 * scale, height: 28 * scale)
                .position(x: 30 * scale, y: 229 * scale)
            Text(monthDay(record.timestamp))
                .gardenFont(size: 10 * scale, weight: .medium)
                .foregroundStyle(Color(red: 49 / 255, green: 91 / 255, blue: 93 / 255))
                .position(x: 73 * scale, y: 229 * scale)
            Image(systemName: "arrow.right")
                .font(.system(size: 18 * scale, weight: .medium))
                .foregroundStyle(Color(red: 49 / 255, green: 91 / 255, blue: 93 / 255))
                .position(x: 145 * scale, y: 229 * scale)
        }
        .frame(width: 174 * scale, height: 264 * scale)
        .overlay {
            RoundedRectangle(cornerRadius: 22 * scale)
                .stroke(.white.opacity(0.85), lineWidth: 1.5 * scale)
        }
        .shadow(color: Color(red: 51 / 255, green: 79 / 255, blue: 59 / 255).opacity(0.16), radius: 8 * scale, y: 7 * scale)
    }

    private func monthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: date).uppercased()
    }
}

private struct ProfileFlowerPlaceholder: View {
    let tint: Color
    let scale: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 22 * scale)
            .fill(.white.opacity(0.28))
            .frame(width: 174 * scale, height: 264 * scale)
            .overlay {
                RoundedRectangle(cornerRadius: 22 * scale)
                    .stroke(
                        Color(red: 143 / 255, green: 192 / 255, blue: 169 / 255).opacity(0.58),
                        style: StrokeStyle(lineWidth: 1.5 * scale, dash: [7 * scale, 6 * scale])
                    )
            }
            .overlay {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.36))
                        .frame(width: 58 * scale, height: 58 * scale)
                    Image("profile_flower_icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38 * scale, height: 38 * scale)
                        .colorMultiply(tint.opacity(0.58))
                }
            }
    }
}

private struct ProfileEmotionPlaceholder: View {
    let tint: Color
    let scale: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
            .fill(.white.opacity(0.22))
            .frame(width: 174 * scale, height: 264 * scale)
            .overlay {
                RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                    .stroke(
                        Color(red: 143 / 255, green: 192 / 255, blue: 187 / 255)
                            .opacity(0.58),
                        style: StrokeStyle(
                            lineWidth: 1.5 * scale,
                            dash: [7 * scale, 6 * scale]
                        )
                    )
            }
            .overlay {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.34))
                        .frame(width: 58 * scale, height: 58 * scale)
                    Image("profile_flower_icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38 * scale, height: 38 * scale)
                        .colorMultiply(tint)
                        .opacity(0.72)
                }
            }
            .accessibilityHidden(true)
    }
}

private extension Color {
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
