//
//  LazyWaterfallListView.swift
//  ListKit
//
//  懒加载瀑布流（分页版）。
//
//  实现参照 samples/LazyWaterfallGrid：**每一列是一个独立的 `LazyVStack`，并排放在
//  `HStack` 里**。列分配用 shortest-column-first 提前算好（只需要高度，不需要测量视图），
//  于是每个 `LazyVStack` 只在自己滚到可见时才创建元素 —— 天然懒加载，
//  不需要波段、不需要 `.offset` 绝对定位。
//
//  为什么不用 `Layout`：`Layout` 必须在摆放前量出每个 subview 的高度，
//  而「量高度」就意味着 SwiftUI 要把元素全部实例化，所以 `Layout` 天生不可能懒。
//
//  与 sample 的差异：
//  * 容器宽度自己测（sample 要求调用方传 `mainWidth`，还要在 macOS 上手减滚动条宽度）；
//  * 接上 `PagedListModel`：下拉刷新、上拉加载更多、失败重试、空态/首屏占位；
//  * 上拉触发条件放在每列「最后一个元素」的 `onAppear` 上（`LazyVStack` 里这个时机就是可见）。
//    这样做还有个好处：每次追加数据只是把新元素补进各列，之前元素的下标分配不变
//    （shortest-column-first 是按顺序贪心的），已创建的视图不会被打散。
//

import SwiftUI

public struct LazyWaterfallListView<Item: Identifiable, Cell: View>: View {
  private let model: PagedListModel<Item>
  private let columns: Int
  private let spacing: CGFloat
  private let horizontalInset: CGFloat
  private let itemHeight: (Item, CGFloat) -> CGFloat
  private let cell: (Item) -> Cell

  @State private var containerWidth: CGFloat = 0

  /// - Parameters:
  ///   - columns: 列数，运行时可改（放进 `withAnimation` 会平滑重排）
  ///   - spacing: 列间距与列内行距
  ///   - itemHeight: `(元素, 列宽) -> 高度`。由数据提供（例如 `列宽 / 宽高比`），
  ///     不需要先渲染元素，所以列分配可以提前算出来 —— 这是能懒加载的前提。
  ///   - cell: 会被裁剪到给定尺寸（元素高度以 `itemHeight` 为准）。
  public init(
    model: PagedListModel<Item>,
    columns: Int = 2,
    spacing: CGFloat = 12,
    horizontalInset: CGFloat = 16,
    itemHeight: @escaping (Item, CGFloat) -> CGFloat,
    @ViewBuilder cell: @escaping (Item) -> Cell
  ) {
    self.model = model
    self.columns = columns
    self.spacing = spacing
    self.horizontalInset = horizontalInset
    self.itemHeight = itemHeight
    self.cell = cell
  }

  public var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        if columnWidth > 0 {
          HStack(alignment: .top, spacing: spacing) {
            ForEach(columnBuckets.indices, id: \.self) { columnIndex in
              columnView(columnBuckets[columnIndex])
            }
          }
          .padding(.horizontal, horizontalInset)
        }

        // 只负责显示加载/失败/到底状态，触发交给每列最后一个元素的 onAppear。
        LoadMoreFooter(model: model, triggersLoad: false)
      }
    }
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { width in
      containerWidth = width
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
    
  // MARK: 列

  private var columnCount: Int { max(1, columns) }

  private var columnWidth: CGFloat {
    let contentWidth = containerWidth - 2 * horizontalInset
    let totalSpacing = CGFloat(columnCount - 1) * spacing
    return max(0, (contentWidth - totalSpacing) / CGFloat(columnCount))
  }

  /// 每列的元素：**每次都按当前数据重算列分配**。
  ///
  /// 删除元素后整体重排（重新均衡列高）是瀑布流的常规语义 ——
  /// 元素可能因此换列、换父容器，SwiftUI 会重建对应的 cell。
  /// 所以 **cell 里不要放本地 `@State`**：跨列重排会丢；
  /// 需要保留的状态（收藏、展开、草稿…）请放在数据层或父视图里按 `Item.ID` 索引。
  ///
  /// `ForEach` 的**身份是 `Item.ID`**（不是下标）：同一列内元素平移时不会无谓重建。
  private var columnBuckets: [[Item]] {
    guard columnWidth > 0, !model.items.isEmpty else {
      return Array(repeating: [], count: columnCount)
    }

    let assignments = WaterfallDistribution.columnAssignments(
      itemHeights: model.items.map { itemHeight($0, columnWidth) },
      columns: columnCount,
      rowSpacing: 0)

    return assignments.map { bucket in
      bucket.map { index in model.items[index] }
    }
  }

  @ViewBuilder
  private func columnView(_ bucket: [Item]) -> some View {
    LazyVStack(spacing: spacing) {
      ForEach(bucket) { item in
        cell(item)
          .frame(width: columnWidth, height: itemHeight(item, columnWidth))
          .clipped()
          .onAppear {
            // 每列最后一个元素出现 == 已经滚到这一列的底部。
            // 用非结构化 Task 发请求：onAppear 只是触发点，请求不该被视图生命周期影响
            //（重复触发由 model 的并发护栏拦住）。
            guard item.id == bucket.last?.id else { return }
            Task { await model.loadMore() }
          }
      }
    }
    .frame(width: columnWidth)
  }
}
