//
//  DemoViews.swift
//  RouterKit demo
//
//  Leaf views referenced by the registries. They show the two ways of reading
//  the router: from the environment (`@Environment(RouterPath<...>.self)`) or
//  from a router owned locally with `@State`.
//

import SwiftUI

// MARK: - Pushed destinations

struct NumberView: View {
  @Environment(RouterPath<AppRoute, AppSheet>.self) private var router

  let value: Int

  var body: some View {
    List {
      Section("Pushed") {
        Text("Number \(value)")
        Text("Stack depth: \(router.depth)")
      }
      Section {
        Button("Push next number") { router.navigate(to: .number(value + 1)) }
        Button("Push to root") { router.popToRoot() }
      }
    }
    .navigationTitle("Number \(value)")
  }
}

struct StatusDetailView: View {
  @Environment(RouterPath<AppRoute, AppSheet>.self) private var router

  let id: String

  var body: some View {
    List {
      Section("Status") {
        Text("id: \(id)")
      }
      Section {
        Button("Reply") { router.present(.composer(mode: .reply(toStatusId: id))) }
        Button("Account @dimillian") { router.navigate(to: .accountDetail(id: "@dimillian")) }
      }
    }
    .navigationTitle("Status \(id)")
  }
}

struct AccountDetailView: View {
  @Environment(RouterPath<AppRoute, AppSheet>.self) private var router

  let id: String

  var body: some View {
    List {
      Section("Account") {
        Text(id)
      }
      Section {
        Button("Open a status of this account") { router.navigate(to: .statusDetail(id: "1010384")) }
      }
    }
    .navigationTitle(id)
  }
}

struct LabelView: View {
  let text: String

  var body: some View {
    List {
      Text(text)
    }
    .navigationTitle(text)
  }
}

// MARK: - Sheet destinations

/// A sheet that owns a *local* router, the RouterKit spelling of IceCubesApp's
/// `NavigationSheet { ... }`: navigation happens inside the modal, and the close
/// button dismisses the whole modal.
struct ComposerView: View {
  @Environment(RouterPath<AppRoute, AppSheet>.self) private var appRouter

  @State private var composerRouter = RouterPath<ComposerRoute, ComposerSheet>()
  @State private var text = "Hello RouterKit"
  /// 和行数同理：`mode` 是 sheet 的本地状态。用
  /// `appRouter.present(.composer(mode: .reply(...)))` 换同 id 的 payload 刷不动内容。
  @State private var mode: ComposeMode

  init(mode: ComposeMode) {
    _mode = State(initialValue: mode)
  }

  var body: some View {
    // 用 modal 形态的 RouterHost 而不是 ModalNavigationStack：
    // 只有绑定 path 的导航栈才能被 `composerRouter.navigate(to:)` 程序化 push。
    RouterHost(router: composerRouter, title: "Composer", showsDismissButton: true) {
      Form {
        Section("Mode") {
          Text(describe(mode))
        }
        Section("Text") {
          TextField("What's up?", text: $text)
        }
        Section {
          Button("Preview") { composerRouter.navigate(to: .preview(text: text)) }
          Button("Emoji picker") { composerRouter.present(.emojiPicker) }
          Button("Switch to reply mode (local state)") {
            withAnimation(.snappy) { mode = .reply(toStatusId: "1010384") }
          }
          Button("Close") { appRouter.dismissSheet() }
        }
      }
    } route: { route in
      ComposerRouteView(route: route)
    } sheet: { sheet in
      ComposerSheetView(sheet: sheet)
    }
  }

  private func describe(_ mode: ComposeMode) -> String {
    switch mode {
    case .new: "new status"
    case .reply(let id): "reply to \(id)"
    }
  }
}

struct ComposerPreviewView: View {
  @Environment(RouterPath<ComposerRoute, ComposerSheet>.self) private var composerRouter

  let text: String

  var body: some View {
    List {
      Text(text)
      Button("Emoji picker") { composerRouter.present(.emojiPicker) }
    }
    .navigationTitle("Preview")
  }
}

struct EmojiPickerView: View {
  @Environment(RouterPath<ComposerRoute, ComposerSheet>.self) private var composerRouter

  private let emojis = ["🚀", "🧊", "🐘", "🎉", "🍕", "📦"]

