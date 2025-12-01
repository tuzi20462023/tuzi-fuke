# 通讯系统开发经验总结

**日期**: 2025年12月1日
**项目**: tuzi-fuke (地球新主复刻版)
**功能**: 玩家间实时聊天通讯系统

---

## 背景

在GPS策略游戏《地球新主》中，玩家需要能够互相通讯。我们需要实现一个基于Supabase的实时聊天系统，让不同手机上的玩家可以发送和接收消息。

### 核心需求
1. 用户认证（邮箱登录/注册）
2. 消息发送
3. 实时接收（Realtime）
4. 聊天UI界面

---

## 技术选型

### 为什么选择 Supabase Realtime

| 方案 | 优点 | 缺点 |
|------|------|------|
| **Firebase** | 成熟、文档丰富 | 国内访问受限、与现有架构不统一 |
| **WebSocket自建** | 完全可控 | 开发成本高、需要服务器 |
| **Supabase Realtime** ✅ | 与现有数据库统一、免费额度足够、支持PostgreSQL | Swift SDK有并发限制 |

选择 Supabase Realtime 原因：
1. 项目已使用 Supabase 作为后端，保持技术栈统一
2. 开箱即用的 PostgreSQL Change Data Capture
3. 免费套餐足够 MVP 验证

---

## 实施步骤

### 1. 数据库设计

在 Supabase SQL Editor 执行：

```sql
-- 消息表
CREATE TABLE messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    sender_id UUID NOT NULL REFERENCES auth.users(id),
    channel_id UUID REFERENCES channels(id),
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'broadcast',
    sender_name TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 频道表（可选，用于分组）
CREATE TABLE channels (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    channel_type TEXT DEFAULT 'public',
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 启用 RLS
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE channels ENABLE ROW LEVEL SECURITY;

-- RLS 策略：所有认证用户可读写
CREATE POLICY "Authenticated users can read messages" ON messages
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can insert messages" ON messages
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = sender_id);

-- 启用 Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
```

### 2. 创建数据模型 (Message.swift)

```swift
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
        case id
        case senderId = "sender_id"
        case channelId = "channel_id"
        case content
        case messageType = "message_type"
        case senderName = "sender_name"
        case metadata
        case createdAt = "created_at"
    }

    var displaySenderName: String {
        return senderName ?? "匿名幸存者"
    }
}
```

### 3. 创建聊天管理器 (ChatManager.swift)

关键设计决策：
- 使用 `@MainActor` 确保 UI 更新在主线程
- 使用 REST API 发送消息（避免 Swift 6 并发问题）
- 使用 Supabase Realtime 接收消息

```swift
@MainActor
class ChatManager: ObservableObject {
    static let shared = ChatManager()

    @Published var messages: [Message] = []
    @Published var isConnected: Bool = false

    private var realtimeChannel: RealtimeChannelV2?

    // 启动聊天系统
    func start() async {
        await loadMessages()      // 加载历史消息
        await subscribeToRealtime() // 订阅实时消息
    }

    // 发送消息 - 使用 REST API
    func sendMessage(content: String) async throws {
        let senderName = AuthManager.shared.currentUser?.email?
            .components(separatedBy: "@").first ?? "匿名"

        try await messageUploader.upload(
            MessageUploadData(
                sender_id: userId.uuidString,
                content: content,
                message_type: MessageType.broadcast.rawValue,
                sender_name: senderName
            ),
            supabaseUrl: SupabaseConfig.supabaseURL.absoluteString,
            anonKey: SupabaseConfig.supabaseAnonKey,
            accessToken: try? await supabase.auth.session.accessToken
        )
    }

    // 订阅 Realtime
    private func subscribeToRealtime() async {
        realtimeChannel = await supabase.realtimeV2.channel("public:messages")

        let insertions = await channel.postgresChange(
            InsertAction.self,
            table: "messages"
        )

        messageInsertTask = Task { @MainActor [weak self] in
            for await insertion in insertions {
                await self?.handleMessageInsert(insertion)
            }
        }

        await channel.subscribe()
    }
}
```

### 4. 使用 Actor 解决 Swift 6 并发问题

Supabase SDK 的某些方法与 Swift 6 严格并发检查冲突，解决方案是使用独立的 Actor：

```swift
actor MessageUploader {
    func upload(_ data: MessageUploadData,
                supabaseUrl: String,
                anonKey: String,
                accessToken: String?) async throws {
        // 使用原生 URLSession 调用 REST API
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        // 处理响应...
    }
}

let messageUploader = MessageUploader()
```

