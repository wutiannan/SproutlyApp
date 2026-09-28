import AVFoundation
import SwiftUI
import UIKit

enum AppTab: String, CaseIterable {
    case garden = "花园"
    case mood = "心情"
    case room = "布置"
    case profile = "我的"

    var icon: String {
        switch self {
        case .garden: return "leaf.fill"
        case .mood: return "sparkles"
        case .room: return "camera.viewfinder"
        case .profile: return "person.fill"
        }
    }
}

enum EmotionKind: String, Codable, CaseIterable, Identifiable {
    case joy
    case calm
    case expectation
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .joy: "愉悦"
        case .calm: "平静"
        case .expectation: "期待"
        case .low: "低落"
        }
    }

    var chartValue: Double {
        switch self {
        case .low: 0.65
        case .calm: 1.55
        case .expectation: 2.45
        case .joy: 3.35
        }
    }

    var chartColor: Color {
        switch self {
        case .joy: Color(red: 0.83, green: 0.98, blue: 0.35)
        case .calm: Color(red: 0.30, green: 0.91, blue: 0.70)
        case .expectation: Color(red: 0.44, green: 0.80, blue: 0.98)
        case .low: Color(red: 1.00, green: 0.62, blue: 0.59)
        }
    }

    init?(displayName: String) {
        switch displayName {
        case "开心", "愉悦", "闪耀": self = .joy
        case "平静", "放松": self = .calm
        case "期待", "兴奋": self = .expectation
        case "低落", "难过": self = .low
        default: return nil
        }
    }
}

enum EmotionRecordSource: String, Codable {
    case homeCheckIn
    case musicCheckIn
    case musicReflection
}

struct MusicSessionDetails: Codable, Hashable {
    let world: String
    let beforeMood: String
    let afterMood: String
    let completion: Double
    let dominantHue: Double
    let meanSaturation: Double
    let warmProportion: Double
    let artworkIndex: Int
    let faceImageName: String?
    let artworkImageName: String?
    let moodColorHexes: [String]?
    let durationSeconds: Int?
    let audioFileName: String?

    init(
        world: String,
        beforeMood: String,
        afterMood: String,
        completion: Double,
        dominantHue: Double,
        meanSaturation: Double,
        warmProportion: Double,
        artworkIndex: Int,
        faceImageName: String?,
        artworkImageName: String?,
        moodColorHexes: [String]?,
        durationSeconds: Int?,
        audioFileName: String? = nil
    ) {
        self.world = world
        self.beforeMood = beforeMood
        self.afterMood = afterMood
        self.completion = completion
        self.dominantHue = dominantHue
        self.meanSaturation = meanSaturation
        self.warmProportion = warmProportion
        self.artworkIndex = artworkIndex
        self.faceImageName = faceImageName
        self.artworkImageName = artworkImageName
        self.moodColorHexes = moodColorHexes
        self.durationSeconds = durationSeconds
        self.audioFileName = audioFileName
    }
}

enum MusicSessionAudioStore {
    static func makeRecordingURL() -> (name: String, url: URL)? {
        // AVAudioEngine 的实时输出直接写入线性 PCM 最稳定，避免 AAC 编码器在
        // 部分真机音频格式下创建成功但实际无法落盘。
        let name = UUID().uuidString + ".caf"
        let directory = recordingsDirectory
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return (name, directory.appendingPathComponent(name))
        } catch {
            return nil
        }
    }

    static func url(for name: String?) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        let url = recordingsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func delete(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(
            at: recordingsDirectory.appendingPathComponent(name)
        )
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: recordingsDirectory)
    }

    private static var recordingsDirectory: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("Sproutly", isDirectory: true)
            .appendingPathComponent("MusicSessions", isDirectory: true)
    }
}

