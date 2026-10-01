# Resource updates — app 1.2.2 / Godot 4.4.1

> Clean staging: bundled visuals are original solid-color primitive scenes, with no extracted assets. The repository URLs below are configurable legacy defaults, not approved or verified live hosting. Obtain release-owner approval for valid-certificate HTTPS hosting and authorized resources before real network updates; nothing has been published. The application-manifest template is now version 1.2.2 with an empty IPA URL.

## What genuinely updates

`scenes/boot.tscn` is the exported project's entry point. Its bundled script validates
and activates a persistent sandbox patch **before loading main.tscn** (no main
preload/autoload). A checked JSON map modifies ground/wall/cover/site materials,
loads optional PNG textures at runtime, and constructs box meshes plus collision.
The existing player, weapons, enemies, round rules, HUD and base map remain bundled.
The blue-ground/purple-obstacle fixture demonstrates a real visible map change.

This is a deliberately restricted **asset ZIP**, not executable PCK replacement.
It never mounts a downloadable pack or invokes ResourceLoader on downloaded scene,
script, GLB, native library, import metadata or serialized Godot resources. Models
are not supported in this first iteration; box geometry is declarative map data.
This also avoids platform-specific import/PCK cache problems on iOS.

## Player workflow

Tap **更新** to check, then explicitly consent to download resources. The UI shows
revision, size, notes and download progress. Current gameplay input is suspended
while the dialog is open. Verification/install does not modify the current match.
After successful installation choose **立即载入资源（重新开始本局）** to reload boot,
or return to the game and apply automatically on the next app launch. There is no
forced network request or mandatory update at startup. A check failure, missing
manifest or a 404 keeps the built-in/current validated map usable.

**另行检查应用 IPA 更新** is separate. It can download an IPA only from the allowed
project raw HTTPS path and honestly explains that an external self-sign/install
tool is required. iOS cannot replace its running application. Existing self-signed
IP download URLs are rejected, not silently trusted; get IPA from the official
release manually instead. Sandbox download alone does not export a file to an
installer; no share sheet/file-sharing entitlement is added here.

## Build a patch (does not upload/publish)

Use Python 3 standard library only. Prepare a directory containing:

- mandatory `maps/main.json`
- optional `textures/[a-z0-9_-]{1,80}.png` (maximum 2048 × 2048)
- absolutely nothing else; builder rejects unexpected files/symlinks

Example JSON:

```json
{
  "schema": 1,
  "label": "Blue training ground",
  "ground_color": [0.08, 0.25, 0.85, 1],
  "ground_texture": "textures/grid.png",
  "wall_color": [0.22, 0.35, 0.65, 1],
  "boxes": [
    {"position": [0, 2, -8], "size": [3, 4, 3], "color": [0.75, 0.1, 0.8, 1]}
  ]
}
```

Colors are RGBA [0,1]. Optional `cover_color`/`site_color` use the same format.
Boxes have centers within [-55,55], each dimension [0.1,20], at most 64 boxes.
Ground/walls and existing gameplay collision remain intact. Avoid placing new
boxes on spawns, bomb sites or routes; playtest gameplay before publishing.

```sh
python3 tools/build_resource_patch.py \
  --source tools/tests/fixtures/resource_patch \
  --output /tmp/shotdawn-patch \
  --revision 1 --min-app 1.2.2 --max-app 1.2.2 \
  --url https://raw.githubusercontent.com/ftyhgddjhfd-jpg/qiangpo-ios/master/update/resources-r1.zip \
  --notes 'Blue floor and a new purple obstacle'
```

Output: deterministic `resources-r1.zip` plus `resources.json`. Both app bounds
are inclusive; bump the monotonic resource revision for later changes. Use the
appropriate app range, never assume future app map schemas are compatible.

After testing, the release owner publishes the **immutable revision ZIP first**
under `update/` and only then publishes the manifest as `update/resources.json`.
The app reads:

`https://raw.githubusercontent.com/ftyhgddjhfd-jpg/qiangpo-ios/master/update/resources.json`

Manifest schema: `schema:1`, `format:"shotdawn-assets-zip-v1"`, positive integer
`revision`, semantic `min_app`/`max_app`, exact `url`, byte `size`, hex `sha256`,
optional `notes`. This change intentionally does **not** publish that manifest or
change existing IPA release metadata. Until publication a resource check can say
HTTP 404 without breaking gameplay. Ensure the iOS export includes the new boot
scene and scripts (current `all_resources` export does).

