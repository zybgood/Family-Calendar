import 'dart:io';

class PerformanceReportRow {
  const PerformanceReportRow({
    required this.metric,
    required this.datasetSize,
    required this.iterations,
    required this.averageMs,
    required this.minMs,
    required this.maxMs,
    required this.notes,
  });

  final String metric;
  final int datasetSize;
  final int iterations;
  final double averageMs;
  final double minMs;
  final double maxMs;
  final String notes;

  String toCsv() {
    return <String>[
      metric,
      datasetSize.toString(),
      iterations.toString(),
      averageMs.toStringAsFixed(3),
      minMs.toStringAsFixed(3),
      maxMs.toStringAsFixed(3),
      '"${notes.replaceAll('"', '""')}"',
    ].join(',');
  }
}

class PerformanceReporter {
  PerformanceReporter._(this.outputPath);

  final String outputPath;
  final List<PerformanceReportRow> _rows = <PerformanceReportRow>[];

  static Future<PerformanceReporter> create({String? fileName}) async {
    final dir = Directory('performance_reports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final resolvedFileName =
        fileName ?? 'memo_performance_report_${DateTime.now().millisecondsSinceEpoch}.csv';
    return PerformanceReporter._('${dir.path}/$resolvedFileName');
  }

  void addRow(PerformanceReportRow row) {
    _rows.add(row);
  }

  Future<void> save() async {
    final file = File(outputPath);
    final sink = file.openWrite();
    sink.writeln('metric,dataset_size,iterations,average_ms,min_ms,max_ms,notes');
    for (final row in _rows) {
      sink.writeln(row.toCsv());
    }
    await sink.flush();
    await sink.close();
  }
}