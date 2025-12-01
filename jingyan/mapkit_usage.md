# MapKit 调用经验（基于原项目）

## 核心模式

1. **SwiftUI 包装 UIViewRepresentable**：`EarthLord/EarthLord/MapViewRepresentable.swift` 使用 `UIViewRepresentable` 包装 `MKMapView`，在 `makeUIView` 中配置地图类型（`mapType = .hybrid`）、POI 过滤、交互开关，并把 `MKMapView` 引用传给各 Manager（`territoryManager.mapView = mapView` 等），实现跨 Manager 协作。
2. **Coordinator 处理渲染**：`Coordinator` 实现 `MKMapViewDelegate` 来管理 overlay/annotation。通过 `updatePath/updateTerritories/updateBuildings` 等方法，根据 `LocationManager` 的路径、`TerritoryManager` 的数据、`BuildingManager` 的模板更新地图。这样一来，MapKit 实际渲染工作都由 coordinator 负责。
3. **自定义 Overlay/Annotation**：
   - 路径/领地：使用 `MKPolyline`、`MKPolygon`（`updatePath`, `updateTerritories`）。坐标点在更新时通过 `CoordinateConverter.convertIfNeeded` 处理 GCJ-02/标准坐标差异。
   - 建筑：自定义 `BuildingAnnotation`（`MapViewRepresentable.swift:5-61`），并在 `viewFor annotation` 中根据 `BuildingDisplayMode` 切换图标或缩略图。
4. **与 SwiftUI 状态联动**：`SimpleMapView` 使用 `@State` 控制器与 `MapViewRepresentable` 交互，例如 `@Binding var shouldCenterMap` 触发居中逻辑，`@Binding var buildingDisplayMode` 控制建筑显示模式，`@Binding var selectedBuilding` 打开详情。
5. **地图风格**：在 `applyApocalypseFilter` 中对 `mapView.layer.filters` 叠加 `CIFilter`，让默认的 MapKit 卫星图呈现末世滤镜（调亮度/饱和度/色温）。

## 检验与验证

- MapKit 直接依赖系统芯片的 GPS 数据，原项目通过 `mapView.showsUserLocation = true` 以及 `LocationManager` 的 `CLLocationManager` 同步来保证蓝点与自定义轨迹一致。
- 重点检查文件：
  - `EarthLord/EarthLord/MapViewRepresentable.swift`: 完整 MapKit 封装逻辑
  - `EarthLord/EarthLord/SimpleMapView.swift`: SwiftUI 层如何初始化 MapView、传递 Manager、处理 UI 交互
  - `EarthLord/EarthLord/CoordinateConverter.swift`: 大陆坐标转换逻辑
  - `EarthLord/EarthLord/LocationManager.swift`: CLLocationManager 配置（`desiredAccuracy`, 权限请求、路径跟踪）

## 引用方式

- 在 tuzi-fuke 项目中复用该结构时，按照以下顺序：
  1. 先实现 `CoordinateConverter`（若需要 GCJ 转换）和最简版 `MapViewRepresentable`（移除不必要的 overlay）。
  2. 新增 `SimpleMapView`，把当前的 `LocationManager`、`TerritoryManager` 等注入进去。
  3. 逐步把 overlay（路径→领地→建筑）和滤镜效果加回来。
- 复刻时优先保留原项目的 `Coordinator` 架构、`MKMapViewDelegate` 实现，确保与 MapKit 原生 API 兼容。

---

以上经验基于 `/Users/mikeliu/Desktop/tuzi-earthlord/EarthLord/EarthLord/MapViewRepresentable.swift` 与 `SimpleMapView.swift`，说明原版完全使用 MapKit（苹果地图 SDK）进行渲染，与友人“调用手机芯片 GPS”不同；我们要复制的也是该方案。
