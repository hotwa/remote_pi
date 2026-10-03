// ignore_for_file: avoid_print, depend_on_referenced_packages

// Collects aggregate VM timeline event counts from a running profile build.
// Usage: dart run tool/benchmarks/live_timeline_probe.dart <ws-uri> [seconds]
// Prints event names only; no terminal output or workspace data is collected.
import 'dart:async';

import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: live_timeline_probe.dart <ws-uri> [seconds]');
    return;
  }
  final seconds = args.length > 1 ? int.parse(args[1]) : 10;
  final service = await vmServiceConnectUri(args[0]);
  try {
    final flags = await service.getVMTimelineFlags();
    print('recorder=${flags.recorderName} available=${flags.availableStreams}');
    final streams = [
      for (final stream in ['Dart', 'Embedder', 'GC', 'Compiler'])
        if (flags.availableStreams?.contains(stream) ?? false) stream,
    ];
    await service.setVMTimelineFlags(streams);
    final start = await service.getVMTimelineMicros();
    await Future<void>.delayed(Duration(seconds: seconds));
    final end = await service.getVMTimelineMicros();
    final timeline = await service.getVMTimeline(
      timeOriginMicros: start.timestamp,
      timeExtentMicros: end.timestamp! - start.timestamp!,
    );
    final counts = <String, int>{};
    final durations = <String, List<num>>{};
    final beginnings = <String, List<int>>{};
    for (final event in timeline.traceEvents ?? []) {
      final json = event.json ?? const <String, dynamic>{};
      final name = json['name']?.toString() ?? '(unnamed)';
      counts[name] = (counts[name] ?? 0) + 1;
      final duration = json['dur'];
      if (duration is num) {
        durations.putIfAbsent(name, () => []).add(duration / 1000);
      }
      final timestamp = json['ts'];
      final phase = json['ph'];
      if (timestamp is num && (phase == 'b' || phase == 'e')) {
        final key = '${json['tid']}/$name';
        if (phase == 'b') {
          beginnings.putIfAbsent(key, () => []).add(timestamp.toInt());
        } else {
          final stack = beginnings[key];
          if (stack != null && stack.isNotEmpty) {
            final start = stack.removeLast();
            durations.putIfAbsent(name, () => []).add(
              (timestamp - start) / 1000,
            );
          }
        }
      }
    }
    print('events=${timeline.traceEvents?.length ?? 0} window=${seconds}s');
    for (final name in [
      'Frame',
      'BUILD',
      'LAYOUT',
      'PAINT',
      'GPURasterizer::Draw',
      'Rasterizer::DoDraw',
    ]) {
      final values = durations[name];
      if (values == null || values.isEmpty) continue;
      values.sort();
      final p50 = values[values.length ~/ 2];
      final p95 = values[((values.length * .95).ceil() - 1).clamp(0, values.length - 1)];
      final overBudget = values.where((value) => value > 16.67).length;
      print('$name: n=${values.length} p50=${p50.toStringAsFixed(2)}ms '
          'p95=${p95.toStringAsFixed(2)}ms max=${values.last.toStringAsFixed(2)}ms '
          '>16.67ms=$overBudget');
    }
    for (final entry in counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))) {
      print('${entry.value}\t${entry.key}');
    }
  } finally {
    await service.dispose();
  }
}