## Persistence and trust

- Downloads: `user://resource_updates/download.zip.part` with a size limit.
- Runtime transport: Godot HTTPS default certificate/hostname verification;
  only exact repository raw `master/update/` URLs; redirects disabled.
  HTTP, other hosts/repos, self-signed IP, URL traversal/encoded escapes rejected.
- Archive requires manifest size and SHA256 match, <=32 MiB, <=65 files;
  per-file <=8 MiB, bounded expanded total <=48 MiB.
- Strict ZIP_STORED only: both local and central directories inspected before
  any decompression/read allocation. ZIP64, compression, encryption, extras,
  descriptors, duplicate paths, symlink entries, unexpected/traversal paths fail.
- Map schema and PNG dimensions/decoding checked before staging.
- Complete validated files go into `user://resource_updates/<sha256>/`;
  a flushed temporary active JSON is atomically renamed into `active.json` only
  after successful archive copy, metadata write and extraction.
- Boot revalidates the retained archive and app compatibility, then regenerates
  the extracted files. Corrupted extraction cannot become authoritative. Corrupt
  current archive falls back to the previous valid archive or built-in resources.
  Interrupted `.part`/temporary pointer/unreferenced staging slots are ignored.
- HTTPS/repository ownership is the authenticity trust root. SHA256 detects
  corruption but is **not a separate signature**; there is no signed manifest or
  offline publisher key. Repository compromise remains a trust risk.
- `user://` persists across launches and normally in-place iOS updates, not
  uninstall/reinstall. Atomic rename is same-filesystem; hardware/power-loss
  durability beyond FileAccess.flush/OS guarantees is not claimed.

## Tests

```sh
python3 tools/tests/test_resource_updates.py
/home/ubuntu/qiangpo/tools/Godot_v4.4.1-stable_linux.x86_64 \
  --headless --path . --script map_shot.gd
/home/ubuntu/qiangpo/tools/Godot_v4.4.1-stable_linux.x86_64 \
  --headless --path . --quit-after 10
```

The Python suite builds a patch, starts a temporary HTTPS fixture, uses a **test-only
transport subclass** with an explicitly trusted ephemeral CA and verified localhost
hostname, downloads via the production HTTPRequest/manifest/install path, exits,
boots a separate Godot process and asserts blue material, newly constructed mesh /
collision and runtime PNG. It also tests immediate boot reload, consent input
blocking, incompatible app range, wrong size/hash, malicious ZIP/paths/scripts/
scenes/symlinks, central-directory mismatch/deflate bomb protection, truncation,
404/redirect failures, interrupted download, corrupt archive built-in fallback,
and previous-valid-patch rollback. No TLS verification is disabled, no system CA
or host config is changed, no production data is published, and the test sandbox
is temporary. Production still only accepts trusted raw GitHub URLs; the temporary
local HTTPS fixture is not a production URL bypass. Linux headless assertions are
not a substitute for on-device iOS network/UI/App Store review testing.

## Current limits

Data-driven color/PNG/box map updates only. No arbitrary Godot scene replacement,
model import, script/native code hotloading, background download resume, CDN /
GitHub Release redirect handling, signed manifests, cross-process installer lock,
or automatic garbage collection of old/unreferenced slots. Large update history
can consume sandbox space; a later cleanup feature must retain active/previous
slots. Boot checksum and extraction are synchronous and bounded but can briefly
block startup for larger packs. IPA downloading remains separate external-install
functionality; this foundation does not bypass iOS platform security or promise
App Store approval. Production raw GitHub publishing/network success and actual
1.2.2 iOS packaging are release-owner responsibilities.

## Changing the trusted delivery server

The defaults above are bundled in `project.godot` under `[hot_update]`:
`manifest_url`, `app_manifest_url`, and `trusted_url_prefixes`. If GitHub delivery
is unavailable, the build/release owner may change them before building to an
owned **valid-certificate HTTPS** domain and exact path prefix ending in `/`.
Trust prefixes must not be broad third-party/shared origins. The downloaded
manifest cannot expand this allowlist. Redirects and normal certificate/hostname
verification remain enforced on alternate endpoints; do not configure an IP /
self-signed endpoint or disable TLS checks. The builder CLI currently validates
the original GitHub prefix; supporting alternate builder URLs requires an explicit
reviewed builder change, not a runtime trust bypass. Local HTTPS tests are
independent of GitHub availability and do not publish anything.
