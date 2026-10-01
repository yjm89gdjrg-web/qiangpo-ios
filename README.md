# ShotDawn 1.2.2 — clean iOS source staging

This directory is prepared source, **not a compiled IPA**, not a published repository, and not an App Store approval claim. No build service was triggered during preparation.

## Asset provenance and attribution

All player/enemy/weapon shapes here are self-created compositions of Godot BoxMesh, CapsuleMesh and CylinderMesh primitives with generated solid colors. `tools/generate_primitive_scenes.py` creates the nine self-contained `.tscn` PackedScenes in `scenes/primitives/` using only Python's standard library and numeric design parameters. There are **no extracted game assets**, model imports, textures, third-party character meshes, screenshots, Git history or imported `.godot` cache in this source staging. The simple SD SVG icon is generated vector/text artwork from the existing prototype, not an extracted game asset. Optional resource-test PNGs are generated mathematically in a temporary directory, not bundled art.

The seven weapon child names and gameplay statistics are retained for compatibility; their new stylized geometry is not a reproduction of extracted models. The gameplay code/config originated from the supplied local prototype. No ownership/license claim over that existing code or the ShotDawn name is made here; confirm code/name rights before any public release. Godot Engine is separately MIT-licensed: https://godotengine.org/license/ . Follow its distribution attribution requirements when shipping engine binaries.

## What is preserved

FPS camera, seven selectable weapons, raycast fire/reload, bots and line-of-sight damage, player/enemy/world collisions, keyboard/touch controls, responsive HUD, bomb rounds and the restricted resource hot-update pipeline remain. The bundled player-body scene is hidden in first person to avoid camera obstruction. Enemy primitives fit the existing 1.8 m capsule, with no dependency on imported mesh scale.

## Local verification

Use Godot **4.4.1** and Python 3. Resource integration tests also require `openssl`; rendered tests require a working display or Xvfb plus OpenGL/Mesa. See `VALIDATION.md` for actual preparation results. Regenerate scenes with:

```sh
python3 tools/generate_primitive_scenes.py
godot --headless --path . --editor --import
godot --headless --path . --script map_shot.gd
python3 tools/tests/test_resource_updates.py --godot /path/to/godot
```

For rendered map screenshots, set `SHOTDAWN_VALIDATION_DIR` to an existing directory outside this source tree. Linux PCK validation is a local packaging/runtime test only, not an iOS build.

## iOS packaging — owner must explicitly start later

`export_presets.cfg` retains unsigned/export-project-only iOS settings, arm64, minimum iOS 13 and version **1.2.2**. The GitHub workflow is **manual dispatch only** and retains GitHub artifact upload; the server-upload step, token requirement and insecure certificate bypass have been removed. Codemagic also retains artifacts only. Neither workflow was executed here. Actual IPA compilation requires macOS, compatible Xcode, Godot iOS export templates and a deliberate owner action. Unsigned IPA installation requires external signing; it cannot directly install through this app.

## Resource delivery is NOT live

The existing repository-specific manifest defaults are retained as configurable settings under `[hot_update]` in `project.godot`: `manifest_url`, `app_manifest_url`, `trusted_url_prefixes`. They are **not verified approved hosting**, and no production manifest/resource/IPA was uploaded. Before real network updates, the release owner must approve an owned hosting location, valid HTTPS certificate, immutable reviewed assets and narrow trusted prefix, and validate actual iOS connectivity. Never use self-signed/IP URLs or disable TLS verification. The builder currently checks the bundled repository prefix; changing hosting also requires a reviewed builder-prefix change. Downloaded manifests cannot enlarge trust.

`update/ShotDawn-update.json` is an inert 1.2.2 staging template with an empty IPA URL, not metadata advertising a real artifact. No resource `resources.json` is bundled/published. Gameplay performs no unsolicited startup network check; pressing Update may fail until valid approved hosting exists. Resource download/install uses validated data maps and optional owner-authorized PNGs, not downloaded scripts/scenes or arbitrary PCK code. Solid-color bundled visuals require no textures. See `docs/resource-hot-updates.md` for limits and trust details.
