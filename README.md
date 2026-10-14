# Kiln

A small Unity-style scene editor for [Flame](https://flame-engine.org). Build a casual game in the editor, save it as a `.kiln.json` scene, and play it in any Flutter app with the `kiln` runtime package. The editor can also generate typed names (scenes, events, variables) for your app code; no build_runner.

```
packages/kiln        runtime: scene model, KilnGame, built-in behaviors
packages/kiln_forge2d  optional physics behaviors (RigidBody, Joint, DragLaunch)
apps/kiln_editor     macOS editor
examples/tap_game    sample game made only of scene files
```

## Embed a scene in your app

1. Depend on the runtime (path or git until it is published):

   ```yaml
   dependencies:
     kiln:
       path: ../kiln/packages/kiln
   flutter:
     assets:
       - assets/scenes/
       - assets/images/   # Sprite
       - assets/audio/    # PlaySound
   ```

2. Copy the `.kiln.json` files from the editor into `assets/scenes/`.

3. Show it:

   ```dart
   import 'package:kiln/kiln.dart';

   KilnGameWidget(asset: 'assets/scenes/level1.kiln.json')
   ```

`LoadScene` actions switch the widget to another scene asset (use it for win/lose/retry screens). For full control, build the game yourself: `GameWidget(game: KilnGame(SceneDoc.fromJson(json)))`.

## Connect your app

Pass a `KilnController` to talk to the running game:

```dart
final c = KilnController(variables: {'lives': 5}, keepVariables: true);

KilnGameWidget(
  asset: KilnScenes.level1,
  controller: c,
  onEvent: (name, value) {
    if (name == KilnEvents.win) showWin(c.vars.coins);
  },
)

c.emit(KilnEvents.pause);        // app -> game: OnEvent behaviors react
c.loadScene(KilnScenes.level1);  // switch scene
```

- Game to app: the `Emit` action (`event`, optional templated `value` like `{score}`) fires `onEvent` / `c.events`.
- App to game: `c.emit(name, value)` runs `OnEvent` behaviors; set `store` on the behavior to keep `value` in a variable.
- Variables: `c.vars` is a `ChangeNotifier`, so `ListenableBuilder` works. `variables:` overrides a scene's starting values.
- `keepVariables: true` keeps one set of variables across `LoadScene` (a new scene only adds missing defaults). `ResetVariables` puts the current scene's variables back to defaults.
- Typed names: saving a scene under `<project>/assets/scenes/` in the editor rewrites `lib/kiln.g.dart` (`KilnScenes`, `KilnEvents`, `KilnVars`). Without the editor: `dart run kiln:types`.

## Scene model

- A scene has a size (the fixed camera resolution, top-left origin), variables (`score`, `time`, ...) and entities.
- An entity has a center position, size, angle (radians), child entities and a list of behaviors.
- Child positions are relative to the parent's top-left corner.
- Text can show variables: `"Score: {score}"`.
- Unknown behaviors/actions are skipped at runtime with a debug log and kept as-is by the editor.

### Built-in behaviors

| Behavior | Props |
|---|---|
| `Sprite` | `image`: a file name in `assets/images/`, stretched to the entity size |
| `Shape` | `shape` rect/oval, `color` `#RRGGBB` or `#AARRGGBB` |
| `Text` | `text`, `fontSize`, `color` |
| `OnTap` | `actions` |
| `Timer` | `interval` s, `repeat`, `actions` |
| `Prefab` | marker: a top-level entity is hidden at play time and used as a template |
| `Spawner` | `prefab` (entity name), `interval`, `max` (0 = no limit); spawns at random points inside its own rect |
| `Tween` | `kind` moveBy/scaleBy/rotateBy, `x`, `y`, `duration`, `loop` once/repeat/pingpong |
| `Condition` | `variable`, `op`, `value`, `actions`; fires once each time the test turns true |
| `Collider` | `shape` rect/circle |
| `OnCollide` | `with` (entity name, empty = any), `actions` |

### Built-in actions

`AddVariable(name, value)`, `SetVariable(name, value)`, `Destroy`, `LoadScene(scene)`, `PlaySound(file in assets/audio/)`. Actions run on the entity that owns the behavior.

### Grid, tiles and saving

| Behavior / action | What it does |
|---|---|
| `Tilemap` | `image` tileset (square `tile` px cells; empty = flat colours), `cols`, `tiles` (row-major, 0 empty, n = tile n), `solid` (tile numbers that block, e.g. `1, 2`). Paint it in the editor: select the entity, **PAINT** in its Tilemap counter, pick a tile, click or drag the scene (**FILL** floods a region). `Body`, `GridMove` and `Follow` treat solid tiles as walls |
| `GridMove` | One cell per key press (hold to repeat), `cell`, `time` s per step (0 = instant), `keys`, `push` (name or `#tag` of crates pushed one cell; a blocked push stops you), `block` (entities that can't be entered), `onStep` actions. The grid origin is the world's (0, 0): keep tilemaps and crates on multiples of `cell` |
| `Follow` + `pathfind` | Routes around solid tiles of the scene's Tilemap (shortest 4-way path, recomputed when the target changes cell) |
| `Dialogue` | `lines` separated by `|` (`{var}` slots work), optional `choices`, `variable` (gets the picked 1-based number), `open` (event that shows it; empty = at start), `actions` when done. Tap, Space/Enter advance; number keys or a tap pick a choice |
| `OnCollide` `exit` | actions that run when the contact ends |
| `SaveGame` / `LoadGame` | `slot`, `names` (comma list, empty = all variables). `LoadGame` emits `loaded` or `loadfailed`; `SaveGame` emits `saved` |

SaveGame/LoadGame write JSON through a `KilnStorage` (default: files in the app support directory). Pass your own to `KilnController(storage: ...)` or `KilnGame(storage: ...)`. Only numbers, strings and booleans are saved; scenes are not.

Example: `examples/sokoban`.

### Physics (`kiln_forge2d`)

An optional package on [Forge2D](https://pub.dev/packages/forge2d). Add it to the app and register it where you build the registry:

```dart
final registry = KilnRegistry();
registerForge2d(registry, gravity: 9.8); // m/s², 50 scene px per meter
KilnGameWidget(asset: 'assets/scenes/level1.kiln.json', registry: registry);
```

Write the schema once so the editor shows the types (see the test in `examples/launcher/test/`).

| Behavior | What it does |
|---|---|
| `RigidBody` | `type` dynamic/static/kinematic, `shape` box/circle (from the entity size), `density`, `restitution`, `friction`, `gravityScale`, `fixedRotation`. It is the entity's one mover: `SetProp vx/vy/spin`, `Move8` and `Follow` set the body's velocity. Don't add `Velocity` or `Body` next to it. Use `Collider` + `OnCollide` for game logic |
| `Joint` | `kind` revolute/distance/rope, `other` (name or `#tag`; empty = a fixed world point), `anchorX/Y` from this entity's centre, `otherAnchorX/Y` from the partner's centre (or the world position when `other` is empty), `collide`, `frequency`/`damping` (distance spring) |
| `DragLaunch` | Slingshot: the body is held until you drag back from it and let go; `power` (px/s per px pulled), `maxPull`, `grab` (extra grab area), `onLaunch` actions; a dotted arc previews the flight |

Physics runs at a fixed 60 Hz step and is frozen in the editor preview. Entities with a `RigidBody` should be top-level (the body lives in world space).

Example: `examples/launcher`.

## Custom behaviors and actions

Register Dart code under a type name, then use that name in the scene:

```dart
import 'package:flame/components.dart';
import 'package:kiln/kiln.dart';

class Spin extends Component with ParentIsA<KilnEntity> {
  Spin(this.speed);
  final double speed;

  @override
  void update(double dt) => parent.angle += speed * dt;
}

final registry = KilnRegistry()
  ..register(BehaviorDef('Spin', const [PropDef('speed', PropKind.number, 1)], (e, p) => Spin(p.number('speed'))))
  ..registerAction(ActionDef('Double', const [PropDef('name', PropKind.string, 'score')], (self, a) {
    final v = self.game.vars[a.string('name')];
    if (v is num) self.game.vars[a.string('name')] = v * 2;
  }));

KilnGameWidget(asset: 'assets/scenes/level1.kiln.json', registry: registry)
```

- A factory returns a Flame `Component` that is added under the entity, or `null` when it only hooks events (`e.tapHandlers`, `e.collideHandlers`).
- `PropDef`s give the default values and tell the editor which input to show.
- `Props` reads scene JSON safely: wrong types fall back to `0`, `''` or `false` instead of throwing.

### Show custom types in the editor

The editor cannot run your Dart code, but it can show forms for it. Export the schema once (e.g. from a test) to the app folder:

```dart
File('kiln.schema.json').writeAsStringSync(jsonEncode(registry.schemaJson()));
```

When you open that folder as the project, the editor reads `kiln.schema.json` and lists your types under "Add behavior" and "Add action".
- The Inspector edits their props the same way as the built-ins.
- The preview and Play skip their code.

## Editor

Run `flutter run -d macos` in `apps/kiln_editor`, or use the "kiln_editor (macOS)" launch config.

| Panel / tool | What it does |
|---|---|
| Project folder | Open your Flutter app folder: images, sounds and `LoadScene` read from its `assets/`, and custom types load from `kiln.schema.json` |
| Hierarchy | Add, delete and select entities |
| Scene view | Click to select, drag to move |
| Inspector | Edit transforms, add or remove behaviors, edit props and action lists. The ⤒ button next to an image/audio prop copies the file into `assets/images/` or `assets/audio/`; it never overwrites a different file with the same name |
| Menu / toolbar | ⌘N new, ⌘O open, ⌘S save, ⇧⌘S save as, ⌘Z/⇧⌘Z undo/redo, ⌘P play/stop |

Workflow:
1. Open your Flutter app folder as the project.
2. Open or create a scene in `assets/scenes/`.
3. Edit it, then press Play.
4. Save it, then run your app.

## Develop

```sh
flutter analyze                      # whole workspace
(cd packages/kiln && flutter test)
(cd packages/kiln_forge2d && flutter test)
(cd apps/kiln_editor && flutter test)
```
