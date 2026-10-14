import 'package:flutter/material.dart';
import 'package:kiln/kiln.dart';

/// Graphite neutrals: one cool ramp, the only greys the editor uses. Darker = further back.
abstract final class Z {
  static const z0 = Color(0xFF0D0E11);
  static const z1 = Color(0xFF121317);
  static const z2 = Color(0xFF181A1F);
  static const z3 = Color(0xFF1F2227);
  static const z4 = Color(0xFF292C33);
  static const z5 = Color(0xFF353943);
  static const z6 = Color(0xFF4A505C);
  static const z7 = Color(0xFF69707E);
  static const z8 = Color(0xFF8D94A3);
  static const z9 = Color(0xFFB9BECA);
  static const z10 = Color(0xFFE8EAF0);

  /// Ember: selection, focus, Play and the playhead.
  static const accent = Color(0xFFFF7A45);

  /// Ember at rest, for fills behind accent text.
  static const accentDim = Color(0x26FF7A45);

  /// Destructive and error only.
  static const danger = Color(0xFFF2555F);

  /// Soft separation under floating surfaces.
  static const shadow = [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))];
}

/// Behavior families: every behavior type belongs to one and shows its hue as an icon chip.
enum Family {
  render('Render', Icons.layers_outlined, Color(0xFF6FB1FF)),
  input('Input', Icons.touch_app_outlined, Color(0xFF5ED6A4)),
  logic('Logic', Icons.account_tree_outlined, Color(0xFFB58CFF)),
  physics('Physics', Icons.blur_circular_outlined, Color(0xFFFF8FA8)),
  motion('Motion', Icons.animation, Color(0xFFF2C94C)),
  custom('Custom', Icons.extension_outlined, Z.z8);

  const Family(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  static Family of(String type) => switch (type) {
    'Shape' ||
    'Sprite' ||
    'SpriteAnimation' ||
    'Text' ||
    'Camera' ||
    'Parallax' ||
    'Tilemap' ||
    'Hud' ||
    'Panel' ||
    'ProgressBar' ||
    'Wheel' ||
    'VarSprite' => render,
    'Tween' || 'Animator' => motion,
    'OnTap' || 'OnKey' || 'Move8' || 'GridMove' || 'Button' || 'Draggable' => input,
    'Timer' ||
    'Spawner' ||
    'Condition' ||
    'Prefab' ||
    'OnEvent' ||
    'OffScreen' ||
    'OnLand' ||
    'Health' ||
    'Dialogue' ||
    'DropZone' => logic,
    'Collider' ||
    'OnCollide' ||
    'Velocity' ||
    'Body' ||
    'Solid' ||
    'Follow' ||
    'Patrol' ||
    'Wander' ||
    'LookAt' => physics,
    _ => custom,
  };
}

/// Type scale: 12px working size, 11px for secondary, 13px for titles. Barlow throughout.
abstract final class T {
  static const size = 12.0;
  static const _tnum = [FontFeature.tabularFigures()];
  static const body = TextStyle(fontFamily: 'Barlow', fontSize: size, height: 16 / size, color: Z.z10);
  static const value = TextStyle(fontFamily: 'Barlow', fontSize: size, color: Z.z10, fontFeatures: _tnum);
  static const label = TextStyle(fontFamily: 'Barlow', fontSize: size, fontWeight: FontWeight.w500, color: Z.z8);
  static const small = TextStyle(fontFamily: 'Barlow', fontSize: 11, fontWeight: FontWeight.w500, color: Z.z7);
  static const head = TextStyle(
    fontFamily: 'Barlow',
    fontSize: size,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: Z.z9,
  );
  static const title = TextStyle(fontFamily: 'Barlow', fontSize: 13, fontWeight: FontWeight.w600, color: Z.z10);
  static const code = TextStyle(
    fontFamily: 'Barlow',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: Z.z8,
    fontFeatures: _tnum,
  );
}

/// Short summary of a behavior shown dim beside its name.
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
    'OnEvent' => p.string('store').isEmpty ? p.string('event') : '${p.string('event')} → ${p.string('store')}',
    'OffScreen' => 'leaves ${p.string('area')}',
    'Velocity' => '${n('vx')}·${n('vy')} px/s',
    'Body' => 'g ${n('gravity')}',
    'Solid' => p.flag('oneWay') ? 'one-way' : 'solid',
    'Parallax' => '×${n('factorX')}·${n('factorY')}',
    'Move8' => '${n('speed')} px/s ${p.string('keys')}',
    'Health' => '${n('hp')} hp',
    'Follow' || 'LookAt' => p.string('target'),
    'Patrol' => '${p.string('points').split(';').where((x) => x.trim().isNotEmpty).length} points',
    'Wander' => '${n('speed')} px/s',
    'Text' => p.string('text'),
    'Animator' => '${p.list('tracks').length} tracks · ${n('duration')}s',
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
    'Tilemap' =>
      '${n('cols')}×${(p.list('tiles').length / (p.number('cols') < 1 ? 1 : p.number('cols'))).ceil()} · ${n('tile')} px',
    'GridMove' => '${n('cell')} px',
    'Dialogue' => '${p.string('lines').split('|').length} lines',
    'Button' => p.string('label'),
    'ProgressBar' => '${p.string('variable')} / ${n('max')}',
    'DropZone' => p.string('accept').isEmpty ? 'any' : p.string('accept'),
    _ => '',
  };
}

ThemeData kilnTheme() {
  const r = BorderRadius.all(Radius.circular(4));
  OutlineInputBorder border(Color c) => OutlineInputBorder(
    borderRadius: r,
    borderSide: BorderSide(color: c),
  );
  final scheme = const ColorScheme.dark(
    surface: Z.z2,
    onSurface: Z.z10,
    primary: Z.accent,
    onPrimary: Z.z0,
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
    splashFactory: NoSplash.splashFactory,
    textTheme: const TextTheme(
      bodyMedium: T.body,
      bodySmall: T.body,
      bodyLarge: T.body,
      titleSmall: T.head,
      titleMedium: T.title,
      labelLarge: T.label,
    ),
    dividerTheme: const DividerThemeData(color: Z.z3, thickness: 1, space: 1),
    iconTheme: const IconThemeData(color: Z.z8, size: 16),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Z.z1,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      border: border(Z.z4),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(Z.accent),
      errorBorder: border(Z.danger),
      hintStyle: T.body.copyWith(color: Z.z7),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Z.accent,
      selectionColor: Z.accent.withValues(alpha: 0.32),
      selectionHandleColor: Z.accent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? Z.z6 : Z.z5),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Z.z0,
        border: Border.all(color: Z.z4),
        borderRadius: r,
      ),
      textStyle: T.body,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    dialogTheme: DialogThemeData(
      backgroundColor: Z.z2,
      elevation: 24,
      shadowColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        side: const BorderSide(color: Z.z4),
      ),
      titleTextStyle: T.title,
      contentTextStyle: T.body,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Z.z2,
      elevation: 16,
      shadowColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        side: const BorderSide(color: Z.z4),
      ),
      textStyle: T.body,
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(3))),
      side: const BorderSide(color: Z.z6),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Z.accent : Z.z1),
      checkColor: const WidgetStatePropertyAll(Z.z0),
      overlayColor: const WidgetStatePropertyAll(Z.z4),
      visualDensity: VisualDensity.compact,
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? Z.z6 : Z.z9),
        overlayColor: const WidgetStatePropertyAll(Z.z4),
        textStyle: const WidgetStatePropertyAll(T.head),
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
