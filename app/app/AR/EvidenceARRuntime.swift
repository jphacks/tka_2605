import ARKit
import AVFoundation
import Combine
import Observation
import OSLog
import RealityKit
import SwiftUI

/// Owns one ARView for the lifetime of the game. Changing its SwiftUI frame must
/// resize this view, rather than constructing a second ARSession.
@Observable
@MainActor
final class EvidenceARRuntime: NSObject {
    private(set) var canCapture = false
    private(set) var isCapturing = false
    private(set) var selectedEvidenceName: String?
    private(set) var statusMessage = "周囲をゆっくり映してください"
    private(set) var placedCount = 0
    private(set) var hasCameraFeed = false

    @ObservationIgnored let arView: ARView
    @ObservationIgnored private let sceneAnchor = AnchorEntity(world: .zero)
    @ObservationIgnored private let inputEntity = Entity()
    @ObservationIgnored private var surfaceEntities: [UUID: Entity] = [:]
    @ObservationIgnored private var evidenceEntities: [EvidenceKey: Entity] = [:]
    @ObservationIgnored private let modelFactory = EvidenceModelFactory()
    @ObservationIgnored private var requestedEvidences: [EvidenceKey: Evidence] = [:]
    @ObservationIgnored private var photographedKeys: Set<EvidenceKey> = []
    @ObservationIgnored private var placementFeedback: [EvidencePlacementFeedback] = []
    @ObservationIgnored private var modelLoadTasks: [EvidenceKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var modelLoadErrors: [EvidenceKey: String] = [:]
    @ObservationIgnored private var lastLoggedSurfaceSummary: String?
    @ObservationIgnored private var sceneSubscription: (any Cancellable)?
    @ObservationIgnored private var gameID: UUID?
    @ObservationIgnored private var evidenceKind: EvidenceKind?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeCapture: EvidenceCaptureRequest?
    @ObservationIgnored private var captureCompletion: ((EvidenceKey, UIImage) -> Void)?
    @ObservationIgnored private var snapshotStarted = false
    @ObservationIgnored private var attached = false
    @ObservationIgnored private var sessionRunning = false
    @ObservationIgnored private var sessionInterrupted = false
    @ObservationIgnored private var needsTrackingReset = true
    @ObservationIgnored private var permissionRequestInProgress = false
    @ObservationIgnored private var unavailableReason: String?
    @ObservationIgnored private var captureError: String?

    private static var systemsRegistered = false
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EvidenceAR", category: "Models")
    private static let surfaceLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EvidenceAR", category: "Surfaces")

    override init() {
        Self.registerSystems()
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        super.init()
        inputEntity.components.set(EvidenceARInputComponent())
        inputEntity.components.set(EvidenceAROutputComponent())
        sceneAnchor.addChild(inputEntity)
        arView.scene.addAnchor(sceneAnchor)
        arView.session.delegate = self
        arView.session.delegateQueue = .main
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
        sceneSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            self?.updateCameraInput()
            self?.consumeSystemOutput()
        }
    }

