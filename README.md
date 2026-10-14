# Kiln

A small Unity-style scene editor for [Flame](https://flame-engine.org). Build a casual game in the editor, save it as a `.kiln.json` scene, and play it in any Flutter app with the `kiln` runtime package. No code generation.

```
packages/kiln        runtime: scene model, KilnGame, built-in behaviors
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
(cd apps/kiln_editor && flutter test)
```
