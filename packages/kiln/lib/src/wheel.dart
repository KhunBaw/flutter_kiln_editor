import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import 'builtins.dart' show loadKilnImage;
import 'game.dart';
import 'registry.dart' show Props;

class WheelSlice {
  const WheelSlice(this.label, {this.image = '', this.weight = 1, this.color = const Color(0xFFE8B04A)});

  final String label;
  final String image;

  /// Relative drop rate: 3 drops three times as often as 1; 0 never drops.
  final double weight;
  final Color color;
}

const _palette = [Color(0xFFE8B04A), Color(0xFF7FB7A4), Color(0xFFE8A0A8), Color(0xFFA9C4E8), Color(0xFFC8B6E8)];

/// Parses `label|image|weight|#RRGGBB;label|...` (only the label is required). Bad weights become 1,
/// bad colours fall back to a palette colour by position.
List<WheelSlice> parseSlices(String spec) {
  final out = <WheelSlice>[];
  for (final part in spec.split(RegExp(r'[;\n]'))) {
    final f = part.split('|').map((x) => x.trim()).toList();
    if (f.first.isEmpty) continue;
    final hex = f.length > 3 ? f[3].replaceFirst('#', '') : '';
    final c = int.tryParse(hex, radix: 16);
    out.add(
      WheelSlice(
        f.first,
        image: f.length > 1 ? f[1] : '',
        weight: f.length > 2 ? double.tryParse(f[2]) ?? 1 : 1,
        color: c == null || hex.length != 6 ? _palette[out.length % _palette.length] : Color(0xFF000000 | c),
      ),
    );
  }
  return out;
}

/// Slices from a JSON list of `{label, image, weight, color}` maps; bad entries are skipped.
List<WheelSlice> sliceList(List<Object?> items) {
  final out = <WheelSlice>[];
  for (final raw in items) {
    final m = Props(raw is Map<String, Object?> ? raw : const {});
    if (m.string('label').isEmpty) continue;
    final hex = m.string('color').replaceFirst('#', '');
    final c = int.tryParse(hex, radix: 16);
    out.add(
      WheelSlice(
        m.string('label'),
        image: m.string('image'),
        weight: m['weight'] is num ? m.number('weight') : 1,
        color: c == null || hex.length != 6 ? _palette[out.length % _palette.length] : Color(0xFF000000 | c),
      ),
    );
  }
  return out;
}

/// Weighted random index; negative weights count as 0, and all-zero weights fall back to uniform.
int pickWeighted(List<double> weights, Random rng) {
  assert(weights.isNotEmpty);
  final total = weights.fold<double>(0, (a, w) => a + max(0, w));
  if (total <= 0) return rng.nextInt(weights.length);
  var x = rng.nextDouble() * total;
  for (var i = 0; i < weights.length; i++) {
    x -= max(0, weights[i]);
    if (x < 0) return i;
  }
  return weights.length - 1; // float rounding
}

/// A prize wheel. Slices come from the game variable [variable] when it is set (the app can change it at
/// any time), else from the [spec] prop. Equal-size slices; the drop rate is each slice's weight.
/// Spinning turns the parent entity; put a pointer entity at the top. Ends by setting [resultVar]
/// to the winner's label and emitting `won` with its index, then shows a reveal (pulsing slice and a prize card)
/// for [revealTime] seconds.
///
/// Spins are limited by [limit] (0 = unlimited), or the number in game variable [limitVar] when set. Each spin
/// adds 1 to [spinsVar]; [leftVar] is kept at the spins remaining (`∞` when unlimited). A spin with none left
/// is refused and emits `nospins`.
class Wheel extends Component with ParentIsA<KilnEntity> {
  Wheel({
    required this.spec,
    required this.variable,
    required this.resultVar,
    required this.spinsVar,
    required this.leftVar,
    required this.limitVar,
    required this.limit,
    required this.revealTime,
    required this.spinTime,
    required this.minTurns,
    required this.spinEvent,
    Random? random,
  }) : _rng = random ?? Random();