    func configure(gameID: UUID, evidences: [Evidence], kind: EvidenceKind) {
        let previousKeys = Set(requestedEvidences.keys)
        requestedEvidences = Dictionary(uniqueKeysWithValues: evidences.map {
            (EvidenceKey(kind: kind, id: $0.id), $0)
        })
        if self.gameID != gameID || evidenceKind != kind {
            hasCameraFeed = false
            generation = UUID()
            cancelModelLoads()
            photographedKeys.removeAll()
            placementFeedback.removeAll()
            invalidateCapture()
            for entity in evidenceEntities.values { entity.removeFromParent() }
            for entity in surfaceEntities.values { entity.removeFromParent() }
            evidenceEntities.removeAll()
            surfaceEntities.removeAll()
            lastLoggedSurfaceSummary = nil
            inputEntity.components.set(EvidenceARInputComponent())
            inputEntity.components.set(EvidenceAROutputComponent())
            self.gameID = gameID
            evidenceKind = kind
            needsTrackingReset = true
            sessionInterrupted = false
            captureError = nil
            for evidence in evidences {
                let key = EvidenceKey(kind: kind, id: evidence.id)
                loadModel(evidence: evidence, key: key)
            }
            placedCount = 0
            selectedEvidenceName = nil
            canCapture = false
            if attached { startSessionIfPossible() }
        } else {
            // 調査が進んだら対象Entityだけを差し替え、AR空間と認識面は維持する。
            let requestedKeys = Set(evidences.map { EvidenceKey(kind: kind, id: $0.id) })
            if requestedKeys != previousKeys {
                generation = UUID()
                cancelModelLoads()
                invalidateCapture()
                clearSelection()
                for key in Array(evidenceEntities.keys) where !requestedKeys.contains(key) {
                    evidenceEntities.removeValue(forKey: key)?.removeFromParent()
                }
                for evidence in evidences {
                    let key = EvidenceKey(kind: kind, id: evidence.id)
                    guard evidenceEntities[key] == nil else { continue }
                    loadModel(evidence: evidence, key: key)
                }
                modifyInput {
                    $0.relocationKeys.formIntersection(requestedKeys)
                    $0.surfaceRevision &+= 1
                    $0.processedSurfaceRevision = -1
                    $0.placementElapsed = 1
                }
                placedCount = evidenceEntities.values.filter {
                    $0.components[EvidencePlacementComponent.self]?.isValid == true
                }.count
            }
            // 同じ調査の状態同期では配置を維持し、収集済み表示だけを更新する。
            for evidence in evidences {
                let key = EvidenceKey(kind: kind, id: evidence.id)
                guard let entity = evidenceEntities[key],
                      var component = entity.components[EvidenceComponent.self]
                else { continue }
                component.isCollected = evidence.isCollected
                component.isPhotographed = photographedKeys.contains(key)
                entity.components.set(component)
                entity.findEntity(named: EvidenceModelFactory.collectedName)?.isEnabled = evidence.isCollected
            }
        }
        updateStatus()
    }

    private func cancelModelLoads() {
        for task in modelLoadTasks.values { task.cancel() }
        modelLoadTasks.removeAll()
        modelLoadErrors.removeAll()
    }

