# BitChat Flutter — 功能路线图与架构

> 去中心化 P2P 加密通信，基于蓝牙 Mesh + Nostr 协议。
> 单一 Flutter 代码库，覆盖 iOS、Android 和 macOS。

---

## 架构

```
lib/
├── models/           # 数据模型 (BitchatPacket, BitchatMessage, PeerID 等)
├── protocol/         # 二进制协议编解码、消息填充、分片
├── crypto/           # Noise 协议 (XX 模式)、Ed25519、X25519
├── mesh/             # BLE 中心 + 外设、节点发现、存储转发
├── nostr/            # Nostr WebSocket 客户端、中继管理器、Geohash 频道
├── sync/             # Gossip 同步、GCS/Bloom 过滤去重
├── services/         # 消息路由、命令处理器、通知、持久化
└── ui/               # 终端风格聊天 UI、频道列表、设置
```

### 协议栈
```
┌─────────────────────────────────────┐
│  应用层 (BitchatMessage)            │
├─────────────────────────────────────┤
│  会话层 (BitchatPacket)             │  ← 二进制编解码、TTL 路由、分片
├─────────────────────────────────────┤
│  加密层 (Noise XX)                  │  ← X25519 + ChaCha20-Poly1305 + SHA256
├─────────────────────────────────────┤
│  传输层 (BLE / Nostr)               │  ← BLE 平台通道，Nostr WebSocket
└─────────────────────────────────────┘
```

---

## 第一阶段 — 核心协议（纯 Dart）✅ 完成

- [x] 二进制协议编解码 (`BitchatPacket` ↔ 字节)
  - 14 字节 v1 包头（版本、类型、TTL、时间戳、标志、负载长度）
  - 8 字节发送者 ID，可选 8 字节接收者 ID
  - PKCS#7 填充到 256/512/1024/2048 块大小
  - 大端字节序
- [x] `BitchatMessage` 二进制编解码（标志、时间戳、ID、发送者、内容、可选字段）
- [x] 消息类型：announce(0x01)、message(0x02)、leave(0x03)、noiseHandshake(0x10)、noiseEncrypted(0x11)、fragment(0x20)、requestSync(0x21)、fileTransfer(0x22)
- [x] PeerID（8 字节截断，十六进制字符串表示）
- [x] IRC 命令解析器（/j、/msg、/w、/block、/clear、/pass、/transfer、/save）
- [x] 终端风格深色主题聊天屏幕 + 应用外壳
- [x] 单元测试 — 19 个通过（协议往返、填充、命令）

## 第二阶段 — 加密层 ✅ 完成

- [x] Ed25519/X25519 密钥生成
- [x] Noise 协议 XX 握手（3 消息模式）
  - `Noise_XX_25519_ChaChaPoly_SHA256`
  - 消息模式：→ e、← e ee s es、→ s se
- [x] Noise 会话管理器（创建、换钥、清理）
- [x] Noise 传输消息加解密
- [x] 频道加密（PBKDF2 密钥派生 + AES-256-GCM）
- [x] 安全密钥存储（flutter_secure_storage）
- [x] 指纹验证（静态公钥的哈希值）
- [x] 加密往返单元测试 — 11 个通过

## 第三阶段 — Nostr 协议 ✅ 完成

- [x] Nostr 事件模型（NIP-01）+ BIP-340 Schnorr 签名（secp256k1/pointycastle）
- [x] 带标签支持的订阅过滤器
- [x] WebSocket 中继管理器（连接、重连、订阅、去重、Geohash 路由）
- [x] Geohash 频道事件（kind 20000/20001）
- [x] NIP-17 gift wrap 过滤器支持
- [x] 单元测试 — 20 个通过

## 第四阶段 — BLE Mesh 网络 ✅ 完成

- [x] BLE 扫描 — 中心模式（flutter_blue_plus）
- [x] 节点发现和连接生命周期（BLEPeerManager）
- [x] 带 TTL 递减的消息中继
- [x] 分片/重组（默认 182 字节分片）
- [x] 消息去重（基于时间的已见集合）
- [x] 连接预算、指数退避、基于 RSSI 的优先级
- [x] 单元测试 — 14 个通过

## 第五阶段 — 用户界面 ✅ 完成

- [x] 频道列表 / 侧边栏导航（抽屉）
- [x] 带自动补全的 IRC 命令输入（建议芯片）
- [x] 带 RSSI 信号指示器的节点列表
- [x] 设置/个人资料屏幕（昵称、指纹、节点 ID）
- [x] 深色/浅色主题切换

## 第六阶段 — 完善与平台 ✅ 完成

