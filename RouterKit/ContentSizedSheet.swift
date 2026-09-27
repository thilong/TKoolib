//
//  ContentSizedSheet.swift
//  RouterKit
//
//  Sheet 高度跟随内容。
//
//  IceCubesApp 里的对应实现是 `AppAccountsSelectorView`：它**手算**高度
//  （`360 + 60 * 账号数`）再喂给 `.presentationDetents([.height(...), .large])`：
//
//      private var preferredHeight: CGFloat {
//        var baseHeight: CGFloat = 360
//        baseHeight += CGFloat(60 * accountsViewModel.count)
//        return baseHeight
//      }
//
//  手算的缺点是内容一改（本地化、动态字体、行高变化）就要重新调参数。
//  RouterKit 的做法是真正测量内容高度，再驱动自定义 detent。
//

import SwiftUI

/// 纯函数的高度计算，便于单测。
public enum SheetHeight {
  /// 把测量到的高度收敛到 `[minimum, maximum]`。
  ///
  /// * 非有限值（NaN / infinity）或非正数 → 视为「还没测到」，返回 `minimum`
  /// * 小于 `minimum` → `minimum`
  /// * 大于 `maximum` → `maximum`
  public static func clamp(
    _ measured: CGFloat,
    minimum: CGFloat = 0,
    maximum: CGFloat? = nil
  ) -> CGFloat {
    var height = measured.isFinite && measured > 0 ? measured : minimum
    if height < minimum { height = minimum }
    if let maximum, height > maximum { height = maximum }
    return height
  }
}

/// 让 sheet 的高度由内容决定。
///
/// ```swift
/// case .emojiPicker:
///   ContentSizedSheet { EmojiPickerList() }     // 高度 = 内容高度
/// ```
///
/// 实现要点：
/// 1. `fixedSize(horizontal: false, vertical: true)` 让内容忽略 sheet 给出的高度，
///    按自身理想高度布局，这样测到的才是内容高度而不是 sheet 高度；
/// 2. `onGeometryChange` 观测该高度；
/// 3. `.presentationDetents([.height(测量值), .large])` 把它变成 detent，
///    保留 `.large` 让超长内容仍可上拖展开（与 IceCubesApp 的 `[.height, .large]` 一致）。
///
/// 注意：`List` / `ScrollView` 这类「贪婪」容器没有稳定的理想高度，
/// 请用栈式内容（`VStack`、固定行数的 `Form`），或改用
/// `.presentationSizing(.fitted)`（iOS 18+，见 RouterKit.md §4.6）。
@MainActor
public struct ContentSizedSheet<Content: View>: View {
  private let minimumHeight: CGFloat
  private let maximumHeight: CGFloat?
  private let extraHeight: CGFloat
  private let allowsExpansion: Bool
  private let showsDragIndicator: Bool
  private let fallbackHeight: CGFloat
  private let content: Content

  @State private var measuredHeight: CGFloat = 0


  public init(
    minimumHeight: CGFloat = 0,
    maximumHeight: CGFloat? = nil,
    /// 测量内容之外的额外高度。
    ///
    /// 推荐把整棵 modal（含 `ModalNavigationStack`）交给 `ContentSizedSheet`，
    /// 这样导航栏高度也会被量进去，`extraHeight` 保持 0；
    /// 只有必须把 `ContentSizedSheet` 放在导航栈内部时才需要手动补导航栏高度。
    extraHeight: CGFloat = 0,
    allowsExpansion: Bool = true,
    showsDragIndicator: Bool = true,
    /// 首帧测量完成前使用的 detent 高度，避免 sheet 从 0 高度长出来。
    fallbackHeight: CGFloat = 320,
    @ViewBuilder content: () -> Content
  ) {
    self.minimumHeight = minimumHeight
    self.maximumHeight = maximumHeight
    self.extraHeight = extraHeight
    self.allowsExpansion = allowsExpansion
    self.showsDragIndicator = showsDragIndicator
    self.fallbackHeight = fallbackHeight
    self.content = content()
  }

  public var body: some View {
    content
      .fixedSize(horizontal: false, vertical: true)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.height
      } action: { height in
        measuredHeight = height
      }
      .presentationDetents(detents)
      .presentationDragIndicator(showsDragIndicator ? .visible : .hidden)
  }

  var detents: Set<PresentationDetent> {
    let height = SheetHeight.clamp(
      measuredHeight > 0 ? measuredHeight + extraHeight : fallbackHeight + extraHeight,
      minimum: minimumHeight,
      maximum: maximumHeight)
    var detents: Set<PresentationDetent> = [.height(height)]
    if allowsExpansion {
      detents.insert(.large)
    }
    return detents
  }
}

public extension View {
  /// 等价于把内容包一层 `ContentSizedSheet`，用于已经在 sheet 里的内容。
  func contentSizedSheet(
    minimumHeight: CGFloat = 0,
    maximumHeight: CGFloat? = nil,
    extraHeight: CGFloat = 0,
    allowsExpansion: Bool = true,
    showsDragIndicator: Bool = true,
    fallbackHeight: CGFloat = 320
  ) -> some View {
    ContentSizedSheet(
      minimumHeight: minimumHeight,
      maximumHeight: maximumHeight,
      extraHeight: extraHeight,
      allowsExpansion: allowsExpansion,
      showsDragIndicator: showsDragIndicator,
      fallbackHeight: fallbackHeight
    ) {
      self
    }
  }
}
