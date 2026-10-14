# Kiln behavior reference

Generated from `KilnRegistry.schemaJson()`; do not edit by hand.

## Behaviors

### Shape

| Property | Kind | Default |
|---|---|---|
| `shape` | choice (rect, oval) | `rect` |
| `color` | color | `#4488FF` |

### Sprite

| Property | Kind | Default |
|---|---|---|
| `image` | image | `` |

### SpriteAnimation

| Property | Kind | Default |
|---|---|---|
| `image` | image | `` |
| `cols` | number | `1` |
| `rows` | number | `1` |
| `fps` | number | `8` |
| `clips` | string | `` |
| `start` | string | `` |
| `loop` | bool | `true` |

### Text

| Property | Kind | Default |
|---|---|---|
| `text` | string | `Text {score}` |
| `fontSize` | number | `24` |
| `color` | color | `#FFFFFF` |

### OnTap

| Property | Kind | Default |
|---|---|---|
| `actions` | actions | `[]` |

### Timer

| Property | Kind | Default |
|---|---|---|
| `interval` | number | `1` |
| `repeat` | bool | `true` |
| `actions` | actions | `[]` |

### Prefab

No properties.

### Spawner

| Property | Kind | Default |
|---|---|---|
| `prefab` | string | `` |
| `interval` | number | `1` |
| `max` | number | `0` |

### Tween

| Property | Kind | Default |
|---|---|---|
| `kind` | choice (moveBy, scaleBy, rotateBy) | `moveBy` |
| `x` | number | `0` |
| `y` | number | `-50` |
| `duration` | number | `1` |
| `loop` | choice (once, repeat, pingpong) | `pingpong` |

### Animator

| Property | Kind | Default |
|---|---|---|
| `duration` | number | `1` |
| `loop` | choice (once, loop, pingpong) | `loop` |
| `autoplay` | bool | `true` |
| `tracks` | keyframes | `[]` |

### Condition

| Property | Kind | Default |
|---|---|---|
| `variable` | string | `score` |
| `op` | choice (==, !=, >, >=, <, <=) | `>=` |
| `value` | number | `10` |
| `expr` | string | `` |
| `check` | choice (change, frame) | `change` |
| `actions` | actions | `[]` |

### StateMachine

| Property | Kind | Default |
|---|---|---|
| `initial` | string | `` |
| `states` | json | `[]` |
| `transitions` | json | `[]` |

### OnPointer

| Property | Kind | Default |
|---|---|---|
| `down` | actions | `[]` |
| `move` | actions | `[]` |
| `up` | actions | `[]` |

### Joystick

| Property | Kind | Default |
|---|---|---|
| `varX` | string | `joyX` |
| `varY` | string | `joyY` |
| `speed` | number | `0` |
| `target` | string | `` |

### Collider

| Property | Kind | Default |
|---|---|---|
| `shape` | choice (rect, circle) | `rect` |

### OnCollide

| Property | Kind | Default |
|---|---|---|
| `with` | string | `` |
| `actions` | actions | `[]` |
| `exit` | actions | `[]` |

### Tilemap

| Property | Kind | Default |
|---|---|---|
| `image` | image | `` |
| `tile` | number | `32` |
| `cols` | number | `10` |
| `tiles` | tiles | `[]` |
| `solid` | string | `1` |

### GridMove

| Property | Kind | Default |
|---|---|---|
| `cell` | number | `32` |
| `time` | number | `0.12` |
| `keys` | choice (both, arrows, wasd) | `both` |
| `push` | string | `` |
| `block` | string | `` |
| `onStep` | actions | `[]` |

### Dialogue

| Property | Kind | Default |
|---|---|---|
| `lines` | string | `Hello!|How are you?` |
| `choices` | string | `` |
| `variable` | string | `answer` |
| `open` | string | `` |
| `fontSize` | number | `18` |
| `color` | color | `#FFFFFF` |
| `actions` | actions | `[]` |

### Hud

No properties.

### Button

| Property | Kind | Default |
|---|---|---|
| `label` | string | `Button` |
| `fontSize` | number | `20` |
| `textColor` | color | `#FFFFFF` |
| `color` | color | `#3A6FD8` |
| `pressedColor` | color | `#2A4F9A` |
| `radius` | number | `8` |
| `actions` | actions | `[]` |

### Panel

| Property | Kind | Default |
|---|---|---|
| `color` | color | `#222A33` |
| `border` | color | `#44525F` |
| `radius` | number | `10` |
| `image` | image | `` |
| `slice` | number | `16` |

