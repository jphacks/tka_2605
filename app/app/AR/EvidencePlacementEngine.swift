import Foundation
import RealityKit

/// Placement rules invoked by the ECS System. This entry point also lets tests
/// exercise real Components and Entities without a camera or SceneUpdateContext.
@MainActor
enum EvidencePlacementEngine {
    private struct Candidate {
        let placement: EvidencePlacementComponent
        let transform: simd_float4x4
        let cost: Float
        var center: SIMD3<Float> {
            let p = transform.columns.3
            return SIMD3(p.x, p.y, p.z)
        }
    }

    private struct Request {
        let key: EvidenceKey
        let candidates: [Candidate]
    }

    static func update(
        input: inout EvidenceARInputComponent,
        output: inout EvidenceAROutputComponent,
        evidences: [Entity],
        surfaces: [RecognizedSurfaceComponent],
        deltaTime: TimeInterval
    ) {
        let surfacesByID = Dictionary(uniqueKeysWithValues: surfaces.map { ($0.anchorID, $0) })
        let entities = evidences.sorted {
            let a = $0.components[EvidenceComponent.self]!
            let b = $1.components[EvidenceComponent.self]!
            let aProtected = a.isCollected || a.isPhotographed
            let bProtected = b.isCollected || b.isPhotographed
            if aProtected != bProtected { return aProtected }
            return a.key.id < b.key.id
        }
        for entity in entities {
            guard let evidence = entity.components[EvidenceComponent.self],
                  input.relocationKeys.remove(evidence.key) != nil else { continue }
            guard !evidence.isCollected, !evidence.isPhotographed else { continue }
            var placement = EvidencePlacementComponent()
            placement.prefersNearbySurface = true
            entity.components.set(placement)
            entity.findEntity(named: EvidenceEntityNames.visual)?.isEnabled = false
            input.processedSurfaceRevision = -1
            input.placementElapsed = 1
        }

        var validCenters: [SIMD3<Float>] = []
        for entity in entities {
            guard let evidence = entity.components[EvidenceComponent.self],
                  var placement = entity.components[EvidencePlacementComponent.self] else { continue }
            if let anchorID = placement.anchorID,
               let surface = surfacesByID[anchorID],
               evidence.requiredSurface != nil, surface.classification == evidence.requiredSurface,
               EvidenceARGeometry.fits(evidence.model, at: placement.planePosition, sign: placement.normalSign,
                                       in: surface, heading: placement.surfaceHeading) {
                let transform = EvidenceARGeometry.worldTransform(placement, model: evidence.model, surface: surface)
                let p = transform.columns.3
                let center = SIMD3(p.x, p.y, p.z)
                placement.isValid = validCenters.allSatisfy { simd_distance_squared($0, center) >= 1 }
                if placement.isValid {
                    entity.setTransformMatrix(transform, relativeTo: nil)
                    validCenters.append(center)
                    placement.waitingReason = nil
                }
            } else {
                placement.isValid = false
            }
            if !placement.isValid { placement.anchorID = nil }
            entity.components.set(placement)
            entity.findEntity(named: EvidenceEntityNames.visual)?.isEnabled = placement.isValid
        }

        input.placementElapsed += deltaTime
        let hasMissing = entities.contains { $0.components[EvidencePlacementComponent.self]?.isValid != true }
        // Retry even if ARKit reports no new anchor. Camera position, heading and
        // a preceding failed placement can change the usable candidate positions.
        if hasMissing, input.interactionEnabled, input.trackingNormal,
           input.placementElapsed >= 0.35,
           input.surfaceRevision != input.processedSurfaceRevision || input.placementElapsed >= 1 {
            input.placementElapsed = 0
            input.processedSurfaceRevision = input.surfaceRevision
            search(input: input, entities: entities, surfaces: surfaces)
        }

        output.placedCount = entities.filter { $0.components[EvidencePlacementComponent.self]?.isValid == true }.count
        output.placementFeedback = entities.compactMap { entity in
            guard let evidence = entity.components[EvidenceComponent.self],
                  let placement = entity.components[EvidencePlacementComponent.self], !placement.isValid else { return nil }
            let hasSurface = surfaces.contains { $0.classification == evidence.requiredSurface && evidence.requiredSurface != nil }
            return EvidencePlacementFeedback(key: evidence.key, name: evidence.name, surface: evidence.requiredSurface,
                                             reason: placement.waitingReason ?? (hasSurface ? .area : .surface))
        }
    }

