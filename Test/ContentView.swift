import Playgrounds
import SwiftUI

/// The root content hosted by `RouterHost` in `MyApp`.
///
/// Every control below only talks to the router — no `NavigationLink` values, no
/// `.sheet` modifiers — which is exactly the IceCubesApp model: views express
/// intent, `AppRegistry` turns destinations into views.
struct ContentView: View {
  @Environment(RouterPath<AppRoute, AppSheet>.self) private var router

  @State private var lastURLResult = "—"

  var body: some View {
    List {
      Section("Navigation") {
        Button("Push number") { router.navigate(to: .number(1)) }
        Button("Push status 1010384") { router.navigate(to: .statusDetail(id: "1010384")) }
        Button("Push three routes at once") {
          router.navigate(to: [.number(1), .statusDetail(id: "42"), .label("#swiftui")])
        }
        Button("Pop") { router.pop() }
        Button("Pop to root") { router.popToRoot() }
      }

      Section("Sheets") {
        Button("Composer (new)") { router.present(.composer(mode: .new)) }
        Button("Composer (reply mode)") {
          router.present(.composer(mode: .reply(toStatusId: "1010384")))
        }
        Button("Settings") { router.present(.settings) }
        Button("Counter from 5") { router.present(.counter(start: 5)) }
        Button("Dismiss sheet") { router.dismissSheet() }
      }

      Section("内容自适应高度的 Sheet") {
        Button("Content-sized (4 rows)") { router.present(.contentSizedSheet(rows: 4)) }
        Button("Content-sized (8 rows)") { router.present(.contentSizedSheet(rows: 8)) }
        Button("Content-sized (18 rows)") { router.present(.contentSizedSheet(rows: 18)) }
        Button("Content-sized, no nav bar") { router.present(.bareContentSizedSheet) }
        Button("Native .presentationSizing(.fitted)") { router.present(.nativeFittedSheet) }
        Button("Native .fitted + List（对照）") { router.present(.nativeFittedListSheet) }
      }

      Section("ListKit") {
        Button("懒加载 List + 瀑布流 demo") { router.navigate(to: .listKitDemo) }
      }

      Section("Sheet 内页面 push") {
        Button("Sheet with in-sheet push") { router.present(.navigationInSheet(initialPath: [])) }
        Button("Sheet opened at page 3") {
          router.present(.navigationInSheet(initialPath: [.page(2), .page(3)]))
        }
      }

      Section("Deep links") {
        Button("mastodon.social/status/1010384") {
          open("https://mastodon.social/status/1010384")
        }
        Button("mastodon.social/tags/swiftui") {
          open("https://mastodon.social/tags/swiftui")
        }
        Button("mastodon.social/@dimillian") {
          open("https://mastodon.social/@dimillian")
        }
        Button("www.threads.net/@dimillian (not claimed)") {
          open("https://www.threads.net/@dimillian")
        }
        Button("theweb.com/test/test/one (not claimed)") {
          open("https://theweb.com/test/test/one")
        }
      }

      Section("Router state") {
        LabeledContent("path.count", value: "\(router.depth)")
        LabeledContent("path", value: router.path.map(describe).joined(separator: " › "))
        LabeledContent("presentedSheet", value: router.presentedSheet?.id ?? "nil")
        LabeledContent("handle(url:)", value: lastURLResult)
      }
    }
    .navigationTitle("RouterKit")
  }

  private func open(_ string: String) {
    guard let url = URL(string: string) else { return }
    lastURLResult = router.handle(url: url).description
  }

  private func describe(_ route: AppRoute) -> String {
    switch route {
    case .number(let value): "number(\(value))"
    case .statusDetail(let id): "status(\(id))"
    case .accountDetail(let id): "account(\(id))"
    case .label(let text): "label(\(text))"
    case .listKitDemo: "listKit"
    }
  }
}

#Preview {
  RouterHost(router: RouterPath<AppRoute, AppSheet>()) {
    ContentView()
  } route: { route in
    AppRouteView(route: route)
  } sheet: { sheet in
    AppSheetView(sheet: sheet)
  }
}

#Playground {
  _ = 1 + 2
}
