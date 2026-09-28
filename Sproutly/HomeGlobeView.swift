import Combine
import RealityKit
import simd
import SwiftUI

@MainActor
final class HomeGlobeModelCache {
    static let shared = HomeGlobeModelCache()

    private var model: ModelEntity?
    private var loading: AnyCancellable?
    private var waiting: [(ModelEntity) -> Void] = []

    func preload() {
        load { _ in }
    }

    func load(_ completion: @escaping (ModelEntity) -> Void) {
        if let model {
            completion(model)
            return
        }
        waiting.append(completion)
        guard loading == nil else { return }
        loading = Entity.loadModelAsync(named: "SproutlyHomeGlobe")
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] _ in
                    self?.loading = nil
                    self?.waiting.removeAll()
                },
                receiveValue: { [weak self] entity in
                    guard let self else { return }
                    self.model = entity
                    let callbacks = self.waiting
                    self.waiting.removeAll()
                    callbacks.forEach { $0(entity) }
                }
            )
    }
}

enum HomeGlobeEntrance: Int, CaseIterable {
    case music, ar, profile

    // Surface points are calibrated from the visible objects in the new model.
    // They drive hit testing independently of the bottom bar's camera framing.
    var sourcePosition: SIMD3<Float> {
        switch self {
        case .music: SIMD3(-1.69, 1.38, -0.02)
        case .ar: SIMD3(1.65, 1.10, 0.58)
        case .profile: SIMD3(-0.43, -0.45, 2.28)
        }
    }

    private static let modelCenter = SIMD3<Float>(0.052, -0.092, 0.015)

    var direction: SIMD3<Float> {
        simd_normalize(sourcePosition - Self.modelCenter)
    }

    // Preserve the model's original framing pivots separately from its hit spots.
    private var framingDirection: SIMD3<Float> {
        let pivot: SIMD3<Float>
        switch self {
        case .music: pivot = SIMD3(-1.55, 0.91, 0.26)
        case .ar: pivot = SIMD3(1.65, 1.10, 0.58)
        case .profile: pivot = SIMD3(-0.43, -0.34, 1.85)
        }
        return simd_normalize(pivot - Self.modelCenter)
    }

    // Screen-space framing calibrated against the three supplied target/current
    // image pairs; the cottage needs its actual body rather than the old edge.
    private var focusedDirection: SIMD3<Float> {
        switch self {
        case .music: simd_normalize(SIMD3(0.08, 0.18, 0.98))
        case .ar: simd_normalize(SIMD3(0, 0.53, 0.85))
        case .profile: simd_normalize(SIMD3(0, 0.22, 0.98))
        }
    }

    var focusRotation: simd_quatf {
        let facing = simd_quatf(from: framingDirection, to: focusedDirection)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let localUp = simd_normalize(worldUp - framingDirection * simd_dot(worldUp, framingDirection))
        let rotatedUp = facing.act(localUp)
        let screenUp = simd_normalize(worldUp - focusedDirection * simd_dot(worldUp, focusedDirection))
        let roll = atan2(
            simd_dot(simd_cross(rotatedUp, screenUp), focusedDirection),
            simd_dot(rotatedUp, screenUp)
        )
        return simd_normalize(simd_quatf(angle: roll, axis: focusedDirection) * facing)
    }

    var hitBox: SIMD3<Float> {
        switch self {
        case .music: SIMD3(0.56, 0.55, 0.18)
        case .ar: SIMD3(0.72, 0.64, 0.20)
        case .profile: SIMD3(0.48, 0.90, 0.18)
        }
    }

    var surfaceOrientation: simd_quatf {
        let forward = direction
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), forward))
        let up = simd_cross(forward, right)
        return simd_quatf(simd_float3x3(columns: (right, up, forward)))
    }
}

@MainActor
final class HomeGlobeInteraction {
    private weak var view: ARView?
    private var markers: [HomeGlobeEntrance: Entity] = [:]
    private var glows: [HomeGlobeEntrance: ModelEntity] = [:]
    private var showsEntranceHints = false

    private static let glowTexture: TextureResource? = {
        let size = CGSize(width: 128, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let colors = [
                UIColor.white.withAlphaComponent(0.9).cgColor,
                UIColor.white.withAlphaComponent(0.8).cgColor,
                UIColor.white.withAlphaComponent(0.44).cgColor,
                UIColor.white.withAlphaComponent(0.16).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor
            ] as CFArray
            let stops: [CGFloat] = [0, 0.24, 0.53, 0.77, 1]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: stops
            ) else { return }
            renderer.cgContext.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: size.width / 2,
                options: []
            )