    private static func search(input: EvidenceARInputComponent, entities: [Entity], surfaces: [RecognizedSurfaceComponent]) {
        let camera = input.cameraTransform.columns.3
        let cameraPoint = SIMD3(camera.x, camera.y, camera.z)
        var fixedCenters: [SIMD3<Float>] = []
        var requests: [Request] = []
        var baseline: [EvidenceKey: Candidate] = [:]
        var reasons: [EvidenceKey: EvidencePlacementWaitingReason] = [:]
        for entity in entities {
            guard let evidence = entity.components[EvidenceComponent.self],
                  let placement = entity.components[EvidencePlacementComponent.self] else { continue }
            if placement.isValid && (evidence.isCollected || evidence.isPhotographed || input.photographing) {
                fixedCenters.append(entity.position(relativeTo: nil))
                continue
            }
            var candidates: [Candidate] = []
            if placement.isValid {
                let candidate = Candidate(placement: placement, transform: entity.transformMatrix(relativeTo: nil), cost: 0)
                candidates.append(candidate)
                baseline[evidence.key] = candidate
            }
            let matching = surfaces.filter { evidence.requiredSurface != nil && $0.classification == evidence.requiredSurface }
                .sorted { EvidenceARGeometry.surfaceDistanceSquared(camera: camera, surface: $0)
                    < EvidenceARGeometry.surfaceDistanceSquared(camera: camera, surface: $1) }
            for surface in matching {
                let local = surface.transform.inverse * camera
                let sign = EvidencePlaneOrientation.normalSign(planeTransform: surface.transform, cameraHeight: local.y)
                let localCamera = SIMD2(local.x, local.z)
                for point in EvidenceARGeometry.candidates(in: surface, model: evidence.model, sign: sign, near: localCamera) {
                    let placement = EvidencePlacementComponent(anchorID: surface.anchorID, planePosition: point,
                        normalSign: sign, surfaceHeading: localCamera - point, isValid: true)
                    let transform = EvidenceARGeometry.worldTransform(placement, model: evidence.model, surface: surface)
                    let p = transform.columns.3
                    let center = SIMD3(p.x, p.y, p.z)
                    candidates.append(Candidate(placement: placement, transform: transform,
                                                cost: 1000 + simd_distance_squared(center, cameraPoint)))
                }
            }
            reasons[evidence.key] = matching.isEmpty ? .surface : (candidates.isEmpty ? .area : .spacing)
            requests.append(Request(key: evidence.key, candidates: representativeCandidates(candidates)))
        }

        let assignments = solve(requests: requests, fixedCenters: fixedCenters, baseline: baseline)
        for entity in entities {
            guard let evidence = entity.components[EvidenceComponent.self],
                  reasons[evidence.key] != nil else { continue }
            if let candidate = assignments[evidence.key] {
                entity.setTransformMatrix(candidate.transform, relativeTo: nil)
                entity.components.set(candidate.placement)
                entity.findEntity(named: EvidenceEntityNames.visual)?.isEnabled = true
            } else {
                var placement = entity.components[EvidencePlacementComponent.self] ?? EvidencePlacementComponent()
                placement.isValid = false
                placement.anchorID = nil
                placement.waitingReason = reasons[evidence.key]
                entity.components.set(placement)
                entity.findEntity(named: EvidenceEntityNames.visual)?.isEnabled = false
            }
        }
    }

    private static func representativeCandidates(_ candidates: [Candidate]) -> [Candidate] {
        let ordered = candidates.sorted { $0.cost < $1.cost }
        guard ordered.count > 96 else { return ordered }
        // Preserve nearby choices and sample the full distance range. Keeping
        // only the nearest points can eliminate the alternatives needed for 1m.
        var result = Array(ordered.prefix(48))
        for index in 0..<48 {
            let position = 48 + index * (ordered.count - 49) / 47
            result.append(ordered[position])
        }
        return result
    }

    private static func solve(
        requests: [Request], fixedCenters: [SIMD3<Float>], baseline: [EvidenceKey: Candidate]
    ) -> [EvidenceKey: Candidate] {
        let requests = requests.sorted {
            $0.candidates.count != $1.candidates.count
                ? $0.candidates.count < $1.candidates.count : $0.key.id < $1.key.id
        }
        var best = baseline
        var bestCost = baseline.values.reduce(Float(0)) { $0 + $1.cost }
        var selected: [EvidenceKey: Candidate] = [:]
        var centers = fixedCenters
        var visits = 0
        func search(_ index: Int, cost: Float) {
            visits += 1
            guard visits <= 30_000, selected.count + requests.count - index >= best.count else { return }
            if selected.count + requests.count - index == best.count && cost >= bestCost { return }
            if index == requests.count {
                if selected.count > best.count || (selected.count == best.count && cost < bestCost) {
                    best = selected
                    bestCost = cost
                }
                return
            }
            let request = requests[index]
            for candidate in request.candidates where centers.allSatisfy({ simd_distance_squared($0, candidate.center) >= 1 }) {
                selected[request.key] = candidate
                centers.append(candidate.center)
                search(index + 1, cost: cost + candidate.cost)
                centers.removeLast()
                selected.removeValue(forKey: request.key)
            }
            search(index + 1, cost: cost)
        }
        search(0, cost: 0)
        return best
    }
}
