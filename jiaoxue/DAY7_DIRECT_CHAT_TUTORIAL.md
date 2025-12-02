# Day 7 私聊通讯系统教程 - 附近玩家与一对一私聊

**目标**: 实现附近玩家查找（L4）和一对一私聊功能（L5）
**时间**: 4-5小时
**开发模式**: AI辅助开发 - 通过AI提示词生成代码
**结果**: 用户可以查找附近玩家并进行一对一私聊

---

## 🤖 AI开发特点

本教程采用AI辅助开发模式：

- ✅ **提示词驱动**: 每个任务都提供完整的AI提示词
- ✅ **问题排查模板**: 遇到问题时如何向AI描述
- ✅ **架构避坑指南**: 避免SwiftUI导航常见问题
- ✅ **双机测试**: GPS功能必须双机验证

---

## 🎯 学习目标

完成本教程后，你将掌握：

- [ ] 设计私聊和附近玩家相关的数据库表
- [ ] 实现GPS距离计算（Haversine公式）
- [ ] 使用 sheet(item:) 实现安全的页面导航
- [ ] 实现实时位置上报和附近玩家查找
- [ ] 一对一私聊消息收发和实时推送

---

## 📋 前置准备

### 已完成的功能

- [x] Day 6 官方频道系统
- [x] Supabase 认证系统
- [x] 通讯设备管理（DeviceManager）
- [x] 基础 UI 框架

### 本日新增功能

- [ ] 附近玩家列表（基于GPS距离）
- [ ] 私聊对话列表
- [ ] 一对一聊天界面
- [ ] 私聊消息实时推送

---

## 🚀 任务1: 创建数据库表 (25分钟)

### 目标

创建私聊消息表和玩家位置实时表。

### 🤖 AI提示词 (Supabase SQL Editor)

```sql
-- ========================================
-- 私聊通讯系统数据库表
-- ========================================

-- 1. 私聊消息表
CREATE TABLE IF NOT EXISTS direct_messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    device_type TEXT,                    -- 发送者设备类型
    sender_lat DOUBLE PRECISION,         -- 发送者位置
    sender_lon DOUBLE PRECISION,
    distance_km DOUBLE PRECISION,        -- 与接收者的距离
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 玩家位置实时表（用于查找附近玩家）
CREATE TABLE IF NOT EXISTS player_locations_realtime (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. 启用 RLS
ALTER TABLE direct_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_locations_realtime ENABLE ROW LEVEL SECURITY;

-- 4. RLS 策略 - 私聊消息
-- 用户只能看到自己发送或接收的消息
CREATE POLICY "Users can read own messages" ON direct_messages
    FOR SELECT TO authenticated
    USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

CREATE POLICY "Users can send messages" ON direct_messages
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = sender_id);

-- 5. RLS 策略 - 玩家位置
-- 所有认证用户可读（用于查找附近玩家）
CREATE POLICY "Authenticated can read locations" ON player_locations_realtime
    FOR SELECT TO authenticated USING (true);

-- 用户只能更新自己的位置
CREATE POLICY "Users can upsert own location" ON player_locations_realtime
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own location" ON player_locations_realtime
    FOR UPDATE TO authenticated USING (auth.uid() = user_id);

-- 6. 启用 Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE direct_messages;

-- 7. 创建索引
CREATE INDEX IF NOT EXISTS idx_dm_sender ON direct_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_dm_recipient ON direct_messages(recipient_id);
CREATE INDEX IF NOT EXISTS idx_dm_created ON direct_messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_player_loc_updated ON player_locations_realtime(updated_at DESC);
```

### ✅ 验证

在 Supabase Dashboard → Table Editor 确认表已创建。

---

## 🚀 任务2: 创建附近玩家查询函数 (20分钟)

### 目标

使用 Haversine 公式计算玩家间距离。

### 🤖 AI提示词 (Supabase SQL Editor)

