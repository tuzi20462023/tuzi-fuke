#!/bin/bash

# 测试 generate-checkin-image Edge Function
# 使用方法: ./test-local.sh

echo "🧪 测试 generate-checkin-image Edge Function"
echo "============================================"
echo ""

# 测试 1: Selfie 模式（无头像）
echo "📸 测试 1: Selfie 模式（纯文本）"
curl -i --location --request POST 'http://localhost:54321/functions/v1/generate-checkin-image' \
  --header 'Content-Type: application/json' \
  --data '{
    "prompt": "在星巴克喝咖啡，阳光明媚",
    "mode": "selfie"
  }'

echo -e "\n\n"
sleep 2

# 测试 2: Cartoon 模式
echo "🎨 测试 2: Cartoon 模式"
curl -i --location --request POST 'http://localhost:54321/functions/v1/generate-checkin-image' \
  --header 'Content-Type: application/json' \
  --data '{
    "prompt": "在公园里野餐",
    "mode": "cartoon",
    "userId": "test-user-123"
  }'

echo -e "\n\n"
sleep 2

# 测试 3: Landscape 模式
echo "🏞️ 测试 3: Landscape 模式"
curl -i --location --request POST 'http://localhost:54321/functions/v1/generate-checkin-image' \
  --header 'Content-Type: application/json' \
  --data '{
    "prompt": "美丽的海滩日落",
    "mode": "landscape"
  }'

echo -e "\n\n"

# 测试 4: 错误处理 - 缺少 prompt
echo "❌ 测试 4: 错误处理（缺少 prompt）"
curl -i --location --request POST 'http://localhost:54321/functions/v1/generate-checkin-image' \
  --header 'Content-Type: application/json' \
  --data '{
    "mode": "selfie"
  }'

echo -e "\n\n"

# 测试 5: 错误处理 - 无效的 mode
echo "❌ 测试 5: 错误处理（无效的 mode）"
curl -i --location --request POST 'http://localhost:54321/functions/v1/generate-checkin-image' \
  --header 'Content-Type: application/json' \
  --data '{
    "prompt": "测试",
    "mode": "invalid"
  }'

echo -e "\n\n"
echo "✅ 测试完成！"
