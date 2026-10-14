# Kiln formulas

Generated from `lib/src/expr.dart`; do not edit by hand.

Start a text or number field with `=` to make it a formula, e.g. `=self.x + 20` or `=score * 2`.
`If.expr` and `Condition.expr` take a formula without the `=`.

## Values

- numbers `1`, `2.5`; text `'hi'` or `"hi"`; `true`, `false`, `null`; lists `[1, 2]`; maps `{'k': 1}`
- a game variable by name (`score`), or a loop local (`i`, `item`)
- `self` / `other` (the collision partner) with `.x .y .angle .width .height .vx .vy .spin .visible .name`, or the entity's own variables (`self.hp`, `self.state`, `self.stateTime`)
- `pointer.x`, `pointer.y`, `pointer.down` (needs an OnPointer or Joystick), `time` (seconds of play)
- `list[i]`, `map.key`, `map['key']`

## Operators

From tightest to loosest: `^` (power), unary `- !`, `* / %`, `+ -` (`+` joins text when either side is text), `< <= > >=`, `== !=`, `&&`, `||`, `cond ? a : b`.
Dividing by zero gives 0. A bad formula logs `kiln: expr ...` and gives `null`; it never stops the game.

## Functions

- `min(a, b)` — smaller of two numbers
- `max(a, b)` — larger of two numbers
- `abs(x)` — absolute value
- `floor(x)` — round down
- `round(x)` — round to nearest
- `sqrt(x)` — square root (0 for negatives)
- `sin(radians)` — sine
- `cos(radians)` — cosine
- `atan2(y, x)` — angle in radians
- `rand(a, b)` — random number from a up to b
- `randi(a, b)` — random whole number from a to b, both included
- `pick(list)` — random item of a list
- `len(x)` — length of a list, map or text
- `count('#tag')` — how many entities match a name or #tag
- `exists('Name')` — true when some entity matches
- `nearest('#tag')` — closest matching entity to self (null if none)
- `tile(c, r)` — tile number of the first tilemap at a cell (-1 outside)
- `cellX(x)` — tilemap column of a world x
- `cellY(y)` — tilemap row of a world y
- `dist(a, b)` — distance between two entities (entity, name or #tag)
