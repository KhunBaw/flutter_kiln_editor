import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:kiln/kiln.dart';

import 'editor_state.dart';
import 'theme.dart';
import 'widgets.dart';

const _propLabels = {
  'x': 'Position X',
  'y': 'Position Y',
  'angle': 'Rotation',
  'scaleX': 'Scale X',
  'scaleY': 'Scale Y',
  'opacity': 'Opacity',
};

const _easeLabels = {
  'linear': 'Linear',
  'easeIn': 'Ease in',
  'easeOut': 'Ease out',
  'easeInOut': 'Ease in-out',
  'backOut': 'Back out',
  'bounceOut': 'Bounce',
  'elasticOut': 'Elastic',
  'step': 'Step (hold)',
};

String propLabel(String p) => _propLabels[p] ?? p;

/// Angle tracks store radians but read in degrees.
double _show(String prop, double v) => prop == 'angle' ? v * 180 / math.pi : v;
double _store(String prop, double v) => prop == 'angle' ? v * math.pi / 180 : v;

String _fmt(String prop, double v) {
  final x = _show(prop, v);
  return x == x.roundToDouble() ? x.toInt().toString() : x.toStringAsFixed(2);
}

const _labelW = 208.0;
const _rowH = 28.0;
const _rulerH = 26.0;
const _padL = 16.0;
const _padR = 20.0;

/// Bottom dock: keyframe timeline for the selected entity's Animator.
class TimelineDock extends StatefulWidget {
  const TimelineDock(this.s, {super.key});

  final EditorState s;

  @override
  State<TimelineDock> createState() => _TimelineDockState();
}

