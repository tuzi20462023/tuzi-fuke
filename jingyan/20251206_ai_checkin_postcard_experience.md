# AI 打卡明信片功能开发经验总结

**日期**: 2025年12月5-6日
**项目**: tuzi-fuke (地球新主复刻版)
**功能**: AI 打卡明信片 - 基于建筑位置生成卡通风格明信片

---

## 背景

在完成建筑系统后，实现 AI 打卡明信片功能：

- 用户在建筑位置点击生成明信片
- 使用 Gemini AI 根据 GPS 坐标搜索地点并生成图片
- 结合用户头像生成卡通风格明信片
- 本地缓存 + 云端同步

---

## 与 AI 对话的经验

### 1. 明确简化需求，避免过度设计

**错误示范**:

```
实现一个AI打卡功能，有三种模式：自拍模式、卡通模式、风景模式...
```

**正确示范**:

```
我想简化AI打卡功能，只保留一种"明信片"模式：
- 用户点击建筑生成明信片
- 根据建筑GPS坐标搜索地点
- 可选结合用户头像
- 生成卡通风格明信片

你觉得这个简化方案怎么样？先不要写代码。
```

**效果**: AI 先理解需求再动手，避免做无用功。

### 2. 提供官方文档和示例代码

**有效的提示词模式**:

```
我看到 Gemini 官方文档的示例代码是这样的：

const ai = new GoogleGenAI({ apiKey: "GEMINI_API_KEY" });
const response = await ai.models.generateContent({
  model: "gemini-2.0-flash-exp",
  contents: "...",
  config: {
    responseModalities: ["TEXT", "IMAGE"],
  },
});

请按照这个官方写法来实现，不要用其他方式。
```

**效果**: 避免 AI 用过时或错误的 API 调用方式。

### 3. 截图 + 错误信息一起提供

**有效的提示词模式**:

```
[截图: 生成的图片显示"梅岭街"]

这个生成地点对了吗？我在白鹭湖，但显示的是梅岭街。

建筑坐标是 23.2006, 114.4504
```

**效果**: 让 AI 能够分析是坐标问题还是搜索问题。

### 4. 分步确认，先理解再写代码

**有效的提示词模式**:

```
你明白我的意思了吗？先不要写代码。
```

或者：

```
是这样的流程吗？
1. xxx
2. xxx
3. xxx

你先理解下我的意思。
```

**效果**: 防止 AI 误解需求后写一堆无用代码。

### 5. 让 AI 列出关键代码确认

**有效的提示词模式**:

```
两个提示词都是啥？列出来给我看看。
```

**效果**: 发现提示词写的是固定值而不是变量，避免低级错误。

### 6. 明确风格要求的表达方式

**错误示范**:

```
生成的图不好看，优化一下
```

**正确示范**:

```
现在生成的是写实照片风格，我想要卡通/动漫风格：
- 像吉卜力工作室的画风
- 把人物也画成卡通角色
- 背景即使是普通建筑也要画得可爱

你觉得提示词应该怎么改？先不要写代码。
```

**效果**: AI 能理解具体要什么风格，而不是随便改。

---

## 遇到的核心 Bug 及解决方案

### Bug 1: Edge Function 读不到环境变量

**问题现象**:

```
❌ [Gemini API] 403 PERMISSION_DENIED
GEMINI_API_KEY存在: false
```

**问题分析**:

Supabase Edge Function 的环境变量设置了但读取失败，`Deno.env.get('GEMINI_API_KEY')` 返回空字符串。

**临时解决方案**:

在代码中硬编码 API Key（仅用于调试）：

```typescript
const GEMINI_API_KEY = 'AIzaSy...实际的key';
```

**注意**: 生产环境应该排查环境变量问题，不要硬编码。

---

### Bug 2: 数据库约束不允许 'postcard' 模式

**问题现象**:

```
PostgresError: new row for relation "checkin_photos" violates
check constraint "checkin_photos_mode_check"
```

**问题分析**:

数据库 `checkin_photos` 表的 `mode` 字段有 CHECK 约束，只允许原来的三种模式（selfie/cartoon/landscape），不包含新的 'postcard'。

**解决方案**:

执行 SQL 修改约束：

```sql
ALTER TABLE checkin_photos
DROP CONSTRAINT checkin_photos_mode_check;

ALTER TABLE checkin_photos
ADD CONSTRAINT checkin_photos_mode_check
CHECK (mode IN ('selfie', 'cartoon', 'landscape', 'postcard'));
```

