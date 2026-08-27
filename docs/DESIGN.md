# 手持相机 App 设计方案

> 海康威视摄像头 + 手机遥控，手持取景与拍摄。
> 预览走 RTSP，控制走 ISAPI。跨平台：macOS（开发调试）/ Windows（exe）/ Android（apk）。

---

## 1. 项目目标

把海康威视网络摄像头（IPC）改造为「手持相机」：

- 手机作为取景屏幕 + 控制端，实时预览摄像头画面
- 支持拍照（抓图）、变倍（Zoom）控制、点击对焦（归一化坐标下发）
- 桌面端（macOS/Windows）用于开发调试与桌面使用
- 全部通过 GitHub Actions 自动构建 Windows EXE 和 Android APK

### 非目标（v1 不做）

- PTZ 云台控制（用户设备无云台，仅有 Z 轴镜头）
- 录像、回放、多摄像头管理
- 推流到公网 / 云平台

> 演进说明：原“非目标”中的 **PTZ 云台**已在 **v1.1** 扩展支持 —— 外接云台通过 `PtzProtocol`（ISAPI Digest + continuous 接口）实现，已超出原始 v1 范围但现已落地。

---

## 2. 架构总览

```
┌────────────────────────────────────────────────┐
│  应用层 (Flutter UI)                            │
│  ┌──────────┐ ┌──────────┐ ┌────────────────┐  │
│  │ 取景器     │ │ 控制面板  │ │ 状态栏/HUD     │  │
│  │ Preview  │ │ Zoom/抓图│ │ StatusBar     │  │
│  └────┬─────┘ └────┬─────┘ └────────────────┘  │
│       │            │ Provider (CameraState)    │
│  ┌────┴────────────┴─────────────────────────┐  │
│  │ 播放层  media_kit (mpv 内核)              │  │
│  │ VideoController ←── RTSP URL              │  │
│  └────────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        │ RTSP (预览) │ ISAPI (控制) │
        ▼            ▼            ▼
┌───────────────────────────────────────────────┐
│  海康威视摄像头 (IPC)                          │
│  - RTSP: rtsp://<ip>:554/Streaming/Channels/10x │
│  - ISAPI: http://<ip>/ISAPI/... (HTTP Digest)  │
└───────────────────────────────────────────────┘
```

**分层原则**：UI 与协议解耦。所有摄像头操作通过 `CameraProtocol` 抽象接口下发，协议实现可自由替换（虚拟协议 → ISAPI 真实协议），UI 层零改动。

---

## 3. 技术栈

| 层 | 选型 | 说明 |
|---|---|---|
| UI 框架 | Flutter 3.x (Dart) | 一套代码，macOS/Windows/Android 三端 |
| 视频播放 | `media_kit` + `media_kit_video` | mpv 内核，RTSP 原生支持，硬解 |
| 状态管理 | `provider` (ChangeNotifier) | 简单可靠，无过度设计 |
| 协议客户端（未来） | Dart `http` + Digest 认证 + XML 解析 | ISAPI 集成时引入 |
| 桌面原生库 | `media_kit_libs_macos_video` | macOS 打包依赖 |

### 为什么暂选 media_kit 而非直接 libVLC

| 维度 | media_kit (mpv) | 直接 libVLC |
|---|---|---|
| 跨平台（Mac/Win/Android） | 官方支持，开箱即用 | 需逐平台集成（Android 需自编 so，Windows 需捆绑 dll） |
| 成熟度/维护 | 活跃维护 | 成熟但 Flutter 绑定需自研 |
| RTSP 支持 | mpv 原生支持 | 原生支持 |
| 延迟参数 | `cache=yes` / `demuxer-readahead` 可控 | `--network-caching` 可控 |

**决策**：v1 用 media_kit 快速跑通端到端。播放层**直接**使用 `media_kit`（`preview_screen.dart` 持有 `Player` / `VideoController`），未引入额外的 `VideoPlayerAdapter` 薄封装抽象；未来若要切换到 libVLC，需改 `preview_screen.dart` 的播放装配。

---

## 4. 视频预览方案（RTSP）

### 4.1 连接

- 默认 URL：`rtsp://<ip>:554/Streaming/Channels/102`（子码流，低延迟预览）
- 主码流：`Channels/101`（高画质）
- RTSP URL 通过应用内配置界面设置，落盘到本地配置

### 4.2 低延迟配置（取景器体验）

media_kit (mpv) 关键参数：

```dart
final player = Player(
  configuration: PlayerConfiguration(
    // 播放器可用参数在媒体配置层控制
  ),
);
await player.open(Media(url, httpHeaders: ...));
```

