import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_logger.dart';

class LogSlidingPanel extends StatefulWidget {
  const LogSlidingPanel({super.key});

  @override
  State<LogSlidingPanel> createState() => _LogSlidingPanelState();
}

class _LogSlidingPanelState extends State<LogSlidingPanel> {
  static const double _minHeight = 78.0;
  static const double _maxScreenFactor = 0.72;
  static const String _lastExportPathKey = 'logs_last_exported_file_path';

  final ScrollController _logScrollController = ScrollController();
  bool _autoScroll = true;
  double _currentHeight = _minHeight;
  bool _isExporting = false;
  String? _lastExportedFilePath;

  @override
  void initState() {
    super.initState();
    AppLogger.instance.addListener(_handleLogsChanged);
    unawaited(_restoreLastExportedPath());
  }

  @override
  void dispose() {
    AppLogger.instance.removeListener(_handleLogsChanged);
    _logScrollController.dispose();
    super.dispose();
  }

  void _handleLogsChanged() {
    if (!_autoScroll || !_logScrollController.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_logScrollController.hasClients) return;
      _logScrollController
          .jumpTo(_logScrollController.position.maxScrollExtent);
    });
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _onDragUpdate(DragUpdateDetails details, double maxHeight) {
    setState(() {
      _currentHeight -= details.delta.dy;
      if (_currentHeight < _minHeight) _currentHeight = _minHeight;
      if (_currentHeight > maxHeight) _currentHeight = maxHeight;
    });
  }

  void _onDragEnd(double maxHeight) {
    final midpoint = (_minHeight + maxHeight) / 2;
    final target = _currentHeight > midpoint ? maxHeight : _minHeight;
    setState(() {
      _currentHeight = target;
    });
  }

  String _formatForFile(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi:$s';
  }

  Future<void> _exportAndShareLogs() async {
    if (_isExporting) return;

    final logger = AppLogger.instance;
    if (logger.entries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logs to export yet.')),
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final now = DateTime.now();
      final timestamp =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';

      final buffer = StringBuffer()
        ..writeln('RoadSense Log Export')
        ..writeln('Generated: ${now.toIso8601String()}')
        ..writeln('Entries: ${logger.entries.length}')
        ..writeln('----------------------------------------');

      for (final entry in logger.entries) {
        buffer.writeln('${_formatForFile(entry.timestamp)} | ${entry.message}');
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/roadsense_logs_$timestamp.txt');
      await file.writeAsString(buffer.toString(), flush: true);
      _lastExportedFilePath = file.path;
      await _saveLastExportedPath(file.path);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'RoadSense logs export',
        subject: 'RoadSense logs ($timestamp)',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logs exported and ready to share.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to export logs.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _saveLastExportedPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastExportPathKey, path);
  }

  Future<void> _restoreLastExportedPath() async {
    final prefs = await SharedPreferences.getInstance();
    _lastExportedFilePath = prefs.getString(_lastExportPathKey);
  }

  Future<File?> _getLatestExportedLogFile() async {
    if (_lastExportedFilePath != null) {
      final lastFile = File(_lastExportedFilePath!);
      if (await lastFile.exists()) {
        return lastFile;
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final entities = await dir.list().toList();
    final exportedLogFiles = entities.whereType<File>().where((file) {
      final name =
          file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : '';
      return name.startsWith('roadsense_logs_') && name.endsWith('.txt');
    }).toList();

    if (exportedLogFiles.isEmpty) {
      return null;
    }

    exportedLogFiles.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );

    _lastExportedFilePath = exportedLogFiles.first.path;
    await _saveLastExportedPath(_lastExportedFilePath!);
    return exportedLogFiles.first;
  }

  Future<void> _shareLatestExportedLog() async {
    if (_isExporting) return;

    setState(() {
      _isExporting = true;
    });

    try {
      final file = await _getLatestExportedLogFile();
      if (file == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No exported log file found yet.')),
        );
        return;
      }

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'RoadSense logs export (latest file)',
        subject: 'RoadSense logs (latest export)',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Latest exported log shared.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to share latest exported log.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeBottomInset = MediaQuery.of(context).viewPadding.bottom;
    final rawMaxHeight = MediaQuery.of(context).size.height * _maxScreenFactor;
    final maxHeight = rawMaxHeight < _minHeight ? _minHeight : rawMaxHeight;
    if (_currentHeight > maxHeight) {
      _currentHeight = maxHeight;
    }

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: _currentHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.88),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
          ),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) =>
                    _onDragUpdate(details, maxHeight),
                onVerticalDragEnd: (_) => _onDragEnd(maxHeight),
                onTap: () {
                  setState(() {
                    _currentHeight =
                        _currentHeight == _minHeight ? maxHeight : _minHeight;
                  });
                },
                child: SizedBox(
                  height: 76,
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: AppLogger.instance,
                        builder: (context, _) {
                          final logger = AppLogger.instance;
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                            child: Row(
                              children: [
                                const Icon(Icons.subject,
                                    color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Logs (${logger.entries.length})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: _autoScroll
                                      ? 'Disable auto-scroll'
                                      : 'Enable auto-scroll',
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(
                                    _autoScroll
                                        ? Icons.vertical_align_bottom
                                        : Icons.swipe_down,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _autoScroll = !_autoScroll;
                                    });
                                  },
                                ),
                                IconButton(
                                  tooltip: logger.paused
                                      ? 'Resume logging'
                                      : 'Pause logging',
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(
                                    logger.paused
                                        ? Icons.play_arrow
                                        : Icons.pause,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  onPressed: logger.togglePaused,
                                ),
                                IconButton(
                                  tooltip: 'Export and share logs',
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(
                                    _isExporting
                                        ? Icons.hourglass_top
                                        : Icons.ios_share,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  onPressed:
                                      _isExporting ? null : _exportAndShareLogs,
                                ),
                                IconButton(
                                  tooltip: 'Share latest exported file',
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.share,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  onPressed: _isExporting
                                      ? null
                                      : _shareLatestExportedLog,
                                ),
                                IconButton(
                                  tooltip: 'Clear logs',
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  onPressed: logger.clear,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0x66FFFFFF)),
              Expanded(
                child: AnimatedBuilder(
                  animation: AppLogger.instance,
                  builder: (context, _) {
                    final entries = AppLogger.instance.entries;

                    if (entries.isEmpty) {
                      return const Center(
                        child: Text(
                          'No logs yet',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _logScrollController,
                      padding: EdgeInsets.fromLTRB(12, 10, 12, 20 + safeBottomInset),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final normalized = entry.message.toLowerCase();
                        final isRoadEvent =
                            normalized.contains('road_event_detected');
                        final isRiskPrediction = isRoadEvent ||
                            normalized.contains('risk_prediction') ||
                            normalized.contains('ml_inference:');
                        final rowBg = isRiskPrediction
                            ? Colors.orange.withValues(alpha: 0.14)
                            : Colors.transparent;
                        final rowBorder = isRiskPrediction
                            ? Colors.orange.withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.0);
                        final timeColor = isRiskPrediction
                            ? Colors.orangeAccent
                            : const Color(0xFF90CAF9);
                        final messageColor = isRiskPrediction
                            ? Colors.orangeAccent.shade100
                            : Colors.white;
                        final leadingIcon = isRiskPrediction
                            ? Icons.crisis_alert
                            : Icons.fiber_manual_record;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            decoration: BoxDecoration(
                              color: rowBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: rowBorder),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  leadingIcon,
                                  size: 12,
                                  color: isRiskPrediction
                                      ? Colors.orangeAccent
                                      : const Color(0xFF90CAF9),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text:
                                              '[${_formatTime(entry.timestamp)}] ',
                                          style: TextStyle(
                                            color: timeColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        TextSpan(
                                          text: entry.message,
                                          style: TextStyle(
                                            color: messageColor,
                                            fontSize: 12,
                                            height: 1.25,
                                            fontWeight: isRiskPrediction
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
