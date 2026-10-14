import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Square icon button with hover, active and disabled states; always carries a tooltip.
class IconBtn extends StatefulWidget {
  const IconBtn(
    this.icon,
    this.tooltip,
    this.onPressed, {
    super.key,
    this.active = false,
    this.color,
    this.size = 28,
    this.glyph,
  });

  final IconData icon;

  /// Replaces the icon with a custom glyph drawn in the resolved colour.
  final Widget Function(Color color)? glyph;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final Color? color;
  final double size;

  @override
  State<IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onPressed != null;
    final fg = !on ? Z.z6 : widget.color ?? (widget.active ? Z.accent : (_hover ? Z.z10 : Z.z8));
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.active && on ? Z.accentDim : (_hover && on ? Z.z4 : Colors.transparent),
              borderRadius: BorderRadius.circular(4),
            ),
            child: widget.glyph?.call(fg) ?? Icon(widget.icon, size: 16, color: fg),
          ),
        ),
      ),
    );
  }
}

/// Text command with an optional leading icon; [primary] fills it with the accent.
class Cmd extends StatefulWidget {
  const Cmd(
    this.label,
    this.onPressed, {
    super.key,
    this.icon,
    this.primary = false,
    this.danger = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool danger;
  final String? tooltip;

  @override
  State<Cmd> createState() => _CmdState();
}

class _CmdState extends State<Cmd> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onPressed != null;
    final fg = !on
        ? Z.z6
        : widget.primary
        ? Z.z0
        : widget.danger
        ? Z.danger
        : (_hover ? Z.z10 : Z.z9);
    final bg = widget.primary
        ? (_hover ? const Color(0xFFFF8F62) : Z.accent)
        : widget.danger
        ? (_hover ? Z.danger.withValues(alpha: 0.16) : Z.danger.withValues(alpha: 0.08))
        : (_hover && on ? Z.z4 : Z.z3);
    final child = MouseRegion(
      cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 28,
          padding: EdgeInsets.symmetric(horizontal: widget.icon == null ? 12 : 10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 16, color: fg), const SizedBox(width: 6)],
              Text(widget.label, style: T.head.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
    return widget.tooltip == null ? child : Tooltip(message: widget.tooltip!, child: child);
  }
}

/// Segmented choice for short option lists.
class Seg extends StatelessWidget {
  const Seg({super.key, required this.options, required this.value, required this.onChanged, this.labels});

  final List<String> options;
  final String? value;
  final ValueChanged<String> onChanged;
  final Map<String, String>? labels;

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(color: Z.z1, borderRadius: BorderRadius.circular(5)),
    child: Row(
      children: [
        for (final o in options)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(o),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: o == value ? Z.z4 : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    labels?[o] ?? o,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.label.copyWith(color: o == value ? Z.z10 : Z.z8),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// On/off switch, 30×16.
class Toggle extends StatelessWidget {
  const Toggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        width: 30,
        height: 16,
        padding: const EdgeInsets.all(2),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(color: value ? Z.accent : Z.z5, borderRadius: BorderRadius.circular(8)),
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: value ? Z.z0 : Z.z9, shape: BoxShape.circle),
        ),
      ),
    ),
  );
}

/// Small family icon chip used by hierarchy rows, behavior cards and menus.
class FamilyChip extends StatelessWidget {
  const FamilyChip(this.family, {super.key, this.size = 22});

  final Family family;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: family.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(5)),
    child: Icon(family.icon, size: size * 0.62, color: family.color),
  );
}

/// Parses user text into a value; null rejects it (not committed).
typedef Parse = Object? Function(String text);

String fmtNum(Object? v) => switch (v) {
  null => '',
  double d when d.isFinite && d == d.roundToDouble() => d.toInt().toString(),
  double d when d.isFinite => double.parse(d.toStringAsFixed(3)).toString(),
  _ => '$v',
};

/// Row shell: fixed label column, control, and a reserved slot for the reset button.
class Row2 extends StatelessWidget {
  const Row2(this.label, this.child, {super.key, this.onReset, this.hint});

  final String label;
  final Widget child;
  final VoidCallback? onReset;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 88,
          child: Row(
            children: [
              if (onReset != null)
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: const BoxDecoration(color: Z.accent, shape: BoxShape.circle),
                ),
              Expanded(
                child: Text(label, style: T.label, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        Expanded(child: child),
        SizedBox(
          width: 22,
          child: onReset == null ? null : IconBtn(Icons.restart_alt, 'Reset to default', onReset, size: 22),
        ),
      ],
    ),
  );
}

/// Text field that commits on every valid keystroke and re-syncs when the doc changes underneath (undo).
/// With [scrub] set, dragging the label changes the number (⇧ ×10, ⌥ ÷10).
class Field extends StatefulWidget {
  const Field(
    this.label,
    this.value,
    this.onChanged, {
    super.key,
    this.parse,
    this.leading,
    this.trailing,
    this.hint,
    this.scrub,
    this.suffix,
    this.compact = false,
    this.onReset,
  });

