# Day 10: AI 打卡明信片功能教学指南

**日期**: 2025年12月6日
**功能**: AI 打卡明信片 - 基于建筑位置生成卡通风格明信片
**难度**: 中高（涉及 Edge Function、AI 生图、本地缓存）

---

## 学习目标

完成本教程后，学员将掌握：

1. Supabase Edge Function 开发与部署
2. Gemini AI 图像生成 API 调用
3. 提示词工程（Prompt Engineering）
4. SwiftData 本地缓存实现
5. 本地优先 + 异步同步架构

---

## 功能架构

```
用户点击建筑生成明信片
        ↓
iOS App (GeminiService)
        ↓ HTTP POST (坐标 + 头像)
Supabase Edge Function
        ↓ 调用 Gemini API
生成卡通风格图片
        ↓ 上传到 Storage
返回图片 URL
        ↓
保存到本地 SwiftData → UI 立即更新
        ↓
后台异步同步到 Supabase
```

---

## 教学重点与常见坑点

### 坑点 1: Edge Function 环境变量读取失败

**现象**: `Deno.env.get('GEMINI_API_KEY')` 返回空字符串

**排查步骤**:

1. 确认 Supabase Dashboard 中设置了环境变量
2. 在代码中打印确认：`console.log('API Key 存在:', !!GEMINI_API_KEY)`
3. 如果还是失败，临时硬编码测试

**教学提示**: 这是 Supabase 的已知问题，先让学员能跑通，再排查根因。

### 坑点 2: 数据库 CHECK 约束

**现象**: 插入数据时报错 `violates check constraint`

**原因**: 新增的 'postcard' 模式不在原有约束中

**解决方案**:

```sql
ALTER TABLE checkin_photos DROP CONSTRAINT checkin_photos_mode_check;
ALTER TABLE checkin_photos ADD CONSTRAINT checkin_photos_mode_check
CHECK (mode IN ('selfie', 'cartoon', 'landscape', 'postcard'));
```

**教学提示**: 让学员理解数据库约束的作用和修改方法。

### 坑点 3: AI 生成写实照片而非卡通

**现象**: 提示词要求卡通风格，但生成的还是真实照片

**原因**:
- 传入真人头像时，AI 倾向保持"真实感"
- 风格要求不够强烈

**解决方案**: 大幅强调卡通风格（见提示词部分）

**教学提示**: 这是 AI 生图的核心难点，让学员理解"提示词工程"的重要性。

### 坑点 4: SwiftData Predicate 枚举问题

**现象**: `Cannot convert value of type 'SyncStatus' to expected argument type 'String'`

**原因**: `#Predicate` 宏不支持直接使用枚举 case

**解决方案**:

```swift
// 错误
#Predicate { photo in photo.syncStatus == SyncStatus.pending.rawValue }

// 正确
let pendingStatus = "pending"
#Predicate { photo in photo.syncStatus == pendingStatus }
```

---

## AI 提示词模板

### 提示词 1: 创建 Edge Function

```
我需要创建一个 Supabase Edge Function 来生成 AI 明信片：

功能：
1. 接收经纬度坐标和可选的用户头像（base64）
2. 调用 Gemini API 生成卡通风格明信片
3. 上传生成的图片到 Supabase Storage
4. 返回图片 URL

请使用 Gemini 官方 SDK @google/genai，参考这个示例：
[粘贴官方示例代码]
```

---

### 提示词 2: 实现本地缓存

```
我需要用 SwiftData 实现打卡记录的本地缓存：

需求：
1. 创建 CachedCheckinPhoto 模型，与云端 CheckinPhoto 对应
2. 支持同步状态：pending、synced、failed、pendingDelete
3. 实现 CRUD 操作
4. 从云端模型转换 / 转换为云端模型

请参考现有的数据模型风格。
```

---

### 提示词 3: 调试图片风格问题

```
[截图: 生成的写实风格图片]

我要求生成卡通/动漫风格，但 AI 生成的是写实照片。

当前提示词：
[粘贴当前提示词]

请帮我优化提示词，让 AI 一定生成卡通风格。关键要求：
1. 背景是卡通插画风格
2. 人物也要画成卡通角色
3. 像吉卜力/新海诚的动画风格
```

---

### 提示词 4: 地点名称不准确

```
[截图: 显示错误地名的明信片]

建筑坐标：23.2006, 114.4504
期望地点：白鹭湖
实际显示：梅岭街

Apple 地图确认坐标是对的，应该是 Google Search 的问题。

我想调整策略：
1. 搜索还是精准搜具体位置
2. 但明信片文字只显示城市名（惠州）
3. 画面基于真实环境，但用卡通风格美化

请帮我修改提示词。
```

---

### 提示词 5: 部署 Edge Function

```
帮我部署 Edge Function 到 Supabase：

项目 ID：shwstoxeowtpxcwcbozc
函数目录：supabase/functions/generate-checkin-image/

如果遇到错误请帮我排查。
```

---

## Edge Function 核心代码

### 完整提示词（buildPrompt 函数）