---

### Bug 3: Google Search 返回不准确的地点名

**问题现象**:

- 建筑坐标在"白鹭湖"
- 但生成的明信片显示"梅岭街"
- Apple 地图确认坐标是正确的

**问题分析**:

Gemini 使用 Google Search 搜索中国大陆的地理位置时，返回的地名不如国内地图服务（高德、百度）准确。

**解决方案**:

调整提示词策略：

1. 降低地址精度要求 - 只显示城市名（如"惠州"），不显示街道
2. 搜索还是精准搜 - 让 AI 搜索具体位置的环境信息
3. 用卡通风格美化 - 即使是普通居民楼也画得好看

```
STEP 3 - POSTCARD TEXT:
- Add "Greetings from 惠州" in cute decorative cartoon font
- Use ONLY city name, not street names
```

---

### Bug 4: 生成的图片是写实照片而不是卡通风格

**问题现象**:

提示词明确要求卡通风格，但 Gemini 生成的还是写实照片。

**问题分析**:

1. 当传入真人头像时，Gemini 倾向于保持"真实感"
2. 第二层追加的提示词可能干扰了主提示词
3. 卡通风格的强调不够明确

**解决方案**:

大幅加强卡通风格要求：

```typescript
const baseStyle = `
⚠️⚠️⚠️ CRITICAL: THIS MUST BE A CARTOON/ANIME ILLUSTRATION - ABSOLUTELY NO REALISTIC PHOTOS! ⚠️⚠️⚠️

🎨 ART STYLE (STRICTLY FOLLOW):
- 2D hand-drawn anime/cartoon illustration style
- Like Studio Ghibli (宫崎骏), Makoto Shinkai (新海诚), or Disney/Pixar concept art
- Cell-shaded coloring with flat colors and clean outlines
- Stylized, NOT photorealistic
...

🧑‍🎨 CONVERT PERSON TO CARTOON CHARACTER (VERY IMPORTANT):
- Transform the reference photo person into a 2D ANIME CHARACTER
- Anime features: large expressive eyes, simplified nose, small mouth
- The person must look DRAWN/ILLUSTRATED, not like a real photo
- Think: how would Studio Ghibli draw this person?
`;
```

关键技巧：
- 用警告符号 ⚠️🚨 强调
- 多次重复"NOT a photo"
- 给具体参考（吉卜力、新海诚、迪士尼）
- 描述具体特征（大眼睛、简化五官）

---

### Bug 5: SwiftData Predicate 不能直接使用枚举

**问题现象**:

```
Cannot convert value of type 'SyncStatus' to expected argument type 'String'
```

**问题分析**:

SwiftData 的 `#Predicate` 宏不支持直接使用枚举 case：

```swift
// 错误写法
#Predicate { photo in
    photo.syncStatus == SyncStatus.pending.rawValue  // 编译错误
}
```

**解决方案**:

用局部变量替代：

```swift
let pendingStatus = "pending"
let descriptor = FetchDescriptor<CachedCheckinPhoto>(
    predicate: #Predicate { photo in
        photo.syncStatus == pendingStatus  // 正确
    }
)
```

---

### Bug 6: Actor 隔离导致的编译错误

**问题现象**:

```
Actor-isolated property 'edgeFunctionURL' can not be referenced from a non-isolated context
```

**问题分析**:

`GeminiService` 是 `actor` 类型，静态属性 `let` 在初始化时会触发 actor 隔离检查。

**解决方案**:

将 `let` 改为计算属性 `var`：

```swift
// 错误
private let edgeFunctionURL: URL = SupabaseConfig.supabaseURL.appendingPathComponent("...")

// 正确
private var edgeFunctionURL: URL {
    SupabaseConfig.supabaseURL.appendingPathComponent("functions/v1/generate-checkin-image")
}
```

---

### Bug 7: Supabase CLI 部署失败

**问题现象**:

```
Cannot find project ref. Have you run supabase link?
```

**问题分析**:

项目目录没有初始化 Supabase 配置。

**解决方案**:

```bash
# 1. 初始化配置
npx supabase init

# 2. 链接项目
npx supabase link --project-ref shwstoxeowtpxcwcbozc

# 3. 部署
npx supabase functions deploy generate-checkin-image --no-verify-jwt
```

---

## 架构设计经验

### 本地优先 + 异步同步

**设计思路**:

