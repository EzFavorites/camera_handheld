import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/camera_config.dart';
import 'core/camera_protocol.dart';
import 'features/camera_state.dart';
import 'features/preview/preview_screen.dart';

class CameraApp extends StatelessWidget {
  final CameraProtocol protocol;
  final CameraConfig initialConfig;

  const CameraApp({
    super.key,
    required this.protocol,
    required this.initialConfig,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CameraState(protocol: protocol, config: initialConfig),
      child: MaterialApp(
        title: 'Camera Handheld',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            surface: Colors.black,
          ),
        ),
        home: const PreviewScreen(),
      ),
    );
  }
}