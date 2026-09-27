//
//  AppRegistry.swift
//  RouterKit demo
//
//  The equivalent of IceCubesApp's `AppRegistry.swift`: the single place that
//  maps destinations to views. `withAppRouter()` / `withSheetDestinations()`
//  become these two switch statements.
//

import SwiftUI

struct AppRouteView: View {
  let route: AppRoute

  var body: some View {
    switch route {
    case .number(let value):
      NumberView(value: value)
    case .statusDetail(let id):
      StatusDetailView(id: id)
    case .accountDetail(let id):
      AccountDetailView(id: id)
    case .label(let text):
      LabelView(text: text)
    case .listKitDemo:
      ListKitDemoView()
    }
  }
}

struct AppSheetView: View {
  let sheet: AppSheet

  var body: some View {
    switch sheet {
    case .composer(let mode):
      ComposerView(mode: mode)
    case .settings:
      ModalNavigationStack(title: "Settings") {
        SettingsView()
      }
    case .about:
      ModalNavigationStack(title: "About") {
        AboutView()
      }
    case .counter(let start):
      ModalNavigationStack(title: "Counter") {
          CounterView(start: start)
      }
    case .contentSizedSheet(let rows):
      // 内容自适应：ModalNavigationStack(contentSized:) 会测量内容并补上导航栏高度。
      // 注意不能把整棵 NavigationStack 交给 ContentSizedSheet —— 贪婪容器会被
      // fixedSize 压塌成空白 sheet。
      ModalNavigationStack(title: "Content sized", contentSized: true) {
        ContentSizedSheetView(rows: rows)
      }
    case .bareContentSizedSheet:
      // 不带导航栈：sheet 高度 == 内容高度，不需要任何魔法数字。
      ContentSizedSheet {
        BareSizedSheetView()
      }
    case .nativeFittedSheet:
      ModalNavigationStack(title: "Native fitted") {
        NativeFittedSheetView()
      }
    case .nativeFittedListSheet:
      ModalNavigationStack(title: "Native fitted + List") {
        NativeFittedListSheetView()
      }
    case .navigationInSheet(let initialPath):
      // sheet 内的页面栈由 NavigationInSheetView 自己的 router 负责，
      // App 级 router / RouterHost 不需要任何改动。
      NavigationInSheetView(initialPath: initialPath)
    }
  }
}

struct ComposerRouteView: View {
  let route: ComposerRoute

  var body: some View {
    switch route {
    case .preview(let text):
      ComposerPreviewView(text: text)
    }
  }
}

struct ComposerSheetView: View {
  let sheet: ComposerSheet

  var body: some View {
    switch sheet {
    case .emojiPicker:
      EmojiPickerView()
    }
  }
}

struct SheetNavRouteView: View {
  let route: SheetNavRoute

  var body: some View {
    switch route {
    case .page(let level):
      SheetNavPageView(level: level)
    }
  }
}

struct SheetNavSheetView: View {
  let sheet: SheetNavSheet

  var body: some View {
    switch sheet {
    case .confirm:
      SheetNavConfirmView()
    }
  }
}
