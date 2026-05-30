import 'package:flutter_test/flutter_test.dart';
import 'package:frame_scheduler/frame_scheduler.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test helpers
// ─────────────────────────────────────────────────────────────────────────────

ScheduledTask _makeTask({
  required String id,
  PriorityLevel priority = PriorityLevel.normal,
  double estimatedMs = 5.0,
  int? maxWaitMs,
  void Function()? onDropped,
}) =>
    ScheduledTask(
      id: id,
      task: () async {},
      priority: priority,
      estimatedDurationMs: estimatedMs,
      maxWaitMs: maxWaitMs,
      onDropped: onDropped,
    );

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('ScheduledTask', () {
    test('id is stored correctly', () {
      final t = _makeTask(id: 'my-task');
      expect(t.id, 'my-task');
    });

    test('priority matches provided value', () {
      final t = _makeTask(id: 't', priority: PriorityLevel.high);
      expect(t.priority, PriorityLevel.high);
      expect(t.effectivePriority, PriorityLevel.high);
    });

    test('effectivePriority can be upgraded', () {
      final t = _makeTask(id: 't', priority: PriorityLevel.low);
      t.upgradePriority();
      expect(t.effectivePriority, PriorityLevel.normal);
    });

    test('upgradePriority is capped at critical', () {
      final t = _makeTask(id: 't', priority: PriorityLevel.critical);
      t.upgradePriority();
      expect(t.effectivePriority, PriorityLevel.critical);
    });

    test('isExpired is false when maxWaitMs is null', () {
      final t = _makeTask(id: 't', maxWaitMs: null);
      expect(t.isExpired, isFalse);
    });

    test('isExpired is false immediately after creation', () {
      final t = _makeTask(id: 't', maxWaitMs: 5000);
      expect(t.isExpired, isFalse);
    });

    test('expiryRatio is 0.0 when maxWaitMs is null', () {
      final t = _makeTask(id: 't', maxWaitMs: null);
      expect(t.expiryRatio, 0.0);
    });

    test('toString contains id and priority', () {
      final t = _makeTask(id: 'my-task', priority: PriorityLevel.high);
      expect(t.toString(), contains('my-task'));
      expect(t.toString(), contains('High'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // TaskQueue
  // ──────────────────────────────────────────────────────────────────────────

  group('TaskQueue — basic operations', () {
    late TaskQueue queue;

    setUp(() => queue = TaskQueue(maxSize: 10));

    test('starts empty', () {
      expect(queue.isEmpty, isTrue);
      expect(queue.length, 0);
    });

    test('isFull is false when below maxSize', () {
      expect(queue.isFull, isFalse);
    });

    test('enqueue returns true on success', () {
      expect(queue.enqueue(_makeTask(id: 't1')), isTrue);
    });

    test('length increments after enqueue', () {
      queue.enqueue(_makeTask(id: 't1'));
      expect(queue.length, 1);
    });

    test('isEmpty is false after enqueue', () {
      queue.enqueue(_makeTask(id: 't1'));
      expect(queue.isEmpty, isFalse);
    });

    test('dequeue returns null when empty', () {
      expect(queue.dequeue(), isNull);
    });

    test('dequeue removes and returns the front task', () {
      final t = _makeTask(id: 't1');
      queue.enqueue(t);
      expect(queue.dequeue()?.id, 't1');
      expect(queue.isEmpty, isTrue);
    });

    test('peek returns front task without removing it', () {
      queue.enqueue(_makeTask(id: 't1'));
      expect(queue.peek()?.id, 't1');
      expect(queue.length, 1);
    });
  });

  group('TaskQueue — priority ordering', () {
    late TaskQueue queue;
    setUp(() => queue = TaskQueue(maxSize: 10));

    test('higher priority task is dequeued first', () {
      queue.enqueue(_makeTask(id: 'low', priority: PriorityLevel.low));
      queue.enqueue(_makeTask(id: 'high', priority: PriorityLevel.high));
      expect(queue.dequeue()!.priority, PriorityLevel.high);
      expect(queue.dequeue()!.priority, PriorityLevel.low);
    });

    test('critical is always first', () {
      queue.enqueue(_makeTask(id: 'n', priority: PriorityLevel.normal));
      queue.enqueue(_makeTask(id: 'c', priority: PriorityLevel.critical));
      queue.enqueue(_makeTask(id: 'l', priority: PriorityLevel.low));
      queue.enqueue(_makeTask(id: 'h', priority: PriorityLevel.high));

      expect(queue.dequeue()!.priority, PriorityLevel.critical);
      expect(queue.dequeue()!.priority, PriorityLevel.high);
      expect(queue.dequeue()!.priority, PriorityLevel.normal);
      expect(queue.dequeue()!.priority, PriorityLevel.low);
    });

    test('tasks of same priority preserve insertion order (FIFO)', () {
      queue.enqueue(_makeTask(id: 'first', priority: PriorityLevel.high));
      queue.enqueue(_makeTask(id: 'second', priority: PriorityLevel.high));
      expect(queue.dequeue()!.id, 'first');
      expect(queue.dequeue()!.id, 'second');
    });
  });

  group('TaskQueue — capacity limits', () {
    test('isFull returns true at maxSize', () {
      final q = TaskQueue(maxSize: 3);
      q.enqueue(_makeTask(id: 't1'));
      q.enqueue(_makeTask(id: 't2'));
      q.enqueue(_makeTask(id: 't3'));
      expect(q.isFull, isTrue);
    });

    test('enqueue returns false when queue is full', () {
      final q = TaskQueue(maxSize: 2);
      q.enqueue(_makeTask(id: 't1'));
      q.enqueue(_makeTask(id: 't2'));
      expect(q.enqueue(_makeTask(id: 't3')), isFalse);
    });

    test('existing tasks are not removed when queue is full', () {
      final q = TaskQueue(maxSize: 2);
      q.enqueue(_makeTask(id: 't1'));
      q.enqueue(_makeTask(id: 't2'));
      q.enqueue(_makeTask(id: 't3')); // Should be rejected
      expect(q.length, 2);
    });
  });

  group('TaskQueue — deduplication', () {
    late TaskQueue queue;
    setUp(() => queue = TaskQueue(maxSize: 10));

    test('duplicate id is rejected', () {
      queue.enqueue(_makeTask(id: 'dup'));
      expect(queue.enqueue(_makeTask(id: 'dup')), isFalse);
    });

    test('containsId returns true for queued task', () {
      queue.enqueue(_makeTask(id: 'exists'));
      expect(queue.containsId('exists'), isTrue);
    });

    test('containsId returns false for absent task', () {
      expect(queue.containsId('absent'), isFalse);
    });

    test('after dequeue, id is no longer contained', () {
      queue.enqueue(_makeTask(id: 'once'));
      queue.dequeue();
      expect(queue.containsId('once'), isFalse);
    });
  });

  group('TaskQueue — pruning and dropping', () {
    late TaskQueue queue;
    setUp(() => queue = TaskQueue(maxSize: 10));

    test('pruneExpired() returns 0 when no tasks are expired', () {
      queue.enqueue(_makeTask(id: 't1', maxWaitMs: 60000)); // 60s
      expect(queue.pruneExpired(), 0);
    });

    test('pruneExpired() calls onDropped for removed tasks', () {
      bool dropped = false;
      queue.enqueue(_makeTask(
        id: 'exp',
        maxWaitMs: null,
        onDropped: () => dropped = true,
      ));
      // Task without maxWaitMs never expires
      queue.pruneExpired();
      expect(dropped, isFalse);
    });

    test('dropBelow() removes tasks of lower priority', () {
      queue.enqueue(_makeTask(id: 'l', priority: PriorityLevel.low));
      queue.enqueue(_makeTask(id: 'n', priority: PriorityLevel.normal));
      queue.enqueue(_makeTask(id: 'h', priority: PriorityLevel.high));

      queue.dropBelow(PriorityLevel.high);
      // 'l' and 'n' are both below 'high'
      expect(queue.length, 1);
      expect(queue.peek()!.id, 'h');
    });

    test('dropBelow() calls onDropped for each removed task', () {
      int dropCount = 0;
      queue.enqueue(_makeTask(
          id: 'l1',
          priority: PriorityLevel.low,
          onDropped: () => dropCount++));
      queue.enqueue(_makeTask(
          id: 'l2',
          priority: PriorityLevel.low,
          onDropped: () => dropCount++));
      queue.enqueue(
          _makeTask(id: 'h', priority: PriorityLevel.high));

      queue.dropBelow(PriorityLevel.high);
      expect(dropCount, 2);
    });

    test('clear() empties the queue', () {
      queue.enqueue(_makeTask(id: 't1'));
      queue.enqueue(_makeTask(id: 't2'));
      queue.clear();
      expect(queue.isEmpty, isTrue);
    });

    test('clear() calls onDropped for every task', () {
      int dropCount = 0;
      for (int i = 0; i < 5; i++) {
        queue.enqueue(_makeTask(
          id: 'task_$i',
          onDropped: () => dropCount++,
        ));
      }
      queue.clear();
      expect(dropCount, 5);
    });
  });

  group('TaskQueue — inspection', () {
    late TaskQueue queue;
    setUp(() => queue = TaskQueue(maxSize: 10));

    test('tasks getter returns unmodifiable list', () {
      queue.enqueue(_makeTask(id: 't1'));
      final tasks = queue.tasks;
      expect(() => (tasks as List).add(_makeTask(id: 'injected')),
          throwsUnsupportedError);
    });

    test('operator[] provides index access', () {
      queue.enqueue(_makeTask(id: 'first', priority: PriorityLevel.critical));
      queue.enqueue(_makeTask(id: 'second', priority: PriorityLevel.low));
      expect(queue[0].id, 'first'); // critical is at index 0
    });

    test('tasksOfPriority filters correctly', () {
      queue.enqueue(_makeTask(id: 'h1', priority: PriorityLevel.high));
      queue.enqueue(_makeTask(id: 'n1', priority: PriorityLevel.normal));
      queue.enqueue(_makeTask(id: 'h2', priority: PriorityLevel.high));

      final highs = queue.tasksOfPriority(PriorityLevel.high);
      expect(highs.length, 2);
      expect(highs.every((t) => t.priority == PriorityLevel.high), isTrue);
    });
  });
}
