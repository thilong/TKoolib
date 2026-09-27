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