@MainActor
final class MusicRecordPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MusicRecordPlaybackController()

    @Published private(set) var activeRecordID: UUID?
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?

    func toggle(record: EmotionRecord) {
        if activeRecordID == record.id {
            if isPlaying {
                pause()
            } else if let player {
                player.play()
                isPlaying = true
            } else {
                play(record: record)
            }
            return
        }
        play(record: record)
    }

    func play(record: EmotionRecord) {
        let details = record.musicSession
        let url = MusicSessionAudioStore.url(for: details?.audioFileName)
            ?? fallbackURL()
        guard let url else {
            stop()
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let nextPlayer = try AVAudioPlayer(contentsOf: url)
            nextPlayer.delegate = self
            nextPlayer.volume = ParentComfortRuntime.musicVolume
            nextPlayer.prepareToPlay()
            nextPlayer.play()
            player?.stop()
            player = nextPlayer
            activeRecordID = record.id
            isPlaying = true
        } catch {
            stop()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.stop()
        player = nil
        activeRecordID = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            self?.player = nil
            self?.activeRecordID = nil
            self?.isPlaying = false
        }
    }

    private func fallbackURL() -> URL? {
        Bundle.main.url(
            forResource: "music_base_classical_vibes_2",
            withExtension: "mp3"
        )
    }
}

struct EmotionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let emotion: EmotionKind
    let timestamp: Date
    let source: EmotionRecordSource
    let musicSession: MusicSessionDetails?

    init(
        id: UUID = UUID(),
        emotion: EmotionKind,
        timestamp: Date = Date(),
        source: EmotionRecordSource,
        musicSession: MusicSessionDetails? = nil
    ) {
        self.id = id
        self.emotion = emotion
        self.timestamp = timestamp
        self.source = source
        self.musicSession = musicSession
    }
}

struct FlowerTicketRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let number: Int
    let timestamp: Date
    let plantCount: Int
    let imageName: String

    init(
        id: UUID = UUID(),
        number: Int,
        timestamp: Date = Date(),
        plantCount: Int,
        imageName: String
    ) {
        self.id = id
        self.number = number
        self.timestamp = timestamp
        self.plantCount = plantCount
        self.imageName = imageName
    }
}

/// 一次 AR 任务的独立学习记录。答对即完成并获得植物，之后是否立刻放置不影响记录。
struct ARLearningRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let taskNumber: Int
    let startedAt: Date
    let completedAt: Date
    let attemptCount: Int
    let rewardName: String

    init(
        id: UUID = UUID(),
        taskNumber: Int,
        startedAt: Date,
        completedAt: Date = Date(),
        attemptCount: Int,
        rewardName: String
    ) {
        self.id = id
        self.taskNumber = taskNumber
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.attemptCount = max(1, attemptCount)
        self.rewardName = rewardName
    }

    var durationSeconds: Int {
        max(1, Int(completedAt.timeIntervalSince(startedAt)))
    }

    var completedAfterHint: Bool { attemptCount > 1 }
}

struct Plant: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    var level: Int
    var progress: Double
    var water: Int
    var sunlight: Int
}

enum KakaAppearance: String, CaseIterable, Identifiable {
    case happy
    case bee
    case dinosaur
    case rabbit
    case sailor
    case candy
    case festival
    case angry
    case thinking
    case love
    case surprised
    case shy
    case calm

    var id: String { rawValue }

    /// 首页 6 的两条轨道各有六张卡，选择器数量始终与卡片一致。
    static let outfits: [KakaAppearance] = [.happy, .candy, .bee, .dinosaur, .rabbit, .sailor, .festival]
    static let moods: [KakaAppearance] = [.shy, .angry, .thinking, .love, .surprised, .calm]

