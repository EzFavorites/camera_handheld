import 'package:camera_handheld/core/camera_config.dart';
import 'package:camera_handheld/core/http_client.dart';
import 'package:camera_handheld/core/isapi_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class Call {
  final String method;
  final String path;
  final String? body;
  Call(this.method, this.path, this.body);
}

class FakeRequester implements HttpRequester {
  final List<Call> calls = [];
  int statusCode;
  FakeRequester({this.statusCode = 200});

  @override
  Future<HttpResponse> request(
    String method,
    String path, {
    String? body,
    Map<String, String>? headers,
  }) async {
    calls.add(Call(method,  path, body));
    return HttpResponse(statusCode, '', []);
  }
}

CameraConfig get _cfg => const CameraConfig(
      ip: '10.0.0.5',
      port: 554,
      username: 'admin',
      password: 'secret',
      useSubStream: false,
    );

void main() {
  test('capture issues snapshot GET on main stream channel (101)', () async {
    final fake = FakeRequester();
    final proto = IsapiProtocol(config: _cfg, requester: fake);
    await proto.capture();
    expect(fake.calls, hasLength(1));
    expect(fake.calls.first.method, 'GET');
    expect(fake.calls.first.path, '/ISAPI/Streaming/channels/101/picture');
  });

  test('capture uses sub stream channel (102) when useSubStream is true', () async {
    final fake = FakeRequester();
    final proto =
        IsapiProtocol(config: _cfg.copyWith(useSubStream: true), requester: fake);
    await proto.capture();
    expect(fake.calls.first.path, '/ISAPI/Streaming/channels/102/picture');
  });

  test('zoomIn sends continuous zoomTele=1', () async {
    final fake = FakeRequester();
    final proto = IsapiProtocol(config: _cfg, requester: fake);
    await proto.zoomIn();
    expect(fake.calls.first.method, 'PUT');
    expect(fake.calls.first.path, '/ISAPI/PTZCtrl/channels/1/continuous');
    expect(fake.calls.first.body, contains('zoomTele>1'));
    expect(fake.calls.first.body, contains('zoomWide>0'));
  });

  test('zoomOut sends continuous zoomWide=A1', () async {
    final fake = FakeRequester();
    final proto = IsapiProtocol(config: _cfg, requester: fake);
    await proto.zoomOut();
    expect(fake.calls.first.body, contains('zoomWide>1'));
    expect(fake.calls.first.body, contains('zoomTele>0'));
  });

  test('zoomStop sends all-zero continuous body', () async {
    final fake = FakeRequester();
    final proto = IsapiProtocol(config: _cfg, requester: fake);
    await proto.zoomStop();
    expect(fake.calls.first.body, contains('zoomTele>0'));
    expect(fake.calls.first.body, contains('zoomWide>0'));
  });

  test('focusAt triggers AF on imaging channel', () async {
    final fake = FakeRequester();
    final proto = IsapiProtocol(config: _cfg, requester: fake);
    await proto.focusAt(320, 480);
    expect(fake.calls.first.method, 'PUT');
    expect(fake.calls.first.path, '/ISAPI/Image/channels/1/focus');
    expect(fake.calls.first.body, contains('focusMode>AUTO'));
  });

  test('non-2xx response throws IsapiException', () async {
    final fake = FakeRequester(statusCode: 401);
    final proto = IsapiProtocol(config: _cfg, requester: fake);
    expect(() => proto.capture(), throwsA(isA<IsapiException>()));
  });
}
