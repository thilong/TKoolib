//
//  WaterfallDistribution.swift
//  ListKit
//
//  瀑布流的列分配算法（纯函数，可单测）。
//
//  列分配策略：每个元素放进当前**最矮**的那一列（shortest-column-first），
//  列高差最小，代价是严格阅读顺序会被打散 —— 这是瀑布流的经典取舍。
//
//  只算「谁在哪一列」，不算 frame：懒加载瀑布流把每一列交给一个独立的 `LazyVStack`
//  （见 `LazyWaterfallListView`），列内位置由 `LazyVStack` 自己排，
//  所以不需要绝对坐标，也就不需要 `Layout`（`Layout` 要求先量出所有 subview 的高度，
//  意味着元素会被全部实例化，做不到懒加载）。
//

import CoreGraphics

public enum WaterfallDistribution {
  /// 把元素按下标分配进 `columns` 列，返回每列的元素下标（列内保持原有顺序）。
  ///
  /// - Parameters:
  ///   - itemHeights: 每个元素在列宽下的高度（由数据提供，不需要渲染元素）
  ///   - columns: 列数（`<= 0` 会被夹到 1）
  ///   - rowSpacing: 同列内元素间距。只在「列高累计」时参与，用来决定下一个元素进哪一列
  public static func columnAssignments(
    itemHeights: [CGFloat],
    columns: Int,
    rowSpacing: CGFloat = 0
  ) -> [[Int]] {
    let columnCount = max(1, columns)
    var columnHeights = [CGFloat](repeating: 0, count: columnCount)
    var buckets = [[Int]](repeating: [], count: columnCount)

    for (index, height) in itemHeights.enumerated() {
      // 最矮的一列；并列时取最左边，保证结果稳定、可断言。
      var target = 0
      for index in 1..<columnCount where columnHeights[index] < columnHeights[target] {
        target = index
      }
      buckets[target].append(index)
      columnHeights[target] += max(0, height) + rowSpacing
    }

    return buckets
  }
}
