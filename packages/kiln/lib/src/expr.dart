import 'dart:math';

import 'package:flame/components.dart' show Vector2;
import 'package:flutter/foundation.dart';

import 'builtins.dart';
import 'game.dart';

/// What a formula can see: global variables, the acting entity, the collision partner and loop locals.
class ExprScope {
  ExprScope(this.game, this.self, {this.other, this.locals = const {}});

  final KilnGame game;
  final KilnEntity self;
  final KilnEntity? other;
  final Map<String, Object?> locals;
}

typedef _Node = Object? Function(ExprScope s);

class _Compiled {
  const _Compiled(this.node, this.error);

  final _Node? node;
  final String? error;
}

final _cache = <String, _Compiled>{};

_Compiled _compile(String src) => _cache.putIfAbsent(src, () {
  try {
    return _Compiled(_Parser(src).parse(), null);
  } on FormatException catch (e) {
    return _Compiled(null, e.message);
  }
});

/// Parse error of formula [src] (without the leading `=`), or null when it is valid.
String? exprError(String src) => _compile(src).error;

/// Evaluates formula [src]. Never throws: a bad formula logs and yields null.
Object? evalExpr(String src, ExprScope scope) {
  final c = _compile(src);
  if (c.node == null) {
    debugPrint('kiln: expr "$src": ${c.error}');
    return null;
  }
  try {
    return c.node!(scope);
  } catch (err) {
    debugPrint('kiln: expr "$src": $err');
    return null;
  }
}

/// Spreadsheet-style truth: false, 0, null and "" are false.
bool truthy(Object? v) => switch (v) {
  null => false,
  bool b => b,
  num n => n != 0,
  String s => s.isNotEmpty,
  _ => true,
};

double _n(Object? v) => switch (v) {
  num n => n.toDouble(),
  true => 1,
  _ => 0,
};

String _str(Object? v) => switch (v) {
  double d when d == d.roundToDouble() && d.isFinite => d.toInt().toString(),
  null => '',
  _ => '$v',
};

/// Entity a formula value stands for: an entity, or a name / `#tag` string.
KilnEntity? _entity(ExprScope s, Object? v) => switch (v) {
  KilnEntity e => e,
  String t => s.game.targets(s.self, t, other: s.other).firstOrNull,
  _ => null,
};

Object? _field(Object? o, String k) => switch (o) {
  KilnEntity e => switch (k) {
    'x' => e.x,
    'y' => e.y,
    'angle' => e.angle,
    'width' => e.width,
    'height' => e.height,
    'vx' => e.motion?.v.x ?? 0.0,
    'vy' => e.motion?.v.y ?? 0.0,
    'spin' => e.motion?.spin ?? 0.0,
    'visible' => e.isVisible,
    'name' => e.node.name,
    _ => e.vars[k],
  },
  Map m => m[k],
  _ => null,
};

Object? _index(Object? o, Object? i) => switch (o) {
  List l when i is num => i >= 0 && i < l.length ? l[i.floor()] : null,
  Map m => m[_str(i)],
  _ => null,
};

