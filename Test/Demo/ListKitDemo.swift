//
//  ListKitDemo.swift
//  ListKit demo
//
//  演示两个组件：单列懒加载分页列表、瀑布流分页列表。
//  数据源是本地模拟的（带延迟、可注入失败），离线可跑、可截图。
//

import SwiftUI

// MARK: - 数据

struct FeedItem: Identifiable, Hashable {
  let id: Int
  let title: String
  let subtitle: String
  /// 瀑布流卡片里色块的高度 —— 元素不等高的来源。
  let coverHeight: CGFloat
  let tintIndex: Int

  private static let heights: [CGFloat] = [150, 220, 110, 260, 180, 130]
  private static let tints: [Color] = [.blue, .purple, .pink, .orange, .green, .teal]

  static func make(id: Int) -> FeedItem {
    FeedItem(
      id: id,
      title: "Item \(id)",
      subtitle: String(repeating: "ListKit ", count: id % 4 + 1).trimmingCharacters(in: .whitespaces),
      coverHeight: heights[id % heights.count],
      tintIndex: id % tints.count)
  }

  var tint: Color { Self.tints[tintIndex] }
}

@MainActor
@Observable
final class DemoFeedLoader {
  var totalItems = 27
  var latency: Duration = .milliseconds(600)
  /// 打开后，下一次「加载更多」会失败一次，用来演示 footer 的错误 + 重试。
  var failNextPage = false

  private(set) var requestCount = 0

  func load(offset: Int, limit: Int) async throws -> PagedResponse<FeedItem> {
    requestCount += 1

    if latency > .zero {
      try await Task.sleep(for: latency)
    }

    if failNextPage, offset > 0 {
      failNextPage = false
      throw NSError(
        domain: "DemoFeedLoader", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "模拟网络错误，点「重试」继续"])
    }

    let end = min(offset + limit, totalItems)
    let items = offset < end ? (offset..<end).map { FeedItem.make(id: $0) } : []
    return PagedResponse(items: items, hasMore: (end + 1) < totalItems)
  }
}

// MARK: - Cell

/// 单列列表的 cell：不依赖 List 的默认样式，方便看出「自定义 cell」。
struct FeedRowCell: View {
  let item: FeedItem

  var body: some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: 8)
        .fill(item.tint.gradient)
        .frame(width: 52, height: 52)
        .overlay {
          Text("\(item.id)")
            .font(.headline)
            .foregroundStyle(.white)
        }

      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.headline)
        Text(item.subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

/// 懒瀑布流的 cell：必须**填满**给定 frame（高度来自数据，不是自己长出来的）。
///
/// 带一个收藏按钮，但状态**不放在 cell 里** —— 瀑布流删除后会重排，元素可能换列、
/// 换父容器，cell 会被重建，本地 `@State` 会丢。所以收藏状态由父视图按 `Item.ID` 持有，
/// 通过参数传进来（这也是虚拟化 / 会重排的列表里保存状态的标准做法）。
struct LazyFeedWaterfallCell: View {
  let item: FeedItem
  let isFavorite: Bool
  let onToggleFavorite: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      RoundedRectangle(cornerRadius: 10)
        .fill(item.tint.gradient)
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // 色块吃掉剩余高度
        .overlay(alignment: .topLeading) {
          Text("\(item.id)")
            .font(.title3.bold())
            .foregroundStyle(.white.opacity(0.9))
            .padding(10)
        }
        .overlay(alignment: .topTrailing) {
          Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
              .font(.body)
              .foregroundStyle(.white)
              .padding(10)
          }
          .accessibilityIdentifier("listkit.favorite.\(item.id)")
          .accessibilityValue(isFavorite ? "1" : "0")
        }

      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.subheadline.weight(.semibold))
        Text(item.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
    }
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    .contentShape(RoundedRectangle(cornerRadius: 12))
  }
}

/// 可复现的伪随机源（SplitMix64）。
///
/// 「随机移除」这种测试必须可复现，否则会变成偶发失败；固定种子就既能覆盖随机组合，
/// 又能稳定复现。
struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

