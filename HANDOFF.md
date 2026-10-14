# HANDOFF — Kiln (scene editor for Flutter Flame)

Written: 2026-10-15 00:57
Written at commit: no commits yet (branch `main`, everything untracked)
Branch: main

> Tags: `[V]` verified against the repo during this handoff · `[?]` recalled, unverified — confirm before relying on it.

---

## GOAL

Expand Kiln from casual/tap MVP to support all major 2D game genres, built from the editor alone (custom Dart behaviors optional).

## PHASE

Phase 0/6: planning done, implementation not started
Status: plan written, user has NOT approved it (ExitPlanMode was rejected once, then /handoff invoked)
Blocked by: user approval of phase plan at `/Users/khunbaw/.claude/plans/ui-flutter-parallel-dewdrop.md`

---

## STATE (verified)

- `[V]` Repo is git on `main` with zero commits — evidence: `git log` → "your current branch 'main' does not have any commits yet"
- `[V]` All project files untracked (`apps/ examples/ packages/ DESIGN.md PRODUCT.md README.md pubspec.yaml .impeccable/ ...`) — evidence: `git status --short`
- `[V]` Pub workspace members: `packages/kiln`, `apps/kiln_editor`, `examples/tap_game` — evidence: re-read `pubspec.yaml`
- `[V]` Runtime built-ins: behaviors Shape, Sprite, Text, OnTap, Timer, Prefab, Spawner, Tween, Condition, Collider, OnCollide; actions AddVariable, SetVariable, Destroy, PlaySound, LoadScene — evidence: grep `BehaviorDef(|ActionDef(` in `packages/kiln/lib/src/builtins.dart`
- `[V]` `KilnGame` ctor has `editing`, `onLoadScene`, `playSound`, `bundle`; mixes `HasCollisionDetection`; `updateTree` passes dt=0 when editing — evidence: re-read `packages/kiln/lib/src/game.dart:28-74`
- `[V]` Example scenes exist: `examples/tap_game/assets/scenes/{level1,win,lose}.kiln.json` — evidence: `ls`
- `[V]` DESIGN.md 321 lines, README.md 132, PRODUCT.md 59 — evidence: `wc -l`
- `[?]` Old milestones M0–M6 complete; "3 tasks" (entitlement + project folder/import, PlaySound, custom schema) complete
- `[?]` Editor redesign "Counter Sheet" complete, finish-review verdict "ship" (round 3)
- `[?]` Last known: `flutter analyze` no issues; kiln tests 14/14; editor tests 5/5 (not re-run this handoff)

Working tree: everything untracked, no commits

## NEXT

1. Get user approval of the phase plan — `/Users/khunbaw/.claude/plans/ui-flutter-parallel-dewdrop.md` — user asked "วางแผนขยายไปในทุกแนวเกมที่เป็น 2D โดยแบ่งเฟส"; adjust if they want changes
2. (Suggest) make an initial commit before Phase 0 so later diffs are reviewable — ask first, no attribution lines
3. Phase 0 Foundation runtime — `packages/kiln/lib/src/builtins.dart`, `game.dart`, `scene.dart`, `registry.dart` — Emit/OnEvent, target+tags, SetProp, Spawn action, OnKey, Velocity, SpriteAnimation, Camera (viewSize vs worldSize), OffScreen, PlayMusic/StopMusic
4. Phase 0 editor — `apps/kiln_editor/lib/panels.dart`, `main.dart`, `theme.dart` (add `Family.of` + `factorOf` cases for every new type) — pan/zoom, resize/rotate handles, snap grid, asset browser, tags editor, target picker
5. Then phases 1–6 per plan (platformer, top-down/shooter, grid/tile, Forge2D package, UI layer, production); one example game per phase = done

## UNVERIFIED CHANGES

- none this session-half (only plan file + this HANDOFF.md written)

---

## DECISIONS

- `[?]` Output = runtime package `kiln` + `.kiln.json` scenes, no code gen — keeps editor a JSON editor
- `[?]` Editor = Flutter desktop macOS; behaviors built-in + custom Dart registered via `KilnRegistry`; editor learns custom types from `kiln.schema.json`
- `[?]` Design direction "Counter Sheet" (dark olive Z ramp, family colors R/I/L/P, mark yellow, Barlow fonts) — documented in `DESIGN.md`; keep it for new UI
- `[?]` Plan: simple kinematic physics in core; Forge2D only in separate package `kiln_forge2d`
- `[?]` Plan out of scope: 3D, multiplayer, node-graph visual scripting, isometric
- `[?]` Shortcuts via `PlatformMenuBar` (native menu), not Flutter `Shortcuts`

