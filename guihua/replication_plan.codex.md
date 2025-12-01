# 地球新主复刻规划（AI辅助一周冲刺）

## 1. 目标与范围

- **核心目标**：在 1 周内基于 AI 辅助完成《地球新主》MVP 复刻，重点展示“定位→圈地→建造”闭环。
- **演示要求**：真机运行，能完成匿名登录、实时定位、地图圈占、建筑放置、基础 UI 展示。
- **技术栈**：iOS 15+/SwiftUI/CoreLocation/MapKit/Supabase，遵循原仓库 `README.md` 中的所有强制准则。

## 2. 总体策略

1. **文档先行**：首日通读 `README.md`、`PROJECT_INFO.md`、`docs/核心功能实现规范_V4.2.md`、`docs/dynamic-message-system/*`、`docs/localization-lessons-learned.md`，列出必须遵守的技术红线。
2. **后端先打底**：同步 `supabase/migrations`、`supabase/functions`、`EarthLord/Resources`，确保数据库、函数、存储、StoreKit 测试环境齐备再写客户端。
3. **闭环优先**：聚焦“Auth + GPS + 地图圈占 + 建筑展示”主链路，其余系统（通讯、交易、IAP）延后。
4. **AI 迭代**：每个功能拆分成明确的输入/输出，编写提示词让 AI 生成代码 → 人工审查 → 真机验证 → 记录问题给下一轮提示。

## 3. 环境准备

- macOS 12+/Xcode 14+、Swift 5、CocoaPods/SwiftPM（视依赖而定）。
- Supabase CLI + Deno 1.37+，登录后创建新项目（region ap-southeast-1 优先）。
- Apple 开发者账号设置定位、后台更新、MapKit、StoreKit 测试证书；准备匿名登录所需的 Info.plist 权限文案。

## 4. Supabase 后端复刻

1. **项目创建**：在 Supabase 控制台新建项目，记录 URL/Anon Key，并更新 `SupabaseConfig.swift`。
2. **数据库迁移**：使用 `supabase db reset && supabase db push`（或逐条 `mcp__supabase__apply_migration`）应用 `supabase/migrations/` 全部 SQL。
3. **存储资源**：创建 `building-images` bucket，上传 `EarthLord/Resources/BuildingImages/*`，保持 `{template_id}_{thumbnail/full}.png` 命名。
4. **初始数据**：导入 `EarthLord/building_templates.json`、必要的 `insert_message_templates.sql` 等基础数据。
5. **Edge Functions**：在 `supabase/functions/` 目录逐个 `supabase functions deploy <name>`；配置环境变量 `SUPABASE_URL`、`SUPABASE_SERVICE_ROLE_KEY`。
6. **测试表**：为 MVP 建立简化表 `positions`, `territories`, `buildings`，字段遵照原项目模型但允许裁剪（Day2/Day3/Day4 使用）。

## 5. iOS 客户端复刻步骤

### Day 1 – 项目骨架

- 新建 SwiftUI App，集成 Supabase SDK、MapKit、CoreLocation，配置 Info.plist 权限。
- 实现 `SupabaseConfig`、`SupabaseManager`、`AuthManager`（匿名登录即可）、`LocationManager`（定位授权+单次获取）。
- 输出可运行 Demo，验证定位弹窗、Supabase 匿名登录成功。

### Day 2 – 定位与数据采集

- LocationManager 增强：后台/前台持续定位，每 10s push 位置信息 → Supabase `positions`。
- SwiftUI `LocationView` 实时展示经纬度、精度、上传状态。
- 构建基础 `DataRepository` 抽象，封装位置/领地/建筑的 CRUD。

### Day 3 – 地图与圈地

- 集成 MapKit，展示用户位置、历史轨迹。
- 点击地图任意点 → 生成 50m 圆形领地 → 写入 `territories` → 本地 overlay 渲染，提供列表查看。
- 预留圈地校验接口对接 `validate-territory` Edge Function（先可直接通过）。

