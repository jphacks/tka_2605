import ARKit
import RealityKit

/// ARKit and UIKit only supply input. Placement rules live in this System.
nonisolated final class EvidencePlacementSystem: System {
    private static let inputQuery = EntityQuery(where: .has(EvidenceARInputComponent.self))
    private static let evidenceQuery = EntityQuery(where: .has(EvidenceComponent.self))
    private static let surfaceQuery = EntityQuery(where: .has(RecognizedSurfaceComponent.self))

    @MainActor required init(scene: Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        guard let inputEntity = context.entities(matching: Self.inputQuery, updatingSystemWhen: .rendering).first(where: { _ in true }),
              var input = inputEntity.components[EvidenceARInputComponent.self]
        else { return }

        let surfaces = context.entities(matching: Self.surfaceQuery, updatingSystemWhen: .rendering)
            .compactMap { $0.components[RecognizedSurfaceComponent.self] }
        let surfacesByID = Dictionary(uniqueKeysWithValues: surfaces.map { ($0.anchorID, $0) })
        let evidences = Array(context.entities(matching: Self.evidenceQuery, updatingSystemWhen: .rendering))
            .sorted { ($0.components[EvidenceComponent.self]?.key.id ?? 0) < ($1.components[EvidenceComponent.self]?.key.id ?? 0) }
        var centers: [SIMD3<Float>] = []

        // Requests may arrive before an async model load finishes. Keep those
        // keys queued, and recheck collection after the latest state sync.
        for entity in evidences {
            guard let evidence = entity.components[EvidenceComponent.self],
                  input.relocationKeys.remove(evidence.key) != nil else { continue }
            guard !evidence.isCollected else { continue }
            var placement = EvidencePlacementComponent()
            placement.prefersNearbySurface = true
            entity.components.set(placement)
            entity.findEntity(named: EvidenceModelFactory.visualName)?.isEnabled = false
            input.processedSurfaceRevision = -1
            input.placementElapsed = 1
        }

        // Plane refinement/removal can invalidate an old placement. Validate immediately,
        // including collected evidence, before selection/capture can run this frame.
        for entity in evidences {
            guard let evidence = entity.components[EvidenceComponent.self],
                  var placement = entity.components[EvidencePlacementComponent.self]
            else { continue }
            if let anchorID = placement.anchorID,
               let surface = surfacesByID[anchorID],
               surface.classification == evidence.requiredSurface,
               evidence.requiredSurface != nil,
               EvidenceARGeometry.fits(evidence.model, at: placement.planePosition, sign: placement.normalSign,
                                       in: surface, heading: placement.surfaceHeading) {
                let transform = EvidenceARGeometry.worldTransform(placement, model: evidence.model, surface: surface)
                let center = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                placement.isValid = centers.allSatisfy { simd_distance($0, center) >= 1 }
                if placement.isValid {
                    entity.setTransformMatrix(transform, relativeTo: nil)
                    centers.append(center)
                }
            } else {
                placement.isValid = false
            }
            if !placement.isValid { placement.anchorID = nil }
            entity.components.set(placement)
            entity.findEntity(named: EvidenceModelFactory.visualName)?.isEnabled = placement.isValid
        }

        input.placementElapsed += context.deltaTime
        if input.interactionEnabled, input.trackingNormal,
           input.surfaceRevision != input.processedSurfaceRevision,
           input.placementElapsed >= 0.35 {
            input.placementElapsed = 0
            input.processedSurfaceRevision = input.surfaceRevision
            for entity in evidences {
                guard let evidence = entity.components[EvidenceComponent.self],
                      entity.components[EvidencePlacementComponent.self]?.isValid != true,
                      let requiredSurface = evidence.requiredSurface
                else { continue }

                var didPlace = false
                var matchingSurfaces = surfaces.filter { $0.classification == requiredSurface }
                if entity.components[EvidencePlacementComponent.self]?.prefersNearbySurface == true {
                    let camera = input.cameraTransform.columns.3
                    matchingSurfaces.sort {
                        EvidenceARGeometry.surfaceDistanceSquared(camera: camera, surface: $0)
                            < EvidenceARGeometry.surfaceDistanceSquared(camera: camera, surface: $1)
                    }
                }
                for surface in matchingSurfaces {
                    let localCamera = surface.transform.inverse * input.cameraTransform.columns.3
                    let sign = EvidencePlaneOrientation.normalSign(planeTransform: surface.transform, cameraHeight: localCamera.y)
                    for point in EvidenceARGeometry.candidates(
                        in: surface,
                        model: evidence.model,
                        sign: sign,
                        near: SIMD2(localCamera.x, localCamera.z)
                    ) {
                        let heading = SIMD2(localCamera.x, localCamera.z) - point
                        guard EvidenceARGeometry.fits(evidence.model, at: point, sign: sign, in: surface, heading: heading)
                        else { continue }
                        let placement = EvidencePlacementComponent(
                            anchorID: surface.anchorID,
                            planePosition: point,
                            normalSign: sign,
                            surfaceHeading: heading,
                            isValid: true
                        )
                        let transform = EvidenceARGeometry.worldTransform(placement, model: evidence.model, surface: surface)
                        let center = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                        guard centers.allSatisfy({ simd_distance($0, center) >= 1 }) else { continue }
                        entity.setTransformMatrix(transform, relativeTo: nil)
                        entity.components.set(placement)
                        entity.findEntity(named: EvidenceModelFactory.visualName)?.isEnabled = true
                        centers.append(center)
                        didPlace = true
                        break
                    }
                    if didPlace { break }
                }
            }
        }

        var output = inputEntity.components[EvidenceAROutputComponent.self] ?? EvidenceAROutputComponent()
        output.placedCount = centers.count
        inputEntity.components.set(input)
        inputEntity.components.set(output)
    }
}