class _TimelineDockState extends State<TimelineDock> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _clock = 0;
  bool _playing = false;
  final _focus = FocusNode(debugLabel: 'timeline');
  String? _drag;
  int _dragCount = 0;
  ({String prop, int index})? _dragKey;

  EditorState get s => widget.s;

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  BehaviorData? get _anim => EditorState.animatorOf(s.selected);

  void _tick(Duration now) {
    final a = _anim;
    if (a == null) return _stop();
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    final dur = EditorState.animDuration(a), loop = Props(a.props).string('loop');
    _clock += dt;
    if (loop == 'once' && _clock >= dur) {
      s.playhead.value = dur;
      return _stop();
    }
    s.playhead.value = clipTime(_clock, dur, loop);
  }

  void _stop() {
    _ticker.stop();
    if (mounted) setState(() => _playing = false);
  }

  void _toggle() {
    if (_playing) return _stop();
    final a = _anim;
    if (a == null) return;
    final dur = EditorState.animDuration(a);
    // Resume from where the playhead is (a finished once-clip restarts).
    _clock = s.playhead.value >= dur ? 0 : s.playhead.value;
    _last = Duration.zero;
    _ticker.start();
    setState(() => _playing = true);
  }

  void _seek(double t) {
    final a = _anim;
    if (a == null) return;
    _clock = t;
    s.playhead.value = ((t * 100).roundToDouble() / 100).clamp(0.0, EditorState.animDuration(a));
  }

  @override
  Widget build(BuildContext context) {
    if (!s.timelineOpen) return _collapsed();
    final e = s.selected, a = _anim;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, ev) {
        if (ev is! KeyDownEvent || e == null || a == null) return KeyEventResult.ignored;
        final k = s.selKey;
        if ((ev.logicalKey == LogicalKeyboardKey.delete || ev.logicalKey == LogicalKeyboardKey.backspace) &&
            k != null) {
          s.deleteKey(e, k.prop, k.index);
          return KeyEventResult.handled;
        }
        if (ev.logicalKey == LogicalKeyboardKey.space) {
          _toggle();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Z.z2,
          border: Border(top: BorderSide(color: Z.z4)),
        ),
        child: Column(
          children: [
            _resizeHandle(),
            _header(e, a),
            const Divider(),
            Expanded(
              child: e == null
                  ? _empty(
                      Icons.touch_app_outlined,
                      'Select an entity',
                      'Pick something in the scene or hierarchy to animate it.',
                    )
                  : a == null
                  ? _create(e)
                  : _body(e, a),
            ),
            if (e != null && a != null && s.selKey != null) _keyStrip(e, a, s.selKey!),
          ],
        ),
      ),
    );
  }

  Widget _collapsed() => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      color: Z.z2,
      border: Border(top: BorderSide(color: Z.z4)),
    ),
    child: Row(
      children: [
        const Icon(Icons.animation, size: 16, color: Z.z8),
        const SizedBox(width: 8),
        const Text('Timeline', style: T.head),
        const Spacer(),
        IconBtn(Icons.keyboard_arrow_up, 'Open timeline', () => s.setTimeline(open: true)),
      ],
    ),
  );

  Widget _resizeHandle() => MouseRegion(
    cursor: SystemMouseCursors.resizeUpDown,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => s.setTimeline(height: s.timelineHeight - d.delta.dy),
      child: const SizedBox(height: 5, width: double.infinity),
    ),
  );

  Widget _header(EntityNode? e, BehaviorData? a) {
    final p = a == null ? null : Props(a.props);
    final dur = a == null ? 1.0 : EditorState.animDuration(a);
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Icon(Icons.animation, size: 16, color: Z.z8),
            const SizedBox(width: 8),
            const Text('Timeline', style: T.head),
            const SizedBox(width: 12),
            IconBtn(Icons.skip_previous, 'Go to start', a == null ? null : () => _seek(0)),
            IconBtn(
              _playing ? Icons.pause : Icons.play_arrow,
              _playing ? 'Pause (Space)' : 'Preview (Space)',
              a == null ? null : _toggle,
              active: _playing,
            ),
            const SizedBox(width: 6),
            if (a != null)
              ValueListenableBuilder(
                valueListenable: s.playhead,
                builder: (_, t, _) => Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: t.toStringAsFixed(2),
                        style: T.title.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      TextSpan(text: '  /  ${dur.toStringAsFixed(2)}s', style: T.small),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 12),
            if (a != null && p != null)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 104,
                        child: Field(
                          'Length',
                          dur,
                          (v) => s.edit(
                            (_) => a.props['duration'] = math.max(0.05, v as double),
                            mergeKey: '${e!.id}.anim.len',
                          ),
                          parse: parseNumber,
                          scrub: 0.02,
                          suffix: 's',
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 204,
                        child: Seg(
                          options: animLoops,
                          value: p.string('loop').isEmpty ? 'loop' : p.string('loop'),
                          labels: const {'once': 'Once', 'loop': 'Loop', 'pingpong': 'Ping-pong'},
                          onChanged: (v) => s.edit((_) => a.props['loop'] = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Tooltip(
                        message: 'Autoplay: start when the scene loads',
                        child: Row(
                          children: [
                            const Icon(Icons.play_circle_outline, size: 15, color: Z.z8),
                            const SizedBox(width: 6),
                            Toggle(
                              value: a.props['autoplay'] != false,
                              onChanged: (v) => s.edit((_) => a.props['autoplay'] = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _addTrackMenu(e!, a),
                    ],
                  ),
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 4),
            IconBtn(Icons.keyboard_arrow_down, 'Collapse timeline', () {
              _stop();
              s.setTimeline(open: false);
            }),
          ],
        ),
      ),
    );
  }

  Widget _addTrackMenu(EntityNode e, BehaviorData a) {
    final free = [
      for (final p in animProps)
        if (!s.isAnimated(e, p)) p,
    ];
    return PopupMenuButton<String>(
      tooltip: 'Add track',
      enabled: free.isNotEmpty,
      position: PopupMenuPosition.under,
      onSelected: (p) => s.addTrack(e, p),
      itemBuilder: (_) => [for (final p in free) PopupMenuItem(value: p, height: 30, child: Text(propLabel(p)))],
      child: IgnorePointer(child: Cmd('Add track', free.isEmpty ? null : () {}, icon: Icons.add)),
    );
  }

  Widget _empty(IconData icon, String title, String body, {Widget? action}) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: Z.z6),
        const SizedBox(height: 8),
        Text(title, style: T.head),
        const SizedBox(height: 4),
        Text(body, style: T.label.copyWith(color: Z.z7)),
        if (action != null) ...[const SizedBox(height: 12), action],
      ],
    ),
  );

  Widget _create(EntityNode e) => _empty(
    Icons.animation,
    '${e.name} has no animation',
    'Add an Animator to key position, rotation, scale and opacity over time.',
    action: Cmd('Create animation', () => s.addAnimator(e), icon: Icons.add, primary: true),
  );

  // --- body -----------------------------------------------------------------------------------

  Widget _body(EntityNode e, BehaviorData a) {
    final tracks = EditorState.tracksOf(a);
    if (tracks.isEmpty) {
      return _empty(
        Icons.timeline,
        'No tracks yet',
        'Add a track, or press the key diamond next to a Transform value in the Inspector.',
        action: _addTrackMenu(e, a),
      );
    }
    final dur = EditorState.animDuration(a);
    return LayoutBuilder(
      builder: (context, box) {
        final laneW = math.max(120.0, box.maxWidth - _labelW);
        final pps = (laneW - _padL - _padR) / dur;
        double xOf(double t) => _padL + t * pps;
        double tOf(double x) => ((x - _padL) / pps).clamp(0.0, dur);
        return Column(
          children: [
            SizedBox(
              height: _rulerH,
              child: Row(
                children: [
                  Container(
                    width: _labelW,
                    padding: const EdgeInsets.only(left: 12),
                    alignment: Alignment.centerLeft,
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: Z.z3)),
                    ),
                    child: Text('${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}', style: T.small),
                  ),
                  Expanded(child: _ruler(dur, pps, tOf)),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _labelW,
                      child: Column(children: [for (final tr in tracks) _trackLabel(e, tr)]),
                    ),
                    SizedBox(width: laneW, height: tracks.length * _rowH, child: _lanes(e, tracks, dur, pps, xOf, tOf)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _ruler(double dur, double pps, double Function(double) tOf) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (d) => _seek(tOf(d.localPosition.dx)),
    onPanStart: (d) => _seek(tOf(d.localPosition.dx)),
    onPanUpdate: (d) => _seek(tOf(d.localPosition.dx)),
    child: Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _RulerPainter(dur, pps))),
        Positioned.fill(
          child: ValueListenableBuilder(
            valueListenable: s.playhead,
            builder: (_, t, _) => CustomPaint(painter: _HeadPainter(_padL + t * pps, handle: true)),
          ),
        ),
      ],
    ),
  );

  Widget _trackLabel(EntityNode e, Map<String, Object?> tr) {
    final prop = tr['prop'] as String;
    final sel = s.selKey?.prop == prop;
    return ValueListenableBuilder(
      valueListenable: s.playhead,
      builder: (_, t, _) {
        final v = sampleKeys(parseKeys(tr['keys']), t) ?? 0;
        final keyed = s.keyedAtPlayhead(e, prop);
        return Container(
          height: _rowH,
          padding: const EdgeInsets.only(left: 6, right: 4),
          decoration: BoxDecoration(
            color: sel ? Z.z3 : Colors.transparent,
            border: const Border(
              bottom: BorderSide(color: Z.z3),
              right: BorderSide(color: Z.z3),
            ),
          ),
          child: Row(
            children: [
              IconBtn(
                Icons.circle,
                keyed ? 'Remove key at playhead' : 'Add key at playhead',
                () => s.toggleKey(e, prop),
                active: keyed,
                size: 24,
                glyph: (c) => Diamond(color: keyed ? Z.accent : Z.z7, filled: keyed),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  propLabel(prop),
                  style: T.body.copyWith(color: sel ? Z.z10 : Z.z9),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(_fmt(prop, v), style: T.code),
              if (prop == 'angle') const Text('°', style: T.small),
              const SizedBox(width: 2),
              IconBtn(Icons.close, 'Remove track', () => s.removeTrack(e, prop), size: 22),
            ],
          ),
        );
      },
    );
  }

  Widget _lanes(
    EntityNode e,
    List<Map<String, Object?>> tracks,
    double dur,
    double pps,
    double Function(double) xOf,
    double Function(double) tOf,
  ) {
    ({String prop, int index})? hit(Offset p) {
      final row = (p.dy / _rowH).floor();
      if (row < 0 || row >= tracks.length) return null;
      final prop = tracks[row]['prop'] as String;
      final keys = parseKeys(tracks[row]['keys']);
      var best = -1;
      var bestD = 9.0;
      for (final (i, k) in keys.indexed) {
        final d = (xOf(k.t) - p.dx).abs();
        if (d < bestD) (best, bestD) = (i, d);
      }
      return best < 0 ? null : (prop: prop, index: best);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        _focus.requestFocus();
        final h = hit(d.localPosition);
        s.selectKey(h);
        if (h != null) _seek(parseKeys(tracks.firstWhere((t) => t['prop'] == h.prop)['keys'])[h.index].t);
      },
      onSecondaryTapDown: (d) {
        final row = (d.localPosition.dy / _rowH).floor();
        if (row < 0 || row >= tracks.length) return;
        final prop = tracks[row]['prop'] as String, t = tOf(d.localPosition.dx);
        showMenu<void>(
          context: context,
          position: RelativeRect.fromLTRB(
            d.globalPosition.dx,
            d.globalPosition.dy,
            d.globalPosition.dx,
            d.globalPosition.dy,
          ),
          items: [
            PopupMenuItem(
              height: 30,
              onTap: () {
                _seek(t);
                s.toggleKey(e, prop);
              },
              child: Text('Add ${propLabel(prop).toLowerCase()} key at ${t.toStringAsFixed(2)}s'),
            ),
          ],
        );
      },
      onPanStart: (d) {
        final h = hit(d.localPosition);
        _dragKey = h;
        _drag = 'key.drag${_dragCount++}';
        if (h != null) s.selectKey(h);
      },
      onPanUpdate: (d) {
        final k = _dragKey;
        // Dragging on empty lane scrubs the playhead; dragging a key moves it (⌥ turns snapping off).
        if (k == null) return _seek(tOf(d.localPosition.dx));
        var t = tOf(d.localPosition.dx);
        if (!HardwareKeyboard.instance.isAltPressed) t = (t / 0.05).roundToDouble() * 0.05;
        t = double.parse(t.clamp(0.0, dur).toStringAsFixed(3));
        final i = s.moveKey(e, k.prop, k.index, t, mergeKey: _drag);
        _dragKey = (prop: k.prop, index: i);
        s.selectKey(_dragKey);
        s.playhead.value = t;
        _clock = t;
      },
      onPanEnd: (_) => _dragKey = null,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _LanePainter(
                tracks: [for (final t in tracks) (t['prop'] as String, parseKeys(t['keys']))],
                dur: dur,
                pps: pps,
                selected: s.selKey,
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder(
                valueListenable: s.playhead,
                builder: (_, t, _) => CustomPaint(painter: _HeadPainter(_padL + t * pps)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- selected key strip ---------------------------------------------------------------------

  Widget _keyStrip(EntityNode e, BehaviorData a, ({String prop, int index}) k) {
    final tr = EditorState.tracksOf(a).where((t) => t['prop'] == k.prop).firstOrNull;
    final keys = tr == null ? const <KeyFrame>[] : parseKeys(tr['keys']);
    if (k.index >= keys.length) return const SizedBox.shrink();
    final key = keys[k.index];
    final mk = '${e.id}.${k.prop}.${k.index}';
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Z.z2,
        border: Border(top: BorderSide(color: Z.z3)),
      ),
      child: Row(
        children: [
          const Diamond(color: Z.accent, filled: true, size: 12),
          const SizedBox(width: 8),
          Text('${propLabel(k.prop)} key', style: T.head),
          const Spacer(),
          SizedBox(
            width: 124,
            child: Field(
              'Time',
              key.t,
              (v) {
                final i = s.moveKey(e, k.prop, k.index, math.max(0, v as double), mergeKey: '$mk.t');
                s.selectKey((prop: k.prop, index: i));
                _seek(v);
              },
              parse: parseNumber,
              scrub: 0.01,
              suffix: 's',
              compact: true,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 132,
            child: Field(
              'Value',
              _show(k.prop, key.v),
              (v) => s.editKey(e, k.prop, k.index, v: _store(k.prop, v as double), mergeKey: '$mk.v'),
              parse: parseNumber,
              scrub: k.prop == 'opacity' || k.prop.startsWith('scale') ? 0.01 : 1,
              suffix: k.prop == 'angle' ? '°' : null,
              compact: true,
            ),
          ),
          const SizedBox(width: 8),
          _easeMenu(key.ease, (v) => s.editKey(e, k.prop, k.index, ease: v)),
          const SizedBox(width: 8),
          IconBtn(Icons.delete_outline, 'Delete key (Del)', () => s.deleteKey(e, k.prop, k.index)),
        ],
      ),
    );
  }

  Widget _easeMenu(String current, ValueChanged<String> onPick) => PopupMenuButton<String>(
    tooltip: 'Easing into the next key',
    position: PopupMenuPosition.over,
    onSelected: onPick,
    itemBuilder: (_) => [
      for (final n in animEases)
        PopupMenuItem(
          value: n,
          height: 34,
          child: Row(
            children: [
              CustomPaint(size: const Size(28, 20), painter: _EaseGlyph(n, n == current)),
              const SizedBox(width: 10),
              Text(_easeLabels[n] ?? n, style: T.body.copyWith(color: n == current ? Z.accent : Z.z10)),
            ],
          ),
        ),
    ],
    child: Container(
      height: 28,
      width: 142,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: Z.z1, borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          CustomPaint(size: const Size(24, 16), painter: _EaseGlyph(current, true)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_easeLabels[current] ?? current, style: T.value, overflow: TextOverflow.ellipsis),
          ),
          const Icon(Icons.unfold_more, size: 14, color: Z.z7),
        ],
      ),
    ),
  );
}