  final Object? spec;
  final String variable, resultVar, spinsVar, leftVar, limitVar, spinEvent;
  final double limit, revealTime, spinTime, minTurns;
  final Random _rng;
  final _images = <String, ui.Image?>{};
  final _loading = <String>{};
  ui.VoidCallback? _off;
  Object? _parsedFrom = '\u0000';
  List<WheelSlice> _slices = const [];
  bool spinning = false;
  double _t = 0, _from = 0, _to = 0;
  int _winner = 0;
  WheelSlice? _won;
  double _reveal = double.infinity; // seconds since the spin ended

  List<WheelSlice> get slices {
    final v = variable.isEmpty ? null : parent.game.vars[variable];
    final src = v is List || (v is String && v.isNotEmpty) ? v : spec;
    if (!identical(src, _parsedFrom) && src != _parsedFrom) {
      _parsedFrom = src;
      _slices = switch (src) {
        List l => sliceList(l),
        String s => parseSlices(s),
        _ => const [],
      };
    }
    return _slices;
  }

  @override
  void onMount() {
    super.onMount();
    if (parent.game.editing) return;
    _off = parent.game.on(spinEvent, (_) => spin());
  }

  @override
  void onRemove() => _off?.call();

  /// Spins still allowed; null when unlimited.
  int? get left {
    final v = parent.game.vars[limitVar];
    final max = v is num ? v : limit;
    if (max <= 0) return null;
    return (max - parent.game.vars.number(spinsVar)).clamp(0, double.infinity).toInt();
  }

  /// Picks the winner by weight now, then animates to it; ignored while spinning or with no slices.
  void spin() {
    final list = slices;
    if (spinning || list.isEmpty) return;
    if (left == 0) return parent.game.emit('nospins');
    _reveal = double.infinity;
    final vars = parent.game.vars;
    if (spinsVar.isNotEmpty) vars[spinsVar] = vars.number(spinsVar) + 1;
    final s = 2 * pi / list.length;
    _winner = pickWeighted([for (final x in list) x.weight], _rng);
    // Land inside the slice, off the edges so the pointer never sits on a line.
    final target = -((_winner + 0.5) * s + (_rng.nextDouble() - 0.5) * s * 0.7);
    _from = parent.angle;
    _to = _from + minTurns * 2 * pi + (target - _from) % (2 * pi);
    _t = 0;
    spinning = true;
    parent.game.emit('spinning');
  }

  @override
  void update(double dt) {
    final vars = parent.game.vars;
    if (!parent.game.editing && leftVar.isNotEmpty) vars[leftVar] = left ?? '∞';
    if (!spinning) {
      _reveal += dt;
      return;
    }
    _t += dt;
    final k = min(1.0, _t / max(0.01, spinTime));
    parent.angle = _from + (_to - _from) * (1 - pow(1 - k, 3));
    if (k < 1) return;
    spinning = false;
    final list = slices;
    _won = list.isEmpty ? null : list[min(_winner, list.length - 1)];
    _reveal = 0;
    if (resultVar.isNotEmpty && _won != null) vars[resultVar] = _won!.label;
    parent.game.emit('won', value: _winner);
  }

  ui.Image? _image(String name) {
    if (name.isEmpty) return null;
    if (_images.containsKey(name)) return _images[name];
    if (_loading.add(name)) {
      loadKilnImage(parent, 'Wheel', name).then((img) => _images[name] = img);
    }
    return null;
  }

