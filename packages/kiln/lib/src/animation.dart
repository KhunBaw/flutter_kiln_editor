import 'dart:math';

import 'package:flame/components.dart';

import 'game.dart';
import 'registry.dart';

/// Properties a keyframe track can drive, with the value a missing track leaves alone.
const animProps = ['x', 'y', 'angle', 'scaleX', 'scaleY', 'opacity'];

const animLoops = ['once', 'loop', 'pingpong'];

const animEases = ['linear', 'easeIn', 'easeOut', 'easeInOut', 'backOut', 'bounceOut', 'elasticOut', 'step'];

/// Maps progress [t] in 0..1 through the named curve; unknown names are linear.
double ease(String name, double t) {
  t = t.clamp(0.0, 1.0);
  return switch (name) {
    'easeIn' => t * t * t,
    'easeOut' => 1 - pow(1 - t, 3).toDouble(),
    'easeInOut' => t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3).toDouble() / 2,
    'backOut' => 1 + 2.70158 * pow(t - 1, 3) + 1.70158 * pow(t - 1, 2),
    'bounceOut' => _bounce(t),
    'elasticOut' =>
      t == 0 || t == 1 ? t : pow(2, -10 * t).toDouble() * sin((t * 10 - 0.75) * (2 * pi / 3)) + 1,
    'step' => t < 1 ? 0 : 1,
    _ => t,
  };
}

double _bounce(double t) {
  const n = 7.5625, d = 2.75;
  if (t < 1 / d) return n * t * t;
  if (t < 2 / d) return n * (t -= 1.5 / d) * t + 0.75;
  if (t < 2.5 / d) return n * (t -= 2.25 / d) * t + 0.9375;
  return n * (t -= 2.625 / d) * t + 0.984375;
}

/// One keyframe: value [v] at time [t] seconds, easing into the next key with [ease].
class KeyFrame {
  const KeyFrame(this.t, this.v, [this.ease = 'linear']);

  final double t;
  final double v;
  final String ease;

  Map<String, Object?> toJson() => {'t': t, 'v': v, if (ease != 'linear') 'ease': ease};
}

/// Lenient read of a track's `keys`: bad entries are dropped, result sorted by time.
List<KeyFrame> parseKeys(Object? raw) {
  final out = <KeyFrame>[];
  for (final k in raw is List ? raw : const []) {
    if (k is! Map || k['t'] is! num || k['v'] is! num) continue;
    final t = (k['t'] as num).toDouble(), v = (k['v'] as num).toDouble();
    if (!t.isFinite || !v.isFinite) continue;
    out.add(KeyFrame(max(0, t), v, k['ease'] is String ? k['ease'] as String : 'linear'));
  }
  return out..sort((a, b) => a.t.compareTo(b.t));
}

/// Value of a track at [time]: held before the first and after the last key, eased in between.
double? sampleKeys(List<KeyFrame> keys, double time) {
  if (keys.isEmpty) return null;
  if (time <= keys.first.t) return keys.first.v;
  if (time >= keys.last.t) return keys.last.v;
  var i = 0;
  while (keys[i + 1].t <= time) {
    i++;
  }
  final a = keys[i], b = keys[i + 1];
  final span = b.t - a.t;
  final u = span <= 0 ? 1.0 : (time - a.t) / span;
  return a.v + (b.v - a.v) * ease(a.ease, u);
}

/// Folds clock [time] into the clip: once clamps, loop wraps, pingpong mirrors.
double clipTime(double time, double duration, String loop) {
  if (duration <= 0 || time <= 0) return 0;
  return switch (loop) {
    'loop' => time % duration,
    'pingpong' => () {
      final m = time % (duration * 2);
      return m <= duration ? m : duration * 2 - m;
    }(),
    _ => min(time, duration),
  };
}

/// Sampled value of every track in [tracks] (the Animator `tracks` prop) at clip time [time].
Map<String, double> samplePose(Object? tracks, double time) {
  final out = <String, double>{};
  for (final tr in tracks is List ? tracks : const []) {
    if (tr is! Map || tr['prop'] is! String) continue;
    final v = sampleKeys(parseKeys(tr['keys']), time);
    if (v != null) out[tr['prop'] as String] = v;
  }
  return out;
}

/// Writes a sampled pose onto a live entity.
void applyPose(KilnEntity e, Map<String, double> pose) {
  if (pose['x'] case final v?) e.position.x = v;
  if (pose['y'] case final v?) e.position.y = v;
  if (pose['angle'] case final v?) e.angle = v;
  if (pose['scaleX'] case final v?) e.scale.x = v;
  if (pose['scaleY'] case final v?) e.scale.y = v;
  if (pose['opacity'] case final v?) e.alpha = v.clamp(0.0, 1.0);
}

/// Plays the keyframe tracks of an Animator behavior on its entity.
class AnimatorComponent extends Component with ParentIsA<KilnEntity> {
  AnimatorComponent(this.props);

  final Props props;
  double _clock = 0;
  bool playing = false;

  double get duration => max(0.05, props.number('duration'));

  void restart() {
    _clock = 0;
    playing = true;
    _apply();
  }

  void pause() => playing = false;

  void resume() => playing = true;

  @override
  void onMount() {
    super.onMount();
    // Editor preview is frozen: pose at the timeline's playhead instead of running.
    if (parent.game.editing) return seek(parent.game.poseTime);
    playing = props['autoplay'] != false;
    _apply();
  }

  /// Poses the entity at clip time [t] without playing.
  void seek(double t) {
    playing = false;
    applyPose(parent, samplePose(props['tracks'], t));
  }

  @override
  void update(double dt) {
    if (!playing) return;
    _clock += dt;
    if (props.string('loop') == 'once' && _clock >= duration) {
      _clock = duration;
      playing = false;
    }
    _apply();
  }

  void _apply() =>
      applyPose(parent, samplePose(props['tracks'], clipTime(_clock, duration, props.string('loop'))));
}
