Run the game rules tests on macOS with Xcode's Swift toolchain:

```sh
bash tests/run-game-rules.sh
```

The runner builds a temporary Swift package in `/private/tmp`, using the actual
application models, GameManager, EpisodeManager, PlayerManager, ScreenManager,
JSON loader, API classes and GameMessage. Only Playgrounds are excluded. Fixtures
avoid evaluating the APIs' lazy bundle JSON. A fake PeerManager records transport
messages; AppKit's NSImage supplies the UIImage type for photo storage tests.
The actual EvidencePlaneOrientation helper is compiled with simd, without
requiring an AR session. Props and sheets are checked against camera headings,
anchor yaw, support offsets and cameras below a table.

The tests cover game rules, snapshot acknowledgements, pending operation replay,
duplicate requests, ending attempts, stale snapshots and local photo retention.
Orientation regression tests cover 1,344 combinations of wall/sloped/horizontal
planes, yaw, in-plane rotation and visible face, checking upright text, matching
surface normals, orthonormality, handedness and the horizontal tangent fallback.
They do not exercise MultipeerConnectivity's discovery or real network delivery.
No Xcode project changes or external dependencies are required. The temporary
directory is kept for inspecting build failures. Swift test options can be passed
to the runner, for example `--filter GameManagerTests.testUnconfirmedCollection`.

The harness also copies the current `app/Data/*.json` as test resources. The
catalog tests decode the updated schema, resolve its references, exercise all
three investigation stages, and verify photo/state preservation across a stage
advance and reconnect. There are 73 tests in total.

Story playback tests cover host-only dialogue and full-text reveal, stale taps,
explicit progression after both players collect a stage, selected-person
testimony, the choice to present evidence or hear another person, result playback,
and evidence-sheet dismissal with AR runtime and photo retention.

The production GameViewModel and EvidenceSearchAssistance policy are also
compiled, with a fake AR runtime and an injected monotonic clock. These tests
cover the 10-second suggestion, active-time pauses, cancel/confirm, phase changes,
reconnection boundaries and exclusion of collected or locally photographed
evidence while its collection acknowledgement is still pending. They verify
that relocation leaves shared progress, photos and outgoing messages unchanged.
They do not run SwiftUI interactions.

Placement regressions additionally use actual RealityKit Entities and Components
with the production EvidencePlacementEngine called by the ECS System. They cover
initial failure recovery without an anchor revision, position-dependent heading,
late table recognition with full-size footprints, joint placement, preservation
of collected/photographed entities, classification and area constraints, tracking
recovery and repeated relocation. The SceneUpdateContext query scheduling and AR
hardware remain outside this harness.

Check the real USDZ assets and production geometry code on macOS:

```sh
bash tests/run-evidence-assets.sh
```

This standalone RealityKit runner loads all resources referenced by the two
evidence JSON files. It verifies normalized render bounds, actual mesh surface
samples, sheet thickness, upright lamp/person poses, the book's cover axis,
independent cached clones, missing resource errors and a failed import followed
by a successful retry, 30cm thresholds,
triangle gaps, two-sided picking, degenerate triangles and BVH traversal.
It does not verify AR hardware, classification, lighting or on-device appearance.