    private func loadModel(evidence: Evidence, key: EvidenceKey) {
        let loadGeneration = generation
        let factory = modelFactory
        modelLoadTasks[key] = Task { @MainActor [weak self] in
            do {
                let entity = try await factory.make(evidence: evidence, key: key)
                try Task.checkCancellation()
                guard let self, self.generation == loadGeneration,
                      let current = self.requestedEvidences[key] else { return }
                if var component = entity.components[EvidenceComponent.self] {
                    component.isCollected = current.isCollected
                    component.isPhotographed = self.photographedKeys.contains(key)
                    entity.components.set(component)
                }
                entity.findEntity(named: EvidenceModelFactory.collectedName)?.isEnabled = current.isCollected
                self.evidenceEntities[key] = entity
                self.sceneAnchor.addChild(entity)
                self.modelLoadTasks.removeValue(forKey: key)
                // A plane may have been recognized while this asset was loading.
                self.modifyInput {
                    $0.surfaceRevision &+= 1
                    $0.processedSurfaceRevision = -1
                    $0.placementElapsed = 1
                }
                self.updateStatus()
            } catch {
                guard let self, self.generation == loadGeneration, !Task.isCancelled else { return }
                self.modelLoadTasks.removeValue(forKey: key)
                Self.logger.error("Model loading failed: \(evidence.modelResourceName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                self.modelLoadErrors[key] = evidence.name
                self.updateStatus()
            }
        }
    }

    func setInteractionEnabled(_ enabled: Bool) {
        modifyInput { input in
            if input.interactionEnabled != enabled {
                input.processedSurfaceRevision = -1
            }
            input.interactionEnabled = enabled
        }
        if !enabled {
            invalidateCapture()
            clearSelection()
        } else if attached {
            startSessionIfPossible()
        }
        updateStatus()
    }

    func setPhotographedEvidenceKeys(_ keys: Set<EvidenceKey>) {
        photographedKeys = keys.intersection(requestedEvidences.keys)
        for (key, entity) in evidenceEntities {
            guard var component = entity.components[EvidenceComponent.self] else { continue }
            component.isPhotographed = photographedKeys.contains(key)
            entity.components.set(component)
        }
    }

    func setPhotographing(_ enabled: Bool) {
        let wasPhotographing = inputEntity.components[EvidenceARInputComponent.self]?.photographing == true
        guard wasPhotographing != enabled else { return }
        invalidateCapture()
        clearSelection()
        captureError = nil
        modifyInput { $0.photographing = enabled }
        updateStatus()
    }

    /// Submit a local ECS command. Photos, collected flags, session tracking and
    /// recognized planes are retained; only requested uncollected placements reset.
    @discardableResult
    func relocateUnacquiredEvidence(keys: Set<EvidenceKey>) -> Bool {
        guard !isCapturing,
              let input = inputEntity.components[EvidenceARInputComponent.self],
              input.interactionEnabled, !input.photographing else { return false }
        let targets = keys.filter {
            requestedEvidences[$0]?.isCollected == false && !photographedKeys.contains($0)
        }
        guard !targets.isEmpty else { return false }
        invalidateCapture()
        clearSelection()
        captureError = nil
        // A failed import has no Entity for the placement System to reset.
        // Explicit relocation must retry that import as well as clear placement.
        for key in targets where evidenceEntities[key] == nil && modelLoadTasks[key] == nil {
            guard let evidence = requestedEvidences[key] else { continue }
            modelLoadErrors.removeValue(forKey: key)
            loadModel(evidence: evidence, key: key)
        }
        modifyInput {
            $0.relocationKeys.formUnion(targets)
            $0.processedSurfaceRevision = -1
            $0.placementElapsed = 1
        }
        updateStatus()
        return true
    }

    func capturePhoto(completion: @escaping (EvidenceKey, UIImage) -> Void) {
        guard canCapture, !isCapturing,
              let output = inputEntity.components[EvidenceAROutputComponent.self],
              let key = output.selectedKey
        else { return }
        let request = EvidenceCaptureRequest(id: UUID(), key: key)
        captureCompletion = completion
        activeCapture = request
        snapshotStarted = false
        isCapturing = true
        canCapture = false
        captureError = nil
        // Acceptance is decided by EvidenceCaptureSystem using the latest scene input.
        modifyInput { $0.captureRequest = request }
        updateStatus()
    }

    fileprivate func attach() {
        attached = true
        startSessionIfPossible()
    }

    fileprivate func detach() {
        attached = false
        hasCameraFeed = false
        invalidateCapture()
        clearSelection()
        modifyInput { $0.trackingNormal = false }
        arView.session.pause()
        sessionRunning = false
    }

    private static func registerSystems() {
        guard !systemsRegistered else { return }
        systemsRegistered = true
        EvidenceComponent.registerComponent()
        EvidencePlacementComponent.registerComponent()
        RecognizedSurfaceComponent.registerComponent()
        EvidenceARInputComponent.registerComponent()
        EvidenceAROutputComponent.registerComponent()
        EvidencePlacementSystem.registerSystem()
        EvidenceSelectionSystem.registerSystem()
        EvidenceCaptureSystem.registerSystem()
    }

    private func startSessionIfPossible() {
        guard attached, gameID != nil,
              inputEntity.components[EvidenceARInputComponent.self]?.interactionEnabled == true else { return }
        guard ARWorldTrackingConfiguration.isSupported else {
            unavailableReason = "この端末はARの空間認識に対応していません"
            updateStatus()
            return
        }
        guard ARPlaneAnchor.isClassificationSupported else {
            unavailableReason = "この端末は面の分類に対応していないため、証拠を配置できません"
            updateStatus()
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            unavailableReason = nil
            guard !sessionRunning || needsTrackingReset else { return }
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            let options: ARSession.RunOptions = needsTrackingReset ? [.resetTracking, .removeExistingAnchors] : []
            arView.session.run(configuration, options: options)
            needsTrackingReset = false
            sessionRunning = true
        case .notDetermined:
            guard !permissionRequestInProgress else { return }
            permissionRequestInProgress = true
            unavailableReason = "ARを使うためにカメラへのアクセスを許可してください"
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                guard let runtime = self else { return }
                Task { @MainActor [runtime] in
                    runtime.permissionRequestInProgress = false
                    runtime.startSessionIfPossible()
                }
            }
        case .denied, .restricted:
            unavailableReason = "カメラを使用できません。設定でカメラへのアクセスを確認してください"
        @unknown default:
            unavailableReason = "カメラの状態を確認できません"
        }
        updateStatus()
    }

