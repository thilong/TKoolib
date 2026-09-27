//
//  TKoolibApp.swift
//  TKoolib
//
//  Created by aidoo on 2026/9/27.
//

import SwiftUI

@main struct TKoolibApp: App {
  /// One app wide router, the RouterKit equivalent of IceCubesApp's
  /// `@State var appRouterPath = RouterPath()` in `IceCubesApp.swift`.
  @State private var router = RouterPath<AppRoute, AppSheet>(
    routeResolver: AppURLRouteResolver(),
    urlHandler: { _ in .systemAction })

  var body: some Scene {
    WindowGroup {
      RouterHost(router: router) {
        ContentView()
      } route: { route in
        AppRouteView(route: route)
      } sheet: { sheet in
        AppSheetView(sheet: sheet)
      }
      .withRouterURLHandling(router)
      .task { DemoLaunchOptions.apply(to: router) }
    }
  }
}
