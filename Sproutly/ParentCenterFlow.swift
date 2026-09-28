import LocalAuthentication
import PhotosUI
import Security
import SwiftUI
import UIKit
import UserNotifications

enum ParentVerificationPurpose {
    case parentCenter
    case growthRecords
    case cameraSettings

    var cardTitle: String {
        switch self {
        case .parentCenter: "验证后进入家长中心"
        case .growthRecords: "验证后查看成长记录"
        case .cameraSettings: "验证后开启相机权限"
        }
    }

    var cardSubtitle: String {
        switch self {
        case .parentCenter: "成长记录、隐私设置与数据授权仅供成人使用"
        case .growthRecords: "成长记录、趋势与数据授权仅供监护人使用"
        case .cameraSettings: "相机权限设置仅供监护人操作"
        }
    }

    var sessionNote: String {
        "验证状态仅在本次家长操作期间有效"
    }

    var biometricReason: String {
        switch self {
        case .parentCenter: "进入灵想家长中心"
        case .growthRecords: "查看灵想成长记录"
        case .cameraSettings: "前往系统设置开启相机权限"
        }
    }

    var biometricOfferMessage: String {
        switch self {
        case .parentCenter: "以后进入家长中心可先用 Face ID 验证，也始终可以改用家长密码。"
        case .growthRecords: "以后查看成长记录可先用 Face ID 验证，也始终可以改用家长密码。"
        case .cameraSettings: "以后调整相机权限可先用 Face ID 验证，也始终可以改用家长密码。"
        }
    }
}

struct ParentVerificationFlowView: View {
    @EnvironmentObject private var store: GardenStore
    let purpose: ParentVerificationPurpose
    let onClose: () -> Void
    let onVerified: () -> Void

    @State private var pinSheet: PinSheetMode?
    @State private var showsBiometricOffer = false
    @State private var errorMessage: String?
    @State private var proceedsAfterErrorDismissal = false

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 402, proxy.size.height / 874)
            ZStack {
                ParentBackground(matchesParentVerificationDesign: true)
                ParentGatePage(
                    scale: scale,
                    purpose: purpose,
                    hasPIN: ParentPINStore.hasPIN,
                    biometricEnabled: store.parentPreferences.biometricEnabled,
                    onClose: onClose,
                    useBiometrics: beginBiometricEntry,
                    usePIN: beginPINEntry
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .sheet(item: $pinSheet) { mode in
            ParentPINSheet(
                mode: mode,
                onSuccess: { pin in completePIN(mode: mode, pin: pin) },
                onForgot: resetForgottenPIN
            )
            .presentationDetents([.height(mode.isSetup ? 430 : 350)])
            .presentationDragIndicator(.visible)
        }
        .alert("是否启用 Face ID？", isPresented: $showsBiometricOffer) {
            Button("暂不启用", role: .cancel, action: onVerified)
            Button("启用") {
                Task { await enableBiometricsAfterSetup() }
            }
        } message: {
            Text(purpose.biometricOfferMessage)
        }
        .alert("暂时无法完成", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {
                if proceedsAfterErrorDismissal {
                    proceedsAfterErrorDismissal = false
                    onVerified()
                }
            }
        } message: {
            Text(errorMessage ?? "请稍后再试。")
        }
    }

    private func beginBiometricEntry() {
        guard ParentPINStore.hasPIN else {
            Task { await authenticateBeforeSetup() }
            return
        }
        guard store.parentPreferences.biometricEnabled else {
            pinSheet = .verify
            return
        }
        Task {
            do {
                try await ParentAuthentication.authenticateBiometrics(reason: purpose.biometricReason)
                onVerified()
            } catch {
                errorMessage = "Face ID 未能验证，请使用家长密码。"
                pinSheet = .verify
            }
        }
    }

    private func beginPINEntry() {
        if ParentPINStore.hasPIN {
            pinSheet = .verify
        } else {
            Task { await authenticateBeforeSetup() }
        }
    }

    private func authenticateBeforeSetup() async {
        do {
            try await ParentAuthentication.authenticateDeviceOwner(
                reason: "验证设备所有者，以创建灵想家长密码"
            )
            pinSheet = .setup
        } catch {
            errorMessage = "请先使用设备密码或生物识别验证设备所有者。"
        }
    }

    private func completePIN(mode: PinSheetMode, pin: String) {
        switch mode {
        case .setup:
            ParentPINStore.set(pin)
            pinSheet = nil
            showsBiometricOffer = true
        case .verify:
            guard ParentPINStore.verify(pin) else {
                errorMessage = "家长密码不正确，请重新输入。"
                return
            }
            pinSheet = nil
            onVerified()
        case .verifyForChange, .verifyForDelete:
            break
        }
    }

    private func resetForgottenPIN() {
        pinSheet = nil
        Task {
            do {
                try await ParentAuthentication.authenticateDeviceOwner(
                    reason: "验证设备所有者，以重设灵想家长密码"
                )
                pinSheet = .setup
            } catch {
                errorMessage = "设备所有者验证未通过，密码没有重设。"
            }
        }
    }

    private func enableBiometricsAfterSetup() async {
        do {
            try await ParentAuthentication.authenticateBiometrics(reason: purpose.biometricReason)
            store.parentPreferences.biometricEnabled = true
            onVerified()
        } catch {
            store.parentPreferences.biometricEnabled = false
            proceedsAfterErrorDismissal = true
            errorMessage = "Face ID 暂不可用，你仍可使用家长密码。"
        }
    }
}

struct ParentCenterFlowView: View {
    @EnvironmentObject private var store: GardenStore
    @Environment(\.scenePhase) private var scenePhase
    let onClose: () -> Void

    @State private var route: Route = .gate
    @State private var pinSheet: PinSheetMode?
    @State private var showsBiometricOffer = false
    @State private var errorMessage: String?
    @State private var isChangingPIN = false

    private enum Route {
        case gate, center, child, comfort, privacy, therapist
    }

    init(initiallyVerified: Bool = false, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _route = State(initialValue: initiallyVerified ? .center : .gate)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 402, proxy.size.height / 874)
            ZStack {
                ParentBackground()
                switch route {
                case .gate:
                    ParentVerificationFlowView(
                        purpose: .parentCenter,
                        onClose: onClose,
                        onVerified: { route = .center }
                    )
                case .center:
                    ParentCenterPage(
                        scale: scale,
                        showChild: { route = .child },
                        showComfort: { route = .comfort },
                        showPrivacy: { route = .privacy },
                        showTherapist: { route = .therapist },
                        onClose: onClose,
                        changePIN: { pinSheet = .verifyForChange }
                    )
                case .child:
                    ParentChildPage(scale: scale) { destination in
                        switch destination {
                        case .back: route = .center
                        case .kaka:
                            store.requestsKakaCustomization = true
                            store.selectedTab = .garden
                            onClose()
                        }
                    }
                case .comfort:
                    ParentComfortPage(scale: scale) { route = .center }
                case .privacy:
                    ParentPrivacyPage(
                        scale: scale,
                        onBack: { route = .center },
                        verifyDelete: { pinSheet = .verifyForDelete }
                    )
                case .therapist:
                    ParentTherapistPage(scale: scale) { route = .center }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            route = .gate
            pinSheet = nil
        }
        .sheet(item: $pinSheet) { mode in
            ParentPINSheet(
                mode: mode,
                onSuccess: { pin in completePIN(mode: mode, pin: pin) },
                onForgot: resetForgottenPIN
            )
            .presentationDetents([.height(mode.isSetup ? 430 : 350)])
            .presentationDragIndicator(.visible)
        }
        .alert("是否启用 Face ID？", isPresented: $showsBiometricOffer) {
            Button("暂不启用", role: .cancel) {
                route = .center
            }
            Button("启用") {
                Task { await enableBiometricsAfterSetup() }
            }
        } message: {
            Text("以后进入家长中心可先用 Face ID 验证，也始终可以改用家长密码。")
        }
        .alert("暂时无法完成", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "请稍后再试。")
        }
    }

    private func completePIN(mode: PinSheetMode, pin: String) {
        switch mode {
        case .setup:
            ParentPINStore.set(pin)
            pinSheet = nil
            if isChangingPIN {
                isChangingPIN = false
                route = .center
            } else {
                showsBiometricOffer = true
            }
        case .verify:
            guard ParentPINStore.verify(pin) else {
                errorMessage = "家长密码不正确，请重新输入。"
                return
            }
            pinSheet = nil
            route = .center
        case .verifyForChange:
            guard ParentPINStore.verify(pin) else {
                errorMessage = "家长密码不正确，请重新输入。"
                return
            }
            pinSheet = nil
            isChangingPIN = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                pinSheet = .setup
            }
        case .verifyForDelete:
            guard ParentPINStore.verify(pin) else {
                errorMessage = "家长密码不正确，请重新输入。"
                return
            }
            pinSheet = nil
            NotificationCenter.default.post(name: .parentDeleteVerified, object: nil)
        }
    }

    private func resetForgottenPIN() {
        pinSheet = nil
        Task {
            do {
                try await ParentAuthentication.authenticateDeviceOwner(
                    reason: "验证设备所有者，以重设灵想家长密码"
                )
                pinSheet = .setup
            } catch {
                errorMessage = "设备所有者验证未通过，密码没有重设。"
            }
        }
    }

    private func enableBiometricsAfterSetup() async {
        do {
            try await ParentAuthentication.authenticateBiometrics()
            store.parentPreferences.biometricEnabled = true
        } catch {
            store.parentPreferences.biometricEnabled = false
            errorMessage = "Face ID 暂不可用，你仍可使用家长密码。"
        }
        route = .center
    }
}