  final String label;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  /// Returns null for invalid input (not committed). Defaults to the raw string.
  final Object? Function(String text)? parse;
  final Widget? leading;
  final Widget? trailing;
  final String? hint;

  /// Units per pixel of horizontal drag on the label; null disables scrubbing.
  final double? scrub;
  final String? suffix;

  /// Label sits inside the field (for x/y/w/h pairs) instead of in a label column.
  final bool compact;
  final VoidCallback? onReset;

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  late final _c = TextEditingController(text: fmtNum(widget.value));
  final _focus = FocusNode();
  double _scrubFrom = 0, _scrubDx = 0;
  bool _scrubbing = false;

  Object? _parse(String t) => widget.parse == null ? t : widget.parse!(t);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
      } else if (_parse(_c.text) == null) {
        _c.text = fmtNum(widget.value);
      }
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(Field old) {
    super.didUpdateWidget(old);
    if (fmtNum(_parse(_c.text)) != fmtNum(widget.value)) _c.text = fmtNum(widget.value);
  }

  @override
  void dispose() {
    _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  Widget _label() {
    final text = Text(widget.label, style: T.label.copyWith(color: _scrubbing ? Z.accent : Z.z7));
    if (widget.scrub == null) return text;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          _scrubFrom = (widget.value as num?)?.toDouble() ?? 0;
          _scrubDx = 0;
          setState(() => _scrubbing = true);
          _focus.unfocus();
        },
        onHorizontalDragUpdate: (d) {
          _scrubDx += d.delta.dx;
          final k = HardwareKeyboard.instance.isShiftPressed
              ? 10.0
              : HardwareKeyboard.instance.isAltPressed
              ? 0.1
              : 1.0;
          var v = _scrubFrom + _scrubDx * widget.scrub! * k;
          v = widget.scrub! >= 1 && k >= 1 ? v.roundToDouble() : double.parse(v.toStringAsFixed(2));
          if (v != widget.value) widget.onChanged(v);
        },
        onHorizontalDragEnd: (_) => setState(() => _scrubbing = false),
        onHorizontalDragCancel: () => setState(() => _scrubbing = false),
        child: text,
      ),
    );
  }

  Widget _input() => TextField(
    controller: _c,
    focusNode: _focus,
    style: T.value,
    textAlignVertical: TextAlignVertical.center,
    decoration: InputDecoration(
      hintText: widget.hint,
      suffixText: widget.suffix,
      suffixStyle: T.small,
      suffixIcon: null,
      prefixIcon: widget.compact
          ? Padding(
              padding: const EdgeInsets.only(left: 8, right: 6),
              child: Center(widthFactor: 1, heightFactor: 1, child: _label()),
            )
          : null,
      prefixIconConstraints: const BoxConstraints(),
      contentPadding: EdgeInsets.fromLTRB(widget.compact ? 0 : 8, 6, 8, 6),
      fillColor: _focus.hasFocus ? Z.z0 : Z.z1,
    ),
    onChanged: (t) {
      final v = _parse(t);
      if (v != null && v != widget.value) widget.onChanged(v);
    },
  );

  @override
  Widget build(BuildContext context) {
    final field = Row(
      children: [
        ?widget.leading,
        Expanded(child: _input()),
        ?widget.trailing,
      ],
    );
    if (widget.compact) return field;
    return Row2(widget.label, field, onReset: widget.onReset);
  }
}

Object? parseNumber(String t) {
  final d = double.tryParse(t);
  return d != null && d.isFinite ? d : null;
}

/// Two controls side by side.
class Pair extends StatelessWidget {
  const Pair(this.a, this.b, {super.key});

  final Widget a, b;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: 6),
        Expanded(child: b),
      ],
    ),
  );
}

/// Colour picker popover: saturation/value square, hue and alpha strips, hex field and swatches.
Future<void> showColorPicker(
  BuildContext context, {
  required Rect anchor,
  required Color color,
  required ValueChanged<Color> onChanged,
}) {
  const w = 232.0;
  final size = MediaQuery.sizeOf(context);
  final left = (anchor.right - w).clamp(8.0, size.width - w - 8);
  final top = anchor.bottom + 6 + 290 > size.height ? anchor.top - 6 - 290 : anchor.bottom + 6;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close colour picker',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    transitionBuilder: (context, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: child,
    ),
    pageBuilder: (context, _, _) => Stack(
      children: [
        Positioned(
          left: left,
          top: math.max(8, top),
          width: w,
          child: Material(
            color: Z.z2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Z.z4),
            ),
            elevation: 16,
            shadowColor: Colors.black,
            child: _ColorPicker(color: color, onChanged: onChanged),
          ),
        ),
      ],
    ),
  );
}

