# Day 6 官方频道系统教程 - Supabase 频道订阅与实时消息

**目标**: 实现官方频道列表、订阅功能、频道消息实时推送
**时间**: 3-4小时
**开发模式**: AI辅助开发 - 通过AI提示词生成代码
**结果**: 用户可以订阅官方频道并实时收到频道消息

---

## 🤖 AI开发特点

本教程采用AI辅助开发模式：

- ✅ **提示词驱动**: 每个任务都提供完整的AI提示词
- ✅ **问题排查模板**: 遇到问题时如何向AI描述
- ✅ **截图对比**: 用截图让AI看到实际效果
- ✅ **数据库验证**: 让AI帮你查数据库确认数据

---

## 🎯 学习目标

完成本教程后，你将掌握：

- [ ] 设计频道相关的数据库表
- [ ] 创建自动更新计数的触发器
- [ ] 使用 pg_cron 定时发送消息
- [ ] 实现频道订阅/取消订阅
- [ ] Supabase Realtime 频道消息订阅
- [ ] SwiftUI 频道列表界面

---

## 📋 前置准备

### 已完成的功能

- [x] Day 5 通讯系统（ChatManager、消息发送接收）
- [x] Supabase 认证系统
- [x] 基础 UI 框架

### 本日新增功能

- [ ] 官方频道列表
- [ ] 频道订阅/取消订阅
- [ ] 频道消息显示
- [ ] 服务器自动发送频道消息

---

## 🚀 任务1: 创建数据库表 (20分钟)

### 目标

创建频道、订阅、消息三张表。

### 🤖 AI提示词 (Supabase SQL Editor)

```sql
-- ========================================
-- 官方频道系统数据库表
-- ========================================

-- 1. 频道表
CREATE TABLE IF NOT EXISTS communication_channels (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    channel_name TEXT NOT NULL,
    channel_code TEXT UNIQUE,
    channel_type TEXT DEFAULT 'official',
    description TEXT,
    icon TEXT,
    subscriber_count INTEGER DEFAULT 0,
    message_count INTEGER DEFAULT 0,
    is_public BOOLEAN DEFAULT TRUE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 频道订阅表
CREATE TABLE IF NOT EXISTS channel_subscriptions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    channel_id UUID NOT NULL REFERENCES communication_channels(id) ON DELETE CASCADE,
    subscribed_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, channel_id)
);

-- 3. 频道消息表
CREATE TABLE IF NOT EXISTS channel_messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    channel_id UUID NOT NULL REFERENCES communication_channels(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES auth.users(id),
    sender_name TEXT,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'user',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. 启用 RLS
ALTER TABLE communication_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_messages ENABLE ROW LEVEL SECURITY;

-- 5. RLS 策略
-- 频道：所有人可读
CREATE POLICY "Anyone can read channels" ON communication_channels
    FOR SELECT USING (true);

-- 订阅：用户只能管理自己的订阅
CREATE POLICY "Users can read own subscriptions" ON channel_subscriptions
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY "Users can subscribe" ON channel_subscriptions
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can unsubscribe" ON channel_subscriptions
    FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- 消息：认证用户可读
CREATE POLICY "Authenticated can read channel messages" ON channel_messages
    FOR SELECT TO authenticated USING (true);

-- 6. 启用 Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE channel_messages;

-- 7. 创建索引
CREATE INDEX IF NOT EXISTS idx_channel_subscriptions_user ON channel_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_channel_subscriptions_channel ON channel_subscriptions(channel_id);
CREATE INDEX IF NOT EXISTS idx_channel_messages_channel ON channel_messages(channel_id);
CREATE INDEX IF NOT EXISTS idx_channel_messages_created ON channel_messages(created_at DESC);
```

### ✅ 验证

在 Supabase Dashboard → Table Editor 确认三张表已创建。

---

## 🚀 任务2: 创建订阅计数触发器 (15分钟)

### 目标

当用户订阅/取消订阅时，自动更新 `subscriber_count`。

### 🤖 AI提示词 (Supabase SQL Editor)

