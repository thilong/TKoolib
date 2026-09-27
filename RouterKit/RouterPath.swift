//
//  RouterPath.swift
//  RouterKit
//
//  A dependency free extraction of the navigation + sheet presentation model
//  used by IceCubesApp (`Packages/Env/Sources/Env/Router.swift`).
//
//  What was kept from the original:
//    * one `@Observable` router object owning both the navigation `path` and the
//      single `presentedSheet`,
//    * a `handle(url:)` entry point that turns inbound URLs into routes and
//      falls back to a system action,
//    * identity based sheet semantics (several destinations can share one `id`,
//      so swapping content does not dismiss / re-present the sheet).
//
//  What was generalised:
//    * the concrete Mastodon `RouterDestination` / `SheetDestination` enums are
//      replaced by two protocols, so one router can be reused per tab, per
//      sheet, or app wide,
//    * the URL -> route mapping moved behind `URLRouteResolver` instead of being
//      hard coded inside the router.
//

import Foundation
import Observation
import SwiftUI

// MARK: - Destinations

/// A value that can be pushed onto a `NavigationStack` path.
public protocol RouteDestination: Hashable {}

/// A value that can be presented as a sheet.
///
/// `id` is the identity SwiftUI uses for the presented sheet. Destinations that
/// share the same `id` are treated as *the same* sheet, which is how IceCubesApp
/// swaps a "new post" editor for a "reply" editor without dismissing and
/// re-presenting the sheet. Conformers opt into that behaviour by implementing
/// `==` and `hash(into:)` from `id` (see `AppSheet` for a worked example).
public protocol SheetDestination: Identifiable, Hashable {}

// MARK: - URL resolving

/// Turns an inbound `URL` into a route.
///
/// IceCubesApp implements this logic inline in `RouterPath.handle(url:)`,
/// `handleDeepLink(url:)` and `handleStatus(status:url:)`, mixing infrastructure
/// concerns (is this a known federated host?) with app routing. Extracting it
/// keeps the router testable and the app specific rules replaceable.
@MainActor
public protocol URLRouteResolver<Route> {
  associatedtype Route: RouteDestination

  /// Returns a route when the URL is meaningful for the app, `nil` otherwise.
  func route(for url: URL) -> Route?
}

/// Closure backed resolver, for call sites that do not need a named type.
@MainActor
public struct ClosureRouteResolver<Route: RouteDestination>: URLRouteResolver {
  private let resolve: (URL) -> Route?

  public init(_ resolve: @escaping (URL) -> Route?) {
    self.resolve = resolve
  }

  public func route(for url: URL) -> Route? {
    resolve(url)
  }
}

// MARK: - Router

/// Owns the navigation stack path and the currently presented sheet.
///
/// Mirrors `RouterPath` from IceCubesApp but is generic over the route and sheet
/// enums, so it can be instantiated app wide *and* per tab / per sheet without
/// collisions in the SwiftUI environment.
@MainActor
@Observable
public final class RouterPath<Route: RouteDestination, Sheet: SheetDestination> {
  /// Pushed navigation destinations, bound to `NavigationStack(path:)`.
  public var path: [Route]

  /// The sheet currently presented, bound to `.sheet(item:)`.
  ///
  /// Setting it to another destination with the same `id` swaps the sheet
  /// content in place; setting it to `nil` dismisses.
  public var presentedSheet: Sheet?

  /// Resolves inbound URLs into routes. Called before `urlHandler`.
  public var routeResolver: (any URLRouteResolver<Route>)?

  /// Last chance handler for URLs the resolver did not claim. IceCubesApp uses
  /// this hook to open links in an in-app Safari or hand them to the system.
  public var urlHandler: (@MainActor (URL) -> URLHandlingResult)?

  public init(
    path: [Route] = [],
    presentedSheet: Sheet? = nil,
    routeResolver: (any URLRouteResolver<Route>)? = nil,
    urlHandler: (@MainActor (URL) -> URLHandlingResult)? = nil
  ) {
    self.path = path
    self.presentedSheet = presentedSheet
    self.routeResolver = routeResolver
    self.urlHandler = urlHandler
  }

  // MARK: Navigation

  /// Pushes a single route, exactly like `RouterPath.navigate(to:)`.
  public func navigate(to route: Route) {
    path.append(route)
  }

  /// Pushes several routes at once (e.g. restoring a deep link chain).
  public func navigate(to routes: [Route]) {
    path.append(contentsOf: routes)
  }

  /// Replaces the whole stack, used when switching account / tab context.
  public func replacePath(with routes: [Route]) {
    path = routes
  }

  @discardableResult
  public func pop() -> Route? {
    guard !path.isEmpty else { return nil }
    return path.removeLast()
  }

  public func popToRoot() {
    path.removeAll()
  }

  /// Pops until `route` is the topmost element. Returns `false` when the route
  /// is not in the stack (the stack is then left untouched).
  @discardableResult
  public func popTo(route: Route) -> Bool {
    guard let index = path.lastIndex(of: route) else { return false }
    path.removeSubrange(path.index(after: index)...)
    return true
  }

  public var isAtRoot: Bool { path.isEmpty }

  public var topRoute: Route? { path.last }

  public var depth: Int { path.count }

  // MARK: Sheets

  /// Presents `sheet`, replacing any sheet already on screen.
  public func present(_ sheet: Sheet) {
    presentedSheet = sheet
  }

  /// Dismisses the current sheet and returns it.
  @discardableResult
  public func dismissSheet() -> Sheet? {
    let dismissed = presentedSheet
    presentedSheet = nil
    return dismissed
  }

  public var isPresentingSheet: Bool { presentedSheet != nil }

  /// True when `sheet` is the currently presented sheet, comparing identity
  /// (i.e. `Sheet.ID`) rather than full equality — this is the check IceCubesApp
  /// effectively relies on when it re-assigns `presentedSheet` from a toolbar.
  public func isPresenting(_ sheet: Sheet) -> Bool {
    presentedSheet?.id == sheet.id
  }

  // MARK: URL handling

  /// Single entry point for `OpenURLAction` / `onOpenURL`.
  ///
  /// 1. ask the resolver for a route and push it,
  /// 2. otherwise delegate to `urlHandler`,
  /// 3. otherwise let the system handle the URL.
  ///
  /// Install it with `.withRouterURLHandling(router)`.
  @discardableResult
  public func handle(url: URL) -> URLHandlingResult {
    if let route = routeResolver?.route(for: url) {
      navigate(to: route)
      return .handled
    }
    return urlHandler?(url) ?? .systemAction
  }
}

