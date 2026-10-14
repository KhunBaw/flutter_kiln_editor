# wheel

Kiln example: prize wheel. Scene `assets/scenes/wheel.kiln.json` uses the built-in `Wheel` and `VarSprite`
behaviors; slices (label, image, drop weight) and the background come from game variables `slices` and
`background`. The scene's variables are the mock data (so it plays in the editor); the Flutter host
overrides them live from `lib/main.dart`.
