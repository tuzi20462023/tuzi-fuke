# 📚 Day 5 通讯系统开发教程 - Supabase Realtime 实时聊天

**目标**: 实现玩家间实时聊天通讯功能
**时间**: 3-4小时
**开发模式**: AI辅助开发 - 通过AI提示词生成代码
**结果**: 两台手机可以实时收发消息的聊天系统

---

## 🤖 AI开发特点

本教程采用AI辅助开发模式：

- ✅ **提示词驱动**: 每个任务都提供完整的AI提示词
- ✅ **代码直接可用**: AI生成的代码无需修改即可使用
- ✅ **错误解决方案**: 包含常见错误的AI解决提示词
- ✅ **快速迭代**: 通过优化提示词快速解决问题

---

## 🎯 学习目标

完成本教程后，你将掌握：

- [ ] Supabase 数据库表设计
- [ ] Supabase Realtime 实时订阅
- [ ] Swift 6 并发编程（Actor、@MainActor）
- [ ] SwiftUI 聊天界面开发
- [ ] 用户认证流程（登录/注册）
- [ ] REST API 调用
- [ ] Git Worktree 并行开发

---

## 📋 前置准备

### 开发环境要求

- [x] Xcode 15.0+
- [x] iOS 15.0+ 设备或模拟器
- [x] Supabase 项目已创建
- [x] Git 仓库已初始化

### 项目初始状态

- [x] 基础 SwiftUI 项目结构
- [x] Supabase SDK 已集成
- [x] SupabaseManager 已配置
- [x] AuthManager 基础框架

---

## 🚀 任务1: 创建开发分支 (10分钟)

### 目标

使用 Git Worktree 创建独立的开发目录，不影响主项目。

### 🤖 AI提示词 (终端执行)

```bash
# 在项目根目录执行
cd /path/to/tuzi-fuke

# 创建并切换到通讯功能分支
git checkout -b feature/communication

# 推送分支到远程
git push -u origin feature/communication

# 创建 worktree（可选，用于并行开发）
git worktree add ../tuzi-fuke-communication feature/communication
```

### ✅ 验证

```bash
git branch  # 应显示 * feature/communication
```

---

## 🚀 任务2: 创建数据库表 (15分钟)

### 目标

在 Supabase 中创建消息和频道表。

### 🤖 AI提示词 (Supabase SQL Editor)

```sql
-- ========================================
-- 通讯系统数据库表
-- ========================================

-- 1. 频道表
CREATE TABLE IF NOT EXISTS channels (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    channel_type TEXT DEFAULT 'public',
    created_by UUID REFERENCES auth.users(id),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 消息表
CREATE TABLE IF NOT EXISTS messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    sender_id UUID NOT NULL REFERENCES auth.users(id),
    channel_id UUID REFERENCES channels(id),
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'broadcast',
    sender_name TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. 启用 RLS
ALTER TABLE channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- 4. RLS 策略
CREATE POLICY "Anyone can read channels" ON channels
    FOR SELECT USING (true);

CREATE POLICY "Authenticated can create channels" ON channels
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Authenticated can read messages" ON messages
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated can send messages" ON messages
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = sender_id);

-- 5. 启用 Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE channels;

-- 6. 创建索引
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_channel_id ON messages(channel_id);
```

### ✅ 验证

在 Supabase Dashboard → Table Editor 中确认表已创建。

---

## 🚀 任务3: 创建消息数据模型 (20分钟)

### 目标

创建 Swift 消息数据结构。

### 🤖 AI提示词 (直接使用)

```
请帮我创建 Message.swift 文件，要求：

1. 创建 MessageType 枚举：broadcast, channel, direct, system
2. 创建 Message 结构体，包含：
   - id: UUID
   - senderId: UUID (映射 sender_id)
   - channelId: UUID? (映射 channel_id)
   - content: String
   - messageType: MessageType (映射 message_type)
   - senderName: String? (映射 sender_name)
   - metadata: [String: String]?
   - createdAt: Date (映射 created_at)

3. 实现 Codable、Identifiable、Sendable 协议
4. 添加 CodingKeys 映射 snake_case
5. 添加计算属性：
   - displaySenderName: 返回 senderName 或 "匿名幸存者"
   - isSystemMessage: 判断是否系统消息
   - formattedTime: 格式化时间显示

参考项目中其他模型文件的风格。
```

### 📝 预期代码结构

```swift
// Message.swift
import Foundation

enum MessageType: String, Codable, Sendable {
    case broadcast = "broadcast"
    case channel = "channel"
    case direct = "direct"
    case system = "system"
}

struct Message: Identifiable, Codable, Sendable {
    let id: UUID
    let senderId: UUID
    let channelId: UUID?
    let content: String
    let messageType: MessageType
    let senderName: String?
    let metadata: [String: String]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, content, metadata
        case senderId = "sender_id"
        case channelId = "channel_id"
        case messageType = "message_type"
        case senderName = "sender_name"
        case createdAt = "created_at"
    }

    var displaySenderName: String {
        if messageType == .system { return "系统" }
        return senderName ?? "匿名幸存者"
    }
}
```

