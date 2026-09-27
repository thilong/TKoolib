//
//  RouterHost.swift
//  RouterKit
//
//  The view layer of RouterKit. IceCubesApp spreads this over
//  `NavigationTab` (the `NavigationStack`), `withAppRouter()`
//  (`navigationDestination(for:)`) and `withSheetDestinations(sheetDestinations:routerPath:)`
//  (`.sheet(item:)`). RouterKit folds those three pieces into one host view plus
//  an optional modifier for the cases where the stack already exists.
//

import SwiftUI

/// Hosts a `NavigationStack` driven by a `RouterPath`, and resolves pushed
/// routes and presented sheets through two `@ViewBuilder` closures.
///
/// ```swift
/// @State private var router = RouterPath<AppRoute, AppSheet>()
///
/// RouterHost(router: router) {
///   ContentView()
/// } route: { route in
///   switch route {
///   case .number(let value): NumberView(value: value)
///   ...
///   }
/// } sheet: { sheet in
///   switch sheet {
///   case .composer(let mode): ComposerView(mode: mode)
///   ...
///   }
/// }
/// ```
///
/// The router is installed into the environment, so any descendant — including
/// sheet content — can call `router.navigate(to:)` or `router.present(_:)`.
///
/// 同一个类型也可以直接放进 sheet：此时它就是「sheet 内那套导航栈」，
/// 传 `title` 会显示 inline 标题，传 `showsDismissButton: true` 会在左上角显示关闭按钮。
/// 因为 path 是绑定的，`router.navigate(to:)` 在 sheet 里同样能 push 页面。
@MainActor
public struct RouterHost<
  Route: RouteDestination,
  Sheet: SheetDestination,
  Content: View
>: View {
  @Bindable private var router: RouterPath<Route, Sheet>

  private let title: String?
  private let showsDismissButton: Bool
  private let content: Content
  private let routeBuilder: (Route) -> AnyView
  private let sheetBuilder: (Sheet) -> AnyView

  public init<RouteContent: View, SheetContent: View>(
    router: RouterPath<Route, Sheet>,
    /// 仅 modal 形态需要：显示 inline 标题。
    title: String? = nil,
    /// 仅 modal 形态需要：左上角关闭按钮（走 `@Environment(\.dismiss)`）。
    showsDismissButton: Bool = false,
    @ViewBuilder content: () -> Content,
    @ViewBuilder route: @escaping (Route) -> RouteContent,
    @ViewBuilder sheet: @escaping (Sheet) -> SheetContent
  ) {
    self.router = router
    self.title = title
    self.showsDismissButton = showsDismissButton
    self.content = content()
    self.routeBuilder = { AnyView(route($0)) }
    self.sheetBuilder = { AnyView(sheet($0)) }
  }

  public var body: some View {
    NavigationStack(path: $router.path) {
      content
        .navigationDestination(for: Route.self) { route in
          routeBuilder(route)
        }
        .modifier(ModalChrome(title: title, showsDismissButton: showsDismissButton))
    }
    .sheet(item: $router.presentedSheet) { sheet in
      sheetBuilder(sheet)
        .environment(router)
    }
    .environment(router)
  }
}

/// modal 形态的标题与关闭按钮；App 级用法（`title == nil`）不加任何东西，
/// 以免覆盖页面自己的 `navigationTitle`。
@MainActor
private struct ModalChrome: ViewModifier {
  let title: String?
  let showsDismissButton: Bool

  func body(content: Content) -> some View {
    if let title {
      content
        .navigationTitle(title)
        // sheet 常常很矮，大标题会压住内容，所以 modal 里固定用 inline 标题。
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          if showsDismissButton {
            DismissToolbarItem()
          }
        }
    } else {
      content
        .toolbar {
          if showsDismissButton {
            DismissToolbarItem()
          }
        }
    }
  }
}

// MARK: - Destinations without a stack

/// Adds the route / sheet registry to an existing `NavigationStack`.
///
/// Use this when the stack is created elsewhere — typically inside a sheet.
///
/// ⚠️ 它**只注册 destination 与 sheet，不绑定 path**：因此 `NavigationLink(value:)`
/// 能正常 push，但 `router.navigate(to:)` 这类程序化 push 不会生效
/// （与 IceCubesApp 原 `NavigationSheet` 的行为一致）。
/// 需要在 sheet 里程序化 push，请用 modal 形态的 `RouterHost`：
///
/// ```swift
/// RouterHost(router: sheetRouter, title: "Flow", showsDismissButton: true) {
///   RootView()
/// } route: { route in
///   RouteView(route: route)
/// } sheet: { sheet in
///   SheetView(sheet: sheet)
/// }
/// ```
public extension View {
  func withRouterDestinations<
    Route: RouteDestination,
    Sheet: SheetDestination,
    RouteContent: View,
    SheetContent: View
  >(
    router: RouterPath<Route, Sheet>,
    @ViewBuilder route: @escaping (Route) -> RouteContent,
    @ViewBuilder sheet: @escaping (Sheet) -> SheetContent
  ) -> some View {
    modifier(
      RouterDestinationsModifier(
        router: router,
        route: route,
        sheet: sheet))
  }
}

@MainActor
private struct RouterDestinationsModifier<
  Route: RouteDestination,
  Sheet: SheetDestination,
  RouteContent: View,
  SheetContent: View
>: ViewModifier {
  @Bindable var router: RouterPath<Route, Sheet>

  let route: (Route) -> RouteContent
  let sheet: (Sheet) -> SheetContent

  func body(content: Content) -> some View {
    content
      .navigationDestination(for: Route.self) { route in
        self.route(route)
      }
      .sheet(item: $router.presentedSheet) { sheet in
        self.sheet(sheet)
          .environment(router)
      }
      .environment(router)
  }
}
