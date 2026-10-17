import ARKit
import AVFoundation
import Combine
import Observation
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

    @ObservationIgnored let arView: ARView
    @ObservationIgnored private let sceneAnchor = AnchorEntity(world: .zero)
    @ObservationIgnored private let inputEntity = Entity()
    @ObservationIgnored private var surfaceEntities: [UUID: Entity] = [:]
    @ObservationIgnored private var evidenceEntities: [EvidenceKey: Entity] = [:]
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
        if self.gameID != gameID || evidenceKind != kind {
            generation = UUID()
            invalidateCapture()
            for entity in evidenceEntities.values { entity.removeFromParent() }
            for entity in surfaceEntities.values { entity.removeFromParent() }
            evidenceEntities.removeAll()
            surfaceEntities.removeAll()
            inputEntity.components.set(EvidenceARInputComponent())
            inputEntity.components.set(EvidenceAROutputComponent())
            self.gameID = gameID
            evidenceKind = kind
            needsTrackingReset = true
            sessionInterrupted = false
            captureError = nil
            for evidence in evidences {
                let key = EvidenceKey(kind: kind, id: evidence.id)
                let entity = EvidenceModelFactory.make(evidence: evidence, key: key)
                evidenceEntities[key] = entity
                sceneAnchor.addChild(entity)
            }
            placedCount = 0
            selectedEvidenceName = nil
            canCapture = false
            if attached { startSessionIfPossible() }
        } else {
            // Snapshots change collection flags without resetting local anchors or photos.
            for evidence in evidences {
                let key = EvidenceKey(kind: kind, id: evidence.id)
                guard let entity = evidenceEntities[key],
                      var component = entity.components[EvidenceComponent.self]
                else { continue }
                component.isCollected = evidence.isCollected
                entity.components.set(component)
                entity.findEntity(named: EvidenceModelFactory.collectedName)?.isEnabled = evidence.isCollected
            }
        }
        updateStatus()
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

    func setPhotographing(_ enabled: Bool) {
        let wasPhotographing = inputEntity.components[EvidenceARInputComponent.self]?.photographing == true
        guard wasPhotographing != enabled else { return }
        invalidateCapture()
        clearSelection()
        captureError = nil
        modifyInput { $0.photographing = enabled }
        updateStatus()
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
            modifyInput { $0.trackingNormal = false }
            return
        }
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
        if input?.trackingNormal != true { statusMessage = "周囲をゆっくり映して空間認識を待ってください"; return }
        if evidenceEntities.values.contains(where: { $0.components[EvidenceComponent.self]?.requiredSurface == nil }) {
            statusMessage = "このエピソードには対応していない配置条件が含まれています"
        } else if let name = selectedEvidenceName {
            statusMessage = "「\(name)」を撮影できます"
        } else if input?.photographing == true {
            statusMessage = "証拠の30cm以内まで近づき、画面内の証拠をタップしてください"
        } else if placedCount < evidenceEntities.count {
            statusMessage = "指定の面と1mの間隔を確認中です。周囲をゆっくり映してください"
        } else {
            statusMessage = "証拠を見つけたら撮影を開始してください"
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
        modifyInput { $0.surfaceRevision &+= 1 }
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
        modifyInput { $0.surfaceRevision &+= 1 }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        sessionInterrupted = true
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
