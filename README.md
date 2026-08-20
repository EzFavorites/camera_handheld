# Camera Handheld

手持相机遥控器 —— 把海康威视网络摄像头（IPC）当手持相机用。手机/桌面作为取景屏与控制端，实时预览画面并远程拍照、变倍、点击对焦。

- **预览**：RTSP 流（`media_kit` / mpv 内核）
- **控制**：ISAPI 协议（`capture` / `zoomIn` / `zoomOut` / `zoomStop` / `focusAt`）
- **平台**：macOS（开发调试）/ Windows（exe）/ Android（apk）
- **状态管理**：Provider（ChangeNotifier）
- **协议抽象**：`CameraProtocol` 接口先行，`VirtualProtocol` 用于无硬件调试，未来切换 `IsapiProtocol` 零 UI 改动

详细设计见 [docs/DESIGN.md](docs/DESIGN.md)。

## 运行

```bash
flutter pub get
flutter run            # 默认启动 macOS / 当前平台桌面端
flutter run -d android # 连接 Android 设备
```

> 预览需要可达的 RTSP 流；无硬件时可用 `VirtualProtocol` 跑通界面（日志输出操作）。
> 摄像头密码通过 `flutter_secure_storage` 加密存储（Keystore / Keychain），不会明文落盘。

## 构建

GitHub Actions 自动构建三端产物（Windows EXE / macOS APP / Android APK）：

```bash
# 本地 release 构建
flutter build windows --release
flutter build macos --release
flutter build apk --release
```

Android 正式签名：在项目根放置 `key.properties`（含 `storeFile` / `storePassword` /
`keyAlias` / `keyPassword`），CI 自动启用正式签名；缺失时回退 debug 签名。

## 测试

```bash
flutter analyze
flutter test
```

## 项目结构

```
lib/
├── main.dart                 # 入口：MediaKit 初始化 + 装配
├── app.dart                  # MaterialApp + Provider 装配
├── core/
│   ├── camera_config.dart    # 连接配置 + RTSP URL 构造
│   ├── camera_config_store.dart  # shared_prefs + 安全存储
│   ├── camera_protocol.dart  # 协议抽象接口
│   └── virtual_protocol.dart # 虚拟协议（调试）
├── features/
│   ├── camera_state.dart     # 全局状态 ChangeNotifier
│   ├── preview/              # 取景器 + 对焦框
│   ├── capture/              # 快门
│   ├── lens/                 # 变倍控制
│   └── settings/             # 设备配置界面
└── ...
```
