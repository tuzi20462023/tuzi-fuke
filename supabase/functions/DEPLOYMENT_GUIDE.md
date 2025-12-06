# Supabase Edge Functions 部署指南

## 前置准备

### 1. 安装 Supabase CLI

```bash
# macOS
brew install supabase/tap/supabase

# Windows (使用 Scoop)
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase

# Linux
brew install supabase/tap/supabase
```

### 2. 登录 Supabase

```bash
supabase login
```

这会打开浏览器进行身份验证。

### 3. 关联项目

```bash
# 在项目根目录执行
supabase link --project-ref your-project-ref
```

你可以在 Supabase Dashboard 的项目设置中找到 `project-ref`。

## 部署 generate-checkin-image Edge Function

### 步骤 1: 创建 Storage Bucket

在 Supabase Dashboard 中：

1. 进入 Storage
2. 创建新的 bucket
   - Name: `checkin-photos`
   - Public: ✅ 选中（允许公开访问）
   - File size limit: 10MB（可根据需求调整）
   - Allowed MIME types: `image/png, image/jpeg, image/jpg`

### 步骤 2: 设置环境变量（可选）

虽然 Gemini API Key 已经在代码中作为后备，但建议通过环境变量管理：

```bash
# 设置 Gemini API Key
supabase secrets set GEMINI_API_KEY=AIzaSyDEVX64qUo_fqQbrPdxR1o5Y4LpVDhxkxo

# 查看已设置的密钥
supabase secrets list
```

注意：`SUPABASE_URL` 和 `SUPABASE_SERVICE_ROLE_KEY` 会自动提供，无需手动设置。

### 步骤 3: 部署 Edge Function

```bash
# 部署单个函数
supabase functions deploy generate-checkin-image

# 部署所有函数
supabase functions deploy
```

### 步骤 4: 验证部署

```bash
# 查看部署的函数列表
supabase functions list

# 查看函数日志
supabase functions logs generate-checkin-image --follow
```

## 本地开发和测试

### 启动本地 Supabase

```bash
# 在项目根目录
supabase start
```

这会启动本地的 Supabase 服务，包括：
- Postgres 数据库
- Storage
- Edge Functions Runtime

### 本地运行 Edge Function

```bash
# 运行单个函数
supabase functions serve generate-checkin-image

# 运行所有函数
supabase functions serve
```

默认会在 `http://localhost:54321/functions/v1/generate-checkin-image` 启动。

### 使用测试脚本

```bash
cd supabase/functions/generate-checkin-image
./test-local.sh
```

或者使用 curl 手动测试：

```bash
curl -i --location --request POST 'http://localhost:54321/functions/v1/generate-checkin-image' \
  --header 'Content-Type: application/json' \
  --data '{
    "prompt": "在咖啡店工作",
    "mode": "selfie",
    "userId": "test-user"
  }'
```

## 生产环境测试

部署后，使用生产 URL 测试：

```bash
curl -i --location --request POST 'https://your-project-ref.supabase.co/functions/v1/generate-checkin-image' \
  --header 'Content-Type: application/json' \
  --header 'Authorization: Bearer YOUR_ANON_KEY' \
  --data '{
    "prompt": "在海边散步",
    "mode": "landscape"
  }'
```

## 权限配置

### Storage Bucket 策略

为了让 Edge Function 能够上传文件并让用户访问，需要设置正确的 Storage 策略：

1. 在 Supabase Dashboard 进入 Storage > Policies
2. 为 `checkin-photos` bucket 创建以下策略：

**策略 1: 允许所有人读取**
```sql
CREATE POLICY "Public Access"
ON storage.objects FOR SELECT
USING ( bucket_id = 'checkin-photos' );
```

**策略 2: 允许 Edge Function 上传**
```sql
CREATE POLICY "Service Role Upload"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'checkin-photos'
  AND auth.role() = 'service_role'
);
```

**策略 3: 允许用户删除自己的图片（可选）**
```sql
CREATE POLICY "Users Delete Own Images"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'checkin-photos'
  AND auth.uid()::text = (storage.foldername(name))[1]
);
```

## 监控和调试

### 查看日志

在 Supabase Dashboard:
- Functions > generate-checkin-image > Logs
- 或使用 CLI: `supabase functions logs generate-checkin-image --follow`

### 常见问题排查

1. **函数返回 500 错误**
   - 检查环境变量是否正确设置
   - 查看函数日志了解详细错误
   - 确认 Gemini API Key 有效

2. **上传失败**
   - 确认 `checkin-photos` bucket 存在
   - 检查 Storage 策略配置
   - 确认 Service Role Key 有效

3. **Gemini API 调用失败**
   - 检查 API Key 配额
   - 确认网络连接正常
   - 查看 Gemini API 状态页面

## 成本估算

### Supabase Edge Functions
- 前 500,000 次调用/月：免费
- 超出部分：$2/100,000 次调用

### Supabase Storage
- 前 1GB 存储：免费
- 超出部分：$0.021/GB/月

### Gemini API
- 具体费用请参考 Google AI 定价页面
- `gemini-2.0-flash-exp` 模型通常是实验性模型，可能有不同的定价

## 更新和回滚

### 更新函数

```bash
# 修改代码后重新部署
supabase functions deploy generate-checkin-image
```

### 查看版本历史

在 Supabase Dashboard 的 Functions 页面可以查看所有部署版本。

## 最佳实践

1. **使用环境变量管理密钥**
   - 不要在代码中硬编码敏感信息
   - 使用 `supabase secrets` 管理

2. **实现请求限流**
   - 考虑添加请求频率限制
   - 使用 Supabase Auth 验证用户身份

3. **错误处理**
   - 提供清晰的错误信息
   - 记录详细的日志用于调试

4. **监控和告警**
   - 定期检查函数日志
   - 设置关键指标告警

5. **测试覆盖**
   - 在本地充分测试后再部署
   - 使用测试脚本覆盖各种场景

## 相关链接

- [Supabase Edge Functions 文档](https://supabase.com/docs/guides/functions)
- [Supabase CLI 参考](https://supabase.com/docs/reference/cli)
- [Gemini API 文档](https://ai.google.dev/docs)
- [Deno Deploy 文档](https://deno.com/deploy/docs)
