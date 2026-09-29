# ListKit — 懒加载分页列表 + 懒加载瀑布流

`SwiftUITestProject/SwiftUITestProject/ListKit/`，和 `RouterKit` 同规格：纯 SwiftUI、
`public` API、不依赖任何第三方库、自带单测与 UI 测试，目录结构可直接搬成 SwiftPM target。

| 组件 | 说明 |
| --- | --- |
| `PagedListView` | 单列懒加载列表：下拉刷新、上拉加载更多、自定义 cell；两种外观（原生 `List` / `ScrollView + LazyVStack`） |
| `LazyWaterfallListView` | 懒加载瀑布流：自定义列数、元素不等高、列数可动态调整、下拉刷新、上拉加载更多；**只实例化可见元素** |
| `PagedListModel` | 上面两个组件共用的分页状态机（含本地增删） |
| `WaterfallDistribution` | 瀑布流列分配算法（纯函数，可单测） |

```
ListKit/
├── PagedListModel.swift        # 分页状态机（首屏 / 刷新 / 加载更多 / 重试 / 并发护栏 / 本地增删）
├── PagedListView.swift         # 单列列表 + 底部加载哨兵 + 首屏占位
├── LazyWaterfallListView.swift # 懒加载瀑布流（每列一个 LazyVStack）
└── WaterfallDistribution.swift # 列分配算法（纯函数）
```

> 这里**没有** `Layout` 版的瀑布流：`Layout` 必须先量出所有 subview 的高度才能摆放，
> 意味着元素会被全部实例化，做不到懒加载，所以不提供这个实现。

---

## 1. 快速上手

### 1.1 懒加载列表

```swift
@State private var model = PagedListModel<Post>(pageSize: 20) { offset, limit in
  let page = try await api.posts(offset: offset, limit: limit)
  return PagedResponse(items: page.items, hasMore: page.hasMore)
}

PagedListView(model: model, style: .list) { post in
  PostRow(post: post)            // 自定义 cell
}
```

组件内部已经接好：`.refreshable`（下拉刷新）、footer 哨兵（上拉加载更多）、
首屏 loading / 失败重试 / 空态占位。

### 1.2 懒加载瀑布流

```swift
@State private var columns = 2

LazyWaterfallListView(
  model: model,
  columns: columns,
  spacing: 12,
  itemHeight: { item, columnWidth in columnWidth / item.aspectRatio }   // 列宽 -> 高度
) { item in
  PhotoCard(item: item)          // 会被裁剪到给定尺寸
}

// 动态改列数（放进 withAnimation 会平滑重排）
Button("3 列") { withAnimation(.snappy) { columns = 3 } }
```

### 1.3 数据源

数据源就是一个闭包 `(offset, limit) async throws -> PagedResponse<Item>`：

```swift
public struct PagedResponse<Item> {
  public var items: [Item]
  public var hasMore: Bool     // 显式返回，别用「本页数量 < limit」去猜
}
```

网络、数据库、内存数组都行；测试里换成替身即可离线确定性跑完。

---

## 2. `PagedListModel` 状态机

```swift
public private(set) var items: [Item]
public private(set) var phase: PagedPhase                  // idle / loadingFirstPage / loaded / failed
public private(set) var loadMorePhase: PagedLoadMorePhase  // idle / loading / failed / exhausted
public var pageSize: Int
public var deduplicatesByID: Bool

func loadInitialIfNeeded() async   // 幂等，可直接挂 .task
func refresh() async               // 下拉刷新：重置 offset 并整体替换
func retryInitialLoad() async      // 首屏失败后的重试
func loadMore() async              // 上拉加载更多（重复调用安全）
func retryLoadMore() async         // footer 上的重试
func reset()                       // 回到初始状态

func remove(_ id: Item.ID)         // 本地移除（见 2.2）
func remove(at offsets: IndexSet)
func removeAll(where: (Item) -> Bool)
```

### 2.1 设计细节（都有单测）

* **并发护栏**：`loadMore()` 在已有请求在飞时直接返回，快速滚动 / 多次触发只发一次请求；
* **offset 语义**：`nextOffset` 累加的是「服务端返回的条数」，不是 `items.count`，
  所以本地去重/删除不会打乱分页游标；`refresh()` 会把 offset 归零；
