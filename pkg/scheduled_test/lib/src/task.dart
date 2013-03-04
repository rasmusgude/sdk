// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library task;

import 'dart:async';
import 'dart:collection';

import 'future_group.dart';
import 'schedule.dart';
import 'utils.dart';

typedef Future TaskBody();

/// A single task to be run as part of a [TaskQueue].
///
/// There are two levels of tasks. **Top-level tasks** are created by calling
/// [TaskQueue.schedule] before the queue in question is running. They're run in
/// sequence as part of that [TaskQueue]. **Nested tasks** are created by
/// calling [TaskQueue.schedule] once the queue is already running, and are run
/// in parallel as part of a top-level task.
class Task {
  /// The queue to which this [Task] belongs.
  final TaskQueue queue;

  // TODO(nweiz): make this a read-only view when issue 8321 is fixed.
  /// Child tasks that have been spawned while running this task. This will be
  /// empty if this task is a nested task.
  final children = new Queue<Task>();

  /// A [FutureGroup] that will complete once all current child tasks are
  /// finished running. This will be null if no child tasks are currently
  /// running.
  FutureGroup _childGroup;

  /// A description of this task. Used for debugging. May be `null`.
  final String description;

  /// The parent task, if this is a nested task that was started while another
  /// task was running. This will be `null` for top-level tasks.
  final Task parent;

  /// The body of the task.
  TaskBody fn;

  /// The identifier of the task. For top-level tasks, this is the index of the
  /// task within [queue]; for nested tasks, this is the index within
  /// [parent.children]. It's used for debugging when [description] isn't
  /// provided.
  int _id;

  /// A Future that will complete to the return value of [fn] once this task
  /// finishes running.
  Future get result => _resultCompleter.future;
  final _resultCompleter = new Completer();

  Task(fn(), String description, TaskQueue queue)
    : this._(fn, description, queue, null, queue.contents.length);

  Task._child(fn(), String description, Task parent)
    : this._(fn, description, parent.queue, parent, parent.children.length);

  Task._(fn(), this.description, this.queue, this.parent, this._id) {
    this.fn = () {
      var future = new Future.immediate(null).then((_) => fn())
          .whenComplete(() {
        if (_childGroup == null || _childGroup.completed) return;
        return _childGroup.future;
      });
      chainToCompleter(future, _resultCompleter);
      return future;
    };

    // Make sure any error thrown by fn isn't top-leveled by virtue of being
    // passed to the result future.
    result.catchError((_) {});
  }

  /// Run [fn] as a child of this task. Returns a Future that will complete with
  /// the result of the child task. This task will not complete until [fn] has
  /// finished.
  Future runChild(fn(), String description) {
    var task = new Task._child(fn, description, this);
    children.add(task);
    if (_childGroup == null || _childGroup.completed) {
      _childGroup = new FutureGroup();
    }
    // Ignore errors in the FutureGroup; they'll get picked up via wrapFuture,
    // and we don't want them to short-circuit the other Futures.
    _childGroup.add(task.result.catchError((_) {}));
    task.fn();
    return task.result;
  }

  String toString() => description == null ? "#$_id" : description;

  /// Returns a detailed representation of [queue] with this task highlighted.
  String generateTree() => queue.generateTree(this);
}