    var assetName: String {
        switch self {
        case .happy: "ar_kaka_happy"
        case .bee: "kaka_outfit_bee"
        case .dinosaur: "kaka_outfit_dinosaur"
        case .rabbit: "kaka_outfit_rabbit"
        case .sailor: "kaka_outfit_sailor"
        case .candy: "kaka_outfit_candy"
        case .festival: "kaka_outfit_festival"
        case .angry: "kaka_mood_angry"
        case .thinking: "kaka_mood_thinking"
        case .love: "kaka_mood_love"
        case .surprised: "kaka_mood_surprised"
        case .shy: "kaka_mood_shy"
        case .calm: "kaka_mood_calm"
        }
    }

    var accessibilityName: String {
        switch self {
        case .happy: "开心 KAKA"
        case .bee: "蜜蜂装 KAKA"
        case .dinosaur: "恐龙装 KAKA"
        case .rabbit: "兔子装 KAKA"
        case .sailor: "水手装 KAKA"
        case .candy: "糖果装 KAKA"
        case .festival: "节日装 KAKA"
        case .angry: "生气的 KAKA"
        case .thinking: "思考的 KAKA"
        case .love: "喜欢的 KAKA"
        case .surprised: "惊讶的 KAKA"
        case .shy: "害羞的 KAKA"
        case .calm: "平静的 KAKA"
        }
    }
}

enum ParentGuidancePreference: String, Codable, CaseIterable, Identifiable {
    case visual
    case sound
    case combined

    var id: String { rawValue }
    var title: String {
        switch self {
        case .visual: "图形"
        case .sound: "声音"
        case .combined: "图形与声音"
        }
    }
}

enum ParentCaregiverRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case mother
    case father
    case grandparent
    case other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .mother: "妈妈"
        case .father: "爸爸"
        case .grandparent: "祖辈"
        case .other: "其他"
        }
    }
}

enum ParentAnimationStrength: String, Codable, CaseIterable, Identifiable {
    case standard
    case gentle
    case minimal

    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "标准"
        case .gentle: "柔和"
        case .minimal: "最少"
        }
    }
}

enum ParentRetentionPeriod: String, Codable, CaseIterable, Identifiable, Hashable {
    case thirtyDays
    case ninetyDays
    case oneYear
    case permanent

    var id: String { rawValue }
    var title: String {
        switch self {
        case .thirtyDays: "30 天"
        case .ninetyDays: "90 天"
        case .oneYear: "1 年"
        case .permanent: "永久保留"
        }
    }

    var days: Int? {
        switch self {
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .oneYear: 365
        case .permanent: nil
        }
    }
}

struct ParentPreferences: Codable, Equatable {
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -4, to: Date()) ?? Date()
    var guidancePreference: ParentGuidancePreference = .combined
    var primaryCaregiver: ParentCaregiverRole = .mother
    var coCaregivers: [ParentCaregiverRole] = [.father]
    var reminderMinutes: Int = 20
    var quietStartMinutes: Int = 20 * 60 + 30
    var quietEndMinutes: Int = 7 * 60 + 30
    var musicVolume: Double = 0.4
    var animationStrength: ParentAnimationStrength = .gentle
    var hapticsEnabled = false
    var retainEmotionPhotos = true
    var retainARResults = true
    var biometricEnabled = false
    var photoRetention: ParentRetentionPeriod = .permanent
    var musicRetention: ParentRetentionPeriod = .permanent
    var arRetention: ParentRetentionPeriod = .permanent
    var childAvatarFileName: String?

    func isQuietTime(_ date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if quietStartMinutes < quietEndMinutes {
            return minute >= quietStartMinutes && minute < quietEndMinutes
        }
        return minute >= quietStartMinutes || minute < quietEndMinutes
    }
}

enum ParentComfortRuntime {
    private static let preferencesKey = "sproutly.parentPreferences.v1"

    static var preferences: ParentPreferences {
        guard let data = UserDefaults.standard.data(forKey: preferencesKey),
              let value = try? JSONDecoder().decode(ParentPreferences.self, from: data) else {
            return ParentPreferences()
        }
        return value
    }

    static var musicVolume: Float {
        Float(min(max(preferences.musicVolume, 0), 1))
    }