延迟优化点：

- 使用子码流（H.264，低分辨率）可显著降低解码与传输延迟
- mpv 渲染走硬解 + GPU 纹理，画面直通无额外拷贝
- 桌面端默认 TCP 模式（`rtsp_transport=tcp`），无线环境更稳

### 4.3 状态管理

- `Player` 状态（playing/error/buffering）映射为 `CameraState.connectionStatus`
- 断流自动重连（指数退避，最多重试 5 次）

---

## 5. 控制协议设计（ISAPI）

> v1 使用 `VirtualProtocol`（打印调试），接口先行；ISAPI 真实实现后续接入。

### 5.1 抽象接口（已实现）

```dart
abstract class CameraProtocol {
  Future<void> capture();                 // 抓图
  Future<void> zoomIn();                  // 变倍开始（tele）
  Future<void> zoomOut();                 // 变倍开始（wide）
  Future<void> zoomStop();                // 变倍停止
  Future<void> focusAt(int x, int y);     // 点击对焦（0-1000 归一化）
  void dispose();
}
```

### 5.2 未来 ISAPI 实现映射

| 操作 | HTTP 请求 | 说明 |
|---|---|---|
| 设备信息 | `GET /ISAPI/System/deviceInfo` | 连接自检 + 型号识别 |
| 抓图 | `GET /ISAPI/Streaming/channels/1/picture` | 响应体即 JPEG |
| 变倍 | VISCA 指令经 `POST /ISAPI/System/MovementMgr/channels/1/MovementParam?format=json` 透传（`visca_tran_jx`） | 按住即变倍（VISCA 步进），松开 stop |
| 对焦 | `PUT /ISAPI/System/Video/inputs/channels/1/focus` `<FocusCommand>near\|far\|stop</FocusCommand>` | 可选 |
| 聚焦区域 | `PUT .../focus` 或 `.../pictureFocus` 区域坐标 | 归一化坐标处理见 §6 |

### 5.3 认证

- 海康默认 **HTTP Digest** 认证（非 Basic）
- Dart 层实现：首包 401 → 用 realm/nonce 计算摘要 → 带 `Authorization` 重发
- v1 预留：`IsapiProtocol` 构造函数接收 `ip / port / user / password`

### 5.4 安全提示

- 设备密码不得硬编码，通过配置界面输入。**当前（v1）使用 `shared_preferences` 明文持久化，安全存储（Keychain / Keystore / `flutter_secure_storage`）为已知待办项，尚未实现** —— 请勿在不信任设备存储敏感密码。
- 局域网内建议关闭摄像头 Web 端口公网暴露

---

## 6. 点击对焦坐标归一化设计

**需求**：手机屏幕任意位置点击 → 转换为摄像头画面坐标系下发。

**方案**：**1000 × 1000 归一化坐标系**（对齐海康聚焦区域接口的坐标体系）

```
屏幕点击 (px, py)         归一化坐标 (x, y)
└── 除以屏幕宽高 ──▶   x = px / W * 1000
                      y = py / H * 1000
                      
范围钳制: 0 ≤ x,y ≤ 1000，取整
```

- 与分辨率无关：无论主码流 4K 还是子码流 720p，同一归一化坐标指向同一画面位置
- 对焦框 UI 用同一坐标反算像素位置渲染，所见即所得
- 点击后 2 秒自动隐藏对焦框

---

## 7. UI/UX 设计

### 7.1 视觉方向

暗色 · 工业 · 专业取景器（类 RED / ARRI 风格）：

- 纯黑底 + 白/浅灰文字，薄边框、等宽数字
- 无 AppBar / 无导航栏，画面即界面
- 控制浮层 3 秒无操作自动淡出，点击任意处唤回

### 7.2 布局

```
┌────────────────────────────────┐
│ LIVE                   2.5×   │  ← 顶栏（常驻）
│                              │
│                              │
│        预览画面（全屏）        │
│       ┌──────────┐            │
│       │ □ 对焦框   │ ← 点击出现  │
│       └──────────┘  坐标 0-1000│
│                (+)             │  ← 变倍（右侧，隐式)
│                (−)             │     长按连发
│                              │
│  [AF] [2.5×] [H.265] [ON]    │  ← 状态栏
│             ⊙                │  ← 快门
└────────────────────────────────┘
```

### 7.3 交互映射

