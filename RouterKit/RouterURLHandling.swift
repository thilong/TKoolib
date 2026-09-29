//
//  RouterURLHandling.swift
//  RouterKit
//
//  IceCubesApp funnels every link through `SafariRouter`
//  (`IceCubesApp/App/Router/SafariRouter.swift`): it installs an `OpenURLAction`
//  in the environment and forwards `onOpenURL` deep links to `RouterPath`.
//
//  RouterKit keeps the same shape but hands back an `Equatable` result so the
//  behaviour is unit testable (`OpenURLAction.Result` itself is not `Equatable`).
//

import SwiftUI

/// The outcome of `RouterPath.handle(url:)`.
public enum URLHandlingResult: Equatable, Sendable {
  /// The router claimed the URL and pushed a route.
  case handled
  /// The URL is explicitly ignored.
  case discarded
  /// The router does not care about the URL; let the system open it.
  case systemAction

  public var openURLActionResult: OpenURLAction.Result {
    switch self {
    case .handled: .handled
    case .discarded: .discarded
    case .systemAction: .systemAction
    }
  }
}

extension URLHandlingResult: CustomStringConvertible {
  public var description: String {
    switch self {
    case .handled: "handled"
    case .discarded: "discarded"
    case .systemAction: "systemAction"
    }
  }
}

public extension View {
  /// 处理 **Universal Link**（`https://<你的域名>/...`）。
  ///
  /// 与 `onOpenURL`（自定义 scheme）共用同一个 `RouterPath.handle(url:)`：
  /// 先经过 `router.routeResolver`，命中则 push，否则走 `router.urlHandler`，
  /// 再否则原样交回系统（Safari）。
  ///
  /// - Parameters:
  ///   - router: 目标路由器（通常与 `RouterHost` 用的是同一个实例）
  ///   - allowedHosts: 只处理这些域名的链接；传 `nil` 表示不限制。
  ///     建议显式传入自己的域名，避免把任意 https 链接都当成深链。
  ///
  /// 使用前提（App 侧，缺一不可）：
  /// 1. Associated Domains 能力里配置 `applinks:<你的域名>`；
  /// 2. 该域名根目录提供 `apple-app-site-association`（AASA）；
  /// 3. 通过 `router.routeResolver` 注册 URL → Route 的解析规则。
  ///
  /// ```swift
  /// RouterHost(router: router) { RootView() } route: { … } sheet: { … }
  ///   .withUniversalLinkHandling(router, allowedHosts: ["example.com"])
  /// ```
  ///
  /// SwiftUI 生命周期下由 `onContinueUserActivity` 接收；
  /// UIKit 生命周期（`scene(_:continue:)`）需自行把 `webpageURL` 交给同一个 `handle(url:)`。
  func withUniversalLinkHandling<Route: RouteDestination, Sheet: SheetDestination>(
    _ router: RouterPath<Route, Sheet>,
    allowedHosts: Set<String>? = nil
  ) -> some View {
    onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
      guard let url = activity.webpageURL else { return }
      if let allowedHosts {
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else { return }
      }
      _ = router.handle(url: url)
    }
  }

  /// Routes every link opened inside this view through the router, and feeds
  /// `onOpenURL` deep links to it as well.
  ///
  /// ```swift
  /// RouterHost(router: router) { ... }
  ///   .withRouterURLHandling(router)
  /// ```
  func withRouterURLHandling<Route: RouteDestination, Sheet: SheetDestination>(
    _ router: RouterPath<Route, Sheet>
  ) -> some View {
    environment(
      \.openURL,
      OpenURLAction { url in
        router.handle(url: url).openURLActionResult
      }
    )
    .onOpenURL { url in
      _ = router.handle(url: url)
    }
  }
}