---

## 🚀 任务4: 创建聊天管理器 (45分钟)

### 目标

创建 ChatManager 处理消息发送和实时接收。

### 🤖 AI提示词 (直接使用)

```
请帮我创建 ChatManager.swift，要求：

1. 使用单例模式 + @MainActor
2. Published 属性：
   - messages: [Message] - 消息列表
   - isLoading: Bool - 加载状态
   - errorMessage: String? - 错误信息
   - isConnected: Bool - Realtime连接状态

3. 公开方法：
   - start() async - 启动聊天系统
   - stop() async - 停止聊天系统
   - sendMessage(content: String) async throws - 发送消息
   - refresh() async - 刷新消息

4. 关键实现细节：
   - 使用 REST API 发送消息（避免 Swift 6 并发问题）
   - 使用 Supabase Realtime 订阅新消息
   - 日期解析要兼容多种格式
   - 发送消息时从用户邮箱提取 sender_name

5. 创建独立的 MessageUploader actor 处理网络请求

参考项目中 TerritoryManager 的代码风格。
注意 Swift 6 严格并发检查，所有跨 actor 调用要正确处理。
```

### 🚨 常见错误及解决方案

#### 错误1: Actor 隔离错误

**现象**:

```
Call to main actor-isolated instance method in a synchronous nonisolated context
```

**解决提示词**:

```
这个方法报 actor 隔离错误，请：
1. 如果是纯函数（不访问 self 属性），标记为 nonisolated
2. 如果需要访问 MainActor 状态，确保调用者也在 MainActor
3. 考虑使用独立的 actor 封装
```

#### 错误2: Sendable 警告

**现象**:

```
Capture of non-sendable type in @Sendable closure
```

**解决提示词**:

```
请检查闭包中捕获的变量，确保：
1. 所有捕获的类型都实现 Sendable
2. 使用 [weak self] 避免强引用
3. 必要时创建局部副本
```

---

## 🚀 任务5: 创建聊天界面 (30分钟)

### 目标

创建 ChatView 聊天界面。

### 🤖 AI提示词 (直接使用)

```
请帮我创建 ChatView.swift 聊天界面，要求：

1. 使用 @StateObject 观察 ChatManager.shared
2. 界面结构：
   - 顶部：连接状态指示器
   - 中间：消息列表（ScrollView + LazyVStack）
   - 底部：输入框 + 发送按钮

3. 消息气泡样式：
   - 自己的消息：右对齐，蓝色背景
   - 他人的消息：左对齐，灰色背景
   - 显示发送者名称和时间

4. 功能：
   - 自动滚动到最新消息
   - 发送中显示加载状态
   - 错误时显示提示
   - 下拉刷新

5. 生命周期：
   - onAppear 调用 chatManager.start()
   - onDisappear 调用 chatManager.stop()

参考项目中其他 View 的代码风格。
```

### 📝 界面预览

```
┌─────────────────────────────┐
│  📡 已连接                   │
├─────────────────────────────┤
│                             │
│  [对方] 你好！               │
│         10:30              │
│                             │
│              你好，在吗？ [我]│
│                      10:31 │
│                             │
├─────────────────────────────┤
│ [输入消息...]      [发送]    │
└─────────────────────────────┘
```

---

## 🚀 任务6: 创建登录界面 (30分钟)

### 目标

创建 AuthView 登录/注册界面。

### 🤖 AI提示词 (直接使用)

```
请帮我创建 AuthView.swift 登录/注册界面，要求：

1. 接收 @ObservedObject var authManager: AuthManager
2. State 属性：
   - isSignUp: Bool - 切换登录/注册
   - email: String
   - password: String
   - isLoading: Bool
   - errorMessage: String?

3. 界面设计：
   - 渐变背景
   - App Logo 和名称
   - 登录/注册 Picker 切换
   - 邮箱输入框（键盘类型 .emailAddress）
   - 密码输入框（SecureField）
   - 提交按钮（带加载状态）
   - 错误提示 Alert

4. 输入验证：
   - 邮箱必须包含 @ 和 .
   - 密码至少6位

5. 注意：不要包装 NavigationView（父视图已有）

游戏名称：地球新主
副标题：末世生存策略游戏
```

---

## 🚀 任务7: 集成到主界面 (15分钟)

### 目标

将聊天功能集成到 ContentView TabView。

### 🤖 AI提示词 (直接使用)