```typescript
function buildPrompt(latitude: number, longitude: number, hasAvatar: boolean): string {
  const baseStyle = `
⚠️⚠️⚠️ CRITICAL: THIS MUST BE A CARTOON/ANIME ILLUSTRATION - ABSOLUTELY NO REALISTIC PHOTOS! ⚠️⚠️⚠️

🎨 ART STYLE (STRICTLY FOLLOW):
- 2D hand-drawn anime/cartoon illustration style
- Like Studio Ghibli (宫崎骏), Makoto Shinkai (新海诚), or Disney/Pixar concept art
- Cell-shaded coloring with flat colors and clean outlines
- Stylized, NOT photorealistic
- Looks like digital painting or watercolor illustration
- Similar to: "Your Name" anime, "Spirited Away", children's book illustrations

STEP 1 - LOCATION RESEARCH:
Use Google Search to find what is at coordinates ${latitude}, ${longitude}.
- Find the actual place: streets, buildings, lakes, parks, shops
- Note the real environment, then REDRAW it in cute cartoon style

STEP 2 - CARTOON RENDERING (MANDATORY):
Transform the real location into anime/cartoon art:
- Simplify complex details into clean cartoon shapes
- Use bright, saturated anime color palette
- Add dreamy atmosphere: soft glow, light rays, sparkles
- Make buildings look cute and charming (rounded edges, warm colors)
- Beautiful illustrated sky with fluffy stylized clouds
- Add whimsical details: birds, butterflies, cherry blossoms, floating particles

STEP 3 - POSTCARD TEXT:
- Add "Greetings from 惠州" in cute decorative cartoon font
- Use ONLY city name, not street names
- Cute banner or ribbon style`;

  if (hasAvatar) {
    return `⚠️ GENERATE A 2D ANIME/CARTOON ILLUSTRATION - NOT A PHOTO! ⚠️

Create a cute anime-style postcard illustration at coordinates: ${latitude}, ${longitude}

${baseStyle}

🧑‍🎨 CONVERT PERSON TO CARTOON CHARACTER (VERY IMPORTANT):
- Transform the reference photo person into a 2D ANIME CHARACTER
- Use the SAME cartoon art style as the background
- Anime features: large expressive eyes, simplified nose, small mouth
- Keep their hair color, hairstyle, clothing but in cartoon/anime form
- Cute happy expression, kawaii style
- The person must look DRAWN/ILLUSTRATED, not like a real photo
- Think: how would Studio Ghibli draw this person?

🎯 FINAL OUTPUT: A cohesive 2D anime-style illustrated postcard where BOTH the background AND the person are in matching cartoon style. NO photorealistic elements.`;
  } else {
    return `⚠️ GENERATE A 2D ANIME/CARTOON ILLUSTRATION - NOT A PHOTO! ⚠️

Create a cute anime-style postcard illustration at coordinates: ${latitude}, ${longitude}

${baseStyle}

COMPOSITION:
- Beautiful 2D illustrated landscape
- Anime/cartoon art style throughout
- Like a background painting from a Ghibli film

🎯 FINAL OUTPUT: A beautiful 2D anime-style illustrated postcard. NO photorealistic elements.`;
  }
}
```

### 追加提示词（第二层强调）

```typescript
if (avatarBase64) {
  const fullPrompt = prompt + '\n\n🚨🚨🚨 ABSOLUTE REQUIREMENT 🚨🚨🚨\n' +
    'The output image MUST be a 2D CARTOON/ANIME STYLE ILLUSTRATION.\n' +
    'DO NOT generate a realistic photograph.\n' +
    'DO NOT keep the person looking like a real photo.\n' +
    'CONVERT the person into an ANIME CHARACTER with the same art style as the background.\n' +
    'The final image should look like it was HAND-DRAWN by an animator, not photographed by a camera.\n' +
    'Style reference: Studio Ghibli, Makoto Shinkai anime films, Disney concept art.';
  // ...
}
```

---

## 开发步骤

### 步骤 1: 创建 Edge Function

```bash
# 在项目目录下
mkdir -p supabase/functions/generate-checkin-image
touch supabase/functions/generate-checkin-image/index.ts
```

### 步骤 2: 实现 Edge Function

核心结构：

```typescript
import { GoogleGenAI } from "npm:@google/genai";

Deno.serve(async (req) => {
  // 1. 解析请求（经纬度、头像）
  const { latitude, longitude, avatarBase64, userId } = await req.json();

  // 2. 构建提示词
  const prompt = buildPrompt(latitude, longitude, !!avatarBase64);

  // 3. 调用 Gemini API
  const imageData = await generateImageWithGemini(prompt, avatarBase64);

  // 4. 上传到 Storage
  await supabase.storage.from('checkin-photos').upload(filePath, imageData);

  // 5. 返回 URL
  return new Response(JSON.stringify({ success: true, image_url: publicUrl }));
});
```

### 步骤 3: 部署 Edge Function

```bash
# 初始化（如果没有）
npx supabase init

# 链接项目
npx supabase link --project-ref YOUR_PROJECT_REF

# 部署
npx supabase functions deploy generate-checkin-image --no-verify-jwt
```

