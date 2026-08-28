# 外接云台（PTZ）设计

> 当前主设备无云台，仅 Z 轴镜头。新增一台带云台的 Hik 设备作为外接云台，
> 通过 ISAPI 独立控制其 pan/tilt；主设备变倍时同步联动云台设备的变倍。

---

## 1. 范围与决策

### 做什么
- 设置页新增「云台」配置区：启用开关、设备 IP、密码（用户名固定 `admin`）、转速 (1–100，默认 50)。
- 保存时用 `IsapiProtocol.testConnection` 验证云台设备连通与认证。
- 启用并保存后，预览页左下角显示云台控制盘（四方向：上/下/左/右），按住连续转动、松开停止。
- 主设备变倍按钮触发时，**同时**向云台设备发送变倍指令（tele/wide/stop）。

### 不做
- 不做八方向斜向（仅四方向）。
- 云台盘上不重复放变倍按钮（云台变倍由主变倍按钮联动）。
- 不做预置位、巡航、回放等高级 PTZ 功能。

### 关键决策
| 项 | 选择 | 理由 |
|---|---|---|
| 方向 | 四方向 pan/tilt | 最简，与现有变倍按钮交互一致 |
| 变倍联动 | 主变倍按钮同时驱动云台 zoom | 用户明确要求；云台镜头可同步跟焦 |
| 用户名 | 固定 `admin` | 与主设备默认一致，减少配置项 |
| 速度 | 设置页可调 1–100 | 用户选择 |
| 认证 | 复用 IsapiProtocol Digest | 已验证可靠 |

---

## 2. ISAPI 端点与报文

云台 PTZ 走 Hikvision 标准 continuous 接口：

```
PUT /ISAPI/PTZCtrl/channels/1/continuous
Content-Type: application/xml

<PTZData>
  <pan>0</pan>          <!-- -1.0 .. 1.0，正=右 负=左 -->
  <tilt>0</tilt>         <!-- -1.0 .. 1.0，正=下 负=上 -->
  <zoom>0</zoom>         <!-- -1.0..1.0 正=tele 负=wide -->
</PTZData>
```

- 方向 → pan/tilt 符号：
  - 上：`tilt = -speed`，pan=0
  - 下：`tilt = +speed`，pan=0
  - 左：`pan = -speed`，tilt=0
  - 右：`pan = +speed`，tilt=0
- 停止：`pan=tilt=zoom=0` 的全零 PTZData。
- `speed` 为归一化浮点：`speedPercent / 100.0`（如 50 → 0.5）。
- 变倍联动：
  - tele：`<zoom>+speed</zoom>`（pan=tilt=0）
  - wide：`<zoom>-speed</zoom>`
  - stop：全零 PTZData（停止 pan/tilt/zoom 全部）

> 注：Hikvision 旧固件字段名为 `panTiltVelocity`/`zoomVelocity`，新固件为 `pan`/`tilt`/`zoom`。
> 默认用新字段名 `pan`/`tilt`/`zoom`；若控制无效再回退（实现内预留常量，便于切换）。

---

## 3. 数据模型

### `PtzConfig`（新增，`lib/core/ptz_config.dart`）
```dart
@immutable
class PtzConfig {
  final bool enabled;
  final String ip;          // 云台设备 IP
  final String password;    // 用户名固定 admin
  final int speed;          // 1..100，默认 50
}
```
- `toJson` / `fromJson` / `copyWith` / `==` / `hashCode`（参照 `CameraConfig` 写法）。
- 默认：`enabled=false, ip='192.168.1.65', password='', speed=50`。

### `CameraConfig` 扩展
- 新增字段 `PtzConfig ptz`（默认 `const PtzConfig()`）。
- `toJson`/`fromJson`/`copyWith`/`==`/`hashCode` 同步更新。
- 向后兼容：旧配置无 `ptz` 键 → 解析为默认（云台禁用）。

### 存储
- `CameraConfigStore` 已序列化整个 `CameraConfig`，无需改动；`ptz` 随之持久化。

---

## 4. 协议层

### `PtzProtocol`（新增，`lib/core/ptz_protocol.dart`）
独立类，**不实现** `CameraProtocol`（接口面向主设备；云台只需 pan/tilt/zoom）。

