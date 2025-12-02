# 私聊通讯系统开发经验总结 (L4-L5)

**日期**: 2025年12月2日
**项目**: tuzi-fuke (地球新主复刻版)
**功能**: L4 附近玩家通讯 + L5 一对一私聊系统

---

## 背景

在完成 L2 官方频道系统后，需要实现私聊功能：

- L4: 查找附近玩家（基于GPS距离）
- L5: 一对一私聊消息

---

## 与AI对话的经验

### 1. 遇到闪退问题时，描述具体触发时机

**无效的描述**:

```
私聊闪退了
```

**有效的描述**:

```
在私聊标签页底下有个幸存者对话列表，
点击列表里的任何一个对话就会闪退。
不是进入聊天界面后闪退，是点击列表项的时候就闪退。
```

**效果**: AI能精准定位是导航组件的问题，而不是聊天界面的问题。

### 2. 当AI改错文件时，明确指出正确路径

**问题场景**:
AI修改了 `/Users/mikeliu/Desktop/tuzi-fuke/` 目录下的文件，
但实际项目在 `/Users/mikeliu/Desktop/tuzi-fuke-communication/` 目录。

**有效的回应**:

```
？？？我们就是在/Users/mikeliu/Desktop/tuzi-fuke-communication 里做的啊？？
你又改错了，现在我在xcode里打开这个项目怎么那些频道都没了？
```

**教训**:

- 在对话开始时明确告诉AI工作目录
- 发现改错立即指出，不要等改了很多再说
- 多个相似名称的项目目录容易混淆

### 3. 让AI参考源项目的实现

**有效的提示词**:

```
还是闪退。。你要不要看看原文档怎么优化架构的？？
/Users/mikeliu/Desktop/tuzi-earthlord
```

**效果**:

- AI会对比源项目的导航架构
- 发现源项目用 `sheet` 而不是 `NavigationLink`
- 直接采用经过验证的模式

### 4. 两台设备测试时提供对比截图

**有效的描述**:

```
[截图1] 设备A显示"可通讯"
[截图2] 设备B显示"超出范围"
这两台手机就放在一起的，为什么显示不一样？
而且需要退出再进入才会更新位置。
```

**效果**: AI会检查：

- 位置上报是否实时
- 距离计算是否正确
- 缓存是否需要刷新

### 5. 问题要一起提，但让AI分步修复

**有效的提示词**:

```
我刚刚说的那些问题都一起修复吧？？
1. 点击对话闪退
2. 设备信息不显示
3. 位置不实时更新
```

**注意**:

- 先把所有问题列出来让AI了解全貌
- AI会判断优先级和依赖关系
- 修复时一个一个来，每次验证

---

## 技术实现经验

### 1. SwiftUI 导航架构的坑

**问题**: 在 TabView 嵌套的页面里使用 NavigationLink 会闪退

**原因分析**:

```
CommunicationHubView (有 NavigationView)
  └── TabView
       └── ConversationListView
            └── NavigationLink → DirectChatView  ❌ 闪退
```

**解决方案**: 使用 `sheet(item:)` 代替 NavigationLink

```swift
// ❌ 错误：在 TabView 内使用 NavigationLink
NavigationLink {
    DirectChatView(recipientId: ..., recipientName: ...)
} label: {
    ConversationRow(conversation: conversation)
}

// ✅ 正确：使用 sheet(item:)
@State private var selectedConversation: ConversationUser?

Button {
    selectedConversation = conversation
} label: {
    ConversationRow(conversation: conversation)
}
.sheet(item: $selectedConversation) { conversation in
    DirectChatView(
        recipientId: conversation.id,
        recipientName: conversation.displayName
    )
}
```

**关键点**:

- `sheet(item:)` 需要模型实现 `Identifiable` 协议
- 不需要额外的 NavigationView 包裹
- 切换更流畅，不会有导航栈问题

### 2. 数据模型必须实现 Identifiable

**用于 sheet(item:) 的模型**:

```swift
struct ConversationUser: Identifiable, Equatable {
    let id: UUID  // ← 必须有 id 属性
    let username: String
    // ...
}

struct NearbyPlayer: Identifiable, Codable {
    let id: UUID  // ← 必须有 id 属性
    let username: String
    // ...
}
```

### 3. 设备信息加载时机

**问题**: 设备信息有时候不显示

**原因**: 没有在正确的时机调用 `loadDevices()`

**解决方案**: 在需要设备信息的每个View的 `.task` 中都调用

```swift
.task {
    await deviceManager.loadDevices()  // ← 确保设备已加载
    await messageManager.loadConversations()
}
```