// MARK: - Demo 页面

enum ListKitDemoMode: String, CaseIterable, Identifiable {
  case lazyList
  case lazyWaterfall

  var id: String { rawValue }

  var title: String {
    switch self {
    case .lazyList: "懒加载 List"
    case .lazyWaterfall: "懒瀑布流"
    }
  }
}

struct ListKitDemoView: View {
  @State private var loader = DemoFeedLoader()
  @State private var lazyModel: PagedListModel<FeedItem>
  @State private var waterfallModel: PagedListModel<FeedItem>
  @State private var mode: ListKitDemoMode
  @State private var listStyle: PagedListStyle = .list
  @State private var columns: Int
  /// 元素实例化情况 —— 直观展示「只创建可见元素」。
  /// * `lazyCreated`: 累计出现过（onAppear）
  /// * `lazyLive`: 当前仍在视图层级里（onAppear 加入、onDisappear 移除）
  @State private var lazyCreated: Set<Int> = []
  @State private var lazyLive: Set<Int> = []
  /// 随机移除用的可复现随机源（固定种子）。
  @State private var churnGenerator = SeededGenerator(seed: 0xC0FF_EE00)
  @State private var didRunLaunchRemoval = false
  /// 本地移除过的元素 id（demo 暴露给 UI 测试断言用）。
  @State private var removedIDs: [Int] = []
  /// 收藏状态：**按 Item.ID 存在父视图里**，不放在 cell 里 —— 瀑布流删除后会重排，
  /// cell 会被重建，本地状态会丢。UI 测试正是用这一点验证「重排之后状态仍然正确」。
  @State private var favorites: Set<Int> = []

  init(mode: ListKitDemoMode? = nil, columns: Int? = nil) {
    let loader = DemoFeedLoader()
    _loader = State(initialValue: loader)
    _lazyModel = State(initialValue: PagedListModel(pageSize: 12, loader: loader.load))
    _waterfallModel = State(initialValue: PagedListModel(pageSize: 12, loader: loader.load))
    _mode = State(initialValue: mode ?? DemoLaunchOptions.listKitMode ?? .lazyList)
    _columns = State(initialValue: columns ?? DemoLaunchOptions.listKitColumns ?? 2)
  }

