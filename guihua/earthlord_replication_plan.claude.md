# 🎮 地球新主复刻计划 - AI辅助开发版

**项目名称**: EarthLord Clone (tuzi-fuke)
**开发模式**: AI辅助开发
**目标时间**: 3周完成MVP
**第一周检查点**: 核心功能演示

---

## 📊 原项目分析

### 技术规模

- **代码量**: 29,443+行Swift代码，136个源文件
- **Manager系统**: 16个核心管理器
- **数据库**: Supabase + PostGIS，18个表
- **功能复杂度**: 企业级iOS应用

### 核心架构

```
EarthLord/
├── 16个Manager系统 (AuthManager, LocationManager等)
├── SwiftUI视图层 (地图、建筑、通讯界面)
├── Models/ (复杂数据模型)
├── StoreKit/ (内购支付)
└── 中英文本地化
```

---

## 🎯 3周复刻策略

### Week 1: MVP核心功能 (演示版)

**目标**: 能演示核心玩法的原型

### Week 2: 功能完善 (可玩版)

**目标**: 基本可玩的游戏

### Week 3: 优化发布 (上线版)

**目标**: 可发布的完整应用

---

## 📅 第一周详细计划 (关键冲刺)

### 🚀 Day 1: 项目基础架构

#### 上午任务 (4小时)

1. **环境配置**
   
   ```bash
   # 当前项目: /Users/mikeliu/Desktop/tuzi-fuke
   # 已有基础iOS项目结构
   ```

2. **依赖集成**
   
   - [ ] Supabase iOS SDK
   - [ ] MapKit (地图功能)
   - [ ] CoreLocation (GPS定位)

3. **基础配置**
   
   - [ ] Info.plist权限配置 (定位、运动传感器)
   - [ ] Bundle ID设置
   - [ ] 目标版本设置 (iOS 15.0+)

#### 下午任务 (4小时)

4. **核心Manager框架搭建**
   
   ```swift
   // 创建这3个核心Manager (简化版)
   - AuthManager.swift      // 用户认证 (匿名登录)
   - LocationManager.swift  // GPS定位管理
   - DataManager.swift      // 数据存储 (Supabase简化版)
   ```

5. **基础数据模型**
   
   ```swift
   // 核心数据模型
   - User.swift           // 用户信息
   - Territory.swift      // 领土数据
   - Building.swift       // 建筑数据
   ```

**AI提示词模板**:

```
角色: 你是资深iOS开发工程师
任务: 帮我创建EarthLord游戏的[具体Manager名称]
要求:
- 使用SwiftUI + Combine架构
- 单例模式设计
- 包含完整错误处理
- 代码完整可编译运行
- 添加详细注释

请提供完整的Swift代码实现。
```

---

### 🗺️ Day 2: 地图与定位系统

#### 核心功能

1. **GPS定位获取**
   
   - [ ] 实时位置追踪
   - [ ] 位置权限处理
   - [ ] 后台定位支持

2. **地图显示**
   
   - [ ] MapKit集成
   - [ ] 显示用户当前位置
   - [ ] 地图交互功能

3. **简单数据存储**
   
   - [ ] Supabase连接设置
   - [ ] 基础数据表创建
   - [ ] 位置数据存储

**关键文件创建**:

```swift
Views/
├── MapView.swift          // 主地图界面
├── LocationTestView.swift // GPS测试界面
Models/
├── Location.swift         // 位置数据模型
```

---

### 🏰 Day 3: 领土圈占系统 (核心演示功能)

#### 核心功能

1. **地图圈占逻辑**
   
   - [ ] 点击地图圈占50米区域
   - [ ] 圆形区域可视化显示
   - [ ] 圈占数据保存

2. **领土管理**
   
   - [ ] 显示已占领区域
   - [ ] 领土边界绘制
   - [ ] 基础冲突检测

**⭐ 演示价值: 5/5** - 这是最重要的展示功能

**关键文件**:

```swift
Managers/
├── TerritoryManager.swift    // 领土管理器
Views/
├── TerritoryMapView.swift    // 领土地图视图
├── ClaimTerritoryView.swift  // 圈占界面
```

---

### 🏠 Day 4: 建筑系统 (简化版)

#### 核心功能

1. **建筑放置**
   
   - [ ] 在占领区域内放置建筑
   - [ ] 3-5种基础建筑类型
   - [ ] 建筑图标地图显示

2. **建筑管理**
   
   - [ ] 建筑列表界面
   - [ ] 建筑信息展示
   - [ ] 基础建筑逻辑

**建筑类型**:

```
🏠 住宅 - 提供人口
🏭 工厂 - 生产资源
🌾 农场 - 生产食物
⛽ 储藏 - 存储资源
🔧 维修站 - 维护建筑
```

---

### 🎨 Day 5: UI优化与交互

#### 核心任务

1. **主界面设计**
   
   - [ ] 游戏主菜单
   - [ ] 导航结构
   - [ ] 状态栏显示

2. **末日主题UI**
   
   - [ ] 深色配色方案
   - [ ] 废土风格组件
   - [ ] 基础动画效果

3. **用户交互优化**
   
   - [ ] 手势交互
   - [ ] 反馈效果
   - [ ] 加载状态

---

### 🔧 Day 6-7: 整合与测试

#### 关键任务

1. **功能整合测试**
   
   - [ ] 所有模块联调
   - [ ] 真机GPS测试
   - [ ] 数据流验证

2. **演示准备**
   
   - [ ] 演示数据准备
   - [ ] 演示流程优化
   - [ ] 关键问题修复