### 4. 附近玩家距离计算

**数据库函数**:

```sql
-- 使用 Haversine 公式计算距离
CREATE OR REPLACE FUNCTION get_nearby_players(
    p_user_id UUID,
    p_lat DOUBLE PRECISION,
    p_lon DOUBLE PRECISION,
    p_range_km DOUBLE PRECISION DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    username TEXT,
    distance_km DOUBLE PRECISION,
    -- ...
) AS $$
    SELECT
        u.id,
        u.username,
        (6371 * acos(
            cos(radians(p_lat)) * cos(radians(loc.latitude)) *
            cos(radians(loc.longitude) - radians(p_lon)) +
            sin(radians(p_lat)) * sin(radians(loc.latitude))
        )) as distance_km
    FROM users u
    JOIN player_locations_realtime loc ON u.id = loc.user_id
    WHERE u.id != p_user_id
    AND (6371 * acos(...)) <= p_range_km
    ORDER BY distance_km;
$$;
```

### 5. 位置实时上报

**问题**: 位置不实时更新，需要退出再进入

**解决方案**: 定期上报位置到 `player_locations_realtime` 表

```swift
// 在 NearbyPlayersView 中定期上报
.onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
    Task {
        await messageManager.reportCurrentLocation()
        await messageManager.loadNearbyPlayers()
    }
}
```

**数据库表**:

```sql
CREATE TABLE player_locations_realtime (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id),
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 遇到的问题清单

| 问题        | 原因                       | 解决方案            |
| --------- | ------------------------ | --------------- |
| 点击对话列表闪退  | TabView内使用NavigationLink | 改用 sheet(item:) |
| 设备信息不显示   | 没调用loadDevices()         | 在.task中加载设备     |
| 位置不实时更新   | 没有定期上报位置                 | 添加Timer定期上报     |
| 两台设备距离不一致 | 位置缓存问题                   | 每次都重新计算距离       |
| AI改错项目目录  | 多个相似目录名                  | 明确指出正确路径        |

---

## 文件结构

```
tuzi-fuke/
├── DirectMessage.swift           # 私聊消息 + 对话用户 + 附近玩家模型
├── DirectMessageManager.swift    # 私聊管理器（消息/附近玩家/Realtime）
├── DirectChatView.swift          # 一对一聊天界面
└── ConversationListView.swift    # 私聊列表 + 附近玩家选择界面
```

---

## 开发工作流

### 1. 先让AI分析源项目

如果有参考项目，先让AI读取并分析架构：

```
请分析 /path/to/source 目录下的私聊相关代码，
总结导航架构和数据流。
```

### 2. 遇到闪退优先检查导航架构

SwiftUI 闪退90%和导航有关：

- NavigationView 嵌套问题
- NavigationLink 在不当位置
- Sheet/FullScreenCover 生命周期问题

### 3. 双机测试位置相关功能

GPS距离功能必须用两台真机测试：

- 检查距离计算是否准确
- 检查位置更新是否及时
- 检查通讯范围判断是否正确

### 4. 错误时提供完整上下文

向AI报告问题时：

- 具体的操作步骤
- 截图（如果是UI问题）
- 控制台日志
- 错误发生的具体位置

---

## 与AI协作的核心经验

### 1. 明确工作目录

在对话开始时说清楚：

```
我们在 /Users/mikeliu/Desktop/tuzi-fuke-communication 项目工作
```

### 2. 发现问题立即指出

AI改错文件时立即打断：

```
你改错目录了，应该是 xxx 而不是 yyy
```

### 3. 让AI参考已验证的代码

有源项目时：

```
请参考 /path/to/source 的实现方式
```

### 4. 问题分批处理

多个问题时：

```
先列出所有问题，然后一个一个修复，每次验证
```

### 5. 提供对比信息

两台设备不一致时：

```
[截图A] [截图B] 为什么不一样？
```

---

## 总结

### 核心技术经验

1. **TabView内不要用NavigationLink**: 用 sheet(item:) 代替
2. **模型要实现Identifiable**: sheet(item:) 需要
3. **设备信息要主动加载**: 在每个需要的View的.task中调用
4. **位置要定期上报**: 用Timer定期更新player_locations_realtime
5. **距离用Haversine公式**: 在数据库函数中计算

### 与AI协作经验

1. **明确工作目录**: 避免改错项目
2. **具体描述问题触发时机**: 帮助定位问题
3. **让AI参考源项目**: 采用已验证的架构
4. **双机截图对比**: 发现同步问题
5. **分步修复验证**: 一次一个问题