  var body: some View {
    @Bindable var loader = loader

    VStack(spacing: 0) {
      Picker("模式", selection: $mode) {
        ForEach(ListKitDemoMode.allCases) { demoMode in
          Text(demoMode.title).tag(demoMode)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
      .padding(.vertical, 8)

      switch mode {
      case .lazyList:
        Pager(
          style: $listStyle,
          current: currentPageCount(lazyModel))
        PagedListView(model: lazyModel, style: listStyle) { item in
          FeedRowCell(item: item)
        }
      case .lazyWaterfall:
        columnBar(created: lazyCreated.count, live: lazyLive.count, total: waterfallModel.items.count)
        // 高度由数据给出，每列一个 LazyVStack：只有滚到可见的元素会被创建。
        LazyWaterfallListView(
          model: waterfallModel,
          columns: columns,
          spacing: 12,
          itemHeight: { item, _ in item.coverHeight + 56 }
        ) { item in
          LazyFeedWaterfallCell(
            item: item,
            isFavorite: favorites.contains(item.id),
            onToggleFavorite: { toggleFavorite(item.id) }
          )
          .onAppear { lazyCreated.insert(item.id); lazyLive.insert(item.id) }
          .onDisappear { lazyLive.remove(item.id) }
        }
      }
    }
    .navigationTitle("ListKit")
    .navigationBarTitleDisplayMode(.inline)
    // 截图 / UI 测试用：启动后延迟一段时间自动移除（见 DemoLaunchOptions）。
    .task {
      guard !didRunLaunchRemoval else { return }
      guard DemoLaunchOptions.autoRemoveCount != nil || DemoLaunchOptions.autoRemoveFirstItem else {
        return
      }
      didRunLaunchRemoval = true
      try? await Task.sleep(for: DemoLaunchOptions.autoRemoveDelay)
      if DemoLaunchOptions.autoRemoveFirstItem {
        removeFirstItem()
      }
      if let count = DemoLaunchOptions.autoRemoveCount {
        removeRandom(count)
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Toggle("下一页请求失败", isOn: $loader.failNextPage)
          Button("随机移除 5 个") { removeRandom(5) }
            .accessibilityIdentifier("listkit.removeRandom")
          Button("移除第一个元素") { removeFirstItem() }
            .accessibilityIdentifier("listkit.removeFirst")
          Button("重置两个列表") {
            lazyModel.reset()
            waterfallModel.reset()
          }
          Button("清空并重新加载") {
            Task {
              lazyModel.reset()
              waterfallModel.reset()
              await lazyModel.loadInitialIfNeeded()
              await waterfallModel.loadInitialIfNeeded()
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
  }

  // MARK: 本地移除

  /// 从**已加载**的元素里随机移除若干个（固定种子，可复现）。
  ///
  /// 只在已加载范围内删，这样分页游标的语义才清晰：下一页仍然从服务端的
  /// `nextOffset` 取，不会因为本地删除而跳号。
  private func removeRandom(_ count: Int) {
    var generator = churnGenerator
    let victims = waterfallModel.items.map(\.id).shuffled(using: &generator).prefix(count)
    churnGenerator = generator

    withAnimation(.snappy) {
      for id in victims {
        waterfallModel.remove(id)
        removedIDs.append(id)
      }
    }
  }

  private func removeFirstItem() {
    guard let first = waterfallModel.items.first else { return }
    withAnimation(.snappy) {
      waterfallModel.remove(first.id)
      removedIDs.append(first.id)
    }
  }

  private func toggleFavorite(_ id: Int) {
    if favorites.contains(id) {
      favorites.remove(id)
    } else {
      favorites.insert(id)
    }
  }

  private func columnBar(created: Int, live: Int, total: Int) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "square.grid.2x2")
        .foregroundStyle(.secondary)

      Picker("列数", selection: animatedColumns) {
        ForEach(1...4, id: \.self) { count in
          Text("\(count) 列").tag(count)
        }
      }
      .pickerStyle(.segmented)

      VStack(alignment: .trailing, spacing: 0) {
        Text("\(total) 项")
          .accessibilityIdentifier("listkit.itemCount")

        HStack(spacing: 4) {
          Text("在层级 \(live)")
            .accessibilityIdentifier("listkit.liveCount")
          Text("·")
          Text("累计 \(created)")
            .accessibilityIdentifier("listkit.createdCount")
          Text("·")
          Text("已移除 \(removedIDs.count)")
            .accessibilityIdentifier("listkit.removedCount")
            // value 放被移除的 id 列表，UI 测试据此断言这些元素确实从列表里消失了
            .accessibilityValue(removedIDs.map(String.init).joined(separator: ","))
        }
        .foregroundStyle(live < total ? Color.green : Color.secondary)
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .monospacedDigit()
    }
    .padding(.horizontal)
    .padding(.bottom, 8)
  }

  /// 列数变化放进 `withAnimation`，瀑布流会平滑重排。
  private var animatedColumns: Binding<Int> {
    Binding(
      get: { columns },
      set: { newValue in
        withAnimation(.snappy) { columns = newValue }
      })
  }

  private func currentPageCount(_ model: PagedListModel<FeedItem>) -> Int {
    model.items.count
  }

  /// 单列模式下的样式切换条。
  private struct Pager: View {
    @Binding var style: PagedListStyle
    let current: Int

    var body: some View {
      HStack(spacing: 12) {
        Picker("样式", selection: $style) {
          ForEach(PagedListStyle.allCases) { style in
            Text(style.title).tag(style)
          }
        }
        .pickerStyle(.segmented)

        Text("\(current) 项")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .accessibilityIdentifier("listkit.itemCount")
      }
      .padding(.horizontal)
      .padding(.bottom, 8)
    }
  }
}