class _ColorPicker extends StatefulWidget {
  const _ColorPicker({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color);
  late final _hex = TextEditingController(text: colorHex(widget.color));

  static const swatches = [
    Color(0xFFFFFFFF),
    Color(0xFF9AA0AE),
    Color(0xFF30333B),
    Color(0xFF000000),
    Color(0xFFFF7A45),
    Color(0xFFF2C94C),
    Color(0xFF5ED6A4),
    Color(0xFF6FB1FF),
    Color(0xFFB58CFF),
    Color(0xFFFF8FA8),
    Color(0xFFF2555F),
    Color(0xFF4488FF),
  ];

  void _set(HSVColor c, {bool hex = true}) {
    setState(() => _hsv = c);
    final out = c.toColor();
    if (hex) _hex.text = colorHex(out);
    widget.onChanged(out);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 130,
            child: _Drag(
              onUpdate: (p, size) => _set(
                _hsv.withSaturation((p.dx / size.width).clamp(0, 1)).withValue(1 - (p.dy / size.height).clamp(0, 1)),
              ),
              builder: (size) => CustomPaint(painter: _SvPainter(_hsv), size: size),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 12,
            child: _Drag(
              onUpdate: (p, size) => _set(_hsv.withHue((p.dx / size.width).clamp(0, 1) * 359.99)),
              builder: (size) => CustomPaint(
                painter: _StripPainter(_hsv.hue / 359.99, hue: true, base: _hsv),
                size: size,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 12,
            child: _Drag(
              onUpdate: (p, size) => _set(_hsv.withAlpha((p.dx / size.width).clamp(0, 1))),
              builder: (size) => CustomPaint(
                painter: _StripPainter(_hsv.alpha, hue: false, base: _hsv),
                size: size,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _hsv.toColor(),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Z.z5),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _hex,
                  style: T.value,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(9),
                  ],
                  decoration: const InputDecoration(
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(left: 8, right: 4),
                      child: Text('HEX', style: T.small),
                    ),
                    prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                  ),
                  onChanged: (t) {
                    final c = parseColor(t);
                    if (c != null) {
                      setState(() => _hsv = HSVColor.fromColor(c));
                      widget.onChanged(c);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in swatches)
                GestureDetector(
                  onTap: () => _set(HSVColor.fromColor(c)),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Z.z5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Drag extends StatelessWidget {
  const _Drag({required this.onUpdate, required this.builder});

  final void Function(Offset p, Size size) onUpdate;
  final Widget Function(Size size) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      return MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: GestureDetector(
          onPanStart: (d) => onUpdate(d.localPosition, size),
          onPanUpdate: (d) => onUpdate(d.localPosition, size),
          onTapDown: (d) => onUpdate(d.localPosition, size),
          child: builder(size),
        ),
      );
    },
  );
}

class _SvPainter extends CustomPainter {
  const _SvPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(5));
    canvas.save();
    canvas.clipRRect(r);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()])
            .createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    canvas.restore();
    final at = Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas.drawCircle(
      at,
      6,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      at,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SvPainter old) => old.hsv != hsv;
}

class _StripPainter extends CustomPainter {
  const _StripPainter(this.t, {required this.hue, required this.base});

  final double t;
  final bool hue;
  final HSVColor base;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.save();
    canvas.clipRRect(r);
    if (hue) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            colors: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble() % 360, 1, 1).toColor()],
          ).createShader(Offset.zero & size),
      );
    } else {
      final cell = size.height / 2;
      final dark = Paint()..color = Z.z4;
      for (var x = 0.0; x < size.width; x += cell) {
        for (var y = 0; y < 2; y++) {
          if (((x / cell).floor() + y).isEven) canvas.drawRect(Rect.fromLTWH(x, y * cell, cell, cell), dark);
        }
      }
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(colors: [base.withAlpha(0).toColor(), base.withAlpha(1).toColor()])
              .createShader(Offset.zero & size),
      );
    }
    canvas.restore();
    final x = (t * size.width).clamp(size.height / 2, size.width - size.height / 2);
    canvas.drawCircle(
      Offset(x, size.height / 2),
      size.height / 2 + 1,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      Offset(x, size.height / 2),
      size.height / 2 + 1,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_StripPainter old) => old.t != t || old.base != base;
}

/// `#RRGGBB`, or `#AARRGGBB` when translucent (the format `Props.color` reads).
String colorHex(Color c) {
  final v = c.toARGB32();
  final rgb = (v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  return c.a >= 0.999 ? '#$rgb' : '#${(v >> 24).toRadixString(16).padLeft(2, '0').toUpperCase()}$rgb';
}

Color? parseColor(String t) {
  final hex = t.replaceFirst('#', '');
  final v = int.tryParse(hex, radix: 16);
  if (v == null || (hex.length != 6 && hex.length != 8)) return null;
  return Color(hex.length == 6 ? 0xFF000000 | v : v);
}

/// Keyframe diamond: a rotated square, filled when a key sits here, outlined otherwise.
class Diamond extends StatelessWidget {
  const Diamond({super.key, required this.color, this.filled = false, this.size = 11});

  final Color color;
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _DiamondPainter(color, filled)),
    ),
  );
}

class _DiamondPainter extends CustomPainter {
  const _DiamondPainter(this.color, this.filled);

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2 - (filled ? 0 : 0.75);
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r, c.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_DiamondPainter old) => old.color != color || old.filled != filled;
}