### ProgressBar

| Property | Kind | Default |
|---|---|---|
| `variable` | string | `hp` |
| `max` | number | `100` |
| `color` | color | `#6CC070` |
| `background` | color | `#2B3138` |

### Draggable

| Property | Kind | Default |
|---|---|---|
| `snapBack` | bool | `true` |
| `actions` | actions | `[]` |

### DropZone

| Property | Kind | Default |
|---|---|---|
| `accept` | string | `` |
| `snap` | bool | `true` |
| `actions` | actions | `[]` |

### Wheel

| Property | Kind | Default |
|---|---|---|
| `slices` | string | `Coins|coin.png|40;Gem|gem.png|10;Star|star.png|1` |
| `variable` | string | `slices` |
| `resultVar` | string | `result` |
| `limit` | number | `0` |
| `limitVar` | string | `limit` |
| `spinsVar` | string | `spins` |
| `leftVar` | string | `left` |
| `revealTime` | number | `2.5` |
| `spinTime` | number | `4` |
| `minTurns` | number | `4` |
| `spinEvent` | string | `spin` |

### VarSprite

| Property | Kind | Default |
|---|---|---|
| `variable` | string | `background` |
| `image` | image | `` |

### OnEvent

| Property | Kind | Default |
|---|---|---|
| `event` | string | `event` |
| `store` | string | `` |
| `actions` | actions | `[]` |

### OnKey

| Property | Kind | Default |
|---|---|---|
| `key` | choice (Space, Enter, Escape, Tab, Shift, Control, Alt, ArrowUp, ArrowDown, ArrowLeft, ArrowRight, A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9) | `Space` |
| `on` | choice (down, up, held) | `down` |
| `actions` | actions | `[]` |

### Velocity

| Property | Kind | Default |
|---|---|---|
| `vx` | number | `0` |
| `vy` | number | `0` |
| `spin` | number | `0` |
| `space` | choice (world, local) | `world` |

### Camera

| Property | Kind | Default |
|---|---|---|
| `deadzoneW` | number | `0` |
| `deadzoneH` | number | `0` |
| `clamp` | bool | `true` |

### Body

| Property | Kind | Default |
|---|---|---|
| `gravity` | number | `1400` |
| `maxFall` | number | `900` |
| `friction` | number | `0` |
| `coyote` | number | `0.1` |

### Solid

| Property | Kind | Default |
|---|---|---|
| `oneWay` | bool | `false` |

### OnLand

| Property | Kind | Default |
|---|---|---|
| `actions` | actions | `[]` |

### Parallax

| Property | Kind | Default |
|---|---|---|
| `factorX` | number | `0.5` |
| `factorY` | number | `0` |

### Move8

| Property | Kind | Default |
|---|---|---|
| `speed` | number | `220` |
| `keys` | choice (both, arrows, wasd) | `both` |
| `joystick` | bool | `false` |
| `turn` | bool | `false` |
| `bounded` | bool | `true` |

### Health

| Property | Kind | Default |
|---|---|---|
| `hp` | number | `3` |
| `invulnerable` | number | `0.5` |
| `variable` | string | `` |
| `hurt` | actions | `[]` |
| `death` | actions | `[]` |

### Follow

| Property | Kind | Default |
|---|---|---|
| `target` | string | `Player` |
| `speed` | number | `100` |
| `stop` | number | `0` |
| `pathfind` | bool | `false` |

### Patrol

| Property | Kind | Default |
|---|---|---|
| `points` | string | `` |
| `speed` | number | `100` |
| `loop` | choice (loop, pingpong, once) | `loop` |

### Wander

| Property | Kind | Default |
|---|---|---|
| `speed` | number | `60` |
| `interval` | number | `1.5` |

### LookAt

| Property | Kind | Default |
|---|---|---|
| `target` | string | `Player` |
| `offset` | number | `0` |

### OffScreen

| Property | Kind | Default |
|---|---|---|
| `area` | choice (view, world) | `view` |
| `margin` | number | `0` |
| `actions` | actions | `[]` |

## Actions

### AddVariable

| Property | Kind | Default |
|---|---|---|
| `name` | string | `score` |
| `value` | number | `1` |
| `scope` | choice (global, self, target) | `global` |
| `entity` | string | `` |

### SetVariable

| Property | Kind | Default |
|---|---|---|
| `name` | string | `score` |
| `value` | string | `` |
| `scope` | choice (global, self, target) | `global` |
| `entity` | string | `` |