private struct ParentGatePage: View {
    let scale: CGFloat
    let purpose: ParentVerificationPurpose
    let hasPIN: Bool
    let biometricEnabled: Bool
    let onClose: () -> Void
    let useBiometrics: () -> Void
    let usePIN: () -> Void

    var body: some View {
        ZStack {
            ParentHeader(
                title: "家长验证",
                subtitle: "成人操作区",
                scale: scale,
                onBack: onClose,
                usesFigmaExportSizing: true
            )

            Image("parent_verify_glow")
                .resizable()
                .scaledToFit()
                .frame(width: 250 * scale, height: 250 * scale)
                .position(x: 201 * scale, y: 279 * scale)

            ZStack {
                Circle()
                    .fill(.white.opacity(0.9))
                    .shadow(
                        color: Color(red: 31 / 255, green: 89 / 255, blue: 77 / 255).opacity(0.12),
                        radius: 20 * scale,
                        y: 8 * scale
                    )
                Text("✓")
                    .gardenFont(size: 38 * scale, weight: .bold)
                    .foregroundStyle(Color(red: 63 / 255, green: 181 / 255, blue: 150 / 255))
            }
            .frame(width: 108 * scale, height: 108 * scale)
            .position(x: 201 * scale, y: 269 * scale)

            ZStack {
                RoundedRectangle(cornerRadius: 26 * scale, style: .continuous)
                    .fill(Color(red: 1, green: 254 / 255, blue: 250 / 255))
                    .shadow(
                        color: Color(red: 31 / 255, green: 89 / 255, blue: 77 / 255).opacity(0.08),
                        radius: 22 * scale,
                        y: 8 * scale
                    )

                Text(purpose.cardTitle)
                    .gardenFont(size: 20 * scale, weight: .bold)
                    .foregroundStyle(Color(red: 36 / 255, green: 79 / 255, blue: 75 / 255))
                    .frame(width: 362 * scale, height: 20 * scale)
                    .position(x: 181 * scale, y: 37 * scale)

                Text(purpose.cardSubtitle)
                    .gardenFont(size: 11 * scale)
                    .foregroundStyle(Color(red: 113 / 255, green: 141 / 255, blue: 136 / 255))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: 290 * scale, height: 20 * scale)
                    .position(x: 181 * scale, y: 78 * scale)

                Button(action: useBiometrics) {
                    Text("使用 Face ID 验证")
                        .gardenFont(size: 14 * scale, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 314 * scale, height: 58 * scale)
                        .background(
                            Color(red: 66 / 255, green: 197 / 255, blue: 168 / 255),
                            in: RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(hasPIN && !biometricEnabled)
                .opacity(hasPIN && !biometricEnabled ? 0.48 : 1)
                .position(x: 181 * scale, y: 153 * scale)

                Button(action: usePIN) {
                    Text("使用家长密码")
                        .gardenFont(size: 12 * scale)
                        .foregroundStyle(Color(red: 57 / 255, green: 118 / 255, blue: 107 / 255))
                        .frame(width: 314 * scale, height: 50 * scale)
                        .background(
                            Color(red: 231 / 255, green: 243 / 255, blue: 239 / 255),
                            in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .position(x: 181 * scale, y: 219 * scale)
            }
            .frame(width: 362 * scale, height: 282 * scale)
            .position(x: 201 * scale, y: 530 * scale)

            Text(purpose.sessionNote)
                .gardenFont(size: 10 * scale)
                .foregroundStyle(Color(red: 111 / 255, green: 142 / 255, blue: 136 / 255))
                .frame(width: 402 * scale, height: 20 * scale)
                .position(x: 201 * scale, y: 714 * scale)
        }
    }
}

private struct ParentCenterPage: View {
    @EnvironmentObject private var store: GardenStore
    let scale: CGFloat
    let showChild: () -> Void
    let showComfort: () -> Void
    let showPrivacy: () -> Void
    let showTherapist: () -> Void
    let onClose: () -> Void
    let changePIN: () -> Void
    @State private var showsChildList = false
    @State private var showsManagement = false

    var body: some View {
        ZStack {
            ParentBotanicalDecoration(scale: scale)
            ParentHeader(title: "家长中心", subtitle: "陪伴孩子安心成长", scale: scale, onBack: onClose)

            Button { showsChildList = true } label: {
                HStack(spacing: 13 * scale) {
                    ParentAvatar(size: 58 * scale)
                    VStack(alignment: .leading, spacing: 4 * scale) {
                        Text("当前儿童")
                            .gardenFont(size: 9 * scale)
                            .foregroundStyle(ParentPalette.secondary)
                        Text(store.userName)
                            .gardenFont(size: 17 * scale, weight: .bold)
                            .foregroundStyle(ParentPalette.ink)
                        Text("当前心情 · \(store.mood)")
                            .gardenFont(size: 10 * scale)
                            .foregroundStyle(ParentPalette.deepMint)
                    }
                    Spacer()
                    VStack(spacing: 4 * scale) {
                        Image(systemName: "chevron.up.chevron.down")
                        Text("切换")
                            .gardenFont(size: 9 * scale)
                    }
                    .foregroundStyle(ParentPalette.secondary)
                }
                .padding(.horizontal, 18 * scale)
                .frame(width: 362 * scale, height: 105 * scale)
                .parentCard(scale: scale)
            }
            .buttonStyle(.plain)
            .position(x: 201 * scale, y: 171.5 * scale)

            Text("日常陪伴")
                .gardenFont(size: 13 * scale, weight: .bold)
                .foregroundStyle(ParentPalette.ink)
                .frame(width: 160 * scale, height: 20 * scale, alignment: .leading)
                .position(x: 102 * scale, y: 254 * scale)

            Button(action: showComfort) {
                HStack(spacing: 14 * scale) {
                    ParentFeatureIcon(
                        asset: "parent_icon_comfort",
                        symbol: "moon.fill",
                        tint: Color(red: 148 / 255, green: 133 / 255, blue: 190 / 255),
                        size: 50 * scale,
                        glyphSize: 22 * scale
                    )
                    VStack(alignment: .leading, spacing: 5 * scale) {
                        Text("使用与舒适")
                            .gardenFont(size: 16 * scale, weight: .bold)
                        Text("提醒、安静时段、音乐与动画强度")
                            .gardenFont(size: 10 * scale)
                            .foregroundStyle(ParentPalette.secondary)
                        Text(comfortSummary)
                            .gardenFont(size: 9 * scale)
                            .foregroundStyle(ParentPalette.deepMint)
                    }
                    Spacer()
                    ParentChevron(scale: scale)
                }
                .padding(.horizontal, 18 * scale)
                .frame(width: 362 * scale, height: 128 * scale)
                .parentCard(scale: scale)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ParentPalette.ink)
            .position(x: 201 * scale, y: 335 * scale)

            ParentCenterNavRow(
                title: "儿童资料",
                subtitle: "基本信息与陪伴偏好",
                icon: "parent_icon_child",
                symbol: "person",
                tint: ParentPalette.deepMint,
                y: 451,
                scale: scale,
                action: showChild
            )
            ParentCenterNavRow(
                title: "数据与隐私",
                subtitle: "查看、导出与清除本地数据",
                icon: "parent_icon_privacy",
                symbol: "scope",
                tint: Color(red: 190 / 255, green: 132 / 255, blue: 93 / 255),
                y: 535,
                scale: scale,
                action: showPrivacy
            )
            ParentCenterNavRow(
                title: "康复师协作",
                subtitle: "尚未连接",
                icon: "parent_icon_therapist",
                symbol: "plus",
                tint: Color(red: 93 / 255, green: 141 / 255, blue: 167 / 255),
                y: 619,
                scale: scale,
                action: showTherapist
            )

            Text("当前数据状态")
                .gardenFont(size: 13 * scale, weight: .bold)
                .foregroundStyle(ParentPalette.ink)
                .frame(width: 160 * scale, height: 20 * scale, alignment: .leading)
                .position(x: 102 * scale, y: 685 * scale)

            ZStack {
                Text("数据状态")
                    .gardenFont(size: 13 * scale, weight: .bold)
                    .foregroundStyle(ParentPalette.ink)
                    .frame(width: 120 * scale, height: 20 * scale, alignment: .leading)
                    .position(x: 76 * scale, y: 23 * scale)

                Button { showsManagement = true } label: {
                    HStack(spacing: 4 * scale) {
                        Text("管理设置")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7 * scale, weight: .bold))
                    }
                    .gardenFont(size: 10 * scale, weight: .bold)
                    .foregroundStyle(ParentPalette.deepMint)
                    .frame(width: 96 * scale, height: 20 * scale, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .position(x: 298 * scale, y: 25 * scale)

                ParentDataStatusItem(
                    title: "照片留存",
                    value: "已开启",
                    tint: ParentPalette.mint,
                    scale: scale
                )
                .position(x: 66 * scale, y: 72 * scale)

                ParentDataStatusItem(
                    title: "云端同步",
                    value: "已关闭",
                    tint: ParentPalette.secondary,
                    scale: scale
                )
                .position(x: 178 * scale, y: 72 * scale)

                ParentDataStatusItem(
                    title: "康复师分享",
                    value: "未连接",
                    tint: Color(red: 112 / 255, green: 157 / 255, blue: 178 / 255),
                    scale: scale
                )
                .position(x: 290 * scale, y: 72 * scale)
            }
            .frame(width: 362 * scale, height: 114 * scale)
            .parentCard(scale: scale)
            .position(x: 201 * scale, y: 761 * scale)
        }
        .sheet(isPresented: $showsChildList) {
            NavigationStack {
                List {
                    HStack(spacing: 14) {
                        ParentAvatar(size: 52)
                        VStack(alignment: .leading) {
                            Text(store.userName).gardenFont(size: 17, weight: .bold)
                            Text("当前儿童").gardenFont(size: 11).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(ParentPalette.mint)
                    }
                }
                .navigationTitle("选择儿童")
                .toolbar { Button("完成") { showsChildList = false } }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsManagement) {
            ParentSecuritySheet(changePIN: {
                showsManagement = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: changePIN)
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var comfortSummary: String {
        let reminder = store.parentPreferences.reminderMinutes == 0
            ? "提醒已关"
            : "\(store.parentPreferences.reminderMinutes) 分钟提醒"
        return "\(reminder) · \(store.parentPreferences.animationStrength.title)动画"
    }
}

private struct ParentDataStatusItem: View {
    let title: String
    let value: String
    let tint: Color
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 4 * scale) {
            HStack(spacing: 4 * scale) {
                Circle()
                    .fill(tint)
                    .frame(width: 5 * scale, height: 5 * scale)
                Text(title)
            }
            .gardenFont(size: 8 * scale, weight: .bold)
            .foregroundStyle(ParentPalette.ink)

            Text(value)
                .gardenFont(size: 8 * scale)
                .foregroundStyle(ParentPalette.secondary)
        }
        .frame(width: 104 * scale, height: 58 * scale)
        .background(
            Color(red: 1, green: 253 / 255, blue: 249 / 255).opacity(0.7),
            in: RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
        )
    }
}

private struct ParentCenterNavRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let symbol: String
    let tint: Color
    let y: CGFloat
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13 * scale) {
                ParentFeatureIcon(
                    asset: icon,
                    symbol: symbol,
                    tint: tint,
                    size: 42 * scale,
                    glyphSize: 18 * scale
                )
                VStack(alignment: .leading, spacing: 3 * scale) {
                    Text(title).gardenFont(size: 14 * scale, weight: .bold)
                    Text(subtitle).gardenFont(size: 9 * scale).foregroundStyle(ParentPalette.secondary)
                }
                Spacer()
                ParentChevron(scale: scale)
            }
            .padding(.horizontal, 16 * scale)
            .frame(width: 362 * scale, height: 72 * scale)
            .parentCard(scale: scale)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ParentPalette.ink)
        .position(x: 201 * scale, y: y * scale)
    }
}

private struct ParentFeatureIcon: View {
    let asset: String
    let symbol: String
    let tint: Color
    let size: CGFloat
    let glyphSize: CGFloat

    var body: some View {
        ZStack {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
            Image(systemName: symbol)
                .font(.system(size: glyphSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private enum ParentChildDestination { case back, kaka }

private struct ParentChildPage: View {
    @EnvironmentObject private var store: GardenStore
    let scale: CGFloat
    let navigate: (ParentChildDestination) -> Void

    @State private var editor: ChildEditor?
    @State private var avatarSource: AvatarSource?
    @State private var photoItem: PhotosPickerItem?
    @State private var showsAvatarActions = false

    fileprivate enum ChildEditor: String, Identifiable {
        case name, birthDate, guidance, primaryCaregiver, coCaregiver
        var id: String { rawValue }
    }

    private enum AvatarSource: String, Identifiable {
        case camera
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            ParentHeader(title: "儿童资料", subtitle: "了解孩子，更好地陪伴", scale: scale) {
                navigate(.back)
            }

            VStack(spacing: 0) {
                HStack(spacing: 16 * scale) {
                    Button { showsAvatarActions = true } label: {
                        ZStack(alignment: .bottomTrailing) {
                            ParentAvatar(size: 82 * scale)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11 * scale, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 25 * scale, height: 25 * scale)
                                .background(ParentPalette.mint, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2 * scale))
                        }
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 5 * scale) {
                        Text(store.userName)
                            .gardenFont(size: 20 * scale, weight: .bold)
                            .foregroundStyle(ParentPalette.ink)
                        Text("\(ageText) · 学龄前阶段")
                            .gardenFont(size: 10 * scale)
                            .foregroundStyle(ParentPalette.secondary)
                        Text("点击头像可更换照片")
                            .gardenFont(size: 9 * scale)
                            .foregroundStyle(ParentPalette.deepMint)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18 * scale)
                .frame(width: 362 * scale, height: 142 * scale)
                .parentCard(scale: scale)
            }
            .position(x: 201 * scale, y: 193 * scale)

            ParentSectionLabel("基本信息", y: 290, scale: scale)
            ParentValueRow(title: "昵称", value: store.userName, y: 345, scale: scale) { editor = .name }
            ParentValueRow(title: "出生日期", value: birthDateText, y: 413, scale: scale) { editor = .birthDate }
            ParentValueRow(title: "年龄阶段", value: "\(ageText) · 学龄前", y: 481, scale: scale) { editor = .birthDate }
            ParentValueRow(title: "引导偏好", value: store.parentPreferences.guidancePreference.title, y: 549, scale: scale) { editor = .guidance }

            ParentSectionLabel("家庭陪伴", y: 603, scale: scale)
            ParentValueRow(
                title: "主要照护者",
                value: store.parentPreferences.primaryCaregiver.title,
                y: 668,
                height: 76,
                scale: scale
            ) { editor = .primaryCaregiver }
            ParentValueRow(
                title: "共同照护者",
                value: coCaregiverText,
                y: 752,
                height: 76,
                scale: scale
            ) { editor = .coCaregiver }

            Button { navigate(.kaka) } label: {
                HStack {
                    KakaAvatarView().frame(width: 42 * scale, height: 42 * scale)
                    VStack(alignment: .leading, spacing: 2 * scale) {
                        Text("KAKA 形象")
                            .gardenFont(size: 13 * scale, weight: .bold)
                        Text("前往装扮世界更换全 App 形象")
                            .gardenFont(size: 8 * scale)
                    }
                    Spacer()
                    ParentChevron(scale: scale)
                }
                .foregroundStyle(ParentPalette.ink)
                .padding(.horizontal, 16 * scale)
                .frame(width: 362 * scale, height: 58 * scale)
                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18 * scale))
            }
            .buttonStyle(.plain)
            .position(x: 201 * scale, y: 825 * scale)
        }
        .confirmationDialog("更换儿童头像", isPresented: $showsAvatarActions) {
            Button("拍照") { avatarSource = .camera }
            Button("从照片中选择") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    photoPickerPresented = true
                }
            }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(isPresented: $photoPickerPresented, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                saveAvatar(image)
            }
        }
        .sheet(item: $avatarSource) { _ in
            ParentCameraPicker { image in
                avatarSource = nil
                if let image { saveAvatar(image) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $editor) { editor in
            ChildEditorSheet(editor: editor, isPresented: Binding(
                get: { self.editor != nil },
                set: { if !$0 { self.editor = nil } }
            ))
            .presentationDetents([.height(editor == .birthDate ? 480 : 390)])
            .presentationDragIndicator(.visible)
        }
    }

    @State private var photoPickerPresented = false

    private var birthDateText: String {
        store.parentPreferences.birthDate.formatted(.dateTime.year().month().day())
    }

    private var ageText: String {
        let years = max(0, Calendar.current.dateComponents([.year], from: store.parentPreferences.birthDate, to: Date()).year ?? 0)
        return "\(years) 岁"
    }

    private var coCaregiverText: String {
        let text = store.parentPreferences.coCaregivers.map(\.title).joined(separator: "、")
        return text.isEmpty ? "未设置" : text
    }

    private func saveAvatar(_ image: UIImage) {
        if let old = store.parentPreferences.childAvatarFileName { ParentChildAvatarStore.delete(old) }
        store.parentPreferences.childAvatarFileName = ParentChildAvatarStore.save(image)
    }
}

private struct ChildEditorSheet: View {
    @EnvironmentObject private var store: GardenStore
    let editor: ParentChildPage.ChildEditor
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var date = Date()
    @State private var guidance: ParentGuidancePreference = .combined
    @State private var caregiver: ParentCaregiverRole = .mother
    @State private var coCaregivers = Set<ParentCaregiverRole>()

    var body: some View {
        NavigationStack {
            Form {
                switch editor {
                case .name:
                    TextField("儿童昵称", text: $name)
                case .birthDate:
                    DatePicker("出生日期", selection: $date, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                case .guidance:
                    Picker("引导偏好", selection: $guidance) {
                        ForEach(ParentGuidancePreference.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                case .primaryCaregiver:
                    Picker("主要照护者", selection: $caregiver) {
                        ForEach(ParentCaregiverRole.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                case .coCaregiver:
                    ForEach(ParentCaregiverRole.allCases) { role in
                        Button {
                            if coCaregivers.contains(role) { coCaregivers.remove(role) }
                            else { coCaregivers.insert(role) }
                        } label: {
                            HStack {
                                Text(role.title).foregroundStyle(.primary)
                                Spacer()
                                if coCaregivers.contains(role) {
                                    Image(systemName: "checkmark").foregroundStyle(ParentPalette.mint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(editorTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
        }
        .onAppear {
            name = store.userName
            date = store.parentPreferences.birthDate
            guidance = store.parentPreferences.guidancePreference
            caregiver = store.parentPreferences.primaryCaregiver
            coCaregivers = Set(store.parentPreferences.coCaregivers)
        }
    }

    private var editorTitle: String {
        switch editor {
        case .name: "修改昵称"
        case .birthDate: "出生日期"
        case .guidance: "引导偏好"
        case .primaryCaregiver: "主要照护者"
        case .coCaregiver: "共同照护者"
        }
    }

    private func save() {
        switch editor {
        case .name:
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { store.userName = String(trimmed.prefix(12)) }
        case .birthDate: store.parentPreferences.birthDate = date
        case .guidance: store.parentPreferences.guidancePreference = guidance
        case .primaryCaregiver: store.parentPreferences.primaryCaregiver = caregiver
        case .coCaregiver:
            store.parentPreferences.coCaregivers = ParentCaregiverRole.allCases.filter(coCaregivers.contains)
        }
        isPresented = false
    }
}

private struct ParentComfortPage: View {
    @EnvironmentObject private var store: GardenStore
    let scale: CGFloat
    let onBack: () -> Void
    @State private var showsQuietEditor = false
    @State private var reminderStatus = ""

    var body: some View {
        ZStack {
            ParentHeader(title: "使用与舒适", subtitle: "让每次陪伴都恰到好处", scale: scale, onBack: onBack)

            VStack(alignment: .leading, spacing: 9 * scale) {
                Text("当前舒适预设")
                    .gardenFont(size: 9 * scale).foregroundStyle(ParentPalette.secondary)
                HStack {
                    Text("温柔陪伴")
                        .gardenFont(size: 18 * scale, weight: .bold).foregroundStyle(ParentPalette.ink)
                    Spacer()
                    Image(systemName: "leaf.fill").foregroundStyle(ParentPalette.mint)
                }
                Text("柔和动画 · 低音量 · 轻触反馈关闭")
                    .gardenFont(size: 10 * scale).foregroundStyle(ParentPalette.deepMint)
            }
            .padding(18 * scale)
            .frame(width: 362 * scale, height: 110 * scale)
            .parentCard(scale: scale)
            .position(x: 201 * scale, y: 177 * scale)

            ParentSectionLabel("日常节奏", y: 251, scale: scale)

            ParentMenuRow(
                title: "使用提醒",
                value: reminderText,
                y: 322,
                scale: scale
            ) {
                ForEach([0, 10, 20, 30, 45], id: \.self) { minute in
                    Button(minute == 0 ? "关闭" : "每 \(minute) 分钟") {
                        store.parentPreferences.reminderMinutes = minute
                        ParentReminderScheduler.update(minutes: minute) { status in
                            reminderStatus = status
                        }
                    }
                }
            }

            ParentValueRow(title: "安静时段", value: quietText, y: 406, height: 76, scale: scale) {
                showsQuietEditor = true
            }

            ParentSectionLabel("感官舒适", y: 457, scale: scale)

            VStack(alignment: .leading, spacing: 9 * scale) {
                HStack {
                    Text("音乐音量").gardenFont(size: 13 * scale, weight: .bold)
                    Spacer()
                    Text("\(Int(store.parentPreferences.musicVolume * 100))%")
                        .gardenFont(size: 10 * scale).foregroundStyle(ParentPalette.deepMint)
                }
                Slider(value: $store.parentPreferences.musicVolume, in: 0...1)
                    .tint(ParentPalette.mint)
            }
            .padding(.horizontal, 17 * scale)
            .frame(width: 362 * scale, height: 76 * scale)
            .parentCard(scale: scale)
            .position(x: 201 * scale, y: 534 * scale)

            ParentMenuRow(title: "动画强度", value: store.parentPreferences.animationStrength.title, y: 618, scale: scale) {
                ForEach(ParentAnimationStrength.allCases) { value in
                    Button(value.title) { store.parentPreferences.animationStrength = value }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 3 * scale) {
                    Text("触觉反馈").gardenFont(size: 13 * scale, weight: .bold)
                    Text("按钮和完成动作的轻微震动")
                        .gardenFont(size: 9 * scale).foregroundStyle(ParentPalette.secondary)
                }
                Spacer()
                Button {
                    store.parentPreferences.hapticsEnabled.toggle()
                } label: {
                    ParentSwitch(isOn: $store.parentPreferences.hapticsEnabled, scale: scale)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 17 * scale)
            .frame(width: 362 * scale, height: 76 * scale)
            .parentCard(scale: scale)
            .position(x: 201 * scale, y: 702 * scale)

            Text(reminderStatus)
                .gardenFont(size: 9 * scale)
                .foregroundStyle(ParentPalette.secondary)
                .frame(width: 350 * scale)
                .position(x: 201 * scale, y: 764 * scale)
        }
        .sheet(isPresented: $showsQuietEditor) {
            ParentQuietHoursSheet(isPresented: $showsQuietEditor)
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
        }
    }

    private var reminderText: String {
        guard store.parentPreferences.reminderMinutes > 0 else { return "已关闭" }
        return "每 \(store.parentPreferences.reminderMinutes) 分钟"
    }

    private var quietText: String {
        "\(ParentTimeText.string(store.parentPreferences.quietStartMinutes))–\(ParentTimeText.string(store.parentPreferences.quietEndMinutes))"
    }
}

private struct ParentQuietHoursSheet: View {
    @EnvironmentObject private var store: GardenStore
    @Binding var isPresented: Bool
    @State private var start = Date()
    @State private var end = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("开始", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("结束", selection: $end, displayedComponents: .hourAndMinute)
                Text("安静时段会暂停自动音乐和提醒，手动播放仍然可用。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("安静时段")
            .toolbar {
                Button("保存") {
                    store.parentPreferences.quietStartMinutes = ParentTimeText.minutes(start)
                    store.parentPreferences.quietEndMinutes = ParentTimeText.minutes(end)
                    isPresented = false
                }
            }
        }
        .onAppear {
            start = ParentTimeText.date(store.parentPreferences.quietStartMinutes)
            end = ParentTimeText.date(store.parentPreferences.quietEndMinutes)
        }
    }
}

private struct ParentPrivacyPage: View {
    @EnvironmentObject private var store: GardenStore
    let scale: CGFloat
    let onBack: () -> Void
    let verifyDelete: () -> Void

    @State private var showsLocalOnly = false
    @State private var infoSheet: PrivacyInfo?
    @State private var retentionEditor: RetentionKind?
    @State private var pendingDisable: DisableKind?
    @State private var exportRange: ParentReportRange?
    @State private var sharedReport: SharedReport?
    @State private var confirmsDelete = false
    @State private var didDelete = false

    private enum PrivacyInfo: String, Identifiable {
        case ai, storage
        var id: String { rawValue }
    }
    private enum DisableKind: String, Identifiable {
        case photos, ar
        var id: String { rawValue }
    }
    private enum RetentionKind: String, Identifiable {
        case photo, music, ar
        var id: String { rawValue }
    }

    private var content: some View {
        ZStack {
            ParentHeader(title: "数据与隐私", subtitle: "数据由家长掌握", scale: scale, onBack: onBack)

            Button { infoSheet = .ai } label: {
                ParentAIInfoCard(scale: scale)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ParentPalette.ink)
            .position(x: 201 * scale, y: 185 * scale)

            ParentSectionLabel("权限与保存", y: 266, scale: scale)

            ParentToggleRow(title: "保存表情照片", subtitle: "用于生成情绪乐卡", y: 337, scale: scale, isOn: Binding(
                get: { store.parentPreferences.retainEmotionPhotos },
                set: { value in
                    if value { store.parentPreferences.retainEmotionPhotos = true }
                    else { pendingDisable = .photos }
                }
            ))
            ParentToggleRow(title: "保存 AR 学习结果", subtitle: "保留任务完成与奖励记录", y: 421, scale: scale, isOn: Binding(
                get: { store.parentPreferences.retainARResults },
                set: { value in
                    if value { store.parentPreferences.retainARResults = true }
                    else { pendingDisable = .ar }
                }
            ))
            ParentToggleRow(title: "云端同步", subtitle: "当前版本仅保存在本机", y: 505, scale: scale, isOn: .constant(false), disabled: true) {
                showsLocalOnly = true
            }
            ParentValueRow(title: "数据留存周期", value: retentionSummary, y: 589, height: 76, scale: scale) {
                retentionEditor = .music
            }

            ParentSectionLabel("数据操作", y: 644, scale: scale)

            Button { exportRange = .thirtyDays } label: {
                ParentActionLabel(title: "导出成长报告", subtitle: "PDF 总结 + CSV 活动明细", color: ParentPalette.deepMint, scale: scale)
            }
            .buttonStyle(.plain)
            .frame(width: 362 * scale, height: 60 * scale)
            .parentCard(scale: scale)
            .position(x: 201 * scale, y: 712 * scale)

            Button { verifyDelete() } label: {
                ParentActionLabel(title: "删除全部成长记录", subtitle: "保留儿童资料、家长设置与密码", color: .red, scale: scale)
            }
            .buttonStyle(.plain)
            .frame(width: 362 * scale, height: 60 * scale)
            .parentCard(scale: scale)
            .position(x: 201 * scale, y: 780 * scale)
        }
    }

    var body: some View {
        alertLayer
    }

    private var dialogLayer: some View {
        content
        .alert("仅保存在本机", isPresented: $showsLocalOnly) {
            Button("知道了", role: .cancel) {}
        } message: { Text("灵想当前不会把儿童数据同步到云端。") }
        .confirmationDialog(
            "关闭后如何处理已有数据？",
            isPresented: Binding(
                get: { pendingDisable != nil },
                set: { if !$0 { pendingDisable = nil } }
            ),
            presenting: pendingDisable
        ) { kind in
            Button("仅停止继续保存") { disable(kind, deleteExisting: false) }
            Button("停止保存并删除已有数据", role: .destructive) { disable(kind, deleteExisting: true) }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "选择报告范围",
            isPresented: Binding(
                get: { exportRange != nil },
                set: { if !$0 { exportRange = nil } }
            ),
            presenting: exportRange
        ) { _ in
            ForEach(ParentReportRange.allCases) { range in
                Button(range.title) { export(range) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var sheetLayer: some View {
        dialogLayer
        .sheet(item: $infoSheet) { info in
            ParentPrivacyInfoSheet(info: info)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $retentionEditor) { _ in
            ParentRetentionSheet(isPresented: Binding(
                get: { retentionEditor != nil },
                set: { if !$0 { retentionEditor = nil } }
            ))
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $sharedReport) { report in
            ParentShareSheet(items: report.urls)
        }
    }

    private var alertLayer: some View {
        sheetLayer
        .onReceive(NotificationCenter.default.publisher(for: .parentDeleteVerified)) { _ in
            confirmsDelete = true
        }
        .alert("确定删除全部成长记录？", isPresented: $confirmsDelete) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                store.deleteAllActivityData()
                didDelete = true
            }
        } message: {
            Text("情绪、音乐、AR、花房记录及相关照片都会从本机删除，无法恢复。")
        }
        .alert("记录已删除", isPresented: $didDelete) {
            Button("知道了", role: .cancel) {}
        } message: { Text("儿童资料、舒适设置和家长密码已保留。") }
    }

    private var retentionSummary: String {
        let values = [store.parentPreferences.photoRetention, store.parentPreferences.musicRetention, store.parentPreferences.arRetention]
        return Set(values).count == 1 ? values[0].title : "分别设置"
    }

    private func disable(_ kind: DisableKind, deleteExisting: Bool) {
        switch kind {
        case .photos:
            store.parentPreferences.retainEmotionPhotos = false
            if deleteExisting { store.deleteEmotionPhotos() }
        case .ar:
            store.parentPreferences.retainARResults = false
            if deleteExisting { store.deleteARLearningRecords() }
        }
    }

    private func export(_ range: ParentReportRange) {
        if let urls = try? ParentReportExporter.make(store: store, range: range) {
            sharedReport = SharedReport(urls: urls)
        }
    }
}

private struct ParentRetentionSheet: View {
    @EnvironmentObject private var store: GardenStore
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                retentionPicker("照片与花房", selection: $store.parentPreferences.photoRetention)
                retentionPicker("音乐与情绪", selection: $store.parentPreferences.musicRetention)
                retentionPicker("AR 学习结果", selection: $store.parentPreferences.arRetention)
                Section {
                    Text("达到留存期限后，灵想会在本机自动移除对应记录。永久保留也仅指这台设备。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("数据留存周期")
            .toolbar {
                Button("完成") {
                    store.purgeExpiredParentData()
                    isPresented = false
                }
            }
        }
    }

    private func retentionPicker(_ title: String, selection: Binding<ParentRetentionPeriod>) -> some View {
        Section(title) {
            Picker(title, selection: selection) {
                ForEach(ParentRetentionPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

private struct ParentAIInfoCard: View {
    let scale: CGFloat
    var body: some View {
        HStack(spacing: 14 * scale) {
            Image(systemName: "sparkles")
                .font(.system(size: 24 * scale, weight: .medium))
                .foregroundStyle(Color.orange)
                .frame(width: 46 * scale, height: 46 * scale)
                .background(Color.orange.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 5 * scale) {
                Text("AI 情绪识别说明")
                    .gardenFont(size: 15 * scale, weight: .bold)
                Text("仅用于当次体验；默认不上传面部照片")
                    .gardenFont(size: 9 * scale).foregroundStyle(ParentPalette.secondary)
                Text("查看处理方式")
                    .gardenFont(size: 9 * scale, weight: .bold).foregroundStyle(Color.orange)
            }
            Spacer()
            ParentChevron(scale: scale)
        }
        .padding(.horizontal, 17 * scale)
        .frame(width: 362 * scale, height: 126 * scale)
        .background(Color(red: 1, green: 0.97, blue: 0.91).opacity(0.9), in: RoundedRectangle(cornerRadius: 24 * scale))
        .overlay(RoundedRectangle(cornerRadius: 24 * scale).stroke(.white.opacity(0.95), lineWidth: scale))
    }
}

private struct ParentPrivacyInfoSheet: View {
    let info: Any
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label("本地优先", systemImage: "iphone.gen3")
                        .font(.title3.bold()).foregroundStyle(ParentPalette.deepMint)
                    Text("表情照片只在设备端用于生成情绪乐卡；关闭保存后，新照片不会写入本机。成长记录导出不包含原始照片。")
                    Text("云同步与康复师连接在当前版本均未开放，应用不会把儿童活动数据自动发送给第三方。")
                }
                .padding(24)
            }
            .navigationTitle("数据处理说明")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ParentTherapistPage: View {
    let scale: CGFloat
    let onBack: () -> Void
    @State private var showsUnavailable = false

    var body: some View {
        ZStack {
            ParentHeader(title: "康复师协作", subtitle: "由家长决定分享范围", scale: scale, onBack: onBack)

            VStack(spacing: 10 * scale) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 34 * scale))
                    .foregroundStyle(Color(red: 0.35, green: 0.63, blue: 0.93))
                Text("尚未连接康复师")
                    .gardenFont(size: 17 * scale, weight: .bold)
                Text("输入康复师提供的连接码后，家长才可选择分享内容")
                    .gardenFont(size: 9 * scale).foregroundStyle(ParentPalette.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 362 * scale, height: 132 * scale)
            .background(Color(red: 0.91, green: 0.96, blue: 1).opacity(0.9), in: RoundedRectangle(cornerRadius: 24 * scale))
            .position(x: 201 * scale, y: 188 * scale)

            ParentSectionLabel("可分享内容", y: 274, scale: scale)
            ParentDisabledShareRow(title: "情绪变化趋势", y: 345, scale: scale)
            ParentDisabledShareRow(title: "音乐调节记录", y: 429, scale: scale)
            ParentDisabledShareRow(title: "AR 任务完成情况", y: 513, scale: scale)
            ParentDisabledShareRow(title: "家长小记", y: 597, scale: scale)

            Button { showsUnavailable = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3 * scale) {
                        Text("输入康复师连接码").gardenFont(size: 13 * scale, weight: .bold)
                        Text("功能准备中").gardenFont(size: 9 * scale).foregroundStyle(ParentPalette.secondary)
                    }
                    Spacer()
                    ParentChevron(scale: scale)
                }
                .padding(.horizontal, 17 * scale)
                .foregroundStyle(ParentPalette.ink)
            }
            .buttonStyle(.plain)
            .frame(width: 362 * scale, height: 60 * scale)
            .parentCard(scale: scale)
            .position(x: 201 * scale, y: 717 * scale)

            HStack {
                Text("撤销全部授权").gardenFont(size: 13 * scale, weight: .bold)
                Spacer()
                Text("未连接").gardenFont(size: 10 * scale).foregroundStyle(ParentPalette.secondary)
            }
            .padding(.horizontal, 17 * scale)
            .frame(width: 362 * scale, height: 60 * scale)
            .parentCard(scale: scale)
            .opacity(0.55)
            .position(x: 201 * scale, y: 785 * scale)
        }
        .alert("功能暂未开放", isPresented: $showsUnavailable) {
            Button("知道了", role: .cancel) {}
        } message: { Text("康复师连接将在后续版本开放。当前数据不会被分享。") }
    }
}

private struct ParentDisabledShareRow: View {
    let title: String
    let y: CGFloat
    let scale: CGFloat
    var body: some View {
        HStack {
            Text(title).gardenFont(size: 13 * scale, weight: .bold)
            Spacer()
            ParentSwitch(isOn: .constant(false), scale: scale).opacity(0.55)
        }
        .padding(.horizontal, 17 * scale)
        .frame(width: 362 * scale, height: 76 * scale)
        .parentCard(scale: scale)
        .foregroundStyle(ParentPalette.ink)
        .opacity(0.72)
        .position(x: 201 * scale, y: y * scale)
    }
}

private struct ParentSecuritySheet: View {
    @EnvironmentObject private var store: GardenStore
    let changePIN: () -> Void
    @State private var localOnly = false

    var body: some View {
        NavigationStack {
            List {
                Section("家长验证") {
                    Toggle("使用 Face ID", isOn: Binding(
                        get: { store.parentPreferences.biometricEnabled },
                        set: { value in
                            if value {
                                Task {
                                    if (try? await ParentAuthentication.authenticateBiometrics()) != nil {
                                        store.parentPreferences.biometricEnabled = true
                                    }
                                }
                            } else {
                                store.parentPreferences.biometricEnabled = false
                            }
                        }
                    ))
                    Button("更改家长密码", action: changePIN)
                }
                Section("数据状态") {
                    LabeledContent("存储位置", value: "仅本机")
                    Button("云端同步（未开放）") { localOnly = true }
                }
            }
            .navigationTitle("管理设置")
            .alert("仅保存在本机", isPresented: $localOnly) {
                Button("知道了", role: .cancel) {}
            }
        }
    }
}

private enum PinSheetMode: String, Identifiable {
    case setup, verify, verifyForChange, verifyForDelete
    var id: String { rawValue }
    var isSetup: Bool { self == .setup }
}

private struct ParentPINSheet: View {
    let mode: PinSheetMode
    let onSuccess: (String) -> Void
    let onForgot: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var localError = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: mode.isSetup ? "lock.badge.plus" : "lock.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(ParentPalette.mint)
                    .padding(.top, 12)
                SecureField("4 位数字密码", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.title2.monospacedDigit())
                    .padding()
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: pin) { _, value in pin = String(value.filter(\.isNumber).prefix(4)) }
                if mode.isSetup {
                    SecureField("再次输入", text: $confirmation)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .font(.title2.monospacedDigit())
                        .padding()
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .onChange(of: confirmation) { _, value in confirmation = String(value.filter(\.isNumber).prefix(4)) }
                }
                if !localError.isEmpty { Text(localError).font(.footnote).foregroundStyle(.red) }
                Button(mode.isSetup ? "保存家长密码" : "验证") { submit() }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(ParentPalette.mint, in: Capsule())
                    .disabled(pin.count != 4 || (mode.isSetup && confirmation.count != 4))
                    .opacity(pin.count == 4 && (!mode.isSetup || confirmation.count == 4) ? 1 : 0.45)
                if !mode.isSetup {
                    Button("忘记密码") { onForgot() }
                        .font(.footnote).foregroundStyle(ParentPalette.deepMint)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .navigationTitle(mode.isSetup ? "创建家长密码" : "家长密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("取消") { dismiss() } }
        }
    }

    private func submit() {
        if mode.isSetup, pin != confirmation {
            localError = "两次输入不一致"
            return
        }
        if !mode.isSetup, !ParentPINStore.verify(pin) {
            localError = "密码不正确，请重新输入"
            pin = ""
            return
        }
        onSuccess(pin)
    }
}

private struct ParentHeader: View {
    let title: String
    let subtitle: String
    let scale: CGFloat
    let onBack: () -> Void
    var usesFigmaExportSizing = false

    var body: some View {
        let backSize: CGFloat = usesFigmaExportSizing ? 56 : 48
        let backY: CGFloat = usesFigmaExportSizing ? 83 : 79

        ZStack {
            Button(action: onBack) {
                Image("parent_back")
                    .resizable().scaledToFit()
                    .frame(width: backSize * scale, height: backSize * scale)
            }
            .buttonStyle(.plain)
            .position(x: 44 * scale, y: backY * scale)

            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(title).gardenFont(size: 23 * scale, weight: .bold)
                Text(subtitle).gardenFont(size: 11 * scale).foregroundStyle(ParentPalette.secondary)
            }
            .foregroundStyle(ParentPalette.ink)
            .frame(width: 285 * scale, alignment: .leading)
            .position(x: 233.5 * scale, y: 80 * scale)
        }
    }
}

private struct ParentBackground: View {
    var matchesParentVerificationDesign = false

    var body: some View {
        LinearGradient(
            colors: matchesParentVerificationDesign
                ? [
                    Color(red: 244 / 255, green: 252 / 255, blue: 249 / 255),
                    Color(red: 217 / 255, green: 240 / 255, blue: 232 / 255)
                ]
                : [
                    Color(red: 0.96, green: 0.99, blue: 0.98),
                    Color(red: 0.87, green: 0.95, blue: 0.92)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct ParentBotanicalDecoration: View {
    let scale: CGFloat
    var body: some View {
        ZStack {
            Image("parent_bg_left").resizable().scaledToFit()
                .frame(width: 150 * scale, height: 270 * scale)
                .position(x: 55 * scale, y: 724 * scale)
            Image("parent_bg_right").resizable().scaledToFit()
                .frame(width: 190 * scale, height: 310 * scale)
                .position(x: 350 * scale, y: 735 * scale)
        }
        .opacity(0.72)
        .allowsHitTesting(false)
    }
}

private struct ParentAvatar: View {
    @EnvironmentObject private var store: GardenStore
    let size: CGFloat
    var body: some View {
        Group {
            if let image = ParentChildAvatarStore.load(store.parentPreferences.childAvatarFileName) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image("profile_child_avatar").resizable().scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
    }
}

private struct ParentChevron: View {
    let scale: CGFloat
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11 * scale, weight: .bold))
            .foregroundStyle(ParentPalette.secondary)
    }
}

private struct ParentSectionLabel: View {
    let title: String
    let y: CGFloat
    let scale: CGFloat
    init(_ title: String, y: CGFloat, scale: CGFloat) { self.title = title; self.y = y; self.scale = scale }
    var body: some View {
        Text(title)
            .gardenFont(size: 12 * scale, weight: .bold)
            .foregroundStyle(ParentPalette.secondary)
            .frame(width: 362 * scale, alignment: .leading)
            .position(x: 201 * scale, y: y * scale)
    }
}

private struct ParentValueRow: View {
    let title: String
    let value: String
    let y: CGFloat
    var height: CGFloat = 60
    let scale: CGFloat
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).gardenFont(size: 13 * scale, weight: .bold)
                Spacer()
                Text(value).gardenFont(size: 10 * scale).foregroundStyle(ParentPalette.secondary)
                ParentChevron(scale: scale)
            }
            .padding(.horizontal, 17 * scale)
            .frame(width: 362 * scale, height: height * scale)
            .parentCard(scale: scale)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ParentPalette.ink)
        .position(x: 201 * scale, y: y * scale)
    }
}

private struct ParentMenuRow<MenuContent: View>: View {
    let title: String
    let value: String
    let y: CGFloat
    let scale: CGFloat
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        Menu(content: menu) {
            HStack {
                Text(title).gardenFont(size: 13 * scale, weight: .bold)
                Spacer()
                Text(value).gardenFont(size: 10 * scale).foregroundStyle(ParentPalette.secondary)
                ParentChevron(scale: scale)
            }
            .padding(.horizontal, 17 * scale)
            .frame(width: 362 * scale, height: 76 * scale)
            .parentCard(scale: scale)
        }
        .foregroundStyle(ParentPalette.ink)
        .position(x: 201 * scale, y: y * scale)
    }
}

private struct ParentToggleRow: View {
    let title: String
    let subtitle: String
    let y: CGFloat
    let scale: CGFloat
    let isOn: Binding<Bool>
    var disabled = false
    var disabledAction: () -> Void = {}

    var body: some View {
        Button {
            if disabled { disabledAction() } else { isOn.wrappedValue.toggle() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3 * scale) {
                    Text(title).gardenFont(size: 13 * scale, weight: .bold)
                    Text(subtitle).gardenFont(size: 9 * scale).foregroundStyle(ParentPalette.secondary)
                }
                Spacer()
                ParentSwitch(isOn: isOn, scale: scale)
                    .allowsHitTesting(false)
                    .opacity(disabled ? 0.55 : 1)
            }
            .padding(.horizontal, 17 * scale)
            .frame(width: 362 * scale, height: 76 * scale)
            .parentCard(scale: scale)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ParentPalette.ink)
        .position(x: 201 * scale, y: y * scale)
    }
}

private struct ParentSwitch: View {
    @Binding var isOn: Bool
    let scale: CGFloat
    var body: some View {
        Capsule()
            .fill(isOn ? ParentPalette.mint : Color(red: 0.83, green: 0.86, blue: 0.86))
            .frame(width: 48 * scale, height: 28 * scale)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white)
                    .frame(width: 24 * scale, height: 24 * scale)
                    .shadow(color: .black.opacity(0.13), radius: 2 * scale, y: scale)
                    .padding(2 * scale)
            }
            .animation(.easeInOut(duration: 0.18), value: isOn)
    }
}

private struct ParentActionLabel: View {
    let title: String
    let subtitle: String
    let color: Color
    let scale: CGFloat
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(title).gardenFont(size: 13 * scale, weight: .bold).foregroundStyle(color)
                Text(subtitle).gardenFont(size: 9 * scale).foregroundStyle(ParentPalette.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 15 * scale, weight: .medium)).foregroundStyle(color)
        }
        .padding(.horizontal, 17 * scale)
    }
}

private enum ParentPalette {
    static let mint = Color(red: 0.26, green: 0.77, blue: 0.66)
    static let deepMint = Color(red: 0.08, green: 0.55, blue: 0.48)
    static let ink = Color(red: 0.15, green: 0.30, blue: 0.29)
    static let secondary = Color(red: 0.40, green: 0.52, blue: 0.49)
    static let line = Color(red: 0.79, green: 0.87, blue: 0.84)
}

private extension View {
    func parentCard(scale: CGFloat) -> some View {
        background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22 * scale, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22 * scale).stroke(.white.opacity(0.94), lineWidth: scale))
            .shadow(color: ParentPalette.deepMint.opacity(0.055), radius: 13 * scale, y: 6 * scale)
    }
}

private enum ParentAuthentication {
    static func authenticateBiometrics(reason: String = "进入灵想家长中心") async throws {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw error ?? LAError(.biometryNotAvailable)
        }
        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
        if !success { throw LAError(.authenticationFailed) }
    }

    static func authenticateDeviceOwner(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? LAError(.passcodeNotSet)
        }
        let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        if !success { throw LAError(.authenticationFailed) }
    }
}

private enum ParentPINStore {
    private static let service = "com.example.Sproutly.parent-gate"
    private static let account = "parent-pin"

    static var hasPIN: Bool { read() != nil }
    static func verify(_ pin: String) -> Bool { read() == pin }

    static func set(_ pin: String) {
        let data = Data(pin.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private enum ParentChildAvatarStore {
    static func save(_ image: UIImage) -> String? {
        let size = CGSize(width: 600, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let ratio = max(size.width / image.size.width, size.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            image.draw(in: CGRect(
                x: (size.width - drawSize.width) / 2,
                y: (size.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.88) else { return nil }
        let name = UUID().uuidString + ".jpg"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            return name
        } catch { return nil }
    }

    static func load(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    private static var directory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("Sproutly", isDirectory: true)
            .appendingPathComponent("ChildAvatar", isDirectory: true)
    }
}

private struct ParentCameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }
    }
}

private enum ParentTimeText {
    static func string(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
    static func date(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }
    static func minutes(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

enum ParentReminderScheduler {
    static func update(minutes: Int, completion: @escaping (String) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["sproutly.parent.usage-reminder"])
        guard minutes > 0 else {
            completion("提醒已关闭")
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted ? "后台提醒已开启" : "通知未授权，将仅在前台温柔提醒")
            }
            guard granted else { return }
            schedule(minutes: minutes, center: center)
        }
    }

    static func scheduleIfAuthorized(minutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["sproutly.parent.usage-reminder"])
        guard minutes > 0 else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            schedule(minutes: minutes, center: center)
        }
    }

    private static func schedule(minutes: Int, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "休息一下吧"
        content.body = "和 KAKA 一起看看远处、伸伸手，再继续探索。"
        content.sound = .default
        let target = adjustedDeliveryDate(
            Date().addingTimeInterval(TimeInterval(minutes * 60)),
            preferences: ParentComfortRuntime.preferences
        )
        let request = UNNotificationRequest(
            identifier: "sproutly.parent.usage-reminder",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(60, target.timeIntervalSinceNow),
                repeats: false
            )
        )
        center.add(request)
    }

    private static func adjustedDeliveryDate(_ target: Date, preferences: ParentPreferences) -> Date {
        guard preferences.isQuietTime(target) else { return target }
        let calendar = Calendar.current
        let endHour = preferences.quietEndMinutes / 60
        let endMinute = preferences.quietEndMinutes % 60
        var end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: target) ?? target
        if end <= target { end = calendar.date(byAdding: .day, value: 1, to: end) ?? target }
        return end
    }
}

private enum ParentReportRange: String, CaseIterable, Identifiable {
    case sevenDays, thirtyDays, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sevenDays: "最近 7 天"
        case .thirtyDays: "最近 30 天"
        case .all: "全部记录"
        }
    }
    var cutoff: Date? {
        switch self {
        case .sevenDays: Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .thirtyDays: Calendar.current.date(byAdding: .day, value: -30, to: Date())
        case .all: nil
        }
    }
}

private struct SharedReport: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private enum ParentReportExporter {
    @MainActor
    static func make(store: GardenStore, range: ParentReportRange) throws -> [URL] {
        let cutoff = range.cutoff
        let emotions = store.emotionRecords.filter { record in
            guard let cutoff else { return true }
            return record.timestamp >= cutoff
        }
        let ar = store.arLearningRecords.filter { record in
            guard let cutoff else { return true }
            return record.completedAt >= cutoff
        }
        let tickets = store.flowerTickets.filter { record in
            guard let cutoff else { return true }
            return record.timestamp >= cutoff
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SproutlyReports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Date().formatted(.iso8601.year().month().day())
        let pdfURL = directory.appendingPathComponent("灵想成长报告-\(stamp).pdf")
        let csvURL = directory.appendingPathComponent("灵想活动明细-\(stamp).csv")

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "灵想成长报告"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842), format: format)
        try renderer.writePDF(to: pdfURL) { context in
            context.beginPage()
            let title = "灵想 · 成长报告"
            title.draw(at: CGPoint(x: 48, y: 52), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 25)])
            let body = "儿童：\(store.userName)\n范围：\(range.title)\n生成时间：\(Date().formatted(date: .long, time: .shortened))\n\n情绪记录：\(emotions.count) 次\n音乐调节：\(emotions.filter { $0.musicSession != nil }.count) 次\nAR 任务：\(ar.count) 关\n花房记录：\(tickets.count) 张\n\n说明：此报告不包含原始面部照片，仅汇总本机活动数据。"
            body.draw(in: CGRect(x: 48, y: 112, width: 499, height: 620), withAttributes: [
                .font: UIFont.systemFont(ofSize: 15),
                .foregroundColor: UIColor(red: 0.15, green: 0.30, blue: 0.29, alpha: 1)
            ])
        }

        var rows = ["时间,类型,内容,时长秒"]
        rows += emotions.map { record in
            "\(csv(record.timestamp)),情绪,\(record.emotion.title),\(record.musicSession?.durationSeconds ?? 0)"
        }
        rows += ar.map { record in
            "\(csv(record.completedAt)),AR任务,第\(record.taskNumber)关-\(record.rewardName),\(record.durationSeconds)"
        }
        rows += tickets.map { record in
            "\(csv(record.timestamp)),花房,第\(record.number)张花房票,0"
        }
        try rows.joined(separator: "\n").data(using: .utf8)?.write(to: csvURL, options: .atomic)
        return [pdfURL, csvURL]
    }

    private static func csv(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false))
    }
}

private struct ParentShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    init(items: [URL]) { self.items = items }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension Notification.Name {
    static let parentDeleteVerified = Notification.Name("sproutly.parent.deleteVerified")
}