```dart
class PtzProtocol {
  PtzConfig config;
  // 复用 IsapiProtocol 的 Digest 认证 + 串行队列思路，
  // 但路径与报文不同，故独立实现而非继承（IsapiProtocol 的 _request 是私有）。
  /// continuous PTZ。pan/tilt/zoom 为 -1.0..1.0 方向值（已含符号），
  /// 内部乘 config.normalizedSpeed 下发。
  Future<void> move({required double pan, required double tilt, required double zoom});
  Future<void> stop();                  // 全零 PTZData
  Future<void> zoomIn();  // zoom=+speed
  Future<void> zoomOut(); // zoom=-speed
  Future<void> zoomStop();// zoom=0
  // 方向便捷方法（海康坐标系：pan 正=右 负=左；tilt 正=下 负=上）
  Future<void> up();
  Future<void> down();
  Future<void> left();
  Future<void> right();
  void updateConfig(PtzConfig c);
  static Future<String?> testConnection(PtzConfig c);  // 设置页自检
  void dispose();
}
```
- `move` 接收归一化方向三元组（命名参数），内部乘 `config.normalizedSpeed`。
- `up/down/left/right` 为方向便捷方法，等价于 `move(pan:±1, tilt:±1, zoom:0)`。
- 每请求生成新随机 `cnonce`（`Random.secure`），不缓存，满足 RFC 2617 重放保护（实现比计划更严）。
- 同样用串行队列避免快速点击时请求堆积冻结 UI。
- 静态 `testConnection(PtzConfig)` 复用 `DigestAuth` 做 `GET /ISAPI/System/deviceInfo` 自检。

### 联动接线
- `CameraState` 持有可选 `PtzProtocol? _ptz`。
- `zoomIn()/zoomOut()/zoomStop()` 在调主协议后，若 `_ptz != null && ptz.enabled`，同步调用 `_ptz.zoomIn/Out/Stop()`（fire-and-forget，错误仅 log，不阻塞主流程）。
- `updateConfig` 时根据 `config.ptz.enabled` 创建/更新/销毁 `_ptz`。

---

## 5. UI

### 5.1 设置页（`settings_screen.dart`）
在「变倍」段后新增「云台」段：
- 启用开关（`Switch`）。
- 启用时展开：设备 IP、密码、转速（`Slider` 1–100，显示数值）。
- 保存时连同主配置一起 `testConnection`（主设备先测，云台启用才测），都通过才落盘。

### 5.2 云台控制盘（新增 `lib/features/ptz/ptz_controls.dart`）
- 布局：2×3 网格，上/左/右/下 四个圆形按钮（参照 `ZoomControls` 的 `_ZoomButton` 视觉：黑底白边、按下高亮缩放）。
  ```
       [ ↑ ]
  [ ← ]    [ → ]
       [ ↓ ]
  ```
- 交互：`onLongPressStart` → `move(方向)`；`onLongPressEnd` / `onTapUp` → `stop()`。短按同样触发一次方向移动 + 短延迟 stop（与变倍按钮一致的 pulse 语义，复用 `zoomTapDelayMs`）。
- 隐藏条件：`ptz.enabled == false` 时整个组件不渲染。

### 5.3 预览页（`preview_screen.dart`）
- `Stack` 新增左下角 `Positioned(bottom: 40, left: 20)`，放 `Consumer<CameraState>` → `PtzControls`（仅当 `state.config.ptz.enabled` 显示）。
- 变倍按钮的 `onZoomIn/Out/Stop` 回调已走 `CameraState`，联动逻辑在 `CameraState` 内完成，预览页无需改动变倍部分。

---

## 6. 错误处理
- 云台请求失败：`PtzProtocol` 内 try/catch + `AppLog` 记录，不弹错误（避免预览中频繁打扰）。
- 设备锁定检测：`_checkLocked(body, statusCode)` 三层判定（保守，避免误报）：① HTTP 403/429 为权威锁定信号；② ISAPI `<statusCode>` 节点含 lock/4/8；③ 兜底子串匹配 `device is locked`。命中后置 `_isLocked`，后续 move 直接抛 `StateError` 记 log。`updateConfig` 会重置 `_isLocked`。
- 主设备变倍不应因云台失败而中断：联动调用 fire-and-forget，错误 swallow。

---

## 7. 测试
- `ptz_config_test.dart`：toJson/fromJson 往返、向后兼容（无 ptz 键→默认禁用）、copyWith、==。
- `ptz_protocol_test.dart`：用伪造的 http client 验证 continuous PUT 的 XML body（pan/tilt/zoom 符号、speed 归一化、stop 全零）、串行队列、locked 状态。
- `camera_state_test.dart`：新增——zoomIn 时若 ptz 启用则 `_ptz.zoomIn` 被调用；ptz 禁用时不应调用。
- `settings_screen_test.dart`：云台段渲染、启用开关展开/收起。
- `ptz_controls_test.dart`：长按触发 move、松开触发 stop、禁用时不渲染。

---

## 8. 验收
1. 设置页可启用云台、填 IP/密码、调速度、保存（保存前双向连通测试）。
2. 启用后预览左下出现云台控制盘；禁用时不显示。
3. 按住方向按钮云台连续转，松开停。
4. 按主变倍 +/- 时，云台设备镜头同步变倍；松开同步停。
5. 云台断连/认证失败仅记日志，不影响主设备预览与变倍。
