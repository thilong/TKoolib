# RouterKit — 从 IceCubesApp 提取的路由 + Sheet 管理组件

本组件放在 `SwiftUITestProject/SwiftUITestProject/RouterKit/`，是把 IceCubesApp 中
「路由（NavigationStack path）」与「Sheet 展示」的实现拆解、泛化后得到的可复用组件，
并附带一套单元 / 集成测试（`SwiftUITestProjectTests/`）。

---

## 1. 原工程分析：IceCubesApp 是怎么做的

| 文件 | 职责 |
| --- | --- |
| `Packages/Env/Sources/Env/Router.swift` | `@Observable @MainActor class RouterPath`：同时持有 `path: [RouterDestination]` 和 `presentedSheet: SheetDestination?`；`navigate(to:)`、`handle(url:)`、`handleDeepLink(url:)`。同文件定义 `RouterDestination` / `SheetDestination` / `WindowDestinationEditor` / `WindowDestinationMedia`。 |
| `IceCubesApp/App/Router/AppRegistry.swift` | 注册表：`withAppRouter()`（`navigationDestination(for:)` 的 switch）、`withSheetDestinations(sheetDestinations:routerPath:)`（`.sheet(item:)` 的 switch）、`withEnvironments()` 依赖注入。 |
| `IceCubesApp/App/Tabs/NavigationTab.swift` | 每个 Tab 一个 `@State RouterPath`，`NavigationStack(path: $routerPath.path)`，并把 router 注入 environment。 |
| `IceCubesApp/App/Tabs/NavigationSheet.swift` | Sheet 内部再套一个 `NavigationStack` + `CloseToolbarItem`（不在 sheet 上叠 sheet，而是在 sheet 内导航）。 |
| `Packages/DesignSystem/.../CloseToolbarItem.swift` | `@Environment(\.dismiss)` + `xmark.circle`，关闭整个 modal。 |
| `IceCubesApp/App/Router/SafariRouter.swift` | 覆写 `\.openURL`、监听 `onOpenURL`，把链接交给 `RouterPath.handle(url:)` / `handleDeepLink(url:)`。 |
| `Packages/Env/Tests/RouterTests.swift` | 已有的 URL → 路由测试（threads / 本地 status / 远端 status / 随机 URL）。 |

关键设计点：

1. **单一数据源**：`path` 与 `presentedSheet` 都挂在同一个 observable 上，视图只表达意图
   （`router.presentedSheet = .newStatusEditor(...)`），由注册表决定渲染什么。
2. **Sheet 身份（identity）语义**：`SheetDestination` 自定义 `==` / `hash`，只比较 `id`。
   所有编辑器 case 共用 `"statusEditor"`，所以「新建」切「回复」时 sheet 不会先关再开。
   ⚠️ 但**内容也不会刷新**（见 §3.1 的实测结论）：SwiftUI 只在 `id` 变化时重建 sheet 内容。
3. **URL 入口统一**：`openURL` 环境值 + `onOpenURL` 深链都汇聚到一个 `handle(url:)`，
   命中则 push，否则回退给 `urlHandler` 或系统。
4. **router 可多实例**：全局一个（TabView 级 `appRouterPath`），每个 Tab 又各自一个。

## 2. 提取后的组件（RouterKit）

```
SwiftUITestProject/RouterKit/
├── RouterPath.swift          # 协议、URLRouteResolver、@Observable RouterPath
├── RouterHost.swift          # NavigationStack + 路由/sheet 注册表 + 环境注入
├── ModalNavigationStack.swift# sheet 内的 NavigationStack + DismissToolbarItem
└── RouterURLHandling.swift   # URLHandlingResult + .withRouterURLHandling(_:)
```