```
请修改 ContentView.swift，要求：

1. 在 body 中判断 authManager.isAuthenticated：
   - 已登录：显示 mainTabView
   - 未登录：显示 AuthView

2. mainTabView 添加聊天 Tab：
   - Tab 1: 地图
   - Tab 2: 聊天 (ChatView)
   - Tab 3: 调试
   - Tab 4: 日志

3. 地图 Tab 的 toolbar 添加用户菜单：
   - 显示当前用户邮箱
   - 退出登录按钮
```

---

## 🚀 任务8: 修复认证管理器 (15分钟)

### 目标

修改 AuthManager 正确处理会话状态。

### 🤖 AI提示词 (直接使用)

```
请修改 AuthManager.swift 的 checkCurrentSession() 方法：

问题：设备上缓存了旧会话，导致自动登录错误账户

修复要求：
1. 检查 session.user.email 是否为空
2. 如果邮箱为空，视为匿名用户，不自动登录
3. 只有真实邮箱用户才自动恢复会话

伪代码：
```swift
let hasEmail = supabaseUser.email != nil && !supabaseUser.email!.isEmpty
if !hasEmail {
    // 匿名用户，需要重新登录
    self.authState = .idle
    return
}
// 真实用户，恢复会话
```

```
---

## 🚀 任务9: 测试双机通讯 (20分钟)

### 目标

在两台设备上验证实时通讯。

### 操作步骤

1. **准备两台设备**
   - 设备A：你的 iPhone
   - 设备B：朋友的 iPhone 或模拟器

2. **注册不同账户**
   - 设备A：注册 `user1@example.com`
   - 设备B：注册 `user2@example.com`

3. **关闭邮箱验证**（如遇到 429 错误）
   - Supabase Dashboard → Authentication → Providers → Email
   - 关闭 "Confirm email"

4. **测试发送**
   - 设备A 发送消息
   - 确认设备B 实时收到

5. **验证日志**
```

   📡 [ChatManager] 发送消息: xxx... 发送者: user1
   ✅ [ChatManager] 消息发送成功
   📨 [ChatManager] 收到新消息: xxx...

```
### ✅ 成功标准

- [ ] 两台设备使用不同账户登录
- [ ] 消息可以双向发送
- [ ] Realtime 实时接收（无需刷新）
- [ ] 发送者名称正确显示

---

## 🚨 常见问题汇总

### Q1: 两台手机登录了同一账户

**原因**: Supabase 会话缓存

**解决**:
1. 两台设备都退出登录
2. 分别注册不同的新账户
3. 确保 AuthManager 正确检查邮箱

### Q2: 注册时报 429 错误

**原因**: Supabase 邮件发送限制

**解决**:
1. Supabase Dashboard → Authentication → Email Templates
2. 关闭 "Confirm email" 选项

### Q3: 消息发送失败

**排查步骤**:
1. 检查网络连接
2. 检查 Supabase RLS 策略
3. 查看控制台日志
4. 确认 auth.uid() 与 sender_id 匹配

### Q4: Realtime 不工作

**排查步骤**:
1. 确认表已添加到 supabase_realtime publication
2. 检查 channel 订阅是否成功
3. 查看 isConnected 状态

---

## 📊 本日学习总结

### 技术栈

| 技术 | 用途 |
|------|------|
| Supabase Database | 消息存储 |
| Supabase Realtime | 实时订阅 |
| Supabase Auth | 用户认证 |
| Swift Actor | 并发安全 |
| SwiftUI | 聊天界面 |

### AI协作要点

1. **分步骤提示**: 每个任务一个提示词，不要一次性要求太多
2. **提供上下文**: 告诉AI参考项目中已有的代码风格
3. **明确约束**: 指定 Swift 版本、并发要求、协议实现
4. **迭代修复**: 遇到错误时，把错误信息给AI让它修复

### 开发经验

1. **Swift 6 并发严格**: 使用 Actor 和 REST API 绑定方案
2. **Realtime 简单易用**: `postgresChange` + `for await` 模式
3. **日期格式要兼容**: Supabase 返回多种格式
4. **开发时关闭邮箱验证**: 避免 rate limit

---

## 🎯 扩展任务（可选）

完成基础功能后，可以继续实现：

### L1 设备系统
- 定义通讯设备（小收音机、对讲机等）
- 设备影响通讯范围和质量

### L2 频道系统
- 官方频道列表
- 用户可订阅/取消订阅频道

### L4 距离过滤
- 根据玩家距离过滤消息
- 信号强度计算

### L5 私聊系统
- 点对点私聊
- 消息加密

---

## 📚 参考资料

- [Supabase Realtime 文档](https://supabase.com/docs/guides/realtime)
- [Swift Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- [SwiftUI 官方教程](https://developer.apple.com/tutorials/swiftui)

---

**恭喜完成 Day 5！** 🎉

你已经掌握了实时通讯系统的开发，这是多人游戏的核心功能之一。
```