    static var hapticsEnabled: Bool { preferences.hapticsEnabled }
    static var isQuietTime: Bool { preferences.isQuietTime() }
}

@MainActor
final class GardenStore: ObservableObject {
    @Published var selectedTab: AppTab = .garden
    @Published var requestedProfilePage: Int?
    @Published var requestsKakaCustomization = false
    @Published var userName = "小芽" {
        didSet { UserDefaults.standard.set(userName, forKey: Self.userNameKey) }
    }
    @Published var energy = 72
    @Published var coins = 286
    @Published var streak = 7
    @Published var mood = "平静"
    @Published var isSignedIn = false
    @Published var gardenStyle = 0
    @Published var placedDecorations: [String] = ["🌳", "🪨", "🌼"]
    @Published private(set) var flowerTickets: [FlowerTicketRecord] = [] {
        didSet { persistFlowerTickets() }
    }
    @Published private(set) var emotionRecords: [EmotionRecord] = [] {
        didSet { persistEmotionRecords() }
    }
    @Published private(set) var arLearningRecords: [ARLearningRecord] = [] {
        didSet { persistARLearningRecords() }
    }
    @Published var plants: [Plant] = [
        Plant(name: "晨光雏菊", icon: "🌼", color: .yellow, level: 6, progress: 0.72, water: 68, sunlight: 80),
        Plant(name: "云朵绣球", icon: "🪻", color: .purple, level: 4, progress: 0.48, water: 82, sunlight: 54),
        Plant(name: "奶油郁金香", icon: "🌷", color: .pink, level: 3, progress: 0.35, water: 74, sunlight: 62)
    ]
    @Published var kakaAppearance: KakaAppearance {
        didSet {
            UserDefaults.standard.set(kakaAppearance.rawValue, forKey: "selectedKakaAppearance")
        }
    }
    @Published var parentPreferences = ParentPreferences() {
        didSet { persistParentPreferences() }
    }

    init() {
        userName = UserDefaults.standard.string(forKey: Self.userNameKey) ?? "小芽"
        let savedAppearance = UserDefaults.standard.string(forKey: "selectedKakaAppearance")
        kakaAppearance = savedAppearance.flatMap(KakaAppearance.init(rawValue:)) ?? .happy

        if let data = UserDefaults.standard.data(forKey: Self.parentPreferencesKey),
           let preferences = try? JSONDecoder().decode(ParentPreferences.self, from: data) {
            parentPreferences = preferences
        }

        if let data = UserDefaults.standard.data(forKey: Self.emotionRecordsKey),
           let records = try? JSONDecoder().decode([EmotionRecord].self, from: data) {
            emotionRecords = records.sorted { $0.timestamp < $1.timestamp }
            if let latest = emotionRecords.last {
                mood = latest.emotion.title
            }
        }

        if let data = UserDefaults.standard.data(forKey: Self.flowerTicketsKey),
           let records = try? JSONDecoder().decode([FlowerTicketRecord].self, from: data) {
            flowerTickets = records.sorted { $0.timestamp > $1.timestamp }
        }

        if let data = UserDefaults.standard.data(forKey: Self.arLearningRecordsKey),
           let records = try? JSONDecoder().decode([ARLearningRecord].self, from: data) {
            arLearningRecords = records.sorted { $0.completedAt > $1.completedAt }
        }
        purgeExpiredParentData()
    }

    var moodHistory: [String] {
        emotionRecords.reversed().map(\.emotion.title)
    }

    func waterPlant(at index: Int) {
        guard plants.indices.contains(index) else { return }
        plants[index].water = min(100, plants[index].water + 12)
        plants[index].progress = min(1, plants[index].progress + 0.04)
        energy = max(0, energy - 2)
    }

    func recordMood(_ value: String) {
        guard let emotion = EmotionKind(displayName: value) else { return }
        recordEmotion(emotion, source: .homeCheckIn)
    }

