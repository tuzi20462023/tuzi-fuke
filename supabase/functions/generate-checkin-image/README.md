# Generate Check-in Image Edge Function

这个 Supabase Edge Function 用于调用 Gemini 2.0 Flash API 生成打卡图片。

## 功能特性

- 支持三种图片生成模式：selfie（自拍）、cartoon（卡通）、landscape（风景）
- 支持纯文本生成图片
- 支持带用户头像的图片生成（将用户头像融入场景）
- 自动上传到 Supabase Storage 的 `checkin-photos` bucket
- 返回图片的公开访问 URL

## API 接口

### 请求

**Method:** POST

**Body (JSON):**
```json
{
  "prompt": "在星巴克喝咖啡",
  "mode": "selfie",
  "avatarBase64": "iVBORw0KGgoAAAANSUhEUg...",  // 可选
  "userId": "user-123"  // 可选，用于组织存储路径
}
```

### 参数说明

- `prompt` (必填): 图片描述文本，用于指导 AI 生成图片
- `mode` (必填): 图片生成模式
  - `selfie`: 生成自拍风格的照片
  - `cartoon`: 生成卡通插画风格
  - `landscape`: 生成风景照片风格
- `avatarBase64` (可选): 用户头像的 base64 编码，可以包含或不包含 `data:image/png;base64,` 前缀
- `userId` (可选): 用户ID，用于按用户组织存储路径

### 响应

**成功响应 (200):**
```json
{
  "success": true,
  "image_url": "https://your-project.supabase.co/storage/v1/object/public/checkin-photos/user-123/selfie_1701234567890_abc123.png"
}
```

**错误响应 (400/500):**
```json
{
  "success": false,
  "error": "错误信息"
}
```

## 部署步骤

### 1. 确保 Supabase Storage Bucket 存在

在 Supabase Dashboard 中创建名为 `checkin-photos` 的 public bucket。

### 2. 设置环境变量

在 Supabase Dashboard 中设置以下环境变量：

- `GEMINI_API_KEY`: 你的 Gemini API Key（已在代码中硬编码作为后备）
- `SUPABASE_URL`: 自动提供
- `SUPABASE_SERVICE_ROLE_KEY`: 自动提供

### 3. 部署 Edge Function

使用 Supabase CLI 部署：

```bash
# 部署到 Supabase
supabase functions deploy generate-checkin-image

# 或者本地测试
supabase functions serve generate-checkin-image
```

## 使用示例

### JavaScript/TypeScript

```typescript
// 纯文本生成
const response = await fetch(
  'https://your-project.supabase.co/functions/v1/generate-checkin-image',
  {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${supabaseAnonKey}`
    },
    body: JSON.stringify({
      prompt: '在咖啡店工作，阳光明媚',
      mode: 'selfie'
    })
  }
);

const data = await response.json();
console.log('生成的图片URL:', data.image_url);
```

### 带头像生成

```typescript
// 先将图片转换为 base64
const avatarBase64 = await fileToBase64(avatarFile);

const response = await fetch(
  'https://your-project.supabase.co/functions/v1/generate-checkin-image',
  {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${supabaseAnonKey}`
    },
    body: JSON.stringify({
      prompt: '在海边散步',
      mode: 'cartoon',
      avatarBase64: avatarBase64,
      userId: 'user-123'
    })
  }
);

const data = await response.json();
console.log('生成的图片URL:', data.image_url);
```

## 技术细节

### Gemini API 配置

- 模型：`gemini-2.0-flash-exp`
- 输出模式：Image
- 宽高比：1:1（正方形）

### 图片存储

- Bucket: `checkin-photos`
- 命名格式: `{mode}_{timestamp}_{randomId}.png`
- 路径结构:
  - 有 userId: `{userId}/{fileName}`
  - 无 userId: `public/{fileName}`

### 图片生成模式详解

1. **selfie（自拍）**
   - 生成类似手机自拍的照片
   - 自然光照
   - 休闲的构图
   - 包含人物在画面中

2. **cartoon（卡通）**
   - 生成有趣的卡通插画
   - 鲜艳的色彩
   - 夸张的角色设计
   - 适合社交应用的可爱风格

3. **landscape（风景）**
   - 生成美丽的风景照片
   - 包含自然或城市景观
   - 良好的前景/中景/背景构图
   - 适合旅行或位置打卡

## 注意事项

1. Gemini API 有使用限制，请注意配额
2. 图片生成可能需要几秒到几十秒不等
3. 生成的图片大小通常在 100KB - 2MB 之间
4. 如果带头像生成，头像图片不应过大（建议小于 1MB）
5. Storage bucket 需要设置为 public 才能获取公开 URL

## 错误处理

常见错误及解决方案：

- `缺少prompt参数`: 确保请求中包含 prompt 字段
- `mode参数必须是selfie、cartoon或landscape之一`: 检查 mode 参数值
- `Gemini API生成图片失败`: 检查 API Key 是否有效，或查看详细日志
- `上传图片失败`: 确保 checkin-photos bucket 存在且权限正确

## 日志监控

可以在 Supabase Dashboard 的 Edge Functions Logs 中查看详细的执行日志：

- 环境变量检查
- 请求参数
- Gemini API 调用详情
- 图片生成和上传进度
- 错误信息

## 相关资源

- [Gemini API 文档](https://ai.google.dev/docs)
- [Supabase Edge Functions 文档](https://supabase.com/docs/guides/functions)
- [Supabase Storage 文档](https://supabase.com/docs/guides/storage)