```sql
-- ========================================
-- 订阅计数自动更新触发器
-- ========================================

-- 重要：使用 COUNT(*) 而不是 +1/-1，避免计数不同步

CREATE OR REPLACE FUNCTION update_channel_subscriber_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE communication_channels
        SET subscriber_count = (
            SELECT COUNT(*) FROM channel_subscriptions
            WHERE channel_id = NEW.channel_id
        )
        WHERE id = NEW.channel_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE communication_channels
        SET subscriber_count = (
            SELECT COUNT(*) FROM channel_subscriptions
            WHERE channel_id = OLD.channel_id
        )
        WHERE id = OLD.channel_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 删除旧触发器（如果存在）
DROP TRIGGER IF EXISTS trigger_update_subscriber_count ON channel_subscriptions;

-- 创建新触发器
CREATE TRIGGER trigger_update_subscriber_count
    AFTER INSERT OR DELETE ON channel_subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION update_channel_subscriber_count();
```

### ⚠️ 为什么用 COUNT(*) 而不是 +1/-1？

```
错误方式：subscriber_count = subscriber_count + 1
问题：如果触发器执行失败或并发问题，计数会不准确

正确方式：subscriber_count = (SELECT COUNT(*) FROM ...)
优点：每次都重新计算真实数量，永远准确
```

---

## 🚀 任务3: 插入官方频道数据 (10分钟)

### 目标

创建4个官方频道。

### 🤖 AI提示词 (Supabase SQL Editor)

```sql
-- ========================================
-- 插入官方频道
-- ========================================

INSERT INTO communication_channels (id, channel_name, channel_code, channel_type, description, icon)
VALUES
    ('00000001-0000-0000-0000-000000000001', '生存指南频道', 'OFF-SURVIVAL', 'official', '全球幸存者生存指南，播报生存技巧和资源位置', 'leaf.fill'),
    ('00000001-0000-0000-0000-000000000002', '幸存者新闻', 'OFF-NEWS', 'official', '幸存者新闻网络，播报最新动态和情报', 'newspaper.fill'),
    ('00000001-0000-0000-0000-000000000003', '每日任务', 'OFF-MISSION', 'official', '每日任务系统，播报任务和奖励', 'target'),
    ('00000001-0000-0000-0000-000000000004', '紧急广播', 'OFF-ALERT', 'official', '紧急广播频道，播报紧急警报和重要通知', 'exclamationmark.triangle.fill')
ON CONFLICT (channel_code) DO NOTHING;
```

---

## 🚀 任务4: 创建自动发送消息函数 (20分钟)

### 目标

创建一个函数，每分钟自动给随机频道发送消息。

### 🤖 AI提示词 (Supabase SQL Editor)

