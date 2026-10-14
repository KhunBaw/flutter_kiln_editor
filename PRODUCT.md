# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

<!-- Inferred mapping: the editor is a Flutter desktop app meant to stay cross-platform (macOS today, Windows/Linux later), so its design language must not be tied to one OS. The schema has no "desktop" value; `web` stands for "platform-neutral". -->

## Users

Open-source users: Flutter developers who already use (or are willing to use) Flame and want a visual scene editor instead of building every scene in code. Their job is to get a small casual, puzzle or tap game into an app they are already building, quickly.

## Product Purpose

Kiln lets developers lay out game scenes visually, add behaviors in an Inspector, test with Play/Stop, and ship the result as a `.kiln.json` file that a runtime package plays inside their Flutter app. Success means a simple game goes from idea to running inside a real app without writing scene code by hand.

## Positioning

- **Unity-like workflow for Flame:** Hierarchy, Scene view, Inspector and Play/Stop, so the editor feels familiar to anyone who knows Unity.
- **Embeds in an existing app:** the game is one widget (`KilnGameWidget`) in an ordinary Flutter app, not a separate game app.
- **Custom Dart behaviors stay first-class:** apps register their own behaviors and actions in Dart, and the editor edits their props through an exported schema (`kiln.schema.json`).

## Operating Context

- Developers run the editor next to their IDE and open their Flutter app folder as the "project".
- Scenes live in the app's `assets/scenes/`, images in `assets/images/`, sounds in `assets/audio/`.
- The loop is: edit in the editor, press Play, save, then run the app.
- Custom behavior code is written in the IDE. The editor only reads its schema and never runs that code.

## Capabilities and Constraints

- Monorepo (pub workspace):
  - `packages/kiln`: runtime, scene model and built-in behaviors.
  - `apps/kiln_editor`: the editor.
  - `examples/tap_game`: sample game.
- Scenes are data-driven. There is no code generation, and the scene format is versioned (`"kiln": 1`).
- Built-in behaviors: Shape, Sprite, Text, OnTap, Timer, Prefab, Spawner, Tween, Condition, Collider, OnCollide.
- Built-in actions: AddVariable, SetVariable, Destroy, LoadScene, PlaySound.
- Editor features:
  - Hierarchy, Scene view (click to select, drag to move), and an Inspector generated from `PropDef`.
  - Undo/redo, Play/Stop, and asset import.
  - Open/save scenes, and open a project folder.
- The editor is Flutter desktop. It runs on macOS now under the app sandbox, so it can only access files the user picks. Cross-platform desktop support is intended.
- MVP genre scope: casual, puzzle and tap games.
- Out of scope for now: visual scripting graphs, tilemaps, Forge2D physics, code export and a web editor.

## Evidence on Hand

- `examples/tap_game`: "pop 10 balloons in 30 seconds", built only from scene files (`level1`, `win`, `lose`), with a generated `balloon.png` and `pop.wav`.
- There are no users, testimonials, benchmarks, adoption numbers or published package yet. Future work must not invent any of these.

## Product Principles

1. **Familiar over novel:** follow Unity editor conventions wherever they fit, so users bring existing muscle memory.
2. **The app owns the game:** everything the editor produces must run unchanged inside the user's own Flutter app.
3. **Code is an extension, not an escape hatch:** custom Dart behaviors get the same editing experience as built-ins.
4. **Never lose the user's work:** load and save failures leave the existing data intact, and imports never overwrite a different file.
