# AGENTS.md

本文件为在本仓库工作的 AI 代理与人类开发者定义**编程规范**与**提交规范**。
目标：`camera_handheld` 始终保持静态分析零告警、测试全绿、提交历史清晰可追溯。

## 项目速览

手持相机遥控器：海康威视 IPC（网络摄像头）实时预览（RTSP）+ 控制（ISAPI）。
平台：macOS（开发调试）/ Windows（exe）/ Android（apk）。

- 状态管理：Provider（`ChangeNotifier`）
- 视频渲染：`media_kit`（mpv 内核）
- 网络：`package:http`（ISAPI + Digest Auth，见 `lib/core/digest_auth.dart`）
- 协议抽象：`CameraProtocol` 接口先行，`VirtualProtocol` 无硬件调试，`IsapiProtocol` 真实实现

关键目录：

```
lib/
├── main.dart                # 入口：MediaKit 初始化 + 装配
├── app.dart                 # MaterialApp + Provider 装配
├── core/                    # 无 UI 核心逻辑（可独立单测）
│   ├── camera_protocol.dart # 协议抽象接口
│   ├── isapi_protocol.dart  # ISAPI 真实实现
│   ├── virtual_protocol.dart# 虚拟协议（调试）
│   ├── ptz_protocol.dart    # 云台：PTZ + zoom 中继（串行队列）
│   ├── digest_auth.dart     # Digest 鉴权助手
│   ├── reconnect_policy.dart
│   ├── camera_config.dart / camera_config_store.dart
│   └── app_log.dart         # 日志（替代 print）
└── features/                # UI 与状态
    ├── camera_state.dart    # 全局状态 ChangeNotifier
    ├── preview/ capture/ lens/ ptz/ settings/
```

## 环境

- Dart SDK `^3.12.2`，Flutter stable
- `analysis_options.yaml`：`flutter_lints` + `avoid_print` + `prefer_single_quotes`
- 设计文档见 `docs/DESIGN.md`、`docs/superpowers/`

## 编程规范

1. **静态分析零告警**
   提交前必须运行 `flutter analyze --no-fatal-infos`，结果为 `No issues found!`。
   warning 视为错误，禁止带告警提交（见下方强制检查清单）。
2. **遵循 flutter_lints**
   禁止为消掉 lint 而加全局 `// ignore_for_file`；仅在确有理由时使用单行 `// ignore: <rule>`，并保持最小化。
3. **代码风格**
   - 字符串一律单引号（`prefer_single_quotes`）
   - 禁止 `print`（`avoid_print`）；需要日志时用 `AppLog`（`lib/core/app_log.dart`）
   - 不写不可达代码/死分支：对非空类型不要用 `??`、对非空表达式不要判空
   - 删除无用 import 与未使用变量
4. **分层与依赖方向**
   - `core/` 不依赖 Flutter UI，可独立单测；协议通过 `CameraProtocol` 接口解耦，切换实现零 UI 改动
   - `features/` 依赖 `core/`；UI 组件不直接发网络请求
   - 新协议实现必须实现 `CameraProtocol`，并配套与 `VirtualProtocol` 同等的测试
5. **状态与错误处理**
   - 全局状态放 `ChangeNotifier`，组件用 `Consumer` / `context.watch` 订阅
   - 网络请求走串行队列 + 超时（参考 `ptz_protocol.dart` / `isapi_protocol.dart`）；吞异常（`catchError`）必须注释原因
   - 异步回调中使用 `context` 前检查 `mounted`；不忽略 `dispose` 上下文
6. **平台与敏感数据**
   - 新增插件前确认三端（macOS/Windows/Android）可用；平台差异用 `Platform.isXxx` 或条件导入隔离
   - 配置经 `CameraConfigStore`（`shared_preferences`）持久化，当前含密码为**明文**——不要引入新的明文敏感落盘；如改安全存储需三端回归

## 测试规范

- 每个新功能/修复必须配套测试，遵循现有命名：`test/<模块>_test.dart`
- 协议测试用 `MockClient`（`package:http`），覆盖：正常、401 Digest 鉴权、错误路径、串行队列顺序（见 `test/ptz_protocol_test.dart`、`test/isapi_protocol_test.dart`）
- 无硬件时用 `VirtualProtocol` 验证 UI 流程（`test/virtual_protocol_test.dart`）
- 提交前必须运行 `flutter test`，全部通过

## 提交规范

使用 **Conventional Commits**，与仓库现有历史保持一致：

```
<type>(<scope>): <subject>
```

- `type`：`feat` / `fix` / `refactor` / `docs` / `test` / `chore` / `ci` / `perf` / `style`
- `scope`：模块名（`ptz`、`preview`、`settings`、`ci` 等）；跨多模块时可省略
- `subject`：英文祈使句概括改动，可附中文说明
- 示例（来自现有提交）：
  - `feat(ptz): wire PtzProtocol into app assembly`
  - `fix: serial command queue for ISAPI requests, 5s timeouts`
  - `refactor: extract DigestAuth helper, IsapiProtocol behavior unchanged`
  - `docs(ptz): add gimbal design spec and implementation plan`

规则：

- **一个提交一件事**：不混入无关改动；`feat` 与 `fix` 分开提交
- 不提交生成物（`build/`、`.dart_tool/` 等，已在 `.gitignore`）

## 提交前强制检查（Commit Checklist）

每次 `git commit` 之前，必须依次执行并全部通过：

```bash
flutter analyze --no-fatal-infos   # 必须输出 No issues found!
flutter test                        # 必须全部通过
```

## Pre-commit Hook

仓库提供 `scripts/pre-commit.sh`，在每次 `git commit` 前自动执行上面两条检查，任一失败即阻止提交。

安装（在仓库根目录执行一次）：

```bash
ln -s ../../scripts/pre-commit.sh .git/hooks/pre-commit
```

- 紧急跳过（不推荐）：`git commit --no-verify`
- 未安装 flutter 时 hook 会明确报错并阻止提交
- 注意：hook 本身不会被 `git clone` 带过去，新克隆的仓库需重新执行上面的安装命令

## 参考

- CI 配置：`.github/workflows/build.yml`（push/PR 对三端分别执行 `flutter analyze --no-fatal-infos` 并构建，tag 触发 release）
- 设计与规划：`docs/DESIGN.md`、`docs/superpowers/`