    private func updateCameraInput() {
        guard attached else { return }
        guard sessionRunning, let frame = arView.session.currentFrame else {
            hasCameraFeed = false
            modifyInput { $0.trackingNormal = false }
            return
        }
        hasCameraFeed = !sessionInterrupted
            && ProcessInfo.processInfo.systemUptime - frame.timestamp < 0.5
        let orientation = arView.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        let viewRotationAngle: CGFloat
        switch orientation {
        case .landscapeRight: viewRotationAngle = 0
        case .portrait: viewRotationAngle = 90
        case .landscapeLeft: viewRotationAngle = 180
        case .portraitUpsideDown: viewRotationAngle = 270
        default: viewRotationAngle = 90
        }
        let size = arView.bounds.size
        let trackingNormal: Bool
        if case .normal = frame.camera.trackingState {
            trackingNormal = !sessionInterrupted
                && ProcessInfo.processInfo.systemUptime - frame.timestamp < 0.5
        } else {
            trackingNormal = false
        }
        modifyInput { input in
            input.cameraTransform = frame.camera.transform
            input.trackingNormal = trackingNormal
            input.viewportSize = size
            if size.width > 0, size.height > 0 {
                input.viewProjection = frame.camera.projectionMatrix(
                    viewRotationAngle: viewRotationAngle,
                    viewportSize: size,
                    zNear: 0.001,
                    zFar: 100
                ) * frame.camera.viewMatrix(viewRotationAngle: viewRotationAngle)
            }
        }
    }

    @objc private func didTap(_ recognizer: UITapGestureRecognizer) {
        guard !isCapturing,
              let ray = arView.ray(through: recognizer.location(in: arView))
        else { return }
        captureError = nil
        modifyInput { $0.tapRay = ray }
    }

    private func consumeSystemOutput() {
        guard var output = inputEntity.components[EvidenceAROutputComponent.self] else { return }
        placedCount = output.placedCount
        placementFeedback = output.placementFeedback
        selectedEvidenceName = output.selectedName
        canCapture = output.canCapture && !isCapturing
        if let decision = output.captureDecision {
            output.captureDecision = nil
            inputEntity.components.set(output)
            switch decision {
            case .approved(let request):
                beginSnapshot(request)
            case .rejected(let token):
                if activeCapture?.id == token {
                    invalidateCapture()
                    clearSelection()
                    captureError = "撮影条件から外れました。証拠をもう一度タップしてください"
                }
            }
        }
        updateStatus()
    }

    private func beginSnapshot(_ request: EvidenceCaptureRequest) {
        guard activeCapture?.id == request.id, !snapshotStarted else { return }
        snapshotStarted = true
        let captureGeneration = generation
        arView.snapshot(saveToHDR: false) { [weak self] image in
            guard let self,
                  self.generation == captureGeneration,
                  self.activeCapture?.id == request.id
            else { return }
            let input = self.inputEntity.components[EvidenceARInputComponent.self]
            let output = self.inputEntity.components[EvidenceAROutputComponent.self]
            guard input?.interactionEnabled == true,
                  input?.photographing == true,
                  input?.trackingNormal == true,
                  output?.selectedKey == request.key,
                  output?.canCapture == true,
                  let image,
                  let square = self.squareImage(image)
            else {
                self.invalidateCapture()
                self.clearSelection()
                self.captureError = "撮影できませんでした。証拠をもう一度タップしてください"
                self.updateStatus()
                return
            }
            let completion = self.captureCompletion
            self.invalidateCapture()
            self.clearSelection()
            // Only a complete AR snapshot reaches the photo store / collection action.
            completion?(request.key, square)
        }
    }