/// Seconds ruler: major ticks with labels, minor ticks between.
class _RulerPainter extends CustomPainter {
  const _RulerPainter(this.dur, this.pps);

  final double dur, pps;

  @override
  void paint(Canvas canvas, Size size) {
    final step = const [0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0].firstWhere((s) => s * pps >= 64, orElse: () => 30.0);
    final minor = Paint()..color = Z.z5;
    final major = Paint()..color = Z.z6;
    final n = (dur / step).floor();
    for (var i = 0; i <= n; i++) {
      final x = _padL + i * step * pps;
      canvas.drawRect(Rect.fromLTWH(x, size.height - 10, 1, 10), major);
      final tp = TextPainter(
        text: TextSpan(text: '${(i * step).toStringAsFixed(step < 1 ? (step < 0.1 ? 2 : 2) : 0)}s', style: T.small),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 4, 4));
      for (var j = 1; j < 5; j++) {
        final mx = x + j * step * pps / 5;
        if (mx > _padL + dur * pps) break;
        canvas.drawRect(Rect.fromLTWH(mx, size.height - 5, 1, 5), minor);
      }
    }
    // End of clip.
    canvas.drawRect(Rect.fromLTWH(_padL + dur * pps, 0, 1, size.height), Paint()..color = Z.z6);
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.dur != dur || old.pps != pps;
}