| IceCubesApp | RouterKit | 说明 |
| --- | --- | --- |
| `RouterDestination` 枚举 | `RouteDestination` 协议 | 由 App 自己定义枚举，组件不感知业务类型 |
| `SheetDestination` 枚举 | `SheetDestination` 协议 | 同上，仍要求 `Identifiable` + 自定义身份相等 |
| `RouterPath` | `RouterPath<Route, Sheet>` | 泛型化，可一个 App 多实例（全局 / 每 Tab / 每 sheet） |
| `handle(url:)` 内联判断 | `URLRouteResolver` 协议 | URL 形状匹配与网络查询解耦，可单测 |
| `withAppRouter()` + `withSheetDestinations()` | `RouterHost` / `.withRouterDestinations(router:route:sheet:)` | 两个 builder 闭包即注册表 |
| `NavigationSheet` + `CloseToolbarItem` | `ModalNavigationStack` + `DismissToolbarItem` | 行为一致（含「不绑定 path」这一限制），另加 `contentSized:` 支持内容自适应高度 |
| — | `RouterHost(title:showsDismissButton:)` | modal 形态：sheet 内**可程序化 push** 的导航栈（原工程没有对应能力） |
| `.presentationDetents([.height(手算), .large])` | `ContentSizedSheet` | 从手算高度改为真测量内容高度 |
| `SafariRouter` 的 openURL/onOpenURL | `.withRouterURLHandling(router)` | 只做路由，不含 App 内 Safari |
| `OpenURLAction.Result` | `URLHandlingResult` | 额外提供 `Equatable`，便于断言 |

保留未实现的部分（按需自行扩展）：visionOS 的 `openWindow` / `WindowDestinationEditor`、
App 内 `SFSafariViewController`、`handleStatus(status:url:)` 这类依赖网络与
Mastodon 客户端的判断。

## 3. IceCubesApp 的关键约束（复刻时必须知道）

对原工程做了全量调用点扫描（详见工作区根目录
`IceCubesApp-navigation-sheets-report.md`），有几条会直接影响 API 设计：

1. **Sheet 身份相等 ⇒ 换 payload 不会刷新内容**：`SheetDestination` 的 `==`/`hash` 只比
   `id`，所以当 sheet 已经打开时，把 `presentedSheet` 换成同 `id` 的另一个 case
   只是修改了 router 里的值，**SwiftUI 不会重建 sheet 内容** —— 实测（`-demo=sheet-sized-resize`）
   把 4 行的 sheet 换成 8 行，6 秒后画面仍是 4 行。IceCubesApp 因此有个 0.3s 延迟重设的
   workaround（`AppAccountsSelectorView.swift` 4 处 `DispatchQueue.main.asyncAfter`）。

   **RouterKit 的推荐做法**：
   * sheet 自己的 UI 状态（行数、模式…）放 `@State`，直接改本地状态即可即时刷新
     （`ContentSizedSheetView` / `ComposerView` 就是这么写的）；
   * 确实需要用新的 payload 重新打开，就 `router.dismissSheet()` 之后再 `present()`，
     必要时延时一帧（复刻 IceCubes 的做法）。
2. **原工程从不写 `presentedSheet = nil`**：关闭一律用 `@Environment(\.dismiss)`
   （28 处真实调用），`NavigationSheet` 的关闭按钮就是 `CloseToolbarItem`。
   RouterKit 两条路都保留：`DismissToolbarItem`（同原实现）+ `router.dismissSheet()`（便于测试与集中控制）。
3. **原工程 sheet 注册表挂在 8 处**（根 TabView + 7 个 Tab），`presentedSheet` 赋值语句
   58 处，另有 14 处零散 `.sheet`。RouterKit 把它们统一成 `RouterHost` /
   `.withRouterDestinations` 一处注册。
4. **每 Tab 一个 RouterPath**，只有 `client.id` 变化时才 `path = []`（7 处），
   对应本组件的 `replacePath(with:)` / `popToRoot()`；push 只有 `navigate(to:)` 一个入口，
   pop 极少（3 处 `removeLast`/`popLast`），对应 `pop()` / `popTo(route:)`。
5. **原 `NavigationSheet` 内部没有 path 绑定**，因此 sheet 里无法 push `RouterDestination`，
   只能 `NavigationLink(destination:)`。RouterKit 两种都提供：`ModalNavigationStack`
   保留原语义；modal 形态的 `RouterHost(title:showsDismissButton:)` 补上「sheet 内可程序化
   push」的缺口（见 §4.4）。

