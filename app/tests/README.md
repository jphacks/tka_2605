Run the game rules tests on macOS with Xcode's Swift toolchain:

```sh
bash tests/run-game-rules.sh
```

The runner builds a temporary Swift package in `/private/tmp`, using the actual
application models, GameManager, EpisodeManager, PlayerManager, ScreenManager,
JSON loader, API classes and GameMessage. Only Playgrounds are excluded. Fixtures
avoid evaluating the APIs' lazy bundle JSON. A fake PeerManager records transport
messages; AppKit's NSImage supplies the UIImage type for photo storage tests.
The actual EvidencePlaneOrientation helper is extracted from the AR components
source and compiled with simd, without requiring an AR session.

The tests cover game rules, snapshot acknowledgements, pending operation replay,
duplicate requests, ending attempts, stale snapshots and local photo retention.
Orientation regression tests cover 1,344 combinations of wall/sloped/horizontal
planes, yaw, in-plane rotation and visible face, checking upright text, matching
surface normals, orthonormality, handedness and the horizontal tangent fallback.
They do not exercise MultipeerConnectivity's discovery or real network delivery.
No Xcode project changes or external dependencies are required. The temporary
directory is kept for inspecting build failures. Swift test options can be passed
to the runner, for example `--filter GameManagerTests.testUnconfirmedCollection`.