```sql
-- ========================================
-- 查询附近玩家的数据库函数
-- ========================================

CREATE OR REPLACE FUNCTION get_nearby_players(
    p_user_id UUID,
    p_lat DOUBLE PRECISION,
    p_lon DOUBLE PRECISION,
    p_range_km DOUBLE PRECISION DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    username TEXT,
    callsign TEXT,
    distance_km DOUBLE PRECISION,
    last_seen_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.raw_user_meta_data->>'username' as username,
        u.raw_user_meta_data->>'callsign' as callsign,
        -- Haversine 公式计算距离（单位：公里）
        (6371 * acos(
            LEAST(1.0, GREATEST(-1.0,
                cos(radians(p_lat)) * cos(radians(loc.latitude)) *
                cos(radians(loc.longitude) - radians(p_lon)) +
                sin(radians(p_lat)) * sin(radians(loc.latitude))
            ))
        )) as distance_km,
        loc.updated_at as last_seen_at
    FROM auth.users u
    JOIN player_locations_realtime loc ON u.id = loc.user_id
    WHERE u.id != p_user_id
    AND loc.updated_at > NOW() - INTERVAL '30 minutes'  -- 只显示30分钟内活跃的
    AND (6371 * acos(
        LEAST(1.0, GREATEST(-1.0,
            cos(radians(p_lat)) * cos(radians(loc.latitude)) *
            cos(radians(loc.longitude) - radians(p_lon)) +
            sin(radians(p_lat)) * sin(radians(loc.latitude))
        ))
    )) <= p_range_km
    ORDER BY distance_km;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### ⚠️ Haversine 公式说明

```
d = 6371 × acos(
    cos(lat1) × cos(lat2) × cos(lon2 - lon1) +
    sin(lat1) × sin(lat2)
)

其中：
- 6371 是地球半径（公里）
- lat1, lon1 是第一个点的纬度、经度（弧度）
- lat2, lon2 是第二个点的纬度、经度（弧度）
- d 是两点间的距离（公里）
```

---

## 🚀 任务3: 创建位置上报函数 (15分钟)

### 目标

允许玩家上报自己的位置。

### 🤖 AI提示词 (Supabase SQL Editor)

```sql
-- ========================================
-- 上报玩家位置的函数
-- ========================================