## 4. 用法

### 4.1 定义目的地（照搬 IceCubesApp 的写法）

```swift
enum AppRoute: RouteDestination {
  case statusDetail(id: String)
  case accountDetail(id: String)
}

enum AppSheet: SheetDestination {
  case composer(mode: ComposeMode)   // 多个 case 共用 id = "composer"
  case settings

  static func == (lhs: AppSheet, rhs: AppSheet) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }

  var id: String {
    switch self {
    case .composer: "composer"
    case .settings: "settings"
    }
  }
}
```

### 4.2 安装

```swift
@main struct MyApp: App {
  @State private var router = RouterPath<AppRoute, AppSheet>(
    routeResolver: AppURLRouteResolver(),        // URL -> Route
    urlHandler: { _ in .systemAction })          // 未命中时的兜底

  var body: some Scene {
    WindowGroup {
      RouterHost(router: router) {
        ContentView()                              // 栈根
      } route: { route in
        AppRouteView(route: route)                 // 注册表（原 withAppRouter）
      } sheet: { sheet in
        AppSheetView(sheet: sheet)                 // 注册表（原 withSheetDestinations）
      }
      .withRouterURLHandling(router)               // 原 SafariRouter 的路由部分
    }
  }
}
```

### 4.3 在视图里操作

```swift
struct StatusDetailView: View {
  @Environment(RouterPath<AppRoute, AppSheet>.self) private var router
  let id: String

  var body: some View {
    Button("Reply") { router.present(.composer(mode: .reply(toStatusId: id))) }
    Button("Account") { router.navigate(to: .accountDetail(id: "@dimillian")) }
  }
}
```

### 4.4 Sheet 内的页面 push（原 `NavigationSheet`）

在 sheet 里 push 页面，用的是**同一个 `RouterHost`**，只是加上 modal 形态的
`title` / `showsDismissButton`：

```swift
struct NavigationInSheetView: View {
  // sheet 自己的页面栈；和 App 级 RouterPath<AppRoute, AppSheet> 是两套独立类型
  @State private var sheetRouter = RouterPath<SheetNavRoute, SheetNavSheet>()

  var body: some View {
    RouterHost(router: sheetRouter, title: "In-sheet navigation", showsDismissButton: true) {
      RootView()                       // 栈根
    } route: { route in
      SheetNavRouteView(route: route)  // sheet 内的页面注册表
    } sheet: { sheet in
      SheetNavSheetView(sheet: sheet)  // 还能在 sheet 上再弹小 sheet
    }
  }
}
```

然后任意子页面里照常 `sheetRouter.navigate(to: .page(3))` / `pop()` / `popToRoot()`。
**App 级 router、`RouterHost`、`RouterPath` 的工作方式一点没变** —— sheet 只是又实例化了
一套自己的 router（这正是 `RouterPath` 泛型化 + 多实例的用途），演示里两套 router 的
`path.count` 同屏对照显示，互不影响。

⚠️ **踩坑记录**：一开始用 `ModalNavigationStack` + `.withRouterDestinations`，结果
`path.count == 2` 但画面还停在根页面 —— 因为 `ModalNavigationStack`（= IceCubes 的
`NavigationSheet`）**没有 path 绑定**，只能接 `NavigationLink(value:)`，程序化
`navigate(to:)` 推不动。需要在 sheet 内程序化 push，就用上面 modal 形态的 `RouterHost`。
`.withRouterDestinations` 保留原语义：只注册 destination / sheet，不绑定 path，
而且必须挂在 `NavigationStack` **内部**的视图上（挂在栈外面 SwiftUI 会直接忽略并打印
`Invalid Configuration` 警告）。

顺带修好了 `ComposerView`：它原来也是 `ModalNavigationStack` + `.withRouterDestinations`，
「Preview」按钮点了没反应，现在同样换成 modal 形态的 `RouterHost`。

| sheet 根页面（两套 router 同屏） | 打开时已 push 到第 3 层 |
| --- | --- |
| ![](Screenshots/08-in-sheet-nav-root.png) | ![](Screenshots/09-in-sheet-nav-pushed.png) |

