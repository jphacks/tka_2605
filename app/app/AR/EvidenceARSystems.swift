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
        let evidences = Array(context.entities(matching: Self.evidenceQuery, updatingSystemWhen: .rendering))
        var output = inputEntity.components[EvidenceAROutputComponent.self] ?? EvidenceAROutputComponent()
        EvidencePlacementEngine.update(input: &input, output: &output, evidences: evidences,
                                       surfaces: surfaces, deltaTime: context.deltaTime)
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