| 用户操作 | UI 行为 | 协议调用 |
|---|---|---|
| 点击预览 | 显示对焦框 + 坐标标签 | `focusAt(x, y)` |
| 点击快门 | 红色脉冲反馈 | `capture()` |
| 短按变倍 +/− | 单次变倍 | `zoomIn/Out` + `zoomStop` |
| 长按变倍 +/− | 连续变倍 | `zoomIn/Out`（按住期间） |
| 松手 | 停止 | `zoomStop()` |
| 任意点击 | 唤回控制浮层 | — |

---

## 8. 跨平台构建（GitHub Actions）

### 8.1 目标产物

| 平台 | 命令 | 产物 | 触发 |
|---|---|---|---|
| Windows | `flutter build windows --release` | `camera_handheld.exe`（含运行库目录） | push / tag |
| Android | `flutter build apk --release` | `app-release.apk` | push / tag |

### 8.2 Workflow 设计

```yaml
.github/workflows/build.yml
├── job: build-windows (windows-latest runner)
│   ├── checkout + setup flutter (stable)
│   ├── flutter pub get
│   └── flutter build windows --release
│       └── upload-artifact: build/windows/x64/runner/Release/ (含 exe)
└── job: build-android (ubuntu-latest runner)
    ├── checkout + setup flutter（含 Android SDK）
    ├── flutter pub get
    └── flutter build apk --release
        └── upload-artifact: build/app/outputs/flutter-apk/
```

- tag 打版时同时上传到 GitHub Release
- Android 签名：开发期用 debug 签名；正式版配置 `keystore` secrets（`KEYSTORE_BASE64` / `KEYSTORE_PASSWORD`）

### 8.3 media_kit 打包注意

- Windows：需在 runner 安装 VC++ 运行库或使用静态链接；media_kit 官方提供 `media_kit_libs_windows_video` 自动捆绑 mpv
- Android：`media_kit_libs_android_video` 捆绑 mpv so
- desktop 端同时引入 `media_kit_libs_linux` 时注意平台条件依赖（Android/Win/Mac 各自 libs 包仅在自己平台生效）

---

## 9. 项目结构

```
camera_handheld/
├── lib/
│   ├── main.dart                 # 入口：MediaKit 初始化 + 装配
│   ├── app.dart                  # MaterialApp + Provider 装配
│   ├── core/
│   │   ├── camera_protocol.dart  # 协议抽象接口
│   │   ├── virtual_protocol.dart # 虚拟协议（调试）
│   │   └── isapi_protocol.dart   # ISAPI 实现（已实现）
│   ├── features/
│   │   ├── camera_state.dart     # 全局状态 ChangeNotifier
│   │   ├── preview/
│   │   │   ├── preview_screen.dart  # 主界面
│   │   │   └── focus_overlay.dart   # 对焦框
│   │   ├── capture/
│   │   │   └── shutter_button.dart  # 快门
│   │   └── lens/
│   │       └── zoom_controls.dart   # 变倍
├── .github/workflows/build.yml  # CI/CD
├── docs/DESIGN.md               # 本文档
└── pubspec.yaml
```

---

## 10. 开发里程碑

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| M1 界面 | 全界面组件 + 虚拟协议 + 本地 RTSP 预览 | macOS 上运行，RTSP 测试流出画，操作打日志 |
| M2 协议 | ISAPI 实现（Digest 认证、抓图、变倍、对焦） | 连真实海康摄像头，操作生效 |
| M3 配置 | 摄像头连接配置界面 + 安全存储 | 可切换 IP/账号/码流 |
| M4 构建 | GitHub Actions 双端产物 | exe + apk 可下载安装运行 |
| M5 打磨 | 断线重连、错误码提示、性能调优 | 弱网 1 分钟断连自动恢复 |

---

## 11. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| media_kit 在 Windows 打包需捆绑 mpv | 构建复杂度 | 用官方 libs 包自动捆绑；CI 上验证 |
| Docker/CI 环境缺 Visual Studio 工具链 | Windows 构建失败 | 用 windows-latest runner + `flutter build` 官方 action |
| 海康固件 ISAPI 字段差异 | 控制失效 | 先 `GET` 能力集 XML 动态适配；预留字段映射表 |
| mpv 默认缓存导致预览延迟 | 手感差 | 子码流 + 缓存参数调优；必要时切 libVLC（需改 preview_screen 播放装配） |
| Android 硬解个别机型兼容 | 花屏/卡顿 | mpv 软解兜底开关（设置项） |

---

## 12. 后续可扩展（非 v1）

- 录像（ISAPI 触发设备侧录像 / 手机侧录制 RTSP）
- OSD 叠加（时间戳、经纬度）
- 蓝牙手柄 / 线控快门
- 多机位切换
- 延时摄影 / 缩时摄影