### If

| Property | Kind | Default |
|---|---|---|
| `expr` | string | `=score > 0` |
| `then` | actions | `[]` |
| `else` | actions | `[]` |

### Log

| Property | Kind | Default |
|---|---|---|
| `value` | string | `` |

### SetState

| Property | Kind | Default |
|---|---|---|
| `state` | string | `` |

### SetTile

| Property | Kind | Default |
|---|---|---|
| `c` | number | `0` |
| `r` | number | `0` |
| `tile` | number | `1` |

### FillTiles

| Property | Kind | Default |
|---|---|---|
| `c` | number | `0` |
| `r` | number | `0` |
| `w` | number | `1` |
| `h` | number | `1` |
| `tile` | number | `0` |

### CameraShake

| Property | Kind | Default |
|---|---|---|
| `strength` | number | `8` |
| `time` | number | `0.3` |

### ListAdd

| Property | Kind | Default |
|---|---|---|
| `name` | string | `items` |
| `value` | string | `` |
| `index` | number | `-1` |

### ListRemove

| Property | Kind | Default |
|---|---|---|
| `name` | string | `items` |
| `index` | number | `0` |

### ListSet

| Property | Kind | Default |
|---|---|---|
| `name` | string | `items` |
| `index` | number | `0` |
| `value` | string | `` |

### ListClear

| Property | Kind | Default |
|---|---|---|
| `name` | string | `items` |

### MapSet

| Property | Kind | Default |
|---|---|---|
| `name` | string | `table` |
| `key` | string | `` |
| `value` | string | `` |

### Repeat

| Property | Kind | Default |
|---|---|---|
| `count` | number | `3` |
| `var` | string | `i` |
| `actions` | actions | `[]` |

### ForEach

| Property | Kind | Default |
|---|---|---|
| `list` | string | `items` |
| `var` | string | `item` |
| `index` | string | `i` |
| `actions` | actions | `[]` |

### Animate

| Property | Kind | Default |
|---|---|---|
| `mode` | choice (restart, pause, resume) | `restart` |

### Destroy

No properties.

### PlaySound

| Property | Kind | Default |
|---|---|---|
| `file` | audio | `` |

### LoadScene

| Property | Kind | Default |
|---|---|---|
| `scene` | string | `assets/scenes/level1.kiln.json` |

### Emit

| Property | Kind | Default |
|---|---|---|
| `event` | string | `event` |
| `value` | string | `` |

### ResetVariables

| Property | Kind | Default |
|---|---|---|
| `names` | string | `` |

### SetProp

| Property | Kind | Default |
|---|---|---|
| `prop` | choice (x, y, angle, width, height, visible, vx, vy, spin) | `x` |
| `mode` | choice (set, add) | `set` |
| `value` | number | `0` |

### Spawn

| Property | Kind | Default |
|---|---|---|
| `prefab` | string | `` |
| `x` | number | `0` |
| `y` | number | `0` |
| `angle` | number | `0` |

### Jump

| Property | Kind | Default |
|---|---|---|
| `force` | number | `600` |
| `air` | bool | `false` |

### Shoot

| Property | Kind | Default |
|---|---|---|
| `prefab` | string | `Bullet` |
| `speed` | number | `600` |
| `aim` | choice (facing, target) | `facing` |
| `at` | string | `` |
| `cooldown` | number | `0.2` |
| `offset` | number | `20` |
| `spread` | number | `0` |

### Damage

| Property | Kind | Default |
|---|---|---|
| `amount` | number | `1` |

### Heal

| Property | Kind | Default |
|---|---|---|
| `amount` | number | `1` |

### Burst

| Property | Kind | Default |
|---|---|---|
| `count` | number | `12` |
| `speed` | number | `140` |
| `life` | number | `0.5` |
| `size` | number | `3` |
| `color` | color | `#E9C548` |

### Flip

| Property | Kind | Default |
|---|---|---|
| `face` | choice (toggle, left, right) | `toggle` |

### PlayAnim

| Property | Kind | Default |
|---|---|---|
| `clip` | string | `` |

### PlayMusic

| Property | Kind | Default |
|---|---|---|
| `file` | audio | `` |

### StopMusic

No properties.

### SaveGame

| Property | Kind | Default |
|---|---|---|
| `slot` | string | `save` |
| `names` | string | `` |

### LoadGame

| Property | Kind | Default |
|---|---|---|
| `slot` | string | `save` |
| `names` | string | `` |