### 5. 日期解析处理

Supabase 返回的日期格式多样，需要兼容处理：

```swift
nonisolated private static func parseDate(_ dateString: String) -> Date? {
    let formats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",  // 微秒精度
        "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",     // 毫秒精度
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ",         // 无毫秒
        "yyyy-MM-dd'T'HH:mm:ss"               // 最简格式
    ]

    for format in formats {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: dateString) {
            return date
        }
    }

    // ISO8601 fallback
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return iso.date(from: dateString)
}
```

注意：`parseDate` 方法需要标记为 `nonisolated`，因为它在 `@MainActor` 类中但不需要访问 actor 状态。

---

## 遇到的问题

### 问题1: 两台手机自动登录同一账户

**现象**: 两台手机都自动登录了 `test@tuzigame.com`，无法测试多用户通讯

**原因**: Supabase 会话被缓存，之前的测试账户 session 保存在设备上

**解决**: 修改 `AuthManager.checkCurrentSession()` 检查用户是否有真实邮箱
```swift
let hasEmail = supabaseUser.email != nil && !supabaseUser.email!.isEmpty
let isAnonymous = !hasEmail

if isAnonymous {
    self.authState = .idle  // 需要重新登录
    return
}
```

### 问题2: 注册时邮箱验证 429 错误

**现象**: `email rate limit exceeded`

**原因**: Supabase 免费套餐邮件发送有限制

**解决**: 在 Supabase Dashboard → Authentication → Email Templates → 关闭 "Confirm email"

### 问题3: 消息发送者显示"匿名幸存者"

**现象**: 所有消息的 sender_name 都是 null

**原因**: 发送消息时没有传入 sender_name 字段

**解决**: 从用户邮箱提取用户名
```swift
let senderName = AuthManager.shared.currentUser?.email?
    .components(separatedBy: "@").first ?? "匿名"
```

### 问题4: Swift 6 Actor 隔离错误

**现象**: `Call to main actor-isolated instance method in a synchronous nonisolated context`

**原因**: Supabase SDK 某些回调不在 MainActor 上执行

**解决**:
1. 使用 REST API 替代 SDK 方法
2. 创建独立的 Actor 处理网络请求
3. 使用 `nonisolated` 标记纯函数

### 问题5: 导航栏被隐藏

**现象**: 登录后看不到用户信息和退出按钮

**原因**: AuthView 中有 `.navigationBarHidden(true)` 和嵌套的 NavigationView

**解决**: 移除 AuthView 中的 NavigationView 包装和 hidden 修饰符

---

## 开发工作流

### 使用 Git Worktree 并行开发

```bash
# 创建通讯功能分支的 worktree
git worktree add ../tuzi-fuke-communication feature/communication

# 在独立目录开发，不影响主项目
cd ../tuzi-fuke-communication
# 开发...

# 完成后合并回 main
git checkout main
git merge feature/communication
git push
```

### 调试 Supabase 数据

```sql
-- 查看消息表数据
SELECT id, sender_id, content, sender_name, created_at
FROM messages
ORDER BY created_at DESC
LIMIT 10;

-- 查看用户
SELECT id, email, created_at FROM auth.users;
```

---

## 文件结构

```
tuzi-fuke/
├── Message.swift          # 消息数据模型
├── ChatManager.swift      # 聊天管理器（发送/接收/Realtime）
├── ChatView.swift         # 聊天界面UI
├── AuthManager.swift      # 认证管理（已有，修改）
├── AuthView.swift         # 登录/注册界面（新增）
└── ContentView.swift      # 主界面（添加聊天Tab）
```

---

## 总结

### 核心经验

1. **Swift 6 并发是大坑**: Supabase SDK 与严格并发检查不兼容，用 REST API + Actor 绑定方案
2. **Realtime 订阅很简单**: `channel.postgresChange()` + `for await` 即可
3. **日期解析要兼容**: Supabase 返回多种日期格式，需要多格式尝试
4. **Session 管理要谨慎**: 区分匿名用户和真实邮箱用户
5. **关闭邮箱验证**: 开发阶段关闭 Supabase 邮箱验证避免 rate limit

### 完成的功能

- ✅ 用户邮箱登录/注册
- ✅ 广播消息发送
- ✅ Realtime 实时接收
- ✅ 聊天列表UI
- ✅ 发送者名称显示
- ✅ 多用户通讯验证

### 待扩展功能

- 🔲 L1 设备系统（小收音机等）
- 🔲 L2 官方频道列表
- 🔲 L4 距离过滤/信号强度
- 🔲 L5 私聊消息