  @override
  void render(ui.Canvas canvas) {
    final list = slices;
    if (list.isEmpty) return;
    final size = parent.size;
    final r = min(size.x, size.y) / 2;
    final s = 2 * pi / list.length;
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    final rect = Rect.fromCircle(center: Offset.zero, radius: r);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x66000000);
    for (var i = 0; i < list.length; i++) {
      canvas.drawArc(rect, -pi / 2 + i * s, s, true, Paint()..color = list[i].color);
      canvas.drawArc(rect, -pi / 2 + i * s, s, true, line);
      if (i == _winner && _reveal < revealTime) {
        final pulse = 0.5 + 0.5 * sin(_reveal * 12);
        canvas.drawArc(rect, -pi / 2 + i * s, s, true, Paint()..color = Color.fromRGBO(255, 255, 255, 0.55 * pulse));
      }
    }
    final icon = min(r * 0.32, 2 * 0.65 * r * sin(s / 2) * 0.9);
    for (var i = 0; i < list.length; i++) {
      canvas.save();
      canvas.rotate((i + 0.5) * s); // slice centre points up, so "radial up" is the text direction
      final img = _image(list[i].image);
      if (img != null) {
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromCenter(center: Offset(0, -r * 0.65), width: icon, height: icon),
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
      _label(canvas, list[i].label, Offset(0, -r * (img == null ? 0.6 : 0.32)), min(18, icon * 0.5 + 6));
      canvas.restore();
    }
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0xFFE8E4D8),
    );
    canvas.drawCircle(Offset.zero, r * 0.08, Paint()..color = const Color(0xFFE8E4D8));
    if (_won != null && _reveal < revealTime) {
      canvas.rotate(-parent.angle); // the card stays upright while the wheel is turned
      _card(canvas, _won!, r);
    }
    canvas.restore();
  }

  /// Pops in with an overshoot, holds, then fades out near the end of [revealTime].
  void _card(ui.Canvas canvas, WheelSlice prize, double r) {
    final t = min(1.0, _reveal / 0.45);
    final scale = 1 + 2.70158 * pow(t - 1, 3) + 1.70158 * pow(t - 1, 2); // easeOutBack
    final fade = min(1.0, (revealTime - _reveal) / 0.4);
    final a = (fade * 255).round();
    canvas.save();
    canvas.scale(max(0.0, scale));
    final card = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: r * 1.3, height: r * 1.3),
      Radius.circular(r * 0.14),
    );
    canvas.drawRRect(card, Paint()..color = Color.fromARGB((a * 0.92).round(), 22, 24, 20));
    canvas.drawRRect(
      card,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = prize.color.withAlpha(a),
    );
    _label(canvas, 'YOU GOT', Offset(0, -r * 0.5), 15, const Color(0xFFB8B4A8), a);
    final img = _image(prize.image);
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromCenter(center: Offset(0, -r * 0.08), width: r * 0.62, height: r * 0.62),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromARGB(a, 255, 255, 255),
      );
    }
    _label(canvas, prize.label, Offset(0, r * 0.42), 26, const Color(0xFFFFFFFF), a);
    canvas.restore();
  }

  // shortcut: lays out text every frame; fine for a dozen slices, cache the painters if slices get many.
  void _label(ui.Canvas canvas, String text, Offset at, double fontSize, [Color? color, int alpha = 255]) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: (color ?? const Color(0xFF161814)).withAlpha(alpha),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 140);
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }
}

/// Draws the image whose file name is in game variable [variable] (the app can swap it live),
/// cropped to cover the entity; [image] is the fallback. Draws nothing while empty or loading.
class VarSprite extends Component with ParentIsA<KilnEntity> {
  VarSprite({required this.variable, required this.image});

  final String variable, image;
  final _images = <String, ui.Image?>{};
  final _loading = <String>{};

  @override
  void render(ui.Canvas canvas) {
    final v = parent.game.vars.string(variable);
    final name = v.isEmpty ? image : v;
    if (name.isEmpty) return;
    if (!_images.containsKey(name) && _loading.add(name)) {
      loadKilnImage(parent, 'VarSprite', name).then((img) => _images[name] = img);
    }
    final img = _images[name];
    if (img == null) return;
    final w = parent.size.x, h = parent.size.y;
    final scale = max(w / img.width, h / img.height);
    final cw = w / scale, ch = h / scale;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH((img.width - cw) / 2, (img.height - ch) / 2, cw, ch),
      Rect.fromLTWH(0, 0, w, h),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }
}
