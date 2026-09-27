//
//  DemoLaunchOptions.swift
//  RouterKit demo
//
//  Lets the demo be driven from the command line so the routing / sheet wiring
//  can be smoke tested (and screenshotted) without tapping:
//
//    xcrun simctl launch booted devplaceholder.JC490GPK.SwiftUITestProject -demo=sheet
//
import Foundation

enum DemoLaunchOptions {
  /// 截图 / 冒烟专用：内容自适应 sheet 出现后自动点一次 Add row。
  ///
  /// 自动化环境里没法真的点击，用这个开关走**和 Add row 按钮完全相同的 `@State` 路径**，
  /// 用来验证「本地状态变化 → 行数变化 → sheet 高度跟着变」。
  static var autoAddRowDelay: Duration?

  /// 截图 / 冒烟专用：ListKit demo 的初始模式与列数。
  static var listKitMode: ListKitDemoMode?
  static var listKitColumns: Int?

  /// 截图 / UI 测试专用：启动后自动做一次本地移除。
  static var autoRemoveCount: Int?
  static var autoRemoveFirstItem = false
  static var autoRemoveDelay: Duration = .seconds(6)

  @MainActor
  static func apply(to router: RouterPath<AppRoute, AppSheet>) {
    for argument in ProcessInfo.processInfo.arguments {
      switch argument {
      case "-demo=sheet":
        router.present(.composer(mode: .new))
      case "-demo=sheet-reply":
        router.present(.composer(mode: .reply(toStatusId: "1010384")))
      case "-demo=sheet-settings":
        router.present(.settings)
      case "-demo=sheet-sized":
        router.present(.contentSizedSheet(rows: 4))
      case "-demo=sheet-sized-8":
        router.present(.contentSizedSheet(rows: 8))
      case "-demo=sheet-sized-resize":
        // 反例复现：sheet 已打开（4 行）后，把 presentedSheet 换成同 id、不同 payload
        // 的 8 行 —— 结果仍是 4 行，证明「同 id 换 payload 刷不动已打开的 sheet 内容」。
        router.present(.contentSizedSheet(rows: 4))
        Task { @MainActor in
          try? await Task.sleep(for: .seconds(2))
          router.present(.contentSizedSheet(rows: 8))
        }
      case "-demo=sheet-sized-autogrow":
        // 正例：走和 Add row 按钮相同的 @State 路径，验证 sheet 会跟着变高。
        autoAddRowDelay = .seconds(2)
        router.present(.contentSizedSheet(rows: 4))
      case "-demo=sheet-bare":
        router.present(.bareContentSizedSheet)
      case "-demo=sheet-native":
        router.present(.nativeFittedSheet)
      case "-demo=sheet-native-list":
        router.present(.nativeFittedListSheet)
      case "-demo=sheet-nav":
        router.present(.navigationInSheet(initialPath: []))
      case "-demo=sheet-nav-deep":
        router.present(.navigationInSheet(initialPath: [.page(2), .page(3)]))
      case "-demo=push":
        router.navigate(to: [.number(1), .statusDetail(id: "1010384")])
      case "-demo=deeplink":
        _ = router.handle(url: URL(string: "https://mastodon.social/status/1010384")!)
      case "-demo=listkit-lazy":
        listKitMode = .lazyList
        router.navigate(to: .listKitDemo)
      case "-demo=listkit-waterfall", "-demo=listkit-waterfall-lazy":
        listKitMode = .lazyWaterfall
        listKitColumns = 2
        router.navigate(to: .listKitDemo)
      case "-demo=listkit-waterfall-3", "-demo=listkit-waterfall-lazy-3":
        listKitMode = .lazyWaterfall
        listKitColumns = 3
        router.navigate(to: .listKitDemo)
      case "-demo=listkit-waterfall-4":
        listKitMode = .lazyWaterfall
        listKitColumns = 4
        router.navigate(to: .listKitDemo)
      case "-demo=listkit-waterfall-lazy-churn":
        // 随机移除 5 个（固定种子）—— 验证移除后列表仍然正确、还能继续分页
        listKitMode = .lazyWaterfall
        listKitColumns = 2
        autoRemoveCount = 5
        router.navigate(to: .listKitDemo)
      case "-demo=listkit-waterfall-lazy-dropfirst":
        // 只移除第一个元素 —— 专门用来暴露「下标当身份」的状态错位
        listKitMode = .lazyWaterfall
        listKitColumns = 2
        autoRemoveFirstItem = true
        router.navigate(to: .listKitDemo)
      default:
        continue
      }
    }
  }
}
