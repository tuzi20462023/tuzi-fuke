# 🚀 tuzi-fuke 项目环境配置指南

**项目**: 地球新主复刻版 (GPS策略游戏)
**状态**: Day 1 上午 - 环境初始化
**技术栈**: SwiftUI + Supabase + MapKit + CoreLocation

---

## ✅ 已完成配置

### 1. ✅ Info.plist权限配置

- [x] GPS定位权限 (前台+后台)
- [x] 运动传感器权限
- [x] URL Schemes配置
- [x] iOS 15.0+要求设置

### 2. ✅ SupabaseConfig配置文件

- [x] 创建了 `SupabaseConfig.swift`
- [x] 包含配置验证和调试功能

### 3. ✅ App入口文件更新

- [x] 导入MapKit和CoreLocation
- [x] 添加启动配置和验证逻辑

---

## 🔧 下一步：SPM依赖集成

### 步骤1: 在Xcode中添加Supabase iOS SDK

**详细操作步骤:**

1. **打开项目**
   
   ```bash
   cd /Users/mikeliu/Desktop/tuzi-fuke
   open tuzi-fuke.xcodeproj
   ```

2. **添加Package依赖**
   
   - 在Xcode中选择项目文件 (`tuzi-fuke`)
   - 选择 `Package Dependencies` 标签
   - 点击 `+` 按钮
   - 输入URL: `https://github.com/supabase/supabase-swift`
   - 点击 `Add Package`

3. **选择产品**
   
   - 勾选以下库:
     - [x] `Supabase` (核心库)
     - [x] `Auth` (认证功能)
     - [x] `PostgREST` (数据库操作)
     - [x] `Realtime` (实时功能，可选)
     - [x] `Storage` (文件存储，可选)
   - 点击 `Add Package`

### 步骤2: 验证依赖集成

**编译测试:**

```bash
# 在Xcode中按 ⌘+B 编译项目
# 应该看到编译成功，无错误
```

**运行测试:**

```bash
# 在模拟器中运行 ⌘+R
# 检查控制台输出是否显示配置信息
```

---

## 🔍 验证清单

### 编译验证

- [ ] `⌘+B` 编译成功，无错误
- [ ] 导入语句 `import Supabase` 无报错
- [ ] SupabaseConfig.swift 编译通过

### 运行验证

- [ ] 应用启动成功
- [ ] 控制台显示应用信息
- [ ] 控制台显示配置验证结果

### 权限验证

- [ ] Info.plist包含定位权限说明
- [ ] Info.plist包含运动传感器权限
- [ ] 应用能在真机上请求定位权限

---

## 🐛 常见问题解决

### 问题1: Supabase导入报错

```swift
// 如果看到 "No such module 'Supabase'" 错误
// 解决方案:
1. 确认SPM依赖已正确添加
2. 清理构建缓存: ⌘+Shift+K
3. 重新构建项目: ⌘+B
```

### 问题2: 权限配置问题

```xml
<!-- 确认Info.plist中包含这些权限说明 -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>地球新主需要访问您的位置来显示您在末世地图上的位置，记录您的开拓轨迹，并帮助您圈占虚拟土地。</string>
```

### 问题3: iOS版本目标设置

```bash
# 确认项目设置中:
# Deployment Target >= iOS 15.0
# Swift Language Version = Swift 5
```

---

## 📋 控制台预期输出

**成功配置后，应用启动时应该看到:**

```
🚀 [App] 地球新主启动中...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎮 地球新主 (tuzi-fuke) - GPS策略游戏
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
版本: MVP v1.0
技术栈: SwiftUI + Supabase + MapKit + CoreLocation
目标: iOS 15.0+
模式: AI辅助开发
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 Supabase 配置信息
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
URL: https://your-project.supabase.co
Key: your-anon-key-here...
状态: ❌ 需要配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 [App] 核心组件初始化中...
📍 [App] MapKit已导入
📱 [App] CoreLocation已导入
✅ [App] 应用初始化完成
```

---

## 🎯 下一步计划

### Day 1 下午任务

完成环境配置后，将创建:

1. **AuthManager.swift** - 匿名认证管理器
2. **LocationManager.swift** - GPS定位管理器
3. **DataManager.swift** - Supabase数据管理器

### 配置Supabase

1. 注册Supabase账号
2. 创建新项目
3. 更新SupabaseConfig.swift中的URL和密钥

---

## ✅ 执行确认

**当前状态**:

- [x] 环境配置文件已创建
- [x] 权限配置完成
- [x] App入口文件已更新
- [ ] **待办: SPM依赖集成** (需要在Xcode中手动完成)

**下一步**: 在Xcode中添加Supabase依赖，然后进行编译验证。