            let context = renderer.cgContext
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.75).cgColor)
            context.setLineWidth(2.5)
            context.strokeEllipse(in: CGRect(x: 21, y: 21, width: 86, height: 86))

            let badge = CGRect(x: 32, y: 32, width: 64, height: 64)
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: 6,
                color: UIColor(red: 0.04, green: 0.25, blue: 0.20, alpha: 0.48).cgColor
            )
            context.setFillColor(UIColor(red: 0.08, green: 0.34, blue: 0.28, alpha: 0.82).cgColor)
            context.fillEllipse(in: badge)
            context.restoreGState()
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(4)
            context.strokeEllipse(in: badge.insetBy(dx: 2, dy: 2))
            UIImage(
                systemName: "hand.tap.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)
            )?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 49, y: 49, width: 30, height: 30))
        }
        guard let image = image.cgImage else { return nil }
        return try? TextureResource.generate(
            from: image,
            withName: "home-entrance-glow",
            options: .init(semantic: .color, mipmapsMode: .none)
        )
    }()

    func attach(to view: ARView, anchor: Entity, modelScale: Float, center: SIMD3<Float>) {
        self.view = view
        markers.removeAll()
        glows.removeAll()
        let originalCenter = SIMD3<Float>(0.052, -0.092, 0.015)

        for entrance in HomeGlobeEntrance.allCases {
            let marker = Entity()
            let relative = entrance.sourcePosition - originalCenter
            let surface = originalCenter + simd_normalize(relative) * max(simd_length(relative), 2.28)
            marker.position = surface * modelScale - center
            marker.orientation = entrance.surfaceOrientation
            marker.components.set(CollisionComponent(shapes: [.generateBox(size: entrance.hitBox)]))

            if let texture = Self.glowTexture {
                var material = UnlitMaterial()
                material.color = .init(tint: .white, texture: .init(texture))
                material.blending = .transparent(opacity: .init(scale: 1))
                let glow = ModelEntity(
                    mesh: .generatePlane(width: 0.26, height: 0.26),
                    materials: [material]
                )
                // The music flower's raised petals sit in front of its entrance point.
                glow.position.z = entrance == .music ? 0.28 : 0.045
                glow.isEnabled = showsEntranceHints && marker.position(relativeTo: nil).z > 0.08
                marker.addChild(glow)
                glows[entrance] = glow
            }
            anchor.addChild(marker)
            markers[entrance] = marker
        }
    }

    func setEntranceHintsVisible(_ visible: Bool) {
        showsEntranceHints = visible
        for (entrance, glow) in glows {
            glow.isEnabled = visible && (markers[entrance]?.position(relativeTo: nil).z ?? 0) > 0.08
        }
    }

    func updateGlow(at time: TimeInterval) {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let viewWidth = Float(view?.bounds.width ?? 410)
        let sizeCorrection = min(Float(1), 410 / max(viewWidth, 1))
        for entrance in HomeGlobeEntrance.allCases {
            guard let glow = glows[entrance], let marker = markers[entrance] else { continue }
            glow.isEnabled = showsEntranceHints && marker.position(relativeTo: nil).z > 0.08
            let phase = time * (2 * .pi / 2.6) + Double(entrance.rawValue) * 0.6
            let pulse = reduceMotion ? Float(1) : Float(1 + 0.08 * sin(phase))
            let scale = sizeCorrection * pulse
            glow.scale = SIMD3<Float>(repeating: scale)
        }
    }

    func reset() {
        markers.removeAll()
        glows.removeAll()
        view = nil
    }

    func entrance(at point: CGPoint) -> HomeGlobeEntrance? {
        guard let view, view.bounds.height > 0 else { return nil }
        for hit in view.hitTest(point, query: .all) {
            guard let entrance = markers.first(where: { $0.value === hit.entity })?.key,
                  let marker = markers[entrance] else { continue }
            // Markers rotate with the model. A front-facing object is selectable
            // anywhere on screen, even when another destination is centered.
            guard marker.position(relativeTo: nil).z > 0.08 else { continue }
            return entrance
        }

        // A marker can render without being returned by ARView.hitTest. Project
        // its surface-aligned hit area so SwiftUI taps still reach the entrance.
        return markers.compactMap { entrance, marker -> (HomeGlobeEntrance, CGFloat)? in
            let worldPosition = marker.position(relativeTo: nil)
            guard worldPosition.z > 0.08,
                  let center = view.project(worldPosition),
                  let horizontal = view.project(marker.convert(
                    position: SIMD3(entrance.hitBox.x * 0.5, 0, 0), to: nil
                  )),
                  let vertical = view.project(marker.convert(
                    position: SIMD3(0, entrance.hitBox.y * 0.5, 0), to: nil
                  )) else { return nil }

            let xX = horizontal.x - center.x
            let xY = horizontal.y - center.y
            let yX = vertical.x - center.x
            let yY = vertical.y - center.y
            let deltaX = point.x - center.x
            let deltaY = point.y - center.y
            let determinant = xX * yY - xY * yX
            guard abs(determinant) > 0.01 else { return nil }
            let across = (deltaX * yY - deltaY * yX) / determinant
            let down = (xX * deltaY - xY * deltaX) / determinant
            guard abs(across) <= 1, abs(down) <= 1 else { return nil }
            return (entrance, across * across + down * down)
        }
        .min(by: { $0.1 < $1.1 })?.0
    }
}

