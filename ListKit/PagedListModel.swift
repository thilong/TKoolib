//
//  PagedListModel.swift
//  ListKit
//
//  分页列表的状态机：首屏加载 / 下拉刷新 / 上拉加载更多 / 失败重试。
//
//  设计要点：
//  * 数据源只是一个闭包 `(offset, limit) async throws -> PagedResponse`，
//    组件不关心是网络、数据库还是内存数组；
//  * 所有状态都在 `@MainActor` 上，`isLoading` 是并发护栏：快速滚动时
//    footer 可能连续触发多次，只有第一次会真的发请求；
//  * 取消（滚出屏幕 / 刷新打断）不算失败，不会污染 UI 状态。
//

import Foundation
import Observation

// MARK: - 数据源协议

/// 一页数据。
public struct PagedResponse<Item> {
  public var items: [Item]
  /// 是否还有下一页。显式返回，避免用「本页数量 < limit」这种容易出错的推断。
  public var hasMore: Bool

  public init(items: [Item], hasMore: Bool) {
    self.items = items
    self.hasMore = hasMore
  }
}

/// 分页数据源。
///
/// ```swift
/// let model = PagedListModel<Post> { offset, limit in
///   let page = try await api.posts(offset: offset, limit: limit)
///   return PagedResponse(items: page.items, hasMore: page.hasMore)
/// }
/// ```
public typealias PagedLoader<Item> = (_ offset: Int, _ limit: Int) async throws -> PagedResponse<Item>

// MARK: - 状态

public enum PagedPhase: Equatable {
  case idle
  case loadingFirstPage
  case loaded
  case failed(message: String)

  public var isFailed: Bool {
    if case .failed = self { return true }
    return false
  }
}

public enum PagedLoadMorePhase: Equatable {
  /// 还有下一页，等待 footer 出现时触发
  case idle
  case loading
  case failed(message: String)
  /// 没有更多了
  case exhausted

  public var isLoading: Bool { self == .loading }
}

// MARK: - Model

@MainActor
@Observable
public final class PagedListModel<Item: Identifiable> {
  public private(set) var items: [Item] = []
  public private(set) var phase: PagedPhase = .idle
  public private(set) var loadMorePhase: PagedLoadMorePhase = .idle

  /// 每页条数。
  public var pageSize: Int
  /// 是否按 `id` 去重（分页接口常见的重复推送场景）。
  public var deduplicatesByID: Bool

  @ObservationIgnored private let loader: PagedLoader<Item>
  @ObservationIgnored private var nextOffset = 0
  @ObservationIgnored private var seenIDs: Set<Item.ID> = []
  /// 并发护栏：一次只允许一个请求在飞。
  @ObservationIgnored private var isLoading = false
  /// `autoLoadOnce()` 是否已经放过行（生命周期级的"进页面只加载一次"）
  @ObservationIgnored private var hasAutoLoadedOnce = false

  public init(
    pageSize: Int = 20,
    deduplicatesByID: Bool = true,
    loader: @escaping PagedLoader<Item>
  ) {
    self.pageSize = pageSize
    self.deduplicatesByID = deduplicatesByID
    self.loader = loader
  }

  // MARK: 派生状态

  public var isEmpty: Bool { phase == .loaded && items.isEmpty }

  public var hasMore: Bool { loadMorePhase != .exhausted }

  public var isRefreshingFirstPage: Bool { phase == .loadingFirstPage && !items.isEmpty }

  // MARK: 首屏

  /// 只在还没加载过时加载首屏（可以直接挂在 `.task` 上）。
  ///
  /// 语义是"首屏初始化一次"：只要 `phase` 已经从 `.idle` 走出去就不再重复。**失败后不会再试**
  /// （重试走 `retryInitialLoad()`）。
  public func loadInitialIfNeeded() async {
    guard phase == .idle else { return }
    await loadFirstPage(keepingItemsOnFailure: false)
  }

  /// 生命周期级的"进页面只加载一次"。
  ///
  /// 与 `loadInitialIfNeeded()` 的区别：多一个**只认一次的标记**，即使 SwiftUI 因为视图
  /// 重建 / 切 tab 再次触发 `.task`，这里也只放行第一次。
  /// 适合"缓存型 tab"（切走不销毁、切回来 `.task` 会被再跑一遍）——不希望在切回时重新拉数据。
  ///
  /// 注意：它只管**自动进入时**的那一次。用户主动刷新（下拉 `refresh()`、切筛选条件、
  /// 重试 `retryInitialLoad()`）都不受这个标记约束。
  public func autoLoadOnce() async {
    guard !hasAutoLoadedOnce else { return }
    hasAutoLoadedOnce = true
    await loadInitialIfNeeded()
  }

  /// 首屏失败后的重试（用户点「重试」）。
  public func retryInitialLoad() async {
    await loadFirstPage(keepingItemsOnFailure: false)
  }

  // MARK: 下拉刷新

  /// 下拉刷新：重新拉第一页并整体替换。
  ///
  /// 失败时**保留已有数据**，只把错误抛到 `loadMorePhase` 之外的状态里，
  /// 避免用户一下拉就把内容清空。
  public func refresh() async {
    await loadFirstPage(keepingItemsOnFailure: true)
  }