* **取消不算失败**：滚出屏幕导致的 `CancellationError` 静默回退到 `.idle`，不会污染 UI；
* **下拉刷新失败保留旧数据**：只在本来就没数据时才进入 `.failed`；
* **到底了** → `loadMorePhase == .exhausted`，footer 显示「没有更多了」。

### 2.2 本地增删

`insert(_:at:)` / `insert(contentsOf:at:)` / `replace(_:)` / `remove(_:)` / `remove(at:)` / `removeAll(where:)`
都只动本地数组，**不改分页游标**（插入/删除都不应该让下一页跳过一条）；`deduplicatesByID` 打开时
`insert` 遇到同 id 会就地替换，不会产生重复行。

`remove(_:)` / `remove(at:)` / `removeAll(where:)` 只动本地数组，**不改分页游标** ——
游标记的是「服务端已经取到第几条」，本地删掉一条不应该让下一页跳过一条（有单测固定）。

注意：本地移除**不会通知服务端**。被移除的元素如果服务端没删，之后仍可能从后续页面回来，
下拉刷新一定会回来。要真正删除请先调服务端接口再 `refresh()`。

---

## 3. 懒加载瀑布流

`LazyWaterfallListView` 的实现参照 `samples/LazyWaterfallGrid.swift`：
**每一列是一个独立的 `LazyVStack`，并排放在 `HStack` 里**。

```swift
ScrollView {
  HStack(alignment: .top, spacing: spacing) {     // 列
    ForEach(columns) { column in
      LazyVStack(spacing: spacing) {              // 每列自己懒加载
        ForEach(column) { item in
          cell(item)
            .frame(width: columnWidth, height: itemHeight(item, columnWidth))
            .clipped()
        }
      }
    }
  }
}
```

高度由数据提供 → 列分配可以纯计算（不渲染任何元素）→ 每列交给系统懒容器。
比"自己切波段 + 绝对定位"简单得多：不需要波段、不需要 `.offset`、也没有对齐陷阱。

与 sample 的差异：容器宽度自己测（sample 要求调用方传 `mainWidth`，还要在 macOS 上手减
滚动条宽度）；接上了 `PagedListModel`（下拉刷新 / 上拉加载更多 / 失败重试 / 占位态）；
上拉触发放在每列「最后一个元素」的 `onAppear` 上。

### 3.1 列分配算法

```swift
WaterfallDistribution.columnAssignments(itemHeights: [CGFloat], columns: Int, rowSpacing: CGFloat = 0)
  -> [[Int]]        // 每列的元素下标，列内保持数据顺序
```

* 每个元素放进当前**最矮**的那一列（shortest-column-first），列高差最小；
* 并列时取最左列，保证结果稳定、可断言；
* **追加稳定**：按顺序贪心，末尾追加不影响之前的选择（单测固定）；
* **删除会重排**：剩下的元素重新均衡列高（见 3.4）。

### 3.2 动态列数

`columns` 就是 `HStack` 里 `LazyVStack` 的个数，运行时改即可重排；放进 `withAnimation` 会有过渡。

| 2 列 | 3 列 | 4 列 |
| --- | --- | --- |
| ![](Screenshots/13-waterfall-lazy-2-columns.png) | ![](Screenshots/14-waterfall-lazy-3-columns.png) | ![](Screenshots/15-waterfall-lazy-4-columns.png) |

### 3.3 懒加载实测

Demo 顶部有两个计数器：

* **在层级**：当前仍在视图层级里的元素数（`onAppear` 加入、`onDisappear` 移除）；
* **累计**：曾经出现过（`onAppear`）的元素数。

2 列时 12 项里只有 **7 个**在层级（上图），4 列时 24 项里 **13 个** —— 只创建可见元素。
列表越长差距越大（「累计」最终会追上总数，所以「在层级」才是关键指标）。

### 3.4 删除后重排 & cell 状态放在哪

