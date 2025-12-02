//
//  CommunicationHubView.swift
//  tuzi-fuke
//
//  通讯终端主界面
//  集成消息、频道、设备管理三大模块
//

import SwiftUI

struct CommunicationHubView: View {
    // 0: 消息, 1: 频道, 2: 设备
    @State private var selectedTab: Int = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 1. 自定义 Tab 切换器
                CustomSegmentedControl(selectedTab: $selectedTab)
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    .background(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 2)
                    .zIndex(1) // 确保阴影在内容之上
                
                // 2. 内容区域
                TabView(selection: $selectedTab) {
                    CommsMessageView()
                        .tag(0)
                    
                    CommsChannelView()
                        .tag(1)
                    
                    CommsDeviceView()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe.americas.fill")
                            .foregroundColor(.blue)
                        Text("EARTH LINK TERMINAL")
                            .font(.system(.headline, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - 自定义 Segment Control
// 设计风格：战术/游戏化

struct CustomSegmentedControl: View {
    @Binding var selectedTab: Int
    
    private let tabs = [
        (icon: "message.fill", title: "讯息"),
        (icon: "list.bullet.rectangle.portrait.fill", title: "频道"),
        (icon: "radio.fill", title: "设备")
    ]
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = index
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tabs[index].icon)
                            .font(.system(size: 14))
                        Text(tabs[index].title)
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            if selectedTab == index {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue, lineWidth: 1.5)
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            }
                        }
                    )
                    .foregroundColor(selectedTab == index ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    CommunicationHubView()
}