### 步骤 4: iOS 端调用

创建 `GeminiService.swift`：

```swift
actor GeminiService {
    func generateCheckinImage(location: CLLocation, avatarImage: UIImage?) async throws -> UIImage {
        var requestBody: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude
        ]

        if let avatar = avatarImage,
           let imageData = avatar.jpegData(compressionQuality: 0.8) {
            requestBody["avatarBase64"] = imageData.base64EncodedString()
        }

        // 调用 Edge Function...
    }
}
```

### 步骤 5: 实现本地缓存

创建 `CheckinDataStore.swift`：

```swift
@Model
final class CachedCheckinPhoto {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var syncStatus: String  // pending, synced, failed, pendingDelete
    // ...其他字段
}

@MainActor
class CheckinDataStore: ObservableObject {
    func saveCheckinPhoto(...) throws -> CachedCheckinPhoto
    func fetchCheckinPhotos(for userId: UUID) throws -> [CachedCheckinPhoto]
    func markAsSynced(_ photo: CachedCheckinPhoto) throws
    // ...
}
```

### 步骤 6: 集成到 CheckinManager

```swift
func generatePostcard(building: PlayerBuilding) async -> CheckinResult {
    // 1. 生成图片
    let image = try await geminiService.generateCheckinImage(...)

    // 2. 上传图片
    let imageURL = try await uploadCheckinImage(...)

    // 3. 保存到本地
    let cached = try dataStore.saveCheckinPhoto(...)

    // 4. 更新 UI
    checkinPhotos.insert(cached.toCheckinPhoto()!, at: 0)

    // 5. 后台同步
    Task { await syncToCloud(cachedPhoto: cached) }

    return CheckinResult(success: true, ...)
}
```

---

## 教学检查点

### 检查点 1: Edge Function 部署

```
✅ 部署成功，控制台显示 Deployed Functions
✅ 在 Supabase Dashboard 能看到函数
```

### 检查点 2: API 调用成功

```
✅ 控制台显示：🎨 [Gemini API] 图片生成成功
✅ 图片成功上传到 Storage
```

### 检查点 3: 图片风格正确

```
✅ 生成的图片是卡通/动漫风格
✅ 人物也是卡通形象（如果有头像）
✅ 文字显示城市名而非街道名
```

### 检查点 4: 本地缓存工作

```
✅ 生成后立即显示在列表中
✅ 状态为 pending
✅ 同步成功后状态变为 synced
```

### 检查点 5: 后台同步

```
✅ 数据同步到 Supabase checkin_photos 表
✅ 网络断开时本地数据保留
✅ 网络恢复后自动同步
```

---

## 常见问题 FAQ

### Q1: Edge Function 返回 403?

**A**: 检查 Gemini API Key：
1. 确认 Key 有效
2. 检查环境变量是否设置
3. 临时硬编码测试

### Q2: 生成的图片还是写实风格?

**A**: 加强提示词中的卡通要求：
- 使用警告符号 ⚠️🚨
- 多次重复 "NOT a photo"
- 给具体参考（吉卜力、新海诚）

### Q3: 地点名称不准确?

**A**: 这是 Google Search 在中国的问题：
- 调整提示词只显示城市名
- 或使用国内地图 API 先获取地名

### Q4: SwiftData 编译错误?

**A**: 常见问题：
- Predicate 中枚举用局部变量替代
- Actor 隔离问题用计算属性解决

### Q5: 图片生成很慢?

**A**: 正常，AI 生图需要 10-30 秒：
- Edge Function timeout 设置 120 秒
- iOS 端 URLSession timeout 也要设置
- 添加加载动画提示用户

---

## 扩展学习

### 进阶功能

1. **多种风格选择**: 水彩、油画、像素风等
2. **自定义文字**: 用户输入祝福语
3. **滤镜效果**: 复古、黑白、暖色调
4. **分享功能**: 生成带水印的分享图

### 相关知识点

- Supabase Edge Functions (Deno)
- Google Gemini AI API
- Prompt Engineering
- SwiftData 持久化
- Actor 并发模型

---

## 参考文件

| 文件 | 用途 |
|------|------|
| supabase/functions/generate-checkin-image/index.ts | Edge Function |
| tuzi-fuke/GeminiService.swift | iOS 端 API 调用 |
| tuzi-fuke/CheckinManager.swift | 打卡管理器 |
| tuzi-fuke/CheckinDataStore.swift | 本地缓存 |
| tuzi-fuke/CheckinModels.swift | 数据模型 |

---

## 教学总结

AI 打卡明信片功能的核心难点是**提示词工程**：

1. **理解 AI 的"倾向性"**: 传入真人照片时 AI 倾向保持真实感
2. **强调风格要求**: 用符号、重复、具体参考来强调
3. **两层提示词**: 主提示词 + 追加强调，双保险
4. **迭代优化**: 根据生成结果不断调整提示词

建议教学时：

1. 先让学员跑通基础流程
2. 再逐步优化提示词
3. 让学员观察不同提示词的效果差异
4. 培养"提示词工程"的思维
