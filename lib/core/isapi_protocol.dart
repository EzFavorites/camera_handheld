import 'package:camera_handheld/core/camera_config.dart';
import 'package:camera_handheld/core/camera_protocol.dart';
import 'package:camera_handheld/core/http_client.dart';

/// Real camera control via Hikvision ISAPI over HTTP (Digest auth).
///
/// Implements [CameraProtocol] so it can be swapped in for [VirtualProtocol].
/// The HTTP layer is injectable ([HttpRequester]) so the protocol is unit-testable
/// without a live camera.
///
/// Endpoints used (Hikvision ISAPI convention):
/// - Snapshot:  GET  /ISAPI/Streaming/channels/{channel}/picture
/// - PTZ (continuous): PUT /ISAPI/PTZCtrl/channels/{ptzChannel}/continuous
/// - AF trigger: PUT /ISAPI/Image/channels/{channel}/focus
///
/// `channel` is 101 (main) / 102 (sub) per [CameraConfig.useSubStream].
class IsapiProtocol implements CameraProtocol {
  IsapiProtocol({
    required this.config,
    HttpRequester? requester,
    int httpPort = 80,
  }) : _requester = requester ??
            DigestHttpClient(
              baseUrl: 'http://${config.ip}:$httpPort',
              username: config.username,
              password: config.password,
            );

  final CameraConfig config;
  final HttpRequester _requester;

  String get _streamChannel => config.useSubStream ? '102' : '101';
  // Hikvision PTZ channel is 1-based and independent of the streaming channel id.
  static const int _ptzChannel = 1;

  @override
  Future<void> capture() async {
    final resp =
        await _requester.request('GET', '/ISAPI/Streaming/channels/$_streamChannel/picture');
    if (!resp.ok) {
      throw IsapiException('snapshot failed', resp.statusCode);
    }
  }

  @override
  Future<void> zoomIn() => _ptz(zoomTele: 1);

  @override
  Future<void> zoomOut() => _ptz(zoomWide: 1);

  @override
  Future<void> zoomStop() => _ptz();

  /// [zoomTele]/[zoomWide] are mutually exclusive "continuous" flags (0/1).
  /// Empty body means an explicit stop. Note PTZ continuous motion is stopped by
  /// sending all-zero flags, which is what [zoomStop] does.
  Future<void> _ptz({
    int zoomTele = 0,
    int zoomWide = 0,
    int focusNear = 0,
    int focusFar = 0,
  }) async {
    final body = '''
<PTZData>
  <panLeft>0</panLeft>
  <panRight>0</panRight>
  <tiltUp>0</tiltUp>
  <tiltDown>0</tiltDown>
  <zoomWide>$zoomWide</zoomWide>
  <zoomTele>$zoomTele</zoomTele>
  <focusNear>$focusNear</focusNear>
  <focusFar>$focusFar</focusFar>
  <irisOpen> 0</irisOpen>
  <irisClose>0</irisClose>
</PTZData>''';
    final resp = await _requester.request(
      'PUT',
      '/ISAPI/PTZCtrl/channels/$_ptzChannel/continuous',
      body: body,
    );
    if (!resp.ok) {
      throw IsapiException('ptz failed', resp.statusCode);
    }
  }

  @override
  Future<void> focusAt(int x, int y) async {
    // Tap-to-focus baseline: trigger autofocus for the imaging channel. True
    // region-based AF (mapping normalized x/y -> AF ROI) can be layered on later.
    final body = '<FocusConfiguration><focusMode>AUTO</focusMode></FocusConfiguration>';
    final resp = await _requester.request(
      'PUT',
      '/ISAPI/Image/channels/1/focus',
      body: body,
    );
    if (!resp.ok) {
      throw IsapiException('focus failed', resp.statusCode);
    }
  }

  @override
  void dispose() {
    // HTTP client holds no persistent socket that needs explicit teardown here.
  }
}

/// Thrown when an ISAPI command returns a non-2xx status.
class IsapiException implements Exception {
  final String message;
  final int? statusCode;
  IsapiException(this.message, this.statusCode);
  @override
  String toString() => 'IsapiException($message, status=$statusCode)';
}