```sql
-- ========================================
-- 自动发送频道消息的函数
-- ========================================

CREATE OR REPLACE FUNCTION send_random_channel_message()
RETURNS VOID AS $$
DECLARE
    v_channel_id UUID;
    v_messages TEXT[];
    v_message TEXT;
    v_channel_code TEXT;
BEGIN
    -- 随机选择一个官方频道
    SELECT id, channel_code INTO v_channel_id, v_channel_code
    FROM communication_channels
    WHERE channel_type = 'official'
    ORDER BY RANDOM()
    LIMIT 1;

    -- 根据频道类型选择消息
    CASE v_channel_code
        WHEN 'OFF-SURVIVAL' THEN
            v_messages := ARRAY[
                '【生存技巧】收集雨水是获取饮用水的好方法。记得用干净的容器储存。',
                '【安全提醒】独自外出时，告诉营友你的目的地和预计返回时间。',
                '【资源情报】废弃的加油站常常有被忽视的物资，但要小心可能的危险。',
                '【生存知识】学会辨别可食用的野生植物，可以在紧急时刻救命。',
                '【天气预警】观察云层变化可以预测天气，积雨云意味着暴风雨即将来临。',
                '【急救常识】止血带只能用于四肢，且每30分钟需要松开一次。',
                '【营地建设】选择营地时要考虑水源、遮蔽和逃生路线。'
            ];
        WHEN 'OFF-NEWS' THEN
            v_messages := ARRAY[
                '【快讯】东部区域发现新的幸存者聚落，正在建立联系中。',
                '【气象】未来24小时天气晴朗，适合外出探索。',
                '【公告】物资交换站将于明日开放，欢迎前往交易。',
                '【情报】北部山区信号塔已修复，通讯范围扩大。',
                '【社区】新的合作协议已达成，各营地将共享资源信息。',
                '【发现】考古队在废墟中发现了重要的历史文献。',
                '【庆祝】本月已有50名新幸存者加入我们的网络！'
            ];
        WHEN 'OFF-MISSION' THEN
            v_messages := ARRAY[
                '【日常任务】探索1个新区域，奖励：探索经验+30',
                '【收集任务】收集5单位水资源，奖励：生存积分+20',
                '【建造任务】升级一个建筑，奖励：建设经验+50',
                '【社交任务】与其他幸存者交流3次，奖励：声望+10',
                '【挑战任务】连续7天登录，奖励：稀有物资包',
                '【团队任务】组队完成区域清理，奖励：团队徽章',
                '【限时任务】在日落前返回营地，奖励：安全积分+25'
            ];
        WHEN 'OFF-ALERT' THEN
            v_messages := ARRAY[
                '⚠️【天气警报】强风预警，请加固帐篷和临时建筑。',
                '🚨【安全提示】近期有不明人员出没，请保持警惕。',
                '⚠️【资源警告】西部水源疑似污染，请勿饮用。',
                '🔔【系统通知】服务器将在凌晨进行维护，预计持续1小时。',
                '⚠️【区域封锁】北部3区因安全原因暂时封闭。',
                '🚨【紧急求助】有幸存者在坐标(23.2, 114.4)附近需要帮助！'
            ];
        ELSE
            v_messages := ARRAY['系统消息：保持警惕，注意安全。'];
    END CASE;

    -- 随机选择一条消息
    v_message := v_messages[1 + floor(random() * array_length(v_messages, 1))::int];

    -- 插入消息
    INSERT INTO channel_messages (channel_id, sender_name, content, message_type)
    VALUES (v_channel_id, NULL, v_message, 'system');

    -- 更新频道消息计数
    UPDATE communication_channels
    SET message_count = message_count + 1
    WHERE id = v_channel_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## 🚀 任务5: 启用 pg_cron 定时任务 (15分钟)

### 目标

每分钟自动调用发送消息函数。

### 步骤1: 启用 pg_cron 扩展

1. Supabase Dashboard → Database → Extensions
2. 搜索 `pg_cron`
3. 点击启用

### 步骤2: 创建定时任务

```sql
-- 每分钟执行一次
SELECT cron.schedule(
    'channel-message-sender',
    '* * * * *',
    'SELECT send_random_channel_message()'
);

-- 查看已创建的任务
SELECT * FROM cron.job;
```

### ✅ 验证

等待1-2分钟，然后查询消息表：

```sql
SELECT * FROM channel_messages ORDER BY created_at DESC LIMIT 5;
```

---

## 🚀 任务6: 创建 Swift 数据模型 (20分钟)

### 目标

创建 CommunicationChannel.swift 文件。

### 🤖 AI提示词

```
请帮我创建 CommunicationChannel.swift，包含以下模型：

1. CommunicationChannel 结构体：
   - id: UUID
   - channelName: String (映射 channel_name)
   - channelCode: String? (映射 channel_code)
   - channelType: String? (映射 channel_type)
   - description: String?
   - icon: String?
   - subscriberCount: Int (映射 subscriber_count)
   - messageCount: Int (映射 message_count)
   - isPublic: Bool (映射 is_public)
   - createdAt: Date (映射 created_at)

   计算属性：
   - isOfficial: Bool (channelType == "official")
   - displayIcon: String (返回 icon 或默认图标)

2. ChannelSubscription 结构体：
   - id: UUID
   - userId: UUID (映射 user_id)
   - channelId: UUID (映射 channel_id)
   - subscribedAt: Date (映射 subscribed_at)

3. ChannelMessage 结构体：
   - id: UUID
   - channelId: UUID (映射 channel_id)
   - senderId: UUID? (映射 sender_id)
   - senderName: String? (映射 sender_name)
   - content: String
   - messageType: String (映射 message_type)
   - createdAt: Date (映射 created_at)

   计算属性：
   - isSystemMessage: Bool (messageType == "system")
   - displaySenderName: String
   - formattedTime: String