### 4.5 演示 App

`ContentView.swift` 是可视化演示：push / pop / popToRoot、三种 sheet、同一 id 的 sheet
深链 URL 命中与兜底、实时显示 `path` 与 `presentedSheet`。

`DemoLaunchOptions.swift` 支持用启动参数直接驱动到某个状态（便于截图 / 手工冒烟）：

```bash
xcrun simctl launch booted devplaceholder.JC490GPK.SwiftUITestProject -demo=sheet
# -demo=sheet / -demo=sheet-reply / -demo=sheet-settings / -demo=push / -demo=deeplink
# -demo=sheet-sized / -demo=sheet-sized-8 / -demo=sheet-bare / -demo=sheet-native / -demo=sheet-native-list
# -demo=sheet-nav / -demo=sheet-nav-deep（sheet 内 push 演示）
# -demo=sheet-sized-resize / -demo=sheet-sized-autogrow（§4.6 坑 1 的正反例）
```

在 iPhone 17 / iOS 27 模拟器上的实际运行结果：

| 根界面 | push 后 | Sheet（composer） | 同 id 换内容（reply） |
| --- | --- | --- | --- |
| ![](Screenshots/01-root.png) | ![](Screenshots/02-pushed-route.png) | ![](Screenshots/03-sheet-composer.png) | ![](Screenshots/04-sheet-reply.png) |

### 4.6 内容自适应高度的 Sheet

可以，用 `ContentSizedSheet`：真测量内容高度 → `.presentationDetents([.height(测量值), .large])`。

IceCubesApp 的对应实现是**手算**（`AppAccountsSelectorView.swift`）：

```swift
private var preferredHeight: CGFloat {
  var baseHeight: CGFloat = 360
  baseHeight += CGFloat(60 * accountsViewModel.count)   // 靠 Magic Number 估算
  return baseHeight
}
```

`ContentSizedSheet` 不需要估算，内容变了高度自动跟着变：

```swift
// A. 带导航栏：交给 ModalNavigationStack(contentSized:)
ModalNavigationStack(title: "Emoji", contentSized: true) {
  EmojiList()                       // 自动测量 + 补 44pt inline 导航栏
}

// B. 不带导航栏：高度精确等于内容，无需任何补偿
ContentSizedSheet {
  VStack { EmojiList(); Button("Close") { ... } }
}

// C. 已经在导航栈内部时，自己补 chrome
ModalNavigationStack(title: "Emoji") {
  EmojiList().contentSizedSheet(extraHeight: ModalNavigationStack.inlineNavigationBarHeight)
}
```

实测结论（iPhone 17 / iOS 27.0 模拟器，见下表）：

| 方案 | 结果 |
| --- | --- |
| `ContentSizedSheet`（测量 + `.height` detent） | ✅ 高度跟随内容：4 行矮、8 行高，改本地 `@State` 行数即可实时改高度 |
| `.presentationSizing(.fitted)`（iOS 18+ 原生） | ❌ iPhone 上无效：sheet 仍是全高，栈式内容只是被垂直居中 |

必须注意的坑（都是实测踩到的）：

1. **加减行必须改 sheet 自己的 `@State`，不能靠 `router.present(同 id 新 payload)`**。
   同 `id` 的 sheet 内容不会重建（§3.1），点 Add row 会「没反应」：
   实测 `-demo=sheet-sized-resize`（4 行 → 同 id 换 8 行）6 秒后画面仍是 4 行；
   而 `-demo=sheet-sized-autogrow`（走 `@State` 的 `rows += 1`）立刻变成 5 行且 sheet 变高。
2. **不要把整棵 `NavigationStack` 交给 `ContentSizedSheet`**。导航栈是贪婪容器，
   `fixedSize(vertical:)` 会让它塌成**空白 sheet**（截图里 sheet 在、内容没了）。
   正确做法是只测量内容，再用 `extraHeight` 补导航栏（方案 A/C）。
