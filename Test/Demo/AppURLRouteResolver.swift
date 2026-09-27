//
//  AppURLRouteResolver.swift
//  RouterKit demo
//
//  Extracted from IceCubesApp's `RouterPath.handle(url:)` /
//  `handleDeepLink(url:)`: those methods mix URL shape matching with network
//  lookups. Here only the shape matching survives, behind `URLRouteResolver`,
//  which makes it unit testable.
//

import Foundation

/// Maps Mastodon-ish URLs of the app's own instance to routes.
struct AppURLRouteResolver: URLRouteResolver {
  /// The instance the signed in account lives on. URLs from other hosts are not
  /// claimed by this resolver.
  var host = "mastodon.social"

  func route(for url: URL) -> AppRoute? {
    guard let urlHost = url.host(), urlHost == host else { return nil }

    let components = url.pathComponents.filter { $0 != "/" }
    guard let first = components.first else { return nil }

    // https://mastodon.social/status/1010384
    if first == "status", components.count >= 2, let id = Int(components[1]) {
      return .statusDetail(id: String(id))
    }

    // https://mastodon.social/tags/swiftui
    if first == "tags", let tag = components.last, components.count >= 2 {
      return .label("#\(tag)")
    }

    // https://mastodon.social/@dimillian
    if first.hasPrefix("@"), first.count > 1 {
      return .accountDetail(id: first)
    }

    return nil
  }
}
