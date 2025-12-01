# 圈地实现经验（MapKit + Supabase）

## 1. 数据与模块分工

- `LocationManager`：负责持续采集 `CLLocation`，维护 `trackingPath`，同时提供闭环状态（是否返回起点）和路线坐标（必要时通过 `CoordinateConverter` 处理 GCJ-02 差异）。
- `TerritoryManager`：监听 `trackingPath`，计算面积/周长/点数，维护圈地状态机（未圈地→录制中→闭环→上传），负责将轨迹转换为领地模型并上传 Supabase；同时持有 `MKMapView` 引用用于渲染。
- `SimpleMapView`/`MapViewRepresentable`：SwiftUI 层提供圈地按钮、状态面板和 `MKMapView` 背景；Coordinator 负责将路径/多边形 overlay 添加到地图并渲染领地列表。
- Supabase 后端：`territories` 表存储领地属性（id/user_id/area/point_count/polygon_wkt/...）；`supabase/functions/validate-territory` Edge Function 执行自交/相交/包含校验。

## 2. 圈地流程（参考《01_开发日志》）

1. **开始圈地**：用户点击“开始圈地”，TerritoryManager 重置状态、记录起点，UI 开始显示录制指示、点数、距离、面积等指标。
2. **轨迹采集**：LocationManager 每次获得新位置即追加到 `trackingPath`，TerritoryManager 计算实时面积/周长，MapViewRepresentable 通过 Coordinator 将路径（`MKPolyline`）与当前闭环多边形（`MKPolygon`）画在地图上。
3. **闭环检测**：当用户回到起点附近（原版和朋友的经验均设定为 5m 以内）才允许“完成圈地”按钮生效，避免随便点几下就圈地；UI 实时显示“距起点 XX 米”并在接近时提示（参见日志中的“快到了”提醒）。
4. **本地校验**：
   - 点数≥3、面积≥最小阈值、路径不包含异常点。
   - 若在中国大陆，所有坐标先通过 `CoordinateConverter.convertIfNeeded` 转换成 WGS84 以便 MapKit 与 Supabase 一致。
5. **上传 Supabase**：TerritoryManager 构造 `TerritoryUpload`（包含 `polygon_wkt`、`area`、`point_count` 等），先调用 Edge Function `validate-territory`（`supabase/functions/validate-territory/index.ts`）执行三层校验（自相交/边界相交/包含他人领地），通过后写入 `territories` 表。
6. **结果反馈**：上传成功发出 `.territoryUploaded` 通知（SimpleMapView 监听），展示成功粒子动画与结果面板；失败则展示错误提示，并保留轨迹供用户重试。

## 3. 关键实现要点

- **UI 状态**：SimpleMapView 中维护圈地状态（录制、暂停、上传），底部 `MapControlsView` 控制按钮，顶部 `MapWarningsView` 显示运动状态/GPS 异常。圈地过程中实时显示点数、距离、面积、距起点距离（来自 `TerritoryManager` 统计）。
- **MKMapView 委托**：Coordinator 将 `trackingPath` 作为 `MKPolyline`，闭环时添加 `MKPolygon`；`territoryManager.nearbyTerritories` 显示历史领地，点击可查看详情。所有 overlay 颜色统一（橙色描边+半透明填充）。
- **最小约束**（参考原版逻辑与朋友经验）：
  - 点数≥50 或按照 `trackingPath` 自动加密，自适应 2 秒/10 米采样。
  - 面积≥100m²，周长≥60m。
  - 距离起点≤5m 才能结束，保证闭环。
  - 上传失败重试并提示原因（速率限制、冲突等）。
- **Supabase 边缘函数**：`validate-territory` 接口需要 `user_id`、`polygon_wkt`、`area`、`point_count`，内部再调用 RPC：self-intersection (`check_polygon_simple`)、boundary intersection (`check_polygon_intersection`，含5米容差) 和 containment (`check_polygon_containment`)；根据返回值给出友好错误信息。
- **数据模型**：`Territory` 包含 `id`, `userId`, `name`, `polygonWKT`, `area`, `perimeter`, `pointCount`, `createdAt`；`TerritoryUpload` 则包含原始点列表与现成 WKT，方便本地/云端同步。

## 4. 复刻建议

1. **优先跑通轨迹采集+闭环检测**：在 tuzi-fuke 先实现 `LocationManager` 的闭环判断和 `TerritoryManager` 的状态机，确保触发条件和 UI 提示正确。
2. **MapKit 渲染同步**：复用原版 `MapViewRepresentable` 的路径/多边形渲染逻辑，少改动即可保证 UI 与数据同步。
3. **后端对接**：在 Supabase 建好 `territories` 表与 Edge Function，按原项目 schema 上传；先允许直接写表，等客户端闭环稳定后再接 `validate-territory`。
4. **教学拆解**：可按朋友日志里的时间线（地图系统→圈地 UI→GPS→闭环）分阶段上课，每个阶段有明确验收（是否能显示轨迹、能否检测闭环、能否上传并在地图显示）。

以上内容结合 `/Users/mikeliu/Desktop/tuzi-earthlord/EarthLord/EarthLord/TerritoryManager.swift`、`SimpleMapView.swift`、`supabase/functions/validate-territory` 与朋友的 Day2 开发日志/提示词整理，可直接作为圈地实现参考与教学说明。
