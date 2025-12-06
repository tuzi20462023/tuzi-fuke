//
//  LogViewerView.swift
//  tuzi-fuke
//
//  App内日志查看界面 - 断开Xcode后也能看日志
//

import SwiftUI

struct LogViewerView: View {
    @ObservedObject var logger = AppLogger.shared

    @State private var filterLevel: LogLevel? = nil
    @State private var filterCategory: String = ""
    @State private var showShareSheet = false
    @State private var autoScroll = true

    var filteredLogs: [LogEntry] {
        logger.logs.filter { entry in
            // 级别过滤
            if let level = filterLevel, entry.level != level {
                return false
            }
            // 分类过滤
            if !filterCategory.isEmpty && !entry.category.localizedCaseInsensitiveContains(filterCategory) {
                return false
            }
            return true
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 过滤器栏
                filterBar

                Divider()

                // 日志列表
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredLogs) { entry in
                                logEntryRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: logger.logs.count) { _, _ in
                        if autoScroll, let lastLog = filteredLogs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // 底部状态栏
                bottomBar
            }
            .navigationTitle("📋 运行日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { logger.clear() }) {
                            Label("清除日志", systemImage: "trash")
                        }

                        Button(action: { showShareSheet = true }) {
                            Label("导出日志", systemImage: "square.and.arrow.up")
                        }

                        Toggle("自动滚动", isOn: $autoScroll)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(text: logger.exportLogs())
            }
        }
    }

    // MARK: - 过滤器栏

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 级别过滤按钮
                filterButton(nil, label: "全部")
                filterButton(.error, label: "错误")
                filterButton(.warning, label: "警告")
                filterButton(.success, label: "成功")
                filterButton(.info, label: "信息")
                filterButton(.debug, label: "调试")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6))
    }

    private func filterButton(_ level: LogLevel?, label: String) -> some View {
        Button(action: { filterLevel = level }) {
            Text(level?.rawValue ?? "📋")
                .font(.caption)
            Text(label)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(filterLevel == level ? Color.blue : Color(.systemGray5))
        .foregroundColor(filterLevel == level ? .white : .primary)
        .cornerRadius(16)
    }

    // MARK: - 日志条目行

    private func logEntryRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(entry.formattedTime)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)

            Text(entry.level.rawValue)
                .font(.system(size: 12))

            Text("[\(entry.category)]")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(entry.level.color)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 底部状态栏

    private var bottomBar: some View {
        HStack {
            Text("共 \(logger.logs.count) 条日志")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if filterLevel != nil || !filterCategory.isEmpty {
                Text("显示 \(filteredLogs.count) 条")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

// MARK: - 分享Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    init(text: String) {
        self.items = [text]
    }

    init(items: [Any]) {
        self.items = items
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    LogViewerView()
}