### Day 4 – 建筑系统

- 设计 `BuildingType`（3-5 种），实现建筑放置 UI：选择领地 → 选类型 → 指定落点 → 保存 `buildings` → 地图 annotation 显示。
- 简化建造逻辑：即时完成，显示不同颜色/图标。
- 与 Supabase 数据同步，支持刷新和删除。

### Day 5 – UI 与体验

- 构建末日主题 Shell（深色调、渐变/噪点背景）。
- 整合地图页、建造列表、玩家面板，通过 `TabView` 或 `NavigationStack` 组织。
- 加入状态提示（定位状态、上传成功/失败、领地数、建筑数）。

### Day 6-7 – 打磨与演示

- 真机回归测试，录制演示流程。
- 修复性能/崩溃问题，完善日志与错误提示。
- 准备演示脚本、演示账号、预置数据，形成可重复展示的 demo。

## 6. 风险与缓解

| 风险               | 影响      | 预案                                 |
| ---------------- | ------- | ---------------------------------- |
| Supabase 迁移/函数复杂 | 阻塞客户端调试 | 先搭建最小 schema 与必要函数，复杂迁移分阶段验证       |
| 定位权限/真机差异        | 演示失败    | 每晚真机巡检 + 录屏备用                      |
| AI 生成代码质量不稳      | 返工      | 坚持“小任务→提示→审查→运行”循环，必要时提供现有代码片段作上下文 |
| 时间不足             | 功能残缺    | 所有新需求按“圈地闭环优先”过滤，其他进入待办            |

## 7. AI 协作模板

```
角色：你是一名资深 iOS/Supabase 工程师
任务：[描述功能，如“实现 MapKit 圈地并保存 Supabase”]
上下文：[列出相关模型/接口/约束]
输出要求：
- Swift 代码可直接粘贴运行
- 包含必要的模型、视图、Manager
- 提供 Supabase 表结构/SQL（如需要）
- 说明如何在现有项目中集成
```

## 8. 里程碑与交付

1. **M1（Day2）**：匿名登录 + 定位上传 + UI 展示。
2. **M2 (Day3)**：地图圈地闭环完成。
3. **M3 (Day4)**：建筑放置与展示完成。
4. **M4 (Day5)**：末日风格 UI + 主界面串联。
5. **M5 (Day7)**：演示脚本与真机录像交付。

---

> 每日结束前务必在真机验证当天闭环，记录问题清单；次日以问题驱动 AI 辅助开发，保证节奏与质量。

## 🔄 2025-11-21 08:48 更新

### Day1 进展摘要

- ✅ 工程初始化完成（Xcode 项目、Info.plist 权限、临时 `SupabaseConfig`、`tuzi_fukeApp` 骨架）。
- ✅ 三大核心 Manager（`AuthManager`、`LocationManager`、`DataManager`）和基础模型 (`User`, `Territory`, `Building`) 落地，并通过测试视图在真机验证运行。
- ✅ Day1 教学指南和提示词整理完毕，可复用在课堂演示。

### Day1 下午协作要点

- 错误处理流程固化：任何编译错误直接复制给 AI，按“复制→修复→验证”循环推进。
- 边界管理：已经将变体需求限定为“主题换皮”，删除过度设计的变体框架，聚焦核心圈地/建筑系统。
- 教学经验沉淀：`jiaoxue/DAY1_*` 文档形成标准案例，展示如何与 AI 配合完成核心 Manager 与数据模型。

### 11.21 晚复盘（与老板沟通要点）