所有模型实现 Codable, Identifiable, Sendable 协议。
参考项目中 Message.swift 的风格。
```

---

## 🚀 任务7: 创建 ChannelManager (45分钟)

### 目标

创建频道管理器处理订阅和消息。

### 🤖 AI提示词

```
请帮我创建 ChannelManager.swift，要求：

1. 使用单例模式 + @MainActor
2. Published 属性：
   - officialChannels: [CommunicationChannel]
   - subscribedChannels: [CommunicationChannel]
   - currentChannel: CommunicationChannel?
   - currentChannelMessages: [ChannelMessage]
   - isLoading: Bool
   - errorMessage: String?

3. 公开方法：
   - loadOfficialChannels() async
   - loadSubscribedChannels() async
   - subscribeToChannel(_ channel) async -> Bool
   - unsubscribeFromChannel(_ channel) async -> Bool
   - isSubscribed(to channel) -> Bool
   - selectChannel(_ channel) async
   - loadChannelMessages(for channel) async

4. 实现细节：
   - 使用 REST API 调用（避免 Swift 6 并发问题）
   - 使用 Supabase Realtime 订阅频道消息
   - 频道列表按 channel_code 排序（保证所有设备顺序一致）
   - 消息加载：获取最新50条，然后反转顺序

5. Realtime 订阅：
   - 只订阅当前选中频道的消息
   - 切换频道时取消旧订阅，创建新订阅
   - 新消息到达时在 MainActor 上更新 UI

参考项目中 ChatManager.swift 的代码风格。
```

### ⚠️ 常见问题

**消息加载顺序错误**:

```swift
// 错误：获取最早的50条
URLQueryItem(name: "order", value: "created_at.asc")

// 正确：获取最新的50条，然后反转
URLQueryItem(name: "order", value: "created_at.desc")
let messages = try decoder.decode([ChannelMessage].self, from: data)
return messages.reversed()  // 旧的在上，新的在下
```

---

## 🚀 任务8: 创建频道列表界面 (30分钟)

### 目标

创建 ChannelListView.swift。

### 🤖 AI提示词

```
请帮我创建 ChannelListView.swift，要求：

1. 使用 @StateObject 观察 ChannelManager.shared
2. 界面结构：
   - 顶部：Segmented Picker（官方频道 / 我的订阅）
   - 列表：频道卡片
   - 频道卡片显示：图标、名称、描述、订阅人数、订阅按钮

3. 频道卡片 (ChannelCard)：
   - 圆形图标背景 + SF Symbol
   - 频道名称 + 官方认证标记
   - 频道描述（最多2行）
   - 订阅人数
   - 订阅/已订阅 按钮

4. 功能：
   - 点击频道卡片：选中频道并关闭列表
   - 点击订阅按钮：订阅/取消订阅
   - 官方频道用不同颜色区分

5. 生命周期：
   - onAppear 加载官方频道和已订阅频道

参考项目中其他 View 的代码风格。
```

---

## 🚀 任务9: 集成到 ChatView (20分钟)

### 目标

在 ChatView 中添加频道选择功能。

### 🤖 AI提示词

```
请修改 ChatView.swift，添加频道功能：

1. 添加 @StateObject channelManager = ChannelManager.shared
2. 添加 @State showChannelList: Bool

3. 导航栏添加频道选择按钮（左侧）：
   - 图标：antenna.radiowaves.left.and.right + chevron.down
   - 点击显示 ChannelListView (sheet)

4. 导航标题：
   - 如果选中了频道：显示频道名称
   - 否则：显示"广播频道"

5. 消息列表修改：
   - 如果 currentChannel != nil：显示 channelManager.currentChannelMessages
   - 否则：显示 chatManager.messages

6. 添加频道消息气泡 (ChannelMessageBubble)：
   - 系统消息：居中显示，橙色背景
   - 用户消息：左对齐，灰色背景
   - 时间显示在消息上方

7. 官方频道输入限制：
   - 如果是官方频道：禁用输入框，显示提示"官方频道仅供收听"
