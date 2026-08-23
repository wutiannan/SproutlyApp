import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: GardenStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var isLaunching = true
    @State private var launchID = UUID()
    @State private var hasEnteredBackground = false

    var body: some View {
        ZStack {
            if !hasSeenOnboarding {
                OnboardingView { hasSeenOnboarding = true }
            } else {
                MainTabView()
            }
            if isLaunching && hasSeenOnboarding {
                DesignLaunchView()
                    .id(launchID)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .font(GardenFont.medium(16))
        .tint(GardenTheme.deepMint)
        .preferredColorScheme(.light)
        .statusBarHidden(false)
        .task(id: launchID) {
            guard hasSeenOnboarding else {
                isLaunching = false
                return
            }
            isLaunching = true
            try? await Task.sleep(for: .seconds(1.15))
            withAnimation(.easeOut(duration: 0.28)) { isLaunching = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                hasEnteredBackground = true
            } else if phase == .active, hasEnteredBackground, hasSeenOnboarding {
                hasEnteredBackground = false
                launchID = UUID()
            }
        }
    }
}

struct DesignLaunchView: View {
    @State private var showsLogo = false

    var body: some View {
        ZStack {
            FigmaScreenCanvas(asset: "figma_onboarding_1") { _ in EmptyView() }
                .opacity(showsLogo ? 0 : 1)
            FigmaScreenCanvas(asset: "figma_onboarding_2") { _ in EmptyView() }
                .opacity(showsLogo ? 1 : 0)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.6)) {
                showsLogo = true
            }
        }
    }
}

struct OnboardingView: View {
    let complete: () -> Void
    @State private var page = 1
    @State private var agreed = false
    @State private var account = ""
    @State private var password = ""
    @State private var nickname = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case account, password, nickname
    }

    var body: some View {
        FigmaScreenCanvas(asset: backgroundAsset) { scale in
            Group {
                if page == 3 {
                    onboardingHotspot(x: 66, y: 491, width: 271, height: 55, scale: scale) {
                        guard agreed else {
                            withAnimation(.easeInOut(duration: 0.2)) { agreed = true }
                            return
                        }
                        go(to: 5, animation: .timingCurve(0.36, 0, 0.66, -0.56, duration: 0.4))
                    }
                    onboardingHotspot(x: 129, y: 802, width: 146, height: 38, scale: scale) {
                        go(to: 4, animation: .easeOut(duration: 0.3))
                    }
                    onboardingHotspot(x: 91, y: 628, width: 24, height: 24, scale: scale) {
                        withAnimation(.easeInOut(duration: 0.2)) { agreed.toggle() }
                    }
                    if agreed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15 * scale))
                            .foregroundStyle(Color(red: 0, green: 0.76, blue: 0.82))
                            .position(x: 103 * scale, y: 641 * scale)
                    }
                } else if page == 4 {
                    nativeLoginFields(scale: scale)
                    onboardingHotspot(x: 66, y: 493, width: 271, height: 45, scale: scale) {
                        focusedField = nil
                        go(to: 5, animation: .timingCurve(0.36, 0, 0.66, -0.56, duration: 0.4))
                    }
                    onboardingHotspot(x: 65, y: 543, width: 52, height: 34, scale: scale) {
                        go(to: 3, animation: .easeOut(duration: 0.3))
                    }
                } else if page == 6 || page == 7 {
                    nicknameField(scale: scale)
                    onboardingHotspot(x: 106, y: 718, width: 189, height: 43, scale: scale) {
                        page = 7
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            focusedField = .nickname
                        }
                    }
                    onboardingHotspot(x: 316, y: 790, width: 75, height: 48, scale: scale) {
                        focusedField = nil
                        go(to: 9, animation: .easeOut(duration: 0.3))
                    }
                } else if page == 8 {
                    onboardingHotspot(x: 106, y: 718, width: 189, height: 43, scale: scale) {
                        go(to: 9, animation: .timingCurve(0.36, 0, 0.66, -0.56, duration: 0.4))
                    }
                    onboardingHotspot(x: 316, y: 790, width: 75, height: 48, scale: scale) {
                        go(to: 9, animation: .easeOut(duration: 0.3))
                    }
                }

            }
        }
        .ignoresSafeArea(.keyboard)
        .task(id: page) {
            switch page {
            case 1:
                try? await Task.sleep(for: .milliseconds(300))
                go(to: 2, animation: .easeOut(duration: 0.6))
            case 2:
                try? await Task.sleep(for: .milliseconds(500))
                go(to: 3, animation: .spring(response: 1.06, dampingFraction: 0.72))
            case 5:
                try? await Task.sleep(for: .seconds(5))
                go(to: 6, animation: .easeIn(duration: 0.4))
            case 9:
                try? await Task.sleep(for: .seconds(5))
                complete()
            default:
                break
            }
        }
    }

    private var backgroundAsset: String {
        page == 7 ? "figma_onboarding_6" : "figma_onboarding_\(page)"
    }

    @ViewBuilder
    private func nativeLoginFields(scale: CGFloat) -> some View {
        TextField("用户名/Email", text: $account)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .account)
            .gardenFont(size: 15 * scale)
            .padding(.horizontal, 11 * scale)
            .frame(width: 271 * scale, height: 42 * scale)
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 9 * scale))
            .position(x: 201.5 * scale, y: 412 * scale)

        SecureField("密码", text: $password)
            .focused($focusedField, equals: .password)
            .gardenFont(size: 15 * scale)
            .padding(.horizontal, 11 * scale)
            .frame(width: 271 * scale, height: 42 * scale)
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 9 * scale))
            .position(x: 201.5 * scale, y: 463 * scale)
            .onSubmit {
                focusedField = nil
                go(to: 5, animation: .timingCurve(0.36, 0, 0.66, -0.56, duration: 0.4))
            }
    }

    private func nicknameField(scale: CGFloat) -> some View {
        TextField("", text: $nickname)
            .focused($focusedField, equals: .nickname)
            .submitLabel(.go)
            .multilineTextAlignment(.center)
            .gardenFont(size: 17 * scale)
            .frame(width: 293 * scale, height: 51 * scale)
            .background(.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 11 * scale))
            .position(x: 201.5 * scale, y: 678.5 * scale)
            .onSubmit {
                focusedField = nil
                go(to: 8, animation: .easeOut(duration: 0.3))
            }
    }

    private func go(to destination: Int, animation: Animation) {
        withAnimation(animation) { page = destination }
    }
}

private func onboardingHotspot(
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    scale: CGFloat,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Color.clear
            .frame(width: width * scale, height: height * scale)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .position(x: (x + width / 2) * scale, y: (y + height / 2) * scale)
}

struct MainTabView: View {
    @EnvironmentObject private var store: GardenStore
    @State private var hidesTabHotspots = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch store.selectedTab {
                case .garden:
                    GardenHomeView { isCustomizing in
                        hidesTabHotspots = isCustomizing
                    }
                case .mood:
                    FigmaMusicView { isGuidanceActive in
                        hidesTabHotspots = isGuidanceActive
                    }
                case .room:
                    FigmaARView { isTaskFlowActive in
                        hidesTabHotspots = isTaskFlowActive
                    }
                case .discover: FigmaCommunityView()
                case .profile: FigmaProfileView()
                }
            }

            if !hidesTabHotspots {
                tabButtons
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: store.selectedTab) { _, selectedTab in
            if selectedTab != .room {
                hidesTabHotspots = false
            }
        }
    }

    private var tabButtons: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.selectedTab = tab
                    }
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 96)
    }
}
