#if DEBUG
import SwiftUI

/// Xcode Canvas 的统一模拟数据容器。
/// 每个页面都单独提供一个可交互的 iPhone 预览。
@MainActor
private struct GardenPreview<Content: View>: View {
    @StateObject private var store = GardenStore()
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .environmentObject(store)
            .previewDevice(PreviewDevice(rawValue: "iPhone 16 Pro"))
    }
}

#Preview("01 · 首次启动引导") {
    GardenPreview {
        OnboardingView {}
    }
}

#Preview("02 · 花园主页") {
    GardenPreview {
        GardenHomeView()
    }
}

#Preview("03 · 音乐") {
    GardenPreview {
        FigmaMusicView()
    }
}
                                    
#Preview("04 · AR世界") {
    GardenPreview {
        FigmaARView()
    }
}

#Preview("05 · 社区") {
    GardenPreview {
        FigmaCommunityView()
    }
}

#Preview("06 · 我的") {
    GardenPreview {
        FigmaProfileView()
    }
}

#Preview("07 · 完整 App") {
    GardenPreview {
        MainTabView()
    }
}
#endif