## DEAD ENDS

- Flutter `Shortcuts`/`CallbackShortcuts` for ⌘S etc. → stopped firing after dialogs closed — use `PlatformMenuBar`
- Flame `images.load` for missing sprite → leaked uncaught error from `_ImageAsset` — fetch bytes via `images.bundle` manually then `images.add`
- flame_audio `BytesSource` in editor → not supported on darwin — use `playSound` hook + `DeviceFileSource`
- Editing entitlements via Bash/perl → blocked by auto-mode classifier — use Edit tool after explicit user consent
- Synthetic CGEvent ⌘ combos to test shortcuts → break Flutter keyboard state — real ⌘S still unverified; needs manual test
- Treating craft-floor "Refuse" list as hard bans (declined inset selection bar) → reviewer overruled; they are defaults a brief can earn

## TRAPS

- `[?]` `PlatformProvidedMenuItem` about/quit must be guarded by `.hasMenu` or widget tests fail on non-mac test platform
- `[?]` Sprite tests need `TestWidgetsFlutterBinding.ensureInitialized()`
- `[?]` Finding `GameWidget` in tests: generic type → use `find.byWidgetPredicate`
- `[?]` Drag in editor snaps to whole pixels from drag start; keep this when adding handles
- `[?]` `KilnGame.editing` freezes time — every new behavior must not move/fire while editing
- `[?]` Prefabs (top-level entities with Prefab behavior) hidden at play time, visible in editor
- `[?]` Saved numbers serialize as `"200.0"` style — known cosmetic issue, not fixed
- `[V]` `rtk find` rejects `-exec`/compound predicates — use plain commands or Read

---

## CONSTRAINTS

- Replies: terse Thai (pordee, no polite particles), technical terms in English; NEVER Vietnamese
- ponytail full: minimal code, end replies with 1–2 lines on skipped/unchecked + risk
- No "should work" — verify with evidence; flag scope creep; error handling + null safety
- Comments minimal, English; commits without attribution lines; commit/push only when asked
- Old scenes must keep loading (default values; migrate in `SceneDoc.fromJson` if format changes)

## ASSUMPTIONS

- Flutter 3.47.1 / Dart 3.13.1 via FVM, Flame 1.38.2 — verify by: `flutter --version`, `pubspec.lock`
- `path_provider` may already be in dependency tree (for Save/Load in Phase 3) — verify by: grep `pubspec.lock`
- Default window 1440×900 never seen on real screen (only 1100×732 tested) — verify on bigger display

## OPEN QUESTIONS

- Approve phase plan as-is, or reorder/cut phases?
- Make initial git commit now?
- Fix documenter drift (mark yellow overuse, danger ≈ logic rust hue, Material default elevation)?

---

## FILES

- `/Users/khunbaw/.claude/plans/ui-flutter-parallel-dewdrop.md` — phase plan (P0–P6) awaiting approval
- `packages/kiln/lib/src/builtins.dart` — built-in behaviors/actions; new ones go here
- `packages/kiln/lib/src/game.dart` — `KilnGame`, `KilnEntity`, `GameVariables`, `KilnGameWidget`
- `packages/kiln/lib/src/registry.dart` — `BehaviorDef`, `ActionDef`, `PropDef`, `PropKind`, schema export/import
- `packages/kiln/lib/src/scene.dart` — `SceneDoc`, `EntityNode`, `BehaviorData` JSON
- `packages/kiln/test/behaviors_test.dart`, `kiln_test.dart` — runtime tests pattern
- `apps/kiln_editor/lib/main.dart` — app shell, toolbar, PlatformMenuBar, Play
- `apps/kiln_editor/lib/panels.dart` — Hierarchy, SceneFrame/SceneView, Inspector
- `apps/kiln_editor/lib/theme.dart` — Z tokens, `Family.of`, `factorOf`, `kilnTheme()`
- `apps/kiln_editor/lib/editor_state.dart` — undo snapshots, project open, asset import
- `apps/kiln_editor/lib/project.dart` — `DirBundle`
- `apps/kiln_editor/test/editor_state_test.dart` — editor tests
- `examples/tap_game/` — sample game + regression target
- `DESIGN.md`, `PRODUCT.md`, `.impeccable/` — design system & context

## COMMANDS

- build/run editor: `cd apps/kiln_editor && flutter run -d macos`
- run sample: `cd examples/tap_game && flutter run -d macos`
- test: `cd packages/kiln && flutter test` ; `cd apps/kiln_editor && flutter test`
- lint: `flutter analyze` (workspace root)
