/// A cursor over an immutable plan: what an entity is working through.
library;

/// A node in a plan.
///
/// The package supplies the composites; a game supplies every leaf by rooting
/// its own sealed family here:
///
/// ```dart
/// sealed class PatrolStep extends Step<PatrolStep> {
///   const PatrolStep();
/// }
/// ```
abstract base class Step<L extends Step<L>> {
  const Step();
}

/// Runs [children] in order. Fails on the first child that fails.
final class Sequence<L extends Step<L>> extends Step<L> {
  const Sequence(this.children);

  /// Run in order, first to last.
  final List<Step<L>> children;
}

/// Runs [children] until one succeeds. Fails when every child fails.
final class Select<L extends Step<L>> extends Step<L> {
  const Select(this.children);

  /// Tried in order until one succeeds.
  final List<Step<L>> children;
}

/// Re-enters [child] [times] times, or forever when [times] is null.
///
/// A failing child fails the repeat; the iteration is not consumed.
final class Repeat<L extends Step<L>> extends Step<L> {
  const Repeat(this.child, {this.times});

  /// The step to re-enter.
  final Step<L> child;

  /// Iterations to run, or null to run forever.
  final int? times;
}

/// What a driver reports about the leaf it just ran.
enum StepResult {
  /// Still working; keep the cursor here.
  running,

  /// Done; move on.
  success,

  /// Could not finish; unwind.
  failure,
}

/// Where one entity is in its plan.
///
/// The plan is immutable and shared by every instance of an archetype; this
/// cursor is the per-entity state. Ticked by its owner system like `Machine`
/// and `GameTimer`, so it pauses, slows and freezes with the game.
///
/// Allocates two `List<int>`. Free for a handful of directors or squads; for
/// hundreds of per-entity plans, prefer a flat cursor.
final class Routine<L extends Step<L>> {
  /// A cursor at the start of [plan].
  Routine(this.plan) {
    restart();
  }

  /// Restores a cursor saved as [path], [loops] and [elapsed].
  Routine.resume(
    this.plan, {
    List<int> path = const <int>[],
    List<int> loops = const <int>[],
    double elapsed = 0,
  }) {
    _path.addAll(path);
    _loops.addAll(loops);
    while (_loops.length < _path.length) {
      _loops.add(0);
    }
    _elapsed = elapsed;
    _settle(_descend());
  }

  /// The plan. Immutable and shared; never mutated.
  final Step<L> plan;

  final List<int> _path = <int>[];
  final List<int> _loops = <int>[];
  double _elapsed = 0;
  bool _finished = false;
  bool _failed = false;

  /// The leaf awaiting a result, or null once the plan settles.
  L? get current {
    if (_finished) return null;
    final node = _nodeAt(_path.length);
    assert(
      node is L,
      'Routine<$L> reached ${node.runtimeType}, which is neither a composite '
      'nor an $L. Every leaf must belong to the plan type.',
    );
    return node is L ? node : null;
  }

  /// Seconds on [current]. Zeroed when the cursor moves.
  double get elapsed => _elapsed;

  /// Whether the plan reached success or failure.
  bool get finished => _finished;

  /// Whether the plan settled on failure.
  bool get failed => _failed;

  /// Child index per depth. Save it like any other field.
  List<int> get path => List<int>.unmodifiable(_path);

  /// Completed iterations per depth, meaningful at [Repeat] nodes.
  List<int> get loops => List<int>.unmodifiable(_loops);

  /// Adds [delta] to [elapsed], then runs [current] through [run], advancing
  /// while leaves settle instantaneously.
  ///
  /// [maxSteps] caps advances per call, so a run of instant leaves finishes in
  /// one frame while a [Repeat] of them asserts instead of hanging. A no-op
  /// once [finished].
  void advance(
    double delta,
    StepResult Function(L leaf) run, {
    int maxSteps = 16,
  }) {
    if (_finished) return;
    _elapsed += delta;
    var steps = 0;
    while (!_finished) {
      if (steps >= maxSteps) {
        assert(
          false,
          'Routine.advance hit maxSteps ($maxSteps) without reaching a leaf '
          'that returned running. A Repeat of instantaneous leaves cannot '
          'yield; give one of them a duration.',
        );
        return;
      }
      steps++;
      final leaf = current;
      if (leaf == null) return;
      final result = run(leaf);
      if (result == StepResult.running) return;
      _elapsed = 0;
      _report(result);
    }
  }

