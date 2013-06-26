// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "package:expect/expect.dart";
import 'dart:async';
import 'dart:isolate';

var events = [];

body() {
  events.add("body entry");
  runAsync(() {
    events.add("run async body");
  });
  return 499;
}

handler(fun) {
  events.add("handler");
  runAsync(fun);
  events.add("handler done");
}

main() {
  // We keep a ReceivePort open until all tests are done. This way the VM will
  // hang if the callbacks are not invoked and the test will time out.
  var port = new ReceivePort();

  // Test that runAsync inside the runAsync-handler goes to the parent zone.
  var result = runZonedExperimental(body, onRunAsync: handler);
  events.add("after");
  runAsync(() {
    Expect.listEquals(
        ["body entry", "handler", "handler done", "after", "run async body"],
        events);
    port.close();
  });
}