3. **导航栏高度要算进 detent**。只测内容的话，第一行会被 inline 导航栏压住。
4. `List` / `ScrollView` 这类容器没有稳定理想高度，测不到内容高度；
   这类内容要么沿用 IceCubes 的固定高度估算，要么保留 `allowsExpansion`（默认开）
   让用户上拖到 `.large`。

| 4 行（高度=内容） | 8 行（自动变高） | 无导航栏（精确等于内容） |
| --- | --- | --- |
| ![](Screenshots/05-content-sized-4-rows.png) | ![](Screenshots/06-content-sized-8-rows.png) | ![](Screenshots/07-content-sized-bare.png) |

坑 1 的实测对照（同一次运行、同样的初始 4 行）：

| ✅ 点 Add row（`@State`）：变成 5 行、sheet 变高 | ❌ 同 id 换 payload：仍是 4 行 |
| --- | --- |
| ![](Screenshots/10-content-sized-add-row.png) | ![](Screenshots/11-same-id-payload-swap-ignored.png) |

## 5. 测试

* `SwiftUITestProjectTests/RouterPathNavigationTests.swift` — push / pop / popToRoot /
  popTo / replacePath / 多实例隔离。
* `SwiftUITestProjectTests/SheetManagementTests.swift` — present / dismiss /
  同 id 替换 payload 后的 router 状态 / `isPresenting` 身份比较 / `AppSheet` 身份语义
  （注意：这里只断言 router 状态；「内容会不会刷新」由 SwiftUI 决定，见 §3.1）。
* `SwiftUITestProjectTests/URLHandlingTests.swift` — 由 IceCubesApp 的
  `RouterTests.swift` 移植：本地 status、tags、@account、threads 与随机 URL、
  `urlHandler` 兜底、resolver 可替换。
* `SwiftUITestProjectTests/RouterHostViewTests.swift` — 用真实 `UIHostingController`
  渲染 `RouterHost`，验证环境注入、注册表被调用、path/sheet 变更不崩溃。
* `SwiftUITestProjectTests/ContentSizedSheetTests.swift` — 高度收敛（min/max/NaN/未测到）、
  `extraHeight` 补偿、detent 组装、渲染。
* `SwiftUITestProjectTests/InSheetNavigationTests.swift` — sheet 内 router 与 App 级 router
  互相独立、初始 `path`、关 sheet 不影响 App 级栈、sheet 内导航视图可挂载。

测试工程改动：`SwiftUITestProject.xcodeproj` 新增 `SwiftUITestProjectTests`
（`com.apple.product-type.bundle.unit-test`，`TEST_HOST` 指向 App）与共享 scheme
`SwiftUITestProject`（Test action 已挂载测试 bundle）。原工程
`IceCubesApp.xcodeproj` 里没有任何单元测试 target，IceCubesApp 的
`Packages/Env/Tests/RouterTests.swift` 只覆盖了 URL → path 的 4 个用例。

最近一次运行结果（Xcode 27.0 / iPhone 17 / iOS 27.0 模拟器）：

```
✔ Test run with 53 tests in 8 suites passed after 0.241 seconds.
** TEST SUCCEEDED **
```

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd SwiftUITestProject
xcodebuild test \
  -project SwiftUITestProject.xcodeproj \
  -scheme SwiftUITestProject \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .derivedData \
  OTHER_SWIFT_FLAGS="-disable-sandbox"
```

> `OTHER_SWIFT_FLAGS="-disable-sandbox"` 只在受限沙箱环境下才需要：Swift 编译器默认用
> `sandbox-exec` 启动宏插件进程（`@Observable` / `@State` 等），在嵌套沙箱中会报
> `sandbox-exec: sandbox_apply: Operation not permitted`。在 Xcode 里正常构建不需要该参数。

## 6. 迁移到独立 Swift Package

组件只依赖 `SwiftUI` / `Foundation` / `Observation`，所有类型都是 `public`，
目录结构可直接作为 SwiftPM target 使用：

```
RouterKit/
├── Package.swift            // platforms: [.iOS(.v18), .macOS(.v15)]
└── Sources/RouterKit/*.swift
```

App 侧 `import RouterKit` 即可，无需改动 `RouterPath` / `RouterHost` 的调用代码。
