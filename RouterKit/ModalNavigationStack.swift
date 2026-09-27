//
//  ModalNavigationStack.swift
//  RouterKit
//
//  Mirrors IceCubesApp's `NavigationSheet` + `CloseToolbarItem`
//  (`IceCubesApp/App/Tabs/NavigationSheet.swift`,
//  `Packages/DesignSystem/Sources/DesignSystem/ToolbarItem/CloseToolbarItem.swift`).
//
//  IceCubesApp pushes flows *inside* a sheet instead of stacking sheets on top
//  of each other: the sheet owns a `NavigationStack`, a close button dismisses
//  the whole modal, and the back button of the stack is provided by SwiftUI.
//

import SwiftUI

/// A `NavigationStack` designed to live inside a sheet.
///
/// 与 IceCubesApp 的 `NavigationSheet` 等价：**没有 path 绑定**，因此只能靠
/// `NavigationLink(value:)` 或 `NavigationLink(destination:)` 进入下一页，
/// 程序化 push（`router.navigate(to:)`）需要改用 modal 形态的 `RouterHost`：
///
/// ```swift
/// // 只需展示 + 关闭按钮：
/// ModalNavigationStack(title: "About") { AboutView() }
///
/// // 需要在 sheet 内 push 页面：
/// RouterHost(router: sheetRouter, title: "Flow", showsDismissButton: true) { ... }
/// ```
///
/// 内容自适应高度用 `contentSized: true`。
@MainActor
public struct ModalNavigationStack<Content: View>: View {
  /// inline 导航栏在 sheet 里的高度，用于内容自适应时补足 chrome。
  public static var inlineNavigationBarHeight: CGFloat { 44 }

  private let title: String?
  private let showsDismissButton: Bool
  private let contentSized: Bool
  private let content: Content

  public init(
    title: String? = nil,
    showsDismissButton: Bool = true,
    /// 为 `true` 时内容高度决定 sheet 高度（`ContentSizedSheet` + 导航栏补偿）。
    contentSized: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.showsDismissButton = showsDismissButton
    self.contentSized = contentSized
    self.content = content()
  }

  public var body: some View {
    NavigationStack {
      sizedContent
        .navigationTitle(title ?? "")
        // sheet 常常很矮，大标题会压住内容，所以 modal 里固定用 inline 标题。
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          if showsDismissButton {
            DismissToolbarItem()
          }
        }
    }
  }

  /// 内容自适应时不能把整棵 `NavigationStack` 交给 `ContentSizedSheet`：
  /// 导航栈是贪婪容器，`fixedSize` 会让它塌成空白。所以只测量内容，再补上导航栏高度。
  @ViewBuilder private var sizedContent: some View {
    if contentSized {
      content.contentSizedSheet(extraHeight: Self.inlineNavigationBarHeight)
    } else {
      content
    }
  }
}

/// The `xmark.circle` leading toolbar button used by every modal in
/// IceCubesApp to close the sheet it lives in.
public struct DismissToolbarItem: ToolbarContent {
  @Environment(\.dismiss) private var dismiss

  public init() {}

  public var body: some ToolbarContent {
    ToolbarItem(placement: .navigationBarLeading) {
      Button(
        action: { dismiss() },
        label: { Image(systemName: "xmark.circle") })
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Close")
    }
  }
}