    func recordEmotion(
        _ emotion: EmotionKind,
        source: EmotionRecordSource,
        at timestamp: Date = Date(),
        musicSession: MusicSessionDetails? = nil
    ) {
        let alreadyRecordedToday = emotionRecords.contains {
            Calendar.current.isDate($0.timestamp, inSameDayAs: timestamp)
        }

        mood = emotion.title
        emotionRecords.append(
            EmotionRecord(
                emotion: emotion,
                timestamp: timestamp,
                source: source,
                musicSession: musicSession
            )
        )
        emotionRecords.sort { $0.timestamp < $1.timestamp }
        if emotionRecords.count > 730 {
            let removed = emotionRecords.prefix(emotionRecords.count - 730)
            for record in removed {
                MusicSessionAudioStore.delete(record.musicSession?.audioFileName)
            }
            emotionRecords.removeFirst(emotionRecords.count - 730)
        }

        if !alreadyRecordedToday {
            streak += 1
            coins += 20
        }
    }

    @discardableResult
    func deleteEmotionRecord(id: UUID) -> Bool {
        guard let index = emotionRecords.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let record = emotionRecords[index]
        if let name = record.musicSession?.faceImageName {
            MusicFaceSnapshotStore.delete(name)
        }
        if let name = record.musicSession?.artworkImageName {
            MusicArtworkSnapshotStore.delete(name)
        }
        MusicSessionAudioStore.delete(record.musicSession?.audioFileName)

        emotionRecords.remove(at: index)
        mood = emotionRecords.last?.emotion.title ?? "平静"
        return true
    }

    func selectKaka(_ appearance: KakaAppearance) {
        kakaAppearance = appearance
    }

    @discardableResult
    func saveFlowerTicket(
        image: UIImage,
        plantCount: Int,
        at timestamp: Date = Date()
    ) -> FlowerTicketRecord? {
        let nextNumber = (flowerTickets.map(\.number).max() ?? 0) + 1
        guard let imageName = FlowerTicketImageStore.save(image) else { return nil }
        let record = FlowerTicketRecord(
            number: nextNumber,
            timestamp: timestamp,
            plantCount: max(1, plantCount),
            imageName: imageName
        )
        flowerTickets.insert(record, at: 0)
        return record
    }

    func flowerTicketImage(for record: FlowerTicketRecord) -> UIImage? {
        FlowerTicketImageStore.load(record.imageName)
    }

    @discardableResult
    func deleteFlowerTicket(id: UUID) -> Bool {
        guard let index = flowerTickets.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let record = flowerTickets[index]
        FlowerTicketImageStore.delete(record.imageName)
        flowerTickets.remove(at: index)
        return true
    }

    func recordARLearning(
        taskNumber: Int,
        startedAt: Date,
        completedAt: Date = Date(),
        attemptCount: Int,
        rewardName: String
    ) {
        guard parentPreferences.retainARResults else { return }
        arLearningRecords.insert(
            ARLearningRecord(
                taskNumber: taskNumber,
                startedAt: startedAt,
                completedAt: completedAt,
                attemptCount: attemptCount,
                rewardName: rewardName
            ),
            at: 0
        )
        if arLearningRecords.count > 500 {
            arLearningRecords.removeLast(arLearningRecords.count - 500)
        }
    }

    private static let emotionRecordsKey = "sproutly.emotionRecords.v1"
    private static let flowerTicketsKey = "sproutly.flowerTickets.v1"
    private static let arLearningRecordsKey = "sproutly.arLearningRecords.v1"
    private static let parentPreferencesKey = "sproutly.parentPreferences.v1"
    private static let userNameKey = "sproutly.childName.v1"

    private func persistEmotionRecords() {
        guard let data = try? JSONEncoder().encode(emotionRecords) else { return }
        UserDefaults.standard.set(data, forKey: Self.emotionRecordsKey)
    }