/// Function table: arity checked at parse time so the editor can flag typos.
final _funcs = <String, (int, int, Object? Function(ExprScope s, List<Object?> a))>{
  'min': (2, 2, (s, a) => min(_n(a[0]), _n(a[1]))),
  'max': (2, 2, (s, a) => max(_n(a[0]), _n(a[1]))),
  'abs': (1, 1, (s, a) => _n(a[0]).abs()),
  'floor': (1, 1, (s, a) => _n(a[0]).floorToDouble()),
  'round': (1, 1, (s, a) => _n(a[0]).roundToDouble()),
  'sqrt': (1, 1, (s, a) => _n(a[0]) < 0 ? 0.0 : sqrt(_n(a[0]))),
  'sin': (1, 1, (s, a) => sin(_n(a[0]))),
  'cos': (1, 1, (s, a) => cos(_n(a[0]))),
  'atan2': (2, 2, (s, a) => atan2(_n(a[0]), _n(a[1]))),
  'rand': (2, 2, (s, a) => _n(a[0]) + kilnRng.nextDouble() * (_n(a[1]) - _n(a[0]))),
  'randi': (
    2,
    2,
    (s, a) {
      final lo = _n(a[0]).floor(), hi = _n(a[1]).floor();
      return (hi < lo ? lo : lo + kilnRng.nextInt(hi - lo + 1)).toDouble();
    },
  ),
  'pick': (
    1,
    1,
    (s, a) => a[0] is List && (a[0] as List).isNotEmpty ? (a[0] as List)[kilnRng.nextInt((a[0] as List).length)] : null,
  ),
  'len': (
    1,
    1,
    (s, a) => switch (a[0]) {
      List l => l.length.toDouble(),
      Map m => m.length.toDouble(),
      String t => t.length.toDouble(),
      _ => 0.0,
    },
  ),
  'count': (1, 1, (s, a) => s.game.targets(s.self, _str(a[0]), other: s.other).length.toDouble()),
  'exists': (1, 1, (s, a) => s.game.targets(s.self, _str(a[0]), other: s.other).isNotEmpty),
  'nearest': (1, 1, (s, a) => s.game.nearest(s.self, _str(a[0]))),
  'tile': (2, 2, (s, a) => (s.game.tilemaps.firstOrNull?.tileAt(_n(a[0]).floor(), _n(a[1]).floor()) ?? -1).toDouble()),
  'cellX': (1, 1, (s, a) => (s.game.tilemaps.firstOrNull?.cellAt(Vector2(_n(a[0]), 0)).$1 ?? 0).toDouble()),
  'cellY': (1, 1, (s, a) => (s.game.tilemaps.firstOrNull?.cellAt(Vector2(0, _n(a[0]))).$2 ?? 0).toDouble()),
  'dist': (
    2,
    2,
    (s, a) {
      final p = _entity(s, a[0]), q = _entity(s, a[1]);
      return p == null || q == null ? double.infinity : p.absoluteCenter.distanceTo(q.absoluteCenter);
    },
  ),
};

/// Recursive descent over a single string; every rule returns a closure over [ExprScope].
class _Parser {
  _Parser(this.src);

  final String src;
  int i = 0;

  _Node parse() {
    final n = _ternary();
    _ws();
    if (i < src.length) _fail('unexpected "${src[i]}"');
    return n;
  }

  Never _fail(String m) => throw FormatException('$m at ${i + 1}');

  void _ws() {
    while (i < src.length && src[i].trim().isEmpty) {
      i++;
    }
  }

  bool _eat(String t) {
    _ws();
    if (!src.startsWith(t, i)) return false;
    i += t.length;
    return true;
  }

  /// Like [_eat] but not when [t] is only the first half of a longer operator.
  bool _op(String t, [List<String> not = const []]) {
    _ws();
    if (!src.startsWith(t, i) || not.any((n) => src.startsWith(n, i))) return false;
    i += t.length;
    return true;
  }

  _Node _ternary() {
    final c = _or();
    if (!_eat('?')) return c;
    final a = _ternary();
    if (!_eat(':')) _fail('expected ":"');
    final b = _ternary();
    return (s) => truthy(c(s)) ? a(s) : b(s);
  }

  _Node _or() {
    var l = _and();
    while (_eat('||')) {
      final a = l, b = _and();
      l = (s) => truthy(a(s)) || truthy(b(s));
    }
    return l;
  }

  _Node _and() {
    var l = _eq();
    while (_eat('&&')) {
      final a = l, b = _eq();
      l = (s) => truthy(a(s)) && truthy(b(s));
    }
    return l;
  }

  _Node _eq() {
    var l = _rel();
    while (true) {
      final neg = _eat('!=');
      if (!neg && !_eat('==')) return l;
      final a = l, b = _rel();
      l = (s) => _equal(a(s), b(s)) != neg;
    }
  }

  static bool _equal(Object? a, Object? b) => a is num && b is num ? a.toDouble() == b.toDouble() : a == b;

  _Node _rel() {
    var l = _add();
    while (true) {
      final op = ['<=', '>=', '<', '>'].where(_eat).firstOrNull;
      if (op == null) return l;
      final a = l, b = _add();
      l = (s) {
        final x = _n(a(s)), y = _n(b(s));
        return switch (op) {
          '<=' => x <= y,
          '>=' => x >= y,
          '<' => x < y,
          _ => x > y,
        };
      };
    }
  }