nonisolated final class EvidenceSelectionSystem: System {
    static let dependencies: [SystemDependency] = [.after(EvidencePlacementSystem.self)]
    private static let inputQuery = EntityQuery(where: .has(EvidenceARInputComponent.self))
    private static let evidenceQuery = EntityQuery(where: .has(EvidenceComponent.self))

    @MainActor required init(scene: Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        guard let inputEntity = context.entities(matching: Self.inputQuery, updatingSystemWhen: .rendering).first(where: { _ in true }),
              var input = inputEntity.components[EvidenceARInputComponent.self]
        else { return }
        var output = inputEntity.components[EvidenceAROutputComponent.self] ?? EvidenceAROutputComponent()
        let evidences = Array(context.entities(matching: Self.evidenceQuery, updatingSystemWhen: .rendering))

        if let tap = input.tapRay {
            // Resolve the closest model body in ECS, never a label or a SwiftUI control.
            input.tapRay = nil
            output.selectedKey = nil
            output.selectedName = nil
            if input.interactionEnabled, input.photographing, input.trackingNormal {
                let hits = evidences.compactMap { entity -> (Entity, Float)? in
                    guard let distance = EvidenceARGeometry.hitDistance(entity, origin: tap.origin, direction: tap.direction)
                    else { return nil }
                    return (entity, distance)
                }
                if let (target, _) = hits.min(by: { $0.1 < $1.1 }),
                   EvidenceARGeometry.canCapture(target, input: input) {
                    let evidence = target.components[EvidenceComponent.self]
                    output.selectedKey = evidence?.key
                    output.selectedName = evidence?.name
                }
            }
        }

        let selected = evidences.first { $0.components[EvidenceComponent.self]?.key == output.selectedKey }
        output.canCapture = selected.map { EvidenceARGeometry.canCapture($0, input: input) } ?? false
        if !output.canCapture {
            output.selectedKey = nil
            output.selectedName = nil
        }
        inputEntity.components.set(input)
        inputEntity.components.set(output)
    }
}

nonisolated final class EvidenceCaptureSystem: System {
    static let dependencies: [SystemDependency] = [.after(EvidenceSelectionSystem.self)]
    private static let inputQuery = EntityQuery(where: .has(EvidenceARInputComponent.self))
    private static let evidenceQuery = EntityQuery(where: .has(EvidenceComponent.self))

    @MainActor required init(scene: Scene) {}

    @MainActor func update(context: SceneUpdateContext) {
        guard let inputEntity = context.entities(matching: Self.inputQuery, updatingSystemWhen: .rendering).first(where: { _ in true }),
              var input = inputEntity.components[EvidenceARInputComponent.self],
              let request = input.captureRequest
        else { return }
        input.captureRequest = nil
        var output = inputEntity.components[EvidenceAROutputComponent.self] ?? EvidenceAROutputComponent()
        let selected = context.entities(matching: Self.evidenceQuery, updatingSystemWhen: .rendering)
            .first { $0.components[EvidenceComponent.self]?.key == request.key }
        if output.selectedKey == request.key,
           let selected,
           EvidenceARGeometry.canCapture(selected, input: input) {
            output.captureDecision = .approved(request)
        } else {
            output.captureDecision = .rejected(request.id)
        }
        inputEntity.components.set(input)
        inputEntity.components.set(output)
    }
}