1. 用户操作立即响应（保存到本地 SwiftData）
2. 后台异步同步到云端
3. 失败时自动重试

**数据流**:

```
用户生成明信片
    ↓
上传图片到 Storage
    ↓
保存到本地 SwiftData（状态: pending）→ UI 立即更新
    ↓
后台异步同步到 Supabase（成功后状态: synced）
```

**关键代码结构**:

```swift
// CheckinManager.swift
func generatePostcard(building: PlayerBuilding) async -> CheckinResult {
    // 1. 调用 Gemini 生成图片
    let generatedImage = try await geminiService.generateCheckinImage(...)

    // 2. 上传到 Storage
    let imageURL = try await uploadCheckinImage(...)

    // 3. 保存到本地（立即可用）
    let cachedPhoto = try dataStore.saveCheckinPhoto(...)

    // 4. 更新 UI
    checkinPhotos.insert(displayPhoto, at: 0)

    // 5. 后台异步同步到云端
    Task {
        await syncToCloud(cachedPhoto: cachedPhoto, userId: userId)
    }

    return CheckinResult(success: true, ...)
}
```

---

## 提示词工程经验

### 提示词结构

```
第一层 buildPrompt() - 主提示词
├── 强调输出格式（卡通/动漫）
├── STEP 1 - 位置搜索（使用坐标变量）
├── STEP 2 - 卡通渲染要求
├── STEP 3 - 文字要求
└── 人物处理要求（如有头像）

第二层 generateImageWithGemini() - 追加强调
└── 再次强调卡通风格，防止被忽略
```

### 变量插入

使用 JavaScript 模板字符串动态插入坐标：

```typescript
function buildPrompt(latitude: number, longitude: number, hasAvatar: boolean): string {
  const baseStyle = `
    STEP 1 - LOCATION RESEARCH:
    Use Google Search to find what is at coordinates ${latitude}, ${longitude}.
    ...
  `;
  // ...
}
```

### 风格强调技巧

1. 用符号标记重要性：⚠️🚨🎨🎯
2. 多次重复关键要求："NOT a photo" 出现多次
3. 给具体参考：吉卜力、新海诚、迪士尼
4. 正向+反向说明：要什么 + 不要什么
5. 问引导性问题："how would Studio Ghibli draw this person?"

---

## 文件修改清单

| 文件 | 修改内容 |
|------|----------|
| supabase/functions/generate-checkin-image/index.ts | Edge Function 完整实现 |
| tuzi-fuke/GeminiService.swift | iOS 端调用 Edge Function |
| tuzi-fuke/CheckinManager.swift | 打卡管理器，集成本地缓存 |
| tuzi-fuke/CheckinDataStore.swift | SwiftData 本地缓存 |
| tuzi-fuke/AvatarManager.swift | 用户头像管理 |
| tuzi-fuke/CheckinModels.swift | 打卡相关数据模型 |

---

## 核心经验总结

### 技术经验

1. **Edge Function 环境变量**: 如果读取失败，先硬编码调试，再排查配置问题
2. **数据库约束**: 新增枚举值时记得更新 CHECK 约束
3. **SwiftData Predicate**: 枚举值要用局部变量，不能直接用 case
4. **Actor 隔离**: 静态属性用计算属性 `var` 替代 `let`
5. **AI 生图风格**: 需要非常强烈地强调风格要求，多次重复

### 与 AI 协作经验

1. **先理解再写代码**: 用"先不要写代码"让 AI 确认理解
2. **提供官方示例**: 给 AI 看官方文档的代码示例
3. **截图+数值**: 让问题可视化、可量化
4. **让 AI 列出代码**: 确认变量是否正确传递
5. **分步确认**: 每完成一步确认一次，避免累积错误

### 提示词工程经验

1. **风格要强调**: 用符号、重复、具体参考
2. **变量要动态**: 用模板字符串插入坐标
3. **两层保险**: 主提示词 + 追加提示词双重强调
4. **给出对比**: 要什么 vs 不要什么

---

## 参考文件

- `/Users/mikeliu/Desktop/tuzi-fuke-building/supabase/functions/generate-checkin-image/index.ts`
- `/Users/mikeliu/Desktop/tuzi-fuke-building/tuzi-fuke/GeminiService.swift`
- `/Users/mikeliu/Desktop/tuzi-fuke-building/tuzi-fuke/CheckinManager.swift`
- `/Users/mikeliu/Desktop/tuzi-fuke-building/tuzi-fuke/CheckinDataStore.swift`
