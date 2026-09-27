//
//  PagedListView.swift
//  ListKit
//
//  单列分页列表：下拉刷新 + 上拉加载更多 + 自定义 cell。
//
//  两种外观：
//  * `.list`：原生 `List`，全懒加载、系统性能最好；
//  * `.scroll`：`ScrollView` + `LazyVStack`，外观完全自定义（无分隔线 / 自定义间距）。
//
//  两种外观共用同一个 `PagedListModel` 与同一个 footer 逻辑。
//

import SwiftUI

// MARK: - 底部加载状态

/// 列表底部的「加载更多」哨兵。
///
/// * `triggersLoad` 为 true 时（`List` 这类**懒容器**），出现即触发下一页：
///   `.task(id: items.count)` 会在首次出现、以及每次数据变化时执行 ——
///   首屏内容不足一屏时也能自动继续补，不会卡住；
/// * `triggersLoad` 为 false 时只负责显示状态，由外层（如瀑布流的滚动几何）触发加载；
/// * 失败给出重试按钮，到底了显示「没有更多了」。
@MainActor
struct LoadMoreFooter<Item: Identifiable>: View {
    let model: PagedListModel<Item>
    var triggersLoad: Bool = true
    
    var body: some View {
        Group {
            switch model.loadMorePhase {
            case .idle:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("加载中…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("加载中…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await model.retryLoadMore() }
                    }
                    .buttonStyle(.bordered)
                }
            case .exhausted:
                if !model.items.isEmpty {
                    Text("没有更多了")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("listkit.exhausted")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .task(id: model.items.count) {
            guard triggersLoad, model.loadMorePhase != .exhausted else { return }
            // ⚠️ 用非结构化 Task 发请求：`.task` 会随视图滚出屏幕被取消，
            // 快速滑动时每次请求都被打断，列表就永远停在「加载中…」分不出页。
            // 这里只负责「触发」，请求本身不受视图生命周期影响（重复调用由 model 的护栏拦住）。
            Task { await model.loadMore() }
        }
    }
}

// MARK: - 首屏占位

/// 首屏状态占位：只在列表为空时覆盖显示。
@MainActor
struct PagedListPlaceholder<Item: Identifiable>: View {
    let model: PagedListModel<Item>
    
    var body: some View {
        if model.items.isEmpty {
            switch model.phase {
            case .idle, .loadingFirstPage:
                ProgressView()
                    .controlSize(.large)
            case .failed(let message):
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task { await model.retryInitialLoad() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .loaded:
                ContentUnavailableView("暂无内容", systemImage: "tray")
            }
        }
    }
}

// MARK: - 外观

/// 单列列表的两种外观。
public enum PagedListStyle: String, CaseIterable, Identifiable, Sendable {
    /// 原生 `List`：全懒加载，系统分隔线与滑动体验
    case list
    /// `ScrollView` + `LazyVStack`：外观完全自定义
    case scroll
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .list: "List"
        case .scroll: "ScrollView"
        }
    }
}

// MARK: - 列表

public struct PagedListView<Item: Identifiable, Cell: View>: View {
    private let model: PagedListModel<Item>
    private let style: PagedListStyle
    private let cell: (Item) -> Cell
    
    public init(
        model: PagedListModel<Item>,
        style: PagedListStyle = .list,
        @ViewBuilder cell: @escaping (Item) -> Cell
    ) {
        self.model = model
        self.style = style
        self.cell = cell
    }
    
    public var body: some View {
        Group {
            switch style {
            case .list:
                List {
                    ForEach(model.items) { item in
                        cell(item)
                    }
                    LoadMoreFooter(model: model)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            case .scroll:
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.items) { item in
                            cell(item)
                        }
                        LoadMoreFooter(model: model)
                    }
                }
            }
        }
        .refreshable {
            await model.refresh()
        }
        .overlay {
            PagedListPlaceholder(model: model)
        }
        .task {
            await model.loadInitialIfNeeded()
        }
    }
}