**删除元素后整体重排**（重新均衡列高）是瀑布流的常规语义：后面的元素往上补，甚至换列。
实测删掉首屏的 5 个元素后，Item 1 从右列补到了左列：

| 删除前（12 项，左列 0/2/4/6…、右列 1/3/5…） | 随机删除 5 个后（左列 1/6/10…、右列 2/5/9…） |
| --- | --- |
| ![](Screenshots/19-waterfall-before-removal.png) | ![](Screenshots/20-waterfall-after-removal-reflowed.png) |

两张图的项数不同是因为懒瀑布流会先自动补页，要对比的是剩下元素所在的**列**。

代价：元素换列 = 换了父容器（另一个 `LazyVStack`）= SwiftUI 只能重建这个 cell，
**cell 里的本地 `@State`、动画、正在加载的图片都会丢**。所以：

* `ForEach` 的身份用 **`Item.ID`**（不是下标）—— 同一列内元素平移时不会无谓重建；
* **需要保留的状态不要放在 cell 里**，放到数据层或父视图里按 `Item.ID` 索引。
  Demo 的收藏就是这么做的：`favorites: Set<Int>` 在页面级，cell 只接收
  `isFavorite` + `onToggleFavorite`，所以重排之后心形仍然跟着正确的元素
  （UI 测试 `testRemovalReflowsTheLayoutAndKeepsDataDrivenState` 覆盖）。

### 3.5 上拉加载更多

触发条件放在**每列最后一个元素**的 `onAppear`：`LazyVStack` 里这个时机就是「滚到了这一列底部」，
内容不足一屏时它们一出现就会继续补，不会卡住。用非结构化 `Task` 发请求（原因见 §4 坑 1）。

分页是滚动驱动的，单测覆盖不到，所以用 **UI 测试**（`SwiftUITestProjectUITests`）真的做
swipe 手势验证：滑到底加载下一页、一直加载到 exhausted、**加载更多之后仍然保持懒加载**
（在层级 < 总数）。

---

## 4. 上拉加载更多的触发方式（实测踩坑）

| 组件 | 容器 | 触发方式 |
| --- | --- | --- |
| `PagedListView(style: .list / .scroll)` | 懒（`List` / `LazyVStack`） | footer 的 `.task(id: items.count)`，出现即触发 |
| `LazyWaterfallListView` | 懒（每列 `LazyVStack`） | 每列**最后一个元素**的 `onAppear` |

**坑 1：footer 的 `.task` 被取消会让分页永远卡住**（UI 测试抓到）。
`.task` 会随视图滚出屏幕被取消，快速滑动时 600ms 的请求每次都被打断，
`CancellationError` 被静默吞掉，列表就停在「加载中…」再也分不出页（实测 12 → 12）。
修法：触发点只负责**触发**，用非结构化 `Task { await model.loadMore() }` 发请求，
让请求不受视图生命周期影响（重复触发由 model 的并发护栏拦住）。

**坑 2：每列宽度必须显式给**。`LazyVStack` 里的元素宽度不会自动等分，
要用 `columnWidth = (容器宽 - 两侧 inset - 列间距×(列数-1)) / 列数`
同时约束 cell 与列本身，否则列宽会随内容变化。

---

## 5. Demo

`ContentView` → **ListKit：懒加载 List + 瀑布流 demo**（走 RouterKit 的路由 push）。
Demo 里可以：

* 切换「懒加载 List / 懒瀑布流」；
* 懒加载 List 切换 `List` / `ScrollView` 两种外观；
* 瀑布流动态切换 1~4 列（带重排动画）；
* 顶部实时显示 `项数 · 在层级 · 累计 · 已移除`；
* 每个卡片右上角有收藏心形（演示「状态放数据层」）；
* 右上角菜单：**下一页请求失败**（footer 错误态 + 重试）、**随机移除 5 个**、
  **移除第一个元素**、重置、清空重载。

模拟器启动参数（便于截图 / UI 测试）：

```bash
xcrun simctl launch booted devplaceholder.JC490GPK.SwiftUITestProject -demo=listkit-lazy
# -demo=listkit-waterfall / -demo=listkit-waterfall-3 / -demo=listkit-waterfall-4
# -demo=listkit-waterfall-lazy-churn      # 延迟数秒随机移除 5 个（固定种子）
# -demo=listkit-waterfall-lazy-dropfirst  # 延迟数秒移除第一个元素
```