  var body: some View {
    ModalNavigationStack(title: "Emoji") {
      List(emojis, id: \.self) { emoji in
        Button(emoji) { composerRouter.dismissSheet() }
      }
    }
  }
}

struct SettingsView: View {
  @Environment(RouterPath<AppRoute, AppSheet>.self) private var router

  var body: some View {
    List {
      Section {
        Button("Push a number from the modal") { router.navigate(to: .number(7)) }
        Button("Open About") { router.present(.about) }
      }
    }
    .navigationTitle("Settings")
  }
}

struct AboutView: View {
  var body: some View {
    List {
      Label("RouterKit", systemImage: "arrow.triangle.branch")
      Text("Extracted from IceCubesApp's RouterPath, withSheetDestinations and NavigationSheet.")
    }
    .navigationTitle("About")
  }
}

struct CounterView: View {
  @Environment(RouterPath<AppRoute, AppSheet>.self) private var router

  @State private var count: Int

  init(start: Int) {
    _count = State(initialValue: start)
  }

  var body: some View {
    List {
      Section {
        Text("Count: \(count)")
        Button("Increment") { count += 1 }
      }
      Section {
        Button("Dismiss") { router.dismissSheet() }
      }
    }
    .navigationTitle("Counter")
  }
}

// MARK: - 内容自适应高度

/// 真测量版：行数存在 sheet 自己的 `@State` 里，加减行 → 内容高度变 → detent 跟着变。
///
/// ⚠️ 这里**不能**用 `router.present(.contentSizedSheet(rows: rows + 1))` 来改行数：
/// 同一个 `id` 的 sheet 在 SwiftUI 里不会重建内容，换了 payload 也刷不动，
/// 表现就是「点 Add row 没反应」（见 RouterKit.md §3.1）。
/// 行数是这个 sheet 的本地 UI 状态，放在 `@State` 里既正确又即时。
///
/// `ContentSizedSheet` 由 `ModalNavigationStack(contentSized:)` 挂在导航栈内部，
/// 导航栏高度因此也算进 detent，否则第一行会被导航栏压住。
struct ContentSizedSheetView: View {
  @State private var rows: Int

  init(rows: Int) {
    _rows = State(initialValue: rows)
  }

  var body: some View {
    VStack(spacing: 0) {
        ScrollView{
            VStack{
                ForEach(1...rows, id: \.self) { index in
                    HStack {
                        Text("Row \(index)")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    
                    Divider().padding(.leading, 20)
                }
            }
        }.frame(maxHeight: 400)

      HStack {
        Button("Add row") { withAnimation(.snappy) { rows += 1 } }
        Spacer()
        Button("Remove row") { withAnimation(.snappy) { rows = max(1, rows - 1) } }
      }
      .padding(20)
      .padding(.bottom, 8)
    }
    .background(.white)
    // 截图 / 冒烟用：走的是和上面 Add row 按钮完全相同的 `@State` 路径。
    .task {
        #if DEBUG
      guard let delay = DemoLaunchOptions.autoAddRowDelay else { return }
      DemoLaunchOptions.autoAddRowDelay = nil
      try? await Task.sleep(for: delay)
      withAnimation(.snappy) { rows += 1 }
        #endif
    }
  }
}

/// 不带导航栈的内容自适应 sheet：高度精确等于内容，自带关闭行。
struct BareSizedSheetView: View {
  @Environment(RouterPath<AppRoute, AppSheet>.self) private var router