- **模块化路线**：项目按 15 个系统拆分，圈地/地图是最核心的里程碑，建筑→资源→交易→通讯逐层叠加，动画/通讯等可作为加分项。
- **认证课程**：Apple/Google/Supabase 邮箱三种登录各用一天教学，难点在外部配置（Xcode、Google Console、Supabase）流程；需准备 7 步顺序和文档。
  - **认证课程**：Apple/Google/Supabase 邮箱三种登录各用一天教学，难点在外部配置（Xcode、Google Console、Supabase）流程；需准备 7 步顺序和文档。先完成核心闭环（地图→圈地→建造）后再安排真实 Apple/Google 登录课程，确保玩法先跑通、再单独讲第三方登录配置。
- **地图＋定位＋多人是核心价值**：所有变体围绕 MapKit + GPS + 多人定位扩展（建造、社交、商业、宝可梦式玩法等），强调“先跑通核心，再做变体”的策略。
- **教学策略**：每个模块完成即设里程碑，方便学生获得成就感；课程资源以模块化代码提供，课堂引导 AI 将大项目拆成小主题。
  
  

### 2025-11-22 12:50 模块优先级梳理

- **基础支撑层**（已完成）：认证（`AuthManager`）、SupabaseConfig、数据仓储（`DataRepository`）、定位基础（`LocationManager`）。Day1/Day2 已实现真实登录+GPS上传。
- **核心闭环层**（当前 Stage）：
  1. **地图展示**：复刻 `SimpleMapView` / `MapViewRepresentable`，渲染实时位置与历史轨迹。
  2. **圈地系统**：实现 `TerritoryManager`、领地模型、地图 Overlay；对接 Supabase `territories` 表与 `validate-territory` Edge Function。
  3. **建造系统**：在圈地基础上接入 `BuildingManager`、建筑模型与放置视图，完成“圈地后建造”体验。
- **资源/经济层**：`ItemManager`、`ResourcesTabView`，提供建筑材料；随后 `TradeManager` 支持交易市场。
- **社交/通讯层**：`CommunicationManager`、`ChannelManager`、`DynamicMessageManager`、`RadioManager`，可按课程安排逐步引入。
- **扩展层**：POI/探索（`POIManager`、`ExplorationManager`）、成就/排行榜、StoreKit/IAP、动画与音效增强。

当前作为 Stage 1→Stage 2 的过渡，需要优先完成“核心闭环层”的前三项：地图展示 → 圈地 → 建造。资源、交易、通讯等模块待核心闭环稳定后再分阶段上线，以保持与老板沟通的优先级一致。

老板希望把 Apple / Google / Supabase 邮箱登录拆成独立课程模块——它们属于“基础支撑层”但可以在核心闭环跑稳后讲。当前我们已经完成邮箱密
  码登录（Day2），下一阶段先把“地图→圈地→建造”闭环做完；等 M2/M3 里程碑稳定后，再按照老板说的安排专门的认证课程：用 1 天讲 Apple Sign
  In、1 天讲 Google Sign In、1 天讲 Supabase 邮箱验证（包含控制台配置、URL Scheme、Entitlements 等 7 步流程）。因此真实的 Google/
  Apple 登录就在核心闭环完成后、进入“认证课程”阶段时做，这样学生既能先看到玩法，也能在单独课程里专注处理复杂的第三方配置。

### 下一步规划（Stage 2 / Day3）

1. **地图展示**：在 `tuzi-fuke` 中复刻 `SimpleMapView`/`MapViewRepresentable`，渲染实时位置与历史轨迹（真机验证）并与现有 `LocationManager` 数据打通。
2. **圈地系统**：实现 `TerritoryManager`、领地模型、圈地 UI；写入 Supabase `territories` 表，预留 `validate-territory` Edge Function 调用；地图上渲染圈地 Overlay。
3. **建造准备**：梳理 `BuildingManager` 所需依赖，设计圈地完成后的入口（占领列表、放置按钮），为 Day4 的建筑系统做代码准备。

完成以上三项即可达成 Stage 2（地图圈地闭环），随后进入建造系统与资源/交易扩展，再在核心稳定后安排 Apple/Google 登录课程及主题变体。
