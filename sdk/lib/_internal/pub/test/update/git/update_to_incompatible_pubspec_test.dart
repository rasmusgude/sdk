// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub_tests;

import 'dart:io';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  initConfig();
  integration("updates Git packages to an incompatible pubspec", () {
    ensureGit();

    d.git('foo.git', [
      d.libDir('foo'),
      d.libPubspec('foo', '1.0.0')
    ]).create();

    d.appDir([{"git": "../foo.git"}]).create();

    pubInstall();

    d.dir(packagesPath, [
      d.dir('foo', [
        d.file('foo.dart', 'main() => "foo";')
      ])
    ]).validate();

    d.git('foo.git', [
      d.libDir('zoo'),
      d.libPubspec('zoo', '1.0.0')
    ]).commit();

    pubUpdate(error: 'The name you specified for your dependency, '
                     '"foo", doesn\'t match the name "zoo" in its pubspec.');

    d.dir(packagesPath, [
      d.dir('foo', [
        d.file('foo.dart', 'main() => "foo";')
      ])
    ]).validate();
  });
}