class _HeadPainter extends CustomPainter {
  const _HeadPainter(this.x, {this.handle = false});

  final double x;
  final bool handle;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Z.accent;
    canvas.drawRect(Rect.fromLTWH(x - 0.5, 0, 1.5, size.height), p);
    if (handle) {
      final path = Path()
        ..moveTo(x - 6, 0)
        ..lineTo(x + 6.5, 0)
        ..lineTo(x + 6.5, 9)
        ..lineTo(x + 0.25, 15)
        ..lineTo(x - 6, 9)
        ..close();
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_HeadPainter old) => old.x != x;
}

class _LanePainter extends CustomPainter {
  const _LanePainter({required this.tracks, required this.dur, required this.pps, required this.selected});

  final List<(String, List<KeyFrame>)> tracks;
  final double dur, pps;
  final ({String prop, int index})? selected;

  @override
  void paint(Canvas canvas, Size size) {
    // Row stripes and one-second grid.
    for (var r = 0; r < tracks.length; r++) {
      if (r.isOdd) {
        canvas.drawRect(Rect.fromLTWH(0, r * _rowH, size.width, _rowH), Paint()..color = Z.z1.withValues(alpha: 0.45));
      }
      canvas.drawRect(Rect.fromLTWH(0, (r + 1) * _rowH - 1, size.width, 1), Paint()..color = Z.z3);
    }
    final step = const [0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0].firstWhere((s) => s * pps >= 64, orElse: () => 30.0);
    for (var i = 0; i <= (dur / step).floor(); i++) {
      canvas.drawRect(Rect.fromLTWH(_padL + i * step * pps, 0, 1, size.height), Paint()..color = Z.z3);
    }
    canvas.drawRect(Rect.fromLTWH(_padL + dur * pps, 0, 1, size.height), Paint()..color = Z.z5);

    for (final (r, (prop, keys)) in tracks.indexed) {
      final cy = r * _rowH + _rowH / 2;
      // Span between neighbouring keys: a rounded bar, dimmed when the value holds.
      for (var i = 0; i + 1 < keys.length; i++) {
        final a = keys[i], b = keys[i + 1];
        final held = a.v == b.v;
        final rect = RRect.fromLTRBR(
          _padL + a.t * pps,
          cy - 2.5,
          _padL + b.t * pps,
          cy + 2.5,
          const Radius.circular(2.5),
        );
        canvas.drawRRect(rect, Paint()..color = held ? Z.z4 : Z.accent.withValues(alpha: 0.28));
      }
      for (final (i, k) in keys.indexed) {
        final sel = selected?.prop == prop && selected?.index == i;
        final c = Offset(_padL + k.t * pps, cy);
        final d = sel ? 7.0 : 6.0;
        final path = Path()
          ..moveTo(c.dx, c.dy - d)
          ..lineTo(c.dx + d, c.dy)
          ..lineTo(c.dx, c.dy + d)
          ..lineTo(c.dx - d, c.dy)
          ..close();
        if (sel) {
          canvas.drawPath(
            path,
            Paint()
              ..color = Z.accent.withValues(alpha: 0.35)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5,
          );
        }
        canvas.drawPath(path, Paint()..color = sel ? Z.accent : Z.z9);
        canvas.drawPath(
          path,
          Paint()
            ..color = Z.z1
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LanePainter old) => true;
}

/// Tiny plot of an easing curve.
class _EaseGlyph extends CustomPainter {
  const _EaseGlyph(this.name, this.on);

  final String name;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final pad = 2.0;
    final w = size.width - pad * 2, h = size.height - pad * 2;
    for (var i = 0; i <= 24; i++) {
      final t = i / 24, v = ease(name, t);
      final p = Offset(pad + t * w, pad + h - v * h * 0.8 - h * 0.1);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = on ? Z.accent : Z.z8
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_EaseGlyph old) => old.name != name || old.on != on;
}