  _Node _add() {
    var l = _mul();
    while (true) {
      final plus = _eat('+');
      if (!plus && !_eat('-')) return l;
      final a = l, b = _mul();
      l = (s) {
        final x = a(s), y = b(s);
        if (!plus) return _n(x) - _n(y);
        return x is String || y is String ? _str(x) + _str(y) : _n(x) + _n(y);
      };
    }
  }

  _Node _mul() {
    var l = _unary();
    while (true) {
      final op = ['*', '/', '%'].where(_eat).firstOrNull;
      if (op == null) return l;
      final a = l, b = _unary();
      l = (s) {
        final x = _n(a(s)), y = _n(b(s));
        return switch (op) {
          '*' => x * y,
          '/' => y == 0 ? 0.0 : x / y,
          _ => y == 0 ? 0.0 : x % y,
        };
      };
    }
  }

  _Node _unary() {
    if (_op('-')) {
      final a = _unary();
      return (s) => -_n(a(s));
    }
    if (_op('!', ['!='])) {
      final a = _unary();
      return (s) => !truthy(a(s));
    }
    return _pow();
  }

  _Node _pow() {
    final b = _postfix();
    if (!_eat('^')) return b;
    final e = _unary();
    return (s) => pow(_n(b(s)), _n(e(s))).toDouble();
  }

  _Node _postfix() {
    var n = _primary();
    while (true) {
      final a = n;
      if (_eat('[')) {
        final k = _ternary();
        if (!_eat(']')) _fail('expected "]"');
        n = (s) => _index(a(s), k(s));
      } else if (_op('.')) {
        final name = _ident() ?? _fail('expected a name after "."');
        n = (s) => _field(a(s), name);
      } else {
        return n;
      }
    }
  }

  String? _ident() {
    _ws();
    final m = RegExp(r'[A-Za-z_]\w*').matchAsPrefix(src, i);
    if (m == null) return null;
    i = m.end;
    return m[0];
  }

  _Node _primary() {
    _ws();
    if (i >= src.length) _fail('unexpected end');
    final c = src[i];
    if (_eat('(')) {
      final n = _ternary();
      if (!_eat(')')) _fail('expected ")"');
      return n;
    }
    if (c == "'" || c == '"') {
      final end = src.indexOf(c, i + 1);
      if (end < 0) _fail('unterminated string');
      final text = src.substring(i + 1, end);
      i = end + 1;
      return (s) => text;
    }
    if (_eat('[')) {
      final items = _list(']', _ternary);
      return (s) => [for (final n in items) n(s)];
    }
    if (_eat('{')) {
      final pairs = _list('}', () {
        final k = _ternary();
        if (!_eat(':')) _fail('expected ":"');
        return (k, _ternary());
      });
      return (s) => {for (final (k, v) in pairs) _str(k(s)): v(s)};
    }
    final num = RegExp(r'\d+(\.\d+)?').matchAsPrefix(src, i);
    if (num != null) {
      i = num.end;
      final v = double.parse(num[0]!);
      return (s) => v;
    }
    final name = _ident() ?? _fail('unexpected "$c"');
    if (_eat('(')) return _call(name);
    return switch (name) {
      'true' => (s) => true,
      'false' => (s) => false,
      'null' => (s) => null,
      'self' => (s) => s.self,
      'other' => (s) => s.other,
      'time' => (s) => s.game.time,
      'pointer' => (s) => {'x': s.game.pointer.x, 'y': s.game.pointer.y, 'down': s.game.pointerDown},
      _ => (s) => s.locals.containsKey(name) ? s.locals[name] : s.game.vars[name],
    };
  }

  /// Comma separated items up to [close] (the opening bracket is already consumed).
  List<T> _list<T>(String close, T Function() item) {
    final out = <T>[];
    if (_eat(close)) return out;
    do {
      out.add(item());
    } while (_eat(','));
    if (!_eat(close)) _fail('expected "$close"');
    return out;
  }

  _Node _call(String name) {
    final f = _funcs[name] ?? _fail('unknown function "$name"');
    final args = <_Node>[];
    if (!_eat(')')) {
      do {
        args.add(_ternary());
      } while (_eat(','));
      if (!_eat(')')) _fail('expected ")"');
    }
    if (args.length < f.$1 || args.length > f.$2) _fail('$name takes ${f.$1} argument(s)');
    return (s) => f.$3(s, [for (final a in args) a(s)]);
  }
}