CREATE OR REPLACE FUNCTION update_player_location(
    p_lat DOUBLE PRECISION,
    p_lon DOUBLE PRECISION
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO player_locations_realtime (user_id, latitude, longitude, updated_at)
    VALUES (auth.uid(), p_lat, p_lon, NOW())
    ON CONFLICT (user_id)
    DO UPDATE SET
        latitude = p_lat,
        longitude = p_lon,
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## 🚀 任务4: 创建 Swift 数据模型 (20分钟)

### 目标

创建 DirectMessage.swift 文件。

### 🤖 AI提示词

```
请帮我创建 DirectMessage.swift，包含以下模型：

1. DirectMessage 结构体（私聊消息）：
   - id: UUID
   - senderId: UUID (映射 sender_id)
   - recipientId: UUID (映射 recipient_id)
   - content: String
   - deviceType: String (映射 device_type)
   - senderLat: Double? (映射 sender_lat)
   - senderLon: Double? (映射 sender_lon)
   - distanceKm: Double? (映射 distance_km)
   - isRead: Bool (映射 is_read)
   - createdAt: Date (映射 created_at)

   计算属性：
   - formattedTime: String（显示时间）
   - distanceText: String?（显示距离，如"500m"或"2.3km"）

2. ConversationUser 结构体（对话列表用户）：
   - id: UUID
   - username: String
   - callsign: String?
   - lastMessage: String?
   - lastMessageTime: Date?
   - unreadCount: Int
   - distanceKm: Double?

   计算属性：
   - displayName: String（优先显示callsign）
   - formattedLastTime: String?
   - distanceText: String?
   - isInRange(deviceRangeKm:) -> Bool

3. NearbyPlayer 结构体（附近玩家）：
   - id: UUID
   - username: String
   - callsign: String?
   - distanceKm: Double (映射 distance_km)
   - lastSeenAt: Date? (映射 last_seen_at)

   计算属性：
   - displayName: String
   - distanceText: String
   - isOnline: Bool（5分钟内活跃算在线）

所有模型实现 Codable, Identifiable 协议。
ConversationUser 额外实现 Equatable 协议（用于 sheet(item:)）。
```

### ⚠️ 重要：必须实现 Identifiable

```swift
// 用于 sheet(item:) 的模型必须实现 Identifiable
struct ConversationUser: Identifiable, Equatable {
    let id: UUID  // ← 必须有
    // ...
}

struct NearbyPlayer: Identifiable, Codable {
    let id: UUID  // ← 必须有
    // ...
}
```

---

## 🚀 任务5: 创建 DirectMessageManager (45分钟)

### 目标

创建私聊管理器处理消息和附近玩家。

### 🤖 AI提示词

```
请帮我创建 DirectMessageManager.swift，要求：

1. 使用单例模式 + @MainActor
2. Published 属性：
   - conversations: [ConversationUser]     // 对话列表
   - nearbyPlayers: [NearbyPlayer]         // 附近玩家
   - currentMessages: [DirectMessage]      // 当前聊天的消息
   - isLoading: Bool
   - errorMessage: String?

3. 公开方法：
   - loadConversations() async             // 加载对话列表
   - loadNearbyPlayers() async             // 加载附近玩家
   - loadMessages(with userId: UUID) async // 加载与某人的聊天记录
   - sendMessage(to recipientId: UUID, content: String) async throws
   - reportCurrentLocation() async         // 上报当前位置
   - canCommunicateWith(userId: UUID) -> (canSend: Bool, reason: String?)
   - stopSubscription() async              // 停止Realtime订阅

4. 实现细节：
   - 使用 REST API 调用
   - 使用 Supabase Realtime 订阅私聊消息
   - 距离判断需要结合 DeviceManager 的设备范围
   - 消息按时间排序（旧的在上）

5. Realtime 订阅：
   - 订阅 direct_messages 表
   - 过滤条件：recipient_id = 当前用户
   - 新消息到达时在 MainActor 上更新 UI

参考项目中 ChannelManager.swift 的代码风格。
```

### ⚠️ 通讯范围判断

```swift
func canCommunicateWith(userId: UUID) -> (canSend: Bool, reason: String?) {
    // 1. 检查是否有设备
    guard let device = DeviceManager.shared.activeDevice else {
        return (false, "无通讯设备")
    }

    // 2. 检查设备是否可发送
    guard device.canSend else {
        return (false, "当前设备仅能接收")
    }

    // 3. 检查对方是否在范围内
    if let player = nearbyPlayers.first(where: { $0.id == userId }) {
        if player.distanceKm > device.effectiveRangeKm {
            return (false, "对方超出通讯范围 (\(String(format: "%.1f", player.distanceKm))km)")
        }
    }

    return (true, nil)
}
```

---

## 🚀 任务6: 创建私聊列表界面 (40分钟)

### 目标

创建 ConversationListView.swift。

### ⚠️ 架构避坑：不要在 TabView 内使用 NavigationLink

**问题描述**:

```
CommunicationHubView (有 NavigationView)
  └── TabView
       └── ConversationListView
            └── NavigationLink → DirectChatView  ❌ 会闪退！
```

**解决方案**: 使用 `sheet(item:)` 代替 NavigationLink

### 🤖 AI提示词

```
请帮我创建 ConversationListView.swift，要求：

⚠️ 重要：因为这个View嵌套在TabView里，不能使用NavigationLink！
必须使用 sheet(item:) 来打开聊天界面。

1. 状态变量：
   - @StateObject messageManager = DirectMessageManager.shared
   - @StateObject deviceManager = DeviceManager.shared
   - @State showNearbyPlayers: Bool
   - @State selectedConversation: ConversationUser?  // 用于 sheet

2. 界面结构：
   - 顶部设备状态栏（显示通讯范围 + 附近玩家按钮）
   - 如果没有对话：空状态提示
   - 如果有对话：对话列表

3. 对话列表：
   - 使用 Button + .sheet(item:) 而不是 NavigationLink
   - 点击时设置 selectedConversation
   - sheet 打开 DirectChatView

4. 对话行 (ConversationRow)：
   - 头像（首字母）
   - 名称 + 距离
   - 最后一条消息（预览）
   - 时间 + 未读数

5. 生命周期：
   - .task 中加载设备和对话列表
   - 两个 .sheet：一个给附近玩家，一个给聊天界面

示例代码结构：
```swift
@State private var selectedConversation: ConversationUser?

var body: some View {
    VStack {
        // ... UI
        List {
            ForEach(messageManager.conversations) { conversation in
                Button {
                    selectedConversation = conversation
                } label: {
                    ConversationRow(conversation: conversation)
                }
                .buttonStyle(.plain)
            }
        }
    }
    .sheet(item: $selectedConversation) { conversation in
        DirectChatView(
            recipientId: conversation.id,
            recipientName: conversation.displayName
        )
    }
}
```

参考项目中 ChannelListView.swift 的代码风格。

```
---

## 🚀 任务7: 创建附近玩家视图 (30分钟)

### 目标

创建 NearbyPlayersView（在 ConversationListView.swift 中）。

### 🤖 AI提示词
```

请在 ConversationListView.swift 中添加 NearbyPlayersView，要求：

1. 状态变量：
   
   - @StateObject messageManager = DirectMessageManager.shared
   - @StateObject deviceManager = DeviceManager.shared
   - @State selectedPlayer: NearbyPlayer?

2. 界面结构：
   
   - 设备范围信息栏
   - 玩家列表或空状态

3. 玩家行 (NearbyPlayerRow)：
   
   - 头像 + 在线状态指示
   - 名称 + 距离
   - 是否在通讯范围（可通讯/超出范围）

4. 交互：
   
   - 点击玩家行设置 selectedPlayer
   - .sheet(item: $selectedPlayer) 打开 DirectChatView

5. 定期刷新：
   
   - .task 中加载设备和附近玩家
   - Timer 每15秒上报位置并刷新列表
     
     ```
     
     ```

---

## 🚀 任务8: 创建聊天界面 (40分钟)

### 目标

创建 DirectChatView.swift。

### 🤖 AI提示词

```
请帮我创建 DirectChatView.swift，要求：

1. 参数：
   - recipientId: UUID
   - recipientName: String

2. 状态变量：
   - @StateObject messageManager = DirectMessageManager.shared
   - @StateObject deviceManager = DeviceManager.shared
   - @State messageText: String
   - @State isSending: Bool
   - @FocusState isInputFocused: Bool

3. 界面结构：
   - 自定义导航栏（返回按钮 + 对方名称 + 在线状态）
   - 通讯状态栏（显示设备信息或超出范围警告）
   - 消息列表 (ScrollView + LazyVStack)
   - 输入栏

4. 消息气泡 (DirectMessageBubble)：
   - 自己发的：蓝色背景，右对齐
   - 对方发的：灰色背景，左对齐
   - 显示时间和距离

5. 输入栏：
   - TextField + 发送按钮
   - 超出范围时禁用输入
   - 显示提示信息

6. 生命周期：
   - .task 加载设备和消息
   - .onDisappear 停止Realtime订阅

7. 通讯状态计算：
   - 使用 messageManager.canCommunicateWith(userId:) 判断
   - 不能发送时显示原因
```

---

## 🚀 任务9: 集成到通讯中心 (15分钟)

### 目标

确保 ConversationListView 正确嵌入 CommunicationHubView。

### 检查清单

```swift
// CommunicationHubView.swift
TabView(selection: $selectedTab) {
    CommsMessageView()
        .tag(0)

    CommsChannelView()
        .tag(1)

    ConversationListView()  // ← 确保已添加
        .tag(2)

    CommsDeviceView()
        .tag(3)
}
```

---

## 🚀 任务10: 双机测试 (30分钟)

### 目标

验证两台设备的私聊功能。

### 测试步骤

1. **设备A和B都登录不同账户**

2. **测试附近玩家**:
   
   - 两台手机放在一起
   - 设备A 打开"附近幸存者"
   - 应该能看到设备B
   - 距离应该显示很近（几十米内）

3. **测试私聊消息**:
   
   - 设备A 点击设备B开始聊天
   - 发送一条消息
   - 设备B 应该实时收到

4. **测试距离限制**:
   
   - 将设备A移动到远处（超出通讯范围）
   - 输入框应该变灰，显示"超出范围"

### 🤖 排查问题的AI提示词

**如果附近玩家不显示**:

```
帮我查一下数据库：
1. player_locations_realtime 表里有位置记录吗？
2. get_nearby_players 函数调用是否正常？
3. 两个用户的位置坐标是多少？距离是多少公里？
```

**如果消息不显示**:

```
帮我查一下：
1. direct_messages 表里有新消息吗？
2. Realtime 订阅是否成功？
3. 看一下控制台日志有没有错误
```

**如果点击闪退**:

```
点击对话列表的时候闪退：
1. 这个View是嵌套在TabView里的
2. 我用的是 NavigationLink 还是 sheet？
3. 请检查导航架构
```

---

## 🚨 常见问题汇总

### Q1: 点击对话列表闪退

**原因**: 在 TabView 内使用了 NavigationLink

**解决**: 改用 sheet(item:)

```swift
// ❌ 错误
NavigationLink { ... }

// ✅ 正确
@State private var selectedConversation: ConversationUser?

Button { selectedConversation = conversation }
.sheet(item: $selectedConversation) { ... }
```

### Q2: 附近玩家不显示

**原因**: 没有上报位置，或位置过期

**解决**:

1. 确保调用了 `reportCurrentLocation()`
2. 检查 SQL 函数中的过期时间（30分钟）

### Q3: 距离显示不准确

**原因**: GPS 精度问题或计算错误

**解决**:

1. 检查 Haversine 公式是否正确
2. 确保经纬度单位是度而不是弧度

### Q4: 消息发送后对方没收到

**原因**: Realtime 订阅问题

**解决**:

1. 检查 RLS 策略
2. 检查 Realtime publication 是否包含表
3. 检查订阅过滤条件

### Q5: 设备信息不显示

**原因**: 没有调用 loadDevices()

**解决**: 在 .task 中加载

```swift
.task {
    await deviceManager.loadDevices()
    await messageManager.loadConversations()
}
```

---

## 📊 本日学习总结

### 技术栈

| 技术                   | 用途             |
| -------------------- | -------------- |
| Supabase Database    | 私聊消息、玩家位置存储    |
| Supabase Realtime    | 私聊消息实时推送       |
| PostgreSQL 函数        | Haversine 距离计算 |
| SwiftUI sheet(item:) | 安全的页面导航        |
| CoreLocation         | 获取GPS位置        |

### AI协作要点

1. **明确工作目录**: 避免AI改错项目
2. **描述具体触发时机**: "点击列表项闪退" 比 "闪退了" 有用
3. **让AI参考源项目**: 已验证的架构更可靠
4. **双机截图对比**: 发现GPS相关问题
5. **分步修复验证**: 一次一个问题

### 核心经验

1. **TabView内不用NavigationLink**: 用 sheet(item:) 代替
2. **模型必须实现Identifiable**: sheet(item:) 需要
3. **位置要定期上报**: 每15秒更新一次
4. **距离用数据库计算**: Haversine 公式在 SQL 函数中
5. **通讯范围要验证**: 结合设备信息判断

---

## 🎯 扩展任务（可选）

完成基础功能后，可以继续实现：

### 消息已读状态

- 对方查看后标记已读
- 显示已读/未读状态

### 消息通知

- 本地通知提醒
- 角标显示未读数

### 历史消息搜索

- 搜索聊天记录
- 按日期筛选

### 位置分享

- 发送当前位置
- 在地图上查看对方位置

---

**恭喜完成 Day 7！** 🎉

你已经掌握了私聊通讯系统的开发，包括：

- 附近玩家查找（GPS + Haversine）
- 一对一私聊消息
- SwiftUI 安全导航架构
- Realtime 消息推送