    private func squareImage(_ image: UIImage) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        // Preserve snapshot pixels instead of expanding a scale-1 image to device scale.
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        guard let cgImage = normalized.cgImage else { return nil }
        let side = min(cgImage.width, cgImage.height)
        let rect = CGRect(x: (cgImage.width - side) / 2, y: (cgImage.height - side) / 2, width: side, height: side)
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: normalized.scale, orientation: .up)
    }

    private func invalidateCapture() {
        activeCapture = nil
        captureCompletion = nil
        snapshotStarted = false
        isCapturing = false
        modifyInput { $0.captureRequest = nil }
        if var output = inputEntity.components[EvidenceAROutputComponent.self] {
            output.captureDecision = nil
            inputEntity.components.set(output)
        }
    }

    private func clearSelection() {
        canCapture = false
        selectedEvidenceName = nil
        modifyInput { $0.tapRay = nil }
        if var output = inputEntity.components[EvidenceAROutputComponent.self] {
            output.selectedKey = nil
            output.selectedName = nil
            output.canCapture = false
            inputEntity.components.set(output)
        }
    }

    private func modifyInput(_ action: (inout EvidenceARInputComponent) -> Void) {
        guard var input = inputEntity.components[EvidenceARInputComponent.self] else { return }
        action(&input)
        inputEntity.components.set(input)
    }

    private func updateStatus() {
        if let unavailableReason { statusMessage = unavailableReason; return }
        if let captureError { statusMessage = captureError; return }
        let input = inputEntity.components[EvidenceARInputComponent.self]
        guard input?.interactionEnabled == true else { statusMessage = "操作を一時停止しています"; return }
        if isCapturing { statusMessage = "撮影しています"; return }
        if let error = modelLoadErrors.sorted(by: { $0.key.id < $1.key.id }).first?.value {
            statusMessage = "「\(error)」のモデルを読み込めませんでした"
            return
        }
        if !modelLoadTasks.isEmpty {
            statusMessage = "証拠モデルを読み込んでいます"
            return
        }
        if input?.trackingNormal != true { statusMessage = "周囲をゆっくり映して空間認識を待ってください"; return }
        if evidenceEntities.values.contains(where: { $0.components[EvidenceComponent.self]?.requiredSurface == nil }) {
            statusMessage = "このエピソードには対応していない配置条件が含まれています"
        } else if let name = selectedEvidenceName {
            statusMessage = "「\(name)」を撮影できます"
        } else if input?.photographing == true {
            statusMessage = "証拠の30cm以内まで近づき、画面内の証拠をタップしてください"
        } else if placedCount < evidenceEntities.count {
            let messages = placementFeedback.map(\.message)
            statusMessage = messages.isEmpty
                ? "指定の面と1mの間隔を確認中です。周囲をゆっくり映してください"
                : messages.joined(separator: "\n")
        } else {
            statusMessage = "証拠を\(placedCount)件設置しています。周囲を見渡して探してください"
        }
    }

    private func receiveSurfaces(_ anchors: [ARAnchor]) {
        for case let plane as ARPlaneAnchor in anchors {
            let surface = surfaceEntities[plane.identifier] ?? Entity()
            surface.components.set(RecognizedSurfaceComponent(
                anchorID: plane.identifier,
                classification: EvidenceSurfaceClassification(plane.classification),
                transform: plane.transform,
                boundary: plane.geometry.boundaryVertices.map { SIMD2($0.x, $0.z) }
            ))
            if surfaceEntities[plane.identifier] == nil {
                surfaceEntities[plane.identifier] = surface
                sceneAnchor.addChild(surface)
            }
        }
        logSurfaceClassificationsIfChanged()
        modifyInput { $0.surfaceRevision &+= 1 }
    }

    /// Surface recognition can stall before placement ever runs. Log ARKit's
    /// actual classifications without changing or substituting the required class.
    private func logSurfaceClassificationsIfChanged() {
        var counts = ["window": 0]
        for entity in surfaceEntities.values {
            let classification = entity.components[RecognizedSurfaceComponent.self]?.classification
            counts[classification?.rawValue ?? "unclassified", default: 0] += 1
        }
        let summary = counts.keys.sorted().map { "\($0)=\(counts[$0]!)" }.joined(separator: ", ")
        guard summary != lastLoggedSurfaceSummary else { return }
        lastLoggedSurfaceSummary = summary
        Self.surfaceLogger.info("AR plane classifications: \(summary, privacy: .public)")
    }
}

// This delegate is delivered on session.delegateQueue = .main. The conformance
// preserves that SDK callback boundary while keeping scene changes on MainActor.
extension EvidenceARRuntime: @preconcurrency ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        receiveSurfaces(anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        receiveSurfaces(anchors)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            surfaceEntities.removeValue(forKey: anchor.identifier)?.removeFromParent()
        }
        logSurfaceClassificationsIfChanged()
        modifyInput { $0.surfaceRevision &+= 1 }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        sessionInterrupted = true
        hasCameraFeed = false
        invalidateCapture()
        clearSelection()
        modifyInput { $0.trackingNormal = false }
        updateStatus()
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        sessionInterrupted = false
        // Keep anchors, but wait for a fresh normal tracking frame before selection.
        modifyInput { $0.trackingNormal = false }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        hasCameraFeed = false
        invalidateCapture()
        clearSelection()
        modifyInput { $0.trackingNormal = false }
        sessionRunning = false
        unavailableReason = "ARを続けられません: \(error.localizedDescription)"
        updateStatus()
    }
}

struct EvidenceARView: UIViewRepresentable {
    let runtime: EvidenceARRuntime

    func makeCoordinator() -> Coordinator { Coordinator(runtime: runtime) }

    func makeUIView(context: Context) -> ARView {
        runtime.attach()
        return runtime.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.runtime.detach()
    }

    @MainActor
    final class Coordinator {
        let runtime: EvidenceARRuntime
        init(runtime: EvidenceARRuntime) { self.runtime = runtime }
    }
}
