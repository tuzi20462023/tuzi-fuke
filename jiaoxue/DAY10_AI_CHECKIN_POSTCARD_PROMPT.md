# Day 10: AI 打卡明信片 - 提示词速查手册

**功能**: AI 打卡明信片
**用途**: 学员遇到问题时快速查找对应提示词

---

## 一、Edge Function 开发

### 1.1 创建 Edge Function

```
我需要创建一个 Supabase Edge Function 来生成 AI 明信片。

功能需求：
1. 接收参数：latitude、longitude、avatarBase64（可选）、userId
2. 使用 Gemini API 生成卡通风格明信片
3. 上传图片到 Supabase Storage 的 checkin-photos bucket
4. 返回 JSON: { success: true, image_url: "..." }

技术要求：
- 使用 Deno
- 使用官方 SDK: npm:@google/genai
- 模型: gemini-2.0-flash-exp
- responseModalities: ['TEXT', 'IMAGE']

请创建完整的 index.ts 文件。
```

### 1.2 部署 Edge Function

```
帮我部署 Edge Function：

1. 先检查 supabase/functions/generate-checkin-image/index.ts 是否存在
2. 执行部署命令
3. 如果遇到错误帮我排查

项目 ID: [你的项目ID]
```

### 1.3 环境变量问题

```
Edge Function 读取不到环境变量，日志显示：
GEMINI_API_KEY存在: false

但我已经在 Supabase Dashboard 设置了。请帮我排查，或者提供临时解决方案。
```

---

## 二、提示词工程

### 2.1 基础卡通风格提示词

```
我需要一个生成卡通风格明信片的提示词，要求：

1. 根据经纬度坐标搜索位置
2. 生成卡通/动漫插画风格（不是照片）
3. 风格参考：吉卜力、新海诚、迪士尼
4. 文字只显示城市名，不显示街道
5. 如果有头像，把人也画成卡通角色

经纬度会作为变量传入：${latitude}, ${longitude}
```

### 2.2 强化卡通风格

```
[截图: 生成的写实风格图片]

AI 生成的还是写实照片，不是卡通。请帮我强化提示词：

1. 用警告符号强调 ⚠️🚨
2. 多次重复"不要照片"
3. 给具体的风格参考
4. 描述卡通的具体特征（大眼睛、简化五官等）
```

### 2.3 地点精度调整

```
问题：坐标在"白鹭湖"，但 AI 搜索到"梅岭街"

我想这样调整：
- 还是让 AI 搜索具体位置（获取环境信息）
- 但明信片文字只写城市名（惠州）
- 画面基于真实环境，用卡通风格美化

请修改提示词。
```

### 2.4 人物卡通化

```
问题：背景是卡通风格了，但人物还是真人照片

请在提示词中强调：
1. 人物必须画成卡通角色
2. 和背景同样的艺术风格
3. 动漫特征：大眼睛、简化五官
4. 保留发型、服装但用卡通形式
```

---

## 三、iOS 端开发

### 3.1 创建 GeminiService

```
创建一个 GeminiService.swift 来调用 Edge Function：

1. 使用 actor 保证线程安全
2. 方法：generateCheckinImage(location: CLLocation, avatarImage: UIImage?) async throws -> UIImage
3. 构建请求体：latitude、longitude、avatarBase64、userId
4. 调用 Edge Function URL
5. 解析响应获取 image_url，下载图片返回
```

### 3.2 创建本地缓存

```
用 SwiftData 创建打卡记录的本地缓存：

1. CachedCheckinPhoto 模型，包含：
   - id, userId, buildingId
   - 位置信息（locationName, latitude, longitude）
   - 图片URL（imageUrl, thumbnailUrl）
   - 同步状态（syncStatus: pending/synced/failed/pendingDelete）
   - 时间戳

2. CheckinDataStore 管理类，实现：
   - saveCheckinPhoto
   - fetchCheckinPhotos
   - markAsSynced
   - markForDeletion
   - syncFromCloud
```

### 3.3 集成到 CheckinManager

```
修改 CheckinManager，集成本地缓存：

流程：
1. 调用 GeminiService 生成图片
2. 上传图片到 Storage
3. 保存到本地 SwiftData（状态 pending）
4. 立即更新 UI
5. 后台 Task 异步同步到云端
6. 同步成功后标记为 synced

请帮我实现 generatePostcard 方法。
```

---

## 四、Bug 排查

### 4.1 数据库约束错误

```
错误信息：
PostgresError: new row for relation "checkin_photos" violates check constraint "checkin_photos_mode_check"

这是因为我新增了 'postcard' 模式。请帮我修改数据库约束。
```

### 4.2 SwiftData Predicate 错误

```
编译错误：
Cannot convert value of type 'SyncStatus' to expected argument type 'String'

代码：
#Predicate { photo in photo.syncStatus == SyncStatus.pending.rawValue }

请帮我修复。
```

### 4.3 Actor 隔离错误

```
编译错误：
Actor-isolated property 'xxx' can not be referenced from a non-isolated context

在 GeminiService actor 中的静态属性报错。请帮我修复。
```

### 4.4 图片生成超时

```
Edge Function 超时了，生成图片需要比较长时间。

请帮我：
1. 检查 Edge Function 的超时设置
2. iOS 端的 URLSession timeout 设置
3. 添加适当的加载提示
```

---

## 五、验证与测试

### 5.1 验证 Edge Function

```
帮我验证 Edge Function 是否正常：

1. 查看 Supabase Dashboard 的 Functions 日志
2. 确认函数已部署
3. 检查最近的调用记录和错误
```

### 5.2 验证生成效果

```
[截图: 生成的明信片]

请帮我确认：
1. 风格是否符合卡通/动漫要求
2. 人物是否成功卡通化
3. 文字显示是否只有城市名
4. 整体美观度如何
5. 还有哪些可以优化的地方
```

### 5.3 验证本地缓存

```
帮我验证本地缓存是否正常工作：

1. 生成后是否立即显示
2. 断网时是否还能看到之前的记录
3. 联网后是否自动同步
4. 删除时是否先本地删除再同步
```

---

## 六、完整提示词参考

### Edge Function 核心提示词（TypeScript）

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

### 追加强调（第二层提示词）

```typescript
const fullPrompt = prompt + '\n\n🚨🚨🚨 ABSOLUTE REQUIREMENT 🚨🚨🚨\n' +
  'The output image MUST be a 2D CARTOON/ANIME STYLE ILLUSTRATION.\n' +
  'DO NOT generate a realistic photograph.\n' +
  'DO NOT keep the person looking like a real photo.\n' +
  'CONVERT the person into an ANIME CHARACTER with the same art style as the background.\n' +
  'The final image should look like it was HAND-DRAWN by an animator, not photographed by a camera.\n' +
  'Style reference: Studio Ghibli, Makoto Shinkai anime films, Disney concept art.';
```
