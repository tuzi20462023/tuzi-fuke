//
//  POIFilterSheet.swift
//  tuzi-fuke
//
//  POI 类型筛选弹窗
//

import SwiftUI

struct POIFilterSheet: View {
    @ObservedObject var poiManager: POIManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 统计信息
                HStack {
                    Text("附近 POI")
                        .font(.headline)
                    Spacer()
                    Text("\(poiManager.filteredPOIs.count)/\(poiManager.allPOIs.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))

                // 快捷操作
                HStack {
                    Button("全选") {
                        poiManager.selectAllTypes()
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)

                    Spacer()

                    Button("清空") {
                        poiManager.deselectAllTypes()
                    }
                    .font(.subheadline)
                    .foregroundColor(.red)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // 类型列表
                List {
                    ForEach(POIType.allCases, id: \.self) { type in
                        POITypeRow(
                            type: type,
                            count: poiManager.countByType(type),
                            isSelected: poiManager.selectedTypes.contains(type),
                            onToggle: {
                                poiManager.toggleTypeFilter(type)
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("POI 筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - POI 类型行

struct POITypeRow: View {
    let type: POIType
    let count: Int
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // 图标
                Image(systemName: type.iconName)
                    .font(.title2)
                    .foregroundColor(Color(hex: type.color))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: type.color).opacity(0.15))
                    .cornerRadius(8)

                // 名称
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text("\(count) 个")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 选中状态
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color 扩展

extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}

// MARK: - Preview

#Preview {
    POIFilterSheet(poiManager: POIManager.shared)
}