/// 首页专用的非 AR RealityKit 场景。球体始终由 SwiftUI 手势控制，
/// RealityKit 只负责渲染烘焙后的材质与固定世界光源，旋转由 SwiftUI 手势控制。
struct HomeGlobeView: UIViewRepresentable {
    let rotation: simd_quatf
    let isInteracting: Bool
    let showsEntranceHints: Bool
    let interaction: HomeGlobeInteraction
    let renderHeightScale: Float
    var onReady: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(interaction: interaction, renderHeightScale: renderHeightScale, onReady: onReady)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(
            frame: .zero,
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        view.isOpaque = false
        view.backgroundColor = .clear
        view.environment.background = .color(.clear)
        view.renderOptions.insert(.disableCameraGrain)
        view.renderOptions.insert(.disableMotionBlur)
        context.coordinator.configure(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.update(
            rotation: rotation,
            isInteracting: isInteracting,
            showsEntranceHints: showsEntranceHints,
            renderHeightScale: renderHeightScale
        )
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.stopGlowAnimation()
        coordinator.interaction.reset()
        uiView.scene.anchors.removeAll()
    }

    @MainActor
    final class Coordinator {
        let interaction: HomeGlobeInteraction
        private let onReady: () -> Void
        private let modelAnchor = AnchorEntity(world: .zero)
        // 旋转容器只承载模型，灯光和相机都在 modelAnchor 外部的世界坐标中。
        private let modelRotationAnchor = Entity()
        private var camera: PerspectiveCamera?
        private var renderHeightScale: Float
        private var glowDisplayLink: CADisplayLink?
        private var pendingRotation = simd_quatf()
        private var pendingInteraction = false

        init(
            interaction: HomeGlobeInteraction,
            renderHeightScale: Float,
            onReady: @escaping () -> Void
        ) {
            self.interaction = interaction
            self.renderHeightScale = renderHeightScale
            self.onReady = onReady
        }

        func configure(_ view: ARView) {
            view.scene.addAnchor(modelAnchor)
            modelAnchor.addChild(modelRotationAnchor)

            // 不使用环境贴图：光照由下面固定在世界坐标的灯光提供，
            // 因此用户旋转模型时，光源位置和方向不会跟着模型移动。
            var environment = view.environment
            environment.lighting.resource = nil
            environment.lighting.intensityExponent = 0
            view.environment = environment

            let cameraAnchor = AnchorEntity(world: .zero)
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = adjustedFieldOfView
            camera.look(
                at: SIMD3<Float>(0, 0.02, 0),
                from: SIMD3<Float>(0, 0.02, 3.35),
                relativeTo: nil
            )
            cameraAnchor.addChild(camera)
            view.scene.addAnchor(cameraAnchor)
            self.camera = camera

            let keyAnchor = AnchorEntity(world: .zero)
            let keyLight = DirectionalLight()
            // 柔和方向光固定在世界坐标，不随模型旋转。
            keyLight.light.intensity = 1080
            keyLight.light.color = .init(white: 1, alpha: 1)
            keyLight.look(
                at: .zero,
                from: SIMD3<Float>(-2.2, 3.0, 3.2),
                relativeTo: nil
            )
            keyAnchor.addChild(keyLight)
            view.scene.addAnchor(keyAnchor)

            let fillAnchor = AnchorEntity(world: .zero)
            let fillLight = PointLight()
            fillLight.light.intensity = 210
            fillLight.light.attenuationRadius = 6
            fillLight.position = SIMD3<Float>(2.4, 1.2, 2.1)
            fillAnchor.addChild(fillLight)
            view.scene.addAnchor(fillAnchor)

            // 模型只从磁盘加载一次；每个新 ARView 使用共享资源的独立实体副本。
            HomeGlobeModelCache.shared.load { [weak self, weak view] source in
                guard let self, let view else { return }
                let entity = source.clone(recursive: true)
                self.removeImportedLighting(from: entity)
                self.modelRotationAnchor.addChild(entity)
                // 旧模型最大边长约为 2 个单位；同时把新模型的几何中心
                // 对齐到旋转中心，保证画面、手势与点击共用同一个原点。
                let bounds = entity.visualBounds(relativeTo: self.modelRotationAnchor)
                let longestSide = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
                var scale: Float = 1
                if longestSide.isFinite && longestSide > 0 {
                    scale = 2 / longestSide
                    entity.scale *= SIMD3<Float>(repeating: scale)
                }
                let center = entity.visualBounds(relativeTo: self.modelRotationAnchor).center
                entity.position -= center
                self.interaction.attach(
                    to: view,
                    anchor: self.modelRotationAnchor,
                    modelScale: scale,
                    center: center
                )
                self.startGlowAnimation()
                self.apply(
                    rotation: self.pendingRotation,
                    isInteracting: self.pendingInteraction,
                    animated: false
                )
                self.onReady()
            }
        }

        func update(
            rotation: simd_quatf,
            isInteracting: Bool,
            showsEntranceHints: Bool,
            renderHeightScale: Float
        ) {
            pendingRotation = rotation
            pendingInteraction = isInteracting
            if self.renderHeightScale != renderHeightScale {
                self.renderHeightScale = renderHeightScale
                camera?.camera.fieldOfViewInDegrees = adjustedFieldOfView
            }
            interaction.setEntranceHintsVisible(showsEntranceHints)
            apply(
                rotation: rotation,
                isInteracting: isInteracting,
                animated: !isInteracting
            )
        }

        private var adjustedFieldOfView: Float {
            let halfAngle = Float(35) * .pi / 360
            return 2 * atan(renderHeightScale * tan(halfAngle)) * 180 / .pi
        }

        private func startGlowAnimation() {
            guard glowDisplayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(animateGlow(_:)))
            link.preferredFramesPerSecond = 24
            link.add(to: .main, forMode: .common)
            glowDisplayLink = link
        }

        func stopGlowAnimation() {
            glowDisplayLink?.invalidate()
            glowDisplayLink = nil
        }

        @objc private func animateGlow(_ link: CADisplayLink) {
            interaction.updateGlow(at: link.timestamp)
        }

        private func apply(
            rotation: simd_quatf,
            isInteracting: Bool,
            animated: Bool
        ) {
            var transform = modelRotationAnchor.transform
            transform.rotation = simd_normalize(rotation)

            if animated {
                modelRotationAnchor.move(
                    to: transform,
                    relativeTo: modelRotationAnchor.parent,
                    duration: 0.46,
                    timingFunction: .easeInOut
                )
            } else {
                modelRotationAnchor.transform = transform
            }
        }

        /// 部分 DCC 导出的 USDZ 会把灯光和环境光一起打包进场景。
        /// 这些灯光必须移除，否则拖动模型时它们会跟着旋转，造成光源位置变化。
        private func removeImportedLighting(from entity: Entity) {
            entity.components.remove(DirectionalLightComponent.self)
            entity.components.remove(PointLightComponent.self)
            entity.components.remove(SpotLightComponent.self)
            if #available(iOS 18.0, *) {
                entity.components.remove(ImageBasedLightComponent.self)
                entity.components.remove(EnvironmentLightingConfigurationComponent.self)
            } else {
                // iOS 17 使用兼容名称清理环境光组件。
                entity.components.remove(__ImageBasedLightComponent.self)
            }

            // USDZ 导出的灯光有时会以普通 Entity（例如 Light、env_light）
            // 出现，而不是 RealityKit 的 Light 类型；直接移除这些节点，
            // 避免它们随着模型旋转改变照明方向。
            for child in Array(entity.children) {
                let name = child.name.lowercased()
                if name == "light" || name.contains("light") || name == "env_light" {
                    entity.removeChild(child)
                    continue
                }
                removeImportedLighting(from: child)
            }
        }
    }
}
