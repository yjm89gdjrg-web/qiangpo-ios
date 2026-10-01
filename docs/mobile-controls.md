# Mobile controls and settings

## Use

- Home: **设置**. In game: **设置**, top right. No floating 更新 button; 更新 is inside settings and opens the existing consent/download UI.
- 自定义触屏布局: select/drag 开火、跳跃、换枪、下包/拆包 or 移动区域 using a finger or mouse; the slider changes the selected control's size (60–180%).
- 保存 applies and persists the draft; 取消 discards it; 恢复默认 resets the draft, then 保存 commits it.
- 显示移动摇杆区域 toggles its visual outline, not its input region. Movement starts only within the configured region, then follows a floating touch origin. The remaining right side controls aim; aiming never fires.

## Implementation

`scripts/ui/control_layout.gd` saves normalized centers, relative size multipliers and visibility with ConfigFile at `user://mobile_controls.cfg`. Size is relative to the viewport's shorter side; rectangles are clamped fully onscreen at use time, so smaller screens do not overwrite saved placement. Invalid/NaN config values are rejected or clamped. HUD and player use exactly the same move-region rectangle.

`scripts/ui/settings.gd` is reused on the unloaded-game homepage and in game. Editor controls are previews, never connected to gameplay actions. Save failures stay visible instead of silently losing the draft.

`scripts/ui/modal_pause.gd` keeps one pause lease per overlay. The first lease captures the previous SceneTree pause state and mouse mode; the final release restores both. Settings acquires the update overlay's lease before releasing its own, preventing a settings→update transition from briefly resuming the game or restoring disabled process modes. Updater/settings continue processing while the scene is paused; bots, player, round timer and reload/impact timers stop. Applying resource updates while an overlay is open cleans up the lease when the old scene exits and returns to the homepage.

Input starts are unhandled-input only, while releases are observed globally so fingers released over GUI cannot leave movement, aim, or HUD fire stuck. Opening a modal and losing application focus clear held input. Keyboard/mouse debug controls remain supported; a GUI mouse press cannot be polled as gameplay shooting.

## Automated verification

Godot 4.4.1 binary: `/home/ubuntu/qiangpo/tools/Godot_v4.4.1-stable_linux.x86_64`.

```sh
$GODOT --headless --path . --editor --import
$GODOT --headless --path . --script tools/tests/mobile_controls_test.gd
$GODOT --headless --path . --script tools/tests/mobile_controls_test.gd -- write
$GODOT --headless --path . --script tools/tests/mobile_controls_test.gd -- read
$GODOT --headless --path . --script tools/tests/home_test.gd
$GODOT --headless --path . --script scripts/smoke_test.gd
python3 tools/tests/test_resource_updates.py
```

Run tests under a temporary `XDG_DATA_HOME` to isolate real user settings. The mobile test includes drag handlers for touch/mouse, selected size, save/cancel/defaults, separate-process persistence, clamping at 1280×720 / 844×390 / 640×360, actual HUD viewport resizing at the first two sizes, live fire/jump/switch/plant/defuse callbacks, editor suppression, modal handoff, pre-existing pause restoration, timer pause, release-over-GUI and unloaded homepage/start behavior. The existing resource regression was updated for explicit home Start, SceneTree pause leases, test-only fixture URL trust and version-independent fixture compatibility; production trust/transport rules are unchanged. Smoke test now sets current_scene and frees it before quitting.

All commands above passed in the final run, with no script errors; the fixture builder emits its intentional duplicate-ZIP-entry warning during negative tests.

## Scope / device checks still needed

This is a script/UI change requiring a new application build; the existing data-only hot update does not install scripts. No app/export version, deployment, signing or workflow changes are included here. Phone visual/multitouch feel and iOS notch safe-area verification remain manual: the UI clamps to the viewport, not OS-specific notch insets. Layouts may deliberately overlap; the editor does not enforce collision avoidance. The editor toolbar occupies the upper-left corner, so avoid dragging controls under it. No migration from earlier layouts is needed because the previous release had no saved custom-layout file.