  /// 用户下拉触发的刷新（列表组件的 `.refreshable` 调这个）。
  /// 和 `refresh()` 一样重拉第一页；区别是已有数据时占位层不盖 loading（顶部已经有系统的刷新圈）。
  /// 切筛选条件等程序触发的 `refresh()` 仍然盖 loading，因为旧内容已经不对应新的条件
  public func pullToRefresh() async {
    isPullRefreshing = true
    defer { isPullRefreshing = false }
    await refresh()
  }

  /// 是否正在执行 `pullToRefresh()`
  public private(set) var isPullRefreshing = false

  // MARK: 上拉加载更多

  /// 加载下一页。重复调用是安全的：正在加载或已到底时直接返回。
  public func loadMore() async {
    guard loadMorePhase != .exhausted, !isLoading else { return }

    isLoading = true
    loadMorePhase = .loading
    let offset = nextOffset
    defer { isLoading = false }

    do {
      let response = try await loader(offset, pageSize)
      append(response.items)
      nextOffset = offset + response.items.count
      loadMorePhase = response.hasMore ? .idle : .exhausted
    } catch is CancellationError {
      // 滚出屏幕 / 刷新打断：静默回退，等 footer 再出现时重试。
      loadMorePhase = .idle
    } catch {
      loadMorePhase = .failed(message: Self.describe(error))
    }
  }

  /// footer 上「重试」按钮。
  public func retryLoadMore() async {
    guard case .failed = loadMorePhase else { return }
    loadMorePhase = .idle
    await loadMore()
  }

  /// 清空回初始状态（切换数据源 / 退出登录等）。
  public func reset() {
    items = []
    seenIDs = []
    nextOffset = 0
    phase = .idle
    loadMorePhase = .idle
  }

  // MARK: 本地增删改

  /// 本地插入一条（发布新帖、插入自己的新评论…）。
  ///
  /// * 默认插到最前；`at` 越界会被夹到合法范围
  /// * `deduplicatesByID == true` 时若同 id 已存在则**就地替换**，不会出现重复行
  /// * 与 `remove` 一样**不改分页游标**：游标记的是「服务端已经取到第几条」，
  ///   本地插入不应该让下一页跳过一条
  public func insert(_ item: Item, at index: Int = 0) {
    if deduplicatesByID, let existing = items.firstIndex(where: { $0.id == item.id }) {
      items[existing] = item
      return
    }
    let target = min(max(index, 0), items.count)
    items.insert(item, at: target)
    seenIDs.insert(item.id)
  }

  /// 批量插入，保持传入顺序（`at` 为起始下标）
  public func insert(contentsOf newItems: [Item], at index: Int = 0) {
    guard !newItems.isEmpty else { return }
    for (offset, item) in newItems.enumerated() {
      insert(item, at: index + offset)
    }
  }

  /// 就地替换同 id 的元素（点赞后更新计数、编辑后更新内容…）。
  /// 返回是否找到并替换；本地不存在的元素如需插入请用 `insert`。
  @discardableResult
  public func replace(_ item: Item) -> Bool {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
    items[index] = item
    return true
  }

  /// 本地移除一条（收藏页取消收藏、屏蔽某人、删除草稿…）。
  ///
  /// 只动本地数组，**不改分页游标** —— 游标记的是「服务端已经取到第几条」，
  /// 本地删掉一条不应该让下一页跳过一条。
  ///
  /// 注意：如果服务端并没有真的删除，这条数据之后仍可能从后续页面回来
  /// （下拉刷新会整体重取，也一定会回来）。需要真正删除请调用服务端接口后
  /// 再 `refresh()`。
  public func remove(_ id: Item.ID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    let removed = items.remove(at: index)
    seenIDs.remove(removed.id)
  }

  /// 批量移除（`List` 的 `.onDelete` 给的就是 `IndexSet`）。
  public func remove(at offsets: IndexSet) {
    // 从后往前删，避免下标平移。
    for index in offsets.sorted(by: >) where items.indices.contains(index) {
      let removed = items.remove(at: index)
      seenIDs.remove(removed.id)
    }
  }

  /// 只保留满足条件的元素（过滤掉屏蔽用户等）。
  public func removeAll(where shouldRemove: (Item) -> Bool) {
    let removed = items.filter(shouldRemove)
    guard !removed.isEmpty else { return }
    items.removeAll(where: shouldRemove)
    for item in removed {
      seenIDs.remove(item.id)
    }
  }

  // MARK: 内部

  private func loadFirstPage(keepingItemsOnFailure: Bool) async {
    isLoading = true
    phase = .loadingFirstPage
    defer { isLoading = false }

    do {
      let response = try await loader(0, pageSize)
      items = []
      seenIDs = []
      append(response.items)
      nextOffset = response.items.count
      loadMorePhase = response.hasMore ? .idle : .exhausted
      phase = .loaded
    } catch is CancellationError {
      phase = items.isEmpty ? .idle : .loaded
    } catch {
      if keepingItemsOnFailure, !items.isEmpty {
        // 下拉刷新失败：保留旧数据，只提示失败。
        phase = .loaded
        loadMorePhase = .failed(message: Self.describe(error))
      } else {
        phase = .failed(message: Self.describe(error))
      }
    }
  }

  private func append(_ newItems: [Item]) {
    guard deduplicatesByID else {
      items.append(contentsOf: newItems)
      return
    }
    for item in newItems where seenIDs.insert(item.id).inserted {
      items.append(item)
    }
  }

  nonisolated static func describe(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
      return description
    }
    return (error as NSError).localizedDescription
  }
}
