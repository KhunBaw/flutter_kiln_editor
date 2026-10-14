import 'dart:io';

import 'package:flutter/services.dart';

/// Serves `<root>/<key>` from disk, so the editor can show images that are not bundled into it.
class DirBundle extends CachingAssetBundle {
  DirBundle(this.root);

  final String root;

  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(await File('$root/$key').readAsBytes());
}
