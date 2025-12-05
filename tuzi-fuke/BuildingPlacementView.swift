//
//  BuildingPlacementView.swift
//  tuzi-fuke
//
//  DAY8: 建筑放置界面 - 对话框形式，按需加载地图
//  参考原项目架构优化，解决白屏问题
//  Created by AI Assistant on 2025/12/02.
//  Updated: 2025/12/05 - 改为对话框+地图分离架构，优化UI
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - 建筑放置确认对话框

struct BuildingPlacementView: View {
    let template: BuildingTemplate
    let territory: Territory

    @ObservedObject private var buildingManager = BuildingManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var showLocationPicker = false
    @State private var isBuilding = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var buildSuccess = false

    // 主题色
    private var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(hex: "1c1c1e") : Color(hex: "f2f2f7")
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? Color(hex: "2c2c2e") : .white
    }

    var body: some View {
        // ✅ 改为全屏适配样式，配合 fullScreenCover 使用
        NavigationView {
            VStack(spacing: 0) {
                // 顶部建筑展示区
                headerSection

                // 内容区域
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // 位置选择
                        locationCard

                        // 资源消耗
                        resourceCard

                        // 建造时间
                        timeCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                // 底部按钮
                actionButtons
            }
            .background(cardBackground.edgesIgnoringSafeArea(.all))
            .navigationBarHidden(true)
        }
        .fullScreenCover(isPresented: $showLocationPicker) {
            BuildingLocationPickerView(
                territory: territory,
                buildingIcon: template.icon,
                existingBuildings: buildingManager.playerBuildings,
                buildingTemplates: buildingManager.buildingTemplates,
                onLocationSelected: { location in
                    selectedLocation = location
                    showLocationPicker = false
                },
                onCancel: {
                    showLocationPicker = false
                }
            )
        }
        .alert(buildSuccess ? "建造成功" : "建造失败", isPresented: $showResult) {
            Button("确定") {
                if buildSuccess {
                    dismiss()
                }
            }
        } message: {
            Text(resultMessage)
        }
    }

    // MARK: - 顶部建筑展示

    private var headerSection: some View {
        VStack(spacing: 0) {
            // 标题栏（带安全区域）
            HStack {
                Text("建造确认")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // 建筑图标和信息
            VStack(spacing: 10) {
                // 大图标
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 72, height: 72)

                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 58, height: 58)

                    Image(systemName: template.icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                }

                // 建筑名称
                Text(template.name)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)

                // 标签
                HStack(spacing: 6) {
                    TagView(text: template.category.displayName, color: .white.opacity(0.25))
                    TagView(text: "Tier \(template.tier)", color: .white.opacity(0.25))
                    if template.requiredLevel > 0 {
                        TagView(text: "需Lv.\(template.requiredLevel)", color: .white.opacity(0.25))
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(primaryGradient)
    }

    // MARK: - 位置选择卡片

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题
            Label("建造位置", systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            if let location = selectedLocation {
                // 已选择位置
                HStack(spacing: 10) {
                    // 位置图标
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 40, height: 40)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("位置已确认")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)

                        Text("\(String(format: "%.4f", location.latitude)), \(String(format: "%.4f", location.longitude))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        showLocationPicker = true
                    } label: {
                        Text("修改")
                            .font(.caption.weight(.medium))
                            .foregroundColor(Color(hex: "667eea"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(hex: "667eea").opacity(0.12))
                            .cornerRadius(6)
                    }
                }
            } else {
                // 未选择位置
                Button {
                    showLocationPicker = true
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(primaryGradient.opacity(0.15))
                                .frame(width: 40, height: 40)

                            Image(systemName: "map.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "667eea"))
                        }

                        Text("在地图上选择位置")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "667eea").opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
    }

    // MARK: - 资源消耗卡片

    private var resourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题
            Label("所需资源", systemImage: "shippingbox.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            // 资源列表（横向排列）
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 6) {
                ForEach(Array(template.requiredResources.keys.sorted()), id: \.self) { resource in
                    if let amount = template.requiredResources[resource] {
                        ResourceItemView(
                            name: resourceName(for: resource),
                            amount: amount,
                            icon: resourceIcon(for: resource)
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
    }

    // MARK: - 建造时间卡片

    private var timeCard: some View {
        HStack(spacing: 12) {
            // 图标
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: "clock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.purple)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("建造时间")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(template.formattedBuildTime)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.primary)
            }

            Spacer()

            // 测试模式标签
            Text("测试: 30秒")
                .font(.caption2.weight(.medium))
                .foregroundColor(Color(hex: "667eea"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: "667eea").opacity(0.1))
                .cornerRadius(4)
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
    }

    // MARK: - 底部按钮

    private var actionButtons: some View {
        HStack(spacing: 10) {
            // 取消按钮
            Button {
                dismiss()
            } label: {
                Text("取消")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(surfaceColor)
                    .cornerRadius(12)
            }

            // 确认建造按钮
            Button {
                Task {
                    await startBuilding()
                }
            } label: {
                HStack(spacing: 6) {
                    if isBuilding {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 14))
                    }
                    Text(isBuilding ? "建造中..." : "开始建造")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    canBuild ? primaryGradient : LinearGradient(colors: [Color.gray.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(12)
            }
            .disabled(!canBuild || isBuilding)
        }
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - Helpers

    private var canBuild: Bool {
        selectedLocation != nil
    }

    private func resourceName(for key: String) -> String {
        let names: [String: String] = [
            "wood": "木材", "stone": "石头", "metal": "金属",
            "cloth": "布料", "scrap": "废料", "nails": "钉子",
            "plastic": "塑料", "glass": "玻璃", "wire": "电线",
            "electronics": "电子件", "seeds": "种子", "soil": "土壤",
            "pipe": "管道", "rope": "绳索", "gears": "齿轮",
            "cement": "水泥", "medical_supplies": "医疗品", "antenna": "天线"
        ]
        return names[key] ?? key
    }

    private func resourceIcon(for key: String) -> String {
        let icons: [String: String] = [
            "wood": "leaf.fill", "stone": "mountain.2.fill", "metal": "gearshape.fill",
            "cloth": "tshirt.fill", "scrap": "trash.fill", "nails": "wrench.fill",
            "plastic": "cube.fill", "glass": "square.fill", "wire": "cable.connector",
            "electronics": "cpu.fill", "seeds": "leaf.circle.fill", "soil": "leaf.fill",
            "pipe": "pipe.and.drop.fill", "rope": "lasso", "gears": "gearshape.2.fill",
            "cement": "square.stack.3d.up.fill", "medical_supplies": "cross.case.fill", "antenna": "antenna.radiowaves.left.and.right"
        ]
        return icons[key] ?? "cube.fill"
    }

    private func startBuilding() async {
        guard let location = selectedLocation else { return }

        isBuilding = true

        let request = BuildingConstructionRequest(
            templateId: template.templateId,
            territoryId: territory.id,
            location: location,
            customName: nil
        )

        let result = await buildingManager.startConstruction(request: request)

        isBuilding = false
        buildSuccess = result.success
        resultMessage = result.message
        showResult = true
    }
}

// MARK: - 辅助视图组件

struct TagView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
            .cornerRadius(4)
    }
}

struct ResourceItemView: View {
    let name: String
    let amount: Int
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.orange)
                .frame(width: 16)

            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            Text("×\(amount)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
    }
}

// MARK: - 地图位置选择器（单独的 Sheet）

struct BuildingLocationPickerView: View {
    let territory: Territory
    let buildingIcon: String
    let existingBuildings: [PlayerBuilding]
    let buildingTemplates: [BuildingTemplate]
    let onLocationSelected: (CLLocationCoordinate2D) -> Void
    let onCancel: () -> Void

    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var isValidLocation = false

    var body: some View {
        NavigationView {
            ZStack {
                // 地图
                LocationPickerMapView(
                    territory: territory,
                    selectedLocation: $selectedLocation,
                    isValidLocation: $isValidLocation,
                    buildingIcon: buildingIcon,
                    existingBuildings: existingBuildings,
                    buildingTemplates: buildingTemplates
                )
                .edgesIgnoringSafeArea(.bottom)

                // 底部面板
                VStack {
                    Spacer()
                    bottomPanel
                }
            }
            .navigationTitle("选择建造位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        onCancel()
                    }
                }
            }
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            // 提示
            HStack {
                Image(systemName: selectedLocation == nil ? "hand.tap.fill" : (isValidLocation ? "checkmark.circle.fill" : "xmark.circle.fill"))
                    .font(.system(size: 18))
                    .foregroundColor(selectedLocation == nil ? .orange : (isValidLocation ? .green : .red))

                Text(selectedLocation == nil ? "点击绿色区域选择位置" : (isValidLocation ? "位置有效" : "请在领地范围内选择"))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(selectedLocation == nil ? .secondary : (isValidLocation ? .green : .red))

                Spacer()

                if let location = selectedLocation {
                    Text(String(format: "%.4f, %.4f", location.latitude, location.longitude))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // 确认按钮
            Button {
                if let location = selectedLocation, isValidLocation {
                    onLocationSelected(location)
                }
            } label: {
                Text("确认位置")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        (selectedLocation != nil && isValidLocation)
                            ? LinearGradient(colors: [Color(hex: "667eea"), Color(hex: "764ba2")], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(12)
            }
            .disabled(selectedLocation == nil || !isValidLocation)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 15, y: -5)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - 地图视图 (UIKit)

struct LocationPickerMapView: UIViewRepresentable {
    let territory: Territory
    @Binding var selectedLocation: CLLocationCoordinate2D?
    @Binding var isValidLocation: Bool
    let buildingIcon: String
    let existingBuildings: [PlayerBuilding]
    let buildingTemplates: [BuildingTemplate]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = false

        // 设置初始区域
        let wgs84Center = territory.centerLocation.coordinate
        let gcj02Center = CoordinateConverter.convertIfNeeded(wgs84Center)
        let radius = max(territory.radius, 50)
        let span = MKCoordinateSpan(
            latitudeDelta: radius * 4 / 111000,
            longitudeDelta: radius * 4 / 111000
        )
        mapView.setRegion(MKCoordinateRegion(center: gcj02Center, span: span), animated: false)

        // 添加领地边界
        addTerritoryPolygon(to: mapView)

        // 添加点击手势
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(context.coordinator.handleMapTap(_:))
        )
        mapView.addGestureRecognizer(tapGesture)

        // 异步添加已有建筑（不阻塞地图显示）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.addExistingBuildings(to: mapView)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // 更新选中位置标注
        let oldAnnotations = mapView.annotations.filter { annotation in
            if let building = annotation as? BuildingAnnotation {
                return building.isNewBuilding
            }
            return false
        }
        mapView.removeAnnotations(oldAnnotations)

        if let location = selectedLocation {
            let annotation = BuildingAnnotation(
                coordinate: location,
                icon: buildingIcon,
                isValid: isValidLocation,
                isNewBuilding: true,
                buildingName: "新建筑"
            )
            mapView.addAnnotation(annotation)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - 添加领地边界

    private func addTerritoryPolygon(to mapView: MKMapView) {
        let coordinates: [CLLocationCoordinate2D]

        if territory.isPolygon, let path = territory.path, !path.isEmpty {
            coordinates = path.compactMap { point in
                guard let lat = point["lat"], let lon = point["lon"] else { return nil }
                let wgs84 = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                return CoordinateConverter.convertIfNeeded(wgs84)
            }
        } else {
            let wgs84Center = territory.centerLocation.coordinate
            let gcj02Center = CoordinateConverter.convertIfNeeded(wgs84Center)
            coordinates = generateCircleCoordinates(center: gcj02Center, radius: territory.radius, points: 36)
        }

        guard coordinates.count >= 3 else { return }

        let polygon = MKPolygon(coordinates: coordinates, count: coordinates.count)
        polygon.title = "territory"
        mapView.addOverlay(polygon)
    }

    private func generateCircleCoordinates(center: CLLocationCoordinate2D, radius: Double, points: Int) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        let earthRadius = 6371000.0

        for i in 0..<points {
            let angle = (Double(i) / Double(points)) * 2 * .pi
            let latOffset = (radius / earthRadius) * cos(angle) * (180 / .pi)
            let lonOffset = (radius / earthRadius) * sin(angle) * (180 / .pi) / cos(center.latitude * .pi / 180)

            coordinates.append(CLLocationCoordinate2D(
                latitude: center.latitude + latOffset,
                longitude: center.longitude + lonOffset
            ))
        }

        return coordinates
    }

    // MARK: - 添加已有建筑

    private func addExistingBuildings(to mapView: MKMapView) {
        let templateDict = Dictionary(uniqueKeysWithValues: buildingTemplates.map { ($0.templateId, $0) })
        let territoryBuildings = existingBuildings.filter { $0.territoryId == territory.id }

        for building in territoryBuildings {
            guard let location = building.location else { continue }

            let coordinate = CLLocationCoordinate2D(
                latitude: location.coordinates[1],
                longitude: location.coordinates[0]
            )

            let template = templateDict[building.buildingTemplateKey]
            let icon = template?.icon ?? "building.2.fill"

            let annotation = BuildingAnnotation(
                coordinate: coordinate,
                icon: icon,
                isValid: true,
                isNewBuilding: false,
                buildingName: building.buildingName,
                buildingStatus: building.status
            )
            mapView.addAnnotation(annotation)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: LocationPickerMapView

        init(_ parent: LocationPickerMapView) {
            self.parent = parent
        }

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

            parent.selectedLocation = coordinate
            parent.isValidLocation = isLocationInTerritory(coordinate)
        }

        private func isLocationInTerritory(_ coordinate: CLLocationCoordinate2D) -> Bool {
            let territory = parent.territory

            if territory.isPolygon, let path = territory.path, path.count >= 3 {
                let locations = path.compactMap { point -> CLLocation? in
                    guard let lat = point["lat"], let lon = point["lon"] else { return nil }
                    let wgs84 = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let gcj02 = CoordinateConverter.convertIfNeeded(wgs84)
                    return CLLocation(latitude: gcj02.latitude, longitude: gcj02.longitude)
                }
                let testLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                return isPointInPolygon(point: testLocation, path: locations)
            } else {
                let wgs84Center = territory.centerLocation.coordinate
                let gcj02Center = CoordinateConverter.convertIfNeeded(wgs84Center)
                let centerLocation = CLLocation(latitude: gcj02Center.latitude, longitude: gcj02Center.longitude)
                let testLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                return testLocation.distance(from: centerLocation) <= territory.radius
            }
        }

        private func isPointInPolygon(point: CLLocation, path: [CLLocation]) -> Bool {
            guard path.count >= 3 else { return false }

            let x = point.coordinate.longitude
            let y = point.coordinate.latitude
            var inside = false

            var j = path.count - 1
            for i in 0..<path.count {
                let xi = path[i].coordinate.longitude
                let yi = path[i].coordinate.latitude
                let xj = path[j].coordinate.longitude
                let yj = path[j].coordinate.latitude

                let intersect = ((yi > y) != (yj > y)) &&
                               (x < (xj - xi) * (y - yi) / (yj - yi) + xi)

                if intersect {
                    inside.toggle()
                }

                j = i
            }

            return inside
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.25)
                renderer.strokeColor = UIColor.systemGreen
                renderer.lineWidth = 3.0
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let buildingAnnotation = annotation as? BuildingAnnotation {
                let identifier = buildingAnnotation.isNewBuilding ? "NewBuilding" : "ExistingBuilding"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

                if view == nil {
                    view = MKAnnotationView(annotation: buildingAnnotation, reuseIdentifier: identifier)
                    view?.canShowCallout = true
                } else {
                    view?.annotation = buildingAnnotation
                }

                let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
                let color: UIColor

                if buildingAnnotation.isNewBuilding {
                    color = buildingAnnotation.isValid ? .systemGreen : .systemRed
                } else {
                    switch buildingAnnotation.buildingStatus {
                    case .constructing: color = .systemBlue
                    case .active: color = .systemGreen
                    case .damaged: color = .systemOrange
                    case .inactive: color = .systemGray
                    case .none: color = .systemGray
                    }
                }

                view?.image = UIImage(systemName: buildingAnnotation.icon, withConfiguration: config)?
                    .withTintColor(color, renderingMode: .alwaysOriginal)

                return view
            }

            return nil
        }
    }
}

// MARK: - 建筑标注

class BuildingAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let icon: String
    let isValid: Bool
    let isNewBuilding: Bool
    let buildingName: String
    let buildingStatus: PlayerBuildingStatus?

    var title: String? { buildingName }

    var subtitle: String? {
        if isNewBuilding {
            return isValid ? "点击确认建造" : "位置无效"
        }
        return buildingStatus?.displayName
    }

    init(coordinate: CLLocationCoordinate2D, icon: String, isValid: Bool, isNewBuilding: Bool = true, buildingName: String = "", buildingStatus: PlayerBuildingStatus? = nil) {
        self.coordinate = coordinate
        self.icon = icon
        self.isValid = isValid
        self.isNewBuilding = isNewBuilding
        self.buildingName = buildingName
        self.buildingStatus = buildingStatus
        super.init()
    }
}

// MARK: - Preview

#Preview {
    BuildingPlacementView(
        template: BuildingTemplate(
            id: UUID(),
            templateId: "campfire",
            name: "篝火",
            tier: 1,
            category: .survival,
            description: "简单的篝火",
            icon: "flame.fill",
            requiredLevel: 0,
            requiredResources: ["wood": 30, "stone": 20],
            buildTimeHours: 0.5,
            effects: [:],
            maxPerTerritory: 3,
            maxLevel: 10,
            durabilityMax: 50,
            isActive: true,
            createdAt: Date()
        ),
        territory: Territory(
            id: UUID(),
            ownerId: UUID(),
            name: "测试领地",
            type: .circle,
            centerLatitude: 23.2005,
            centerLongitude: 114.4513,
            radius: 100
        )
    )
}
