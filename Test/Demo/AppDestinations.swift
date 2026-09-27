//
//  AppDestinations.swift
//  RouterKit demo
//
//  Application level destinations, modelled after IceCubesApp's
//  `RouterDestination` / `SheetDestination` enums.
//

import Foundation

/// Everything that can be pushed on the app's navigation stack.
enum AppRoute: RouteDestination {
  case number(Int)
  case statusDetail(id: String)
  case accountDetail(id: String)
  case label(String)
  /// ListKit 演示（懒加载 List + 瀑布流）
  case listKitDemo
}

/// The status editor has many flavours in IceCubesApp; they are modelled here
/// with a single payload enum so the demo stays small.
enum ComposeMode: Hashable {
  case new
  case reply(toStatusId: String)
}

/// Everything that can be presented as a sheet.
///
/// Note the custom `==` / `hash(into:)`: like IceCubesApp's `SheetDestination`,
/// equality is *identity* (`id`) based. `.composer(mode: .new)` and
/// `.composer(mode: .reply(toStatusId: "1"))` are therefore considered the same
/// sheet, so swapping one for the other updates the content in place instead of
/// dismissing and re-presenting the modal.
enum AppSheet: SheetDestination {
  case composer(mode: ComposeMode)
  case settings
  case about
  case counter(start: Int)
  /// 内容自适应高度：真测量 + `.presentationDetents(.height(...))`
  case contentSizedSheet(rows: Int)
  /// 内容自适应高度：不带导航栈，高度完全等于内容（无需补 chrome）
  case bareContentSizedSheet
  /// 内容自适应高度：iOS 18+ 原生 `.presentationSizing(.fitted)`
  case nativeFittedSheet
  /// 原生 `.fitted` 用在贪婪容器（List）上的对照实验
  case nativeFittedListSheet
  /// sheet 内部页面 push 演示；`initialPath` 用于直接打开到某一层（截图/深链）
  case navigationInSheet(initialPath: [SheetNavRoute])

  static func == (lhs: AppSheet, rhs: AppSheet) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  var id: String {
    switch self {
    case .composer: "composer"
    case .settings: "settings"
    case .about: "about"
    case .counter: "counter"
    case .contentSizedSheet: "contentSizedSheet"
    case .bareContentSizedSheet: "bareContentSizedSheet"
    case .nativeFittedSheet: "nativeFittedSheet"
    case .nativeFittedListSheet: "nativeFittedListSheet"
    case .navigationInSheet: "navigationInSheet"
    }
  }
}

// MARK: - sheet 内部的页面栈

/// sheet 内导航演示专用路由。
///
/// 它和 App 级的 `AppRoute` 是两套完全独立的类型，因此：
/// * App 级 `RouterPath<AppRoute, AppSheet>` / `RouterHost` 的工作方式完全不变；
/// * sheet 打开时清空自己的栈，也不会影响 App 级栈。
enum SheetNavRoute: RouteDestination {
  case page(Int)
}

/// sheet 内那套 router 自己的 sheet 类型（从被 push 的页面里再弹一个小 sheet）。
enum SheetNavSheet: SheetDestination {
  case confirm

  var id: String { "confirm" }
}

/// A router local to the composer sheet, demonstrating that `RouterPath` can be
/// instantiated per flow instead of globally.
enum ComposerRoute: RouteDestination {
  case preview(text: String)
}

enum ComposerSheet: SheetDestination {
  case emojiPicker

  var id: String { "emojiPicker" }
}