  /// Returns the cursor to the start of [plan].
  void restart() {
    _path.clear();
    _loops.clear();
    _elapsed = 0;
    _finished = false;
    _failed = false;
    _settle(_descend());
  }

  /// The node reached by following [_path] for [depth] steps.
  Step<L> _nodeAt(int depth) {
    var node = plan;
    for (var i = 0; i < depth; i++) {
      node = switch (node) {
        Sequence<L>(:final children) => children[_path[i]],
        Select<L>(:final children) => children[_path[i]],
        Repeat<L>(:final child) => child,
        _ => node,
      };
    }
    return node;
  }

  /// Descends into composites until a leaf. Returns the result of an empty
  /// composite that settled on entry, or null on reaching a leaf.
  StepResult? _descend() {
    while (true) {
      final node = _nodeAt(_path.length);
      switch (node) {
        case Sequence<L>(:final children):
          if (children.isEmpty) return StepResult.success;
        case Select<L>(:final children):
          if (children.isEmpty) return StepResult.failure;
        case Repeat<L>(:final times):
          if (times != null && times <= 0) return StepResult.success;
        default:
          return null;
      }
      _path.add(0);
      _loops.add(0);
    }
  }

  /// Records [result] for the current position and bubbles it up.
  void _report(StepResult result) {
    var outcome = result;
    while (_path.isNotEmpty) {
      final depth = _path.length - 1;
      final index = _path[depth];

      switch (_nodeAt(depth)) {
        case Sequence<L>(:final children):
          if (outcome == StepResult.failure) break;
          if (index + 1 < children.length) {
            _path[depth] = index + 1;
            _loops[depth] = 0;
            final immediate = _descend();
            if (immediate == null) return;
            outcome = immediate;
            continue;
          }
        case Select<L>(:final children):
          if (outcome == StepResult.success) break;
          if (index + 1 < children.length) {
            _path[depth] = index + 1;
            _loops[depth] = 0;
            final immediate = _descend();
            if (immediate == null) return;
            outcome = immediate;
            continue;
          }
        case Repeat<L>(:final times):
          if (outcome == StepResult.failure) break;
          final done = _loops[depth] + 1;
          if (times == null || done < times) {
            _loops[depth] = done;
            final immediate = _descend();
            if (immediate == null) return;
            outcome = immediate;
            continue;
          }
          outcome = StepResult.success;
        default:
          return;
      }
      _path.removeLast();
      _loops.removeLast();
    }
    _settle(outcome);
  }

  /// Marks the plan finished when [outcome] reached the root.
  void _settle(StepResult? outcome) {
    if (outcome == null) return;
    _finished = true;
    _failed = outcome == StepResult.failure;
  }

  /// The active path and leaf, e.g. `Repeat[0] Sequence[2] Pause 3.0s (1.20s)`.
  @override
  String toString() {
    if (_finished) return _failed ? 'failed' : 'finished';
    final buffer = StringBuffer();
    for (var i = 0; i < _path.length; i++) {
      final label = switch (_nodeAt(i)) {
        Sequence<L>() => 'Sequence',
        Select<L>() => 'Select',
        Repeat<L>() => 'Repeat',
        _ => '?',
      };
      buffer.write('$label[${_path[i]}] ');
    }
    final leaf = _nodeAt(_path.length);
    final text = '$leaf';
    buffer
      ..write(text.startsWith("Instance of '") ? '${leaf.runtimeType}' : text)
      ..write(' (${_elapsed.toStringAsFixed(2)}s)');
    return buffer.toString();
  }
}