    private func persistFlowerTickets() {
        guard let data = try? JSONEncoder().encode(flowerTickets) else { return }
        UserDefaults.standard.set(data, forKey: Self.flowerTicketsKey)
    }

    private func persistARLearningRecords() {
        guard let data = try? JSONEncoder().encode(arLearningRecords) else { return }
        UserDefaults.standard.set(data, forKey: Self.arLearningRecordsKey)
    }

    private func persistParentPreferences() {
        guard let data = try? JSONEncoder().encode(parentPreferences) else { return }
        UserDefaults.standard.set(data, forKey: Self.parentPreferencesKey)
    }

    func deleteEmotionPhotos() {
        MusicFaceSnapshotStore.deleteAll()
    }

    func deleteARLearningRecords() {
        arLearningRecords.removeAll()
    }

    func deleteAllActivityData() {
        emotionRecords.removeAll()
        arLearningRecords.removeAll()
        flowerTickets.removeAll()
        MusicFaceSnapshotStore.deleteAll()
        MusicArtworkSnapshotStore.deleteAll()
        MusicSessionAudioStore.deleteAll()
        FlowerTicketImageStore.deleteAll()
        UserDefaults.standard.removeObject(forKey: "sproutly.music.coloring.music313.v3")
        mood = "平静"
        streak = 0
    }

    func purgeExpiredParentData(now: Date = Date()) {
        if let days = parentPreferences.musicRetention.days,
           let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) {
            for record in emotionRecords where record.timestamp < cutoff {
                if let name = record.musicSession?.faceImageName { MusicFaceSnapshotStore.delete(name) }
                if let name = record.musicSession?.artworkImageName { MusicArtworkSnapshotStore.delete(name) }
                MusicSessionAudioStore.delete(record.musicSession?.audioFileName)
            }
            emotionRecords.removeAll { $0.timestamp < cutoff }
        }
        if let days = parentPreferences.arRetention.days,
           let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) {
            arLearningRecords.removeAll { $0.completedAt < cutoff }
        }
        if let days = parentPreferences.photoRetention.days,
           let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) {
            for record in flowerTickets where record.timestamp < cutoff {
                FlowerTicketImageStore.delete(record.imageName)
            }
            flowerTickets.removeAll { $0.timestamp < cutoff }
        }
    }
}

private enum FlowerTicketImageStore {
    static func save(_ image: UIImage) -> String? {
        let normalized = image.normalizedFlowerTicketImage(maxDimension: 1800)
        guard let data = normalized.jpegData(compressionQuality: 0.9) else { return nil }
        let name = UUID().uuidString + ".jpg"
        let url = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func load(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
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
            .appendingPathComponent("FlowerTickets", isDirectory: true)
    }
}

private extension UIImage {
    func normalizedFlowerTicketImage(maxDimension: CGFloat) -> UIImage {
        let swapAxes: Bool
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            swapAxes = true
        default:
            swapAxes = false
        }
        let orientedSize = swapAxes
            ? CGSize(width: size.height, height: size.width)
            : size
        let factor = min(1, maxDimension / max(orientedSize.width, orientedSize.height))
        let target = CGSize(
            width: max(1, orientedSize.width * factor),
            height: max(1, orientedSize.height * factor)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// 所有页面共用的 KAKA；首页选择后会即时同步到音乐和 AR。
struct KakaAvatarView: View {
    @EnvironmentObject private var store: GardenStore
    var selectedAppearance: KakaAppearance? = nil
    var magnification: CGFloat = 1.25
    /// 舞台等需要并排比较装扮的场景，默认形象也采用同一放大比例。
    var matchesVariantScale: Bool = false

    private var appearance: KakaAppearance {
        selectedAppearance ?? store.kakaAppearance
    }

    var body: some View {
        GeometryReader { proxy in
            Image(appearance.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .scaleEffect(appearance == .happy && !matchesVariantScale ? 1 : magnification)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appearance.accessibilityName)
    }
}
