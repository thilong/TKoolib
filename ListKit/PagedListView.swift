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
    var appearance: PagedListAppearance = .default
    
    var body: some View {
        Group {
            switch model.loadMorePhase {
            case .idle, .loading:
                // `showsFooterLoading == false`：首屏已有 loading mask，footer 不再重复提示
                if appearance.showsFooterLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(appearance.loadingText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(appearance.retryText) {
                        Task { await model.retryLoadMore() }
                    }
                    .buttonStyle(.bordered)
                }
            case .exhausted:
                if !model.items.isEmpty, !appearance.exhaustedText.isEmpty {
                    Text(appearance.exhaustedText)
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
/// 下拉刷新：越过阈值后**手指松开**才开始加载。
///
/// 系统 `.refreshable` 在越过阈值的瞬间（手指还按着）就回调；这里先等滚动阶段离开
/// `.interacting` 再拉数据。等待状态放在不参与观察的引用盒子里，避免触发重绘。
/// iOS 17 没有 `onScrollPhaseChange`，退化为系统默认行为（越过阈值即加载）。
struct PullToRefreshOnRelease<Item: Identifiable>: ViewModifier {
    let model: PagedListModel<Item>
    @State private var gate = PullReleaseGate()

    func body(content: Content) -> some View {
        content
            .modifier(ScrollInteractionTracker(gate: gate))
            .refreshable { [gate] in
                // 放进独立 Task：refreshable 的任务在视图更新时可能被 SwiftUI 取消，
                // 取消会被 PagedListModel 静默吞掉，表现为"下拉了但没刷新"
                await Task {
                    await gate.waitForRelease()
                    await model.pullToRefresh()
                }.value
            }
    }
}

/// 记录手指是否还按在滚动视图上（普通引用类型，不参与 SwiftUI 观察）
@MainActor
final class PullReleaseGate {
    var isInteracting = false

    func waitForRelease() async {
        while isInteracting {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }
}

private struct ScrollInteractionTracker: ViewModifier {
    let gate: PullReleaseGate

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                gate.isInteracting = phase == .interacting
            }
        } else {
            content
        }
    }
}

/// 盖 loading 占位层时把列表旧内容隐藏。
///
/// 必须是独立的 modifier：`isShowingLoadingMask` 只能在这里读。若在挂 `.refreshable` 的那层
/// body 里直接读，下拉时 `phase` / `isPullRefreshing` 一变那层就重绘，
/// SwiftUI 会取消正在执行的 refreshable 任务 → 下拉刷新被静默打断。
struct HidesUnderLoadingMask<Item: Identifiable>: ViewModifier {
    let model: PagedListModel<Item>

    func body(content: Content) -> some View {
        content.opacity(model.isShowingLoadingMask ? 0 : 1)
    }
}

struct PagedListPlaceholder<Item: Identifiable>: View {
    let model: PagedListModel<Item>
    var appearance: PagedListAppearance = .default
    
    var body: some View {
        // 首屏 loading mask 的显示规则见 `PagedListModel.isShowingLoadingMask`。
        // 失败 / 空态仍只在列表为空时显示，避免刷新失败时把已有内容盖住。
        if model.isShowingLoadingMask {
            loadingPlaceholder
        } else if model.items.isEmpty {
            switch model.phase {
            case .idle:
                loadingPlaceholder
            case .failed(let message):
                if let failedView = appearance.failedView {
                    failedView(message)
                } else {
                    ContentUnavailableView {
                        Label(appearance.failedTitle, systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button(appearance.retryText) {
                            Task { await model.retryInitialLoad() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            case .loaded:
                if let emptyView = appearance.emptyView {
                    emptyView
                } else {
                    ContentUnavailableView(appearance.emptyTitle, systemImage: "tray")
                }
            case .loadingFirstPage:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var loadingPlaceholder: some View {
        if let loadingView = appearance.loadingView {
            loadingView
        } else {
            ProgressView().controlSize(.large)
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
    private let appearance: PagedListAppearance
    private let cell: (Item) -> Cell
    
    public init(
        model: PagedListModel<Item>,
        style: PagedListStyle = .list,
        appearance: PagedListAppearance = .default,
        @ViewBuilder cell: @escaping (Item) -> Cell
    ) {
        self.model = model
        self.style = style
        self.appearance = appearance
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
                // 盖 loading 占位层时隐藏旧内容，否则骨架会叠在旧 cell 上
                .modifier(HidesUnderLoadingMask(model: model))
            case .scroll:
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.items) { item in
                            cell(item)
                        }
                        LoadMoreFooter(model: model)
                    }
                    .modifier(HidesUnderLoadingMask(model: model))
                }
            }
        }
        .modifier(PullToRefreshOnRelease(model: model))
        .overlay {
            PagedListPlaceholder(model: model, appearance: appearance)
        }
        .task {
            await model.loadInitialIfNeeded()
        }
    }
}
