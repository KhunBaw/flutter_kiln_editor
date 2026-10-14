import 'package:flutter/material.dart';
import 'package:kiln/kiln.dart';

/// Map-board neutrals: one eleven-step ramp, the only greys the editor uses.
abstract final class Z {
  static const z0 = Color(0xFF0F110E);
  static const z1 = Color(0xFF161814);
  static const z2 = Color(0xFF1D1F1A);
  static const z3 = Color(0xFF252821);
  static const z4 = Color(0xFF30332B);
  static const z5 = Color(0xFF3D4137);
  static const z6 = Color(0xFF50554A);
  static const z7 = Color(0xFF6A6F62);
  static const z8 = Color(0xFF8E9286);
  static const z9 = Color(0xFFBDBFB4);
  static const z10 = Color(0xFFE8E6DC);

  /// Marker chit: selection and Play only.
  static const mark = Color(0xFFE9C548);

  /// Signal red: destructive and error only; kept clear of the logic rust hue.
  static const danger = Color(0xFFE8606A);
}

/// Counter families: every behavior type belongs to one.
enum Family {
  render('R', Color(0xFFC9B57A)),
  input('I', Color(0xFF7C93A8)),
  logic('L', Color(0xFFC96A42)),
  physics('P', Color(0xFF8B9958)),
  custom('C', Z.z8);

  const Family(this.letter, this.color);
  final String letter;
  final Color color;

  static Family of(String type) => switch (type) {
    'Shape' || 'Sprite' || 'SpriteAnimation' || 'Text' || 'Tween' || 'Camera' || 'Parallax' => render,
    'OnTap' || 'OnKey' => input,
    'Timer' || 'Spawner' || 'Condition' || 'Prefab' || 'OnEvent' || 'OffScreen' || 'OnLand' => logic,
    'Collider' || 'OnCollide' || 'Velocity' || 'Body' || 'Solid' => physics,
    _ => custom,
  };
}

/// One text size inside panels; rank comes from weight, case and rules.
abstract final class T {
  static const size = 13.0;
  static const body = TextStyle(fontFamily: 'Barlow', fontSize: size, height: 18 / size, color: Z.z10);
  static const value = TextStyle(
    fontFamily: 'Barlow',
    fontSize: size,
    color: Z.z10,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const label = TextStyle(
    fontFamily: 'BarlowSemiCondensed',
    fontSize: size,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.9,
    color: Z.z8,
  );
  static const head = TextStyle(
    fontFamily: 'BarlowSemiCondensed',
    fontSize: size,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.3,
    color: Z.z9,
  );
  static const code = TextStyle(
    fontFamily: 'BarlowSemiCondensed',
    fontSize: size,
    fontWeight: FontWeight.w600,
    color: Z.z8,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// Short face text for a behavior counter: its key factors.
String factorOf(BehaviorData b) {
  final p = Props(b.props);
  String n(String k) {
    final v = p.number(k);
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  return switch (b.type) {
    'Shape' => p.string('shape'),
    'Sprite' => p.string('image').isEmpty ? 'no image' : p.string('image'),
    'SpriteAnimation' => p.string('image').isEmpty ? 'no image' : '${n('cols')}×${n('rows')} · ${n('fps')} fps',
    'Camera' =>
      p.number('deadzoneW') == 0 && p.number('deadzoneH') == 0 ? 'follow' : 'zone ${n('deadzoneW')}×${n('deadzoneH')}',
    'OnKey' => '${p.string('key')} ${p.string('on')}',
    'OnEvent' => p.string('event'),
    'OffScreen' => 'leaves ${p.string('area')}',
    'Velocity' => '${n('vx')}·${n('vy')} px/s',
    'Body' => 'g ${n('gravity')}',
    'Solid' => p.flag('oneWay') ? 'one-way' : 'solid',
    'Parallax' => '×${n('factorX')}·${n('factorY')}',
    'Text' => p.string('text'),
    'Tween' => switch (p.string('kind')) {
      'rotateBy' => '${n('x')} rad / ${n('duration')}s',
      _ => '${n('x')}·${n('y')} / ${n('duration')}s',
    },
    'Timer' => '${n('interval')}s ${p['repeat'] == false ? '×1' : '∞'}',
    'Spawner' => '${p.string('prefab')} / ${n('interval')}s',
    'Condition' => '${p.string('variable')} ${p.string('op')} ${n('value')}',
    'Collider' => p.string('shape'),
    'OnTap' || 'OnCollide' || 'OnLand' => switch (p.list('actions').length) {
      1 => '1 case',
      final c => '$c cases',
    },
    'Prefab' => 'template',
    _ => '',
  };
}

ThemeData kilnTheme() {
  const r = BorderRadius.all(Radius.circular(2));
  OutlineInputBorder border(Color c) => OutlineInputBorder(
    borderRadius: r,
    borderSide: BorderSide(color: c),
  );
  final scheme = const ColorScheme.dark(
    surface: Z.z2,
    onSurface: Z.z10,
    primary: Z.mark,
    onPrimary: Z.z1,
    secondary: Z.z8,
    error: Z.danger,
    outline: Z.z4,
    surfaceContainerHighest: Z.z3,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Z.z1,
    fontFamily: 'Barlow',
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textTheme: const TextTheme(
      bodyMedium: T.body,
      bodySmall: T.body,
      bodyLarge: T.body,
      titleSmall: T.head,
      titleMedium: T.head,
      labelLarge: T.label,
    ),
    dividerTheme: const DividerThemeData(color: Z.z3, thickness: 1, space: 1),
    iconTheme: const IconThemeData(color: Z.z8, size: 16),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Z.z1,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      border: border(Z.z4),
      enabledBorder: border(Z.z4),
      focusedBorder: border(Z.mark),
      errorBorder: border(Z.danger),
      hintStyle: T.body.copyWith(color: Z.z7),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Z.mark,
      selectionColor: Z.mark.withValues(alpha: 0.32),
      selectionHandleColor: Z.mark,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(1),
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? Z.z6 : Z.z5),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Z.z0,
        border: Border.all(color: Z.z4),
        borderRadius: r,
      ),
      textStyle: T.body,
      waitDuration: const Duration(milliseconds: 500),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Z.z4,
      elevation: 0,
      contentTextStyle: T.body,
      behavior: SnackBarBehavior.floating,
      width: 420,
      shape: const RoundedRectangleBorder(borderRadius: r),
    ),
    // Overlays separate by a z4 rule and a tone step, never by shadow.
    dialogTheme: DialogThemeData(
      backgroundColor: Z.z2,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: const BorderSide(color: Z.z4),
      ),
      titleTextStyle: T.head.copyWith(color: Z.z10),
      contentTextStyle: T.body,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Z.z0,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: const BorderSide(color: Z.z4),
      ),
      textStyle: T.body,
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
    ),
    // Square marker box, not a pill: matches the 2px-corner world.
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(borderRadius: r),
      side: const BorderSide(color: Z.z6),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Z.mark : Z.z1),
      checkColor: const WidgetStatePropertyAll(Z.z1),
      overlayColor: const WidgetStatePropertyAll(Z.z4),
      visualDensity: VisualDensity.compact,
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? Z.z6 : Z.z9),
        overlayColor: const WidgetStatePropertyAll(Z.z4),
        textStyle: const WidgetStatePropertyAll(T.label),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: r)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
        minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? Z.z6 : Z.z8),
        overlayColor: const WidgetStatePropertyAll(Z.z4),
        iconSize: const WidgetStatePropertyAll(16),
        minimumSize: const WidgetStatePropertyAll(Size(28, 28)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: r)),
      ),
    ),
  );
}