- [x] 自适应电池管理（4 种电源模式：性能/均衡/省电/超省电）
- [x] 紧急清除（三击触发，安全存储清除）
- [x] Zlib 消息压缩（自动降级，1 字节头标记）
- [x] 掩护流量（密码学随机虚拟数据包）
- [x] 协议版本协商（8 字节握手，功能标志）
- [x] Tor 集成 — 存根（完整实现需要 Arti FFI）
- [x] 推送通知 — 存根（需要 flutter_local_notifications）
- [x] Nostr 中继实时通信（3 个公共中继，通过聊天 UI 收发）
- [x] 单元测试 — 27 个通过

---

## 第七阶段 — iOS 功能对齐（缺失功能）

> 原版 iOS `bitchat` 中有但 Flutter 版本缺失的功能。

### 7A — 媒体消息（高优先级）
- [x] **图片发送** — 选择/拍照 → 压缩至约 45KB JPEG → 去除 EXIF → 发送 ✅ Sprint 1
- [x] **图片显示** — 块状揭示动画、模糊/隐私模式 ✅ Sprint 1
- [x] **语音便签** — 录音、波形可视化、播放控制 ✅ Sprint 4
- [x] **语音编码** — AAC 编码（M4A）、16kHz 单声道、base64 传输 ✅ Sprint 4
- [x] **文件传输进度** — TransferProgressManager 状态机 + 进度 UI ✅ Sprint 13
- [x] **MIME 类型检测** — 60+ 扩展名，类型检查（图片/音频/视频/文档）✅ Sprint 13

### 7B — 私信（高优先级）
- [x] **1:1 加密私信** — NIP-04（ECDH + AES-256-CBC）加密私信 ✅ Sprint 3
- [x] **私信 UI** — 独立私信线程视图 ✅ Sprint 3
- [x] **已读回执** — ReadReceipt 模型 + JSON 序列化 ✅ Sprint 13
- [x] **送达状态 UI** — DeliveryTracker（待发/已发/已送达/已读/失败）✅ Sprint 13

### 7C — 身份与验证（中优先级）
- [x] **安全身份管理** — SHA-256 指纹、信任等级、JSON 导出 ✅ Sprint 6
- [x] **指纹验证** — 并排对比、验证/取消验证 ✅ Sprint 6
- [x] **二维码验证** — 基于指纹的确定性 QR 网格、匹配比较 ✅ Sprint 13
- [x] **信任等级** — unknown/casual/trusted/verified 节点状态 ✅ Sprint 6

### 7D — 位置与 Geohash 频道（中优先级）
- [x] **Geohash 频道** — Geohash 编解码/邻居，自动发现本地房间 ✅ Sprint 14
- [x] **位置频道地图** — GeohashChannel 带中心坐标 ✅ Sprint 14
- [x] **存在广播** — GeohashPresence 5 分钟新鲜度、公告 API ✅ Sprint 14
- [x] **参与者追踪** — 基于存在数据的每频道参与者列表 ✅ Sprint 14
- [x] **位置笔记** — LocationNote 固定到 geohash，CRUD 操作 ✅ Sprint 14
- [x] **频道书签** — 收藏/取消收藏 geohash 频道 ✅ Sprint 14

### 7E — Gossip 同步（中优先级）
- [x] **GCS Bloom 过滤器** — Golomb 编码集合用于消息去重同步 ✅ Sprint 10
- [x] **Gossip 协议** — GossipSyncManager 过滤器交換和缺失消息检测 ✅ Sprint 12
- [x] **请求同步** — SyncRequest + MessageRequest 用于显式消息请求 ✅ Sprint 12
- [x] **同步类型标志** — 位掩码用于消息/存在/文件/频道 ✅ Sprint 12

### 7F — BLE 外设与 Mesh（高优先级）
- [x] **统一节点服务** — UnifiedPeerService 合并 BLE+Nostr 节点，传输/质量追踪 ✅ Sprint 15
- [x] **网络激活** — NetworkMode（all/bleOnly/nostrOnly/auto）智能切换 ✅ Sprint 15

### 7G — 聊天 UI 增强（中优先级）
- [x] **消息格式化引擎** — 粗体、斜体、代码内联格式 ✅ Sprint 5
- [x] **链接检测** — URL 检测并设置下划线 + 蓝色样式 ✅ Sprint 7
- [x] **节点颜色调色板** — 基于 DJB2 哈希的每节点唯一颜色 ✅ Sprint 5
- [x] **速率限制器** — 令牌桶算法（突发 5、补充 1/秒、3 秒冷却）✅ Sprint 7
- [x] **矩阵加密动画** — 逐字符循环 + 交错揭示，连续循环 ✅ Sprint 9
- [x] **PoW 状态指示器** — 紧凑/详细模式，挖掘时旋转盾牌图标 ✅ Sprint 9
- [x] **支付芯片** — LightningPayment 模型 + PaymentChip 组件（BTC 橙色渐变）✅ Sprint 16
- [x] **输入验证** — 消息 ≤2000 字符，昵称 1-24 字符 ✅ Sprint 7
- [x] **收藏/书签** — 联系人屏幕，收藏、别名、信任徽章 ✅ Sprint 8
- [x] **公共时间线存储** — SQLite 持久消息历史 ✅ Sprint 2
- [x] **全屏图片查看器** — 点击查看全屏 ✅ Sprint 1

