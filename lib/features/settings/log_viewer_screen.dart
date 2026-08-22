import 'dart:async';

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
      body: _lines.isEmpty
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