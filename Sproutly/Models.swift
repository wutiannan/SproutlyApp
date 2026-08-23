import SwiftUI

enum AppTab: String, CaseIterable {
    case garden = "花园"
    case mood = "心情"
    case room = "布置"
    case discover = "发现"
    case profile = "我的"

    var icon: String {
        switch self {
        case .garden: return "leaf.fill"
        case .mood: return "sparkles"
        case .room: return "camera.viewfinder"
        case .discover: return "safari.fill"
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

struct EmotionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let emotion: EmotionKind
    let timestamp: Date
    let source: EmotionRecordSource

    init(
        id: UUID = UUID(),
        emotion: EmotionKind,
        timestamp: Date = Date(),
        source: EmotionRecordSource
    ) {
        self.id = id
        self.emotion = emotion
        self.timestamp = timestamp
        self.source = source
    }
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

@MainActor
final class GardenStore: ObservableObject {
    @Published var selectedTab: AppTab = .garden
    @Published var userName = "小芽"
    @Published var energy = 72
    @Published var coins = 286
    @Published var streak = 7
    @Published var mood = "平静"
    @Published var isSignedIn = false
    @Published var gardenStyle = 0
    @Published var placedDecorations: [String] = ["🌳", "🪨", "🌼"]
    @Published private(set) var emotionRecords: [EmotionRecord] = [] {
        didSet { persistEmotionRecords() }
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

    init() {
        let savedAppearance = UserDefaults.standard.string(forKey: "selectedKakaAppearance")
        kakaAppearance = savedAppearance.flatMap(KakaAppearance.init(rawValue:)) ?? .happy

        if let data = UserDefaults.standard.data(forKey: Self.emotionRecordsKey),
           let records = try? JSONDecoder().decode([EmotionRecord].self, from: data) {
            emotionRecords = records.sorted { $0.timestamp < $1.timestamp }
            if let latest = emotionRecords.last {
                mood = latest.emotion.title
            }
        }
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
        at timestamp: Date = Date()
    ) {
        let alreadyRecordedToday = emotionRecords.contains {
            Calendar.current.isDate($0.timestamp, inSameDayAs: timestamp)
        }

        mood = emotion.title
        emotionRecords.append(
            EmotionRecord(
                emotion: emotion,
                timestamp: timestamp,
                source: source
            )
        )
        emotionRecords.sort { $0.timestamp < $1.timestamp }
        if emotionRecords.count > 730 {
            emotionRecords.removeFirst(emotionRecords.count - 730)
        }

        if !alreadyRecordedToday {
            streak += 1
            coins += 20
        }
    }

    func selectKaka(_ appearance: KakaAppearance) {
        kakaAppearance = appearance
    }

    private static let emotionRecordsKey = "sproutly.emotionRecords.v1"

    private func persistEmotionRecords() {
        guard let data = try? JSONEncoder().encode(emotionRecords) else { return }
        UserDefaults.standard.set(data, forKey: Self.emotionRecordsKey)
    }
}

/// 所有页面共用的 KAKA；首页选择后会即时同步到音乐、AR 和社区。
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