### 7H — 引导与权限（Android 专属，高优先级）
- [x] **引导流程** — 4 步欢迎流程（介绍、昵称、权限、就绪）✅ Sprint 10
- [x] **蓝牙检查屏幕** — PermissionService BLE/位置/麦克风状态追踪 ✅ Sprint 15
- [x] **位置检查屏幕** — 权限说明和状态检查 ✅ Sprint 15
- [x] **电池优化** — 权限检查（实际请求需要原生 Android API）✅ Sprint 16
- [x] **权限说明** — 用户友好的屏幕解释每项权限的用途 ✅ Sprint 10

### 7I — Tor 集成（Android 有完整实现）
- [x] **Tor 模式偏好** — TorPreferenceManager（off/whenAvailable/always 模式）✅ Sprint 16
- [x] **SOCKS 代理路由** — SOCKS5 代理配置、shouldRouteThrough 逻辑 ✅ Sprint 16

### 7J — 文件传输（Android 专属功能）
- [x] **文件选择器** — FilePickerService 选择模式、验证、大小限制 ✅ Sprint 16
- [x] **文件消息显示** — 文件名、大小、类型图标在聊天气泡中 ✅ Sprint 11
- [x] **文件发送动画** — 传输过程中的进度指示器 ✅ Sprint 11
- [x] **文件查看器** — FileViewerService 应用内预览检测 ✅ Sprint 16
- [x] **媒体选择器** — 统一图片/文件选择底部表格 ✅ Sprint 11

### 7K — 调试工具（Android 专属）
- [x] **调试设置面板** — 网络统计、加密信息、实验开关 ✅ Sprint 11
- [x] **Mesh 图形可视化** — 力导向布局 + 物理模拟 ✅ Sprint 12
- [x] **调试偏好** — 切换实验功能（PoW、掩护流量、压缩）✅ Sprint 11

### 7L — 本地化
- [x] **i18n/l10n** — L10n 管理器，10 种语言环境、50+ 键、中英日韩翻译 ✅ Sprint 15

---

## 第八阶段 — 剩余原生平台功能

> 这些功能需要 Swift/Kotlin/Rust 原生代码，无法在纯 Dart 中实现。

### 8A — BLE 外设与后台（需要原生代码）
- [x] **BLE 外设广播** — 平台通道 + Swift CBPeripheralManager + Kotlin BluetoothLeAdvertiser ✅ Sprint 18
- [x] **Android 前台服务** — MeshForegroundService 持久通知 + 停止按钮 ✅ Sprint 18
- [x] **开机自启** — BootCompletedReceiver + SharedPreferences 开关 ✅ Sprint 18

### 8B — Tor 原生集成（需要 Rust FFI）
- [x] **Arti Tor 客户端** — ArtiTorManager FFI 存根，bootstrap/shutdown 生命周期，SOCKS 代理 ✅ Sprint 18

---

## 第九阶段 — Mesh BLE 聊天集成 🔜

> 将 `BLEMeshService` 接入 Mesh 模式聊天 UI，实现真正的 BLE 蓝牙点对点通信。

### 9A — Mesh 模式聊天集成（高优先级）
- [ ] **Mesh 模式启动 BLE** — 用户选择 Mesh 模式时启动 `BLEMeshService` 扫描和连接
- [ ] **接收 BLE 消息** — 将收到的 `BitchatPacket` 消息显示在 Mesh 聊天 UI
- [ ] **通过 BLE 发送** — 发送聊天消息时通过 `BLEMeshService.broadcastPacket()` 广播
- [ ] **BLE 权限处理** — 按平台（Android/iOS/macOS）请求蓝牙权限
- [ ] **节点列表集成** — 将 `PeerListScreen` 接入实际的 `BLEMeshService` 已连接节点
- [ ] **连接状态显示** — 在 UI 中显示 BLE mesh 节点数量和连接状态

### 9B — 已知限制
- macOS `flutter_blue_plus` 仅支持 Central 角色（扫描），不支持 Peripheral（广播）
- BLE 范围约 10-30 米，需要两台设备都开启蓝牙
- iOS 后台 BLE 需要特定的 entitlements 和后台模式

---

## 跨平台协议兼容性

所有二进制格式必须与 iOS/Android 完全一致：
- 数据包头：14 字节 (v1) / 16 字节 (v2)
- 字节序：全程大端序
- 填充：PKCS#7 对齐到 256/512/1024/2048
- BLE UUID：相同的服务和特征 ID
- Noise：`Noise_XX_25519_ChaChaPoly_SHA256`
- Nostr：标准 NIP 事件格式
