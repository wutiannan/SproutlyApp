import AVFoundation
import SwiftUI
import UIKit

struct RootView: View {
    private enum RootAlert: Identifiable {
        case usageReminder
        case cameraPermission

        var id: Self { self }
    }

    @EnvironmentObject private var store: GardenStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var isLaunching = true
    @State private var launchID = UUID()
    @State private var hasEnteredBackground = false
    @State private var activeAlert: RootAlert?
    @State private var cameraPermissionRestricted = false
    @State private var cameraPermissionCheckTask: Task<Void, Never>?
    @State private var showsCameraSettingsGate = false
    @State private var opensSettingsAfterVerification = false

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
        .transaction { transaction in
            if store.parentPreferences.animationStrength == .minimal {
                transaction.disablesAnimations = true
            }
        }
        .statusBarHidden(false)
        .task(id: launchID) {
            HomeGlobeModelCache.shared.preload()
            guard hasSeenOnboarding else {
                isLaunching = false
                return
            }
            isLaunching = true
            try? await Task.sleep(for: .seconds(1.15))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) { isLaunching = false }
        }
        .onAppear { scheduleCameraPermissionCheck() }
        .onChange(of: hasSeenOnboarding) { _, completed in
            if completed { scheduleCameraPermissionCheck() }
        }
        .onChange(of: isLaunching) { _, launching in
            if !launching { scheduleCameraPermissionCheck() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                hasEnteredBackground = true
                ParentReminderScheduler.scheduleIfAuthorized(
                    minutes: store.parentPreferences.reminderMinutes
                )
            } else if phase == .active {
                if hasEnteredBackground, hasSeenOnboarding {
                    hasEnteredBackground = false
                    launchID = UUID()
                }
                scheduleCameraPermissionCheck()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            scheduleCameraPermissionCheck()
        }
        .onDisappear { cameraPermissionCheckTask?.cancel() }
        .task(id: "\(scenePhase)-\(store.parentPreferences.reminderMinutes)") {
            guard scenePhase == .active, store.parentPreferences.reminderMinutes > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(store.parentPreferences.reminderMinutes * 60))
                guard !Task.isCancelled else { return }
                if !store.parentPreferences.isQuietTime(), activeAlert == nil {
                    activeAlert = .usageReminder
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .usageReminder:
                Alert(
                    title: Text("休息一下吧"),
                    message: Text("和 KAKA 一起看看远处、伸伸手，再继续探索。"),
                    dismissButton: .cancel(Text("好呀"))
                )
            case .cameraPermission:
                Alert(
                    title: Text("相机权限未开启"),
                    message: Text(cameraPermissionRestricted
                        ? "相机访问受到设备限制，请由监护人检查系统设置。"
                        : "开启相机权限后，才能使用拍照和 AR 探索。"),
                    primaryButton: .cancel(Text("暂不")),
                    secondaryButton: .default(Text("前往设置")) {
                        showsCameraSettingsGate = true
                    }
                )
            }
        }
        .onChange(of: activeAlert) { previous, current in
            if previous == .usageReminder && current == nil {
                scheduleCameraPermissionCheck()
            }
        }
        .fullScreenCover(isPresented: $showsCameraSettingsGate, onDismiss: {
            guard opensSettingsAfterVerification else { return }
            opensSettingsAfterVerification = false
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }) {
            ParentVerificationFlowView(
                purpose: .cameraSettings,
                onClose: { showsCameraSettingsGate = false },
                onVerified: {
                    opensSettingsAfterVerification = true
                    showsCameraSettingsGate = false
                }
            )
        }
    }

    private func scheduleCameraPermissionCheck() {
        cameraPermissionCheckTask?.cancel()
        cameraPermissionCheckTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            showCameraPermissionAlertIfNeeded()
        }
    }

    private func showCameraPermissionAlertIfNeeded() {
        guard UIApplication.shared.applicationState == .active,
              hasSeenOnboarding, !isLaunching,
              !showsCameraSettingsGate, activeAlert == nil else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .denied || status == .restricted else { return }
        cameraPermissionRestricted = status == .restricted
        activeAlert = .cameraPermission
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
    @State private var loadingTab: AppTab? = .garden
    @State private var homeReadyOnce = false
    @State private var loadIsTakingLong = false
    @State private var loadTimeout: Task<Void, Never>?
    @State private var navigationTarget: AppTab?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch store.selectedTab {
                case .garden:
                    GardenHomeView(onContentReady: finishHomeLoading, onNavigate: navigateFromHome) { isCustomizing in
                        hidesTabHotspots = isCustomizing
                    }
                case .mood:
                    FigmaMusicView(onContentReady: finishMusicLoading) { isGuidanceActive in
                        hidesTabHotspots = isGuidanceActive
                    }
                case .room:
                    FigmaARView { isTaskFlowActive in
                        hidesTabHotspots = isTaskFlowActive
                    }
                    .onAppear { finishStaticLoading(.room) }
                case .profile:
                    FigmaProfileView()
                        .onAppear { finishStaticLoading(.profile) }
                }
            }

            if !hidesTabHotspots
                && store.selectedTab != .garden
                && store.selectedTab != .mood
                && store.selectedTab != .room
                && store.selectedTab != .profile {
                tabButtons
            }

            PageLoadingOverlay(isTakingLong: loadIsTakingLong) {
                loadTimeout?.cancel()
                loadingTab = nil
            }
            .background {
                LoadingDisplaySignal(isActive: navigationTarget != nil) {
                    continueNavigationIfNeeded()
                }
                .frame(width: 1, height: 1)
            }
            .opacity(loadingTab == nil ? 0 : 1)
            .allowsHitTesting(loadingTab != nil)
            .accessibilityHidden(loadingTab == nil)
            .zIndex(50)
        }
        .ignoresSafeArea(.keyboard)
        .onAppear { beginLoading(store.selectedTab) }
        .onChange(of: store.selectedTab) { _, selectedTab in
            beginLoading(selectedTab)
            if selectedTab == .mood {
                hidesTabHotspots = true
            } else if selectedTab != .room {
                hidesTabHotspots = false
            }
        }
        .onDisappear {
            loadTimeout?.cancel()
        }
    }

    private func navigateFromHome(to tab: AppTab) {
        guard store.selectedTab == .garden else { return }
        navigationTarget = tab
        beginLoading(tab)
    }

    private func continueNavigationIfNeeded() {
        guard let tab = navigationTarget, loadingTab == tab else { return }
        guard store.selectedTab == .garden else { return }
        navigationTarget = nil
        store.selectedTab = tab
    }

    private func beginLoading(_ tab: AppTab) {
        loadTimeout?.cancel()
        loadIsTakingLong = false
        guard tab != .garden || !homeReadyOnce else {
            loadingTab = nil
            return
        }
        loadingTab = tab
        loadTimeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, loadingTab == tab else { return }
            loadIsTakingLong = true
        }
    }

    private func finishHomeLoading() {
        guard store.selectedTab == .garden else { return }
        homeReadyOnce = true
        finishLoading(.garden)
    }

    private func finishMusicLoading() {
        finishLoading(.mood)
    }

    private func finishStaticLoading(_ tab: AppTab) {
        Task { @MainActor in
            await Task.yield()
            finishLoading(tab)
        }
    }

    private func finishLoading(_ tab: AppTab) {
        guard store.selectedTab == tab, loadingTab == tab else { return }
        loadTimeout?.cancel()
        loadingTab = nil
        loadIsTakingLong = false
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

private struct PageLoadingOverlay: View {
    let isTakingLong: Bool
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            SproutlyHomeGradient().ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color(red: 0.12, green: 0.50, blue: 0.48))

                Text(isTakingLong ? "加载时间较长" : "正在准备页面")
                    .gardenFont(size: 16, weight: .medium)
                    .foregroundStyle(Color(red: 0.16, green: 0.36, blue: 0.38))

                if isTakingLong {
                    Button("先进入页面", action: onContinue)
                        .gardenFont(size: 15, weight: .medium)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.88), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}

private struct LoadingDisplaySignal: UIViewRepresentable {
    let isActive: Bool
    let onPresented: () -> Void

    func makeUIView(context: Context) -> LoadingDisplaySignalView {
        let view = LoadingDisplaySignalView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: LoadingDisplaySignalView, context: Context) {
        view.onPresented = onPresented
        view.isActive = isActive
    }
}

private final class LoadingDisplaySignalView: UIView {
    var onPresented: (() -> Void)?
    var isActive = false {
        didSet {
            if isActive != oldValue { updateDisplayLink() }
        }
    }

    private var displayLink: CADisplayLink?
    private var frameCount = 0

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDisplayLink()
    }

    private func updateDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        guard isActive, window != nil else { return }
        frameCount = 0
        let link = CADisplayLink(target: self, selector: #selector(displayFrame))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func displayFrame() {
        frameCount += 1
        guard frameCount >= 2 else { return }
        displayLink?.invalidate()
        displayLink = nil
        onPresented?()
    }

    deinit { displayLink?.invalidate() }
}