  var body: some View {
    VStack(spacing: 0) {
      Text("Content sized, no navigation bar")
        .font(.headline)
        .padding(.top, 24)
        .padding(.bottom, 12)

      ForEach(1...3, id: \.self) { index in
        HStack {
          Text("Row \(index)")
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        Divider().padding(.leading, 20)
      }

      Button("Close") { router.dismissSheet() }
        .padding(20)
        .padding(.bottom, 8)
    }.background(.white)
  }
}

/// iOS 18+ 原生方案：`.presentationSizing(.fitted)`，栈式内容。
struct NativeFittedSheetView: View {
  var body: some View {
    VStack(spacing: 0) {
      ForEach(1...4, id: \.self) { index in
        HStack {
          Text("Row \(index)")
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        Divider().padding(.leading, 20)
      }
    }
    .presentationSizing(.fitted)
  }
}

/// 对照实验：`.fitted` 遇到 List 这类贪婪容器会怎样。
struct NativeFittedListSheetView: View {
  var body: some View {
    List(1...4, id: \.self) { index in
      Text("Row \(index)")
    }
    .presentationSizing(.fitted)
  }
}

// MARK: - sheet 内的页面 push

/// 演示：在 sheet 里 push 页面。
///
/// **App 级 router 的工作方式没有任何改动**：
/// * sheet 自己持有一个 `RouterPath<SheetNavRoute, SheetNavSheet>`（`@State`）；
/// * `RouterHost`（modal 形态）提供 sheet 自己的、**绑定 path** 的 `NavigationStack`，
///   并同时充当「sheet 内路由 → sheet 内页面」的注册表。
///
/// 为什么不能直接拿 App 级 router 在 sheet 里 push：sheet 是独立呈现的，不在 App 级
/// `NavigationStack` 的 destination 作用域内，push 进去也没有页面接住。
struct NavigationInSheetView: View {
  @State private var sheetRouter: RouterPath<SheetNavRoute, SheetNavSheet>

  init(initialPath: [SheetNavRoute] = []) {
    _sheetRouter = State(initialValue: RouterPath(path: initialPath))
  }

  var body: some View {
    RouterHost(router: sheetRouter, title: "In-sheet navigation", showsDismissButton: true) {
      SheetNavRootView()
    } route: { route in
      SheetNavRouteView(route: route)
    } sheet: { sheet in
      SheetNavSheetView(sheet: sheet)
    }
  }
}

/// sheet 内导航栈的根页面。
struct SheetNavRootView: View {
  @Environment(RouterPath<SheetNavRoute, SheetNavSheet>.self) private var sheetRouter
  @Environment(RouterPath<AppRoute, AppSheet>.self) private var appRouter

  var body: some View {
    List {
      Section("在 sheet 内 push") {
        Button("Push page 2") { sheetRouter.navigate(to: .page(2)) }
        Button("一次 push page 2 → 3") { sheetRouter.navigate(to: [.page(2), .page(3)]) }
      }

      Section("两套 router 并存且互不影响") {
        LabeledContent("sheet 内 path.count", value: "\(sheetRouter.depth)")
        LabeledContent("App 级 path.count", value: "\(appRouter.depth)")
        Text("sheet 用的是 RouterPath<SheetNavRoute, SheetNavSheet>，App 级 RouterHost 一行都没改。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// 被 push 的页面：每一层都能继续 push / pop，并显示各自所在栈的深度。
struct SheetNavPageView: View {
  @Environment(RouterPath<SheetNavRoute, SheetNavSheet>.self) private var sheetRouter
  @Environment(RouterPath<AppRoute, AppSheet>.self) private var appRouter

  let level: Int

  var body: some View {
    List {
      Section("Page \(level)") {
        Text("这是 sheet 内导航栈的第 \(sheetRouter.depth) 层")
        LabeledContent("App 级 path.count", value: "\(appRouter.depth)")
      }

      Section("继续在 sheet 内导航") {
        Button("Push page \(level + 1)") { sheetRouter.navigate(to: .page(level + 1)) }
        Button("Pop") { sheetRouter.pop() }
        Button("Pop to root") { sheetRouter.popToRoot() }
        Button("在 sheet 上再弹一个小 sheet") { sheetRouter.present(.confirm) }
      }

      Section("跨 router 协作") {
        Button("关掉 sheet 并 push App 级 status 页面") {
          appRouter.navigate(to: .statusDetail(id: "1010384"))
          appRouter.dismissSheet()
        }
      }
    }
    .navigationTitle("Page \(level)")
  }
}

/// 由 sheet 内那套 router 弹出的 sheet。
struct SheetNavConfirmView: View {
  @Environment(RouterPath<SheetNavRoute, SheetNavSheet>.self) private var sheetRouter

  var body: some View {
    ModalNavigationStack(title: "Confirm") {
      List {
        Text("这个 sheet 由 sheet 内那套 router 弹出，App 级 router 依然没参与。")
        Button("完成") { sheetRouter.dismissSheet() }
      }
    }
  }
}
