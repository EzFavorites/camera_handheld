import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_log.dart';

/// Log viewer screen — shows the in-memory AppLog buffer with live updates.
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final ScrollController _scroll = ScrollController();
  List<String> _lines = AppLog.snapshot();
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    AppLog.addListener(_onNewLine);
  }

  void _onNewLine(String line) {
    if (!mounted) return;
    setState(() => _lines = AppLog.snapshot());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stickToBottom) _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  void dispose() {
    AppLog.removeListener(_onNewLine);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copyAll() async {
    final text = _lines.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('日志已复制到剪贴板'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _clearAll() {
    AppLog.clear();
    setState(() => _lines = AppLog.snapshot());
  }

  /// Open the folder containing the on-disk log file in the OS file manager.
  Future<void> _openLogFolder() async {
    final path = AppLog.filePath;
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('日志文件不可用（可能尚未初始化）')),
        );
      }
      return;
    }
    try {
      final dir = File(path).parent.path;
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('explorer', ['/select,', path]);
      } else if (Platform.isMacOS) {
        result = await Process.run('open', ['-R', path]);
      } else {
        result = await Process.run('xdg-open', [dir]);
      }
      if (result.exitCode != 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开文件夹：${result.stderr}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开日志文件夹失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '查看日志',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            onPressed: _openLogFolder,
            tooltip: '打开日志文件夹',
            icon: Icon(
              Icons.folder_open,
              size: 18,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          IconButton(
            onPressed: _copyAll,
            tooltip: '复制全部',
            icon: Icon(
              Icons.copy,
              size: 18,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          IconButton(
            onPressed: _clearAll,
            tooltip: '清空',
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          // Stick-to-bottom toggle
          IconButton(
            onPressed: () => setState(() {
              _stickToBottom = !_stickToBottom;
              if (_stickToBottom) _scrollToBottom();
            }),
            tooltip: '自动滚动',
            icon: Icon(
              _stickToBottom ? Icons.vertical_align_bottom : Icons.unfold_more,
              size: 18,
              color: _stickToBottom
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Log file location banner — where the on-disk log lives.
          Container(
            width: double.infinity,
            color: Colors.white.withValues(alpha: 0.04),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLog.filePath ?? '日志文件不可用',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontFamily: 'SF Mono',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _lines.isEmpty
                ? Center(
                    child: Text(
                      '暂无日志',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 14,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _lines.length,
                    itemBuilder: (context, i) {
                      final line = _lines[i];
                      final color = _lineColor(line);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: SelectableText(
                          line,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontFamily: 'SF Mono',
                            height: 1.5,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _lineColor(String line) {
    if (line.contains('FAILED') || line.contains('error') ||
        line.contains('Error') || line.contains('LOCKED')) {
      return Colors.red.shade300;
    }
    if (line.contains('OK') || line.contains('result: 0') ||
        line.contains('initialized successfully')) {
      return Colors.green.shade300;
    }
    if (line.contains('Warn') || line.contains('→ 500')) {
      return Colors.orange.shade300;
    }
    return Colors.white70;
  }
}