```

---

## 🚀 任务10: 测试双机同步 (20分钟)

### 目标

验证两台设备的频道订阅和消息同步。

### 测试步骤

1. **设备A和B都登录不同账户**

2. **测试订阅同步**:
   
   - 设备A 订阅"生存指南频道"
   - 刷新设备B 的频道列表
   - 确认订阅人数增加

3. **测试消息实时推送**:
   
   - 设备A 和 B 都进入同一个频道
   - 等待 pg_cron 发送消息
   - 确认两台设备都收到消息

4. **测试列表顺序**:
   
   - 对比两台设备的频道列表顺序
   - 应该完全一致

### 🤖 排查问题的AI提示词

**如果订阅人数不更新**:

```
帮我查一下数据库：
1. channel_subscriptions 表里有我的订阅记录吗？
2. communication_channels 表里 subscriber_count 是多少？
3. 触发器是否正确执行？
```

**如果消息不显示**:

```
帮我查一下：
1. channel_messages 表最近有新消息吗？
2. pg_cron 任务是否在执行？
3. Realtime 订阅是否成功？
看一下控制台日志有没有相关输出。
```

**如果列表顺序不一致**:

```
两台手机的频道列表顺序不一样：
[截图1] [截图2]
请检查排序逻辑，应该按 channel_code 排序。
```

---

## 🚨 常见问题汇总

### Q1: 订阅后计数还是0

**原因**: 触发器可能用了 +1/-1 方式

**解决**: 使用 COUNT(*) 重新计算

```sql
SET subscriber_count = (SELECT COUNT(*) FROM channel_subscriptions WHERE channel_id = NEW.channel_id)
```

### Q2: 看不到历史消息

**原因**: 加载时用了 `order=created_at.asc` + `limit=50`

**解决**: 改为 `order=created_at.desc`，然后在客户端 `reversed()`

### Q3: 实时消息不出现

**原因**: 没在 MainActor 上更新 UI

**解决**:

```swift
await MainActor.run {
    self.currentChannelMessages.append(message)
}
```

### Q4: 不同手机列表顺序不同

**原因**: 没有固定排序

**解决**: 按 channel_code 排序

```swift
subscribedChannels = channels.sorted { ($0.channelCode ?? "") < ($1.channelCode ?? "") }
```

### Q5: 只有一个频道收到消息

**原因**: 这是正常的！pg_cron 每分钟随机选一个频道发送

**解决**: 不需要修复，或者改成轮流发送

---

## 📊 本日学习总结

### 技术栈

| 技术                | 用途         |
| ----------------- | ---------- |
| Supabase Database | 频道、订阅、消息存储 |
| Supabase Realtime | 频道消息实时推送   |
| pg_cron           | 定时自动发送消息   |
| PostgreSQL 触发器    | 自动更新订阅计数   |
| SwiftUI           | 频道列表界面     |

### AI协作要点

1. **提供截图**: 让AI看到实际界面效果
2. **提供日志**: 粘贴控制台输出帮助定位问题
3. **描述预期vs实际**: 清晰对比更容易修复
4. **让AI查数据库**: 直接看数据判断问题在哪
5. **分步骤解决**: 一次只处理一个问题

### 核心经验

1. **触发器用 COUNT 不用增减**: 避免计数不同步
2. **消息加载要倒序再反转**: 获取最新N条，显示时旧的在上
3. **Realtime 更新要在 MainActor**: 否则 UI 不刷新
4. **列表排序要固定**: 用 channel_code 保证所有设备一致

---

## 🎯 扩展任务（可选）

完成基础功能后，可以继续实现：

### TTS 语音播报

- 新消息自动语音播报
- 支持开关控制

### 消息分类标签

- 不同类型消息显示不同颜色标签
- 生存（绿）、新闻（蓝）、任务（橙）、警报（红）

### 频道详情页

- 点击频道查看详细信息
- 显示更多统计数据

---

**恭喜完成 Day 6！** 🎉

你已经掌握了官方频道系统的开发，包括：

- 数据库表设计和触发器
- pg_cron 定时任务
- Realtime 频道消息订阅
- SwiftUI 频道列表界面