---

## 6. 测试

```
✔ Test run with 86 tests in 10 suites passed      # 单元测试（含 RouterKit 的 53 个）
✔ Test Case ... 6 passed                          # UI 测试（真实滑动 / 点击）
```

ListKit 相关单元测试（33 个）：

* `PagedListModelTests`（24）— 首屏（幂等、空数据）、加载更多（追加、到底、并发护栏、
  失败重试、取消不算失败、立即重试）、下拉刷新（重置 offset、失败保留旧数据、从 exhausted 恢复）、
  去重开关、`reset()`；本地移除（按 id / IndexSet / 条件过滤、游标不动、随机移除后仍不重不漏）；
* `WaterfallColumnAssignmentTests`（9）— 最矮列优先、并列取最左、每个元素恰好分配一次、
  列高均衡性、列数边界（0 / 负数 / 超过元素数 / 空数据）、追加稳定、
  **删除后重排（元素会换列）**、随机删除后仍是合法划分。

UI 测试（`SwiftUITestProjectUITests/ListKitPaginationUITests`，6 个）：

| 用例 | 断言 |
| --- | --- |
| `testLazyWaterfallLoadsMorePagesWhenScrolledToBottom` | 滑到底 → 项数增长 |
| `testLazyWaterfallKeepsLoadingUntilExhausted` | 反复滑到底 → 加载到 60 项并出现「没有更多了」 |
| `testLazyWaterfallStaysLazyAfterLoadingMore` | 加载更多之后「在层级」仍 < 总数 |
| `testLazyListLoadsMorePagesWhenScrolledToBottom` | 单列懒加载 List 滑到底 → 项数增长 |
| `testRandomRemovalKeepsListConsistentAndStillPaginating` | 随机移除 5 个：被移除的消失、可见元素不重复、移除后仍能分页且保持懒加载 |
| `testRemovalReflowsTheLayoutAndKeepsDataDrivenState` | 删除后重排，数据层持有的收藏状态仍跟着正确的元素 |

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd SwiftUITestProject

# 单元测试
xcodebuild test -project SwiftUITestProject.xcodeproj -scheme SwiftUITestProject \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .derivedData \
  -only-testing:SwiftUITestProjectTests OTHER_SWIFT_FLAGS="-disable-sandbox"

# UI 测试（真实滑动，较慢）
xcodebuild test -project SwiftUITestProject.xcodeproj -scheme SwiftUITestProject \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .derivedData \
  -only-testing:SwiftUITestProjectUITests OTHER_SWIFT_FLAGS="-disable-sandbox"
```

> `OTHER_SWIFT_FLAGS="-disable-sandbox"` 只在受限沙箱下需要（宏插件进程），Xcode 里正常构建不需要。

---

## 7. 已知限制

* 瀑布流**不支持跨列元素**（通栏 header / banner）：每列是独立的 `LazyVStack`，
  塞不进跨列内容；需要的话得换自定义布局（但那样就不懒加载了）；
* 瀑布流的 cell 会被裁剪到 `itemHeight` 给出的尺寸，**高度必须由数据提供**；
  不定高内容（长文本自适应）请用单列的 `PagedListView`；
* 瀑布流**删除 / 重排数据时列会整体重算**（元素可能换列 → 对应 cell 会重建）：
  有意为之（保证列高均衡），代价是 cell 里的本地 `@State` 不可靠，状态请放数据层；
* 懒瀑布流的列高不保证完全均衡：分页是「追加」语义，新元素只补进当时最矮的列；
* 本地移除只动本地数组，不通知服务端（见 2.2）；
* 下拉刷新依赖 `.refreshable`（系统手势），组件只负责把 `refresh()` 接上；
* 去重按 `Item.ID`，需要保留重复项时设 `deduplicatesByID: false`；
* 分页触发是「滚到接近底部即预加载」，没有做「请求失败自动退避重试」，失败后需要用户点重试。