3. **性能优化**
   
   - [ ] 内存泄漏检查
   - [ ] 地图性能优化
   - [ ] 数据加载优化

---

## 💡 AI开发加速策略

### 1. 关键文件复用策略

**从原项目重点参考**:

```bash
# 优先研究这些核心文件
EarthLord/EarthLordApp.swift        # 应用架构
EarthLord/Models.swift              # 数据模型设计
EarthLord/LocationTrackerManager.swift  # 定位逻辑
EarthLord/TerritoryManager.swift    # 圈地核心算法
```

### 2. 技术简化原则

```
🟢 保留: GPS定位、地图圈占、建筑放置
🟡 简化: 用户认证(匿名)、数据存储(基础表)
🔴 跳过: 通讯系统、交易、内购、防作弊
```

### 3. AI提示词策略

**针对复杂功能的提示词模板**:

```
场景: 我正在复刻一个GPS策略游戏
原始代码参考: [粘贴原项目相关代码片段]
需求: 实现[具体功能]
技术栈: SwiftUI + Supabase + MapKit
要求:
- 代码完整可运行
- 简化版实现，专注核心功能
- 包含详细注释
- 遵循MVVM架构

请给出完整实现方案。
```

---

## 🎯 第一周交付目标

### 演示效果清单

- [x] ✅ 打开app显示地图界面，准确显示用户位置
- [x] ✅ 用户点击地图任意点，成功圈占50米圆形区域
- [x] ✅ 圈占区域以半透明圆形显示在地图上
- [x] ✅ 在已圈占区域内可以放置建筑(3-5种类型)
- [x] ✅ 建筑以图标形式显示在地图上
- [x] ✅ 基础的游戏导航界面和状态显示
- [x] ✅ 所有数据持久化到Supabase数据库

### 技术指标

- **代码量**: 2000-3000行 (vs原项目29,443行)
- **功能覆盖**: ~20%核心功能
- **演示时长**: 5-10分钟完整演示

---

## 📁 项目文件结构规划

```
tuzi-fuke/
├── tuzi-fuke/
│   ├── App/
│   │   ├── tuzi_fukeApp.swift         # 应用入口
│   │   └── ContentView.swift          # 主视图
│   ├── Managers/                      # 核心管理器
│   │   ├── AuthManager.swift
│   │   ├── LocationManager.swift
│   │   ├── TerritoryManager.swift
│   │   ├── BuildingManager.swift
│   │   └── DataManager.swift
│   ├── Models/                        # 数据模型
│   │   ├── User.swift
│   │   ├── Territory.swift
│   │   ├── Building.swift
│   │   └── Location.swift
│   ├── Views/                         # UI视图
│   │   ├── Map/
│   │   │   ├── GameMapView.swift
│   │   │   ├── TerritoryMapView.swift
│   │   │   └── BuildingMapView.swift
│   │   ├── UI/
│   │   │   ├── MainMenuView.swift
│   │   │   ├── BuildingListView.swift
│   │   │   └── UserStatusView.swift
│   │   └── Components/
│   │       ├── ApocalypseButton.swift
│   │       ├── StatusBar.swift
│   │       └── LoadingView.swift
│   ├── Services/                      # 服务层
│   │   ├── SupabaseService.swift
│   │   └── LocationService.swift
│   └── Utils/                         # 工具类
│       ├── Constants.swift
│       ├── Extensions.swift
│       └── Helpers.swift
├── Config/
│   ├── Info.plist                     # 应用配置
│   └── SupabaseConfig.swift           # 数据库配置
└── Resources/
    ├── Assets.xcassets                # 资源文件
    └── Sounds/                        # 音效文件
```

---

## 🚨 风险控制与应对

### 高风险点

1. **GPS定位问题** → 真机测试，模拟器备选方案
2. **地图性能问题** → 区域限制，数据分页
3. **Supabase连接问题** → 本地数据备选方案
4. **复杂度超预期** → 功能进一步简化

### 应急预案

- **Plan A**: 完整功能演示
- **Plan B**: 核心功能 + 模拟数据
- **Plan C**: 静态演示 + 关键功能说明

---

## 📞 AI协作工作流

### 每日协作流程

1. **晨会**: 明确当日目标和关键问题
2. **编码**: 使用AI完成60-70%编码工作
3. **测试**: 真机验证和问题修复
4. **晚总结**: 记录进度和明日计划

### AI使用最佳实践

- 🎯 **具体明确**: 详细描述需求和技术要求
- 📋 **分步骤**: 复杂功能拆分为小任务
- 🔍 **代码参考**: 提供原项目相关代码片段
- ⚡ **快速迭代**: 问题及时反馈，快速调整

---

## ✅ 执行检查清单

### 准备阶段 (今天完成)

- [ ] 读完整个复刻计划
- [ ] 确认开发环境和工具
- [ ] 注册Supabase账号
- [ ] 准备iOS开发者账号

### Day 1执行检查

- [ ] 项目依赖正确集成
- [ ] 基础Manager类编译通过
- [ ] 权限配置验证完成
- [ ] 真机基础测试OK

**开始执行时间**: ___________
**预计完成时间**: ___________
**实际完成时间**: ___________

---

**📝 备注**: 本计划基于AI辅助开发模式设计，重点关注快速原型验证。如遇技术难点，优先保证核心演示效果，细节优化留待后续迭代。

**🎯 一周后目标**: 向老板展示一个可交互、有核心玩法的游戏原型，证明技术可行性和开发进度。